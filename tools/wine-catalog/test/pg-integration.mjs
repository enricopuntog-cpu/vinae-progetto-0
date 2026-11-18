#!/usr/bin/env bun
// Prove di concorrenza e crash su un PostgreSQL LOCALE REALE (WI-001B). Due connessioni vere, ruolo catalog_loader,
// nessun mock. NON fa parte di `node --test` (serve Bun + un database con la migration applicata): si lancia a mano.
//
//   CATALOG_DATABASE_URL=postgresql://postgres:…@127.0.0.1:PORT/postgres bun tools/wine-catalog/test/pg-integration.mjs
//
// Usa una fonte di prova dedicata (`WI-CONC-TEST`), registrata e RIMOSSA dalla prova stessa (cleanup anche su errore);
// non tocca LIVEX-LWIN7. Esce con codice 1 se un controllo fallisce.
import { createHash } from 'node:crypto';
import { assertLocalDatabaseUrl } from '../lib/paths.mjs';

const url = process.env.CATALOG_DATABASE_URL;
if (!url) { console.error('Manca CATALOG_DATABASE_URL (database locale).'); process.exit(2); }
assertLocalDatabaseUrl(url);

const CODE = 'WI-CONC-TEST';
const results = [];
const check = (id, desc, ok, detail = '') => { results.push({ id, desc, ok: Boolean(ok), detail }); console.log(`${ok ? 'OK  ' : 'FAIL'} ${id} ${desc}${ok ? '' : ` — ${detail}`}`); };
const sha = (s) => createHash('sha256').update(s).digest('hex');
const row = (ext, tag = 'v1') => ({
  external_id: ext, status: 'Live', scope: 'wine', reference_external_id: null, country: 'Italy', region: 'Piedmont', sub_region: null,
  payload: { lwin: ext, tag }, raw: { LWIN: ext }, content_hash: sha(`${ext}|${tag}`),
});
const msg = (e) => String(e?.message ?? e);

const admin = new Bun.SQL({ url, max: 1 });
const open = async () => {
  const c = new Bun.SQL({ url, max: 1 });
  await c.unsafe('set role catalog_loader');
  const pid = (await c.unsafe('select pg_backend_pid() as p'))[0].p;
  return { c, pid, q: async (t, p = []) => Array.from(await c.unsafe(t, p)) };
};
const adm = async (t, p = []) => Array.from(await admin.unsafe(t, p));
const parse = (v) => (typeof v === 'string' ? JSON.parse(v) : v);
const begin = (conn, shaHex, opts = {}) => conn.q(
  'select catalog.begin_import_run($1, $2, $3, $4, $5, $6, make_interval(secs => $7::int), $8) as r',
  [CODE, shaHex, 'prova.xlsx', null, 'pg-integration', opts.takeover ?? false, opts.staleSecs ?? 600, opts.force ?? false]).then((r) => parse(r[0].r));
const stage = (conn, runId, rows) => conn.q('select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r', [runId, JSON.stringify(rows)]).then((r) => parse(r[0].r));
const finish = (conn, runId, n, summary = {}) => conn.q('select catalog.finish_import_run($1::uuid, $2::bigint, ($3::text)::jsonb) as r', [runId, n, JSON.stringify(summary)]).then((r) => parse(r[0].r));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function cleanup() {
  const src = (await adm('select id from catalog.sources where code = $1', [CODE]))[0]?.id;
  if (!src) return;
  const stmts = [
    'delete from catalog.import_stage where run_id in (select id from catalog.import_runs where source_id = $1)',
    'delete from catalog.source_record_events where run_id in (select id from catalog.import_runs where source_id = $1)',
    'delete from catalog.import_findings where source_id = $1',
    'delete from catalog.record_links where source_id = $1',
    'delete from catalog.source_records where source_id = $1',
    'delete from catalog.territory_edges where child_id in (select id from catalog.territories where source_id = $1)',
    'delete from catalog.aliases where territory_id in (select id from catalog.territories where source_id = $1)',
    'delete from catalog.territories where source_id = $1',
    'delete from catalog.import_runs where source_id = $1',
    'delete from catalog.import_snapshots where source_id = $1',
    'delete from catalog.sources where id = $1',
  ];
  for (const s of stmts) await adm(s, [src]);
}

