// WI-001C-FIX-01 / I-1: comportamento REALE di Bun.SQL contro un server TLS isolato (processo Node separato, loopback, porta casuale).
// Nessuna connessione verso Supabase né verso altre reti. Richiede Bun e openssl: sotto Node, o senza openssl, i test sono SALTATI
// (in CI girano con `bun tools/wine-catalog/test/tls-bun.test.mjs`).
//
// Provato:
//  - CA corretta + hostname corretto → accettato; il ruolo si imposta con SET ROLE esplicito (non come parametro di avvio);
//  - CA errata → rifiutato; hostname errato → rifiutato; TLS disabilitato o abbassato nell'URL → rifiutato PRIMA di aprire un socket;
//    server che non offre TLS → rifiutato (nessuna sessione in chiaro);
//  - connessione caduta → la sessione NON si ricollega da sola (un solo startup sul server), le richieste successive falliscono;
//  - sessione di sola lettura (dry-run): le scritture non partono dal client.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { opensslAvailable, makeTlsFixtures } from './helpers/tls-fixtures.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MOCK = join(HERE, 'helpers', 'mock-pg-server.mjs');
const hasBun = typeof Bun !== 'undefined' && typeof Bun.SQL === 'function';
const ok = hasBun && opensslAvailable();
// In CI (CI=true) la prova NON si salta in silenzio: senza Bun o openssl il file fallisce.
if (!ok && process.env.CI === 'true' && process.env.WI_TLS_REQUIRE_BUN === 'true') throw new Error('tls-bun.test.mjs: Bun e openssl sono obbligatori in CI');
const skip = ok ? false : 'richiede Bun e openssl (in CI: bun tools/wine-catalog/test/tls-bun.test.mjs)';

const BOOL = 16;
const TEXT = 25;
const INT = 23;
const RESPONSES = [
  { match: 'pg_backend_pid() as pid, current_user', columns: [['pid', INT], ['cu', TEXT], ['ro', TEXT]], values: ['777', 'catalog_loader', 'on'] },
  { match: 'current_user::text as cu', columns: [['cu', TEXT], ['su', BOOL], ['bypass', BOOL], ['powers', BOOL], ['can_login', BOOL], ['client_roles', INT], ['catalog_usage', BOOL], ['public_create', BOOL]], values: ['catalog_loader', 'f', 'f', 'f', 'f', '0', 't', 'f'] },
  { match: 'pg_backend_pid() as pid', columns: [['pid', INT]], values: ['777'] },
  { match: "current_setting('transaction_read_only') as ro", columns: [['ro', TEXT]], values: ['on'] },
  { match: 'select 1', columns: [['x', INT]], values: ['1'] },
];

async function startMock(fix, { cert = 'good', allowTls = true } = {}) {
  const pair = cert === 'good' ? fix.good : fix.wrongName;
  const child = spawn('node', [MOCK, JSON.stringify({ cert: pair.cert, key: pair.key, allowTls, responses: RESPONSES })], { stdio: ['ignore', 'pipe', 'inherit'] });
  const state = { port: null, log: {} };
  let buf = '';
  await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.stdout.on('data', (d) => {
      buf += d;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const l of lines) {
        try {
          const j = JSON.parse(l);
          if (j.port) { state.port = j.port; resolve(); }
          if (j.log) state.log = j.log;
        } catch { /* riga parziale */ }
      }
    });
  });
  return {
    port: state.port,
    log: async () => { await new Promise((r) => setTimeout(r, 400)); return state.log; },
    stop: () => child.kill(),
  };
}

const urlFor = (port, mode = 'verify-full', host = '127.0.0.1') => `postgres://catalog_login:pw@${host}:${port}/postgres?sslmode=${mode}`;
let fix;
let db;
const { connectCloud, connectCloudMonitor } = ok ? await import('../lib/db-bun.mjs') : {};
if (ok) fix = makeTlsFixtures();
test.after(() => { fix?.dispose(); });

async function withMock(opts, fn) {
  const m = await startMock(fix, opts);
  try { return await fn(m); } finally { m.stop(); }
}

