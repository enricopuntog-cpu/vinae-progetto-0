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
 *
 * Cifratura (WI-001C, sblocco Supavisor). `pg_stat_ssl` descrive la connessione vista dal BACKEND PostgreSQL. Dietro il pooler
 * condiviso (Supavisor, sessione) quel backend è raggiunto da Supavisor, non dal client: `ssl` riguarda il tratto
 * Supavisor → PostgreSQL, che dipende dall'impostazione «SSL enforcement» del progetto, NON il tratto client → Supavisor.
 *  - `kind: 'direct'`: il backend vede il client; `pg_stat_ssl.ssl` DEVE essere true (controllo invariato).
 *  - `kind: 'pooler'`: il tratto client → pooler è protetto dal TLS del driver (verify-full + CA + hostname, `rejectUnauthorized`),
 *    che il chiamante attesta con `clientTlsVerified: true` (impostato da db-bun SOLO dopo una connessione riuscita con quelle
 *    opzioni); senza attestazione l'import è rifiutato. L'identità è controllata dal login effettivo (`expectedLogin`, il ruolo
 *    della URL `<ruolo>.<ref>`: il ref seleziona il tenant Supavisor). Il tratto Supavisor → PostgreSQL è riportato come
 *    `encrypted` SOLO se `pg_stat_ssl.ssl` è true; altrimenti `not_proven` (mai dichiarato cifrato senza prova).
 * Un `kind` sconosciuto è rifiutato (fail-closed).
 */
export async function assertCloudSession(query, { kind = 'direct', clientTlsVerified = false, expectedLogin = null } = {}) {
  if (kind !== 'direct' && kind !== 'pooler') throw new Error('Controllo di sessione cloud fallito (tipo di connessione sconosciuto): importazione rifiutata.');
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
  if (kind === 'direct') {
    if (row.ssl !== true) fail('la connessione non è cifrata');
  } else {
    if (clientTlsVerified !== true) fail('TLS verificato client → pooler non attestato');
    if (typeof expectedLogin !== 'string' || expectedLogin === '' || row.session_user !== expectedLogin) fail('il login effettivo non corrisponde a quello della URL');
  }
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
  const backendSsl = row.ssl === true;
  const transport = kind === 'direct'
    ? { kind, client_to_server: 'tls_verify_full_pg_stat_ssl' }
    : { kind, client_to_pooler: 'tls_verify_full_driver', pooler_to_postgres: backendSsl ? 'encrypted_pg_stat_ssl' : 'not_proven' };
  return { server_version: row.version, database: row.db, session_user: row.session_user, ...(kind === 'direct' ? { ssl: true } : { backend_ssl: backendSsl }), transport, login_audit: 'conforme' };
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
      try { await measure(); } catch { return { start_lsn: start, wal_mb: Math.round(last / 1048576), budget_mb: maxWalMb, unavailable: true, stale: true }; } // ultimo valore noto, dichiarato non aggiornato
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
//  - (FIX-02) una MISURA CONCLUSIVA del WAL a fine finish (monotona: non decresce) decide l'esito anche se il finish è più rapido del timer;
//    `finalizeWal` distingue within_budget / cancelled_before_commit / over_budget_after_commit / monitor_lost / finish_unknown e solo
//    within_budget senza altre anomalie vale come successo (exit 0). Dopo un commit non si dichiara mai un rollback e non si tocca nulla.
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

// SQL del monitor: l'elenco è CHIUSO. La connessione di monitoraggio (db-bun.mjs) accetta SOLO questi testi esatti: la sicurezza non
// dipende da un filtro a espressioni regolari sul testo del chiamante ma da un insieme finito e costante di istruzioni.
export const MONITOR_SQL = Object.freeze({
  wal: 'select pg_wal_lsn_diff(pg_current_wal_lsn(), $1::pg_lsn)::bigint as bytes',
  cancel: 'select pg_cancel_backend($1::int) as ok',
  // Si identifica il backend per pid + login (non per application_name): Supavisor riscrive application_name in 'Supavisor' (misurato su
  // Preview reale), quindi un filtro sul nome darebbe un falso «gone» dietro il pooler. Stesso login = stessa identità del processo.
  activity: 'select state::text as state from pg_stat_activity where pid = $1::int and usename = session_user and pid <> pg_backend_pid()',
  ping: 'select 1 as ok',
});
export const MONITOR_SQL_ALLOWED = new Set(Object.values(MONITOR_SQL));

const defaultTimers = { setTimeout: (...a) => setTimeout(...a), clearTimeout: (...a) => clearTimeout(...a) };

/**
 * Promise con scadenza: una query bloccata non tiene mai ferma l'esecuzione (nessuna attesa indefinita).
 * ATTENZIONE: la scadenza interrompe l'ATTESA JavaScript, NON la query PostgreSQL, che può restare in esecuzione sul server (e
 * confermare dopo la scadenza). L'errore ha `code = 'WI_DEADLINE'` perché il chiamante lo tratti come esito incerto, mai come annullamento.
 */
export function withDeadline(promise, ms, what, timers = defaultTimers) {
  let t;
  const timeout = new Promise((_, reject) => {
    t = timers.setTimeout(() => reject(Object.assign(new Error(`${what}: nessuna risposta entro ${ms} ms`), { code: 'WI_DEADLINE' })), ms);
  });
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => timers.clearTimeout(t));
}

