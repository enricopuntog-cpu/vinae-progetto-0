// Controlli sulla sessione cloud (WI-001C). Come `role-check.mjs`, ricevono una funzione
// `query(text, params) → { rows }`: provabili con un database finto, indipendenti da Bun.

const MIN_SERVER_VERSION_NUM = 150000;

/**
 * Controlli di sessione PRIMA di qualunque operazione di import:
 *  - connessione cifrata (pg_stat_ssl) e server non in recovery;
 *  - versione PostgreSQL almeno 15;
 *  - l'utente di connessione non è superuser (un superuser potrebbe uscire dal ruolo con RESET ROLE);
 *  - lo schema `catalog` della migration WI-001B è presente e completo (funzioni del protocollo, staging UNLOGGED).
 * Restituisce un riepilogo senza segreti; lancia al primo controllo fallito.
 */
export async function assertCloudSession(query) {
  const r = await query(
    `select current_setting('server_version_num')::int as version_num,
            current_setting('server_version') as version,
            current_database()::text as db,
            session_user::text as session_user,
            (select rolsuper from pg_roles where rolname = session_user) as session_superuser,
            (select rolbypassrls or rolcreaterole or rolcreatedb or rolreplication from pg_roles where rolname = session_user) as session_powers,
            coalesce((select nspowner = (select oid from pg_roles where rolname = session_user) from pg_namespace where nspname = 'catalog'), false) as session_owns_catalog,
            coalesce((select pg_has_role(session_user, r.oid, 'member') from pg_roles r where r.rolname = 'catalog_curator'), false) as session_curator,
            pg_is_in_recovery() as in_recovery,
            coalesce((select ssl from pg_stat_ssl where pid = pg_backend_pid()), false) as ssl,
            to_regprocedure('catalog.finish_import_run(uuid,bigint,jsonb)') is not null as has_finish,
            to_regprocedure('catalog.begin_import_run(text,text,text,integer,text,boolean,interval,boolean)') is not null as has_begin,
            to_regprocedure('catalog.stage_source_records(uuid,jsonb)') is not null as has_stage,
            coalesce((select relpersistence = 'u' from pg_class where oid = to_regclass('catalog.import_stage')), false) as stage_unlogged`,
  );
  const row = r.rows[0];
  if (!row) throw new Error('Controllo di sessione: nessuna risposta dal database.');
  const fail = (why) => { throw new Error(`Controllo di sessione cloud fallito (${why}): importazione rifiutata.`); };
  if (!row.ssl) fail('la connessione non è cifrata');
  if (row.in_recovery) fail('il server è in recovery (replica di sola lettura)');
  if (Number(row.version_num) < MIN_SERVER_VERSION_NUM) fail(`PostgreSQL ${row.version} < 15`);
  if (row.session_superuser) fail('l\x27utente di connessione è superuser');
  // il login deve essere dedicato (runbook): con poteri propri potrebbe uscire dal ruolo con RESET ROLE
  if (row.session_powers) fail('l\x27utente di connessione ha BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION: serve un login dedicato');
  if (row.session_owns_catalog) fail('l\x27utente di connessione è proprietario dello schema catalog: serve un login dedicato');
  if (row.session_curator) fail('l\x27utente di connessione è membro di catalog_curator');
  if (!row.has_begin || !row.has_stage || !row.has_finish) fail('la migration WI-001B non risulta applicata');
  if (!row.stage_unlogged) fail('import_stage non è UNLOGGED');
  // I-2: grafo TRANSITIVO delle appartenenze e privilegi effettivi del login (non solo i flag del ruolo)
  const audit = parseAudit((await query(LOGIN_AUDIT_SQL, [row.session_user])).rows[0]?.audit);
  const violations = evaluateLoginAudit(audit, { loader: 'catalog_loader' });
  if (violations.length > 0) fail(`login non dedicato: ${violations.join('; ')}`);
  return { server_version: row.version, database: row.db, session_user: row.session_user, ssl: true, login_audit: 'conforme' };
}