test('CA corretta + hostname corretto: accettato; ruolo con SET ROLE esplicito (non come parametro di avvio); un solo backend', { skip }, async () => {
  await withMock({}, async (m) => {
    db = await connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5 });
    assert.equal(db.backendPid, 777);
    assert.equal(db.clientTlsVerified, true, 'attestazione TLS client usata da assertCloudSession per il pooler');
    await db.assertIntact();
    await db.close();
    const log = await m.log();
    assert.equal(log.tlsOk, 1, 'sessione TLS stabilita');
    assert.equal(log.plainStartup, 0, 'nessuno startup in chiaro');
    assert.ok(log.queries.some((q) => q.includes('set role "catalog_loader"')), 'SET ROLE esplicito');
    assert.ok(log.startup.every((p) => !p.includes('role')), 'il ruolo non viaggia come parametro di avvio');
    assert.equal(log.startup.length, 1);
  });
});

test('CA errata: rifiutato con messaggio chiaro; nessuna query eseguita', { skip }, async () => {
  await withMock({}, async (m) => {
    await assert.rejects(() => connectCloud(urlFor(m.port), { caPem: fix.otherCa, connectTimeoutSec: 5 }), /verifica TLS fallita/);
    const log = await m.log();
    assert.equal(log.queries.length, 0);
  });
});

test('hostname errato (certificato per altro.example.com, URL localhost): rifiutato anche con CA corretta', { skip }, async () => {
  await withMock({ cert: 'wrongname' }, async (m) => {
    await assert.rejects(() => connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5 }), /verifica TLS fallita/);
    const log = await m.log();
    assert.equal(log.queries.length, 0, 'nessuna query: la sessione non è mai stata stabilita');
  });
});

test('TLS disabilitato o abbassato nell\'URL (disable/allow/prefer/require/verify-ca): rifiutato PRIMA di aprire un socket', { skip }, async () => {
  await withMock({}, async (m) => {
    for (const mode of ['disable', 'allow', 'prefer', 'require', 'verify-ca']) {
      await assert.rejects(() => connectCloud(urlFor(m.port, mode), { caPem: fix.ca, connectTimeoutSec: 5 }), /verify-full/, mode);
    }
    await assert.rejects(() => connectCloud(`${urlFor(m.port)}&sslmode=disable`, { caPem: fix.ca }), /un solo sslmode/);
    const log = await m.log();
    assert.equal(log.connections, 0, 'nemmeno una connessione TCP aperta');
  });
});

test('senza CA: rifiutato; la verifica non può essere disattivata (nessun percorso con rejectUnauthorized false)', { skip }, async () => {
  await withMock({}, async (m) => {
    await assert.rejects(() => connectCloud(urlFor(m.port), { caPem: null }), /CA mancante/);
    const log = await m.log();
    assert.equal(log.connections, 0);
  });
});

test('server che non offre TLS (risponde N): rifiutato, nessuna sessione in chiaro', { skip }, async () => {
  await withMock({ allowTls: false }, async (m) => {
    await assert.rejects(() => connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 2 }), /Connessione cloud rifiutata/);
    const log = await m.log();
    assert.equal(log.plainStartup, 0, 'nessuno startup in chiaro');
    assert.equal(log.queries.length, 0);
  });
});

test('connessione caduta: la sessione NON si ricollega da sola; richieste successive rifiutate; un solo startup sul server', { skip }, async () => {
  await withMock({}, async (m) => {
    const d = await connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5 });
    await assert.rejects(() => d.query('select drop_connection'), (e) => e?.code === 'ERR_POSTGRES_CONNECTION_CLOSED');
    assert.equal(d.state.broken, true);
    await assert.rejects(() => d.query('select 1'), /Sessione cloud interrotta/);
    await assert.rejects(() => d.assertIntact(), /Sessione cloud interrotta/);
    await Promise.race([d.close(), new Promise((r) => setTimeout(r, 6000))]);
    const log = await m.log();
    assert.equal(log.startup.length, 1, 'nessuna riconnessione silenziosa (sessione, ruolo e timeout non vanno persi)');
    assert.equal(log.sslRequests, 1);
  });
});

