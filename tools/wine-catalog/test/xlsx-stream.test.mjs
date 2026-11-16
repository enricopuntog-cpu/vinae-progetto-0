import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readXlsxRows } from '../lib/xlsx-stream.mjs';
import { makeXlsx, makeRawSheetXlsx } from './make-xlsx.mjs';

async function withFile(buf, fn) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-'));
  const p = join(dir, 'f.xlsx');
  writeFileSync(p, buf);
  try {
    return await fn(p);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
async function collect(p) {
  const out = [];
  for await (const r of readXlsxRows(p)) out.push(r);
  return out;
}

test('legge stringhe inline, numeri e celle vuote nella posizione di colonna giusta', async () => {
  const buf = makeXlsx([['A', 'B', 'C'], ['x', 12, null], ['y', null, 'z & <w>']]);
  await withFile(buf, async (p) => {
    const rows = await collect(p);
    assert.deepEqual(rows, [
      { rowNumber: 1, cells: ['A', 'B', 'C'] },
      { rowNumber: 2, cells: ['x', '12', ''] },
      { rowNumber: 3, cells: ['y', '', 'z & <w>'] },
    ]);
  });
});

test('risolve le shared strings', async () => {
  const buf = makeXlsx([['H1', 'H2'], ['a', 'b']], { shared: true });
  await withFile(buf, async (p) => {
    const rows = await collect(p);
    assert.deepEqual(rows[1].cells, ['a', 'b']);
  });
});

test('un file che non è uno zip viene rifiutato con errore esplicito', async () => {
  await withFile(Buffer.from('non sono uno zip'), async (p) => {
    await assert.rejects(collect(p), /zip/i);
  });
});

test('funziona su input più grande dei chunk di lettura (righe spezzate tra chunk)', async () => {
  const rows = [['N', 'T']];
  for (let i = 0; i < 5000; i++) rows.push([String(i), 'testo-' + 'x'.repeat(i % 50)]);
  await withFile(makeXlsx(rows), async (p) => {
    const got = await collect(p);
    assert.equal(got.length, 5001);
    assert.equal(got[4999].cells[0], '4998');
    assert.equal(got[5000].rowNumber, 5001);
  });
});

test('una riga che non si chiude mai viene fermata dal tetto di memoria', async () => {
  const sheetHead = '<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>';
  await withFile(makeRawSheetXlsx(sheetHead + 'a'.repeat(20 * 1024 * 1024)), async (p) => {
    await assert.rejects(collect(p), /tetto|limite/i);
  });
});

test('contenuto di tutte le righe su più chunk, con celle autochiuse e gap di colonna', async () => {
  const rows = [['H']];
  for (let i = 0; i < 3000; i++) rows.push([`k${i}`, null, `v&${i}`]);
  await withFile(makeXlsx(rows), async (p) => {
    const got = await collect(p);
    assert.equal(got.length, 3001);
    got.slice(1).forEach((g, i) => assert.deepEqual(g.cells, [`k${i}`, '', `v&${i}`]));
  });
});
