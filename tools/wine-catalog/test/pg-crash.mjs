#!/usr/bin/env bun
// Prova di CRASH REALE del server PostgreSQL locale e ripresa dell'import (WI-001B) — tabella staging UNLOGGED.
// Una tabella UNLOGGED viene svuotata dal recupero dopo un arresto anomalo; il tentativo (tabella normale, con WAL)
// resta `running`. La prova verifica che il progetto sia FAIL-CLOSED: dopo il crash nulla viene dichiarato `succeeded`
// con uno staging perso, e la ripresa controllata completa l'import.
//
// DISTRUTTIVA PER IL CONTENITORE INDICATO (docker kill = SIGKILL, poi docker start): usare SOLO sul database locale
// isolato di questo task. Per evitare incidenti servono ENTRAMBE le variabili e il nome del contenitore deve essere
// esattamente quello dichiarato:
//
//   CATALOG_DATABASE_URL=postgresql://postgres:…@127.0.0.1:58322/postgres \
//   VINEA_CRASH_CONTAINER=supabase_db_vinea_wi001b_local \
//   VINEA_CRASH_CONFIRM=distruggi-questo-database-locale \
//   bun tools/wine-catalog/test/pg-crash.mjs
//
// Usa una fonte di prova (`WI-CRASH-TEST`) rimossa a fine prova; non tocca LIVEX-LWIN7. Esce con 1 se un controllo fallisce.
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { assertLocalDatabaseUrl } from '../lib/paths.mjs';

const url = process.env.CATALOG_DATABASE_URL;
const container = process.env.VINEA_CRASH_CONTAINER;
if (!url || !container || process.env.VINEA_CRASH_CONFIRM !== 'distruggi-questo-database-locale') {
  console.error('Servono CATALOG_DATABASE_URL, VINEA_CRASH_CONTAINER e VINEA_CRASH_CONFIRM=distruggi-questo-database-locale.');
  process.exit(2);
}
assertLocalDatabaseUrl(url);
if (!/^supabase_db_vinea_wi001b_[a-z0-9_]+$/.test(container)) {
  console.error('Il contenitore deve essere il database isolato di WI-001B (supabase_db_vinea_wi001b_*).');
  process.exit(2);
}

const CODE = 'WI-CRASH-TEST';
const results = [];
const check = (id, desc, ok, detail = '') => { results.push({ id, ok: Boolean(ok) }); console.log(`${ok ? 'OK  ' : 'FAIL'} ${id} ${desc}${ok ? '' : ` — ${detail}`}`); };
const sha = (s) => createHash('sha256').update(s).digest('hex');
const msg = (e) => String(e?.message ?? e);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const row = (ext, tag = 'v1') => ({
  external_id: ext, status: 'Live', scope: 'wine', reference_external_id: null, country: 'Italy', region: 'Piedmont', sub_region: null,
  payload: { lwin: ext, tag }, raw: { LWIN: ext }, content_hash: sha(`${ext}|${tag}`),
});
const parse = (v) => (typeof v === 'string' ? JSON.parse(v) : v);
const docker = (...a) => spawnSync('docker', a, { encoding: 'utf8' });

const { connectLocal } = await import('../lib/db-bun.mjs');
let admin = new Bun.SQL({ url, max: 1 });
const adm = async (t, p = []) => Array.from(await admin.unsafe(t, p));

async function cleanup() {
  const src = (await adm('select id from catalog.sources where code = $1', [CODE]))[0]?.id;
  if (!src) return;
  for (const s of [
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
  ]) await adm(s, [src]);
}

