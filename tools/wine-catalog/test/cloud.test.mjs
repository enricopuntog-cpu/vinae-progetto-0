// Predisposizione dell'importatore cloud (WI-001C). Nessun database né rete: funzioni pure e database finti.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  parseCloudUrl, redactUrl, assertCloudAuthorized, resolveCloudLimits, PRODUCTION_REF, CLOUD_ENABLE_ENV,
} from '../lib/cloud-target.mjs';
import { redact, limitLine, sanitizeError, createLogger } from '../lib/safe-log.mjs';
import { assertCloudSession, assertLoaderPrivileges, createWalGuard, applySessionLimits, verifyFinish } from '../lib/cloud-guards.mjs';
import { assertLocalDatabaseUrl } from '../lib/paths.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, '..', 'lwin-load.mjs');
const REPO = join(HERE, '..', '..', '..');
const REF = 'abcdefghijklmnopqrst';
const DIRECT = `postgresql://catalog_loader_login:s3cretPW@db.${REF}.supabase.co:5432/postgres?sslmode=verify-full`;
const POOLER = `postgresql://postgres.${REF}:s3cretPW@aws-0-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=verify-full`;
const ENABLED = { [CLOUD_ENABLE_ENV]: 'enabled' };

// --- Identità della destinazione -----------------------------------------------------------------------------------

test('URL cloud ammessi: connessione diretta e pooler in sessione, con TLS verificato', () => {
  const d = parseCloudUrl(DIRECT);
  assert.deepEqual([d.kind, d.ref, d.production, d.database], ['direct', REF, false, 'postgres']);
  const p = parseCloudUrl(POOLER);
  assert.deepEqual([p.kind, p.ref], ['pooler', REF]);
  assert.equal(parseCloudUrl(`postgresql://u:p@db.${PRODUCTION_REF}.supabase.co/postgres?sslmode=verify-full`).production, true);
});

test('URL cloud rifiutati: host non Supabase, sslmode debole, parametri extra, pooler in transazione, ref incoerente', () => {
  const bad = [
    [`postgresql://u:p@evil.example.com:5432/postgres?sslmode=verify-full`, /non ammesso/],
    [`postgresql://u:p@db.${REF}.supabase.co.evil.com/postgres?sslmode=verify-full`, /non ammesso/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres`, /sslmode=verify-full/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres?sslmode=require`, /sslmode=verify-full/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres?sslmode=verify-full&host=evil.com`, /non ammesso/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres?sslmode=verify-full&options=-c%20role%3Dx`, /non ammesso/],
    [`postgresql://u:p@db.${REF}.supabase.co:6543/postgres?sslmode=verify-full`, /6543/],
    [`postgresql://u:p@db.${REF}.supabase.co:5433/postgres?sslmode=verify-full`, /Porta/],
    [`postgresql://u:p@aws-0-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=verify-full`, /<ruolo>\.<ref/],
    [`mysql://u:p@db.${REF}.supabase.co/postgres?sslmode=verify-full`, /schema/],
    [`postgresql://u:p@db.${REF}.supabase.co,db.${REF}.supabase.co/postgres?sslmode=verify-full`, /host|non valida/],
    [`postgresql://u:p@db.TOOSHORT.supabase.co/postgres?sslmode=verify-full`, /non ammesso/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres?sslmode=verify-full&sslmode=disable`, /ripetuto/],
    [`postgresql://u:p@db.${REF}.supabase.co/postgres?sslmode=verify-full&application_name=a&application_name=b`, /ripetuto/],
    ['non-una-url', /non valida/],
  ];
  for (const [url, re] of bad) assert.throws(() => parseCloudUrl(url), re, url);
});

test('le protezioni loopback di WI-001B restano: un host cloud è rifiutato dalla modalità locale', () => {
  assert.throws(() => assertLocalDatabaseUrl(DIRECT), /locali|loopback|non ammesso/);
  assert.throws(() => assertLocalDatabaseUrl(`postgresql://u:p@db.${REF}.supabase.co/postgres`), /loopback|non ammesso/);
  assert.doesNotThrow(() => assertLocalDatabaseUrl('postgresql://u:p@127.0.0.1:54322/postgres'));
});

// --- Autorizzazione ------------------------------------------------------------------------------------------------

test('cloud DISABILITATO di default: senza --cloud, senza interruttore, senza target-ref non parte', () => {
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { targetRef: REF } }), /manca --cloud/);
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: {}, flags: { cloud: true, targetRef: REF } }), /DISABILITATA/);
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: { [CLOUD_ENABLE_ENV]: 'true' }, flags: { cloud: true, targetRef: REF } }), /DISABILITATA/);
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true } }), /--target-ref/);
  assert.throws(() => assertCloudAuthorized({ url: null, env: ENABLED, flags: { cloud: true, targetRef: REF } }), /CATALOG_DATABASE_URL/);
});

