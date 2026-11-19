// WI-001C-FIX-01 — importatore cloud: login dedicato (I-2), WAL preventivo e monitor del finish (I-3), TLS e CA (I-1).
// Nessun database, nessuna rete: funzioni pure e database finti. La prova con un server TLS reale è in tls-bun.test.mjs
// (richiede Bun); la prova dell'audit del login su RUOLI REALI è la griglia SQL 12zz.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { CLOUD_ENABLE_ENV } from '../lib/cloud-target.mjs';
import {
  assertCloudSession, evaluateLoginAudit, LOGIN_AUDIT_SQL, planFinishWal, createWalMonitor,
  FINISH_WAL_BYTES_PER_ROW, FINISH_WAL_BASE_BYTES,
} from '../lib/cloud-guards.mjs';
import { normalizeCaPem, loadCaPem, assertVerifiedTlsUrl, tlsOptions, describeConnectError, isConnectionLost } from '../lib/cloud-tls.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, '..', 'lwin-load.mjs');
const REPO = join(HERE, '..', '..', '..');
const REF = 'abcdefghijklmnopqrst';
const DIRECT = `postgresql://catalog_loader_login:s3cretPW@db.${REF}.supabase.co:5432/postgres?sslmode=verify-full`;
const MB = 1048576;

const goodSession = {
  version_num: 170006, version: '17.6', db: 'postgres', session_user: 'loader_login', session_superuser: false, in_recovery: false,
  session_powers: false, session_owns_catalog: false, session_curator: false,
  ssl: true, has_finish: true, has_begin: true, has_stage: true, stage_unlogged: true,
};
const goodAudit = {
  login_found: true, login_can_login: true, login_powers: false, reachable: ['catalog_loader'], powerful: [], admin_over: [],
  direct_grants: 0, owned_objects: 0, db_create: false, public_create: false, catalog_create: false,
};
const sessionQuery = (row, audit = goodAudit) => async (text) => (text.includes('server_version_num') ? { rows: [row] } : { rows: [{ audit }] });

// --- I-2: login dedicato, grafo TRANSITIVO delle appartenenze -------------------------------------------------------------

test('audit del login: SQL parametrico (un solo parametro), di sola lettura, con grafo pg_auth_members ricorsivo', () => {
  assert.match(LOGIN_AUDIT_SQL, /with recursive/i);
  assert.match(LOGIN_AUDIT_SQL, /pg_auth_members/);
  const noStrings = LOGIN_AUDIT_SQL.replace(/'[^']*'/g, "''");
  assert.ok(!/\b(insert|update|delete|alter|create|drop|grant|revoke|truncate)\b/i.test(noStrings), 'nessuna istruzione di scrittura');
  assert.ok(!/session_user/.test(LOGIN_AUDIT_SQL), 'il login è il parametro $1: la stessa query gira sui ruoli di prova della griglia 12zz');
  assert.deepEqual([...new Set(LOGIN_AUDIT_SQL.match(/\$\d/g))], ['$1']);
});

const GRID_12ZZ = join(REPO, 'supabase', 'tests', '12zz_wi_001c_fix01_login_audit.sql');
// il Rilascio A (solo runner, nessun file in supabase/) non contiene la griglia: il controllo si attiva col Rilascio B
// (docs/wine-intelligence/RELEASE_STRATEGY_WI_001C.md)
test('audit del login: la griglia SQL 12zz contiene ESATTAMENTE lo stesso testo (nessuna deriva tra codice e prova su ruoli reali)', { skip: existsSync(GRID_12ZZ) ? false : 'griglia 12zz assente (Rilascio A senza supabase/)' }, () => {
  const grid = readFileSync(GRID_12ZZ, 'utf8');
  const norm = (x) => x.replace(/\s+/g, ' ').trim();
  assert.ok(norm(grid).includes(norm(LOGIN_AUDIT_SQL)), 'LOGIN_AUDIT_SQL deve comparire identico nella griglia 12zz');
});

test('audit del login conforme: accettato', () => {
  assert.deepEqual(evaluateLoginAudit(goodAudit), []);
});

