#!/usr/bin/env node
// Importatore locale LWIN (WI-001A). Sola lettura del file di input, nessun
// database, nessuna rete. Scrive solo i file indicati, e SOLO fuori dal repository:
// il file LWIN, lo snapshot (212k righe) e i report grezzi non vanno committati.
//
// Uso:
//   node tools/wine-catalog/lwin-import.mjs --input <file.xlsx> --report <out.json>
//        [--snapshot-out <snap.json>] [--previous <snap.json>]
import { readFileSync, writeFileSync, realpathSync, existsSync } from 'node:fs';
import { resolve, relative, isAbsolute, dirname, basename, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { runImport } from './lib/import.mjs';

const REPO_ROOT = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), '..', '..'));

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

/** Percorso canonico anche se il file non esiste: realpath del primo antenato esistente + resto. */
function canonical(p) {
  let cur = resolve(p);
  const rest = [];
  while (!existsSync(cur)) {
    rest.unshift(basename(cur));
    const up = dirname(cur);
    if (up === cur) break;
    cur = up;
  }
  return join(realpathSync(cur), ...rest);
}

function insideRepo(p) {
  const rel = relative(REPO_ROOT, canonical(p));
  if (rel === '') return true;
  const escapes = rel === '..' || rel.startsWith('..' + sep) || isAbsolute(rel);
  return !escapes;
}

let args;
try {
  args = parseArgs({
    options: {
      input: { type: 'string' },
      report: { type: 'string' },
      'snapshot-out': { type: 'string' },
      previous: { type: 'string' },
    },
    strict: true,
  }).values;
} catch (e) {
  fail(`${e.message}\nUso: lwin-import.mjs --input <file.xlsx> --report <out.json> [--snapshot-out <snap.json>] [--previous <snap.json>]`);
}
if (!args.input) fail('Manca --input <file.xlsx>');
if (!args.report) fail('Manca --report <out.json>');

const outputs = [args.report, args['snapshot-out']].filter(Boolean);
for (const out of outputs) {
  if (insideRepo(out)) fail(`Rifiuto di scrivere dentro il repository: ${out}. Usa una cartella esterna.`);
}
// Un output non deve mai coincidere con un altro output né con un file letto: sovrascriverebbe i dati.
const reads = [args.input, args.previous].filter(Boolean).map(canonical);
const writes = outputs.map(canonical);
if (new Set(writes).size !== writes.length) fail('--report e --snapshot-out indicano lo stesso file.');
for (const w of writes) {
  if (reads.includes(w)) fail('Un file di output coincide con un file di input (--input/--previous): rifiuto di sovrascriverlo.');
}

let previous = null;
if (args.previous) {
  try {
    const parsed = JSON.parse(readFileSync(args.previous, 'utf8'));
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('forma non valida');
    for (const v of Object.values(parsed)) if (typeof v !== 'string') throw new Error('valori non stringa');
    previous = new Map(Object.entries(parsed));
  } catch (e) {
    fail(`--previous non è uno snapshot valido (${e.message}).`);
  }
}

const { report, snapshot } = await runImport(args.input, { previous });
writeFileSync(args.report, JSON.stringify(report, null, 2));
if (args['snapshot-out']) writeFileSync(args['snapshot-out'], JSON.stringify(Object.fromEntries(snapshot)));
console.log(`Righe dati: ${report.rows.data_rows} | record: ${report.rows.records} | scartati: ${report.rows.rejected} | rilievi: ${report.issues.total}`);
