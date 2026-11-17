// Caricatore LWIN → PostgreSQL (WI-001B). Parla con il database SOLO attraverso un adattatore
// `db = { query(text, params) → { rows } }` e SOLO con istruzioni costanti: il testo del dataset
// viaggia come parametro ($n), mai concatenato nell'SQL. Le scritture passano dalle funzioni
// `catalog.*` della migrazione 20261117120000 (ruolo `catalog_loader`, nessun DELETE sui record).
//
// Protocollo differenziale (migration 20261117120000):
//   begin_import_run  → identità dello snapshot (sha256); se lo stesso file è già l'ultimo completato la
//                       risposta è `skipped` e il caricatore NON apre né legge il file;
//   stage_source_records (a lotti) → ogni lotto entra nello staging transitorio del tentativo: solo l'hash se
//                       il record è invariato, il contenuto completo se nuovo/modificato. `source_records` non è toccata;
//   finish_import_run → UNA transazione di promozione (nuovi/modificati/rimossi/eventi/collegamenti/territori).
// Un'interruzione lascia il tentativo `running` con lo staging parziale: nulla è visibile finché il finish non riesce;
// il tentativo successivo (con --takeover se quello fermo non è ancora scaduto) riparte dal file intero.
import { iterateRecords, snapshotFile, foldKey } from './import.mjs';
import { classifyImport } from './diff.mjs';

export const LWIN_SOURCE_CODE = 'LIVEX-LWIN7';
export const LWIN_EXPECTED_SHA256 = '7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e';
export const LWIN_EXPECTED_ROWS = 212894;
export const IMPORTER_VERSION = 'WI-001B';
export const DEFAULT_BATCH_SIZE = 2000;
const FINDING_BATCH = 1000;
const SAMPLE_LIMIT = 20;

/** Riga di lotto per `catalog.stage_source_records` (la forma è quella di jsonb_to_recordset). */
export function toBatchRow(record, raw) {
  const { row_hash: contentHash, ...payload } = record;
  return {
    external_id: record.lwin,
    status: record.status ?? 'Unknown',
    scope: record.scope,
    reference_external_id: record.reference_lwin,
    country: record.country,
    region: record.region,
    sub_region: record.sub_region,
    payload,
    raw,
    content_hash: contentHash,
  };
}

// Ruolo effettivo verificato prima di ogni operazione privilegiata (l'adattatore reale lo espone; i finti dei test no).
async function checkRole(db) {
  if (typeof db.assertRole === 'function') await db.assertRole();
}

function checkSha(actual, expected) {
  if (expected && actual !== expected) {
    throw new Error(`SHA-256 del file diverso dall'atteso (atteso ${expected}, trovato ${actual}): import rifiutato.`);
  }
}

function naturalKey(r) {
  return [r.producer_name, r.wine, r.country, r.region, r.sub_region, r.site, r.colour, r.sub_type, r.designation, r.classification]
    .map(foldKey)
    .join('|');
}

/**
 * Anteprima di ciò che farebbe un import, senza scrivere: legge il file e (se c'è un db) lo stato
 * attuale del catalogo per la fonte. Con db = null il confronto è con un catalogo vuoto.
 */
export async function planLoad(db, path, { sourceCode = LWIN_SOURCE_CODE, expectedSha256 = null } = {}) {
  const snap = await snapshotFile(path);
  try {
    return await planFromSnapshot(db, snap, { sourceCode, expectedSha256 });
  } finally {
    snap.dispose();
  }
}

async function planFromSnapshot(db, snap, { sourceCode, expectedSha256 }) {
  const { sha256, size } = snap;
  checkSha(sha256, expectedSha256);

  const state = new Map();
  let alreadyCurrent = false;
  if (db) {
    const src = await db.query('select id from catalog.sources where code = $1', [sourceCode]);
    if (src.rows.length === 0) throw new Error(`Fonte ${sourceCode} non registrata nel database.`);
    const cv = await db.query('select complete_sha256 from catalog.complete_versions where code = $1', [sourceCode]);
    alreadyCurrent = cv.rows.length > 0 && cv.rows[0].complete_sha256 === sha256;
    const cur = await db.query(
      'select external_id, content_hash, removed_from_source_at is not null as removed from catalog.source_records where source_id = $1',
      [src.rows[0].id],
    );
    for (const r of cur.rows) state.set(r.external_id, { hash: r.content_hash, removed: r.removed });
  }

  const records = [];
  let dataRows = 0;
  let rejected = 0;
  for await (const { record } of iterateRecords(snap.path)) {
    dataRows += 1;
    if (!record) rejected += 1;
    else records.push(record);
  }
  const previous = state.size > 0 ? new Map([...state].map(([k, v]) => [k, v.hash])) : null;
  const c = classifyImport(records, previous);
  const inFile = new Set(records.map((r) => r.lwin));
  const reappeared = records.filter((r) => state.get(r.lwin)?.removed).length;
  const removedNow = c.removedLwins.filter((l) => !state.get(l)?.removed);

  return {
    mode: 'dry_run',
    database_writes: 0,
    source: { code: sourceCode, sha256, size_bytes: size },
    rows: { data_rows: dataRows, records: records.length, rejected, distinct_external_ids: inFile.size },
    database_state: { records: state.size, compared: db !== null, snapshot_already_current: alreadyCurrent },
    delta: {
      ...c.counts,
      reappeared,
      removed_from_source: removedNow.length,
      removed_sample: removedNow.slice(0, SAMPLE_LIMIT),
      conflict_lwins: c.conflictLwins.slice(0, SAMPLE_LIMIT),
    },
  };
}

