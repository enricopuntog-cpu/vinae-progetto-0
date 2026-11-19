// Assemblaggio dell'esito della sessione cloud per il CLI (WI-001C-FIX-03). Raccoglie in funzioni PROVABILI (senza Bun, senza rete) ciò che
// lwin-load.mjs deve fare dopo il finish, sia sul percorso di successo sia su quello d'errore, così che un secondo errore (stop del monitor,
// verifica, lettura del WAL) non possa far perdere il report né trasformare un commit confermato in un successo o in un rollback immaginario.
import { writeFileSync } from 'node:fs';
import {
  withDeadline, safeStopMonitor, runVerification, buildFinishOutcome, buildReconcile, sanitizeRunIdentity, applySessionLimits,
} from './cloud-guards.mjs';

const SESSION_STEP_DEADLINE_MS = 15_000;
const WAL_REPORT_DEADLINE_MS = 10_000;

/**
 * Dopo un commit CONFERMATO: (1) se la sessione è ancora quella verificata, ripristina i limiti dei lotti (il finish ha un timeout lungo);
 * (2) esegue la verifica obbligatoria. Se la sessione non è integra la verifica NON parte (`verification_not_run`) e i limiti non si toccano:
 * una sessione incerta non si riusa. Non lancia.
 */
export async function postCommitChecks({ db, batchLimits, verifyArgs, timers, verify }) {
  let notRunReason = null;
  let sessionLimits = 'skipped_session_not_intact';
  let lastError = null;
  try {
    if (db.state?.broken === true) throw new Error('sessione interrotta');
    if (typeof db.assertIntact === 'function') await withDeadline(db.assertIntact(), SESSION_STEP_DEADLINE_MS, 'controllo della sessione', timers);
  } catch {
    notRunReason = 'session_not_intact';
  }
  if (!notRunReason) {
    try {
      await withDeadline(applySessionLimits(db, batchLimits), SESSION_STEP_DEADLINE_MS, 'ripristino dei limiti di sessione', timers);
      sessionLimits = 'restored';
    } catch (e) {
      lastError = e;
      sessionLimits = 'restore_failed';
    }
    if (sessionLimits === 'restore_failed' && lastError?.code === 'WI_DEADLINE') {
      // la query dei limiti è ancora in volo sul socket: la sessione è incerta e non si riusa (la verifica non parte)
      if (db.state) { db.state.broken = true; db.state.why ??= 'limits_deadline'; }
      notRunReason = 'session_not_intact';
    }
  }
  const verification = await runVerification((t, p) => db.query(t, p), verifyArgs, { notRunReason, timers, verify });
  return { session_limits: sessionLimits, verification };
}

/**
 * Chiude l'esito: legge il WAL finale (con scadenza), ferma il monitor SENZA lanciare, costruisce `finish_outcome` e `reconcile`.
 * Restituisce `{ outcome, exitCode }`. Non lancia (ogni passo è protetto): un errore qui non può impedire la scrittura del report.
 *  finishStatus: 'committed' | 'failed' | 'unknown' | null (null = il finish non è mai partito).
 */
export async function settleCloudRun({
  cloudInfo, walGuard = null, walMonitor = null, finishConclusion = null, finishStatus = null, verification, budgetBytes, identity, errorCode, uncertainReason, failMarked, failed = false, timers,
}) {
  if (walGuard) {
    try {
      cloudInfo.wal = await withDeadline(walGuard.report(), WAL_REPORT_DEADLINE_MS, 'lettura finale del WAL', timers);
    } catch {
      cloudInfo.wal = { start_lsn: walGuard.start ?? null, wal_mb: null, budget_mb: Math.round(budgetBytes / 1048576), unavailable: true };
    }
  }
  if (walMonitor && !cloudInfo.wal_monitor) cloudInfo.wal_monitor = await safeStopMonitor(walMonitor);
  const safeIdentity = sanitizeRunIdentity(identity);
  cloudInfo.run_identity = safeIdentity;
  let outcome = null;
  if (finishStatus && walMonitor) {
    outcome = buildFinishOutcome({ finishStatus, conclusion: finishConclusion, verification, budgetBytes, errorCode, identity: safeIdentity, uncertainReason, failMarked });
    cloudInfo.finish_outcome = outcome;
  } else {
    // nessun finish concluso (errore prima del finish, oppure dry-run): gli identificativi servono comunque a ritrovare il tentativo
    cloudInfo.reconcile = buildReconcile(safeIdentity);
  }
  let exitCode = 0;
  if (outcome) exitCode = outcome.exit_code;
  if (verification && verification.ok !== true) exitCode = 1;
  if (failed) exitCode = 1;
  return { outcome, exitCode };
}

/** Scrive il report (0600). Restituisce true se riuscito; non lancia (il report di errore è best effort, ma il fallimento è dichiarato). */
export function writeReportFile(path, payload, write = writeFileSync) {
  try {
    write(path, JSON.stringify(payload, null, 2), { mode: 0o600 });
    return true;
  } catch {
    return false;
  }
}