/** Margine (ms) tra lo `statement_timeout` del finish (lato server) e la scadenza lato client: il server deve poter scadere per primo. */
export const FINISH_DEADLINE_MARGIN_MS = 60_000;
/** Scadenza lato client della chiamata `finish_import_run`: `finishTimeoutMin` + margine documentato. */
export function finishDeadlineMs(finishTimeoutMin) {
  const min = Number(finishTimeoutMin);
  if (!Number.isFinite(min) || min <= 0) throw new Error('Scadenza del finish: finishTimeoutMin non valido.');
  return Math.round(min * 60_000) + FINISH_DEADLINE_MARGIN_MS;
}
/** Scadenza complessiva della verifica post-commit (somma di query indipendenti: nessuna attesa illimitata). */
export const VERIFY_DEADLINE_MS = 120_000;
/** Scadenza complessiva della conclusione del finish (stop del monitor, riconciliazione, misura del WAL). */
export const CONCLUDE_DEADLINE_MS = 90_000;

/**
 * Monitor del WAL del finish su una SECONDA connessione. `query` è quella del monitor (login, nessun SET ROLE: vedi db-bun.mjs);
 * `backendPid` è il backend da annullare. Timer iniettabili per i test.
 *
 * Proprietà (WI-001C-FIX-02):
 *  - ogni query del monitor ha una scadenza (`queryTimeoutMs`): una query bloccata conta come campione fallito e non lascia mai `busy` attivo;
 *  - l'annullamento è «riuscito» solo se `pg_cancel_backend` risponde true; false/eccezione si ritenta a ogni campione, con tetto
 *    `maxCancelAttempts` (poi `lost`): nessun ciclo illimitato;
 *  - `stop()` è asincrono: attende (con scadenza) un campione ancora in volo; un campione tardivo viene registrato (picco, superamento) ma
 *    NON può più annullare nulla;
 *  - `start()` rifiuta se il monitor non ha già misurato almeno una volta o ha perso la visibilità.
 * Una richiesta di annullamento riuscita NON prova che il finish sia stato annullato: l'esito lo decide il finish stesso (vedi finalizeWal).
 */
