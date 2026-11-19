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
  return { server_version: row.version, database: row.db, session_user: row.session_user, ssl: true };
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