/**
 * Carica il file nel catalogo. Restituisce il report finale; se qualcosa fallisce marca il
 * tentativo `failed` (mai `succeeded`) e rilancia l'errore.
 */
export async function loadToDatabase(db, path, opts = {}) {
  const {
    sourceCode = LWIN_SOURCE_CODE,
    expectedSha256 = null,
    expectedRows = null,
    takeover = false,
    staleMinutes = 10,
    allowMassRemoval = false,
    force = false,
    batchSize = DEFAULT_BATCH_SIZE,
    importerVersion = IMPORTER_VERSION,
    onProgress = () => {},
  } = opts;
  // una sola copia privata: l'hash dichiarato e i byte importati sono gli stessi
  const snap = await snapshotFile(path);
  try {
    return await loadFromSnapshot(db, snap, path, {
      sourceCode, expectedSha256, expectedRows, takeover, staleMinutes, allowMassRemoval, force, batchSize, importerVersion, onProgress,
    });
  } finally {
    snap.dispose();
  }
}

async function loadFromSnapshot(db, snap, path, {
  sourceCode, expectedSha256, expectedRows, takeover, staleMinutes, allowMassRemoval, force, batchSize, importerVersion, onProgress,
}) {
  const { sha256 } = snap;
  checkSha(sha256, expectedSha256);
  const fileName = path.split(/[\\/]/).pop();

  await checkRole(db);
  const begun = await db.query('select catalog.begin_import_run($1, $2, $3, $4, $5, $6, make_interval(mins => $7::int), $8) as r', [
    sourceCode, sha256, fileName, expectedRows, importerVersion, takeover, staleMinutes, force,
  ]);
  const begin = typeof begun.rows[0].r === 'string' ? JSON.parse(begun.rows[0].r) : begun.rows[0].r;
  const runId = begin.run_id;
  if (begin.mode === 'skipped') {
    // snapshot già completato e ancora corrente: nessuna lettura del file, nessuna elaborazione
    return {
      mode: 'skipped',
      run_id: runId,
      reason: 'snapshot_already_current',
      of_run: begin.of_run,
      source: { code: sourceCode, sha256, file_name: fileName, size_bytes: snap.size },
      database_writes: 'una riga di telemetria (import_runs, status skipped)',
    };
  }

  const totals = { received: 0, new: 0, updated: 0, unchanged: 0, reappeared: 0 };
  let dataRows = 0;
  let rejected = 0;
  let duplicates = 0;
  let divergent = 0;
  let batch = [];
  let findings = [];
  const seen = new Map(); // lwin → content_hash (primo valore visto)
  const natural = new Map();

  const flushBatch = async () => {
    if (batch.length === 0) return;
    await checkRole(db);
    const r = await db.query('select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r', [runId, JSON.stringify(batch)]);
    const got = typeof r.rows[0].r === 'string' ? JSON.parse(r.rows[0].r) : r.rows[0].r;
    for (const k of Object.keys(totals)) totals[k] += Number(got[k] ?? 0);
    batch = [];
    onProgress({ rows: dataRows, written: totals.received });
  };
  const flushFindings = async (force = false) => {
    if (findings.length === 0 || (!force && findings.length < FINDING_BATCH)) return;
    await db.query('select catalog.record_findings($1::uuid, ($2::text)::jsonb) as n', [runId, JSON.stringify(findings)]);
    findings = [];
  };

  try {
    for await (const { raw, record, issues } of iterateRecords(snap.path)) {
      dataRows += 1;
      for (const i of issues) {
        findings.push({ external_id: record?.lwin ?? null, kind: 'parse_issue', detail: { code: i.code, field: i.field, row: i.row, message: i.message } });
      }
      if (!record) {
        rejected += 1;
        continue;
      }
      const first = seen.get(record.lwin);
      if (first !== undefined) {
        if (first === record.row_hash) duplicates += 1;
        else {
          divergent += 1;
          findings.push({ external_id: record.lwin, kind: 'divergent_duplicate', detail: { kept_hash: first, ignored_hash: record.row_hash } });
        }
        continue;
      }
      seen.set(record.lwin, record.row_hash);
      if (record.scope === 'wine' && record.status === 'Live') {
        const key = naturalKey(record);
        const g = natural.get(key);
        if (g) g.push(record.lwin);
        else natural.set(key, [record.lwin]);
      }
      batch.push(toBatchRow(record, raw));
      if (batch.length >= batchSize) await flushBatch();
      await flushFindings();
    }
    await flushBatch();
    for (const g of natural.values()) {
      if (g.length > 1) findings.push({ external_id: g[0], kind: 'possible_duplicate', detail: { lwins: g.slice(0, 10), size: g.length } });
    }
    await flushFindings(true);

    const summary = {
      importer_version: importerVersion,
      data_rows: dataRows,
      rejected,
      duplicate_rows: duplicates,
      divergent_duplicates: divergent,
      staged: totals,
      ...(allowMassRemoval ? { allow_mass_removal: true } : {}),
    };
    await checkRole(db);
    const fin = await db.query('select catalog.finish_import_run($1::uuid, $2::bigint, ($3::text)::jsonb) as r', [runId, seen.size, JSON.stringify(summary)]);
    const result = typeof fin.rows[0].r === 'string' ? JSON.parse(fin.rows[0].r) : fin.rows[0].r;
    return { mode: 'load', run_id: runId, source: { code: sourceCode, sha256, file_name: fileName, size_bytes: snap.size }, distinct_external_ids: seen.size, ...summary, result };
  } catch (e) {
    try {
      await db.query('select catalog.fail_import_run($1::uuid, $2)', [runId, String(e?.message ?? e)]);
    } catch {
      // il tentativo resta `running`: sarà rilevato e ripreso con --takeover
    }
    throw e;
  }
}