export function createWalMonitor({
  query, backendPid, startLsn, maxWalMb, intervalMs = 2000, failuresBeforeCancel = 2, reopen = null,
  queryTimeoutMs = 5000, stopWaitMs = 5000, maxCancelAttempts = 5,
  setTimer = setInterval, clearTimer = clearInterval, timers = defaultTimers,
}) {
  if (!Number.isInteger(backendPid) || backendPid < 1) throw new Error('Monitor WAL: pid del backend non valido.');
  if (!startLsn || !LSN_RE.test(startLsn)) throw new Error('Monitor WAL: posizione iniziale non valida.');
  if (!Number.isInteger(maxWalMb) || maxWalMb < 1) throw new Error('Monitor WAL: budget non valido.');
  const budgetBytes = maxWalMb * 1048576;
  const state = {
    samples: 0, peakBytes: 0, failures: 0, timeouts: 0, skippedTicks: 0, lateSamples: 0, exceeded: false, cancelRequested: false, cancelOk: null,
    cancelAttempts: 0, lost: false, running: false, inflightAtStop: false, stopTimedOut: false,
  };
  let activeQuery = query;
  let stopped = false;
  let timer = null;
  let busy = false;
  let inflight = null;
  const ask = (q, sql, params) => withDeadline(q(sql, params), queryTimeoutMs, 'query del monitor', timers);

  // L'annullamento NON si considera fatto finché non riesce: se la connessione del monitor è rotta o bloccata se ne apre una nuova
  // (`reopen`, solo la connessione del monitor); a ogni campione successivo si riprova, fino a `maxCancelAttempts`.
  const cancel = async (reason) => {
    // dopo stop() (finish terminato) nessun annullamento tardivo: colpirebbe la verifica o fail_import_run sullo stesso backend
    if (state.cancelOk === true || stopped) return;
    if (state.cancelAttempts >= maxCancelAttempts) { state.lost = true; return; }
    state.cancelReason ??= reason;
    state.cancelAttempts += 1;
    const attempt = async (q) => {
      const r = await ask(q, MONITOR_SQL.cancel, [backendPid]);
      return r.rows[0]?.ok === true;
    };
    try {
      if (stopped) return;
      state.cancelOk = await attempt(activeQuery);
      state.cancelRequested = state.cancelOk;
      return; // false = il server non ha segnalato il backend (già terminato o non annullabile): NON è un annullamento
    } catch {
      state.cancelOk = false;
    }
    if (typeof reopen === 'function') {
      try {
        activeQuery = await reopen();
        if (stopped) return; // finish già concluso durante la riapertura: nessun annullamento tardivo
        state.cancelOk = await attempt(activeQuery);
        state.cancelRequested = state.cancelOk;
        return;
      } catch {
        state.cancelOk = false;
      }
    }
    state.lost = true;
  };
  const doSample = async () => {
    if (state.exceeded || state.lost || state.cancelAttempts > 0) {
      // un annullamento già deciso ma non riuscito: si ritenta (con tetto)
      await cancel(state.cancelReason);
      return;
    }
    try {
      const r = await ask(activeQuery, MONITOR_SQL.wal, [startLsn]);
      const bytes = Number(r.rows[0]?.bytes);
      if (!Number.isFinite(bytes)) throw new Error('lettura WAL non numerica');
      state.samples += 1;
      state.failures = 0;
      state.peakBytes = Math.max(state.peakBytes, bytes);
      if (bytes > budgetBytes) {
        state.exceeded = true;
        if (stopped) state.lateSamples += 1; // campione concluso dopo stop(): registrato, nessuna azione
        else await cancel('budget WAL superato');
      } else if (stopped) state.lateSamples += 1;
    } catch (e) {
      if (/nessuna risposta entro/.test(String(e?.message))) state.timeouts += 1;
      state.failures += 1;
      // fail-closed: senza visibilità sul WAL il finish non prosegue
      if (state.failures >= failuresBeforeCancel && !stopped) await cancel('monitor WAL senza visibilità');
    }
  };
  const sample = async () => {
    if (state.cancelOk === true) return;
    if (busy) { state.skippedTicks = Math.min(state.skippedTicks + 1, 1_000_000); return; }
    busy = true;
    inflight = doSample().finally(() => { busy = false; });
    await inflight;
  };
  const snapshot = () => ({ ...state, peak_mb: Math.round(state.peakBytes / 1048576), budget_mb: maxWalMb, interval_ms: intervalMs });
  return {
    sample,
    start() {
      if (timer) return;
      if (state.samples < 1 || state.lost) throw new Error('Monitor WAL non operativo all\'avvio del finish: finish non avviato (fail-closed).');
      state.running = true;
      timer = setTimer(() => { void sample(); }, intervalMs);
      if (timer && typeof timer.unref === 'function') timer.unref();
    },
    /** Ferma il monitor e attende (con scadenza) un campione ancora in volo. Idempotente. */
    async stop() {
      stopped = true;
      if (timer) clearTimer(timer);
      timer = null;
      state.running = false;
      if (busy && inflight) {
        state.inflightAtStop = true;
        try {
          await withDeadline(inflight.catch(() => {}), stopWaitMs, 'campione in volo', timers);
        } catch {
          state.stopTimedOut = true;
        }
      }
      return snapshot();
    },
    status: snapshot,
  };
}

/** Imposta i limiti della sessione. `target` è la sessione cloud (metodo `setLimits`, SQL interno fidato) oppure una funzione `query` (test/locale). */
export const SESSION_LIMITS_SQL = `select set_config('statement_timeout', $1, false), set_config('lock_timeout', $2, false),
            set_config('idle_in_transaction_session_timeout', $3, false)`;
