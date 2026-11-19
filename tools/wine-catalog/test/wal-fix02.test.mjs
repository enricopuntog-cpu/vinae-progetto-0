// WI-001C-FIX-02 / P1 WAL: il finish può concludersi tra due campioni del monitor. Prove deterministiche (nessun server, nessuna rete,
// nessun dataset LWIN): database finto con un «server» che accumula WAL, timer finti, due righe di fixture.
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
  createWalMonitor, concludeFinish, finalizeWal, measureFinalWal, reconcileLostFinish, withDeadline, MONITOR_SQL, MONITOR_SQL_ALLOWED,
  createWalGuard, applySessionLimits, SESSION_LIMITS_SQL, WAL_OUTCOMES,
} from '../lib/cloud-guards.mjs';

const MB = 1048576;
const HERE = dirname(fileURLToPath(import.meta.url));
const row = (o) => LWIN_COLUMNS.map((c) => (c in o ? o[c] : c === 'REFERENCE' ? '' : 'NA'));
const W = (lwin) => row({ LWIN: lwin, STATUS: 'Live', DISPLAY_NAME: `Prod, Vino ${lwin}`, PRODUCER_NAME: 'Prod', WINE: `Vino ${lwin}`, COUNTRY: 'Italy', REGION: 'Piedmont', COLOUR: 'Red', TYPE: 'Wine' });