test('audit del login: ogni scostamento è rifiutato (membership indiretta, ruolo privilegiato, grant extra, escalation, RESET ROLE)', async () => {
  const cases = [
    [{ login_found: false }, /non trovato/],
    // appartenenza INDIRETTA: login → ruolo_intermedio → catalog_curator (un controllo sulla membership diretta non la vedrebbe)
    [{ reachable: ['catalog_curator', 'catalog_loader', 'ruolo_intermedio'] }, /oltre a catalog_loader: catalog_curator, ruolo_intermedio/],
    [{ reachable: ['catalog_loader', 'postgres'] }, /postgres/],
    [{ reachable: ['catalog_loader', 'service_role'] }, /service_role/],
    [{ reachable: [] }, /non è raggiungibile/],
    [{ reachable: ['altro'] }, /oltre a catalog_loader/],
    [{ powerful: ['supabase_admin'], reachable: ['catalog_loader', 'supabase_admin'] }, /poteri amministrativi/],
    [{ login_powers: true }, /SUPERUSER|BYPASSRLS/],
    // con ADMIN OPTION il login potrebbe concedersi altri ruoli: escalation
    [{ admin_over: ['catalog_loader'] }, /ADMIN OPTION/],
    // grant aggiuntivi diretti al login: RESET ROLE lo riporterebbe a privilegi propri
    [{ direct_grants: 2 }, /privilegi concessi direttamente/],
    [{ owned_objects: 1 }, /possiede/],
    [{ db_create: true }, /creare schemi/], [{ public_create: true }, /public/], [{ catalog_create: true }, /catalog/],
  ];
  for (const [patch, re] of cases) {
    const v = evaluateLoginAudit({ ...goodAudit, ...patch });
    assert.ok(v.length > 0, JSON.stringify(patch));
    assert.ok(v.some((m) => re.test(m)), `${JSON.stringify(patch)} → ${v.join(' | ')}`);
    await assert.rejects(() => assertCloudSession(sessionQuery(goodSession, { ...goodAudit, ...patch })), /login non dedicato|non trovato/);
  }
});

test('audit del login: risposta assente o parziale → rifiuto (fail-closed); accetta anche la risposta come stringa JSON', async () => {
  await assert.rejects(() => assertCloudSession(async (t) => (t.includes('server_version_num') ? { rows: [goodSession] } : { rows: [] })), /nessuna risposta/);
  assert.deepEqual(evaluateLoginAudit(null), ['login non trovato nel catalogo dei ruoli']);
  assert.ok(evaluateLoginAudit({ login_found: true }).length > 0, 'senza dati sulla raggiungibilità il login non è accettato');
  const asString = async (t) => (t.includes('server_version_num') ? { rows: [goodSession] } : { rows: [{ audit: JSON.stringify(goodAudit) }] });
  assert.equal((await assertCloudSession(asString)).login_audit, 'conforme');
});

// --- I-3: WAL preventivo e monitor del finish ----------------------------------------------------------------------------------

test('stima preventiva del WAL del finish: entro il budget → ok; oltre → rifiuto PRIMA del finish; valori non validi → errore', () => {
  const small = planFinishWal({ usedBytes: 10 * MB, budgetBytes: 3000 * MB, writtenRows: 212894 });
  assert.equal(small.ok, true);
  assert.equal(small.projectedFinishBytes, FINISH_WAL_BASE_BYTES + 212894 * FINISH_WAL_BYTES_PER_ROW);
  assert.ok(small.projectedFinishBytes < 2000 * MB, 'la stima per il file completo resta sotto il budget predefinito (≈1 GB misurato su dati sintetici)');
  assert.equal(planFinishWal({ usedBytes: 10 * MB, budgetBytes: 1000 * MB, writtenRows: 212894 }).ok, false);
  assert.equal(planFinishWal({ usedBytes: 2990 * MB, budgetBytes: 3000 * MB, writtenRows: 0 }).ok, false);
  assert.throws(() => planFinishWal({ usedBytes: -1, budgetBytes: 1, writtenRows: 0 }), /non validi/);
  assert.throws(() => planFinishWal({ usedBytes: NaN, budgetBytes: 1, writtenRows: 0 }), /non validi/);
});