export async function applySessionLimits(target, { statementTimeoutMs, lockTimeoutMs, idleTxTimeoutMs }) {
  const params = [String(statementTimeoutMs), String(lockTimeoutMs), String(idleTxTimeoutMs)];
  if (target && typeof target.setLimits === 'function') await target.setLimits(SESSION_LIMITS_SQL, params);
  else await target(SESSION_LIMITS_SQL, params);
}

// ---------------------------------------------------------------------------------------------------------------------
// Conclusione del finish (WI-001C-FIX-02 / P1 WAL)
//
// Il finish può terminare tra due campioni del monitor: la sola assenza di un campione oltre budget NON prova che il budget sia stato
// rispettato. L'esito si decide da (a) come è finito il finish (committed / failed / unknown), (b) una MISURA CONCLUSIVA del WAL
// (monotona: pg_current_wal_lsn non decresce, quindi la misura finale ≥ qualunque picco), (c) lo stato del monitor.
// ---------------------------------------------------------------------------------------------------------------------

/** Misura conclusiva: prova le sorgenti in ordine (connessione principale, poi monitor), una volta ciascuna, con scadenza. Non lancia. */
export async function measureFinalWal({ sources, startLsn, timeoutMs = 5000, timers = defaultTimers }) {
  const errors = [];
  for (const { name, query } of sources) {
    try {
      const r = await withDeadline(query(MONITOR_SQL.wal, [startLsn]), timeoutMs, `misura conclusiva (${name})`, timers);
      const bytes = Number(r.rows[0]?.bytes);
      if (Number.isFinite(bytes) && bytes >= 0) return { ok: true, bytes, via: name, errors };
      errors.push(`${name}: lettura non numerica`);
    } catch (e) {
      errors.push(`${name}: ${/nessuna risposta entro/.test(String(e?.message)) ? 'timeout' : String(e?.code ?? 'errore').slice(0, 40)}`); // mai il testo del driver (segreti)
    }
  }
  return { ok: false, bytes: null, via: null, errors };
}

/**
 * Connessione principale persa durante il finish: il backend remoto potrebbe ancora lavorare. Dalla connessione di monitor si guarda
 * `pg_stat_activity` (al massimo `maxProbes` volte, con pausa) e, se il backend è attivo, si chiede UNA volta l'annullamento.
 * Non legge lo stato logico del tentativo (il login non ha privilegi sul catalogo): l'esito resta `finish_unknown` e va riconciliato.
 */
export async function reconcileLostFinish({ query, backendPid, sleep, maxProbes = 4, intervalMs = 1000, timeoutMs = 5000, timers = defaultTimers }) {
  const out = { backend: 'probe_unavailable', probes: 0, cancel_sent: false, cancel_ok: null };
  for (let i = 0; i < maxProbes; i += 1) {
    let state;
    try {
      const r = await withDeadline(query(MONITOR_SQL.activity, [backendPid]), timeoutMs, 'sonda pg_stat_activity', timers);
      state = r.rows.length === 0 ? null : String(r.rows[0]?.state ?? '');
    } catch {
      out.backend = 'probe_unavailable';
      return out;
    }
    out.probes += 1;
    if (state === null) { out.backend = 'gone'; return out; }
    if (state === 'idle') { out.backend = 'idle'; return out; }
    out.backend = state === 'active' ? 'still_active' : state === 'idle in transaction' ? 'idle_in_transaction' : `other:${state.slice(0, 40)}`;
    if (state === 'active' && !out.cancel_sent) {
      out.cancel_sent = true;
      try {
        const c = await withDeadline(query(MONITOR_SQL.cancel, [backendPid]), timeoutMs, 'annullamento', timers);
        out.cancel_ok = c.rows[0]?.ok === true;
      } catch {
        out.cancel_ok = false;
      }
    }
    if (i < maxProbes - 1) await sleep(intervalMs);
  }
  return out;
}

/**
 * Ferma il monitor SENZA mai lanciare (R4). Se `stop()` lancia lo stato è registrato come perso con `stop_failed: true` (il monitor non
 * è affidabile: non si sa se un campione tardivo o un annullamento siano ancora in corso) e si conserva quanto noto con `status()`.
 */
