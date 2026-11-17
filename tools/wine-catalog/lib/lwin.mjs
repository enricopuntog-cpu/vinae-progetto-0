// Normalizzazione deterministica delle righe del database LWIN.
// Nessuna AI, nessuna rete: solo regole esplicite e rilievi tipizzati.
import { createHash } from 'node:crypto';

export const LWIN_COLUMNS = [
  'LWIN', 'STATUS', 'DISPLAY_NAME', 'PRODUCER_TITLE', 'PRODUCER_NAME', 'WINE',
  'COUNTRY', 'REGION', 'SUB_REGION', 'SITE', 'PARCEL', 'COLOUR', 'TYPE', 'SUB_TYPE',
  'DESIGNATION', 'CLASSIFICATION', 'VINTAGE_CONFIG', 'FIRST_VINTAGE', 'FINAL_VINTAGE',
  'DATE_ADDED', 'DATE_UPDATED', 'REFERENCE',
];

export const KNOWN_STATUS = new Set(['Live', 'Combined', 'Deleted']);
export const KNOWN_TYPE = new Set(['Wine', 'Fortified Wine', 'Spirit', 'Other', 'Cider', 'Beer']);
const WINE_SCOPE_TYPES = new Set(['Wine', 'Fortified Wine']);

/** Abbina le celle alle intestazioni; l'intestazione deve coincidere con quella attesa. */
export function rowToRaw(header, cells) {
  const same = header.length === LWIN_COLUMNS.length && LWIN_COLUMNS.every((c, i) => header[i] === c);
  if (!same) {
    throw new Error(`Intestazioni non attese: trovate [${header.join(', ')}], attese [${LWIN_COLUMNS.join(', ')}]`);
  }
  const raw = {};
  LWIN_COLUMNS.forEach((c, i) => {
    raw[c] = cells[i] ?? '';
  });
  return raw;
}

/** "NA" e stringa vuota sono assenza di dato (null); tutto il resto è tenuto, ripulito ai bordi. */
export function cleanText(v) {
  if (v === undefined || v === null) return null;
  const t = String(v).trim();
  return t === '' || t === 'NA' ? null : t;
}

const LWIN_RE = /^(\d{7})(?:\.0)?$/;