test('filtri del chiamante: RESET ROLE, SET ROLE, BEGIN/COMMIT non arrivano mai al server', { skip }, async () => {
  await withMock({}, async (m) => {
    const d = await connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5 });
    for (const q of ['set/**/role postgres', 'reset/**/role', 'SET /* x */ ROLE postgres', "select set_config($1, 'x', false)", "select set_config(e'role', 'x', false)",
      'reset role', 'RESET ROLE', 'set role postgres', 'set session authorization postgres', 'begin', 'commit', 'rollback', '  /* c */ reset role',
    'select 1; reset role', 'select 1;reset role', "select set_config('role', 'postgres', false)", 'select 1; select 2', '/* x */ begin']) {
      await assert.rejects(() => d.query(q), /non ammesso/, q);
    }
    // FIX-02: il chiamante invia solo SELECT/WITH/VALUES senza scritture dirette; set_config è vietato ovunque (nome qualificato, tra virgolette, in sottoquery)
    for (const q of ['insert into catalog.sources values (1)', 'update catalog.sources set name = 1', 'delete from catalog.sources', 'truncate catalog.sources', 'do $ begin end $', 'create table x (a int)',
      'select pg_catalog.set_config($1, $2, false)', 'select "set_config"($1, $2, false)', 'select (select set_config($1, $2, false))',
      'with x as (delete from catalog.sources returning 1) select count(*) from x']) {
      await assert.rejects(() => d.query(q), /non ammess/, q);
    }
    await d.close();
    const log = await m.log();
    assert.ok(!log.queries.some((q) => /^\s*(reset|begin|commit|rollback)\b/i.test(q) || /set role postgres/i.test(q)));
  });
});

test('sessione di SOLA LETTURA (dry-run): default_transaction_read_only attivato; scritture rifiutate dal client e mai inviate', { skip }, async () => {
  await withMock({}, async (m) => {
    const d = await connectCloud(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5, readOnly: true });
    await assert.rejects(() => d.query('insert into catalog.sources values (1)'), /sola lettura/);
    await assert.rejects(() => d.query('update catalog.sources set name = 1'), /sola lettura/);
    await assert.rejects(() => d.query('delete from catalog.sources'), /sola lettura/);
    await assert.rejects(() => d.query('create table x (a int)'), /sola lettura/);
    await assert.rejects(() => d.query('with x as (delete from catalog.sources returning 1) select count(*) from x'), /sola lettura/);
    await assert.rejects(() => d.query("select set_config('default_transaction_read_only', 'off', false)"), /non ammesso/);
    await assert.rejects(() => d.query('select set_config($1, $2, false)', ['role', 'postgres']), /non ammesso/);
    await assert.rejects(() => d.query('show transaction_read_only'), /non ammesso/);
    await assert.rejects(() => d.query('  -- commento\n  insert into x values (1)'), /sola lettura/);
    assert.deepEqual((await d.query('select 1')).rows.length, 1);
    assert.deepEqual((await d.query('  /* c */ select 1')).rows.length, 1, 'un SELECT preceduto da spazi o commenti è ammesso');
    await d.assertIntact();
    await d.close();
    const log = await m.log();
    assert.ok(log.queries.some((q) => q.includes("set_config('default_transaction_read_only', 'on', false)")), 'sola lettura per default di sessione');
    assert.ok(!log.queries.some((q) => /^\s*(insert|update|delete|create)\b/i.test(q) || q.includes('insert into')), 'nessuna scrittura inviata');
  });
});

test('monitor: stessa verifica TLS, nessun SET ROLE (resta il login), non scrive', { skip }, async () => {
  await withMock({}, async (m) => {
    const mon = await connectCloudMonitor(urlFor(m.port), { caPem: fix.ca, connectTimeoutSec: 5 });
    assert.equal((await mon.query('select 1 as ok')).rows.length, 1);
    await assert.rejects(() => mon.query('select 1'), /non ammessa sulla connessione di monitoraggio/, 'elenco chiuso: solo i testi esatti del monitor');
    await assert.rejects(() => mon.query("select set_config('role', 'postgres', false)"), /non ammessa/);
    await mon.close();
    const log = await m.log();
    assert.ok(!log.queries.some((q) => /set role/i.test(q)));
    assert.equal(log.tlsOk, 1);
    await assert.rejects(() => connectCloudMonitor(urlFor(m.port), { caPem: fix.otherCa, connectTimeoutSec: 5 }), /verifica TLS fallita/);
  });
});