test('destinazione non confermata: il target-ref deve coincidere con il ref dell\'URL', () => {
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true, targetRef: 'zzzzzzzzzzzzzzzzzzzz' } }), /non coincide/);
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true, targetRef: 'corto' } }), /ref di progetto/);
  const t = assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true, targetRef: REF } });
  assert.deepEqual([t.ref, t.production], [REF, false]);
});

test('la URL non si passa da riga di comando in modalità cloud', () => {
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true, targetRef: REF, databaseUrlOnCommandLine: true } }), /--database-url/);
});

test('Production rifiutata senza approvazione esplicita e coerente (oggi nessuna approvazione esiste)', () => {
  const prodUrl = `postgresql://u:p@db.${PRODUCTION_REF}.supabase.co/postgres?sslmode=verify-full`;
  const base = { url: prodUrl, flags: { cloud: true, targetRef: PRODUCTION_REF } };
  assert.throws(() => assertCloudAuthorized({ ...base, env: ENABLED }), /Production rifiutata/);
  assert.throws(() => assertCloudAuthorized({ ...base, flags: { ...base.flags, allowProduction: true }, env: ENABLED }), /Production rifiutata/);
  assert.throws(() => assertCloudAuthorized({ ...base, env: { ...ENABLED, CATALOG_PRODUCTION_APPROVAL: `approved:${PRODUCTION_REF}:x` } }), /Production rifiutata/);
  assert.throws(() => assertCloudAuthorized({ ...base, flags: { ...base.flags, allowProduction: true }, env: { ...ENABLED, CATALOG_PRODUCTION_APPROVAL: 'approved:altro:ticket-1234' } }), /Production rifiutata/);
  const ok = assertCloudAuthorized({ ...base, flags: { ...base.flags, allowProduction: true }, env: { ...ENABLED, CATALOG_PRODUCTION_APPROVAL: `approved:${PRODUCTION_REF}:ticket-1234` } });
  assert.equal(ok.production, true);
  assert.throws(() => assertCloudAuthorized({ url: DIRECT, env: ENABLED, flags: { cloud: true, targetRef: REF, allowProduction: true } }), /incoerente/);
});

test('limiti di risorse: valori di default, intervalli validati', () => {
  assert.deepEqual(resolveCloudLimits(), { batchSize: 1000, maxWalMb: 3000, batchTimeoutSec: 120, finishTimeoutMin: 30, lockTimeoutSec: 30, idleTxTimeoutSec: 60 });
  assert.equal(resolveCloudLimits({ batchSize: '500' }).batchSize, 500);
  for (const [k, v] of [['batchSize', '0'], ['batchSize', '5001'], ['maxWalMb', '10'], ['finishTimeoutMin', '999'], ['batchTimeoutSec', 'abc']]) {
    assert.throws(() => resolveCloudLimits({ [k]: v }), /intero tra/, `${k}=${v}`);
  }
});

// --- Segreti e log -------------------------------------------------------------------------------------------------

test('redactUrl e redact non lasciano password né credenziali nei messaggi', () => {
  assert.ok(!redactUrl(DIRECT).includes('s3cretPW'));
  assert.match(redactUrl(DIRECT), /:\*\*\*@/);
  const msg = redact(`connection failed for ${DIRECT} (password s3cretPW)`, ['s3cretPW']);
  assert.ok(!msg.includes('s3cretPW'));
  assert.ok(!sanitizeError(new Error(`boom ${DIRECT}`), [DIRECT]).includes('s3cretPW'));
});

test('log limitati: righe lunghe troncate, numero di righe con tetto', () => {
  assert.ok(limitLine('x'.repeat(1000), 300).length < 330);
  const out = [];
  const logger = createLogger({ maxLines: 3, sink: (l) => out.push(l) });
  for (let i = 0; i < 10; i += 1) logger.log(`riga ${i} ${DIRECT}`);
  assert.equal(out.length, 3);
  assert.ok(out.every((l) => !l.includes('s3cretPW')));
  assert.deepEqual(logger.summary(), { lines: 3, suppressed: 7 });
});

