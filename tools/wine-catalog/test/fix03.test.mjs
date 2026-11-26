// WI-001C-FIX-03 (R1–R6): riconciliazione univoca, esito incerto del finish, scadenze, stop() del monitor, verifica post-commit, parser SQL.
// Prove deterministiche: database finto, timer finti, fixture di due righe, nessuna rete, nessun dataset LWIN.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LWIN_COLUMNS } from '../lib/lwin.mjs';
import { makeXlsx } from './make-xlsx.mjs';
import { loadToDatabase } from '../lib/load.mjs';
import {
  createWalMonitor, concludeFinish, finalizeWal, buildFinishOutcome, safeStopMonitor, runVerification, withDeadline, finishDeadlineMs,
  sanitizeRunIdentity, buildReconcile, MONITOR_SQL, WAL_OUTCOMES, FINISH_DEADLINE_MARGIN_MS, RECONCILE_RUNBOOK_SECTION, VERIFICATION_NOT_RUN,
  VERIFY_CHECK_DEADLINE_MS, VERIFY_STATEMENT_TIMEOUT_MS,
} from '../lib/cloud-guards.mjs';
import { classifyFinishError, extractSqlState } from '../lib/finish-error.mjs';
import { postCommitChecks, settleCloudRun, writeReportFile } from '../lib/cloud-outcome.mjs';
import { sanitizeSqlForFilter } from '../lib/sql-scan.mjs';
import { assertCallerSql } from '../lib/db-bun.mjs';

const MB = 1048576;
const HERE = dirname(fileURLToPath(import.meta.url));
const RUN_ID = '00000000-0000-4000-8000-000000000001';
const row = (o) => LWIN_COLUMNS.map((c) => (c in o ? o[c] : c === 'REFERENCE' ? '' : 'NA'));
const W = (lwin) => row({ LWIN: lwin, STATUS: 'Live', DISPLAY_NAME: `Prod, Vino ${lwin}`, PRODUCER_NAME: 'Prod', WINE: `Vino ${lwin}`, COUNTRY: 'Italy', REGION: 'Piedmont', COLOUR: 'Red', TYPE: 'Wine' });