async function withFile(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'wi001c-fix02-'));
  try {
    const p = join(dir, 'lwin.xlsx');
    writeFileSync(p, makeXlsx([LWIN_COLUMNS, W('1000001'), W('1000002')]));
    return await fn(p);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Timer finti: nessuna attesa reale; `fireAll()` fa scadere tutte le scadenze pendenti. */
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
const err = (code, message = code) => Object.assign(new Error(message), { code });

/** «Server» con WAL e un database principale finto che imita le funzioni catalog.*. */
function world({ startBytes = 0, onFinish }) {
  const w = { bytes: startBytes, cancelled: false, failCalls: 0, finishCalls: 0, calls: [], mainBroken: false };
  const db = {
    state: { broken: false },
    backendPid: 99,
    async query(text, params = []) {
      w.calls.push(text);
      if (db.state?.broken) throw new Error('Sessione cloud interrotta: la connessione è caduta e non viene riaperta (fail-closed).');
      if (text.includes('begin_import_run')) return { rows: [{ r: { run_id: '00000000-0000-4000-8000-000000000001', mode: 'import' } }] };
      if (text.includes('stage_source_records')) { const k = JSON.parse(params[1]).length; return { rows: [{ r: { received: k, new: k, updated: 0, unchanged: 0, reappeared: 0 } }] }; }
      if (text.includes('record_findings')) return { rows: [{ n: 0 }] };
      if (text.includes('fail_import_run')) { w.failCalls += 1; return { rows: [] }; }
      if (text.includes('pg_wal_lsn_diff')) return { rows: [{ bytes: w.bytes }] };
      if (text.includes('finish_import_run')) {
        w.finishCalls += 1;
        await onFinish(w, db);
        return { rows: [{ r: { records_seen: Number(params[1]) } }] };
      }
      throw new Error(`istruzione non prevista: ${text}`);
    },
  };
  const monitorQuery = async (text, params = []) => {
    if (text === MONITOR_SQL.wal) return { rows: [{ bytes: w.bytes }] };
    if (text === MONITOR_SQL.cancel) { w.cancelled = true; return { rows: [{ ok: true }] }; }
    throw new Error(`istruzione di monitor non prevista: ${text} ${JSON.stringify(params)}`);
  };
  return { w, db, monitorQuery };
}

/** Compone gli stessi pezzi del CLI (lwin-load.mjs): monitor → finish → conclusione → esito. */
async function runLoad(file, { budgetMb = 100, onFinish, monitorQuery: mq, makeMonitorQuery, sleep = async () => {} } = {}) {
  const sim = world({ onFinish });
  const monitorQuery = makeMonitorQuery ? makeMonitorQuery(sim) : (mq ?? sim.monitorQuery);
  const monitor = createWalMonitor({ query: monitorQuery, backendPid: 99, startLsn: '0/16B3748', maxWalMb: budgetMb, intervalMs: 5, setTimer: () => ({ unref() {} }), clearTimer: () => {} });
  await monitor.sample();
  sim.monitor = monitor;
  let conclusion = null;
  const hooks = {
    beforeFinish: async () => { monitor.start(); },
    afterFinish: async ({ status }) => {
      conclusion = await concludeFinish({ monitor, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery: (t, p) => monitorQuery(t, p), startLsn: '0/16B3748', backendPid: 99, sleep });
      return conclusion;
    },
  };
  try {
    const report = await loadToDatabase(sim.db, file, hooks);
    const outcome = finalizeWal({ finish: 'committed', monitor: conclusion.monitor, finalWal: conclusion.finalWal, budgetBytes: budgetMb * MB });
    return { ...sim, report, conclusion, outcome, error: null };
  } catch (e) {
    const outcome = e?.finish?.status && conclusion ? finalizeWal({ finish: e.finish.status, monitor: conclusion.monitor, finalWal: conclusion.finalWal, remote: conclusion.remote, budgetBytes: budgetMb * MB }) : null;
    return { ...sim, report: null, conclusion, outcome, error: e };
  }
}

// --- 1. il vecchio scenario: finish rapido da 400 MB su budget 100 MB, nessun campione periodico durante il finish ----------------

test('P1 WAL — finish rapido: 400 MB prodotti su budget 100 MB, senza campioni periodici → NON successo (exit ≠ 0), commit dichiarato, nessun rollback inventato', async () => {
  await withFile(async (file) => {
    const r = await runLoad(file, { budgetMb: 100, onFinish: async (w) => { w.bytes += 400 * MB; } });
    assert.equal(r.w.finishCalls, 1);
    assert.equal(r.monitor.status().samples, 1, 'nessun campione durante il finish (solo quello iniziale): il vecchio codice usciva con 0');
    assert.equal(r.monitor.status().exceeded, false, 'il monitor periodico NON ha visto lo sforamento');
    assert.equal(r.outcome.outcome, WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT);
    assert.equal(r.outcome.ok, false);
    assert.equal(r.outcome.exit_code, 1);
    assert.ok(r.outcome.failure_reasons.includes('wal_budget_exceeded_after_commit'));
    assert.equal(r.outcome.wal.measured_mb, 400);
    assert.equal(r.outcome.wal.budget_mb, 100);
    assert.equal(r.w.failCalls, 0, 'nessun fail_import_run su un tentativo già confermato');
    assert.doesNotMatch(`${r.outcome.known_db_state} ${r.outcome.residual_uncertainty} ${r.outcome.next_action}`, /rollback (completo|eseguito|riuscito)|annullat[oa] con successo/i);
    assert.match(r.outcome.known_db_state, /CONFERMATA/);
    assert.match(r.outcome.next_action, /NON ripetere/);
    assert.match(r.outcome.next_action, /NON ripetere l'import e non cancellare dati/);
    assert.equal(r.report.finish.status, 'committed');
  });
});

// --- 2. finish rapido entro budget → successo --------------------------------------------------------------------------------------

test('P1 WAL — finish rapido entro budget: successo (exit 0), misura conclusiva presente', async () => {
  await withFile(async (file) => {
    const r = await runLoad(file, { budgetMb: 100, onFinish: async (w) => { w.bytes += 40 * MB; } });
    assert.equal(r.outcome.outcome, WAL_OUTCOMES.WITHIN_BUDGET);
    assert.deepEqual([r.outcome.ok, r.outcome.exit_code, r.outcome.failure_reasons], [true, 0, []]);
    assert.equal(r.outcome.wal.measured_mb, 40);
    assert.equal(r.outcome.wal.measured_via, 'principale');
  });
});

// --- 3. il monitor vede lo sforamento e annulla PRIMA del commit ------------------------------------------------------------------

test('P1 WAL — il monitor rileva lo sforamento durante il finish, pg_cancel_backend riesce, il finish è annullato (57014): cancelled_before_commit, rollback noto', async () => {
  await withFile(async (file) => {
    const sim = world({ onFinish: async (w) => { w.bytes += 150 * MB; await tick(); if (w.cancelled) throw err('57014', 'canceling statement due to user request'); } });
    const monitor = createWalMonitor({ query: sim.monitorQuery, backendPid: 99, startLsn: '0/16B3748', maxWalMb: 100, setTimer: () => ({ unref() {} }), clearTimer: () => {} });
    async function tick() { await monitor.sample(); }
    await monitor.sample();
    monitor.start();
    let conclusion;
    let thrown;
    try {
      await loadToDatabase(sim.db, file, {
        afterFinish: async ({ status }) => { conclusion = await concludeFinish({ monitor, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery: (t, p) => sim.monitorQuery(t, p), startLsn: '0/16B3748', backendPid: 99, sleep: async () => {} }); return conclusion; },
      });
    } catch (e) { thrown = e; }
    assert.equal(thrown.finish.status, 'failed');
    const o = finalizeWal({ finish: 'failed', monitor: conclusion.monitor, finalWal: conclusion.finalWal, budgetBytes: 100 * MB });
    assert.equal(o.outcome, WAL_OUTCOMES.CANCELLED_BEFORE_COMMIT);
    assert.equal(o.ok, false);
    assert.equal(o.exit_code, 1);
    assert.ok(o.failure_reasons.includes('wal_budget_exceeded_cancelled'));
    assert.match(o.known_db_state, /rollback/);
    assert.equal(sim.w.failCalls, 1, 'rollback noto: il tentativo è marcato failed');
    assert.equal(o.monitor.cancel_ok, true);
  });
});

// --- 4. il monitor vede lo sforamento DOPO il commit -------------------------------------------------------------------------------

test('P1 WAL — annullamento richiesto ma il finish ha già confermato: over_budget_after_commit con cancel_requested_but_committed, nessun fail_import_run', async () => {
  await withFile(async (file) => {
    const sim = world({ onFinish: async (w) => { w.bytes += 150 * MB; await monitor.sample(); /* cancel riuscito, ma il finish termina comunque */ } });
    const monitor = createWalMonitor({ query: sim.monitorQuery, backendPid: 99, startLsn: '0/16B3748', maxWalMb: 100, setTimer: () => ({ unref() {} }), clearTimer: () => {} });
    await monitor.sample();
    monitor.start();
    let conclusion;
    const report = await loadToDatabase(sim.db, file, {
      afterFinish: async ({ status }) => { conclusion = await concludeFinish({ monitor, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery: (t, p) => sim.monitorQuery(t, p), startLsn: '0/16B3748', backendPid: 99, sleep: async () => {} }); return conclusion; },
    });
    assert.equal(report.finish.status, 'committed');
    const o = finalizeWal({ finish: 'committed', monitor: conclusion.monitor, finalWal: conclusion.finalWal, budgetBytes: 100 * MB });
    assert.equal(o.outcome, WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT);
    assert.ok(o.failure_reasons.includes('cancel_requested_but_committed'));
    assert.equal(o.exit_code, 1);
    assert.equal(sim.w.failCalls, 0);
    assert.doesNotMatch(o.known_db_state, /rollback/);
  });
});

// --- 5. monitor che non risponde (query bloccata) → scadenza, nessuna attesa indefinita, nessun busy bloccato --------------------

test('monitor che non risponde: ogni query ha una scadenza; due campioni persi → annullamento tentato (anch\'esso con scadenza) → perso; start() rifiutato senza campione iniziale', async () => {
  const timers = fakeTimers();
  const hang = () => new Promise(() => {}); // non risolve mai
  let reopened = 0;
  const mon = createWalMonitor({ query: hang, backendPid: 5, startLsn: '0/1', maxWalMb: 100, timers, queryTimeoutMs: 10, failuresBeforeCancel: 2, reopen: async () => { reopened += 1; return hang; }, setTimer: () => ({}), clearTimer: () => {} });
  assert.throws(() => mon.start(), /non operativo/, 'senza una misura riuscita il finish non parte');
  const s1 = mon.sample();
  timers.fireAll();
  await s1;
  assert.equal(mon.status().failures, 1);
  assert.equal(mon.status().timeouts, 1);
  const s2 = mon.sample(); // il flag busy NON è rimasto attivo: il campione successivo parte
  timers.fireAll();
  await flush();
  timers.fireAll(); // annullamento sulla connessione bloccata → scade
  await flush();
  timers.fireAll(); // riapertura + nuovo tentativo → scade
  await s2;
  const st = mon.status();
  assert.equal(st.failures >= 2, true);
  assert.equal(reopened, 1, 'riaperta SOLO la connessione del monitor');
  assert.equal(st.cancelOk, false);
  assert.equal(st.lost, true);
  const o = finalizeWal({ finish: 'committed', monitor: st, finalWal: { ok: true, bytes: 20 * MB, via: 'principale' }, budgetBytes: 100 * MB });
  assert.equal(o.outcome, WAL_OUTCOMES.MONITOR_LOST, 'monitor perso: anche se il WAL finale è sotto budget non è un successo');
  assert.equal(o.exit_code, 1);
});

test('monitor: tetto ai tentativi di annullamento (nessun ciclo illimitato) e ticks sovrapposti saltati, non accodati', async () => {
  let cancels = 0;
  const q = async (t) => { if (t === MONITOR_SQL.cancel) { cancels += 1; return { rows: [{ ok: false }] }; } return { rows: [{ bytes: 500 * MB }] }; };
  const mon = createWalMonitor({ query: q, backendPid: 5, startLsn: '0/1', maxWalMb: 100, maxCancelAttempts: 3, setTimer: () => ({}), clearTimer: () => {} });
  for (let i = 0; i < 20; i += 1) await mon.sample();
  assert.equal(cancels, 3, 'al massimo 3 richieste di annullamento');
  assert.equal(mon.status().lost, true);
  // tick sovrapposto: il secondo viene saltato
  const slow = createWalMonitor({ query: () => new Promise((r) => setTimeout(() => r({ rows: [{ bytes: MB }] }), 20)), backendPid: 5, startLsn: '0/1', maxWalMb: 100, setTimer: () => ({}), clearTimer: () => {} });
  await Promise.all([slow.sample(), slow.sample(), slow.sample()]);
  assert.equal(slow.status().samples, 1);
  assert.equal(slow.status().skippedTicks, 2);
});

// --- 6. connessione principale persa durante il finish ------------------------------------------------------------------------------

test('connessione principale persa durante il finish: esito sconosciuto, niente fail_import_run, sonda del backend, annullamento del backend ancora attivo, exit ≠ 0', async () => {
  await withFile(async (file) => {
    const probes = [];
    const states = ['active', 'active', null];
    const cancels = [];
    const w = { bytes: 10 * MB };
    const monitorQuery = async (text, params) => {
      if (text === MONITOR_SQL.wal) return { rows: [{ bytes: w.bytes }] };
      if (text === MONITOR_SQL.activity) { const s = states.shift() ?? null; probes.push(s); return { rows: s === null ? [] : [{ state: s }] }; }
      if (text === MONITOR_SQL.cancel) { cancels.push(params); return { rows: [{ ok: true }] }; }
      throw new Error('imprevisto');
    };
    const sim = world({ onFinish: async (_w, db) => { db.state.broken = true; throw err('ERR_POSTGRES_CONNECTION_CLOSED', 'Connection closed'); } });
    const monitor = createWalMonitor({ query: monitorQuery, backendPid: 99, startLsn: '0/16B3748', maxWalMb: 100, setTimer: () => ({}), clearTimer: () => {} });
    await monitor.sample();
    monitor.start();
    let conclusion;
    let thrown;
    try {
      await loadToDatabase(sim.db, file, {
        afterFinish: async ({ status }) => { conclusion = await concludeFinish({ monitor, status, mainQuery: (t, p) => sim.db.query(t, p), monitorQuery, startLsn: '0/16B3748', backendPid: 99, sleep: async () => {} }); return conclusion; },
      });
    } catch (e) { thrown = e; }
    assert.equal(thrown.finish.status, 'unknown');
    assert.equal(sim.w.failCalls, 0, 'un tentativo forse già terminale non si tocca');
    assert.equal(conclusion.remote.backend, 'gone');
    assert.equal(conclusion.remote.cancel_sent, true);
    assert.deepEqual(cancels, [[99]], 'una sola richiesta di annullamento');
    assert.equal(conclusion.finalWal.via, 'monitor', 'la misura conclusiva passa dalla connessione di monitor');
    const o = finalizeWal({ finish: thrown.finish.status, monitor: conclusion.monitor, finalWal: conclusion.finalWal, remote: conclusion.remote, budgetBytes: 100 * MB });
    assert.equal(o.outcome, WAL_OUTCOMES.FINISH_UNKNOWN);
    assert.equal(o.exit_code, 1);
    assert.equal(o.known_db_state, 'sconosciuto');
    assert.match(o.next_action, /NON ripetere/);
    assert.ok(o.failure_reasons.includes('remote_backend_gone'));
  });
});

test('sonda del backend remoto: limite di sonde, mai un ciclo illimitato; sonda non disponibile → esito dichiarato', async () => {
  let n = 0;
  const q = async (t) => { if (t === MONITOR_SQL.activity) { n += 1; return { rows: [{ state: 'idle in transaction' }] }; } return { rows: [{ ok: true }] }; };
  const out = await reconcileLostFinish({ query: q, backendPid: 7, sleep: async () => {}, maxProbes: 3 });
  assert.equal(n, 3);
  assert.equal(out.backend, 'idle_in_transaction');
  assert.equal(out.cancel_sent, false, 'un backend non attivo non si annulla');
  const dead = await reconcileLostFinish({ query: async () => { throw new Error('rete'); }, backendPid: 7, sleep: async () => {} });
  assert.equal(dead.backend, 'probe_unavailable');
});

// --- 7. pg_cancel_backend restituisce false ----------------------------------------------------------------------------------------

test('pg_cancel_backend → false: la richiesta NON conta come annullamento (cancelRequested resta false); finish fallito per altra causa ≠ cancelled_before_commit', async () => {
  const q = async (t) => (t === MONITOR_SQL.cancel ? { rows: [{ ok: false }] } : { rows: [{ bytes: 500 * MB }] });
  const mon = createWalMonitor({ query: q, backendPid: 5, startLsn: '0/1', maxWalMb: 100, setTimer: () => ({}), clearTimer: () => {} });
  await mon.sample();
  await mon.sample();
  const st = await mon.stop();
  assert.equal(st.cancelRequested, false);
  assert.equal(st.cancelOk, false);
  assert.equal(st.exceeded, true);
  const failed = finalizeWal({ finish: 'failed', monitor: st, finalWal: { ok: true, bytes: 500 * MB, via: 'principale' }, budgetBytes: 100 * MB });
  assert.equal(failed.outcome, WAL_OUTCOMES.FAILED_BEFORE_COMMIT, 'una cancellazione richiesta ma non riuscita non equivale a una cancellazione riuscita');
  assert.ok(failed.failure_reasons.includes('monitor_unreliable'));
  const committed = finalizeWal({ finish: 'committed', monitor: st, finalWal: { ok: true, bytes: 500 * MB, via: 'principale' }, budgetBytes: 100 * MB });
  assert.equal(committed.outcome, WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT);
});

// --- 8. campione in volo durante stop() --------------------------------------------------------------------------------------------

test('campione in volo durante stop(): stop() lo attende, lo registra come tardivo (picco e superamento) e NON può più annullare nulla', async () => {
  let release;
  const gate = new Promise((r) => { release = r; });
  const cancels = [];
  const q = async (t, p) => {
    if (t === MONITOR_SQL.cancel) { cancels.push(p); return { rows: [{ ok: true }] }; }
    await gate;
    return { rows: [{ bytes: 500 * MB }] };
  };
  const mon = createWalMonitor({ query: q, backendPid: 5, startLsn: '0/1', maxWalMb: 100, setTimer: () => ({}), clearTimer: () => {} });
  const inflight = mon.sample();
  const stopping = mon.stop();
  release();
  const st = await stopping;
  await inflight;
  assert.equal(st.inflightAtStop, true);
  assert.equal(st.lateSamples, 1);
  assert.equal(st.exceeded, true, 'il superamento tardivo è visibile nell\'esito');
  assert.deepEqual(cancels, [], 'nessun annullamento dopo stop(): colpirebbe la verifica o il fail_import_run');
  assert.equal(finalizeWal({ finish: 'committed', monitor: st, finalWal: { ok: true, bytes: 500 * MB, via: 'principale' }, budgetBytes: 100 * MB }).outcome, WAL_OUTCOMES.OVER_BUDGET_AFTER_COMMIT);
});

test('campione in volo che non termina: stop() ha una scadenza (stopTimedOut) e l\'esito non è un successo', async () => {
  const timers = fakeTimers();
  const mon = createWalMonitor({ query: () => new Promise(() => {}), backendPid: 5, startLsn: '0/1', maxWalMb: 100, timers, queryTimeoutMs: 1_000_000, stopWaitMs: 10, setTimer: () => ({}), clearTimer: () => {} });
  void mon.sample();
  const stopping = mon.stop();
  await flush();
  timers.fireAll();
  const st = await stopping;
  assert.equal(st.stopTimedOut, true);
  const o = finalizeWal({ finish: 'committed', monitor: st, finalWal: { ok: true, bytes: MB, via: 'principale' }, budgetBytes: 100 * MB });
  assert.equal(o.outcome, WAL_OUTCOMES.MONITOR_LOST);
  assert.equal(o.exit_code, 1);
});

// --- 9. fallimento della verifica conclusiva ----------------------------------------------------------------------------------------

test('verifica conclusiva: WAL non misurabile → monitor_lost; verifyFinish fallita → failure_reasons e exit ≠ 0 anche con WAL entro budget; misura impossibile da ogni sorgente', async () => {
  const unavailable = await measureFinalWal({ sources: [{ name: 'principale', query: async () => { throw new Error('rotta'); } }, { name: 'monitor', query: async () => ({ rows: [{ bytes: 'x' }] }) }], startLsn: '0/1' });
  assert.equal(unavailable.ok, false);
  assert.equal(unavailable.errors.length, 2);
  const o1 = finalizeWal({ finish: 'committed', monitor: { samples: 1, peakBytes: MB, cancelAttempts: 0, cancelOk: null }, finalWal: unavailable, budgetBytes: 100 * MB });
  assert.equal(o1.outcome, WAL_OUTCOMES.MONITOR_LOST);
  assert.ok(o1.failure_reasons.includes('final_wal_measurement_unavailable'));
  assert.equal(o1.exit_code, 1);
  assert.match(o1.residual_uncertainty, /non è verificabile/);
  const o2 = finalizeWal({
    finish: 'committed', monitor: { samples: 1, peakBytes: MB, cancelAttempts: 0, cancelOk: null }, finalWal: { ok: true, bytes: 30 * MB, via: 'principale' }, budgetBytes: 100 * MB,
    verification: { ok: false, checks: [{ id: 'V04_stage_emptied', ok: false }, { id: 'V01_run_succeeded', ok: true }] },
  });
  assert.equal(o2.outcome, WAL_OUTCOMES.WITHIN_BUDGET);
  assert.equal(o2.ok, false);
  assert.deepEqual(o2.failure_reasons, ['verification_failed']);
  assert.match(o2.next_action, /V04_stage_emptied/);
  assert.equal(o2.exit_code, 1);
  assert.throws(() => finalizeWal({ finish: 'boh', budgetBytes: MB }), /non valido/);
  assert.throws(() => finalizeWal({ finish: 'committed', budgetBytes: 0 }), /non valido/);
});

// --- 10. secondo tentativo idempotente ---------------------------------------------------------------------------------------------

test('secondo tentativo dopo un import già completato: skipped, nessuna lettura/staging/finish, nessun monitor avviato, nessuna scrittura oltre la telemetria', async () => {
  await withFile(async (file) => {
    const calls = [];
    const db = { async query(text) { calls.push(text); if (text.includes('begin_import_run')) return { rows: [{ r: { run_id: '00000000-0000-4000-8000-000000000002', mode: 'skipped', of_run: '00000000-0000-4000-8000-0000000000aa' } }] }; throw new Error(`non previsto: ${text}`); } };
    let hooks = 0;
    const rep = await loadToDatabase(db, file, { beforeFinish: async () => { hooks += 1; }, afterFinish: async () => { hooks += 1; } });
    assert.equal(rep.mode, 'skipped');
    assert.equal(rep.reason, 'snapshot_already_current');
    assert.equal(calls.length, 1, 'solo begin_import_run');
    assert.equal(hooks, 0, 'nessun hook di finish: nessun monitor');
    assert.equal(rep.finish, undefined);
  });
});

// --- confini e SQL interno ---------------------------------------------------------------------------------------------------------

test('SQL del monitor: elenco chiuso e costante; la guardia WAL usa lo stesso testo; i limiti di sessione passano da setLimits (SQL interno), non dal chiamante', async () => {
  assert.equal(MONITOR_SQL_ALLOWED.size, 4);
  for (const sql of MONITOR_SQL_ALLOWED) assert.doesNotMatch(sql, /;/);
  const seen = [];
  const guard = await createWalGuard(async (t, p) => { seen.push(t); return { rows: [{ lsn: '0/16B3748', bytes: 5 }] }; }, { maxWalMb: 100 });
  await guard.check();
  assert.ok(seen.includes(MONITOR_SQL.wal), 'stesso testo del monitor: unico punto di verità');
  const viaMethod = [];
  await applySessionLimits({ setLimits: async (t, p) => viaMethod.push([t, p]) }, { statementTimeoutMs: 1000, lockTimeoutMs: 2000, idleTxTimeoutMs: 3000 });
  assert.deepEqual(viaMethod, [[SESSION_LIMITS_SQL, ['1000', '2000', '3000']]]);
  const viaFn = [];
  await applySessionLimits(async (t, p) => viaFn.push([t, p]), { statementTimeoutMs: 1, lockTimeoutMs: 2, idleTxTimeoutMs: 3 });
  assert.equal(viaFn[0][0], SESSION_LIMITS_SQL);
});

test('withDeadline: una promessa che non si risolve scade; una che si risolve libera il timer', async () => {
  const timers = fakeTimers();
  const never = withDeadline(new Promise(() => {}), 10, 'x', timers);
  timers.fireAll();
  await assert.rejects(never, /nessuna risposta entro 10 ms/);
  assert.equal(await withDeadline(Promise.resolve(7), 10, 'x', timers), 7);
  assert.equal(timers.count(), 0, 'nessun timer residuo');
});

test('CLI: il cablaggio usa la misura conclusiva e l\'esito strutturato; il successo si stampa solo se l\'esito è conforme; nessun fail_import_run su esito sconosciuto', () => {
  const cli = readFileSync(join(HERE, '..', 'lwin-load.mjs'), 'utf8');
  assert.match(cli, /concludeFinish\(\{/);
  assert.ok(cli.includes('buildFinishOutcome({'));
  assert.match(cli, /finish_outcome/);
  assert.match(cli, /Caricamento NON confermato/);
  assert.match(cli, /applySessionLimits\(db,/, 'i timeout passano dal metodo interno della sessione');
  assert.match(cli, /await walMonitor\.stop\(\)/);
  const load = readFileSync(join(HERE, '..', 'lib', 'load.mjs'), 'utf8');
  assert.match(load, /e\?\.finish\?\.status === 'unknown'/);
});

// --- correzioni dopo la revisione interna (FIX-02) ----------------------------------------------------------------------------------

import { buildFinishOutcome } from '../lib/cloud-guards.mjs';
import { sanitizeSqlForFilter } from '../lib/sql-scan.mjs';

test('conclusione ASSENTE dopo un commit (hook fallito): fail-closed, monitor_lost ed exit ≠ 0; con verifica fallita lo dice', () => {
  const o = buildFinishOutcome({ finishStatus: 'committed', conclusion: null, budgetBytes: 100 * MB });
  assert.equal(o.outcome, WAL_OUTCOMES.MONITOR_LOST);
  assert.equal(o.exit_code, 1);
  assert.ok(o.failure_reasons.includes('final_wal_measurement_unavailable'));
  const v = buildFinishOutcome({ finishStatus: 'committed', conclusion: null, budgetBytes: 100 * MB, verification: { ok: false, checks: [{ id: 'V01_run_succeeded', ok: false }] } });
  assert.ok(v.failure_reasons.includes('verification_failed'));
});

test('finish fallito: «annullato dal monitor» solo con SQLSTATE 57014; sforamento osservato registrato; cancel inviato ma commit anche entro budget = segnale', () => {
  const mon = { samples: 2, peakBytes: 150 * MB, exceeded: true, cancelRequested: true, cancelOk: true, cancelAttempts: 1, lost: false };
  const fin = { ok: true, bytes: 150 * MB, via: 'principale' };
  assert.equal(finalizeWal({ finish: 'failed', monitor: mon, finalWal: fin, budgetBytes: 100 * MB, errorCode: '57014' }).outcome, WAL_OUTCOMES.CANCELLED_BEFORE_COMMIT);
  const other = finalizeWal({ finish: 'failed', monitor: mon, finalWal: fin, budgetBytes: 100 * MB, errorCode: '23505' });
  assert.equal(other.outcome, WAL_OUTCOMES.FAILED_BEFORE_COMMIT);
  assert.ok(other.failure_reasons.includes('wal_budget_exceeded_observed'));
  const quiet = finalizeWal({ finish: 'committed', monitor: { ...mon, exceeded: false, peakBytes: MB }, finalWal: { ok: true, bytes: 5 * MB, via: 'principale' }, budgetBytes: 100 * MB });
  assert.equal(quiet.ok, false);
  assert.ok(quiet.failure_reasons.includes('cancel_sent_but_committed'));
});

test('beforeFinish che lancia (monitor non operativo): il finish NON parte e il tentativo è marcato failed', async () => {
  await withFile(async (file) => {
    const sim = world({ onFinish: async () => {} });
    const mon = createWalMonitor({ query: sim.monitorQuery, backendPid: 99, startLsn: '0/16B3748', maxWalMb: 100, setTimer: () => ({}), clearTimer: () => {} });
    await assert.rejects(() => loadToDatabase(sim.db, file, { beforeFinish: async () => { mon.start(); } }), /non operativo/);
    assert.equal(sim.w.finishCalls, 0);
    assert.equal(sim.w.failCalls, 1);
  });
});

test('classificazione del finish: in locale (senza db.state) un errore dal testo «socket» è un fallimento, non un esito sconosciuto; errori non-Error gestiti', async () => {
  await withFile(async (file) => {
    const sim = world({ onFinish: async () => { throw new Error('socket hang up in funzione'); } });
    delete sim.db.state;
    await assert.rejects(() => loadToDatabase(sim.db, file, {}), (e) => e.finish.status === 'failed');
    assert.equal(sim.w.failCalls, 1);
    const sim2 = world({ onFinish: async () => { throw 'stringa nuda'; } });
    await assert.rejects(() => loadToDatabase(sim2.db, file, {}), (e) => e instanceof Error && e.finish.status === 'failed');
  });
});

test('filtro SQL lessicale: letterali, commenti annidati, E\'\' e dollari non nascondono un set_config/RESET; testo non chiuso rifiutato', () => {
  assert.equal(sanitizeSqlForFilter("select '--' as x -- c\n, 1"), "select '' as x  , 1");
  assert.doesNotMatch(sanitizeSqlForFilter("select '--'; reset role"), /^select ''\s*$/, 'il ; e RESET ROLE restano visibili al filtro');
  assert.match(sanitizeSqlForFilter("select '--'; reset role"), /reset role/);
  assert.match(sanitizeSqlForFilter(`select E'${String.fromCharCode(92)}''; reset role`), /reset role/, 'un apice con escape a backslash non chiude la stringa a metà');
  assert.match(sanitizeSqlForFilter('select "set_config"(1)'), /set_config/);
  assert.match(sanitizeSqlForFilter('select /* a /* b */ c */ set_config(1)'), /set_config/);
  assert.doesNotMatch(sanitizeSqlForFilter("select $$ set_config $$"), /set_config/);
  for (const bad of ["select 'aperta", 'select /* aperto', 'select "aperto', 'select $x$ aperto']) assert.throws(() => sanitizeSqlForFilter(bad), /non leggibile/, bad);
});