// --- Controlli di sessione e privilegi (database finto) ------------------------------------------------------------

const goodSession = {
  version_num: 170006, version: '17.6', db: 'postgres', session_user: 'postgres', session_superuser: false, in_recovery: false,
  session_powers: false, session_owns_catalog: false, session_curator: false,
  ssl: true, has_finish: true, has_begin: true, has_stage: true, stage_unlogged: true,
};
const fakeQuery = (row) => async () => ({ rows: [row] });
// login conforme (I-2): raggiunge SOLO catalog_loader, nessun potere, nessun grant diretto, nessuna proprietà
const goodAudit = {
  login_found: true, login_can_login: true, login_powers: false, reachable: ['catalog_loader'], powerful: [], admin_over: [],
  direct_grants: 0, owned_objects: 0, db_create: false, public_create: false, catalog_create: false,
};
const sessionQuery = (row, audit = goodAudit) => async (text) => (text.includes('server_version_num') ? { rows: [row] } : { rows: [{ audit }] });

test('sessione cloud: accettata se cifrata, non in recovery, PostgreSQL ≥ 15, non superuser, migration presente, login dedicato', async () => {
  const r = await assertCloudSession(sessionQuery(goodSession));
  assert.deepEqual([r.ssl, r.server_version, r.login_audit], [true, '17.6', 'conforme']);
});

test('sessione cloud: ogni requisito mancante è rifiutato con il motivo', async () => {
  const cases = [
    [{ ssl: false }, /non è cifrata/], [{ in_recovery: true }, /recovery/], [{ version_num: 140000, version: '14.2' }, /< 15/],
    [{ session_superuser: true }, /superuser/], [{ session_powers: true }, /login dedicato/], [{ session_owns_catalog: true }, /proprietario/],
    [{ session_curator: true }, /catalog_curator/], [{ has_finish: false }, /WI-001B/], [{ stage_unlogged: false }, /UNLOGGED/],
  ];
  for (const [patch, re] of cases) await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ...patch })), re);
});

// --- Pooler (Supavisor, sessione): pg_stat_ssl descrive il tratto pooler → PostgreSQL, non client → pooler ---------------

const POOLER_OPTS = { kind: 'pooler', clientTlsVerified: true, expectedLogin: 'postgres' };

test('pooler: ssl del backend false ma TLS client attestato → accettato, tratto pooler→PostgreSQL dichiarato NON provato (mai «cifrato»)', async () => {
  const r = await assertCloudSession(sessionQuery({ ...goodSession, ssl: false }), POOLER_OPTS);
  assert.deepEqual([r.ssl, r.backend_ssl], [undefined, false]);
  assert.deepEqual(r.transport, { kind: 'pooler', client_to_pooler: 'tls_verify_full_driver', pooler_to_postgres: 'not_proven' });
});

test('pooler: ssl del backend true → tratto pooler→PostgreSQL dichiarato cifrato (con prova pg_stat_ssl)', async () => {
  const r = await assertCloudSession(sessionQuery(goodSession), POOLER_OPTS);
  assert.deepEqual([r.backend_ssl, r.transport.pooler_to_postgres], [true, 'encrypted_pg_stat_ssl']);
});

test('pooler: informazione SSL non disponibile (null/assente) → non dichiarata cifrata', async () => {
  for (const ssl of [null, undefined]) {
    const r = await assertCloudSession(sessionQuery({ ...goodSession, ssl }), POOLER_OPTS);
    assert.deepEqual([r.backend_ssl, r.transport.pooler_to_postgres], [false, 'not_proven']);
  }
});

test('pooler: senza attestazione del TLS verificato lato client → rifiutato (fail-closed), qualunque sia pg_stat_ssl', async () => {
  for (const ssl of [true, false]) {
    for (const clientTlsVerified of [false, undefined, 'true', 1]) {
      await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ssl }), { ...POOLER_OPTS, clientTlsVerified }), /TLS verificato client → pooler non attestato/);
    }
  }
});

test('pooler: login effettivo diverso da quello della URL (o non dichiarato) → rifiutato', async () => {
  await assert.rejects(() => assertCloudSession(sessionQuery(goodSession), { ...POOLER_OPTS, expectedLogin: 'altro_login' }), /login effettivo/);
  for (const expectedLogin of [null, undefined, '']) {
    await assert.rejects(() => assertCloudSession(sessionQuery(goodSession), { ...POOLER_OPTS, expectedLogin }), /login effettivo/);
  }
});

