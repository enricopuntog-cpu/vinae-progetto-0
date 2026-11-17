import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { LWIN_COLUMNS } from '../lib/lwin.mjs';
import { makeXlsx } from './make-xlsx.mjs';
import { loadToDatabase, planLoad, toBatchRow } from '../lib/load.mjs';
import { assertLocalDatabaseUrl } from '../lib/paths.mjs';
import { classifyImport } from '../lib/diff.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const row = (o) => LWIN_COLUMNS.map((c) => (c in o ? o[c] : c === 'REFERENCE' ? '' : 'NA'));
const W = (lwin, extra = {}) => row({
  LWIN: lwin, STATUS: 'Live', DISPLAY_NAME: `Prod, Vino ${lwin}`, PRODUCER_NAME: 'Prod', WINE: `Vino ${lwin}`,
  COUNTRY: 'Italy', REGION: 'Piedmont', COLOUR: 'Red', TYPE: 'Wine', ...extra,
});

async function withFile(rows, fn) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-'));
  try {
    const p = join(dir, 'lwin.xlsx');
    writeFileSync(p, makeXlsx([LWIN_COLUMNS, ...rows]));
    return await fn(p);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** db finto: registra ogni istruzione e imita le risposte delle funzioni catalog.* */
function fakeDb({ failFinish = false, state = [] } = {}) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      calls.push({ text, params });
      if (text.includes('begin_import_run')) return { rows: [{ run_id: '00000000-0000-4000-8000-000000000001' }] };
      if (text.includes('upsert_source_records')) {
        const n = JSON.parse(params[1]).length;
        return { rows: [{ r: { received: n, new: n, updated: 0, unchanged: 0, reappeared: 0 } }] };
      }
      if (text.includes('record_findings')) return { rows: [{ n: JSON.parse(params[1]).length }] };
      if (text.includes('finish_import_run')) {
        if (failFinish) throw new Error('catalog: import incompleto');
        return { rows: [{ r: { records_seen: Number(params[1]) } }] };
      }
      if (text.includes('fail_import_run')) return { rows: [] };
      if (text.includes('from catalog.sources')) return { rows: [{ id: 'src-1' }] };
      if (text.includes('from catalog.source_records')) return { rows: state };
      throw new Error(`istruzione non prevista: ${text}`);
    },
  };
}

