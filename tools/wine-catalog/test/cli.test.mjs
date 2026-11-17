import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LWIN_COLUMNS } from '../lib/lwin.mjs';
import { makeXlsx } from './make-xlsx.mjs';

const CLI = join(dirname(fileURLToPath(import.meta.url)), '..', 'lwin-import.mjs');
const r = (lwin) => LWIN_COLUMNS.map((c) => ({ LWIN: lwin, STATUS: 'Live', TYPE: 'Wine', DISPLAY_NAME: 'd', WINE: 'w', PRODUCER_NAME: 'p', REFERENCE: '' })[c] ?? 'NA');

function run(args) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
}

test('scrive report e snapshot; secondo giro con --previous classifica il delta', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-cli-'));
  try {
    const f1 = join(dir, 'a.xlsx');
    const f2 = join(dir, 'b.xlsx');
    writeFileSync(f1, makeXlsx([LWIN_COLUMNS, r('1000001'), r('1000002')]));
    writeFileSync(f2, makeXlsx([LWIN_COLUMNS, r('1000001'), r('1000003')]));
    let res = run(['--input', f1, '--report', join(dir, 'r1.json'), '--snapshot-out', join(dir, 's1.json')]);
    assert.equal(res.status, 0, res.stderr);
    assert.equal(JSON.parse(readFileSync(join(dir, 'r1.json'), 'utf8')).rows.records, 2);
    res = run(['--input', f2, '--report', join(dir, 'r2.json'), '--previous', join(dir, 's1.json')]);
    assert.equal(res.status, 0, res.stderr);
    const c = JSON.parse(readFileSync(join(dir, 'r2.json'), 'utf8')).classification.counts;
    assert.deepEqual([c.new, c.unchanged, c.removed_from_source], [1, 1, 1]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('senza --input esce con codice 2 e messaggio d uso; non scrive nulla', () => {
  const res = run([]);
  assert.equal(res.status, 2);
  assert.match(res.stderr, /--input/);
});

test('rifiuta di scrivere il report dentro la cartella del repository', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-cli-'));
  try {
    const f = join(dir, 'a.xlsx');
    writeFileSync(f, makeXlsx([LWIN_COLUMNS, r('1000001')]));
    const inRepo = join(dirname(CLI), 'report-non-permesso.json');
    const res = run(['--input', f, '--report', inRepo]);
    assert.equal(res.status, 2);
    assert.ok(!existsSync(inRepo));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('rifiuta un percorso dentro il repo anche se il primo segmento inizia con ".."', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-cli-'));
  try {
    const f = join(dir, 'a.xlsx');
    writeFileSync(f, makeXlsx([LWIN_COLUMNS, r('1000001')]));
    // <repo>/..out/x.json: dentro il repo, ma il primo segmento relativo inizia con "..".
    const inside = join(dirname(CLI), '..', '..', '..out', 'x.json');
    assert.equal(run(['--input', f, '--report', inside]).status, 2);
    assert.ok(!existsSync(inside));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('rifiuta output che coincide con input, previous o con l altro output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-cli-'));
  try {
    const f = join(dir, 'a.xlsx');
    const bytes = makeXlsx([LWIN_COLUMNS, r('1000001')]);
    writeFileSync(f, bytes);
    assert.equal(run(['--input', f, '--report', f]).status, 2);
    assert.deepEqual(readFileSync(f), bytes);
    const same = join(dir, 'o.json');
    assert.equal(run(['--input', f, '--report', same, '--snapshot-out', same]).status, 2);
    assert.ok(!existsSync(same));
    writeFileSync(join(dir, 'p.json'), '{}');
    assert.equal(run(['--input', f, '--report', join(dir, 'p.json'), '--previous', join(dir, 'p.json')]).status, 2);
    assert.equal(readFileSync(join(dir, 'p.json'), 'utf8'), '{}');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('un previous illeggibile dà messaggio chiaro, exit 2 e nessun report', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wi001a-cli-'));
  try {
    const f = join(dir, 'a.xlsx');
    writeFileSync(f, makeXlsx([LWIN_COLUMNS, r('1000001')]));
    writeFileSync(join(dir, 'bad.json'), 'non json');
    const res = run(['--input', f, '--report', join(dir, 'r.json'), '--previous', join(dir, 'bad.json')]);
    assert.equal(res.status, 2);
    assert.ok(!existsSync(join(dir, 'r.json')));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