export async function safeStopMonitor(monitor) {
  if (!monitor) return null;
  try {
    return await monitor.stop();
  } catch {
    let known = {};
    try { known = typeof monitor.status === 'function' ? monitor.status() : {}; } catch { /* stato non leggibile */ }
    return {
      samples: 0, peakBytes: 0, cancelAttempts: 0, cancelOk: null, exceeded: false, cancelRequested: false, lateSamples: 0, timeouts: 0,
      ...known, running: false, lost: true, stop_failed: true,
    };
  }
}

/**
 * Orchestrazione fine-finish: ferma il monitor (attendendo un campione in volo), riconcilia se serve, misura il WAL. Non lancia e NON
 * attende oltre `deadlineMs` (CONCLUDE_DEADLINE_MS): ogni suo passo ha già una scadenza propria, quella complessiva è la rete di sicurezza.
 * Se scade, ciò che manca è assente (WAL finale non misurato = esito non verificabile), mai assunto.
 */
export async function concludeFinish({ monitor, status, mainQuery, monitorQuery, startLsn, backendPid, sleep, timers = defaultTimers, deadlineMs = CONCLUDE_DEADLINE_MS }) {
  const acc = { monitor: null, remote: null, finalWal: { ok: false, bytes: null, via: null, errors: ['conclusione non completata'] }, deadline_expired: false };
  const body = async () => {
    acc.monitor = await safeStopMonitor(monitor);
    if (status === 'unknown') acc.remote = await reconcileLostFinish({ query: monitorQuery, backendPid, sleep, timers });
    acc.finalWal = await measureFinalWal({ sources: [{ name: 'principale', query: mainQuery }, { name: 'monitor', query: monitorQuery }], startLsn, timers });
  };
  try {
    await withDeadline(body(), deadlineMs, 'conclusione del finish', timers);
  } catch (e) {
    if (e?.code === 'WI_DEADLINE') acc.deadline_expired = true; // le operazioni in corso non sono annullate: esito non confermato
    else acc.finalWal = { ok: false, bytes: null, via: null, errors: ['conclusione fallita'] };
  }
  return acc;
}

// ---------------------------------------------------------------------------------------------------------------------
// Identità del run e riconciliazione (WI-001C-FIX-03 / R1). Nessuna credenziale: solo identificativi pubblici del tentativo.
// ---------------------------------------------------------------------------------------------------------------------
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const RECONCILE_RUNBOOK_SECTION = 'Esito incerto del finish';

/** Ripulisce l'identità del run: valori solo nella forma attesa, altrimenti null (mai testo libero del driver). */
export function sanitizeRunIdentity(id) {
  const x = id && typeof id === 'object' ? id : {};
  const fileName = typeof x.file_name === 'string' ? x.file_name.split(/[\\/]/).pop().replace(/[\u0000-\u001f]/g, '').slice(0, 200) : '';
  return {
    run_id: typeof x.run_id === 'string' && UUID_RE.test(x.run_id) ? x.run_id.toLowerCase() : null,
    source_code: typeof x.source_code === 'string' && /^[A-Za-z0-9._-]{1,64}$/.test(x.source_code) ? x.source_code : null,
    file_sha256: typeof x.file_sha256 === 'string' && /^[0-9a-f]{64}$/i.test(x.file_sha256) ? x.file_sha256.toLowerCase() : null,
    file_name: fileName || null,
    backend_pid: Number.isInteger(x.backend_pid) && x.backend_pid > 0 ? x.backend_pid : null,
  };
}

/** Blocco `reconcile` del report: gli identificativi con cui un operatore, da una sessione NUOVA, ritrova il tentativo. */
export function buildReconcile(identity) {
  const id = sanitizeRunIdentity(identity);
  return {
    ...id,
    runbook_section: RECONCILE_RUNBOOK_SECTION,
    lookup: id.run_id
      ? 'catalog.import_runs where id = run_id (status, finished_at, counts)'
      : 'run_id sconosciuto (la risposta di begin_import_run non è arrivata): catalog.import_runs della fonte source_code con snapshot file_sha256, il più recente',
    backend_pid_note: id.backend_pid ? 'valido solo per la sessione terminata: non riusarlo per una sessione nuova' : null,
  };
}