test('pooler: gli altri controlli di sessione restano in vigore (recovery, superuser, login non dedicato, migration)', async () => {
  const cases = [[{ in_recovery: true }, /recovery/], [{ session_superuser: true }, /superuser/], [{ has_finish: false }, /WI-001B/]];
  for (const [patch, re] of cases) await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ssl: false, ...patch }), POOLER_OPTS), re);
  await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ssl: false }, { ...goodAudit, reachable: ['catalog_loader', 'authenticated'] }), POOLER_OPTS), /login non dedicato/);
});

test('connessione diretta: il controllo pg_stat_ssl resta obbligatorio e l\'attestazione client NON lo sostituisce', async () => {
  await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ssl: false }), { kind: 'direct', clientTlsVerified: true }), /non è cifrata/);
  await assert.rejects(() => assertCloudSession(sessionQuery({ ...goodSession, ssl: null })), /non è cifrata/);
  const r = await assertCloudSession(sessionQuery(goodSession), { kind: 'direct' });
  assert.deepEqual([r.ssl, r.transport.kind], [true, 'direct']);
});

test('tipo di connessione sconosciuto → rifiutato prima di qualunque query', async () => {
  let called = false;
  for (const kind of ['transaction', 'POOLER', '', null, 'proxy']) {
    await assert.rejects(() => assertCloudSession(async () => { called = true; return { rows: [goodSession] }; }, { kind, clientTlsVerified: true, expectedLogin: 'postgres' }), /tipo di connessione sconosciuto/);
  }
  assert.equal(called, false);
});

test('destinazione pooler: porta 6543 vietata, ref dell\'utente diverso da --target-ref rifiutato, host non Supabase rifiutato', () => {
  assert.throws(() => parseCloudUrl(`postgresql://postgres.${REF}:p@aws-1-eu-west-1.pooler.supabase.com:6543/postgres?sslmode=verify-full`), /6543/);
  const otherRef = 'zzzzzzzzzzzzzzzzzzzz';
  assert.throws(() => assertCloudAuthorized({ url: POOLER, env: ENABLED, flags: { cloud: true, targetRef: otherRef } }), /non coincide/);
  assert.throws(() => parseCloudUrl(`postgresql://postgres.${REF}:p@aws-1-eu-west-1.pooler.evil.com:5432/postgres?sslmode=verify-full`), /non ammesso/);
  assert.throws(() => parseCloudUrl(POOLER.replace('verify-full', 'require')), /sslmode=verify-full/);
  assert.equal(assertCloudAuthorized({ url: POOLER, env: ENABLED, flags: { cloud: true, targetRef: REF } }).kind, 'pooler');
});

const goodPriv = {
  sr_insert: true, sr_update: true, sr_delete: false, sr_truncate: false, stage_insert: true, sources_insert: false, sources_update: false,
  canonical_select: false, canonical_insert: false, curator_member: false, public_create: false, can_finish: true,
};

test('privilegi del caricatore: conformi accettati; DELETE/TRUNCATE, scrittura fonti, canonico, curatore rifiutati', async () => {
  assert.ok(await assertLoaderPrivileges(fakeQuery(goodPriv)));
  const cases = [
    [{ sr_delete: true }, /DELETE/], [{ sr_truncate: true }, /TRUNCATE/], [{ sources_update: true }, /registro delle fonti/],
    [{ canonical_select: true }, /canoniche/], [{ curator_member: true }, /catalog_curator/], [{ public_create: true }, /public/],
    [{ can_finish: false }, /mancanti/],
  ];
  for (const [patch, re] of cases) await assert.rejects(() => assertLoaderPrivileges(fakeQuery({ ...goodPriv, ...patch })), re);
});

test('guardia WAL: fail-closed se non leggibile; interrompe oltre il budget; riporta i MB', async () => {
  await assert.rejects(() => createWalGuard(async () => { throw new Error('permission denied'); }, { maxWalMb: 100 }), /fail-closed/);
  await assert.rejects(() => createWalGuard(fakeQuery({ lsn: 'non-un-lsn' }), { maxWalMb: 100 }), /non valida/);
  let bytes = 0;
  const q = async (text) => (text.includes('pg_current_wal_lsn()::text') ? { rows: [{ lsn: '0/16B3748' }] } : { rows: [{ bytes }] });
  const g = await createWalGuard(q, { maxWalMb: 100 });
  bytes = 50 * 1048576;
  assert.equal(await g.check(), bytes);
  bytes = 101 * 1048576;
  await assert.rejects(() => g.check(), /Budget WAL superato/);
  assert.deepEqual(await g.report(), { start_lsn: '0/16B3748', wal_mb: 101, budget_mb: 100 });
});