/**
 * Audit del LOGIN di connessione (WI-001C-FIX-01 / I-2). Un solo parametro: il nome del login (`session_user`). SOLA LETTURA del
 * catalogo di sistema; lo stesso testo è eseguito dalla griglia SQL 12zz su ruoli reali (grafo di appartenenze, grant, proprietà).
 * Il login deve raggiungere, direttamente o per via transitiva (a prescindere dal flag INHERIT: `SET ROLE` basta), SOLO `catalog_loader`.
 */
export const LOGIN_AUDIT_SQL = `with recursive me as (
  select oid, rolname, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, rolreplication, rolcanlogin from pg_roles where rolname = $1::name
), reach(roleid, admin, depth) as (
  select m.roleid, m.admin_option, 1 from pg_auth_members m join me on m.member = me.oid
  union
  select m.roleid, m.admin_option or r.admin, r.depth + 1 from reach r join pg_auth_members m on m.member = r.roleid where r.depth < 20
)
select jsonb_build_object(
  'login_found', exists (select 1 from me),
  'login_can_login', coalesce((select rolcanlogin from me), false),
  'login_powers', coalesce((select rolsuper or rolbypassrls or rolcreaterole or rolcreatedb or rolreplication from me), false),
  'reachable', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid), '[]'::jsonb),
  'powerful', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid
                         where x.rolsuper or x.rolbypassrls or x.rolcreaterole or x.rolcreatedb or x.rolreplication), '[]'::jsonb),
  'admin_over', coalesce((select jsonb_agg(distinct x.rolname order by x.rolname) from reach r join pg_roles x on x.oid = r.roleid where r.admin), '[]'::jsonb),
  'direct_grants',
    (select count(*) from pg_class c cross join lateral aclexplode(c.relacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_proc p cross join lateral aclexplode(p.proacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_namespace n cross join lateral aclexplode(n.nspacl) a, me where a.grantee = me.oid)
  + (select count(*) from pg_attribute t cross join lateral aclexplode(t.attacl) a, me where t.attacl is not null and a.grantee = me.oid)
  + (select count(*) from pg_database d cross join lateral aclexplode(d.datacl) a, me where a.grantee = me.oid and a.privilege_type <> 'CONNECT'),
  'owned_objects',
    (select count(*) from pg_class c, me where c.relowner = me.oid)
  + (select count(*) from pg_proc p, me where p.proowner = me.oid)
  + (select count(*) from pg_namespace n, me where n.nspowner = me.oid)
  + (select count(*) from pg_database d, me where d.datdba = me.oid),
  'db_create', coalesce(case when exists (select 1 from me) then has_database_privilege($1::name, current_database(), 'CREATE') end, false),
  'public_create', coalesce(case when exists (select 1 from me) then has_schema_privilege($1::name, 'public', 'CREATE') end, false),
  'catalog_create', coalesce(case when exists (select 1 from me) then has_schema_privilege($1::name, 'catalog', 'CREATE') end, false)
) as audit`;

function parseAudit(raw) {
  if (raw === undefined || raw === null) throw new Error('Controllo del login: nessuna risposta dal database.');
  return typeof raw === 'string' ? JSON.parse(raw) : raw;
}

/**
 * Valuta l'esito di LOGIN_AUDIT_SQL. Restituisce l'elenco (vuoto = conforme) dei motivi per cui il login NON è dedicato al caricatore.
 */