/**
 * Verifica post-commit con scadenza complessiva e risultato SEMPRE normalizzato (R5). Non lancia.
 *  status: 'completed' (la verifica è finita: `ok` dice se i controlli sono superati) | 'failed' (lanciata, scaduta o risultato non valido)
 *          | 'not_run' (non avviata: sessione non integra).
 * Un risultato non valido o assente NON è mai `ok: true`.
 */
export const VERIFICATION_NOT_RUN = Object.freeze({ status: 'not_run', ok: false, reason: 'verification_not_run', checks: [] });
export async function runVerification(query, args, { deadlineMs = VERIFY_DEADLINE_MS, timers = defaultTimers, verify = verifyFinish, notRunReason = null } = {}) {
  if (notRunReason) return { ...VERIFICATION_NOT_RUN, detail: String(notRunReason).slice(0, 120) };
  let res;
  try {
    res = await withDeadline(verify(query, args), deadlineMs, 'verifica post-commit', timers);
  } catch (e) {
    return { status: 'failed', ok: false, reason: e?.code === 'WI_DEADLINE' ? 'verification_deadline' : 'verification_error', checks: [] };
  }
  if (!res || typeof res !== 'object' || typeof res.ok !== 'boolean' || !Array.isArray(res.checks)) {
    return { status: 'failed', ok: false, reason: 'verification_invalid_result', checks: [] };
  }
  return { status: 'completed', ...res, ok: res.ok === true };
}

/**
 * Esito conclusivo per il CLI: come finalizeWal, ma (a) una conclusione ASSENTE (hook fallito) dopo un commit vale «WAL non verificabile»
 * (monitor_lost, exit 1), (b) un monitor assente nella conclusione vale non affidabile, (c) dopo un commit la verifica è OBBLIGATORIA:
 * se manca vale `verification_not_run`. L'invariante «solo within_budget vale successo» non dipende dal fatto che questi pezzi esistano.
 */
export function buildFinishOutcome({ finishStatus, conclusion, verification, budgetBytes, errorCode, identity, uncertainReason, failMarked }) {
  const monitor = conclusion?.monitor ?? { samples: 0, peakBytes: 0, cancelAttempts: 0, cancelOk: null, lost: true, missing: true };
  return finalizeWal({
    finish: finishStatus, monitor, finalWal: conclusion?.finalWal ?? { ok: false, bytes: null, via: null },
    remote: conclusion?.remote ?? null, budgetBytes, errorCode, identity, uncertainReason, failMarked,
    verification: finishStatus === 'committed' ? (verification ?? VERIFICATION_NOT_RUN) : verification,
    concludeDeadlineExpired: conclusion?.deadline_expired === true,
  });
}

export const WAL_OUTCOMES = Object.freeze({
  WITHIN_BUDGET: 'within_budget',
  CANCELLED_BEFORE_COMMIT: 'cancelled_before_commit',
  OVER_BUDGET_AFTER_COMMIT: 'over_budget_after_commit',
  MONITOR_LOST: 'monitor_lost',
  FINISH_UNKNOWN: 'finish_unknown',
  FAILED_BEFORE_COMMIT: 'failed_before_commit', // finish fallito per altra causa (timeout, errore SQL): rollback noto
});

/**
 * Esito conclusivo del finish rispetto al WAL. Funzione PURA.
 *  finish: 'committed' | 'failed' | 'unknown'  (come è finita la chiamata finish_import_run)
 *  monitor: stato del monitor (stop()) o null; finalWal: { ok, bytes } della misura conclusiva; remote: esito di reconcileLostFinish;
 *  verification: esito di verifyFinish (`ok`, `checks`) oppure undefined se non eseguita.
 * `ok` è true SOLO per within_budget senza altre anomalie; l'exit code del processo è 0 solo allora.
 * Se il commit è avvenuto NON si parla di rollback e NON si tocca nulla: si segnala e si chiede riconciliazione.
 */