function monitorFixture({ readings, cancelOk = true, failAt = new Set() }) {
  const calls = [];
  let i = 0;
  const query = async (text, params) => {
    calls.push([text, params]);
    if (text.includes('pg_cancel_backend')) return { rows: [{ ok: cancelOk }] };
    const n = i;
    i += 1;
    if (failAt.has(n)) throw new Error('connessione del monitor caduta');
    return { rows: [{ bytes: readings[Math.min(n, readings.length - 1)] }] };
  };
  const mon = createWalMonitor({
    query, backendPid: 4321, startLsn: '0/16B3748', maxWalMb: 100, intervalMs: 5,
    setTimer: () => ({ unref() {} }), clearTimer: () => {},
  });
  return { mon, calls, tick: () => mon.sample() };
}

test('monitor WAL: sotto il budget non annulla nulla; oltre il budget chiama pg_cancel_backend sul backend dell\'import UNA volta', async () => {
  const f = monitorFixture({ readings: [10 * MB, 50 * MB, 101 * MB, 500 * MB] });
  await f.tick();
  await f.tick();
  assert.equal(f.mon.status().cancelRequested, false);
  await f.tick();
  assert.equal(f.mon.status().exceeded, true);
  assert.equal(f.mon.status().cancelRequested, true);
  await f.tick();
  await f.tick();
  const cancels = f.calls.filter(([t]) => t.includes('pg_cancel_backend'));
  assert.equal(cancels.length, 1, 'un solo annullamento');
  assert.deepEqual(cancels[0][1], [4321]);
  const final = await f.mon.stop();
  assert.equal(final.peak_mb, 101);
  assert.equal(final.cancelOk, true);
});

test('monitor WAL: senza visibilità (errori ripetuti) annulla comunque il finish (fail-closed); un errore isolato no', async () => {
  const one = monitorFixture({ readings: [MB], failAt: new Set([1]) });
  await one.tick();
  await one.tick();
  await one.tick();
  assert.equal(one.mon.status().cancelRequested, false, 'un solo campione fallito non basta');
  const lost = monitorFixture({ readings: [MB], failAt: new Set([0, 1, 2]) });
  await lost.tick();
  await lost.tick();
  assert.equal(lost.mon.status().cancelRequested, true);
  assert.match(String(lost.mon.status().cancelReason), /senza visibilità/);
});

test('monitor WAL: pg_cancel_backend negato o fallito è registrato (cancelOk = false), non nascosto', async () => {
  const f = monitorFixture({ readings: [500 * MB], cancelOk: false });
  await f.tick();
  assert.equal(f.mon.status().cancelOk, false);
  const broken = createWalMonitor({
    query: async (t) => { if (t.includes('pg_cancel_backend')) throw new Error('negato'); return { rows: [{ bytes: 500 * MB }] }; },
    backendPid: 7, startLsn: '0/1', maxWalMb: 100,
  });
  await broken.sample();
  assert.deepEqual([broken.status().cancelOk, broken.status().lost], [false, true]);
});

test('monitor WAL: il ciclo temporizzato campiona, si ferma con stop() e non si sovrappone', async () => {
  let readings = 0;
  const monitor = createWalMonitor({
    query: async () => { readings += 1; return { rows: [{ bytes: 1 * MB }] }; },
    backendPid: 9, startLsn: '0/1', maxWalMb: 100, intervalMs: 5,
  });
  await monitor.sample(); // il monitor deve aver già misurato una volta prima di partire
  monitor.start();
  await new Promise((r) => setTimeout(r, 60));
  const final = await monitor.stop();
  const seen = readings;
  await new Promise((r) => setTimeout(r, 30));
  assert.ok(seen >= 2, `campioni raccolti: ${seen}`);
  assert.equal(readings, seen, 'nessun campione dopo stop()');
  assert.equal(final.running, false);
});

