// Controlli di sicurezza e di integrità dell'input del caricatore (WI-001B). Nessun database: db finti.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, readFileSync, readdirSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { assertLocalDatabaseUrl } from '../lib/paths.mjs';
import { assertEffectiveRole } from '../lib/role-check.mjs';
import { snapshotFile } from '../lib/import.mjs';
import { normalizeLwinRow, NORMALIZER_VERSION, LWIN_COLUMNS } from '../lib/lwin.mjs';

const CLI = join(dirname(fileURLToPath(import.meta.url)), '..', 'lwin-load.mjs');

// --- B. URL di connessione: allowlist restrittiva ---------------------------------------------------

test('URL ammessi: solo loopback esatto e parametri in allowlist', () => {
  for (const u of [
    'postgresql://postgres:x@127.0.0.1:58322/postgres',
    'postgres://u@localhost/db?sslmode=disable',
    'postgresql://u:p@[::1]:5432/db?application_name=wi001b&connect_timeout=5',
  ]) assertLocalDatabaseUrl(u);
});

test('URL rifiutati: host alternativi, override host=/hostaddr=, più host, socket, varianti numeriche, schemi errati', () => {
  const bad = [
    'postgresql://u@evil.com/db',
    'postgresql://u@127.0.0.1,evil.com/db',
    'postgresql://u@evil.com,127.0.0.1/db',
    'postgresql:///db?host=/var/run/postgresql',
    'postgresql://u@127.0.0.1/db?host=evil.com',
    'postgresql://u@127.0.0.1/db?HOST=evil.com',
    'postgresql://u@127.0.0.1/db?hostaddr=8.8.8.8',
    'postgresql://u@127.0.0.1/db?service=remoto',
    'postgresql://u@127.0.0.1/db?options=-c%20role%3Dpostgres',
    'postgresql://u@127.0.0.1.evil.com/db',
    'postgresql://127.0.0.1@evil.com/db',
    'postgresql://u@127.1/db',
    'postgresql://u@2130706433/db',
    'postgresql://u@0.0.0.0/db',
    'postgresql://u@localhost.evil.com/db',
    'postgresql://u@[::ffff:7f00:1]/db',
    'postgresql://u@[::ffff:127.0.0.1]/db',
    'http://127.0.0.1/db',
    'unix:///var/run/postgresql/.s.PGSQL.5432',
    '',
  ];
  for (const u of bad) assert.throws(() => assertLocalDatabaseUrl(u), undefined, `deve essere rifiutato: ${u}`);
});

// --- C. ruolo effettivo ----------------------------------------------------------------------------

const roleRow = (o = {}) => ({ cu: 'catalog_loader', su: false, bypass: false, powers: false, can_login: false, client_roles: 0, catalog_usage: true, public_create: false, ...o });
const fakeRole = (row) => async () => ({ rows: [row] });

test('ruolo effettivo corretto: accettato', async () => {
  await assertEffectiveRole(fakeRole(roleRow()), 'catalog_loader');
});

test('ruolo effettivo sbagliato o con privilegi eccessivi: rifiutato, con il motivo', async () => {
  const cases = [
    [{ cu: 'postgres' }, /ruolo effettivo "postgres"/],
    [{ su: true }, /superuser/],
    [{ bypass: true }, /BYPASSRLS/],
    [{ powers: true }, /CREATEROLE/],
    [{ can_login: true }, /login/],
    [{ client_roles: 1 }, /anon\/authenticated\/service_role/],
    [{ catalog_usage: false }, /USAGE/],
    [{ public_create: true }, /public/],
  ];
  for (const [o, re] of cases) await assert.rejects(() => assertEffectiveRole(fakeRole(roleRow(o)), 'catalog_loader'), re);
  await assert.rejects(() => assertEffectiveRole(async () => ({ rows: [] }), 'catalog_loader'), /nessuna risposta/);
});