export function evaluateLoginAudit(audit, { loader = 'catalog_loader' } = {}) {
  const v = [];
  if (!audit || audit.login_found !== true) return ['login non trovato nel catalogo dei ruoli'];
  const list = (x) => (Array.isArray(x) ? x : []);
  const reachable = list(audit.reachable);
  const extra = reachable.filter((r) => r !== loader);
  if (extra.length > 0) v.push(`ruoli raggiungibili oltre a ${loader}: ${extra.slice(0, 8).join(', ')}`);
  if (!reachable.includes(loader)) v.push(`${loader} non è raggiungibile dal login`);
  if (audit.login_powers) v.push('il login ha SUPERUSER/BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION');
  if (list(audit.powerful).length > 0) v.push(`ruoli con poteri amministrativi raggiungibili: ${list(audit.powerful).slice(0, 8).join(', ')}`);
  if (list(audit.admin_over).length > 0) v.push(`il login può amministrare appartenenze (ADMIN OPTION): ${list(audit.admin_over).slice(0, 8).join(', ')}`);
  if (Number(audit.direct_grants) > 0) v.push(`${audit.direct_grants} privilegi concessi direttamente al login (oltre a CONNECT)`);
  if (Number(audit.owned_objects) > 0) v.push(`il login possiede ${audit.owned_objects} oggetti`);
  if (audit.db_create) v.push('il login può creare schemi nel database');
  if (audit.public_create) v.push('il login può creare oggetti in public');
  if (audit.catalog_create) v.push('il login può creare oggetti in catalog');
  return v;
}

/**
 * Matrice dei privilegi del ruolo caricatore (sola lettura del catalogo di sistema). Il caricatore deve poter
 * scrivere lo staging e NON deve poter cancellare i record di fonte, fare TRUNCATE, toccare lo schema canonico
 * né essere membro del curatore. Restituisce la matrice; lancia sul primo scostamento.
 */
export async function assertLoaderPrivileges(query, role = 'catalog_loader') {
  const r = await query(
    `select has_table_privilege($1, 'catalog.source_records', 'INSERT') as sr_insert,
            has_table_privilege($1, 'catalog.source_records', 'UPDATE') as sr_update,
            has_table_privilege($1, 'catalog.source_records', 'DELETE') as sr_delete,
            has_table_privilege($1, 'catalog.source_records', 'TRUNCATE') as sr_truncate,
            has_table_privilege($1, 'catalog.import_stage', 'INSERT') as stage_insert,
            has_table_privilege($1, 'catalog.sources', 'INSERT') as sources_insert,
            has_table_privilege($1, 'catalog.sources', 'UPDATE') as sources_update,
            coalesce(has_table_privilege($1, to_regclass('catalog.wines'), 'SELECT'), false) as canonical_select,
            coalesce(has_table_privilege($1, to_regclass('catalog.wines'), 'INSERT'), false) as canonical_insert,
            coalesce((select pg_has_role($1, r.oid, 'member') from pg_roles r where r.rolname = 'catalog_curator'), false) as curator_member,
            has_schema_privilege($1, 'public', 'CREATE') as public_create,
            has_function_privilege($1, 'catalog.finish_import_run(uuid,bigint,jsonb)', 'EXECUTE') as can_finish`,
    [role],
  );
  const m = r.rows[0];
  if (!m) throw new Error('Controllo dei privilegi: nessuna risposta dal database.');
  const fail = (why) => { throw new Error(`Privilegi del ruolo ${role} non conformi (${why}): importazione rifiutata.`); };
  if (m.sr_delete) fail('DELETE su source_records');
  if (m.sr_truncate) fail('TRUNCATE su source_records');
  if (m.sources_insert || m.sources_update) fail('scrittura sul registro delle fonti');
  if (m.canonical_select || m.canonical_insert) fail('accesso alle tabelle canoniche');
  if (m.curator_member) fail('membro di catalog_curator');
  if (m.public_create) fail('CREATE sullo schema public');
  if (!m.sr_insert || !m.sr_update || !m.stage_insert || !m.can_finish) fail('privilegi di import mancanti');
  return m;
}

const LSN_RE = /^[0-9A-F]{1,8}\/[0-9A-F]{1,8}$/i;

/**
 * Controllo del WAL generato dall'import. Fail-closed: se la posizione WAL non è leggibile l'import non parte.
 * `check()` lancia quando il WAL prodotto dall'inizio supera il budget (include l'attività di altri client: è un
 * limite superiore prudente). `report()` restituisce l'esito per il report strutturato.
 */