test('monitor WAL: connessione del monitor rotta durante il finish → si riapre una connessione NUOVA e si annulla; senza via d\'uscita l\'esito è «perso» e si ritenta', async () => {
  const calls = [];
  const broken = async () => { throw new Error('connessione caduta'); };
  const fresh = async (t, p) => { calls.push([t, p]); return { rows: [{ ok: true }] }; };
  const m = createWalMonitor({ query: broken, backendPid: 55, startLsn: '0/1', maxWalMb: 100, failuresBeforeCancel: 1, reopen: async () => fresh });
  await m.sample();
  assert.equal(m.status().cancelOk, true, 'annullato tramite la connessione nuova');
  assert.deepEqual(calls[0][1], [55]);
  // nessuna via d'uscita: perso, e a ogni campione successivo si riprova (non si dichiara fatto)
  let reopens = 0;
  const lost = createWalMonitor({ query: broken, backendPid: 55, startLsn: '0/1', maxWalMb: 100, failuresBeforeCancel: 1, reopen: async () => { reopens += 1; throw new Error('rete assente'); } });
  await lost.sample();
  await lost.sample();
  assert.equal(lost.status().lost, true);
  assert.equal(lost.status().cancelOk, false);
  assert.ok(reopens >= 2, 'ritentato');
});

test('monitor WAL: parametri non validi rifiutati (pid, LSN, budget)', () => {
  const base = { query: async () => ({ rows: [] }), backendPid: 1, startLsn: '0/16B3748', maxWalMb: 100 };
  assert.throws(() => createWalMonitor({ ...base, backendPid: 0 }), /pid/);
  assert.throws(() => createWalMonitor({ ...base, startLsn: 'x' }), /posizione/);
  assert.throws(() => createWalMonitor({ ...base, maxWalMb: 0 }), /budget/);
});

// --- I-1: TLS, CA e URL (funzioni pure) ---------------------------------------------------------------------------------------

// blocco "chiave privata" assemblato a runtime (nessun marcatore di chiave letterale nel sorgente: gli scanner di segreti non devono scattare)
const PRIVATE_BLOCK = ['-----BEGIN', 'PRIVATE KEY-----\nAAAA\n-----END', 'PRIVATE KEY-----'].join(' ');
const FAKE_CA = '-----BEGIN CERTIFICATE-----\nMIIBszCCAVmgAwIBAgIUQ8w=\n-----END CERTIFICATE-----\n';

test('CA: accettato solo un PEM di certificati pubblici; chiave privata, vuoto, enorme o malformato rifiutati', () => {
  assert.match(normalizeCaPem(FAKE_CA), /BEGIN CERTIFICATE/);
  assert.match(normalizeCaPem(`rumore\n${FAKE_CA}altro rumore`), /^-----BEGIN CERTIFICATE-----/);
  assert.throws(() => normalizeCaPem(''), /CA mancante/);
  assert.throws(() => normalizeCaPem('non un pem'), /nessun blocco CERTIFICATE/);
  assert.throws(() => normalizeCaPem(`${FAKE_CA}${PRIVATE_BLOCK}`), /chiave privata/);
  assert.throws(() => normalizeCaPem(FAKE_CA + 'x'.repeat(70000)), /troppo grande/);
  assert.throws(() => normalizeCaPem(FAKE_CA.repeat(11)), /troppi certificati/);
});

test('CA: sorgente unica (env o file), mai entrambe né nessuna; il file è letto tramite un lettore iniettato', () => {
  assert.match(loadCaPem({ envPem: FAKE_CA, readFile: () => { throw new Error('non deve leggere'); } }), /BEGIN CERTIFICATE/);
  assert.match(loadCaPem({ caFile: '/x/ca.pem', readFile: () => FAKE_CA }), /BEGIN CERTIFICATE/);
  assert.throws(() => loadCaPem({ caFile: '/x', envPem: FAKE_CA, readFile: () => FAKE_CA }), /una sola/);
  assert.throws(() => loadCaPem({ readFile: () => FAKE_CA }), /CA mancante/);
});

