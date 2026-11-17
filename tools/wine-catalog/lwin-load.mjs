#!/usr/bin/env bun
// Caricatore persistente LWIN → PostgreSQL LOCALE (WI-001B).
//
// Solo database loopback (localhost/127.0.0.1/::1): nessun override, nessuna rete esterna. Il report
// va scritto FUORI dal repository. Il file Excel è indicato esplicitamente con --input e non viene mai cercato.
//
// Uso (Bun, client PostgreSQL integrato):
//   bun tools/wine-catalog/lwin-load.mjs --input <LWINdatabase.xlsx> --database-url postgresql://… \
//        --report <out.json> [--dry-run] [--takeover] [--expected-sha256 <hex>] [--batch-size 2000]
// La URL può venire da CATALOG_DATABASE_URL (preferibile: non resta nella cronologia della shell).
import { writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { insideRepo, assertLocalDatabaseUrl } from './lib/paths.mjs';
import {
  planLoad, loadToDatabase, LWIN_EXPECTED_SHA256, LWIN_EXPECTED_ROWS, DEFAULT_BATCH_SIZE,
} from './lib/load.mjs';
import { sha256File } from './lib/import.mjs';

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

let args;
try {
  args = parseArgs({
    options: {
      input: { type: 'string' },
      'database-url': { type: 'string' },
      report: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
      takeover: { type: 'boolean', default: false },
      'stale-minutes': { type: 'string' },
      'allow-mass-removal': { type: 'boolean', default: false },
      'expected-sha256': { type: 'string' },
      'batch-size': { type: 'string' },
    },
    strict: true,
  }).values;
} catch (e) {
  fail(`${e.message}\nUso: lwin-load.mjs --input <file.xlsx> --report <out.json> [--database-url <url>] [--dry-run] [--takeover] [--expected-sha256 <hex>] [--batch-size N]`);
}
if (!args.input) fail('Manca --input <file.xlsx> (percorso esplicito: il file non viene cercato).');
if (!args.report) fail('Manca --report <out.json> (fuori dal repository).');
if (insideRepo(args.report)) fail(`Rifiuto di scrivere dentro il repository: ${args.report}.`);
const url = args['database-url'] ?? process.env.CATALOG_DATABASE_URL ?? null;
if (!url && !args['dry-run']) fail('Manca --database-url (o CATALOG_DATABASE_URL): solo database locale.');
if (url) {
  try {
    assertLocalDatabaseUrl(url);
  } catch (e) {
    fail(e.message);
  }
}
const batchSize = args['batch-size'] ? Number(args['batch-size']) : DEFAULT_BATCH_SIZE;
if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 20000) fail('--batch-size deve essere un intero tra 1 e 20000.');

// Il file di riferimento (sha256 noto) è convalidato di default; un'altra versione richiede
// di dichiarare il suo hash con --expected-sha256.
const expectedSha = args['expected-sha256'] ?? LWIN_EXPECTED_SHA256;
const known = expectedSha === LWIN_EXPECTED_SHA256;

let db = null;
try {
  if (url) {
    const { connectLocal } = await import('./lib/db-bun.mjs');
    db = await connectLocal(url, { role: 'catalog_loader' });
  }
  const t0 = performance.now();
  let report;
  if (args['dry-run']) {
    report = await planLoad(db, args.input, { expectedSha256: expectedSha });
  } else {
    report = await loadToDatabase(db, args.input, {
      expectedSha256: expectedSha,
      expectedRows: known ? LWIN_EXPECTED_ROWS : null,
      takeover: args.takeover,
      staleMinutes: args['stale-minutes'] ? Number(args['stale-minutes']) : 10,
      allowMassRemoval: args['allow-mass-removal'],
      batchSize,
      onProgress: ({ rows, written }) => {
        if (written % 20000 < batchSize) console.error(`… ${rows} righe lette, ${written} scritte`);
      },
    });
  }
  report.elapsed_ms = Math.round(performance.now() - t0);
  report.peak_rss_mb = Math.round(process.memoryUsage().rss / 1048576);
  report.file_size_bytes = (await sha256File(args.input)).size;
  writeFileSync(args.report, JSON.stringify(report, null, 2));
  console.log(args['dry-run'] ? 'Anteprima (nessuna scrittura):' : 'Caricamento completato:', JSON.stringify(report.rows ?? report.result?.territories ?? {}), `| ${report.elapsed_ms} ms | RSS ${report.peak_rss_mb} MB`);
} catch (e) {
  console.error(`Errore: ${e.message}`);
  process.exitCode = 1;
} finally {
  if (db) await db.close();
}
// riferimento per i test statici
export const CLI_PATH = fileURLToPath(import.meta.url);
