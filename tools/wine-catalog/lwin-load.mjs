#!/usr/bin/env bun
// Caricatore persistente LWIN → PostgreSQL LOCALE (WI-001B).
//
// Per DEFAULT solo database loopback (localhost/127.0.0.1/::1): nessun override, nessuna rete esterna. La modalità
// `--cloud` (WI-001C) è DISABILITATA salvo CATALOG_CLOUD_IMPORT=enabled e una destinazione identificata con
// --target-ref (vedi lib/cloud-target.mjs e docs/wine-intelligence/CLOUD_IMPORT_RUNBOOK.md); non è mai stata
// eseguita su un database reale. Il report va scritto FUORI dal repository. Il file Excel è indicato esplicitamente con --input e non viene mai cercato.
//
// Uso (Bun, client PostgreSQL integrato):
//   bun tools/wine-catalog/lwin-load.mjs --input <LWINdatabase.xlsx> --database-url postgresql://… \
//        --report <out.json> [--dry-run] [--takeover] [--force] [--expected-sha256 <hex>] [--batch-size 2000]
// Lo stesso file (sha256) già importato e ancora corrente non viene rielaborato (tentativo `skipped`);
// --force lo rielabora comunque (verifica dello stato: i record invariati non vengono comunque riscritti).
// La URL può venire da CATALOG_DATABASE_URL (preferibile: non resta nella cronologia della shell).
import { writeFileSync, readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { insideRepo, assertLocalDatabaseUrl } from './lib/paths.mjs';
import { assertCloudAuthorized, resolveCloudLimits, redactUrl } from './lib/cloud-target.mjs';
import { createLogger, sanitizeError } from './lib/safe-log.mjs';
import {
  assertCloudSession, assertLoaderPrivileges, createWalGuard, applySessionLimits, planFinishWal, createWalMonitor,
  concludeFinish, safeStopMonitor, finishDeadlineMs,
} from './lib/cloud-guards.mjs';
import { extractSqlState } from './lib/finish-error.mjs';
import { postCommitChecks, settleCloudRun, writeReportFile } from './lib/cloud-outcome.mjs';
import { loadCaPem } from './lib/cloud-tls.mjs';
import {
  planLoad, loadToDatabase, LWIN_EXPECTED_SHA256, LWIN_EXPECTED_ROWS, DEFAULT_BATCH_SIZE,
} from './lib/load.mjs';

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
      force: { type: 'boolean', default: false },
      'expected-sha256': { type: 'string' },
      'batch-size': { type: 'string' },
      'expected-rows': { type: 'string' },
      cloud: { type: 'boolean', default: false },
      'target-ref': { type: 'string' },
      'allow-production': { type: 'boolean', default: false },
      'ca-file': { type: 'string' },
      'max-wal-mb': { type: 'string' },
      'batch-timeout-sec': { type: 'string' },
      'finish-timeout-min': { type: 'string' },
    },
    strict: true,
  }).values;
} catch (e) {
  fail(`${e.message}\nUso: lwin-load.mjs --input <file.xlsx> --report <out.json> [--database-url <url>] [--dry-run] [--takeover] [--force] [--expected-sha256 <hex>] [--expected-rows N] [--batch-size N]`);
}
if (!args.input) fail('Manca --input <file.xlsx> (percorso esplicito: il file non viene cercato).');
if (!args.report) fail('Manca --report <out.json> (fuori dal repository).');
if (insideRepo(args.report)) fail(`Rifiuto di scrivere dentro il repository: ${args.report}.`);
const url = args['database-url'] ?? process.env.CATALOG_DATABASE_URL ?? null;
let cloudTarget = null;
let cloudLimits = null;
if (args.cloud) {
  try {
    cloudTarget = assertCloudAuthorized({
      url: process.env.CATALOG_DATABASE_URL ?? null,
      env: process.env,
      flags: { cloud: true, targetRef: args['target-ref'], allowProduction: args['allow-production'], databaseUrlOnCommandLine: args['database-url'] !== undefined },
    });
    cloudLimits = resolveCloudLimits({
      batchSize: args['batch-size'], maxWalMb: args['max-wal-mb'], batchTimeoutSec: args['batch-timeout-sec'], finishTimeoutMin: args['finish-timeout-min'],
    });
  } catch (e) {
    fail(sanitizeError(e, [process.env.CATALOG_DATABASE_URL]));
  }
} else {
  for (const f of ['target-ref', 'allow-production', 'ca-file', 'max-wal-mb', 'batch-timeout-sec', 'finish-timeout-min']) {
    if (args[f] !== undefined && args[f] !== false) fail(`--${f} ha senso solo con --cloud.`);
  }
  if (!url && !args['dry-run']) fail('Manca --database-url (o CATALOG_DATABASE_URL): solo database locale.');
  if (url) {
    try {
      assertLocalDatabaseUrl(url);
    } catch (e) {
      fail(e.message);
    }
  }
}
if (args['stale-minutes'] !== undefined && !(Number.isInteger(Number(args['stale-minutes'])) && Number(args['stale-minutes']) >= 1)) fail('--stale-minutes deve essere un intero >= 1 (con 0 un caricatore ancora vivo verrebbe scavalcato).');
const batchSize = cloudLimits ? cloudLimits.batchSize : (args['batch-size'] ? Number(args['batch-size']) : DEFAULT_BATCH_SIZE);
if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 20000) fail('--batch-size deve essere un intero tra 1 e 20000.');
if (args['expected-rows'] && !(Number.isInteger(Number(args['expected-rows'])) && Number(args['expected-rows']) >= 0)) fail('--expected-rows deve essere un intero >= 0.');