export async function createWalGuard(query, { maxWalMb }) {
  if (!Number.isInteger(maxWalMb) || maxWalMb < 1) throw new Error('Budget WAL non valido.');
  let start;
  try {
    const r = await query('select pg_current_wal_lsn()::text as lsn');
    start = r.rows[0]?.lsn;
  } catch {
    throw new Error('Controllo WAL non disponibile (pg_current_wal_lsn non leggibile): importazione rifiutata (fail-closed).');
  }
  if (!start || !LSN_RE.test(start)) throw new Error('Controllo WAL: posizione non valida.');
  let last = 0;
  const measure = async () => {
    const r = await query('select pg_wal_lsn_diff(pg_current_wal_lsn(), $1::pg_lsn)::bigint as bytes', [start]);
    last = Number(r.rows[0]?.bytes ?? 0);
    return last;
  };
  return {
    start,
    async check() {
      const bytes = await measure();
      if (bytes > maxWalMb * 1048576) {
        throw new Error(`Budget WAL superato (${Math.round(bytes / 1048576)} MB > ${maxWalMb} MB): import interrotto.`);
      }
      return bytes;
    },
    async report() {
      try { await measure(); } catch { /* ultimo valore noto */ }
      return { start_lsn: start, wal_mb: Math.round(last / 1048576), budget_mb: maxWalMb };
    },
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// WAL durante il finish (WI-001C-FIX-01 / I-3)
//
// COSA È GARANTITO:
//  - un controllo PREVENTIVO prima del finish: se il WAL già prodotto più la stima prudente del finish supera il budget, il finish
//    NON parte (stima = costante per riga scritta, derivata dalla misura sintetica WI-001B di ≈1 GB per 212.894 record, con margine);
//  - un monitor SEPARATO (seconda connessione) che, mentre il finish gira, misura il WAL ogni `intervalMs` e, se il budget è
//    superato, chiama `pg_cancel_backend` sul backend dell'import: il finish è UNA transazione, quindi l'annullamento ne fa il
//    rollback completo (nessun dato parziale visibile); se il monitor perde la visibilità (errori ripetuti) annulla comunque (fail-closed);
//  - `statement_timeout` dedicato al finish (--finish-timeout-min) come limite di tempo indipendente dal monitor.
// COSA NON È GARANTITO:
//  - NON è un limite rigido: tra due campioni (`intervalMs`) il WAL può crescere oltre il budget, e il rollback NON restituisce il WAL
//    già scritto (resta nel log/archivio e nei costi); il picco è «budget + velocità × (intervallo + latenza di annullamento)»;
//  - la stima preventiva è euristica (file reale mai misurato); la misura include anche il WAL di altri client (limite prudente);
//  - se il monitor E la connessione principale cadono, resta solo `statement_timeout`; un crash del server è fuori da questo controllo.
// ---------------------------------------------------------------------------------------------------------------------
export const FINISH_WAL_BYTES_PER_ROW = 8192;
export const FINISH_WAL_BASE_BYTES = 64 * 1048576;

/** Stima prudente del WAL del finish e decisione: `ok` solo se WAL già usato + stima ≤ budget. Non è un limite rigido. */
export function planFinishWal({ usedBytes, budgetBytes, writtenRows }) {
  const used = Number(usedBytes);
  const budget = Number(budgetBytes);
  const rows = Number(writtenRows);
  if (![used, budget, rows].every(Number.isFinite) || used < 0 || budget <= 0 || rows < 0) throw new Error('Stima WAL del finish: valori non validi.');
  const projected = FINISH_WAL_BASE_BYTES + rows * FINISH_WAL_BYTES_PER_ROW;
  return { ok: used + projected <= budget, usedBytes: used, projectedFinishBytes: projected, budgetBytes: budget };
}

/**
 * Monitor del WAL del finish su una SECONDA connessione. `query` è quella del monitor (login, nessun SET ROLE: vedi db-bun.mjs);
 * `backendPid` è il backend da annullare. Timer iniettabili per i test.
 */
export function createWalMonitor({
  query, backendPid, startLsn, maxWalMb, intervalMs = 2000, failuresBeforeCancel = 2, reopen = null,
  setTimer = setInterval, clearTimer = clearInterval,
}) {
  if (!Number.isInteger(backendPid) || backendPid < 1) throw new Error('Monitor WAL: pid del backend non valido.');
  if (!startLsn || !LSN_RE.test(startLsn)) throw new Error('Monitor WAL: posizione iniziale non valida.');
  if (!Number.isInteger(maxWalMb) || maxWalMb < 1) throw new Error('Monitor WAL: budget non valido.');
  const budgetBytes = maxWalMb * 1048576;
  const state = { samples: 0, peakBytes: 0, failures: 0, exceeded: false, cancelRequested: false, cancelOk: null, cancelAttempts: 0, lost: false, running: false };
  let activeQuery = query;
  let stopped = false;
  let timer = null;
  let busy = false;

  // L'annullamento NON si considera fatto finché non riesce: se la connessione del monitor è rotta si tenta di riaprirne una nuova
  // (`reopen`), e a ogni campione successivo si riprova. Esito finale in `cancelOk`; `lost` = nessuna via per annullare.
  const cancel = async (reason) => {
    // dopo stop() (finish terminato) nessun annullamento tardivo: colpirebbe la verifica o fail_import_run sullo stesso backend
    if (state.cancelOk === true || stopped) return;
    state.cancelReason ??= reason;
    state.cancelAttempts += 1;
    const attempt = async (q) => {
      const r = await q('select pg_cancel_backend($1::int) as ok', [backendPid]);
      return r.rows[0]?.ok === true;
    };
    try {
      state.cancelOk = await attempt(activeQuery);
      state.cancelRequested = true;
      return;
    } catch {
      state.cancelOk = false;
    }
    if (typeof reopen === 'function') {
      try {
        activeQuery = await reopen();
        state.cancelOk = await attempt(activeQuery);
        state.cancelRequested = true;
        return;
      } catch {
        state.cancelOk = false;
      }
    }
    state.lost = true;
  };
  const sample = async () => {
    if (busy || state.cancelOk === true) return;
    busy = true;
    if (state.exceeded || state.lost || state.cancelAttempts > 0) {
      // un annullamento già deciso ma non riuscito: si ritenta
      try { await cancel(state.cancelReason); } finally { busy = false; }
      return;
    }
    try {
      const r = await activeQuery('select pg_wal_lsn_diff(pg_current_wal_lsn(), $1::pg_lsn)::bigint as bytes', [startLsn]);
      const bytes = Number(r.rows[0]?.bytes);
      if (!Number.isFinite(bytes)) throw new Error('lettura WAL non numerica');
      state.samples += 1;
      state.failures = 0;
      state.peakBytes = Math.max(state.peakBytes, bytes);
      if (bytes > budgetBytes) {
        state.exceeded = true;
        await cancel('budget WAL superato');
      }
    } catch {
      state.failures += 1;
      // fail-closed: senza visibilità sul WAL il finish non prosegue
      if (state.failures >= failuresBeforeCancel) await cancel('monitor WAL senza visibilità');
    } finally {
      busy = false;
    }
  };
  return {
    sample,
    start() {
      if (timer) return;
      state.running = true;
      timer = setTimer(() => { void sample(); }, intervalMs);
      if (timer && typeof timer.unref === 'function') timer.unref();
    },
    stop() {
      stopped = true;
      if (timer) clearTimer(timer);
      timer = null;
      state.running = false;
      return { ...state, peak_mb: Math.round(state.peakBytes / 1048576), budget_mb: maxWalMb, interval_ms: intervalMs };
    },
    status: () => ({ ...state, peak_mb: Math.round(state.peakBytes / 1048576), budget_mb: maxWalMb }),
  };
}

/** Imposta i limiti della sessione (set_config non ha bisogno di privilegi speciali). */
export async function applySessionLimits(query, { statementTimeoutMs, lockTimeoutMs, idleTxTimeoutMs }) {
  await query(
    `select set_config('statement_timeout', $1, false), set_config('lock_timeout', $2, false),
            set_config('idle_in_transaction_session_timeout', $3, false)`,
    [String(statementTimeoutMs), String(lockTimeoutMs), String(idleTxTimeoutMs)],
  );
}

/**
 * Verifica dopo `finish_import_run` (procedura documentata in docs/wine-intelligence/CLOUD_IMPORT_RUNBOOK.md):
 * il tentativo è `succeeded`, lo snapshot è quello atteso, nessun altro tentativo è in corso, lo staging è
 * stato svuotato, i conteggi coincidono con i record attivi, l'impronta dello stato è quella dichiarata e ogni record
 * con paese ha un territorio. Non lancia: restituisce l'elenco dei controlli, `ok` solo se tutti superati.
 */
export async function verifyFinish(query, { runId, sourceCode, expectedSha256 }) {
  const checks = [];
  const add = (id, ok, detail = '') => checks.push({ id, ok: ok === true, detail: String(detail).slice(0, 300) });
  const run = (await query(
    `select r.status, r.finished_at is not null as finished, r.counts, s.id as source_id, sn.file_sha256,
            extract(epoch from (r.finished_at - r.started_at))::int as seconds
       from catalog.import_runs r
       join catalog.sources s on s.id = r.source_id
       join catalog.import_snapshots sn on sn.id = r.snapshot_id
      where r.id = $1::uuid and s.code = $2`,
    [runId, sourceCode],
  )).rows[0];
  add('V01_run_succeeded', run?.status === 'succeeded' && run?.finished, run?.status ?? 'tentativo non trovato');
  if (!run) return { ok: false, checks };
  const counts = typeof run.counts === 'string' ? JSON.parse(run.counts) : run.counts ?? {};
  add('V02_snapshot_sha256', !expectedSha256 || run.file_sha256 === expectedSha256, run.file_sha256);
  const q = async (text, params) => (await query(text, params)).rows[0];
  const running = await q(`select count(*)::int as n from catalog.import_runs where source_id = $1::uuid and status = 'running'`, [run.source_id]);
  add('V03_no_running_attempt', running.n === 0, `running=${running.n}`);
  const stage = await q('select count(*)::int as n from catalog.import_stage where run_id = $1::uuid', [runId]);
  add('V04_stage_emptied', stage.n === 0, `stage=${stage.n}`);
  const active = await q('select count(*)::int as n from catalog.source_records where source_id = $1::uuid and removed_from_source_at is null', [run.source_id]);
  add('V05_active_equals_seen', Number(counts.records_seen) === active.n, `seen=${counts.records_seen} active=${active.n}`);
  const digest = await q('select catalog.state_digest($1::uuid) as d', [run.source_id]);
  add('V06_state_digest', counts.state_digest && counts.state_digest === digest.d, 'impronta dello stato');
  const unlinked = await q(
    'select count(*)::int as n from catalog.source_records where source_id = $1::uuid and removed_from_source_at is null and country is not null and territory_id is null',
    [run.source_id],
  );
  add('V07_territories_linked', unlinked.n === 0, `senza territorio=${unlinked.n}`);
  const removed = await q('select count(*)::int as n from catalog.source_records where removed_in_run = $1::uuid', [runId]);
  add('V08_removals_marked_only', Number(counts.removed_from_source ?? 0) === removed.n, `dichiarati=${counts.removed_from_source ?? 0} marcati=${removed.n}`);
  add('V09_duration_recorded', Number.isFinite(run.seconds), `finish incluso: ${run.seconds}s`);
  return { ok: checks.every((c) => c.ok), checks, duration_seconds: run.seconds, counts_summary: { records_seen: counts.records_seen, new: counts.new, updated: counts.updated, unchanged: counts.unchanged, removed_from_source: counts.removed_from_source } };
}
