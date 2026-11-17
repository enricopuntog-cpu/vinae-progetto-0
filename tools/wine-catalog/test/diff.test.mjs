import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyImport } from '../lib/diff.mjs';

const rec = (lwin, hash, extra = {}) => ({ lwin, row_hash: hash, status: 'Live', reference_lwin: null, ...extra });

test('primo import: tutto nuovo', () => {
  const r = classifyImport([rec('1', 'a'), rec('2', 'b')], null);
  assert.deepEqual(r.counts, { new: 2, updated: 0, unchanged: 0, duplicate: 0, conflict: 0, merged: 0, removed_from_source: 0 });
});

test('confronto con snapshot precedente: nuovo, aggiornato, invariato, rimosso dalla fonte', () => {
  const prev = new Map([['1', 'a'], ['2', 'old'], ['3', 'c']]);
  const r = classifyImport([rec('1', 'a'), rec('2', 'new'), rec('4', 'd')], prev);
  assert.equal(r.counts.unchanged, 1);
  assert.equal(r.counts.updated, 1);
  assert.equal(r.counts.new, 1);
  assert.equal(r.counts.removed_from_source, 1);
  assert.deepEqual(r.removedLwins, ['3']);
});

test('stesso LWIN due volte: identico = duplicato, diverso = conflitto (nessuna scelta silenziosa)', () => {
  const r = classifyImport([rec('1', 'a'), rec('1', 'a'), rec('2', 'x'), rec('2', 'y')], null);
  assert.equal(r.counts.duplicate, 1);
  assert.equal(r.counts.conflict, 1);
  assert.deepEqual(r.conflictLwins, ['2']);
  assert.equal(r.counts.new, 1); // solo LWIN 1; il 2 in conflitto non è né nuovo né aggiornato
});

test('Combined = accorpato: contato a parte e con destinazione', () => {
  const r = classifyImport([rec('1', 'a', { status: 'Combined', reference_lwin: '9' })], null);
  assert.equal(r.counts.merged, 1);
  assert.deepEqual(r.mergedPairs, [{ from: '1', into: '9' }]);
});

test('un record rimosso dalla fonte non è mai una cancellazione: è solo elencato', () => {
  const r = classifyImport([], new Map([['1', 'a']]));
  assert.equal(r.counts.removed_from_source, 1);
  assert.equal(r.deleteAction, 'none');
});