// Il file di riferimento (sha256 noto) è convalidato di default; un'altra versione richiede
// di dichiarare il suo hash con --expected-sha256.
const expectedSha = args['expected-sha256'] ?? LWIN_EXPECTED_SHA256;
const known = expectedSha === LWIN_EXPECTED_SHA256;

let db = null;
const urlPassword = (() => { try { return new URL(process.env.CATALOG_DATABASE_URL ?? url ?? '').password; } catch { return ''; } })();
const logSecrets = [process.env.CATALOG_DATABASE_URL, url, urlPassword ? decodeURIComponent(urlPassword) : '', urlPassword];
const logger = createLogger({ secrets: logSecrets });
let walGuard = null;
let monitorDb = null;
let walMonitor = null;
let committedRun = false; // vero dopo un finish confermato: da qui in poi ogni errore NON è un rollback
let finishConclusion = null; // misura conclusiva e stato del monitor, raccolti subito dopo il finish (anche se fallito)
let runIdentity = null; // run_id, source_code, file_sha256, file_name, backend_pid: aggiornata da loadToDatabase (R1), mai persa dopo un errore
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const currentIdentity = (e) => ({ ...(e?.runIdentity ?? {}), ...(runIdentity ?? {}), backend_pid: db?.backendPid ?? runIdentity?.backend_pid ?? null });
const cloudInfo = cloudTarget
  ? { target: { kind: cloudTarget.kind, ref: cloudTarget.ref, host: cloudTarget.host, database: cloudTarget.database, production: cloudTarget.production, url: redactUrl(process.env.CATALOG_DATABASE_URL) }, limits: cloudLimits }
  : null;