export function finalizeWal({ finish, monitor = null, finalWal = null, budgetBytes, remote = null, verification, errorCode, identity, uncertainReason, concludeDeadlineExpired = false, failMarked } = {}) {
  if (!['committed', 'failed', 'unknown'].includes(finish)) throw new Error('Esito del finish non valido.');
  if (!Number.isFinite(Number(budgetBytes)) || Number(budgetBytes) <= 0) throw new Error('Budget WAL non valido.');
  const budget = Number(budgetBytes);
  const mb = (b) => Math.round(b / 1048576);
  const measured = finalWal?.ok === true ? Number(finalWal.bytes) : null;
  const peak = Math.max(Number(monitor?.peakBytes ?? 0), measured ?? 0);
  const overBudget = monitor?.exceeded === true || (measured !== null && measured > budget);
  const stopFailed = monitor?.stop_failed === true;
  const monitorUnreliable = monitor !== null && (monitor.lost === true || stopFailed || monitor.missing === true || (Number(monitor.cancelAttempts) > 0 && monitor.cancelOk !== true) || monitor.stopTimedOut === true);
  const reasons = [];
  let outcome;
  let dbState;
  let uncertainty;
  let nextAction;

  if (finish === 'unknown') {
    outcome = WAL_OUTCOMES.FINISH_UNKNOWN;
    dbState = 'sconosciuto';
    reasons.push('finish_result_unknown');
    if (remote) reasons.push(`remote_backend_${remote.backend}`);
    if (uncertainReason) reasons.push(`finish_unknown_${String(uncertainReason).replace(/[^a-z0-9_]/gi, '_').slice(0, 60)}`);
    if (overBudget) reasons.push('wal_budget_exceeded_observed');
    uncertainty = uncertainReason === 'deadline_expired'
      ? 'La scadenza lato client è trascorsa: la query PostgreSQL potrebbe essere ancora in esecuzione o aver confermato dopo la scadenza. La scadenza NON annulla nulla e non prova né il commit né il rollback.'
      : 'Non si sa se la promozione sia stata confermata o annullata: l\'esito del finish non è dimostrato (connessione caduta, errore senza SQLSTATE affidabile o risposta illeggibile).';
    nextAction = `NON ripetere l'import e NON chiamare fail_import_run (cancellerebbe finding e staging di un run forse già confermato). Da una sessione nuova leggere catalog.import_runs per il run indicato in \`reconcile\` (status, finished_at) e riconciliare come da runbook (sezione «${RECONCILE_RUNBOOK_SECTION}»).`;
  } else if (finish === 'failed') {
    // «annullato dal monitor» solo se il server ha davvero interrotto l'istruzione (57014); un altro errore non si attribuisce al monitor
    const byMonitor = monitor?.cancelRequested === true && monitor?.cancelOk === true && (errorCode === undefined || errorCode === '57014');
    outcome = byMonitor ? WAL_OUTCOMES.CANCELLED_BEFORE_COMMIT : WAL_OUTCOMES.FAILED_BEFORE_COMMIT;
    dbState = 'finish non confermato (rollback della transazione di promozione); nessun dato parziale visibile';
    reasons.push(byMonitor ? (overBudget ? 'wal_budget_exceeded_cancelled' : 'monitor_visibility_lost_cancelled') : 'finish_failed');
    if (overBudget && !byMonitor) reasons.push('wal_budget_exceeded_observed');
    if (monitorUnreliable) reasons.push('monitor_unreliable');
    uncertainty = failMarked === true
      ? 'Il WAL già scritto dal finish annullato non si recupera (costo/log). fail_import_run è riuscito: il tentativo è marcato failed.'
      : failMarked === false
        ? 'Il WAL già scritto non si recupera. fail_import_run NON è riuscito: il tentativo può essere ancora `running` con lo staging pieno (riprendere con --takeover dopo il timeout di heartbeat).'
        : 'Il WAL già scritto dal finish annullato non si recupera (costo/log). Lo stato del tentativo (failed/running) non è stato rilevato: verificarlo in catalog.import_runs.';
    nextAction = byMonitor
      ? 'Aumentare il budget o ridurre il carico solo con una decisione esplicita; poi ripetere il tentativo (il file intero riparte).'
      : 'Leggere il messaggio d\'errore del report e il tentativo failed; correggere la causa prima di ripetere.';
  } else if (overBudget) {
    outcome = WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT;
    dbState = 'promozione CONFERMATA (committed): i dati importati restano; il budget WAL è stato superato';
    reasons.push('wal_budget_exceeded_after_commit');
    if (monitor?.cancelRequested === true) reasons.push('cancel_requested_but_committed');
    uncertainty = 'Il commit è avvenuto: nessun rollback è possibile o dichiarato. Il WAL in eccesso è già stato scritto.';
    nextAction = 'NON ripetere l\'import e non cancellare dati. Verificare il run (succeeded), il costo/WAL effettivo e la verifica post-finish; riconciliare come da runbook.';
  } else if (finalWal?.ok !== true || monitorUnreliable) {
    outcome = WAL_OUTCOMES.MONITOR_LOST;
    dbState = 'promozione CONFERMATA (committed)';
    if (finalWal?.ok !== true) reasons.push('final_wal_measurement_unavailable');
    if (monitorUnreliable) reasons.push('monitor_unreliable');
    uncertainty = 'Il commit è avvenuto, ma il WAL totale non è verificabile o il monitor non era affidabile: il budget potrebbe essere stato superato senza che nessuno lo abbia visto.';
    nextAction = 'NON ripetere l\'import. Misurare il WAL/costo dal pannello del progetto e riconciliare come da runbook.';
  } else {
    outcome = WAL_OUTCOMES.WITHIN_BUDGET;
    if (monitor?.cancelRequested === true) reasons.push('cancel_sent_but_committed'); // segnale da non ignorare anche entro budget
    dbState = 'promozione CONFERMATA (committed)';
    uncertainty = 'Il WAL include l\'attività di altri client (limite superiore prudente).';
    nextAction = 'Nessuna azione sul WAL.';
  }
  if (stopFailed) reasons.push('monitor_stop_failed');
  if (concludeDeadlineExpired) reasons.push('conclusion_deadline_expired');
  // verifica post-commit (R5): obbligatoria dopo un commit. `undefined` = non richiesta (solo prove unitarie di finalizeWal: il CLI passa
  // sempre da buildFinishOutcome, che la rende obbligatoria). Assente, non eseguita, fallita o con risultato non valido NON è mai un successo.
  let verificationState = 'not_applicable';
  if (finish === 'committed') {
    if (verification === undefined) verificationState = 'not_requested';
    else if (verification?.status === 'not_run') {
      verificationState = 'not_run';
      reasons.push('verification_not_run');
      nextAction = `${nextAction} Verifica post-finish NON eseguita: va eseguita da una sessione nuova (runbook).`;
    } else if (!verification || typeof verification !== 'object' || typeof verification.ok !== 'boolean' || verification.status === 'failed') {
      verificationState = 'failed';
      reasons.push('verification_failed');
      nextAction = `${nextAction} Verifica post-finish NON completata (${verification?.reason ?? 'risultato non valido'}): va ripetuta da una sessione nuova.`;
    } else if (verification.ok === false) {
      verificationState = 'failed_checks';
      reasons.push('verification_failed');
      nextAction = `${nextAction} Verifica post-finish NON superata: ${(verification.checks ?? []).filter((c) => !c.ok).map((c) => c.id).slice(0, 6).join(', ') || 'dettaglio nel report'}.`;
    } else verificationState = 'passed';
  }
  const monitorStatus = monitor === null ? 'absent' : stopFailed ? 'stop_failed' : monitor.missing === true ? 'missing' : monitor.lost === true ? 'lost' : monitorUnreliable ? 'unreliable' : 'reliable';
  const ok = outcome ===WAL_OUTCOMES.WITHIN_BUDGET && reasons.length === 0;
  return {
    outcome,
    ok,
    exit_code: ok ? 0 : 1,
    failure_reasons: reasons,
    finish_status: finish,
    wal: { measured_mb: measured === null ? null : mb(measured), measured_bytes: measured, peak_mb: mb(peak), budget_mb: mb(budget), measured_via: finalWal?.via ?? null },
    monitor: monitor ? { samples: monitor.samples, late_samples: monitor.lateSamples ?? 0, exceeded: monitor.exceeded === true, cancel_requested: monitor.cancelRequested === true, cancel_ok: monitor.cancelOk ?? null, cancel_attempts: monitor.cancelAttempts ?? 0, lost: monitor.lost === true, stop_failed: stopFailed, timeouts: monitor.timeouts ?? 0 } : null,
    // stati DISTINTI: database, verifica post-commit, monitor, esito globale (un commit confermato non diventa mai un rollback immaginario)
    states: { database: finish === 'committed' ? 'committed' : finish === 'failed' ? 'rolled_back_known' : 'unknown', verification: verificationState, monitor: monitorStatus, overall: outcome },
    known_db_state: dbState,
    residual_uncertainty: uncertainty,
    next_action: nextAction,
    ...(identity !== undefined ? { reconcile: buildReconcile(identity) } : {}),
    ...(remote ? { remote_backend: remote } : {}),
  };
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
