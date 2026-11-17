import test from 'node:test';
import assert from 'node:assert/strict';
import { LWIN_COLUMNS, rowToRaw, normalizeLwinRow, excelSerialToIso } from '../lib/lwin.mjs';

const base = () => ({
  LWIN: '1000001', STATUS: 'Live', DISPLAY_NAME: 'Schieferkopf, Lieu Dit Buehl Riesling',
  PRODUCER_TITLE: 'NA', PRODUCER_NAME: 'Schieferkopf', WINE: 'Lieu Dit Buehl Riesling',
  COUNTRY: 'France', REGION: 'Alsace', SUB_REGION: 'NA', SITE: 'NA', PARCEL: 'NA',
  COLOUR: 'White', TYPE: 'Wine', SUB_TYPE: 'Still', DESIGNATION: 'AOP', CLASSIFICATION: 'NA',
  VINTAGE_CONFIG: 'sequential', FIRST_VINTAGE: 'NA', FINAL_VINTAGE: 'NA',
  DATE_ADDED: '40702.0', DATE_UPDATED: '45849.46644675926', REFERENCE: '',
});

test('le 22 colonne attese sono nell ordine del file LWIN', () => {
  assert.equal(LWIN_COLUMNS.length, 22);
  assert.equal(LWIN_COLUMNS[0], 'LWIN');
  assert.equal(LWIN_COLUMNS[21], 'REFERENCE');
});

test('rowToRaw associa le celle alle intestazioni e rifiuta intestazioni diverse', () => {
  const cells = LWIN_COLUMNS.map((c) => base()[c]);
  assert.equal(rowToRaw(LWIN_COLUMNS, cells).WINE, 'Lieu Dit Buehl Riesling');
  assert.throws(() => rowToRaw(['LWIN', 'STATUS'], ['1', 'Live']), /intestazion/i);
});

test('NA e stringhe vuote diventano null; i valori reali restano', () => {
  const { record, issues } = normalizeLwinRow(base(), 2);
  assert.deepEqual(issues, []);
  assert.equal(record.lwin, '1000001');
  assert.equal(record.producer_title, null);
  assert.equal(record.sub_region, null);
  assert.equal(record.region, 'Alsace');
  assert.equal(record.first_vintage, null);
  assert.equal(record.reference_lwin, null);
});

test('il codice LWIN numerico con .0 viene normalizzato a 7 cifre', () => {
  const { record } = normalizeLwinRow({ ...base(), LWIN: '1000001.0' }, 2);
  assert.equal(record.lwin, '1000001');
});

test('LWIN non valido: nessun record, rilievo bloccante', () => {
  for (const bad of ['', 'NA', 'abc', '12345', '1000001.5']) {
    const r = normalizeLwinRow({ ...base(), LWIN: bad }, 7);
    assert.equal(r.record, null, bad);
    assert.equal(r.issues[0].code, 'invalid_lwin');
    assert.equal(r.issues[0].row, 7);
  }
});

test('lo stato sconosciuto è un rilievo ma il record resta', () => {
  const r = normalizeLwinRow({ ...base(), STATUS: 'Boh' }, 2);
  assert.ok(r.record);
  assert.deepEqual(r.issues.map((i) => i.code), ['unknown_status']);
});

test('Combined richiede un riferimento valido e diverso dal proprio LWIN', () => {
  let r = normalizeLwinRow({ ...base(), STATUS: 'Combined', REFERENCE: '1316384' }, 2);
  assert.equal(r.record.reference_lwin, '1316384');
  assert.deepEqual(r.issues, []);
  r = normalizeLwinRow({ ...base(), STATUS: 'Combined', REFERENCE: '' }, 2);
  assert.deepEqual(r.issues.map((i) => i.code), ['combined_without_reference']);
  r = normalizeLwinRow({ ...base(), STATUS: 'Combined', REFERENCE: '1000001' }, 2);
  assert.deepEqual(r.issues.map((i) => i.code), ['self_reference']);
});

test('annate: anni validi, ordine rispettato, altrimenti rilievo', () => {
  let r = normalizeLwinRow({ ...base(), FIRST_VINTAGE: '1990', FINAL_VINTAGE: '2020' }, 2);
  assert.equal(r.record.first_vintage, 1990);
  assert.deepEqual(r.issues, []);
  r = normalizeLwinRow({ ...base(), FIRST_VINTAGE: '2020', FINAL_VINTAGE: '1990' }, 2);
  assert.deepEqual(r.issues.map((i) => i.code), ['vintage_order']);
  r = normalizeLwinRow({ ...base(), FIRST_VINTAGE: 'abcd' }, 2);
  assert.deepEqual(r.issues.map((i) => i.code), ['invalid_vintage_year']);
  assert.equal(r.record.first_vintage, null);
});

test('scope: solo Wine e Fortified Wine sono vino; il resto è fuori ambito ma conservato', () => {
  assert.equal(normalizeLwinRow(base(), 2).record.scope, 'wine');
  assert.equal(normalizeLwinRow({ ...base(), TYPE: 'Fortified Wine' }, 2).record.scope, 'wine');
  assert.equal(normalizeLwinRow({ ...base(), TYPE: 'Spirit' }, 2).record.scope, 'other');
  const odd = normalizeLwinRow({ ...base(), TYPE: 'Still' }, 2);
  assert.equal(odd.record.scope, 'other');
  assert.ok(odd.issues.some((i) => i.code === 'unknown_type'));
});

test('date: seriale Excel convertito in ISO UTC; non valida = rilievo', () => {
  // 40544 = 2011-01-01; +158 giorni = 2011-06-08.
  assert.equal(excelSerialToIso('40544'), '2011-01-01T00:00:00.000Z');
  assert.equal(excelSerialToIso('40702.0'), '2011-06-08T00:00:00.000Z');
  assert.equal(excelSerialToIso('NA'), null);
  const r = normalizeLwinRow({ ...base(), DATE_ADDED: 'ieri' }, 2);
  assert.deepEqual(r.issues.map((i) => i.code), ['invalid_date']);
});

test('row_hash è stabile, cambia se cambia un attributo e ignora lo spazio ai bordi', () => {
  const a = normalizeLwinRow(base(), 2).record.row_hash;
  const b = normalizeLwinRow({ ...base(), WINE: '  Lieu Dit Buehl Riesling ' }, 9).record.row_hash;
  const c = normalizeLwinRow({ ...base(), REGION: 'Elsass' }, 2).record.row_hash;
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[0-9a-f]{64}$/);
});

test('row_hash distingue due testi diversi anche se entrambi invalidi (nessuna cecità)', () => {
  const a = normalizeLwinRow({ ...base(), FIRST_VINTAGE: '19x0' }, 2).record.row_hash;
  const b = normalizeLwinRow({ ...base(), FIRST_VINTAGE: 'abcd' }, 2).record.row_hash;
  const ref1 = normalizeLwinRow({ ...base(), STATUS: 'Combined', REFERENCE: 'zzz' }, 2).record.row_hash;
  const ref2 = normalizeLwinRow({ ...base(), STATUS: 'Combined', REFERENCE: 'yyy' }, 2).record.row_hash;
  assert.notEqual(a, b);
  assert.notEqual(ref1, ref2);
});

test('le date non entrano nel row_hash: cambia solo il calendario, non il contenuto', () => {
  const a = normalizeLwinRow(base(), 2).record.row_hash;
  const b = normalizeLwinRow({ ...base(), DATE_UPDATED: '46000.5' }, 2).record.row_hash;
  assert.equal(a, b);
});
