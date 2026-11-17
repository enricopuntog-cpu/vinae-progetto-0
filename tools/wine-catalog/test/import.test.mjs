import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runImport, foldKey } from '../lib/import.mjs';
import { LWIN_COLUMNS } from '../lib/lwin.mjs';
import { makeXlsx } from './make-xlsx.mjs';

const row = (o) => LWIN_COLUMNS.map((c) => (c in o ? o[c] : c === 'REFERENCE' ? '' : 'NA'));
const W = (lwin, extra = {}) => row({
  LWIN: lwin, STATUS: 'Live', DISPLAY_NAME: `Prod, Vino ${lwin}`, PRODUCER_NAME: 'Prod', WINE: `Vino ${lwin}`,
  COUNTRY: 'Italy', REGION: 'Piedmont', SUB_REGION: 'Barolo', COLOUR: 'Red', TYPE: 'Wine', SUB_TYPE: 'Still',
  DESIGNATION: 'DOCG', DATE_ADDED: '40702.0', DATE_UPDATED: '45849.5', ...extra,
});

async function importRows(rows, opts) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-imp-'));
  try {
    const p = join(dir, 'lwin.xlsx');
    writeFileSync(p, makeXlsx([LWIN_COLUMNS, ...rows]));
    return await runImport(p, opts);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('conta righe, record validi e scartati; i rilievi bloccanti non producono record', async () => {
  const { report } = await importRows([W('1000001'), W('1000002'), W('xx')]);
  assert.equal(report.rows.data_rows, 3);
  assert.equal(report.rows.records, 2);
  assert.equal(report.rows.rejected, 1);
  assert.equal(report.issues.by_code.invalid_lwin.count, 1);
  assert.equal(report.issues.by_code.invalid_lwin.samples[0].row, 4);
});

test('distribuzioni: stato, tipo, scope e gerarchia territoriale', async () => {
  const { report } = await importRows([
    W('1000001'),
    W('1000002', { TYPE: 'Spirit', REGION: 'NA', SUB_REGION: 'NA' }),
    W('1000003', { STATUS: 'Combined', REFERENCE: '1000001' }),
  ]);
  assert.deepEqual(report.distributions.status, { Live: 2, Combined: 1 });
  assert.equal(report.distributions.scope.wine, 2);
  assert.equal(report.distributions.scope.other, 1);
  assert.equal(report.territory.distinct_countries, 1);
  assert.equal(report.territory.records_without_region, 1);
  assert.equal(report.territory.wine_scope_without_region, 0);
});

test('duplicati sullo stesso LWIN: identico vs conflitto, riportati e mai fusi', async () => {
  const { report } = await importRows([W('1000001'), W('1000001'), W('1000002'), W('1000002', { REGION: 'Tuscany' })]);
  assert.equal(report.classification.counts.duplicate, 1);
  assert.equal(report.classification.counts.conflict, 1);
  assert.deepEqual(report.classification.conflict_lwins, ['1000002']);
});

test('possibili duplicati per chiave naturale (LWIN diversi, stessa identità): segnalati, non accorpati', async () => {
  const same = { PRODUCER_NAME: 'Château Éxample', WINE: 'Grand  Vin' };
  const { report } = await importRows([W('1000001', same), W('1000002', { ...same, PRODUCER_NAME: 'chateau example', WINE: 'grand vin' }), W('1000003')]);
  assert.equal(report.potential_duplicates.groups, 1);
  assert.equal(report.potential_duplicates.records_involved, 2);
  assert.equal(report.potential_duplicates.action, 'none');
});

test('integrità dei riferimenti Combined: destinazione mancante, non Live, o catena', async () => {
  const { report } = await importRows([
    W('1000001'),
    W('1000002', { STATUS: 'Combined', REFERENCE: '1000001' }), // ok
    W('1000003', { STATUS: 'Combined', REFERENCE: '1999999' }), // destinazione assente
    W('1000004', { STATUS: 'Combined', REFERENCE: '1000002' }), // catena
    W('1000005', { STATUS: 'Deleted' }),
    W('1000006', { STATUS: 'Combined', REFERENCE: '1000005' }), // destinazione Deleted
  ]);
  const ref = report.references;
  assert.equal(ref.combined, 4);
  assert.equal(ref.target_missing, 1);
  assert.equal(ref.target_combined_chain, 1);
  assert.equal(ref.target_deleted, 1);
  assert.deepEqual(ref.samples.target_missing, [{ from: '1000003', into: '1999999' }]);
});

test('foldKey toglie accenti, maiuscole e spazi multipli', () => {
  assert.equal(foldKey('  Château  Éxample '), 'chateau example');
});

test('snapshot: lo snapshot di un import è l input del confronto del successivo', async () => {
  const first = await importRows([W('1000001'), W('1000002')]);
  const second = await importRows([W('1000001'), W('1000002', { WINE: 'Cambiato' }), W('1000004')], { previous: first.snapshot });
  assert.equal(second.report.classification.counts.unchanged, 1);
  assert.equal(second.report.classification.counts.updated, 1);
  assert.equal(second.report.classification.counts.new, 1);
  assert.equal(second.report.classification.counts.removed_from_source, 0);
});

test('il report non contiene percorsi locali né righe di dato complete oltre ai campioni di rilievo', async () => {
  const { report } = await importRows([W('1000001')]);
  const text = JSON.stringify(report);
  assert.ok(!/[A-Z]:\\|\/Users\//.test(text));
  assert.match(report.source.sha256, /^[0-9a-f]{64}$/);
  assert.equal(report.source.file_name, 'lwin.xlsx');
});

test('file con intestazioni diverse: errore esplicito, nessun report parziale', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-imp-'));
  try {
    const p = join(dir, 'x.xlsx');
    writeFileSync(p, makeXlsx([['A', 'B'], ['1', '2']]));
    await assert.rejects(runImport(p), /intestazion/i);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('LWIN ripetuto (stesso contenuto) non è un possibile duplicato per chiave naturale', async () => {
  const { report } = await importRows([W('1000001'), W('1000001'), W('1000002')]);
  assert.equal(report.potential_duplicates.groups, 0);
  assert.equal(report.classification.counts.duplicate, 1);
});

test('valori come "constructor" o "__proto__" nei campi non corrompono le distribuzioni', async () => {
  const { report } = await importRows([W('1000001', { COLOUR: 'constructor' }), W('1000002', { COLOUR: '__proto__' }), W('1000003', { COLOUR: 'constructor' })]);
  assert.equal(report.distributions.colour.constructor, 2);
  assert.equal(Object.entries(report.distributions.colour).find(([k]) => k === '__proto__')?.[1], 1);
});

test('una riga di soli spazi è ignorata, non scartata come LWIN invalido', async () => {
  const { report } = await importRows([W('1000001'), LWIN_COLUMNS.map(() => '  ')]);
  assert.equal(report.rows.data_rows, 1);
  assert.equal(report.rows.rejected, 0);
});
