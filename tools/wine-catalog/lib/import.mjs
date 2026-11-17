// Orchestratore locale dell'import LWIN: legge, normalizza, classifica e produce
// un report. Non scrive su nessun database, non apre connessioni di rete.
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename } from 'node:path';
import { readXlsxRows } from './xlsx-stream.mjs';
import { LWIN_COLUMNS, rowToRaw, normalizeLwinRow } from './lwin.mjs';
import { classifyImport } from './diff.mjs';

const SAMPLE_LIMIT = 20;
const DUP_GROUP_SAMPLES = 10;

/** Chiave di confronto: senza accenti, minuscola, spazi collassati. */
export function foldKey(s) {
  return String(s ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

export async function sha256File(path) {
  const h = createHash('sha256');
  let size = 0;
  for await (const chunk of createReadStream(path)) {
    h.update(chunk);
    size += chunk.length;
  }
  return { sha256: h.digest('hex'), size };
}

const bump = (obj, key) => {
  const k = key ?? '(vuoto)';
  obj[k] = (obj[k] ?? 0) + 1;
};
const sorted = (obj) => Object.fromEntries(Object.entries(obj).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])));
const top = (obj, n) => Object.fromEntries(Object.entries(sorted(obj)).slice(0, n));

/**
 * Flusso riga per riga (WI-001B): ogni elemento porta la riga originale (`raw`, testo come nel file),
 * il record normalizzato (null se il LWIN non è utilizzabile) e i rilievi. Non accumula nulla.
 * @param {string} path file .xlsx LWIN
 */
export async function* iterateRecords(path) {
  let header = null;
  for await (const { rowNumber, cells } of readXlsxRows(path)) {
    if (header === null) {
      header = cells;
      rowToRaw(header, []);
      continue;
    }
    if (cells.every((c) => c.trim() === '')) continue;
    const raw = rowToRaw(header, cells);
    const { record, issues } = normalizeLwinRow(raw, rowNumber);
    yield { rowNumber, raw, record, issues };
  }
  if (header === null) throw new Error('File vuoto: nessuna intestazione trovata');
}

/**
 * @param {string} path file .xlsx LWIN
 * @param {{previous?: Map<string,string>|null}} [opts] snapshot precedente (lwin -> row_hash)
 * @returns {Promise<{report: object, snapshot: Map<string,string>}>}
 */
