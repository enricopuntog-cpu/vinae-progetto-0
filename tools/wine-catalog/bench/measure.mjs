#!/usr/bin/env bun
// Banco di misura dell'import differenziale su un PostgreSQL LOCALE (loopback). Esegue il caricatore reale
// (`lwin-load.mjs`) come processo figlio e, prima e dopo ogni passo, rileva: WAL generato, tuple scritte per
// tabella (n_tup_ins/upd/del), dimensioni (tabelle e database), righe morte, tempo e RSS massimo del caricatore.
// Non è un test con soglie: produce numeri da leggere. NON usare su database remoti (rifiutati).
//
//   CATALOG_DATABASE_URL=postgresql://…@127.0.0.1:PORT/postgres \
//   bun tools/wine-catalog/bench/measure.mjs --base <base.xlsx> --modified <mod.xlsx> --report <out.json> \
//        [--steps base,repeat,repeat-force,modified,modified-repeat,revert] [--batch-size 2000]
//
// La base dati deve avere la migration applicata e nessun import precedente (altrimenti il passo `base` non è «a freddo»).
import { writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { assertLocalDatabaseUrl, insideRepo } from '../lib/paths.mjs';

const { values: a } = parseArgs({ options: {
  base: { type: 'string' }, modified: { type: 'string' }, report: { type: 'string' }, steps: { type: 'string' }, 'batch-size': { type: 'string' },
} });
const url = process.env.CATALOG_DATABASE_URL;
if (!url || !a.base || !a.report) { console.error('Servono CATALOG_DATABASE_URL, --base e --report.'); process.exit(2); }
assertLocalDatabaseUrl(url);
if (insideRepo(a.report)) { console.error('Il report va scritto fuori dal repository.'); process.exit(2); }
const steps = (a.steps ?? 'base,repeat,repeat-force,modified,modified-repeat,revert').split(',');
const here = dirname(fileURLToPath(import.meta.url));
const loader = join(here, '..', 'lwin-load.mjs');

const sql = new Bun.SQL({ url, max: 1 });
const q = async (text, params = []) => Array.from(await sql.unsafe(text, params));
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');

async function snapshot() {
  await q('select pg_stat_force_next_flush()');
  const lsn = (await q('select pg_current_wal_lsn()::text as l'))[0].l;
  const tables = await q(`select c.relname as t, coalesce(s.n_tup_ins,0)::bigint as ins, coalesce(s.n_tup_upd,0)::bigint as upd,
      coalesce(s.n_tup_hot_upd,0)::bigint as hot, coalesce(s.n_tup_del,0)::bigint as del, coalesce(s.n_dead_tup,0)::bigint as dead,
      pg_total_relation_size(c.oid)::bigint as bytes
    from pg_class c left join pg_stat_all_tables s on s.relid = c.oid
    where c.relnamespace = 'catalog'::regnamespace and c.relkind = 'r' order by 1`);
  const db = (await q('select pg_database_size(current_database())::bigint as b'))[0].b;
  return { lsn, tables: Object.fromEntries(tables.map((r) => [r.t, { ins: Number(r.ins), upd: Number(r.upd), hot: Number(r.hot), del: Number(r.del), dead: Number(r.dead), bytes: Number(r.bytes) }])), db: Number(db) };
}

async function runLoader(file, extra, tag) {
  const out = join(process.env.TEMP ?? '/tmp', `wi001b-measure-${tag}-${Date.now()}.json`);
  const s = sha(file);
  const args = [process.execPath, loader, '--input', file, '--report', out, '--expected-sha256', s, ...extra];
  if (a['batch-size']) args.push('--batch-size', a['batch-size']);
  const t0 = performance.now();
  const proc = Bun.spawn(args, { env: { ...process.env, CATALOG_DATABASE_URL: url }, stdout: 'pipe', stderr: 'pipe' });
  const code = await proc.exited;
  const wall = performance.now() - t0;
  const usage = proc.resourceUsage?.();
  const err = await new Response(proc.stderr).text();
  let rep = null;
  try { rep = JSON.parse(readFileSync(out, 'utf8')); } catch { /* il caricatore può fallire prima del report */ }
  return { code, wall_ms: Math.round(wall), max_rss_mb: usage?.maxRSS ? Math.round(usage.maxRSS / 1048576) : null, report: rep, stderr_tail: err.split('\n').filter((l) => !l.startsWith('…')).slice(-5).join('\n') };
}

const plan = {
  base: () => [a.base, [], 'base'],
  repeat: () => [a.base, [], 'repeat'],
  'repeat-force': () => [a.base, ['--force'], 'repeat-force'],
  modified: () => [a.modified, [], 'modified'],
  'modified-repeat': () => [a.modified, [], 'modified-repeat'],
  revert: () => [a.base, [], 'revert'],
};

const results = [];
for (const step of steps) {
  if (!plan[step]) throw new Error(`passo sconosciuto: ${step}`);
  const [file, extra, tag] = plan[step]();
  if (!file) throw new Error(`passo ${step}: file mancante`);
  const before = await snapshot();
  const run = await runLoader(file, extra, tag);
  const after = await snapshot();
  const wal = Number((await q('select pg_wal_lsn_diff($1::pg_lsn, $2::pg_lsn)::bigint as d', [after.lsn, before.lsn]))[0].d);
  const perTable = {};
  for (const t of Object.keys(after.tables)) {
    const b = before.tables[t] ?? { ins: 0, upd: 0, hot: 0, del: 0, dead: 0, bytes: 0 };
    const d = after.tables[t];
    const row = { ins: d.ins - b.ins, upd: d.upd - b.upd, del: d.del - b.del, dead_after: d.dead, bytes_after: d.bytes, bytes_growth: d.bytes - b.bytes };
    if (row.ins || row.upd || row.del || row.bytes_growth) perTable[t] = row;
  }
  const r = run.report;
  results.push({
    step, exit_code: run.code, wall_ms: run.wall_ms, loader_elapsed_ms: r?.elapsed_ms ?? null, max_rss_mb: run.max_rss_mb, loader_rss_end_mb: r?.peak_rss_mb ?? null,
    mode: r?.mode ?? null, counts: r?.result ? { new: r.result.new, updated: r.result.updated, unchanged: r.result.unchanged, reappeared: r.result.reappeared, removed: r.result.removed_from_source, records_seen: r.result.records_seen } : null,
    wal_bytes: wal, db_bytes_after: after.db, db_growth_bytes: after.db - before.db, tuples: perTable, stderr_tail: run.code ? run.stderr_tail : undefined,
  });
  console.log(`${step}: exit ${run.code}, ${run.wall_ms} ms, WAL ${(wal / 1048576).toFixed(1)} MB, rss ${run.max_rss_mb} MB, modo ${r?.mode}`);
}
const extras = await q(`select (select count(*) from catalog.source_records) as records, (select count(*) from catalog.source_record_events) as events,
  (select count(*) from catalog.import_runs) as runs, (select count(*) from catalog.import_findings) as findings`);
writeFileSync(a.report, JSON.stringify({ generated_at: new Date().toISOString(), server: (await q('select version() as v'))[0].v, steps: results, final: extras[0] }, (k, v) => (typeof v === 'bigint' ? Number(v) : v), 2));
await sql.close();