const state = async () => (await adm(`select md5(coalesce(string_agg(id::text || ctid::text || xmin::text || content_hash, ',' order by id), '')) as d, count(*)::int as n
  from catalog.source_records where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0];

async function waitReady(maxMs = 120000) {
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    const r = docker('exec', container, 'pg_isready', '-U', 'postgres', '-d', 'postgres');
    if (r.status === 0) {
      try { const c = new Bun.SQL({ url, max: 1 }); await c.unsafe('select 1'); await c.close(); return Date.now() - t0; } catch { /* ancora in avvio */ }
    }
    await sleep(1000);
  }
  throw new Error('il database non è tornato disponibile entro il limite');
}

let L;
try {
  await cleanup();
  await adm(`insert into catalog.sources (code, name, authorization_status) values ($1, 'Fonte di prova crash', 'authorized')`, [CODE]);
  const unlogged = (await adm(`select relpersistence from pg_class where oid = 'catalog.import_stage'::regclass`))[0].relpersistence;
  check('C00', 'import_stage è UNLOGGED (relpersistence = u) e import_runs è normale (p)',
    unlogged === 'u' && (await adm(`select relpersistence from pg_class where oid = 'catalog.import_runs'::regclass`))[0].relpersistence === 'p');

  // snapshot 1 completo: 50 record
  L = await connectLocal(url);
  const q = async (t, p = []) => (await L.query(t, p)).rows;
  const begin = async (shaHex, o = {}) => parse((await q('select catalog.begin_import_run($1,$2,$3,$4,$5,$6,make_interval(secs => $7::int),$8) as r', [CODE, shaHex, 'prova.xlsx', null, 'pg-crash', o.takeover ?? false, o.staleSecs ?? 600, false]))[0].r);
  const stage = async (id, rows) => parse((await q('select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r', [id, JSON.stringify(rows)]))[0].r);
  const finish = async (id, n) => parse((await q('select catalog.finish_import_run($1::uuid, $2::bigint, ($3::text)::jsonb) as r', [id, n, '{}']))[0].r);
  const base = Array.from({ length: 50 }, (_, i) => row(String(8000001 + i)));
  const r1 = await begin(sha('s1'));
  await stage(r1.run_id, base);
  const f1 = await finish(r1.run_id, 50);
  check('C01', 'snapshot 1 importato (50 nuovi)', f1.new === 50, JSON.stringify(f1));

  // snapshot 2: 3 modificati; si mette in staging solo una parte, poi crash
  const s2 = base.map((r, i) => (i < 3 ? row(r.external_id, 'v2') : r));
  const r2 = await begin(sha('s2'));
  await stage(r2.run_id, s2.slice(0, 30));
  const stagedBefore = (await adm('select count(*)::int as n from catalog.import_stage where run_id = $1', [r2.run_id]))[0].n;
  const before = await state();
  await L.close(); L = null;

  const t0 = Date.now();
  const k = docker('kill', container);
  check('C02', 'docker kill (SIGKILL) del server PostgreSQL locale', k.status === 0, k.stderr);
  const s = docker('start', container);
  check('C03', 'riavvio del contenitore', s.status === 0, s.stderr);
  const up = await waitReady();
  console.log(`    (server tornato disponibile dopo ${Math.round((Date.now() - t0) / 1000)} s; recupero ${up} ms dopo l'avvio)`);
  await admin.close(); admin = new Bun.SQL({ url, max: 1 });

  const after = await state();
  const stagedAfter = (await adm('select count(*)::int as n from catalog.import_stage where run_id = $1', [r2.run_id]))[0].n;
  const runSt = (await adm('select status from catalog.import_runs where id = $1', [r2.run_id]))[0]?.status;
  check('C04', `staging UNLOGGED svuotato dal recupero dopo il crash (prima ${stagedBefore} righe, dopo ${stagedAfter})`, stagedBefore === 30 && stagedAfter === 0, `${stagedBefore}/${stagedAfter}`);
  check('C05', 'il tentativo (tabella con WAL) è sopravvissuto e resta running — non è né succeeded né perso', runSt === 'running', runSt);
  check('C06', 'source_records è fisicamente identica a prima del crash (nulla era stato promosso)', before.d === after.d && after.n === 50);

  // fail-closed: il finish senza rifare lo staging è rifiutato
  L = await connectLocal(url);
  const q2 = async (t, p = []) => (await L.query(t, p)).rows;
  const tryFinish = async (id, n, summary) => { try { await q2('select catalog.finish_import_run($1::uuid, $2::bigint, ($3::text)::jsonb) as r', [id, n, JSON.stringify(summary)]); return 'accettato'; } catch (e) { return msg(e); } };
  const m1 = await tryFinish(r2.run_id, 50, {});
  check('C07', 'finish con lo staging perso (visti 0, attesi 50): rifiutato come import incompleto', /incompleto/.test(m1), m1);
  const m2 = await tryFinish(r2.run_id, 0, {});
  check('C08', 'finish con conteggio atteso 0 (tentativo di far passare un file vuoto): rifiutato come rimozione di massa', /rimozione di massa/.test(m2), m2);
  check('C09', 'dopo i rifiuti il tentativo è ancora running e source_records è invariata', (await adm('select status from catalog.import_runs where id = $1', [r2.run_id]))[0].status === 'running' && (await state()).d === before.d);

  // ripresa controllata: takeover dopo la scadenza, stage completo, finish
  const resumed = parse((await q2('select catalog.begin_import_run($1,$2,$3,$4,$5,$6,make_interval(secs => 0),$7) as r', [CODE, sha('s2'), 'prova.xlsx', null, 'pg-crash', true, false]))[0].r);
  parse((await q2('select catalog.stage_source_records($1::uuid, ($2::text)::jsonb) as r', [resumed.run_id, JSON.stringify(s2)]))[0].r);
  const f2 = parse((await q2('select catalog.finish_import_run($1::uuid, $2::bigint, ($3::text)::jsonb) as r', [resumed.run_id, 50, '{}']))[0].r);
  check('C10', 'ripresa con takeover: tentativo fermo abandoned, nuovo tentativo completo; 3 aggiornati, 47 invariati, 0 nuovi',
    (await adm('select status from catalog.import_runs where id = $1', [r2.run_id]))[0].status === 'abandoned' && f2.updated === 3 && f2.unchanged === 47 && f2.new === 0, JSON.stringify(f2));
  check('C11', 'storia conservata: succeeded, abandoned, succeeded', (await adm(`select string_agg(status, ',' order by seq) as s from catalog.import_runs where source_id = (select id from catalog.sources where code = $1)`, [CODE]))[0].s === 'succeeded,abandoned,succeeded');
} catch (e) {
  check('ERR', 'eccezione non attesa', false, msg(e));
} finally {
  try { await L?.close(); } catch { /* già chiusa */ }
  try { await cleanup(); check('CLEAN', 'dati di prova rimossi', (await adm('select count(*)::int as n from catalog.sources where code = $1', [CODE]))[0].n === 0); } catch (e) { check('CLEAN', 'pulizia', false, msg(e)); }
  await admin.close();
}
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} controlli superati`);
process.exit(failed.length ? 1 : 0);