test('URL TLS: solo sslmode=verify-full, una volta; disable/allow/prefer/require/verify-ca e parametri ripetuti rifiutati prima del socket', () => {
  const base = `postgresql://u:p@db.${REF}.supabase.co:5432/postgres`;
  assertVerifiedTlsUrl(`${base}?sslmode=verify-full`);
  for (const mode of ['disable', 'allow', 'prefer', 'require', 'verify-ca', '']) assert.throws(() => assertVerifiedTlsUrl(`${base}?sslmode=${mode}`), /verify-full/, mode);
  assert.throws(() => assertVerifiedTlsUrl(base), /verify-full/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?sslmode=verify-full&sslmode=disable`), /un solo sslmode/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?sslmode=disable&sslmode=verify-full`), /un solo sslmode/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?sslmode=verify-full&sslrootcert=/tmp/x`), /Parametri di connessione/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?SSLMODE=require`), /verify-full/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?sslmode=verify-full#sslmode=disable`), /frammento/);
  assert.throws(() => assertVerifiedTlsUrl(`${base}?%73slmode=verify-full&sslmode=require`), /un solo sslmode|verify-full/);
  assert.throws(() => assertVerifiedTlsUrl('non una url'), /non valida/);
});

test('opzioni TLS: sempre rejectUnauthorized = true con la CA data; la verifica non è mai disattivabile', () => {
  const o = tlsOptions(FAKE_CA);
  assert.equal(o.rejectUnauthorized, true);
  assert.match(o.ca, /BEGIN CERTIFICATE/);
  assert.throws(() => tlsOptions(null), /CA mancante/);
});

test('errori di connessione: TLS e hostname spiegati (anche con messaggio vuoto), timeout riconosciuto, credenziali mascherate', () => {
  assert.match(describeConnectError({ code: 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', message: 'unable to verify the first certificate' }), /verifica TLS fallita/);
  assert.match(describeConnectError({ code: '', message: '' }), /verifica TLS fallita/, 'Bun restituisce un messaggio vuoto per un hostname errato');
  assert.match(describeConnectError({ code: 'ERR_POSTGRES_CONNECTION_TIMEOUT', message: 'x' }), /timeout/);
  const redacted = describeConnectError({ code: 'EOTHER', message: 'fail postgres://u:s3cretPW@h/db' }, (x) => x.replace('s3cretPW', '***'));
  assert.ok(!redacted.includes('s3cretPW'));
  assert.equal(isConnectionLost({ code: 'ERR_POSTGRES_CONNECTION_CLOSED' }), true);
  assert.equal(isConnectionLost({ code: '42501', message: 'permission denied' }), false);
});

// --- CLI ---------------------------------------------------------------------------------------------------------------------

function runCli(extra, env = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-fix-'));
  try {
    return spawnSync(process.execPath, [CLI, '--input', join(dir, 'x.xlsx'), '--report', join(dir, 'r.json'), ...extra], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...env },
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('CLI: --cloud senza CA è rifiutato PRIMA di qualunque connessione (nessun segreto negli output)', () => {
  const r = runCli(['--cloud', '--target-ref', REF, '--dry-run'], { CATALOG_DATABASE_URL: DIRECT, [CLOUD_ENABLE_ENV]: 'enabled' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /CA mancante/);
  assert.ok(!r.stderr.includes('s3cretPW') && !r.stdout.includes('s3cretPW'));
});

test('CLI: CA indicata due volte o con una chiave privata è rifiutata', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-ca-'));
  try {
    const keyFile = join(dir, 'ca.pem');
    writeFileSync(keyFile, `${FAKE_CA}${PRIVATE_BLOCK}\n`);
    const env = { CATALOG_DATABASE_URL: DIRECT, [CLOUD_ENABLE_ENV]: 'enabled' };
    assert.match(runCli(['--cloud', '--target-ref', REF, '--dry-run', '--ca-file', keyFile], { ...env, CATALOG_DB_CA_PEM: FAKE_CA }).stderr, /una sola/);
    assert.match(runCli(['--cloud', '--target-ref', REF, '--dry-run', '--ca-file', keyFile], env).stderr, /chiave privata/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI: l\'URL con sslmode diverso da verify-full non arriva mai a un socket (rifiutato alla validazione della destinazione)', () => {
  const weak = `postgresql://u:s3cretPW@db.${REF}.supabase.co:5432/postgres?sslmode=require`;
  const r = runCli(['--cloud', '--target-ref', REF, '--dry-run'], { CATALOG_DATABASE_URL: weak, [CLOUD_ENABLE_ENV]: 'enabled', CATALOG_DB_CA_PEM: FAKE_CA });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /verify-full/);
  assert.ok(!r.stderr.includes('s3cretPW'));
});