let A; let B; let C;
try {
  await cleanup();
  await adm(`insert into catalog.sources (code, name, authorization_status) values ($1, 'Fonte di prova concorrenza', 'authorized')`, [CODE]);
  A = await open(); B = await open();

  // P01 — due avvii simultanei sulla stessa fonte: ne passa uno solo
  const settled = await Promise.allSettled([begin(A, sha('s1')), begin(B, sha('s1'))]);
  const ok = settled.filter((s) => s.status === 'fulfilled');
  const ko = settled.filter((s) => s.status === 'rejected');
  check('P01', 'due begin_import_run simultanei: uno solo parte, l\'altro è rifiutato (55P03)', ok.length === 1 && ko.length === 1 && /già in corso|55P03/.test(msg(ko[0].reason)), settled.map((s) => s.status).join(','));
  const run1 = ok[0].value.run_id;
  check('P01b', 'un solo tentativo running per la fonte', (await adm(`select count(*)::int as n from catalog.import_runs where source_id = (select id from catalog.sources where code = $1) and status = 'running'`, [CODE]))[0].n === 1);

  // P02 — il caricatore A tiene il lock del suo tentativo (transazione aperta): il takeover di B (stale 0) ATTENDE
  await A.q('begin');
  await stage(A, run1, [row('9000001'), row('9000002')]);
  let bDone = false;
  const bTake = begin(B, sha('s1'), { takeover: true, staleSecs: 0 }).then((r) => { bDone = true; return r; }, (e) => { bDone = true; throw e; });
  await sleep(700);
  check('P02', 'takeover concorrente con un lotto in corso: attende il lock del tentativo (non lo calpesta)', bDone === false);
  await A.q('commit');
  const taken = await bTake;
  const aRun = (await adm('select status from catalog.import_runs where id = $1', [run1]))[0].status;
  check('P03', 'dopo il commit di A il takeover prosegue: tentativo di A abbandonato, nuovo tentativo di B', aRun === 'abandoned' && taken.mode === 'import' && taken.run_id !== run1, `${aRun} ${taken.mode}`);
  let zombie = '';
  try { await stage(A, run1, [row('9000003')]); zombie = 'accettato'; } catch (e) { zombie = msg(e); }
  check('P04', 'il caricatore A (lease scaduta) non può più scrivere nello staging: 55000', /non in corso/.test(zombie), zombie);
  check('P04b', 'lo staging del tentativo abbandonato è stato scartato', (await adm('select count(*)::int as n from catalog.import_stage where run_id = $1', [run1]))[0].n === 0);
  const run2 = taken.run_id;

  // P05 — il finish di B non può essere interrotto da un takeover di A: A attende e poi non abbandona nulla
  await stage(B, run2, [row('9000001'), row('9000002'), row('9000003')]);
  await B.q('begin');
  const fin = await finish(B, run2, 3, {});
  let aDone = false;
  const aTake = begin(A, sha('s2'), { takeover: true, staleSecs: 0 }).then((r) => { aDone = true; return r; }, (e) => { aDone = true; throw e; });
  await sleep(700);
  check('P05', 'takeover durante un finish non ancora confermato: attende (il finish non viene abbandonato a metà)', aDone === false);
  await B.q('commit');
  const second = await aTake;
  const bRun = (await adm('select status from catalog.import_runs where id = $1', [run2]))[0].status;
  check('P06', 'finish confermato: il tentativo resta succeeded (mai abbandonato), 3 record, nessun duplicato', bRun === 'succeeded' && fin.records_seen === 3
    && (await adm(`select count(*)::int as n from catalog.source_records where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0].n === 3, bRun);
  await A.q('select catalog.fail_import_run($1::uuid, $2)', [second.run_id, 'chiusura prova']);

  // P07 — crash del caricatore a metà: backend terminato con staging parziale
  C = await open();
  const crash = await begin(C, sha('s3'));
  await stage(C, crash.run_id, [row('9000001', 'v2'), row('9000004')]);
  const before = (await adm(`select md5(string_agg(id::text || ctid::text || xmin::text, ',' order by id)) as d from catalog.source_records where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0].d;
  await adm('select pg_terminate_backend($1)', [C.pid]);
  await sleep(300);
  const after = (await adm(`select md5(string_agg(id::text || ctid::text || xmin::text, ',' order by id)) as d from catalog.source_records where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0].d;
  const st = (await adm('select status from catalog.import_runs where id = $1', [crash.run_id]))[0].status;
  check('P07', 'crash a metà: il tentativo resta running, source_records è fisicamente identica (nulla è stato promosso)', st === 'running' && before === after, `${st}`);
  let refused = '';
  try { await begin(A, sha('s3')); refused = 'accettato'; } catch (e) { refused = msg(e); }
  check('P08', 'dopo il crash, senza takeover, un nuovo avvio è rifiutato (non si sovrascrive un tentativo possibilmente vivo)', /già in corso|55P03/.test(refused), refused);
  let early = '';
  try { await begin(A, sha('s3'), { takeover: true, staleSecs: 600 }); early = 'accettato'; } catch (e) { early = msg(e); }
  check('P09', 'takeover prima della scadenza del heartbeat rifiutato', /ancora attivo|55P03/.test(early), early);
  const resumed = await begin(A, sha('s3'), { takeover: true, staleSecs: 0 });
  await stage(A, resumed.run_id, [row('9000001', 'v2'), row('9000002'), row('9000003'), row('9000004')]);
  const fin3 = await finish(A, resumed.run_id, 4, {});
  const crashed = (await adm('select status from catalog.import_runs where id = $1', [crash.run_id]))[0].status;
  check('P10', 'ripresa controllata: tentativo interrotto abandoned, ripresa completa; 1 aggiornato, 1 nuovo, 2 invariati', crashed === 'abandoned' && fin3.updated === 1 && fin3.new === 1 && fin3.unchanged === 2, JSON.stringify(fin3));
  const hist = (await adm(`select string_agg(status, ',' order by seq) as s from catalog.import_runs where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0].s;
  check('P11', 'storia dei tentativi conservata (abandoned, succeeded, failed, abandoned, succeeded)', hist === 'abandoned,succeeded,failed,abandoned,succeeded', hist);

  // P12 — ruolo effettivo: l'adattatore reale lo imposta come parametro di avvio e lo MANTIENE dopo una riconnessione
  const { connectLocal } = await import('../lib/db-bun.mjs');
  const real = await connectLocal(url);
  await real.assertRole();
  const pidBefore = (await real.query('select pg_backend_pid() as p')).rows[0].p;
  await adm('select pg_terminate_backend($1)', [pidBefore]);
  await sleep(400);
  let afterKill = null;
  try { afterKill = (await real.query('select current_user::text as cu, pg_backend_pid() as p')).rows[0]; } catch { afterKill = (await real.query('select current_user::text as cu, pg_backend_pid() as p')).rows[0]; }
  await real.assertRole();
  check('P12', 'dopo la terminazione del backend e la riconnessione del client il ruolo effettivo resta catalog_loader (nuovo backend)', afterKill.cu === 'catalog_loader' && afterKill.p !== pidBefore, JSON.stringify(afterKill));
  await real.close();

  // P13 — una sessione che NON è catalog_loader (es. postgres) è rifiutata dalla verifica prima di ogni operazione privilegiata
  const wrong = await connectLocal(url, { role: null }).then(() => 'accettata', (e) => String(e.message));
  check('P13', 'connessione senza il ruolo del caricatore: verifica del ruolo rifiutata', wrong === 'accettata' ? false : true, wrong);
  const wrongRole = new Bun.SQL({ url, max: 1 });
  const { assertEffectiveRole } = await import('../lib/role-check.mjs');
  const msg13 = await assertEffectiveRole(async (t, pr) => ({ rows: Array.from(await wrongRole.unsafe(t, pr)) }), 'catalog_loader').then(() => 'accettata', (e) => String(e.message));
  check('P13b', 'sessione postgres: rifiutata con motivo "ruolo effettivo"', /ruolo effettivo "postgres"/.test(msg13), msg13);
  await wrongRole.close();

  // P14 — smoke di scala del finish (10.000 record): base e poi 10% modificato subito dopo, con tetto di tempo e
  // statement_timeout di 60 s. NON è la guardia contro il piano quadratico: su un database vuoto passa anche con il
  // nestloop ripristinato (controllo negativo eseguito); il difetto compare solo con tabelle già popolate e senza
  // statistiche (misurato con EXPLAIN ANALYZE, vedi architettura §11). La guardia è il caso 12zs A12b.
  const N14 = 10000;
  const rows14 = (changed) => Array.from({ length: N14 }, (_, i) => row(String(9500001 + i), changed && i % 10 === 3 ? 'v2' : 'v1'));
  const D = await open();
  try {
    await D.q("set statement_timeout = '60s'");
    const timeFinish = async (shaHex, rows) => {
      const b = await begin(D, shaHex);
      for (let i = 0; i < rows.length; i += 1000) await stage(D, b.run_id, rows.slice(i, i + 1000));
      const t = performance.now();
      const f = await finish(D, b.run_id, rows.length, { allow_mass_removal: true });
      return { ms: performance.now() - t, f };
    };
    const base14 = await timeFinish(sha('p14-base'), rows14(false));
    const mod14 = await timeFinish(sha('p14-mod'), rows14(true));
    console.log(`    (finish ${N14} record: base ${Math.round(base14.ms)} ms, modificato ${Math.round(mod14.ms)} ms)`);
    check('P14', `finish su ${N14} record (smoke di scala: base < 30 s, modificato < 8 s); ${mod14.f.updated} aggiornati, ${mod14.f.unchanged} invariati`,
      base14.ms < 30000 && mod14.ms < 8000 && base14.f.new === N14 && mod14.f.updated === N14 / 10 && mod14.f.unchanged === N14 - N14 / 10, JSON.stringify([base14.f.new, mod14.f.updated, mod14.f.unchanged]));
  } finally {
    await D.c.close();
  }
} catch (e) {
  check('ERR', 'eccezione non attesa', false, msg(e));
} finally {
  for (const c of [A, B, C]) { try { await c?.c.close(); } catch { /* connessione già chiusa */ } }
  try { await cleanup(); check('CLEAN', 'dati di prova rimossi (nessun residuo della fonte WI-CONC-TEST)', (await adm('select count(*)::int as n from catalog.sources where code = $1', [CODE]))[0].n === 0); } catch (e) { check('CLEAN', 'pulizia', false, msg(e)); }
  await admin.close();
}
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} controlli superati`);
process.exit(failed.length ? 1 : 0);