test('il caricatore verifica il ruolo prima di begin, di ogni lotto e del finish; un ruolo perso blocca tutto', async () => {
  const { loadToDatabase } = await import('../lib/load.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-sec-'));
  try {
    const p = join(dir, 'lwin.xlsx');
    const { makeXlsx } = await import('./make-xlsx.mjs');
    const row = LWIN_COLUMNS.map((c) => (c === 'LWIN' ? '1000001' : c === 'STATUS' ? 'Live' : c === 'TYPE' ? 'Wine' : c === 'REFERENCE' ? '' : 'NA'));
    writeFileSync(p, makeXlsx([LWIN_COLUMNS, row]));
    let checks = 0;
    const seen = [];
    const db = {
      async assertRole() { checks += 1; seen.push('role'); },
      async query(text) {
        if (text.includes('begin_import_run')) { seen.push('begin'); return { rows: [{ r: { run_id: 'r', mode: 'import' } }] }; }
        if (text.includes('stage_source_records')) { seen.push('stage'); return { rows: [{ r: { received: 1, new: 1, updated: 0, unchanged: 0, reappeared: 0 } }] }; }
        if (text.includes('finish_import_run')) { seen.push('finish'); return { rows: [{ r: { records_seen: 1 } }] }; }
        return { rows: [{ n: 0 }] };
      },
    };
    await loadToDatabase(db, p, {});
    assert.deepEqual(seen.filter((s) => s !== 'role').length, 3);
    assert.ok(checks >= 3, `ruolo verificato ${checks} volte`);
    // ogni operazione privilegiata è preceduta da una verifica
    for (const op of ['begin', 'stage', 'finish']) assert.equal(seen[seen.indexOf(op) - 1], 'role', `${op} senza verifica del ruolo`);

    const lost = { ...db, async assertRole() { throw new Error('Verifica del ruolo fallita'); } };
    await assert.rejects(() => loadToDatabase(lost, p, {}), /Verifica del ruolo fallita/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// --- A. byte importati = byte hashati --------------------------------------------------------------

test('snapshotFile: lo sha256 è quello dei byte della copia; modificare l\'originale dopo non cambia la copia', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-snap-'));
  try {
    const p = join(dir, 'in.bin');
    writeFileSync(p, Buffer.alloc(300000, 7));
    const snap = await snapshotFile(p);
    try {
      assert.equal(snap.sha256, createHash('sha256').update(readFileSync(snap.path)).digest('hex'));
      assert.equal(snap.size, 300000);
      assert.notEqual(snap.path, p);
      appendFileSync(p, 'altro');                       // l'originale cambia DOPO l'acquisizione
      assert.equal(createHash('sha256').update(readFileSync(snap.path)).digest('hex'), snap.sha256);
    } finally {
      const copyDir = dirname(snap.path);
      snap.dispose();
      assert.deepEqual(readdirSync(tmpdir()).filter((n) => copyDir.endsWith(n) && n.startsWith('vinea-lwin-')), [], 'la copia temporanea è rimossa');
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('snapshotFile: file assente o non leggibile → errore e nessuna copia residua', async () => {
  // cartella temporanea PRIVATA di questo test: altri file di test girano in parallelo (processi separati) e creano cartelle
  // `vinea-lwin-` nella temp condivisa, il che rendeva il conteggio intermittente
  const priv = mkdtempSync(join(tmpdir(), 'wi001b-priv-'));
  const saved = { TMPDIR: process.env.TMPDIR, TMP: process.env.TMP, TEMP: process.env.TEMP };
  process.env.TMPDIR = process.env.TMP = process.env.TEMP = priv;
  try {
    const before = readdirSync(tmpdir()).filter((n) => n.startsWith('vinea-lwin-')).length;
    await assert.rejects(() => snapshotFile(join(priv, 'wi001b-inesistente-xyz.xlsx')));
    assert.equal(readdirSync(tmpdir()).filter((n) => n.startsWith('vinea-lwin-')).length, before);
  } finally {
    for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
    rmSync(priv, { recursive: true, force: true });
  }
});

// --- hash: scope e versione del normalizzatore -----------------------------------------------------

test('row_hash dipende da scope e dalla versione del normalizzatore', () => {
  const raw = Object.fromEntries(LWIN_COLUMNS.map((c) => [c, c === 'LWIN' ? '1000001' : c === 'STATUS' ? 'Live' : c === 'TYPE' ? 'Wine' : null]));
  const a = normalizeLwinRow(raw, 2).record;
  const b = normalizeLwinRow({ ...raw, TYPE: 'Spirit' }, 2).record;
  assert.notEqual(a.row_hash, b.row_hash);
  assert.equal(a.scope, 'wine');
  assert.match(NORMALIZER_VERSION, /^lwin-norm-\d+$/);
  // lo stesso input dà lo stesso hash (determinismo)
  assert.equal(normalizeLwinRow(raw, 9).record.row_hash, a.row_hash);
});

// --- CLI: --stale-minutes ----------------------------------------------------------------------------

test('--stale-minutes 0 o non numerico è rifiutato con exit 2', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-cli-'));
  try {
    for (const v of ['0', '-3', 'abc']) {
      const r = spawnSync(process.execPath, [CLI, '--input', join(dir, 'x.xlsx'), '--report', join(dir, 'r.json'), '--dry-run', '--stale-minutes', v], { encoding: 'utf8' });
      assert.equal(r.status, 2, `--stale-minutes ${v}: ${r.stderr}`);
      assert.match(r.stderr, /stale-minutes/);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