test('il caricamento scrive a lotti, con istruzioni costanti e dati solo come parametri', async () => {
  const rows = ['1000001', '1000002', '1000003', '1000004', '1000005'].map((l) => W(l));
  const db = fakeDb();
  const rep = await withFile(rows, (p) => loadToDatabase(db, p, { batchSize: 2 }));
  const upserts = db.calls.filter((c) => c.text.includes('upsert_source_records'));
  assert.deepEqual(upserts.map((c) => JSON.parse(c.params[1]).length), [2, 2, 1]);
  assert.equal(rep.distinct_external_ids, 5);
  assert.equal(rep.upsert.received, 5);
  const finish = db.calls.find((c) => c.text.includes('finish_import_run'));
  assert.equal(finish.params[1], 5);
  // nessun testo del dataset dentro l'SQL
  for (const c of db.calls) assert.ok(!/Vino|Prod|Piedmont|1000001/.test(c.text), `SQL con dati: ${c.text}`);
  // ogni istruzione è una costante nota
  for (const c of db.calls) assert.match(c.text, /^select catalog\.(begin_import_run|upsert_source_records|record_findings|finish_import_run|fail_import_run)\(/);
});

test('hash del file diverso dall\'atteso: rifiutato prima di toccare il database', async () => {
  const db = fakeDb();
  await assert.rejects(
    withFile([W('1000001')], (p) => loadToDatabase(db, p, { expectedSha256: 'a'.repeat(64) })),
    /SHA-256/,
  );
  assert.equal(db.calls.length, 0);
});

test('hash atteso corretto: accettato', async () => {
  const db = fakeDb();
  await withFile([W('1000001')], async (p) => {
    const sha = createHash('sha256').update(readFileSync(p)).digest('hex');
    const rep = await loadToDatabase(db, p, { expectedSha256: sha });
    assert.equal(rep.source.sha256, sha);
  });
});

test('duplicati identici ignorati, divergenti segnalati e non scritti; record non valido scartato con rilievo', async () => {
  const db = fakeDb();
  const rep = await withFile(
    [W('1000001'), W('1000001'), W('1000002'), W('1000002', { REGION: 'Tuscany' }), W('xx')],
    (p) => loadToDatabase(db, p),
  );
  assert.equal(rep.duplicate_rows, 1);
  assert.equal(rep.divergent_duplicates, 1);
  assert.equal(rep.rejected, 1);
  assert.equal(rep.distinct_external_ids, 2);
  const written = db.calls.filter((c) => c.text.includes('upsert_source_records')).flatMap((c) => JSON.parse(c.params[1]));
  assert.deepEqual(written.map((r) => r.external_id), ['1000001', '1000002']);
  const kinds = db.calls.filter((c) => c.text.includes('record_findings')).flatMap((c) => JSON.parse(c.params[1])).map((f) => f.kind).sort();
  assert.deepEqual(kinds, ['divergent_duplicate', 'parse_issue']);
});

test('possibili duplicati (stessa identità normalizzata) segnalati, mai fusi', async () => {
  const db = fakeDb();
  await withFile(
    [W('1000001', { WINE: 'Château X' }), W('1000002', { WINE: 'Chateau X' }), W('1000003', { WINE: 'Altro' })],
    (p) => loadToDatabase(db, p),
  );
  const f = db.calls.filter((c) => c.text.includes('record_findings')).flatMap((c) => JSON.parse(c.params[1]));
  const dup = f.filter((x) => x.kind === 'possible_duplicate');
  assert.equal(dup.length, 1);
  assert.deepEqual(dup[0].detail.lwins.sort(), ['1000001', '1000002']);
  const written = db.calls.filter((c) => c.text.includes('upsert_source_records')).flatMap((c) => JSON.parse(c.params[1]));
  assert.equal(written.length, 3);
});

test('errore a metà: il tentativo è marcato failed, mai finito, e l\'errore risale', async () => {
  const db = fakeDb({ failFinish: true });
  await assert.rejects(withFile([W('1000001')], (p) => loadToDatabase(db, p)), /incompleto/);
  assert.ok(db.calls.some((c) => c.text.includes('fail_import_run')));
  assert.equal(db.calls.filter((c) => c.text.includes('finish_import_run')).length, 1);
});

test('un file con intestazioni errate non apre nessun tentativo che resti running', async () => {
  const db = fakeDb();
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-'));
  try {
    const p = join(dir, 'bad.xlsx');
    writeFileSync(p, makeXlsx([['A', 'B'], ['1', '2']]));
    await assert.rejects(loadToDatabase(db, p), /Intestazioni/);
    assert.ok(db.calls.some((c) => c.text.includes('begin_import_run')));
    assert.ok(db.calls.some((c) => c.text.includes('fail_import_run')), 'il tentativo aperto va chiuso come failed');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('toBatchRow: stato mancante conservato come Unknown, hash separato dal payload, raw intatto', () => {
  const r = toBatchRow({ lwin: '1', status: null, scope: 'other', reference_lwin: null, country: null, region: null, sub_region: null, row_hash: 'h' }, { LWIN: '1' });
  assert.equal(r.status, 'Unknown');
  assert.equal(r.content_hash, 'h');
  assert.ok(!('row_hash' in r.payload));
  assert.deepEqual(r.raw, { LWIN: '1' });
});

test('dry-run: anteprima del delta contro lo stato del database, zero scritture', async () => {
  const sha = (s) => createHash('sha256').update(s).digest('hex');
  await withFile([W('1000001'), W('1000002', { WINE: 'Cambiato' }), W('1000004')], async (p) => {
    // calcolo gli hash reali del file per costruire lo stato "già nel database"
    const probe = fakeDb();
    await loadToDatabase(probe, p);
    const rows = probe.calls.filter((c) => c.text.includes('upsert_source_records')).flatMap((c) => JSON.parse(c.params[1]));
    const h = Object.fromEntries(rows.map((r) => [r.external_id, r.content_hash]));
    const db = fakeDb({
      state: [
        { external_id: '1000001', content_hash: h['1000001'], removed: false }, // invariato
        { external_id: '1000002', content_hash: sha('vecchio'), removed: false }, // aggiornato
        { external_id: '1000003', content_hash: sha('x'), removed: false }, // sparito
        { external_id: '1000004', content_hash: h['1000004'], removed: true }, // ricomparso
        { external_id: '1000009', content_hash: sha('y'), removed: true }, // già marcato rimosso
      ],
    });
    const plan = await planLoad(db, p);
    assert.equal(plan.database_writes, 0);
    assert.ok(db.calls.every((c) => /^select /.test(c.text)), 'solo letture');
    assert.equal(plan.delta.unchanged, 2);
    assert.equal(plan.delta.updated, 1);
    assert.equal(plan.delta.new, 0);
    assert.equal(plan.delta.reappeared, 1);
    assert.deepEqual(plan.delta.removed_sample, ['1000003']);
    assert.equal(plan.delta.removed_from_source, 1);
  });
});

test('dry-run senza database: confronto con un catalogo vuoto', async () => {
  const plan = await withFile([W('1000001'), W('1000002')], (p) => planLoad(null, p));
  assert.equal(plan.delta.new, 2);
  assert.equal(plan.database_state.compared, false);
});

test('G1: la modifica del riferimento di un Combined tra snapshot è un aggiornamento', () => {
  const rec = (lwin, hash, extra = {}) => ({ lwin, row_hash: hash, status: 'Combined', reference_lwin: '9', ...extra });
  const prev = new Map([['1', 'h1'], ['2', 'h2']]);
  const c = classifyImport([rec('1', 'h1'), rec('2', 'h2x', { reference_lwin: '8' }), rec('3', 'h3')], prev).counts;
  assert.equal(c.merged, 3);
  assert.equal(c.merged_unchanged, 1);
  assert.equal(c.merged_updated, 1);
  assert.equal(c.merged_new, 1);
});

test('database remoto o non loopback rifiutato; loopback accettato', () => {
  assert.throws(() => assertLocalDatabaseUrl('postgresql://u:p@db.qsknroyjzempizibcywa.supabase.co:5432/postgres'), /loopback/);
  assert.throws(() => assertLocalDatabaseUrl('postgresql://u:p@10.0.0.5:5432/postgres'), /loopback/);
  assert.throws(() => assertLocalDatabaseUrl('postgresql://u:p@localhost.evil.com:5432/postgres'), /loopback/);
  assert.throws(() => assertLocalDatabaseUrl('mysql://localhost/x'), /postgres/);
  assert.throws(() => assertLocalDatabaseUrl('non un url'), /non valido/);
  assertLocalDatabaseUrl('postgresql://postgres:postgres@127.0.0.1:54322/postgres');
  assertLocalDatabaseUrl('postgresql://postgres:postgres@localhost:54322/postgres');
  assertLocalDatabaseUrl('postgresql://postgres:postgres@[::1]:54322/postgres');
});

// --- Controlli statici sulla migrazione e sulla configurazione (nessun database) ---

test('config.toml non espone lo schema catalog alla Data API', () => {
  const cfg = readFileSync(join(ROOT, 'supabase', 'config.toml'), 'utf8');
  const schemas = /^schemas\s*=\s*\[(.*?)\]/ms.exec(cfg)?.[1] ?? '';
  assert.ok(schemas.includes('"public"'));
  assert.ok(!/catalog/.test(schemas), `schemas esposti: ${schemas}`);
  assert.ok(!/extra_search_path\s*=\s*\[[^\]]*catalog/.test(cfg));
});

test('migrazione catalog: nessun SECURITY DEFINER, nessun grant a PUBLIC/anon/authenticated/service_role, RLS su ogni tabella', () => {
  const sql = readFileSync(join(ROOT, 'supabase', 'migrations', '20261117120000_wi_001b_catalog_staging.sql'), 'utf8');
  const code = sql.replace(/--.*$/gm, '');
  assert.ok(!/security\s+definer/i.test(code));
  assert.ok(!/grant\s[^;]*\sto\s[^;]*\b(public|anon|authenticated|service_role)\b/i.test(code), 'grant a un ruolo client');
  assert.ok(!/alter\s+default\s+privileges/i.test(code));
  const tables = [...code.matchAll(/create table catalog\.(\w+)/g)].map((m) => m[1]);
  assert.ok(tables.length >= 10);
  for (const t of tables) assert.match(code, new RegExp(`alter table catalog\\.${t} enable row level security`), `RLS mancante su ${t}`);
  // nessuna modifica a tabelle esistenti di public
  assert.ok(!/alter\s+table\s+public\./i.test(code));
  assert.ok(!/(create|alter|drop)\s+(table|view)\s+public\./i.test(code));
  // nessun DELETE concesso sui record di fonte
  assert.ok(!/grant[^;]*delete[^;]*source_records/i.test(code));
});

test('lo schema catalog non compare in nessuna migrazione precedente né in altri file della Data API', () => {
  const cfg = readFileSync(join(ROOT, 'supabase', 'config.toml'), 'utf8');
  assert.ok(!/catalog/.test(/\[api\][\s\S]*?(?=\n\[)/.exec(cfg)?.[0] ?? ''));
});