export async function runImport(path, { previous = null } = {}) {
  const records = [];
  const issuesByCode = {};
  const status = Object.create(null);
  const type = Object.create(null);
  const colour = Object.create(null);
  const scope = Object.create(null);
  const countriesWine = Object.create(null);
  const designationWine = Object.create(null);
  const regions = new Set();
  const subRegions = new Set();
  const countries = new Set();
  const natural = new Map();
  let header = null;
  let dataRows = 0;
  let rejected = 0;
  let noRegion = 0;
  let wineNoRegion = 0;
  let wineNoCountry = 0;
  let wineLive = 0;
  const nullCoverage = {};

  for await (const { rowNumber, cells } of readXlsxRows(path)) {
    if (header === null) {
      header = cells;
      rowToRaw(header, []); // valida le intestazioni prima di leggere altro
      continue;
    }
    if (cells.every((c) => c.trim() === '')) continue;
    dataRows += 1;
    const { record, issues } = normalizeLwinRow(rowToRaw(header, cells), rowNumber);
    for (const i of issues) {
      const slot = (issuesByCode[i.code] ??= { count: 0, samples: [] });
      slot.count += 1;
      if (slot.samples.length < SAMPLE_LIMIT) slot.samples.push({ row: i.row, field: i.field, message: i.message });
    }
    if (!record) {
      rejected += 1;
      continue;
    }
    records.push(record);
    bump(status, record.status);
    bump(type, record.type);
    bump(colour, record.colour);
    bump(scope, record.scope);
    if (record.country) countries.add(record.country);
    if (record.country && record.region) regions.add(`${record.country}|${record.region}`);
    if (record.country && record.region && record.sub_region) subRegions.add(`${record.country}|${record.region}|${record.sub_region}`);
    if (!record.region) noRegion += 1;
    if (record.scope === 'wine') {
      bump(countriesWine, record.country);
      bump(designationWine, record.designation);
      if (!record.region) wineNoRegion += 1;
      if (!record.country) wineNoCountry += 1;
      if (record.status === 'Live') {
        wineLive += 1;
        for (const f of ['producer_name', 'wine', 'region', 'sub_region', 'colour', 'sub_type', 'designation', 'classification', 'first_vintage']) {
          if (record[f] === null) nullCoverage[f] = (nullCoverage[f] ?? 0) + 1;
        }
        const key = [record.producer_name, record.wine, record.country, record.region, record.sub_region, record.site, record.colour, record.sub_type, record.designation, record.classification]
          .map(foldKey)
          .join('|');
        const g = natural.get(key);
        if (g) { if (!g.includes(record.lwin)) g.push(record.lwin); }
        else natural.set(key, [record.lwin]);
      }
    }
  }
  if (header === null) throw new Error('File vuoto: nessuna intestazione trovata');

  const classification = classifyImport(records, previous);
  const snapshot = new Map();
  for (const r of records) if (!snapshot.has(r.lwin)) snapshot.set(r.lwin, r.row_hash);

  const statusOf = new Map();
  for (const r of records) if (!statusOf.has(r.lwin)) statusOf.set(r.lwin, r.status);
  const references = { combined: 0, target_missing: 0, target_deleted: 0, target_combined_chain: 0, samples: { target_missing: [], target_deleted: [], target_combined_chain: [] } };
  for (const r of records) {
    if (r.status !== 'Combined' || r.reference_lwin === null) continue;
    references.combined += 1;
    const t = statusOf.get(r.reference_lwin);
    const kind = t === undefined ? 'target_missing' : t === 'Deleted' ? 'target_deleted' : t === 'Combined' ? 'target_combined_chain' : null;
    if (!kind) continue;
    references[kind] += 1;
    if (references.samples[kind].length < SAMPLE_LIMIT) references.samples[kind].push({ from: r.lwin, into: r.reference_lwin });
  }

  const dupGroups =[...natural.values()].filter((g) => g.length > 1);
  const { sha256, size } = await sha256File(path);

  const report = {
    generated_by: 'wine-catalog/lwin-import (WI-001A, locale, sola lettura)',
    source: { file_name: basename(path), size_bytes: size, sha256, expected_columns: LWIN_COLUMNS.length },
    rows: { data_rows: dataRows, records: records.length, rejected },
    issues: {
      total: Object.values(issuesByCode).reduce((a, s) => a + s.count, 0),
      by_code: issuesByCode,
    },
    distributions: {
      status: sorted(status),
      type: sorted(type),
      colour: sorted(colour),
      scope: sorted(scope),
      wine_scope_country_top30: top(countriesWine, 30),
      wine_scope_designation_top20: top(designationWine, 20),
    },
    territory: {
      distinct_countries: countries.size,
      distinct_regions: regions.size,
      distinct_sub_regions: subRegions.size,
      records_without_region: noRegion,
      wine_scope_without_region: wineNoRegion,
      wine_scope_without_country: wineNoCountry,
    },
    references,
    wine_live_null_coverage: { records: wineLive, null_by_field: nullCoverage },
    classification: {
      counts: classification.counts,
      conflict_lwins: classification.conflictLwins.slice(0, 100),
      merged_pairs_sample: classification.mergedPairs.slice(0, 20),
      removed_lwins_sample: classification.removedLwins.slice(0, 100),
      delete_action: classification.deleteAction,
      compared_with_previous_snapshot: previous !== null,
    },
    potential_duplicates: {
      basis: 'produttore+vino+territorio+colore+sottotipo+denominazione+classificazione (Live, ambito vino), confronto senza accenti/maiuscole',
      groups: dupGroups.length,
      records_involved: dupGroups.reduce((a, g) => a + g.length, 0),
      sample_groups: dupGroups.slice(0, DUP_GROUP_SAMPLES).map((g) => g.slice(0, 5)),
      action: 'none',
    },
  };
  return { report, snapshot };
}