test('limiti di sessione: timeout impostati con set_config (valori passati come parametri)', async () => {
  const seen = [];
  await applySessionLimits(async (t, p) => { seen.push([t, p]); return { rows: [] }; }, { statementTimeoutMs: 120000, lockTimeoutMs: 30000, idleTxTimeoutMs: 60000 });
  assert.match(seen[0][0], /set_config\('statement_timeout'/);
  assert.deepEqual(seen[0][1], ['120000', '30000', '60000']);
});

// --- Verifica dopo finish_import_run -------------------------------------------------------------------------------

function fakeVerifyDb(over = {}) {
  const st = {
    run: { status: 'succeeded', finished: true, counts: { records_seen: 10, state_digest: 'D', removed_from_source: 2, new: 10, updated: 0, unchanged: 0 }, source_id: 'S', file_sha256: 'abc', seconds: 42 },
    running: 0, stage: 0, active: 10, digest: 'D', unlinked: 0, removed: 2, ...over,
  };
  return async (text) => {
    if (text.includes('from catalog.import_runs r')) return { rows: st.run ? [st.run] : [] };
    if (text.includes("status = 'running'")) return { rows: [{ n: st.running }] };
    if (text.includes('catalog.import_stage')) return { rows: [{ n: st.stage }] };
    if (text.includes('removed_in_run')) return { rows: [{ n: st.removed }] };
    if (text.includes('territory_id is null')) return { rows: [{ n: st.unlinked }] };
    if (text.includes('state_digest')) return { rows: [{ d: st.digest }] };
    if (text.includes('removed_from_source_at is null')) return { rows: [{ n: st.active }] };
    throw new Error(`query inattesa: ${text.slice(0, 60)}`);
  };
}

test('verifica del finish: tutti i controlli superati su uno stato coerente', async () => {
  const v = await verifyFinish(fakeVerifyDb(), { runId: 'r', sourceCode: 'LIVEX-LWIN7', expectedSha256: 'abc' });
  assert.equal(v.ok, true);
  assert.equal(v.checks.length, 9);
  assert.equal(v.duration_seconds, 42);
});

test('verifica del finish: ogni anomalia è rilevata (stato, sha, running, staging, conteggi, digest, territori, rimozioni)', async () => {
  const cases = [
    [{ run: { status: 'failed', finished: true, counts: {}, source_id: 'S', file_sha256: 'abc', seconds: 1 } }, 'V01_run_succeeded'],
    [{ run: { status: 'succeeded', finished: true, counts: { records_seen: 10, state_digest: 'D', removed_from_source: 2 }, source_id: 'S', file_sha256: 'altro', seconds: 1 } }, 'V02_snapshot_sha256'],
    [{ running: 1 }, 'V03_no_running_attempt'], [{ stage: 5 }, 'V04_stage_emptied'], [{ active: 9 }, 'V05_active_equals_seen'],
    [{ digest: 'X' }, 'V06_state_digest'], [{ unlinked: 3 }, 'V07_territories_linked'], [{ removed: 1 }, 'V08_removals_marked_only'],
  ];
  for (const [over, id] of cases) {
    const v = await verifyFinish(fakeVerifyDb(over), { runId: 'r', sourceCode: 'LIVEX-LWIN7', expectedSha256: 'abc' });
    assert.equal(v.ok, false, id);
    assert.ok(v.checks.some((c) => c.id === id && !c.ok), id);
  }
  const missing = await verifyFinish(fakeVerifyDb({ run: null }), { runId: 'r', sourceCode: 'LIVEX-LWIN7', expectedSha256: 'abc' });
  assert.equal(missing.ok, false);
});

// --- CLI: nessuna connessione senza le autorizzazioni -------------------------------------------------------------

function runCli(extra, env = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-cli-'));
  try {
    return spawnSync(process.execPath, [CLI, '--input', join(dir, 'x.xlsx'), '--report', join(dir, 'r.json'), ...extra], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...env },
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('CLI: --cloud senza interruttore esce con 2 e non nomina la password', () => {
  const r = runCli(['--cloud', '--target-ref', REF], { CATALOG_DATABASE_URL: DIRECT });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /DISABILITATA/);
  assert.ok(!r.stderr.includes('s3cretPW') && !r.stdout.includes('s3cretPW'));
});

test('CLI: --cloud con --database-url, senza target-ref o con destinazione errata è rifiutato (exit 2)', () => {
  const env = { CATALOG_DATABASE_URL: DIRECT, [CLOUD_ENABLE_ENV]: 'enabled' };
  assert.match(runCli(['--cloud', '--target-ref', REF, '--database-url', DIRECT], env).stderr, /--database-url/);
  assert.match(runCli(['--cloud'], env).stderr, /--target-ref/);
  const wrong = runCli(['--cloud', '--target-ref', 'zzzzzzzzzzzzzzzzzzzz'], env);
  assert.equal(wrong.status, 2);
  assert.match(wrong.stderr, /non coincide/);
  const prod = runCli(['--cloud', '--target-ref', PRODUCTION_REF], { CATALOG_DATABASE_URL: `postgresql://u:s3cretPW@db.${PRODUCTION_REF}.supabase.co/postgres?sslmode=verify-full`, [CLOUD_ENABLE_ENV]: 'enabled' });
  assert.equal(prod.status, 2);
  assert.match(prod.stderr, /Production rifiutata/);
  assert.ok(!prod.stderr.includes('s3cretPW'));
});

test('CLI: le opzioni cloud senza --cloud sono rifiutate; la modalità locale resta loopback-only', () => {
  assert.match(runCli(['--target-ref', REF, '--dry-run']).stderr, /solo con --cloud/);
  const r = runCli(['--database-url', DIRECT]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /locali|loopback|non ammesso/);
});

// --- Workflow GitHub-hosted protetto -------------------------------------------------------------------------------

test('workflow cloud: solo manuale, disabilitato di default, environment protetto, permessi minimi, azioni fissate, nessuna interpolazione negli script', () => {
  const p = join(REPO, '.github', 'workflows', 'wine-catalog-cloud-import.yml');
  assert.ok(existsSync(p));
  const t = readFileSync(p, 'utf8');
  const code = t.split(/\r?\n/).filter((l) => !l.trim().startsWith('#')).join('\n');
  assert.match(code, /^on:\s*\n\s+workflow_dispatch:/m);
  assert.ok(!/pull_request|push:|schedule:|workflow_run/.test(code), 'nessun altro trigger');
  assert.match(code, /vars\.CATALOG_CLOUD_IMPORT_ENABLED == 'true'/);
  assert.match(code, /environment: catalog-cloud-import/);
  assert.match(code, /github\.ref == 'refs\/heads\/main'/);
  // i segreti non sono a livello di job: solo gli step che li usano li ricevono
  const jobEnv = code.split(/\n    steps:/)[0];
  assert.ok(!/secrets\./.test(jobEnv), 'nessun segreto a livello di job');
  assert.match(code, /^permissions:\s*\n\s+contents: read\s*$/m);
  assert.ok(!/:\s*write\b/.test(code));
  for (const m of code.matchAll(/uses:\s*(\S+)/g)) assert.match(m[1], /@[0-9a-f]{40}$/, m[1]);
  assert.match(code, /persist-credentials: false/);
  assert.match(code, /sha256sum --check/);
  // FIX-01 I-1: la CA arriva come segreto in variabile d'ambiente (non su file, non come argomento) e solo allo step del caricatore
  assert.match(code, /CATALOG_DB_CA_PEM: \$\{\{ secrets\.CATALOG_DB_CA_PEM \}\}/);
  assert.ok(!/--ca-file/.test(code), 'la CA non passa da file/argomenti');
  assert.ok(!/sslmode=(?!verify-full)/.test(code));
  // nessun input interpolato dentro uno script `run:` (iniezione): solo variabili d'ambiente
  const runBlocks = code.split(/\n\s+run:\s*[|>]?\s*/).slice(1).map((b) => b.split(/\n\s+- name:/)[0]);
  for (const b of runBlocks) assert.ok(!/\$\{\{/.test(b), `interpolazione in run: ${b.slice(0, 60)}`);
  assert.ok(!/CATALOG_PRODUCTION_APPROVAL/.test(code), 'il workflow non imposta mai l\x27approvazione di Production');
  assert.ok(!/--allow-production/.test(code));
});