export function excelSerialToIso(v) {
  const t = cleanText(v);
  if (t === null) return null;
  const n = Number(t);
  if (!Number.isFinite(n) || n <= 0) return null;
  const d = new Date(Math.round((n - 25569) * 86400000));
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function parseYear(v, field, row, issues) {
  const t = cleanText(v);
  if (t === null) return null;
  if (!/^\d{4}$/.test(t) || Number(t) < 1500 || Number(t) > 2100) {
    issues.push({ code: 'invalid_vintage_year', field, row, message: `Anno non valido: "${t}"` });
    return null;
  }
  return Number(t);
}

// Versione del normalizzatore: entra nell'hash, così un cambio di regole di normalizzazione NON passa per
// «invariato» (i record sarebbero riletti come cambiati e l'import lo mostra in modo esplicito).
export const NORMALIZER_VERSION = 'lwin-norm-2';

const HASH_FIELDS = [
  'scope', 'lwin', 'status', 'display_name', 'producer_title', 'producer_name', 'wine', 'country',
  'region', 'sub_region', 'site', 'parcel', 'colour', 'type', 'sub_type', 'designation',
  'classification', 'vintage_config', 'first_vintage', 'final_vintage', 'reference_lwin',
];

/**
 * Restituisce { record, issues }. record è null solo se il codice LWIN non è
 * utilizzabile. Le date di inserimento/aggiornamento NON entrano in row_hash:
 * "aggiornato" significa che è cambiato il contenuto, non il calendario.
 */
export function normalizeLwinRow(raw, row) {
  const issues = [];
  const lwinText = cleanText(raw.LWIN);
  const m = lwinText && LWIN_RE.exec(lwinText);
  if (!m) {
    return { record: null, issues: [{ code: 'invalid_lwin', field: 'LWIN', row, message: `LWIN non valido: "${raw.LWIN ?? ''}"` }] };
  }
  const lwin = m[1];

  const status = cleanText(raw.STATUS);
  if (!status || !KNOWN_STATUS.has(status)) {
    issues.push({ code: 'unknown_status', field: 'STATUS', row, message: `Stato non previsto: "${status ?? ''}"` });
  }

  const type = cleanText(raw.TYPE);
  if (!type || !KNOWN_TYPE.has(type)) {
    issues.push({ code: 'unknown_type', field: 'TYPE', row, message: `Tipo non previsto: "${type ?? ''}"` });
  }

  let reference = null;
  const refText = cleanText(raw.REFERENCE);
  if (refText !== null) {
    const rm = LWIN_RE.exec(refText);
    if (!rm) issues.push({ code: 'invalid_reference', field: 'REFERENCE', row, message: `Riferimento non valido: "${refText}"` });
    else reference = rm[1];
  }
  if (status === 'Combined') {
    if (reference === null && refText === null) {
      issues.push({ code: 'combined_without_reference', field: 'REFERENCE', row, message: 'Record Combined senza riferimento di destinazione' });
    } else if (reference === lwin) {
      issues.push({ code: 'self_reference', field: 'REFERENCE', row, message: 'Il riferimento coincide con il LWIN del record' });
    }
  }

  const first = parseYear(raw.FIRST_VINTAGE, 'FIRST_VINTAGE', row, issues);
  const final = parseYear(raw.FINAL_VINTAGE, 'FINAL_VINTAGE', row, issues);
  if (first !== null && final !== null && first > final) {
    issues.push({ code: 'vintage_order', field: 'FIRST_VINTAGE', row, message: `Prima annata (${first}) successiva all'ultima (${final})` });
  }

  for (const f of ['DATE_ADDED', 'DATE_UPDATED']) {
    const t = cleanText(raw[f]);
    if (t !== null && excelSerialToIso(t) === null) {
      issues.push({ code: 'invalid_date', field: f, row, message: `Data non valida: "${t}"` });
    }
  }

  const record = {
    lwin,
    status,
    display_name: cleanText(raw.DISPLAY_NAME),
    producer_title: cleanText(raw.PRODUCER_TITLE),
    producer_name: cleanText(raw.PRODUCER_NAME),
    wine: cleanText(raw.WINE),
    country: cleanText(raw.COUNTRY),
    region: cleanText(raw.REGION),
    sub_region: cleanText(raw.SUB_REGION),
    site: cleanText(raw.SITE),
    parcel: cleanText(raw.PARCEL),
    colour: cleanText(raw.COLOUR),
    type,
    sub_type: cleanText(raw.SUB_TYPE),
    designation: cleanText(raw.DESIGNATION),
    classification: cleanText(raw.CLASSIFICATION),
    vintage_config: cleanText(raw.VINTAGE_CONFIG),
    first_vintage: first,
    final_vintage: final,
    reference_lwin: reference,
    date_added: excelSerialToIso(raw.DATE_ADDED),
    date_updated: excelSerialToIso(raw.DATE_UPDATED),
    scope: type && WINE_SCOPE_TYPES.has(type) ? 'wine' : 'other',
  };
  // Anni e riferimento entrano nell'hash col testo ripulito (non col valore parsato):
  // altrimenti due testi diversi ma entrambi invalidi (→ null) avrebbero lo stesso hash.
  const hashed = { ...record, first_vintage: cleanText(raw.FIRST_VINTAGE), final_vintage: cleanText(raw.FINAL_VINTAGE), reference_lwin: refText };
  record.row_hash = createHash('sha256')
    .update(JSON.stringify([NORMALIZER_VERSION, ...HASH_FIELDS.map((f) => hashed[f])]))
    .digest('hex');
  return { record, issues };
}