try {
  if (cloudTarget) {
    const { connectCloud, connectCloudMonitor } = await import('./lib/db-bun.mjs');
    // CA: variabile d'ambiente (preferita, nessun file su disco) oppure --ca-file; il TLS non verificato è rifiutato
    const caPem = loadCaPem({ caFile: args['ca-file'] ?? null, envPem: process.env.CATALOG_DB_CA_PEM ?? null, readFile: (p) => readFileSync(p, 'utf8') });
    // dry-run: sessione di SOLA LETTURA (default_transaction_read_only + solo SELECT lato client); l'import usa il ruolo caricatore
    db = await connectCloud(process.env.CATALOG_DATABASE_URL, { role: 'catalog_loader', caPem, readOnly: args['dry-run'] });
    const q = (t, p) => db.query(t, p);
    cloudInfo.session = await assertCloudSession(q, {
      kind: cloudTarget.kind,
      clientTlsVerified: db.clientTlsVerified === true,
      preRoleSsl: db.preRoleSsl ?? null,
      // pooler: la URL ha utente `<ruolo>.<ref>`; Supavisor presenta al database il solo `<ruolo>`
      expectedLogin: cloudTarget.kind === 'pooler' ? cloudTarget.user.slice(0, -(cloudTarget.ref.length + 1)) : null,
    });
    cloudInfo.loader_privileges = await assertLoaderPrivileges(q);
    await applySessionLimits(db, {
      statementTimeoutMs: cloudLimits.batchTimeoutSec * 1000,
      lockTimeoutMs: cloudLimits.lockTimeoutSec * 1000,
      idleTxTimeoutMs: cloudLimits.idleTxTimeoutSec * 1000,
    });
    walGuard = await createWalGuard(q, { maxWalMb: cloudLimits.maxWalMb });
    if (!args['dry-run']) {
      // monitor del finish su una seconda connessione (stesso login): deve funzionare PRIMA di iniziare, altrimenti l'import non parte
      monitorDb = await connectCloudMonitor(process.env.CATALOG_DATABASE_URL, { caPem });
      walMonitor = createWalMonitor({
        query: (t, p) => monitorDb.query(t, p), backendPid: db.backendPid, startLsn: walGuard.start, maxWalMb: cloudLimits.maxWalMb,
        // connessione del monitor caduta durante il finish: se ne apre una nuova solo per annullare (sessione dedicata, stesso login)
        reopen: async () => { try { await monitorDb.close(); } catch { /* già chiusa */ } monitorDb = await connectCloudMonitor(process.env.CATALOG_DATABASE_URL, { caPem }); return (t, p) => monitorDb.query(t, p); },
      });
      await walMonitor.sample();
      if (walMonitor.status().samples < 1) throw new Error('Monitor WAL non operativo: importazione rifiutata (fail-closed).');
      // la connessione principale è riservata e NON si ricollega: se cade durante il finish l'esito è «sconosciuto» (finalizeWal)
    }
    logger.log(`destinazione cloud identificata: ${cloudTarget.kind} ${cloudTarget.ref} (${cloudTarget.database}), TLS verificato lato client, ${cloudTarget.kind === 'pooler' ? `tratto pooler→PostgreSQL ${cloudInfo.session.transport.pooler_to_postgres}` : 'sessione cifrata (pg_stat_ssl)'}, privilegi conformi`);
  } else if (url) {
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
      expectedRows: known ? LWIN_EXPECTED_ROWS : (args['expected-rows'] ? Number(args['expected-rows']) : null),
      takeover: args.takeover,
      staleMinutes: args['stale-minutes'] ? Number(args['stale-minutes']) : 10,
      allowMassRemoval: args['allow-mass-removal'],
      force: args.force,
      batchSize,
      onIdentity: (i) => { runIdentity = i; },
      // scadenza lato client del finish = statement_timeout del finish + margine (R3); interrompe l'attesa, NON la query
      finishDeadlineMs: cloudTarget ? finishDeadlineMs(cloudLimits.finishTimeoutMin) : null,
      onProgress: async ({ rows, written }) => {
        if (walGuard) await walGuard.check();
        if (cloudTarget) await db.assertIntact();
        if (written % 20000 < batchSize) logger.log(`… ${rows} righe lette, ${written} scritte`);
      },
      beforeFinish: async ({ staged }) => {
        if (!cloudTarget) return;
        await db.assertIntact();
        // controllo PREVENTIVO (euristico, non un limite rigido): WAL già usato + stima prudente del finish entro il budget
        const used = await walGuard.check();
        cloudInfo.finish_estimate = planFinishWal({ usedBytes: used, budgetBytes: cloudLimits.maxWalMb * 1048576, writtenRows: Number(staged?.new ?? 0) + Number(staged?.updated ?? 0) + Number(staged?.reappeared ?? 0) });
        if (!cloudInfo.finish_estimate.ok) {
          throw new Error(`Finish non avviato: WAL già usato ${Math.round(used / 1048576)} MB + stima del finish ${Math.round(cloudInfo.finish_estimate.projectedFinishBytes / 1048576)} MB superano il budget ${cloudLimits.maxWalMb} MB.`);
        }
        // il finish è UNA transazione di promozione: timeout dedicato (più lungo di quello dei lotti) e monitor separato che può annullarla
        await applySessionLimits(db, {
          statementTimeoutMs: cloudLimits.finishTimeoutMin * 60000,
          lockTimeoutMs: cloudLimits.lockTimeoutSec * 1000,
          idleTxTimeoutMs: cloudLimits.idleTxTimeoutSec * 1000,
        });
        walMonitor.start();
      },
      afterFinish: async ({ status }) => {
        if (!walMonitor) return null;
        // ferma il monitor (attende un campione in volo), riconcilia se la connessione principale è caduta e MISURA il WAL a fine finish:
        // un finish più rapido del timer non lascia mai l'esito al solo campionamento periodico
        finishConclusion = await concludeFinish({
          monitor: walMonitor, status,
          mainQuery: (t, p) => db.query(t, p), monitorQuery: (t, p) => monitorDb.query(t, p),
          startLsn: walGuard.start, backendPid: db.backendPid, sleep,
        });
        cloudInfo.wal_monitor = finishConclusion.monitor;
        return finishConclusion;
      },
    });
    if (cloudTarget && report.mode === 'load') {
      committedRun = true;
      // dopo il commit: limiti dei lotti ripristinati SOLO se la sessione è integra, poi verifica OBBLIGATORIA con scadenza (R3/R5).
      // Se la verifica non parte, scade, lancia o restituisce un risultato non valido, l'esito NON è un successo (exit 1).
      const post = await postCommitChecks({
        db,
        batchLimits: { statementTimeoutMs: cloudLimits.batchTimeoutSec * 1000, lockTimeoutMs: cloudLimits.lockTimeoutSec * 1000, idleTxTimeoutMs: cloudLimits.idleTxTimeoutSec * 1000 },
        verifyArgs: { runId: report.run_id, sourceCode: 'LIVEX-LWIN7', expectedSha256: expectedSha },
      });
      cloudInfo.session_limits = post.session_limits;
      cloudInfo.verification = post.verification;
    }
  }
  if (cloudInfo) {
    // esito conclusivo: SOLO `within_budget` con verifica completata e monitor affidabile vale come successo (exit 0)
    const settled = await settleCloudRun({
      cloudInfo, walGuard, walMonitor, finishConclusion, finishStatus: committedRun ? 'committed' : null, verification: cloudInfo.verification,
      budgetBytes: cloudLimits.maxWalMb * 1048576, identity: currentIdentity(null),
    });
    if (settled.exitCode) process.exitCode = 1;
    cloudInfo.log = logger.summary();
    report.cloud = cloudInfo;
  }
  report.elapsed_ms = Math.round(performance.now() - t0);
  report.peak_rss_mb = Math.round(process.memoryUsage().rss / 1048576);
  report.file_size_bytes = report.source?.size_bytes ?? null;
  if (!writeReportFile(args.report, report)) { console.error('Report NON scritto (percorso non scrivibile): esito da ricostruire dai log.'); process.exitCode = 1; }
  const anomalous = (report.cloud?.finish_outcome && !report.cloud.finish_outcome.ok) || process.exitCode === 1;
  if (anomalous) {
    const fo = report.cloud?.finish_outcome;
    console.error(fo ? `ESITO ANOMALO (${fo.outcome}): importazione NON confermata come riuscita. ${fo.known_db_state}. ${fo.next_action}` : 'ESITO ANOMALO: importazione NON confermata come riuscita (verifica non superata, report non scritto o altro esito ≠ 0: vedere i messaggi sopra e il report).');
  }
  console.log(args['dry-run'] ? 'Anteprima (nessuna scrittura):' : report.mode === 'skipped' ? 'Snapshot già importato e corrente (nessuna elaborazione):' : anomalous ? 'Caricamento NON confermato (vedi esito):' : 'Caricamento completato:', JSON.stringify(report.rows ?? report.result?.territories ?? {}), `| ${report.elapsed_ms} ms | RSS ${report.peak_rss_mb} MB`);
} catch (e) {
  console.error(`Errore: ${sanitizeError(e, logSecrets)}`);
  process.exitCode = 1;
  if (cloudInfo) {
    // report anche in caso di errore: destinazione, limiti, WAL, identificativi del run e log aiutano la diagnosi/riconciliazione (nessun segreto).
    // Ogni passo è protetto: un secondo errore (stop del monitor, lettura del WAL, verifica) non impedisce di scrivere il report.
    try {
      // finish fallito o dall'esito sconosciuto: l'esito conclusivo dice cosa si sa dello stato remoto e cosa no
      const st = e?.finish?.status ?? (committedRun ? 'committed' : null);
      const settled = await settleCloudRun({
        cloudInfo, walGuard, walMonitor, finishConclusion, finishStatus: st, verification: cloudInfo.verification,
        budgetBytes: cloudLimits.maxWalMb * 1048576, identity: currentIdentity(e), errorCode: extractSqlState(e), uncertainReason: e?.finish?.reason, failMarked: e?.failMarked, failed: true,
      });
      if (settled.outcome) console.error(`ESITO (${settled.outcome.outcome}): ${settled.outcome.known_db_state}. ${settled.outcome.next_action}`);
      cloudInfo.log = logger.summary();
    } catch {
      // l'assemblaggio dell'esito non può impedire la scrittura del report
    }
    if (!writeReportFile(args.report, { mode: 'error', error: sanitizeError(e, logSecrets), run_identity: cloudInfo.run_identity ?? null, cloud: cloudInfo })) {
      console.error('Report di errore NON scritto (percorso non scrivibile).');
    }
  }
} finally {
  // stop() idempotente e SENZA eccezioni: un secondo errore non nasconde l'esito già registrato
  if (walMonitor) await safeStopMonitor(walMonitor);
  try { if (monitorDb) await monitorDb.close(); } catch { /* connessione già chiusa */ }
  try { if (db) await db.close(); } catch { /* connessione già chiusa */ }
}
// riferimento per i test statici
export const CLI_PATH = fileURLToPath(import.meta.url);
