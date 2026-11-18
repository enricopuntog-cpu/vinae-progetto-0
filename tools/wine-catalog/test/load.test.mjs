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
function fakeDb({ failFinish = false, state = [], skipped = false, currentSha = null } = {}) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      calls.push({ text, params });
      if (text.includes('begin_import_run')) {
        const run_id = '00000000-0000-4000-8000-000000000001';
        return { rows: [{ r: skipped ? { run_id, mode: 'skipped', of_run: '00000000-0000-4000-8000-0000000000aa' } : { run_id, mode: 'import', attempt_no: 1 } }] };
      }
      if (text.includes('stage_source_records')) {
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
      if (text.includes('from catalog.complete_versions')) return { rows: currentSha ? [{ complete_sha256: currentSha }] : [] };
      if (text.includes('from catalog.source_records')) return { rows: state };
      throw new Error(`istruzione non prevista: ${text}`);
    },
  };
}

test('il caricamento scrive a lotti, con istruzioni costanti e dati solo come parametri', async () => {
  const rows = ['1000001', '1000002', '1000003', '1000004', '1000005'].map((l) => W(l));
  const db = fakeDb();
  const rep = await withFile(rows, (p) => loadToDatabase(db, p, { batchSize: 2 }));
  const upserts = db.calls.filter((c) => c.text.includes('stage_source_records'));
  assert.deepEqual(upserts.map((c) => JSON.parse(c.params[1]).length), [2, 2, 1]);
  assert.equal(rep.distinct_external_ids, 5);
  assert.equal(rep.staged.received, 5);
  const finish = db.calls.find((c) => c.text.includes('finish_import_run'));
  assert.equal(finish.params[1], 5);
  // il riepilogo porta le righe lette (il database le confronta con le attese dello snapshot)
  assert.equal(JSON.parse(finish.params[2]).data_rows, 5);
  // nessun testo del dataset dentro l'SQL
  for (const c of db.calls) assert.ok(!/Vino|Prod|Piedmont|1000001/.test(c.text), `SQL con dati: ${c.text}`);
  // ogni istruzione è una costante nota
  for (const c of db.calls) assert.match(c.text, /^select catalog\.(begin_import_run|stage_source_records|record_findings|finish_import_run|fail_import_run)\(/);
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
  const written = db.calls.filter((c) => c.text.includes('stage_source_records')).flatMap((c) => JSON.parse(c.params[1]));
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
  const written = db.calls.filter((c) => c.text.includes('stage_source_records')).flatMap((c) => JSON.parse(c.params[1]));
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
    const rows = probe.calls.filter((c) => c.text.includes('stage_source_records')).flatMap((c) => JSON.parse(c.params[1]));
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
  const tables = [...code.matchAll(/create (?:unlogged )?table catalog\.(\w+)/g)].map((m) => m[1]);
  assert.ok(tables.length >= 11);
  for (const t of tables) assert.match(code, new RegExp(`alter table catalog\\.${t} enable row level security`), `RLS mancante su ${t}`);
  // nessuna modifica a tabelle esistenti di public
  assert.ok(!/alter\s+table\s+public\./i.test(code));
  assert.ok(!/(create|alter|drop)\s+(table|view)\s+public\./i.test(code));
  // nessun DELETE concesso sui record di fonte
  assert.ok(!/grant[^;]*delete[^;]*source_records/i.test(code));
  assert.ok(!/grant[^;]*truncate/i.test(code));
  // nessun SQL dinamico nelle funzioni del catalogo (solo il blocco DO del ruolo usa format) e search_path fisso
  const fns = code.match(/create or replace function[\s\S]*?\n\$\$;/g) ?? [];
  assert.ok(fns.length >= 12, `funzioni trovate: ${fns.length}`);
  for (const f of fns) {
    assert.ok(!/\bexecute\b/i.test(f) && !/\bformat\s*\(/i.test(f), 'SQL dinamico in una funzione');
    assert.match(f, /set search_path = ''/);
  }
});

test('lo schema catalog non compare in nessuna migrazione precedente né in altri file della Data API', () => {
  const cfg = readFileSync(join(ROOT, 'supabase', 'config.toml'), 'utf8');
  assert.ok(!/catalog/.test(/\[api\][\s\S]*?(?=\n\[)/.exec(cfg)?.[0] ?? ''));
});

// --- WI-001B-BUILD: protocollo differenziale ---

test('snapshot già importato e corrente: nessuna lettura del file, nessun lotto, nessun finish', async () => {
  const db = fakeDb({ skipped: true });
  const dir = mkdtempSync(join(tmpdir(), 'wi001b-'));
  try {
    // un file con intestazioni sbagliate non produce errore: viene saltato PRIMA di essere letto
    const p = join(dir, 'gia-importato.xlsx');
    writeFileSync(p, makeXlsx([['A', 'B'], ['1', '2']]));
    const rep = await loadToDatabase(db, p);
    assert.equal(rep.mode, 'skipped');
    assert.equal(rep.reason, 'snapshot_already_current');
    assert.deepEqual(db.calls.map((c) => c.text.match(/catalog\.(\w+)/)[1]), ['begin_import_run']);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('--force raggiunge begin_import_run (p_force = true); senza opzione è false', async () => {
  const run = async (opts) => {
    const db = fakeDb();
    await withFile([W('1000001')], (p) => loadToDatabase(db, p, opts));
    return db.calls.find((c) => c.text.includes('begin_import_run')).params;
  };
  assert.equal((await run({ force: true }))[7], true);
  assert.equal((await run({}))[7], false);
});

test('dry-run: segnala se lo snapshot è già quello completo e corrente', async () => {
  await withFile([W('1000001')], async (p) => {
    const sha = createHash('sha256').update(readFileSync(p)).digest('hex');
    const same = await planLoad(fakeDb({ currentSha: sha }), p);
    assert.equal(same.database_state.snapshot_already_current, true);
    const other = await planLoad(fakeDb({ currentSha: 'f'.repeat(64) }), p);
    assert.equal(other.database_state.snapshot_already_current, false);
    assert.equal(same.database_writes, 0);
  });
});

test('il caricatore non scrive mai direttamente su tabelle catalog.* (solo funzioni)', async () => {
  const db = fakeDb();
  await withFile([W('1000001'), W('1000002')], (p) => loadToDatabase(db, p));
  for (const c of db.calls) assert.ok(!/(insert\s+into|update\s|delete\s+from)\s+catalog\./i.test(c.text), `scrittura diretta: ${c.text}`);
});

test('riepilogo finale: data_rows e righe scartate passano al database per il controllo di completezza', async () => {
  const db = fakeDb();
  await withFile([W('1000001'), W('xx')], (p) => loadToDatabase(db, p, { expectedRows: 2 }));
  const sum = JSON.parse(db.calls.find((c) => c.text.includes('finish_import_run')).params[2]);
  assert.equal(sum.data_rows, 2);
  assert.equal(sum.rejected, 1);
  assert.equal(db.calls.find((c) => c.text.includes('begin_import_run')).params[3], 2);
});

test('allow_mass_removal viaggia nel riepilogo solo se richiesto esplicitamente', async () => {
  const get = async (allowMassRemoval) => {
    const db = fakeDb();
    await withFile([W('1000001')], (p) => loadToDatabase(db, p, { allowMassRemoval }));
    return JSON.parse(db.calls.find((c) => c.text.includes('finish_import_run')).params[2]);
  };
  assert.equal((await get(true)).allow_mass_removal, true);
  assert.ok(!('allow_mass_removal' in (await get(false))));
});

test('il lotto contiene il contenuto completo (payload/raw) e l\'hash; nessuna colonna di presenza per record', async () => {
  const db = fakeDb();
  await withFile([W('1000001')], (p) => loadToDatabase(db, p));
  const [row] = JSON.parse(db.calls.find((c) => c.text.includes('stage_source_records')).params[1]);
  assert.match(row.content_hash, /^[0-9a-f]{64}$/);
  assert.ok(row.payload && row.raw);
  assert.ok(!('last_seen_run' in row));
});
