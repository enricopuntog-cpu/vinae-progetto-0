#!/usr/bin/env bun
// Genera un dataset SINTETICO nel formato LWIN (22 colonne) per misure riproducibili. NON è il file reale:
// nessun nome vero, seme fisso, distribuzioni simili a quelle documentate (≈97% Live, ≈3% Combined, ≈0,2% Deleted,
// ≈90% ambito vino, ~100 paesi / ~400 regioni / ~2.000 sottoregioni, alcune catene Combined, Combined → Deleted,
// gruppi di possibili duplicati).
//
//   bun tools/wine-catalog/bench/make-synthetic.mjs --out <base.xlsx> [--rows 212894] [--seed 1]
//   bun tools/wine-catalog/bench/make-synthetic.mjs --out <mod.xlsx> --variant modified   # delta noto, vedi sotto
//
// Variante `modified` rispetto a `base` (stesso seme): 998 record con WINE cambiato, 30 Combined con REFERENCE diverso,
// 500 record rimossi (ultimi LWIN del file base) e 500 nuovi aggiunti in fondo. Scrivere fuori dal repository.
import { writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { LWIN_COLUMNS } from '../lib/lwin.mjs';
import { makeXlsx } from '../test/make-xlsx.mjs';
import { insideRepo } from '../lib/paths.mjs';

const { values: a } = parseArgs({ options: { out: { type: 'string' }, rows: { type: 'string' }, seed: { type: 'string' }, variant: { type: 'string' } } });
if (!a.out) { console.error('Manca --out'); process.exit(2); }
if (insideRepo(a.out)) { console.error('Rifiuto di scrivere dentro il repository.'); process.exit(2); }
const N = Number(a.rows ?? 212894);
const modified = a.variant === 'modified';

let state = Number(a.seed ?? 1) >>> 0 || 1;
const rnd = () => { state ^= state << 13; state >>>= 0; state ^= state >>> 17; state ^= state << 5; state >>>= 0; return state / 4294967296; };
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];

const countries = Array.from({ length: 101 }, (_, i) => `Paese ${i + 1}`);
const regionsOf = (c) => Array.from({ length: 4 }, (_, k) => `Regione ${c}-${k + 1}`);
const subsOf = (r) => Array.from({ length: 5 }, (_, k) => `Zona ${r}-${k + 1}`);
const colours = ['Red', 'White', 'Rose', 'Sweet', 'Sparkling', 'NA'];
const types = ['Wine', 'Wine', 'Wine', 'Wine', 'Wine', 'Wine', 'Wine', 'Wine', 'Wine', 'Fortified Wine', 'Spirit', 'Other'];

const BASE = 1000000;
const row = (o) => LWIN_COLUMNS.map((c) => (c in o ? o[c] : c === 'REFERENCE' ? '' : 'NA'));

const live = [];
const rows = [];
for (let i = 0; i < N; i += 1) {
  const lwin = String(BASE + i);
  const country = pick(countries);
  const region = rnd() < 0.93 ? pick(regionsOf(country)) : 'NA';
  const sub = region !== 'NA' && rnd() < 0.45 ? pick(subsOf(region)) : 'NA';
  const kind = rnd();
  const status = kind < 0.0294 ? 'Combined' : kind < 0.0317 ? 'Deleted' : 'Live';
  const dupGroup = i < 140 ? Math.floor(i / 2) : -1; // 70 gruppi di coppie con la stessa identità normalizzata
  const producer = dupGroup >= 0 ? `Produttore Dup ${dupGroup}` : `Produttore ${Math.floor(rnd() * 40000)}`;
  const wine = dupGroup >= 0 ? `Vino Dup ${dupGroup}` : `Vino ${i}`;
  const type = pick(types);
  rows.push({
    LWIN: lwin, STATUS: status, DISPLAY_NAME: `${producer}, ${wine}`, PRODUCER_NAME: producer, WINE: wine,
    COUNTRY: dupGroup >= 0 ? 'Paese 1' : country, REGION: dupGroup >= 0 ? 'Regione Paese 1-1' : region, SUB_REGION: dupGroup >= 0 ? 'NA' : sub,
    COLOUR: pick(colours), TYPE: type, SUB_TYPE: 'NA', DESIGNATION: rnd() < 0.3 ? 'AOC' : 'NA', CLASSIFICATION: 'NA',
    FIRST_VINTAGE: rnd() < 0.5 ? String(1950 + Math.floor(rnd() * 70)) : 'NA', DATE_ADDED: '42000', DATE_UPDATED: '44000',
  });
  if (status === 'Live') live.push(lwin);
}
// riferimenti dei Combined: quasi tutti verso un Live; qualche catena; qualche verso Deleted
const deleted = rows.filter((r) => r.STATUS === 'Deleted').map((r) => r.LWIN);
const combined = rows.filter((r) => r.STATUS === 'Combined');
combined.forEach((r, k) => {
  if (k % 200 === 0 && deleted.length) r.REFERENCE = pick(deleted);
  else if (k % 150 === 1 && k > 0) r.REFERENCE = combined[k - 1].LWIN;
  else r.REFERENCE = pick(live);
});

let out = rows;
if (modified) {
  out = rows.map((r) => ({ ...r }));
  for (let k = 0; k < 998; k += 1) { const t = out[1000 + k * 7]; if (t.STATUS === 'Live' || t.STATUS === 'Deleted') t.WINE += ' (rev)'; else t.WINE += ' (rev)'; }
  let changed = 0;
  for (const r of out) {
    if (changed >= 30) break;
    if (r.STATUS === 'Combined' && r.REFERENCE) { r.REFERENCE = live[(live.indexOf(r.REFERENCE) + 17) % live.length] ?? live[0]; changed += 1; }
  }
  out = out.slice(0, out.length - 500);
  for (let k = 0; k < 500; k += 1) {
    const lwin = String(BASE + N + k);
    out.push({ LWIN: lwin, STATUS: 'Live', DISPLAY_NAME: `Nuovo ${k}`, PRODUCER_NAME: `Produttore nuovo ${k}`, WINE: `Vino nuovo ${k}`, COUNTRY: 'Paese 2', REGION: 'Regione Paese 2-1', COLOUR: 'Red', TYPE: 'Wine' });
  }
}
writeFileSync(a.out, makeXlsx([LWIN_COLUMNS, ...out.map(row)]));
console.log(`scritto ${a.out}: ${out.length} righe dati (${modified ? 'modified' : 'base'})`);