async function withFile(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-fix03-'));
  try {
    const p = join(dir, 'lwin.xlsx');
    writeFileSync(p, makeXlsx([LWIN_COLUMNS, W('1000001'), W('1000002')]));
    return await fn(p, dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function fakeTimers() {
  const pending = new Map();
  let n = 0;
  return {
    setTimeout: (fn) => { n += 1; pending.set(n, fn); return n; },
    clearTimeout: (id) => { pending.delete(id); },
    fireAll() { for (const [id, fn] of [...pending]) { pending.delete(id); fn(); } },
    count: () => pending.size,
  };
}
const flush = () => new Promise((r) => setImmediate(r));
const serverError = (sqlstate, message = 'errore del server') => Object.assign(new Error(message), { code: 'ERR_POSTGRES_SERVER_ERROR', errno: sqlstate });

/** Database cloud finto (con `state`, `backendPid`): imita le funzioni catalog.* e registra le chiamate. */
function world({ onFinish, bytes = 0 } = {}) {
  const w = { bytes, failCalls: 0, finishCalls: 0, calls: [] };
  const db = {
    state: { broken: false },
    backendPid: 4242,
    async query(text, params = []) {
      w.calls.push(text);
      if (db.state?.broken) throw new Error('Sessione cloud interrotta: la connessione è caduta e non viene riaperta (fail-closed).');
      if (text.includes('begin_import_run')) return { rows: [{ r: { run_id: RUN_ID, mode: 'import' } }] };
      if (text.includes('stage_source_records')) { const k = JSON.parse(params[1]).length; return { rows: [{ r: { received: k, new: k, updated: 0, unchanged: 0, reappeared: 0 } }] }; }
      if (text.includes('record_findings')) return { rows: [{ n: 0 }] };
      if (text.includes('fail_import_run')) { w.failCalls += 1; return { rows: [] }; }
      if (text.includes('pg_wal_lsn_diff')) return { rows: [{ bytes: w.bytes }] };
      if (text.includes('finish_import_run')) { w.finishCalls += 1; await onFinish?.(w, db); return { rows: [{ r: { records_seen: Number(params[1]) } }] }; }
      throw new Error(`istruzione non prevista: ${text}`);
    },
  };
  const monitorQuery = async (text) => {
    if (text === MONITOR_SQL.wal) return { rows: [{ bytes: w.bytes }] };
    if (text === MONITOR_SQL.activity) return { rows: [] };
    if (text === MONITOR_SQL.cancel) return { rows: [{ ok: true }] };
    throw new Error(`istruzione di monitor non prevista: ${text}`);
  };
  return { w, db, monitorQuery };
}
const okMonitor = (q) => createWalMonitor({ query: q, backendPid: 4242, startLsn: '0/16B3748', maxWalMb: 100, setTimer: () => ({ unref() {} }), clearTimer: () => {} });

/** Compone gli stessi pezzi del CLI: identità → finish → conclusione → esito. */
async function runLoad(file, { onFinish, finishDeadlineMs: dl = null, timers, monitor: customMonitor } = {}) {
  const sim = world({ onFinish });
  const monitor = customMonitor ?? okMonitor(sim.monitorQuery);
  await monitor.sample?.();
  let identity = null;
  let conclusion = null;
  try {
    const report = await loadToDatabase(sim.db, file, {
      onIdentity: (i) => { identity = i; },
      finishDeadlineMs: dl,
      timers,
      afterFinish: async ({ status }) => {
        conclusion = await concludeFinish({ monitor, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery: (t, p) => sim.monitorQuery(t, p), startLsn: '0/16B3748', backendPid: 4242, sleep: async () => {}, timers });
        return conclusion;
      },
    });
    return { ...sim, monitor, report, identity, conclusion, error: null };
  } catch (error) {
    return { ...sim, monitor, report: null, identity, conclusion, error };
  }
}

// --- R1 ---------------------------------------------------------------------------------------------------------------------------------

test('R1 — connessione persa durante il finish: gli identificativi (run_id, fonte, sha256, file, backend) sono nell\'errore e in finish_outcome.reconcile', async () => {
  await withFile(async (file) => {
    const r = await runLoad(file, { onFinish: async (_w, db) => { db.state.broken = true; throw Object.assign(new Error('Connection closed'), { code: 'ERR_POSTGRES_CONNECTION_CLOSED' }); } });
    assert.equal(r.error.finish.status, 'unknown');
    assert.equal(r.w.failCalls, 0);
    const id = r.error.runIdentity;
    assert.equal(id.run_id, RUN_ID);
    assert.equal(id.source_code, 'LIVEX-LWIN7');
    assert.match(id.file_sha256, /^[0-9a-f]{64}$/);
    assert.equal(id.file_name, 'lwin.xlsx');
    assert.equal(id.backend_pid, 4242);
    assert.deepEqual(r.identity, id, 'lo stesso valore arriva all\'hook onIdentity');
    const o = buildFinishOutcome({ finishStatus: r.error.finish.status, conclusion: r.conclusion, budgetBytes: 100 * MB, identity: id, uncertainReason: r.error.finish.reason });
    assert.equal(o.outcome, WAL_OUTCOMES.FINISH_UNKNOWN);
    assert.deepEqual({ ...o.reconcile }, { ...buildReconcile(id) });
    for (const k of ['run_id', 'source_code', 'file_sha256', 'file_name', 'backend_pid']) assert.equal(o.reconcile[k], id[k], k);
    assert.equal(o.reconcile.runbook_section, RECONCILE_RUNBOOK_SECTION);
    assert.match(o.next_action, /NON ripetere/);
    assert.match(o.next_action, /fail_import_run/);
  });
});

test('R1 — identità disponibile anche per errori DOPO begin_import_run e PRIMA del finish, e (senza run_id) per un errore di begin', async () => {
  await withFile(async (file) => {
    const sim = world();
    const realQuery = sim.db.query;
    sim.db.query = async (t, p) => { if (t.includes('stage_source_records')) throw new Error('lotto rifiutato'); return realQuery(t, p); };
    await assert.rejects(() => loadToDatabase(sim.db, file, {}), (e) => e.runIdentity?.run_id === RUN_ID && e.runIdentity.backend_pid === 4242);
    const sim2 = world();
    const q2 = sim2.db.query;
    sim2.db.query = async (t, p) => { if (t.includes('begin_import_run')) throw Object.assign(new Error('Connection closed'), { code: 'ERR_POSTGRES_CONNECTION_CLOSED' }); return q2(t, p); };
    await assert.rejects(() => loadToDatabase(sim2.db, file, {}), (e) => e.runIdentity?.run_id === null && /^[0-9a-f]{64}$/.test(e.runIdentity.file_sha256) && e.runIdentity.file_name === 'lwin.xlsx');
    const rec = buildReconcile({ run_id: null, source_code: 'LIVEX-LWIN7', file_sha256: 'a'.repeat(64), file_name: 'x.xlsx' });
    assert.match(rec.lookup, /run_id sconosciuto/);
  });
});

test('R1 — sanitizeRunIdentity: solo forme attese, nessun percorso, nessun segreto, nessun testo libero', () => {
  const id = sanitizeRunIdentity({
    run_id: 'non-un-uuid', source_code: 'postgresql://u:segreto@h/db', file_sha256: 'xyz', file_name: 'C:\\Users\\mario\\dati\\lwin.xlsx\u0000', backend_pid: '12', extra: 'password=segreto',
  });
  assert.deepEqual(id, { run_id: null, source_code: null, file_sha256: null, file_name: 'lwin.xlsx', backend_pid: null });
  assert.equal(JSON.stringify(id).includes('segreto'), false);
  assert.equal(Object.keys(id).length, 5);
});

test('R1 — il runbook ha davvero la sezione citata dai messaggi di riconciliazione', () => {
  const rb = readFileSync(join(HERE, '..', '..', '..', 'docs', 'wine-intelligence', 'CLOUD_IMPORT_RUNBOOK.md'), 'utf8');
  assert.ok(rb.split('\n').some((l) => /^#{2,3} /.test(l) && l.includes(RECONCILE_RUNBOOK_SECTION)), 'intestazione «Esito incerto del finish» mancante');
});

// --- R2 ---------------------------------------------------------------------------------------------------------------------------------

test('R2 — errore client SENZA SQLSTATE durante il finish: esito sconosciuto, NESSUNA chiamata a fail_import_run, sessione non riusata, nessuna ripetizione, nessun rollback dichiarato', async () => {
  await withFile(async (file) => {
    const r = await runLoad(file, { onFinish: async () => { throw new TypeError('risposta non decodificabile'); } });
    assert.equal(r.error.finish.status, 'unknown');
    assert.equal(r.error.finish.reason, 'no_reliable_sqlstate');
    assert.equal(r.error.finish.sqlstate, null);
    assert.equal(r.w.failCalls, 0, 'fail_import_run cancellerebbe finding e staging di un run forse già confermato');
    assert.equal(r.w.calls.filter((c) => c.includes('fail_import_run')).length, 0);
    assert.equal(r.w.finishCalls, 1, 'nessun secondo finish');
    assert.equal(r.db.state.broken, true, 'sessione incerta: non riutilizzabile');
    const o = buildFinishOutcome({ finishStatus: 'unknown', conclusion: r.conclusion, budgetBytes: 100 * MB, identity: r.error.runIdentity, uncertainReason: r.error.finish.reason });
    assert.equal(o.outcome, WAL_OUTCOMES.FINISH_UNKNOWN);
    assert.equal(o.exit_code, 1);
    assert.equal(o.known_db_state, 'sconosciuto');
    assert.equal(o.states.database, 'unknown');
    assert.ok(o.failure_reasons.includes('finish_unknown_no_reliable_sqlstate'));
    assert.doesNotMatch(`${o.known_db_state} ${o.residual_uncertainty} ${o.next_action}`, /rollback (completo|eseguito|riuscito|noto)|annullat[oa] con successo/i);
  });
});

test('R2 — matrice di classificazione: solo un errore del server con SQLSTATE affidabile su sessione integra prova il rollback', () => {
  const c = (e, o) => classifyFinishError(e, { cloud: true, ...o });
  // sconosciuto
  for (const code of ['08000', '08006', '08003', '57P01', '57P02', '57P03', '57P04', '57P05', '58030', 'XX000']) {
    assert.equal(c(serverError(code)).status, 'unknown', code);
  }
  assert.equal(c(Object.assign(new Error('x'), { code: 'ERR_POSTGRES_CONNECTION_CLOSED' })).reason, 'connection_lost');
  assert.equal(c(Object.assign(new Error('read'), { code: 'ECONNRESET', syscall: 'read' })).status, 'unknown');
  assert.equal(c(Object.assign(new Error('x'), { code: 'EPIPE' })).status, 'unknown', 'EPIPE non è uno SQLSTATE');
  assert.equal(c(new TypeError('decodifica')).reason, 'no_reliable_sqlstate');
  assert.equal(c(new Error('canceling statement due to user request')).status, 'unknown', 'il testo non basta: serve lo SQLSTATE');
  assert.equal(c('stringa nuda').status, 'unknown');
  assert.equal(c(null).status, 'unknown');
  assert.equal(c(Object.assign(new Error('x'), { code: 'ERR_POSTGRES_SERVER_ERROR' })).status, 'unknown', 'errno assente');
  assert.equal(c(Object.assign(new Error('x'), { errno: '23505' })).status, 'unknown', 'errno vale solo con code = ERR_POSTGRES_SERVER_ERROR');
  assert.equal(c(Object.assign(new Error('x'), { code: 'WI_DEADLINE' })).reason, 'deadline_expired');
  assert.equal(c(serverError('40001'), { sessionBroken: true }).status, 'unknown');
  assert.equal(c(serverError('23505', 'duplicate key ... socket ...')).status, 'failed', 'un messaggio del server con la parola «socket» non lo rende incerto');
  // fallito (rollback noto)
  for (const code of ['23505', '40001', '40P01', '22P02', '42804', 'P0001', '53200', '55P03']) assert.equal(c(serverError(code)).status, 'failed', code);
  assert.equal(c(Object.assign(new Error('x'), { sqlState: '23514' })).status, 'failed');
  // 57014: copre statement_timeout E pg_cancel_backend; errore del server su sessione integra = istruzione interrotta
  const t = c(serverError('57014'));
  assert.equal(t.status, 'failed');
  assert.equal(t.reason, 'query_canceled_server_reported');
  assert.equal(c(serverError('57014'), { sessionBroken: true }).status, 'unknown');
  // locale: regola storica
  assert.equal(classifyFinishError(new Error('qualunque'), { cloud: false }).status, 'failed');
  assert.equal(extractSqlState(Object.assign(new Error('x'), { code: '23505', syscall: 'read' })), null);
  assert.equal(extractSqlState(Object.assign(new Error('x'), { code: '23505' })), '23505');
});

test('R2 — errore del server con SQLSTATE affidabile (23505): rollback noto, fail_import_run chiamato UNA volta, esito failed_before_commit', async () => {
  await withFile(async (file) => {
    const r = await runLoad(file, { onFinish: async () => { throw serverError('23505', 'duplicate key'); } });
    assert.equal(r.error.finish.status, 'failed');
    assert.equal(r.error.finish.sqlstate, '23505');
    assert.equal(r.w.failCalls, 1);
    assert.equal(r.db.state.broken, false, 'sessione integra');
    const o = buildFinishOutcome({ finishStatus: 'failed', conclusion: r.conclusion, budgetBytes: 100 * MB, errorCode: extractSqlState(r.error), identity: r.error.runIdentity });
    assert.equal(o.outcome, WAL_OUTCOMES.FAILED_BEFORE_COMMIT);
    assert.equal(o.states.database, 'rolled_back_known');
  });
});

test('R2 — 57014 senza una richiesta di annullamento riuscita del monitor NON è attribuito al monitor (cancelled_before_commit richiede il monitor)', () => {
  const fin = { ok: true, bytes: MB, via: 'principale' };
  const idle = { samples: 1, peakBytes: MB, exceeded: false, cancelRequested: false, cancelOk: null, cancelAttempts: 0, lost: false };
  assert.equal(finalizeWal({ finish: 'failed', monitor: idle, finalWal: fin, budgetBytes: 100 * MB, errorCode: '57014' }).outcome, WAL_OUTCOMES.FAILED_BEFORE_COMMIT);
});

// --- R3 ---------------------------------------------------------------------------------------------------------------------------------

test('R3 — scadenza del finish: l\'attesa JavaScript finisce, l\'esito è SCONOSCIUTO (mai «annullato»), sessione non riutilizzabile, nessun secondo finish, nessun fail_import_run', async () => {
  await withFile(async (file) => {
    const timers = fakeTimers();
    const never = new Promise(() => {}); // la query «continua» sul server
    const sim = world({ onFinish: () => never });
    const monitor = okMonitor(sim.monitorQuery);
    await monitor.sample();
    let conclusion = null;
    const p = loadToDatabase(sim.db, file, {
      finishDeadlineMs: finishDeadlineMs(1), timers,
      afterFinish: async ({ status }) => {
        conclusion = await concludeFinish({ monitor, status, mainQuery: (t, q) => sim.db.query(t, q), monitorQuery: (t, q) => sim.monitorQuery(t, q), startLsn: '0/16B3748', backendPid: 4242, sleep: async () => {}, timers });
        return conclusion;
      },
    });
    const settled = p.then(() => null, (e) => e);
    // il file xlsx si legge con I/O reale: si attende (al massimo 3 s) che il finish sia partito e la sua scadenza armata
    for (let i = 0; i < 600 && timers.count() === 0; i += 1) await new Promise((r) => setTimeout(r, 5));
    assert.equal(sim.w.finishCalls, 1, 'il finish è partito e non risponde');
    timers.fireAll(); // scade la scadenza del finish
    const e = await settled;
    assert.equal(e.finish.status, 'unknown');
    assert.equal(e.finish.reason, 'deadline_expired');
    assert.equal(e.code, 'WI_DEADLINE');
    assert.equal(sim.w.finishCalls, 1);
    assert.equal(sim.w.failCalls, 0);
    assert.equal(sim.db.state.broken, true);
    assert.equal(conclusion.finalWal.via, 'monitor', 'la sessione scaduta non si riusa: la misura passa dal monitor');
    const o = buildFinishOutcome({ finishStatus: 'unknown', conclusion, budgetBytes: 100 * MB, identity: e.runIdentity, uncertainReason: e.finish.reason });
    assert.equal(o.outcome, WAL_OUTCOMES.FINISH_UNKNOWN);
    assert.equal(o.exit_code, 1);
    assert.match(o.residual_uncertainty, /NON annulla nulla/);
    assert.match(o.residual_uncertainty, /ancora in esecuzione o aver confermato/);
    assert.doesNotMatch(`${o.known_db_state} ${o.residual_uncertainty} ${o.next_action}`, /annullat[oa] con successo|rollback (completo|eseguito|riuscito|noto)/i);
    assert.ok(o.failure_reasons.includes('finish_unknown_deadline_expired'));
  });
});

test('R3 — scadenza = finishTimeoutMin + margine documentato; valori non validi rifiutati; withDeadline marca l\'errore e libera il timer', async () => {
  assert.equal(finishDeadlineMs(30), 30 * 60_000 + FINISH_DEADLINE_MARGIN_MS);
  assert.ok(FINISH_DEADLINE_MARGIN_MS >= 30_000, 'il server deve poter scadere (statement_timeout) prima del client');
  assert.throws(() => finishDeadlineMs(0), /non valido/);
  assert.throws(() => finishDeadlineMs('x'), /non valido/);
  const timers = fakeTimers();
  const p = withDeadline(new Promise(() => {}), 5, 'x', timers);
  timers.fireAll();
  await assert.rejects(p, (e) => e.code === 'WI_DEADLINE');
  assert.equal(timers.count(), 0);
});

test('R3 — conclusione del finish: scadenza complessiva (nessun polling infinito); la misura non completata resta «non verificabile», mai assunta', async () => {
  const timers = fakeTimers();
  const sim = world({ bytes: 10 * MB });
  const monitor = okMonitor(sim.monitorQuery);
  const probes = [];
  const mq = async (t) => { if (t === MONITOR_SQL.activity) { probes.push(1); return { rows: [{ state: 'active' }] }; } return sim.monitorQuery(t); };
  const p = concludeFinish({ monitor, status: 'unknown', mainQuery: sim.db.query, monitorQuery: mq, startLsn: '0/16B3748', backendPid: 4242, sleep: () => new Promise(() => {}), timers, deadlineMs: 50 });
  for (let i = 0; i < 20; i += 1) await flush();
  timers.fireAll();
  const c = await p;
  assert.equal(c.deadline_expired, true);
  assert.equal(c.finalWal.ok, false);
  assert.equal(probes.length, 1, 'nessuna sonda oltre la scadenza: nessun polling infinito');
  const o = buildFinishOutcome({ finishStatus: 'committed', conclusion: c, verification: { status: 'completed', ok: true, checks: [] }, budgetBytes: 100 * MB });
  assert.equal(o.outcome, WAL_OUTCOMES.MONITOR_LOST);
  assert.ok(o.failure_reasons.includes('conclusion_deadline_expired'));
});

test('R3 — limiti dei lotti ripristinati SOLO se la sessione è integra; sessione non integra: nessun ripristino e verifica non eseguita', async () => {
  const batch = { statementTimeoutMs: 1000, lockTimeoutMs: 2000, idleTxTimeoutMs: 3000 };
  const limitsCalls = [];
  const intact = { state: { broken: false }, assertIntact: async () => {}, setLimits: async (t, p) => limitsCalls.push(p), query: async () => ({ rows: [] }) };
  const verifyOk = async () => ({ ok: true, checks: [{ id: 'V01', ok: true }] });
  const r1 = await postCommitChecks({ db: intact, batchLimits: batch, verifyArgs: {}, verify: verifyOk });
  assert.equal(r1.session_limits, 'restored');
  // WI-008 / J3: prima i limiti della verifica, poi (a verifica finita) quelli dei lotti
  assert.deepEqual(limitsCalls, [[String(VERIFY_STATEMENT_TIMEOUT_MS), '2000', '3000'], ['1000', '2000', '3000']]);
  assert.equal(r1.verification.status, 'completed');
  assert.equal(r1.verification.ok, true);
  // sessione marcata interrotta
  const limits2 = [];
  let verified = 0;
  const broken = { state: { broken: true }, assertIntact: async () => {}, setLimits: async (t, p) => limits2.push(p), query: async () => ({ rows: [] }) };
  const r2 = await postCommitChecks({ db: broken, batchLimits: batch, verifyArgs: {}, verify: async () => { verified += 1; return { ok: true, checks: [] }; } });
  assert.deepEqual([r2.session_limits, r2.verification.status, r2.verification.reason, limits2.length, verified], ['skipped_session_not_intact', 'not_run', 'verification_not_run', 0, 0]);
  // assertIntact lancia (backend diverso)
  const changed = { state: { broken: false }, assertIntact: async () => { throw new Error('backend diverso'); }, setLimits: async () => { throw new Error('non va chiamato'); }, query: async () => ({ rows: [] }) };
  const r3 = await postCommitChecks({ db: changed, batchLimits: batch, verifyArgs: {}, verify: verifyOk });
  assert.equal(r3.verification.status, 'not_run');
  // ripristino fallito: dichiarato, la verifica prosegue con la propria scadenza
  const flaky = { state: { broken: false }, assertIntact: async () => {}, setLimits: async () => { throw new Error('rotta'); }, query: async () => ({ rows: [] }) };
  const r4 = await postCommitChecks({ db: flaky, batchLimits: batch, verifyArgs: {}, verify: verifyOk });
  assert.deepEqual([r4.session_limits, r4.verification.status], ['restore_failed', 'completed']);
});

// --- R4 ---------------------------------------------------------------------------------------------------------------------------------

test('R4 — commit confermato, WAL entro budget, monitor.stop() LANCIA → monitor_lost, stop_failed, exit 1, report SALVATO', async () => {
  await withFile(async (file, dir) => {
    const sim = world({ bytes: 5 * MB, onFinish: async (w) => { w.bytes += 20 * MB; } });
    const real = okMonitor(sim.monitorQuery);
    await real.sample();
    const throwing = { sample: real.sample, start: real.start, status: real.status, stop: async () => { throw new Error('stop esploso: password=segreto'); } };
    let conclusion = null;
    const report = await loadToDatabase(sim.db, file, {
      beforeFinish: async () => { real.start(); },
      afterFinish: async ({ status }) => {
        conclusion = await concludeFinish({ monitor: throwing, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery: (t, p) => sim.monitorQuery(t, p), startLsn: '0/16B3748', backendPid: 4242, sleep: async () => {} });
        return conclusion;
      },
    });
    assert.equal(report.finish.status, 'committed');
    assert.equal(conclusion.monitor.stop_failed, true);
    assert.equal(conclusion.monitor.lost, true);
    const cloudInfo = {}; // wal_monitor assente: settleCloudRun deve fermare il monitor da sé (secondo stop() che lancia)
    // anche il walGuard.report() e il secondo stop() possono lanciare: il report si scrive comunque
    const settled = await settleCloudRun({
      cloudInfo, walGuard: { start: '0/16B3748', report: async () => { throw new Error('lettura WAL rotta'); } }, walMonitor: throwing, finishConclusion: conclusion, finishStatus: 'committed',
      verification: { status: 'completed', ok: true, checks: [] }, budgetBytes: 100 * MB, identity: { run_id: RUN_ID, source_code: 'LIVEX-LWIN7', file_sha256: 'b'.repeat(64), file_name: 'lwin.xlsx', backend_pid: 4242 },
    });
    assert.equal(settled.outcome.outcome, WAL_OUTCOMES.MONITOR_LOST);
    assert.equal(settled.outcome.ok, false);
    assert.equal(settled.outcome.exit_code, 1);
    assert.equal(settled.exitCode, 1);
    assert.equal(settled.outcome.states.monitor, 'stop_failed');
    assert.equal(settled.outcome.states.database, 'committed');
    assert.ok(settled.outcome.failure_reasons.includes('monitor_stop_failed'));
    assert.ok(settled.outcome.failure_reasons.includes('monitor_unreliable'));
    assert.equal(settled.outcome.wal.measured_mb, 25, 'il WAL entro budget (5 MB iniziali + 20 MB del finish) è comunque misurato');
    assert.equal(cloudInfo.wal.unavailable, true, 'WAL finale illeggibile: dichiarato, non inventato');
    assert.equal(cloudInfo.wal_monitor.stop_failed, true, 'il secondo stop() lanciato è registrato, non perso');
    const path = join(dir, 'report.json');
    assert.equal(writeReportFile(path, { mode: 'load', cloud: cloudInfo }), true);
    const saved = JSON.parse(readFileSync(path, 'utf8'));
    assert.equal(saved.cloud.finish_outcome.outcome, 'monitor_lost');
    assert.equal(saved.cloud.finish_outcome.reconcile.run_id, RUN_ID);
    assert.equal(JSON.stringify(saved).includes('segreto'), false, 'il testo dell\'errore di stop non finisce nel report');
    assert.equal(writeReportFile(join(dir, 'nessuna', 'cartella', 'r.json'), {}), false, 'un report non scrivibile è dichiarato, non lanciato');
  });
});

test('R4 — safeStopMonitor: idempotente, non lancia mai, conserva quanto noto; stop() reale ripetibile', async () => {
  const bad = { status: () => ({ samples: 3, peakBytes: 7 }), stop: async () => { throw new Error('x'); } };
  const a = await safeStopMonitor(bad);
  const b = await safeStopMonitor(bad);
  assert.deepEqual(a, b);
  assert.equal(a.stop_failed, true);
  assert.equal(a.samples, 3);
  assert.equal((await safeStopMonitor({ stop: async () => { throw new Error('x'); } })).lost, true, 'anche senza status()');
  assert.equal(await safeStopMonitor(null), null);
  const sim = world();
  const m = okMonitor(sim.monitorQuery);
  await m.sample();
  const s1 = await safeStopMonitor(m);
  const s2 = await safeStopMonitor(m);
  assert.equal(s1.running, false);
  assert.equal(s2.stop_failed, undefined);
});

test('R4 — la rilevazione degli sforamenti WAL (FIX-02) non cambia: 400/100 MB dopo il commit resta over_budget_after_commit', () => {
  const o = finalizeWal({ finish: 'committed', monitor: { samples: 1, peakBytes: MB, cancelAttempts: 0, cancelOk: null }, finalWal: { ok: true, bytes: 400 * MB, via: 'principale' }, budgetBytes: 100 * MB, verification: { status: 'completed', ok: true, checks: [] } });
  assert.equal(o.outcome, WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT);
  assert.equal(o.exit_code, 1);
});

// --- R5 ---------------------------------------------------------------------------------------------------------------------------------

test('R5 — commit confermato ma verifica non eseguita / lanciata / scaduta / non valida: mai ok:true, exit ≠ 0, stati distinti', async () => {
  const good = { finishStatus: 'committed', conclusion: { monitor: { samples: 2, peakBytes: MB, cancelAttempts: 0, cancelOk: null, lost: false }, remote: null, finalWal: { ok: true, bytes: 10 * MB, via: 'principale' } }, budgetBytes: 100 * MB };
  const base = buildFinishOutcome({ ...good, verification: { status: 'completed', ok: true, checks: [{ id: 'V01', ok: true }] } });
  assert.deepEqual([base.outcome, base.ok, base.exit_code, base.states], [WAL_OUTCOMES.WITHIN_BUDGET, true, 0, { database: 'committed', verification: 'passed', monitor: 'reliable', overall: 'within_budget' }]);
  // non eseguita (esplicita) e assente (obbligatoria dopo il commit)
  for (const v of [VERIFICATION_NOT_RUN, undefined]) {
    const o = buildFinishOutcome({ ...good, verification: v });
    assert.equal(o.ok, false);
    assert.equal(o.exit_code, 1);
    assert.ok(o.failure_reasons.includes('verification_not_run'));
    assert.deepEqual([o.states.database, o.states.verification, o.states.monitor], ['committed', 'not_run', 'reliable']);
    assert.match(o.known_db_state, /CONFERMATA/, 'un commit confermato non diventa un rollback immaginario');
    assert.doesNotMatch(o.known_db_state, /rollback/);
  }
  // lanciata, scaduta, risultato non valido
  const timers = fakeTimers();
  const thrown = await runVerification(async () => ({ rows: [] }), {}, { verify: async () => { throw new Error('boom'); } });
  assert.deepEqual([thrown.status, thrown.ok, thrown.reason], ['failed', false, 'verification_error']);
  const slow = runVerification(async () => ({ rows: [] }), {}, { verify: () => new Promise(() => {}), deadlineMs: 5, timers });
  for (let i = 0; i < 5; i += 1) await flush();
  timers.fireAll();
  assert.deepEqual([(await slow).status, (await slow).reason], ['failed', 'verification_deadline']);
  for (const bad of [undefined, null, 7, {}, { ok: 'sì', checks: [] }, { ok: true }, { ok: true, checks: 'x' }]) {
    const v = await runVerification(async () => ({ rows: [] }), {}, { verify: async () => bad });
    assert.deepEqual([v.status, v.ok, v.reason], ['failed', false, 'verification_invalid_result'], JSON.stringify(bad));
    const o = buildFinishOutcome({ ...good, verification: v });
    assert.equal(o.ok, false);
    assert.ok(o.failure_reasons.includes('verification_failed'));
    assert.equal(o.states.verification, 'failed');
  }
  // controlli falliti ≠ verifica non completata
  const failed = buildFinishOutcome({ ...good, verification: { status: 'completed', ok: false, checks: [{ id: 'V04_stage_emptied', ok: false }] } });
  assert.equal(failed.states.verification, 'failed_checks');
  assert.match(failed.next_action, /V04_stage_emptied/);
  // il risultato valido di verifyFinish passa invariato
  const okv = await runVerification(async () => ({ rows: [] }), {}, { verify: async () => ({ ok: true, checks: [{ id: 'V01', ok: true }], duration_seconds: 3 }) });
  assert.deepEqual([okv.status, okv.ok, okv.duration_seconds], ['completed', true, 3]);
});

test('R5 — settleCloudRun: verifica non completata → exit 1 anche con WAL entro budget; successo pieno → exit 0', async () => {
  const conclusion = { monitor: { samples: 2, peakBytes: MB, cancelAttempts: 0, cancelOk: null, lost: false }, remote: null, finalWal: { ok: true, bytes: 10 * MB, via: 'principale' } };
  const walMonitor = { stop: async () => conclusion.monitor };
  const run = (verification) => settleCloudRun({ cloudInfo: { wal_monitor: conclusion.monitor }, walMonitor, finishConclusion: conclusion, finishStatus: 'committed', verification, budgetBytes: 100 * MB, identity: { run_id: RUN_ID } });
  assert.equal((await run(VERIFICATION_NOT_RUN)).exitCode, 1);
  assert.equal((await run({ status: 'failed', ok: false, reason: 'verification_deadline', checks: [] })).exitCode, 1);
  assert.equal((await run({ status: 'completed', ok: true, checks: [] })).exitCode, 0);
});

// --- R6 ---------------------------------------------------------------------------------------------------------------------------------

test('R6 — `x$q$; reset role;`: il `$` dentro un identificativo non apre una stringa a dollaro (il filtro vede ancora RESET ROLE)', () => {
  const clean = sanitizeSqlForFilter('select 1 as x$q$; reset role;');
  assert.match(clean, /reset role/);
  assert.throws(() => assertCallerSql('select 1 as x$q$; reset role;'), /non ammesso/);
  assert.doesNotThrow(() => sanitizeSqlForFilter('select x$q$ aperto'), 'niente falso «letterale non chiuso» per un identificativo');
  assert.throws(() => assertCallerSql('select x$$; reset role'), /non ammesso/);
  assert.throws(() => assertCallerSql('select a$b$, set_config(\'role\', \'postgres\', false)'), /non ammesso/);
  assert.match(sanitizeSqlForFilter('select _x9$tag$; set role postgres'), /set role postgres/);
  assert.match(sanitizeSqlForFilter('select é$q$; reset role;'), /reset role/, 'carattere non ASCII nell\'identificativo');
});

test('R6 — una stringa a dollaro vera resta una stringa (positivi), dopo spazio, virgola, parentesi, letterale e identificativo quotato', () => {
  assert.doesNotMatch(sanitizeSqlForFilter('select $$ reset role; $$'), /reset role/);
  assert.doesNotMatch(sanitizeSqlForFilter('select $q$ set_config $q$'), /set_config/);
  assert.doesNotMatch(sanitizeSqlForFilter('select($$ reset role $$)'), /reset role/);
  assert.doesNotMatch(sanitizeSqlForFilter('select 1,$a$ reset role $a$'), /reset role/);
  assert.doesNotMatch(sanitizeSqlForFilter('select "x"$q$ reset role $q$'), /reset role/, 'dopo un identificativo quotato il `$` è un nuovo token');
  assert.doesNotMatch(sanitizeSqlForFilter('select $a$x$a$ $b$ reset role $b$'), /reset role/, 'stringa a dollaro chiusa e poi un\'altra');
  assert.throws(() => sanitizeSqlForFilter('select $q$ aperto'), /non leggibile/);
  assert.doesNotThrow(() => assertCallerSql('select $$a; reset role$$ as t'));
  assert.doesNotThrow(() => assertCallerSql("select 'a; reset role' as t"));
  assert.doesNotThrow(() => assertCallerSql('select "x$q$" from catalog.sources'));
  assert.doesNotThrow(() => assertCallerSql('select 1 -- ; reset role\n'));
  assert.doesNotThrow(() => assertCallerSql('select /* ; reset role */ 1'));
  assert.doesNotThrow(() => assertCallerSql("select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r"));
});

test('R6 — il filtro del chiamante resta restrittivo (negativi): ruolo, transazione, più istruzioni, DML, set_config, sola lettura', () => {
  for (const bad of [
    'select 1; reset role', 'reset role', 'set role postgres', 'SET/**/ROLE postgres', 'select set_config(\'role\',\'x\',false)', 'select "set_config"(1)',
    'begin', 'commit', 'select 1; select 2', 'insert into catalog.sources values (1)', 'delete from catalog.source_records', 'truncate catalog.source_records',
    'select 1 /* x */; set session authorization postgres', 'select 1 where transaction_read_only = $$on$$ ; reset all',
  ]) assert.throws(() => assertCallerSql(bad), /non ammess|Cambio|Istruzione/, bad);
  assert.throws(() => assertCallerSql('update catalog.sources set code = 1', { readOnly: true }));
  assert.throws(() => assertCallerSql('select catalog.finish_import_run(1) into x', { readOnly: true }));
  assert.doesNotThrow(() => assertCallerSql('with x as (select 1) select * from x', { readOnly: true }));
  assert.doesNotThrow(() => assertCallerSql('select 1', { readOnly: true }));
});

// --- correzioni dopo la revisione interna (FIX-03) ---------------------------------------------------------------------------------

test('revisione — parser: tag a dollaro non ASCII o lunghi, commento chiuso da CR, `$` non riconosciuto → il filtro vede RESET ROLE o rifiuta', () => {
  const longTag = `a${'b'.repeat(100)}`;
  for (const bad of [
    "select $é$ ' $é$; reset role; --'",
    `select $${longTag}$ ' $${longTag}$; reset role; select $${longTag}$'$${longTag}$`,
    'select 1 -- x\r; reset role',
    "select éE'\\'; reset role; --'",
  ]) assert.throws(() => assertCallerSql(bad), /non ammess|Cambio|non leggibile/, JSON.stringify(bad));
  assert.match(sanitizeSqlForFilter('select 1 -- x\r; reset role'), /reset role/);
  assert.match(sanitizeSqlForFilter('select 1 -- x\n; reset role'), /reset role/);
  assert.doesNotMatch(sanitizeSqlForFilter('select $é$ reset role $é$'), /reset role/, 'tag non ASCII riconosciuto: la stringa resta una stringa');
  assert.doesNotMatch(sanitizeSqlForFilter(`select $${longTag}$ reset role $${longTag}$`), /reset role/);
  assert.throws(() => sanitizeSqlForFilter('select $ ; reset role'), /non leggibile/, '`$` isolato: fail-closed');
  assert.doesNotThrow(() => sanitizeSqlForFilter('select $1::uuid, $2::text'), 'i parametri $n restano ammessi');
  assert.doesNotThrow(() => assertCallerSql('select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r'));
});

test('revisione — SQLSTATE: 40003, 25P03, FATAL/PANIC, E2BIG → unknown; fail_import_run non chiamato per 40003; esito di fail_import_run dichiarato', async () => {
  const c = (e) => classifyFinishError(e, { cloud: true });
  assert.equal(c(serverError('40003')).status, 'unknown');
  assert.equal(c(serverError('25P03')).status, 'unknown');
  assert.equal(c(Object.assign(serverError('23505'), { severity: 'FATAL' })).reason, 'fatal_severity');
  assert.equal(c(Object.assign(serverError('XX001'), { severity: 'PANIC' })).status, 'unknown');
  assert.equal(extractSqlState(Object.assign(new Error('x'), { code: 'E2BIG' })), null);
  assert.equal(c(serverError('40001')).status, 'failed');
  await withFile(async (file) => {
    const r = await runLoad(file, { onFinish: async () => { throw serverError('40003'); } });
    assert.equal(r.error.finish.status, 'unknown');
    assert.equal(r.w.failCalls, 0);
    // 23505 con fail_import_run che FALLISCE: dichiarato, non presunto
    const sim = world({ onFinish: async () => { throw serverError('23505', 'duplicate key: host=db.interno'); } });
    const q = sim.db.query;
    const persisted = [];
    sim.db.query = async (t, p) => { if (t.includes('fail_import_run')) { persisted.push(p[1]); throw new Error('rotta'); } return q(t, p); };
    const e = await loadToDatabase(sim.db, file, {}).then(() => null, (x) => x);
    assert.equal(e.failMarked, false);
    assert.match(persisted[0], /^import interrotto \(23505\)$/, 'nel catalogo solo testo fisso + SQLSTATE');
    assert.doesNotMatch(persisted[0], /host=/);
    const o = buildFinishOutcome({ finishStatus: 'failed', conclusion: null, budgetBytes: 100 * MB, errorCode: '23505', failMarked: e.failMarked });
    assert.match(o.residual_uncertainty, /NON è riuscito/);
    const ok = buildFinishOutcome({ finishStatus: 'failed', conclusion: null, budgetBytes: 100 * MB, errorCode: '23505', failMarked: true });
    assert.match(ok.residual_uncertainty, /fail_import_run è riuscito/);
  });
});

test('revisione — identità disponibile anche se lo sha256 atteso non coincide; walGuard.report() dichiara un valore non aggiornato; scadenza dei limiti → sessione incerta, verifica non eseguita', async () => {
  await withFile(async (file) => {
    const sim = world();
    const e = await loadToDatabase(sim.db, file, { expectedSha256: 'f'.repeat(64) }).then(() => null, (x) => x);
    assert.match(e.message, /SHA-256/);
    assert.equal(e.runIdentity.file_name, 'lwin.xlsx');
    assert.equal(e.runIdentity.run_id, null);
  });
});

test('revisione — walGuard.report() dichiara un valore non aggiornato', async () => {
  const { createWalGuard } = await import('../lib/cloud-guards.mjs');
  let fail = false;
  const guard = await createWalGuard(async (t) => (fail ? Promise.reject(new Error('rotta')) : { rows: [{ lsn: '0/16B3748', bytes: 3 * MB }] }), { maxWalMb: 100 });
  await guard.check();
  fail = true;
  const rep = await guard.report();
  assert.deepEqual([rep.unavailable, rep.stale, rep.wal_mb], [true, true, 3]);
});

test('revisione — scadenza del ripristino dei limiti: sessione incerta e verifica non eseguita', async () => {
  const timers = fakeTimers();
  const db = { state: { broken: false }, assertIntact: async () => {}, setLimits: () => new Promise(() => {}), query: async () => ({ rows: [] }) };
  const p = postCommitChecks({ db, batchLimits: { statementTimeoutMs: 1, lockTimeoutMs: 1, idleTxTimeoutMs: 1 }, verifyArgs: {}, timers, verify: async () => ({ ok: true, checks: [] }) });
  await flush(); // il controllo di sessione si è risolto e la sua scadenza è stata liberata; resta armata solo quella dei limiti
  assert.equal(timers.count(), 1);
  timers.fireAll();
  const r = await p;
  assert.deepEqual([r.session_limits, r.verification.status, db.state.broken], ['restore_failed', 'not_run', true]);
});

// --- WI-008 / J3 — la verifica post-commit ha un limite lato SERVER coerente con la scadenza lato client -------------------------

test('WI-008 / J3 — la verifica gira con uno statement_timeout del server sotto la scadenza client del singolo controllo (non con i 120 s dei lotti)', async () => {
  assert.ok(VERIFY_STATEMENT_TIMEOUT_MS > 120_000, 'più lungo dello statement_timeout dei lotti, che annullava la verifica per primo');
  assert.ok(VERIFY_CHECK_DEADLINE_MS - VERIFY_STATEMENT_TIMEOUT_MS >= 30_000, 'il server scade per primo: limite esplicito su entrambi i lati');
  const events = [];
  const db = { state: { broken: false }, assertIntact: async () => {}, setLimits: async (t, p) => events.push(`limiti ${p[0]}`), query: async () => ({ rows: [] }) };
  await postCommitChecks({ db, batchLimits: { statementTimeoutMs: 120_000, lockTimeoutMs: 30_000, idleTxTimeoutMs: 60_000 }, verifyArgs: {}, verify: async () => { events.push('verifica'); return { ok: true, checks: [{ id: 'V01', ok: true }] }; } });
  assert.deepEqual(events, [`limiti ${VERIFY_STATEMENT_TIMEOUT_MS}`, 'verifica', 'limiti 120000']);
});

test('WI-008 / J3 — scadenza client della verifica: la query è ancora in volo, la sessione non si riusa e l\'esito non è positivo', async () => {
  const calls = [];
  const db = { state: { broken: false }, assertIntact: async () => {}, setLimits: async (t, p) => calls.push(p[0]), query: async () => ({ rows: [] }) };
  const scaduta = async () => { const e = new Error('scadenza'); e.code = 'WI_DEADLINE'; throw e; };
  const r = await postCommitChecks({ db, batchLimits: { statementTimeoutMs: 120_000, lockTimeoutMs: 1, idleTxTimeoutMs: 1 }, verifyArgs: {}, verify: scaduta });
  assert.deepEqual([r.verification.status, r.verification.ok, r.verification.reason], ['failed', false, 'verification_deadline']);
  assert.deepEqual(calls, [String(VERIFY_STATEMENT_TIMEOUT_MS)], 'nessuna query sulla sessione incerta');
  assert.deepEqual([r.session_limits, db.state.broken], ['skipped_session_not_intact', true]);
});

test('WI-008 / J3 — il server annulla un controllo (57014): sessione integra, limiti dei lotti ripristinati, verifica fallita', async () => {
  const calls = [];
  const db = { state: { broken: false }, assertIntact: async () => {}, setLimits: async (t, p) => calls.push(p[0]), query: async () => ({ rows: [] }) };
  const annullata = async () => { const e = new Error('canceling statement due to statement timeout'); e.errno = '57014'; throw e; };
  const r = await postCommitChecks({ db, batchLimits: { statementTimeoutMs: 120_000, lockTimeoutMs: 1, idleTxTimeoutMs: 1 }, verifyArgs: {}, verify: annullata });
  assert.equal(r.verification.ok, false);
  assert.equal(r.verification.status, 'failed');
  assert.deepEqual([r.session_limits, calls.at(-1)], ['restored', '120000']);
});

// --- il runner resta indipendente dal catalogo B -----------------------------------------------------------------------------------

test('il runner non dipende dal catalogo B: nessun import o riferimento a supabase/ né a oggetti canonici nei moduli del caricatore', () => {
  for (const f of ['cloud-guards.mjs', 'cloud-outcome.mjs', 'finish-error.mjs', 'load.mjs', 'db-bun.mjs', 'sql-scan.mjs']) {
    const src = readFileSync(join(HERE, '..', 'lib', f), 'utf8');
    assert.doesNotMatch(src, /from '[^']*supabase[^']*'/, f);
    // cloud-guards nomina catalog.wines SOLO per verificare che il caricatore NON abbia privilegi canonici (controllo negativo)
    if (f !== 'cloud-guards.mjs') assert.doesNotMatch(src, /catalog\.(wines|producers|canonical_events|entity_merges|promote_wine_candidates)\b/, f);
  }
});
