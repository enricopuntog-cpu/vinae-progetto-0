-- WI-008 (griglia wi008c): simulazione, anteprima e lotto valutano il rapporto dei candidati UNA SOLA VOLTA, con lo
-- stesso risultato di prima.
--
-- Perché: `catalog.wine_candidate_report` rilegge tutta `catalog.source_records` (639 MB in Production). Prima di
-- WI-008 la simulazione la valutava ~10 volte (timeout), l'anteprima 3, il lotto reale 3 (più il join di ritorno
-- su `source_records` per l'id del record).
--
-- Due prove indipendenti:
--   * EQUIVALENZA: gli oracoli `pg_temp.oracolo_*` sono i corpi PRECEDENTI (WI-001C-FIX-01 / WI-007) copiati qui; il
--     codice nuovo deve restituire gli stessi insiemi, nello stesso ordine, e gli stessi conteggi;
--   * COSTO: con le sole scansioni sequenziali abilitate, `pg_stat_xact_user_tables.seq_scan` di `source_records`
--     cresce esattamente di 1 per chiamata (il conteggio è della transazione corrente, quindi deterministico).
--
-- Fixture sintetiche, nessun LWIN reale. SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi008c: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi008c: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi008c (id text primary key, descrizione text, passed boolean, detail text) on commit drop;
grant all on esiti_wi008c to public;
create temp table ctx (k text primary key, v text) on commit drop;
grant all on ctx to public;

create function pg_temp.rec(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as
$$ insert into esiti_wi008c values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $$;

create function pg_temp.fx(p_ext text, p_status text, p_producer text, p_wine text, p_country text, p_region text,
                           p_colour text, p_ref text default null, p_scope text default 'wine')
returns jsonb language sql as
$$ select jsonb_build_object(
     'external_id', p_ext, 'status', p_status, 'scope', p_scope, 'reference_external_id', p_ref,
     'country', p_country, 'region', p_region, 'sub_region', null,
     'payload', jsonb_build_object('lwin', p_ext, 'status', p_status, 'producer_name', p_producer, 'wine', p_wine,
                                    'country', p_country, 'region', p_region, 'colour', p_colour, 'type', 'Wine'),
     'raw', jsonb_build_object('LWIN', p_ext),
     'content_hash', encode(sha256(convert_to(concat_ws('|', p_ext, p_status, p_ref, p_producer, p_wine, p_country, p_region, p_colour), 'UTF8')), 'hex')) $$;

-- 40 idonei su 7 produttori, più ogni classe di esclusione. 'Ritirata' è il produttore che verrà ritirato.
create temp table fx on commit drop as
  select jsonb_agg(r order by r ->> 'external_id') as batch from (
    select pg_temp.fx((4000000 + g)::text, 'Live', 'Produttore ' || (g % 7), 'Vino ' || g,
                      case when g % 7 in (0, 3) then 'France' else 'Italy' end, case when g % 5 = 0 then null else 'Regione' end,
                      case when g % 4 = 0 then null else 'Red' end) as r
      from generate_series(1, 40) g
    union all select pg_temp.fx('4000101', 'Live', 'Ritirata', 'Primo', 'Italy', 'Piedmont', 'Red')
    union all select pg_temp.fx('4000102', 'Live', 'Ritirata', 'Secondo', 'Italy', 'Piedmont', 'Red')
    union all select pg_temp.fx('4000201', 'Live', 'Doppio', 'Stesso', 'Italy', 'Tuscany', 'Red')
    union all select pg_temp.fx('4000202', 'Live', 'DOPPIO', 'stesso', 'italy', 'tuscany', 'red')
    union all select pg_temp.fx('4000301', 'Live', null, 'Senza produttore', 'Italy', 'Tuscany', 'Red')
    union all select pg_temp.fx('4000302', 'Live', 'Senza nome', null, 'Italy', 'Tuscany', 'Red')
    union all select pg_temp.fx('4000303', 'Live', 'Senza paese', 'Orfano', null, null, 'Red')
    union all select pg_temp.fx('400040', 'Live', 'Codice corto', 'Sei cifre', 'Italy', 'Tuscany', 'Red')
    union all select pg_temp.fx('4000501', 'Combined', 'Produttore 1', 'Vecchio', 'Italy', 'Regione', 'Red', '4000001')
    union all select pg_temp.fx('4000502', 'Deleted', 'Produttore 1', 'Eliminato', 'Italy', 'Regione', 'Red')
    union all select pg_temp.fx('4000601', 'Live', 'Birrificio', 'Non vino', 'Italy', 'Tuscany', null, null, 'other')
  ) t;
grant select on fx to public;

set local role catalog_loader;
insert into ctx select 'run', (catalog.begin_import_run('LIVEX-LWIN7', repeat('c', 64), 'sintetico-wi008c.xlsx', null, 'wi-008c-test') ->> 'run_id');
insert into ctx select 'stage', catalog.stage_source_records((select v::uuid from ctx where k = 'run'), batch)::text from fx;
insert into ctx select 'fin', catalog.finish_import_run((select v::uuid from ctx where k = 'run'), (select jsonb_array_length(batch) from fx))::text;
reset role;
insert into ctx select 'source', id::text from catalog.sources where code = 'LIVEX-LWIN7';

-- ---------------------------------------------------------------------------------------------
-- Oracoli: i corpi precedenti, copiati (non chiamano nulla del codice nuovo)
-- ---------------------------------------------------------------------------------------------
create function pg_temp.oracolo_candidati(p_source_id uuid)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text, blocked_producer_id uuid)
language sql stable as $$
  select sr.id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation, c.classification,
         c.territory_id, c.country, k.producer_key,
         (select p.id from catalog.producers p
           where p.natural_key = k.producer_key
             and (select f.status from catalog.producers f where f.id = catalog.producer_final(p.id)) is distinct from 'active')
    from catalog.wine_candidate_report c
    join catalog.source_records sr on sr.source_id = c.source_id and sr.external_id = c.lwin
    cross join lateral (select catalog.fold_text(c.producer_name) || chr(31) || coalesce(catalog.fold_text(c.country), '') as producer_key) k
   where c.source_id = p_source_id and c.readiness = 'fields_complete' and c.lwin ~ '^[0-9]{7}$'
     and catalog.fold_text(c.producer_name) is not null and catalog.fold_text(c.wine) is not null
     and not exists (select 1 from catalog.wines w where w.lwin7 = c.lwin);
$$;

create function pg_temp.oracolo_conteggi(p_source_id uuid)
returns jsonb language plpgsql stable as $$
declare v jsonb; v_blocked bigint; v_producers bigint;
begin
  with b as (
    select r.*, (r.lwin ~ '^[0-9]{7}$') as lwin_ok,
           exists (select 1 from catalog.wines w where w.lwin7 = r.lwin) as promoted
      from catalog.wine_candidate_report r where r.source_id = p_source_id)
  select jsonb_build_object(
           'live_wine_records', count(*),
           'eligible', count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted),
           'already_promoted', count(*) filter (where promoted),
           'blocked_missing_producer', count(*) filter (where 'missing_producer' = any (review_reasons)),
           'blocked_missing_wine_name', count(*) filter (where 'missing_wine_name' = any (review_reasons)),
           'blocked_missing_country', count(*) filter (where 'missing_country' = any (review_reasons)),
           'blocked_possible_duplicate', count(*) filter (where 'possible_duplicate' = any (review_reasons)),
           'blocked_invalid_lwin7', count(*) filter (where not lwin_ok))
    into v from b;
  select count(*) into v_blocked from pg_temp.oracolo_candidati(p_source_id) where blocked_producer_id is not null;
  v := jsonb_set(v, '{eligible}', to_jsonb((v ->> 'eligible')::bigint - v_blocked));
  select count(distinct catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''))
    into v_producers
    from catalog.wine_candidate_report r
   where r.source_id = p_source_id and r.readiness = 'fields_complete' and r.lwin ~ '^[0-9]{7}$'
     and not exists (select 1 from catalog.wines w where w.lwin7 = r.lwin)
     and not exists (select 1 from catalog.producers p
                      where p.natural_key = catalog.fold_text(r.producer_name) || chr(31) || coalesce(catalog.fold_text(r.country), ''));
  return v || jsonb_build_object('blocked_producer_retired', v_blocked, 'producers_to_create_upper_bound', v_producers);
end;
$$;

-- Confronto completo, ripetibile in ogni stato del catalogo (vuoto, con produttore ritirato, parzialmente promosso)
create function pg_temp.equivalenza(p_prefisso text, p_stato text)
returns void language plpgsql as $f$
declare
  s uuid := (select v::uuid from ctx where k = 'source');
  v_diff bigint; v_a jsonb; v_b jsonb; v_sim jsonb; v_prev jsonb; v_n int;
begin
  select count(*) into v_diff from (
    (select * from catalog.promotion_candidates(s) except all select * from pg_temp.oracolo_candidati(s))
    union all
    (select * from pg_temp.oracolo_candidati(s) except all select * from catalog.promotion_candidates(s))) d;
  perform pg_temp.rec(p_prefisso || '1', p_stato || ': candidati identici all''oracolo (tutte le colonne, id del record compreso)',
    v_diff = 0, v_diff::text);

  foreach v_n in array array[1, 7, 10000] loop
    select coalesce(jsonb_agg(to_jsonb(b)), '[]') into v_a from catalog.promotion_batch(s, v_n) b;
    select coalesce(jsonb_agg(to_jsonb(o) - 'blocked_producer_id' order by o.lwin), '[]') into v_b
      from (select * from pg_temp.oracolo_candidati(s) x where x.blocked_producer_id is null order by x.lwin limit v_n) o;
    perform pg_temp.rec(p_prefisso || '2-' || v_n, p_stato || ': lotto da ' || v_n || ' identico all''oracolo, nello stesso ordine', v_a = v_b,
      jsonb_array_length(v_a)::text || ' / ' || jsonb_array_length(v_b)::text);
  end loop;

  select coalesce(jsonb_agg(to_jsonb(b)), '[]') into v_a from catalog.promotion_blocked(s, 10000) b;
  select coalesce(jsonb_agg(jsonb_build_object('source_record_id', o.source_record_id, 'lwin', o.lwin,
           'blocked_producer_id', o.blocked_producer_id) order by o.lwin), '[]') into v_b
    from pg_temp.oracolo_candidati(s) o
   where o.blocked_producer_id is not null
     and not exists (select 1 from catalog.promotion_exceptions e where e.source_record_id = o.source_record_id and e.reason = 'producer_retired');
  perform pg_temp.rec(p_prefisso || '3', p_stato || ': bloccati non ancora tracciati identici all''oracolo', v_a = v_b,
    v_a::text || ' / ' || v_b::text);

  v_prev := catalog.promotion_preview();
  v_b := pg_temp.oracolo_conteggi(s);
  perform pg_temp.rec(p_prefisso || '4', p_stato || ': conteggi dell''anteprima identici all''oracolo, nessuna scrittura',
    v_prev - 'rule_version' - 'rule_status' - 'promotion_enabled' - 'database_writes' = v_b
    and (v_prev ->> 'database_writes')::int = 0, v_prev::text || ' / ' || v_b::text);

  v_sim := catalog.promotion_simulation('LIVEX-LWIN7', 'lwin-conservative-v1', 200);
  perform pg_temp.rec(p_prefisso || '5', p_stato || ': la simulazione riporta lo stesso riepilogo e gli stessi candidati del lotto reale',
    v_sim -> 'summary' = v_prev
    and (select coalesce(jsonb_agg(c ->> 'lwin'), '[]') from jsonb_array_elements(v_sim -> 'candidates') c)
        = (select coalesce(jsonb_agg(b.lwin), '[]') from catalog.promotion_batch(s, 200) b), left(v_sim::text, 300));
end;
$f$;

-- ---------------------------------------------------------------------------------------------
-- A. Catalogo vuoto
-- ---------------------------------------------------------------------------------------------
select pg_temp.equivalenza('A', 'catalogo vuoto');

do $$
declare v_sim jsonb;
begin
  v_sim := catalog.promotion_simulation('LIVEX-LWIN7', 'lwin-conservative-v1', 50);
  perform pg_temp.rec('A6', 'fixture: 42 idonei, 2 possibili duplicati in 1 gruppo, 1 per ogni campo mancante, 1 LWIN non valido',
    (v_sim -> 'summary' ->> 'eligible')::int = 42 and (v_sim ->> 'possible_duplicate_records')::int = 2
    and jsonb_array_length(v_sim -> 'possible_duplicate_groups') = 1
    and v_sim -> 'excluded_by_reason' = jsonb_build_object('possible_duplicate', 2, 'missing_producer', 1, 'missing_wine_name', 1,
                                                           'missing_country', 1, 'invalid_lwin7', 1)
    and jsonb_array_length(v_sim -> 'excluded_sample') = 6
    and (v_sim -> 'missing_information' ->> 'without_region')::int = 8
    and (v_sim -> 'missing_information' ->> 'without_colour')::int = 10, left((v_sim - 'candidates')::text, 900));
end $$;

-- ---------------------------------------------------------------------------------------------
-- C. Costo: UNA scansione di source_records per chiamata (solo scansioni sequenziali, per contarle)
-- ---------------------------------------------------------------------------------------------
create function pg_temp.scansioni(p_sql text)
returns bigint language plpgsql as $f$
declare v0 bigint; v1 bigint;
begin
  select coalesce(seq_scan, 0) + coalesce(idx_scan, 0) into v0
    from pg_stat_xact_user_tables where schemaname = 'catalog' and relname = 'source_records';
  execute p_sql;
  select coalesce(seq_scan, 0) + coalesce(idx_scan, 0) into v1
    from pg_stat_xact_user_tables where schemaname = 'catalog' and relname = 'source_records';
  return v1 - v0;
end;
$f$;

set local enable_indexscan = off;
set local enable_indexonlyscan = off;
set local enable_bitmapscan = off;
set local max_parallel_workers_per_gather = 0;

do $$
declare s text := (select v from ctx where k = 'source'); n bigint;
begin
  n := pg_temp.scansioni(format('select count(*) from catalog.wine_candidate_report where source_id = %L', s));
  perform pg_temp.rec('C0', 'controllo del metodo: una lettura della vista = 1 scansione di source_records', n = 1, n::text);
  n := pg_temp.scansioni(format('select count(*) from pg_temp.oracolo_candidati(%L)', s));
  perform pg_temp.rec('C0b', 'controllo discriminante: il corpo PRECEDENTE dei candidati scandisce più di una volta', n > 1, n::text);
  n := pg_temp.scansioni(format('select count(*) from catalog.promotion_candidates(%L)', s));
  perform pg_temp.rec('C1', 'promotion_candidates: 1 sola scansione', n = 1, n::text);
  n := pg_temp.scansioni(format('select count(*) from catalog.promotion_lot(%L, 10, 10)', s));
  perform pg_temp.rec('C2', 'promotion_lot (lotto + bloccati insieme): 1 sola scansione', n = 1, n::text);
  n := pg_temp.scansioni('select catalog.promotion_preview()');
  perform pg_temp.rec('C3', 'promotion_preview (e prova a secco): 1 sola scansione', n = 1, n::text);
  n := pg_temp.scansioni('select catalog.promotion_simulation()');
  perform pg_temp.rec('C4', 'promotion_simulation: 1 sola scansione', n = 1, n::text);
  perform pg_temp.rec('C5', 'il lotto reale legge i candidati una volta sola: una sola chiamata a promotion_lot, nessuna a batch/blocked/candidates/vista',
    (select (length(prosrc) - length(replace(prosrc, 'catalog.promotion_lot(', ''))) / length('catalog.promotion_lot(') = 1
            and prosrc !~ 'catalog\.(promotion_batch|promotion_blocked|promotion_candidates|promotion_report|wine_candidate_report)'
       from pg_proc where oid = 'catalog.promote_wine_candidates(text,text,integer,boolean,text)'::regprocedure));
end $$;

reset enable_indexscan;
reset enable_indexonlyscan;
reset enable_bitmapscan;
reset max_parallel_workers_per_gather;

-- ---------------------------------------------------------------------------------------------
-- S. Superficie e impronta
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_fp text := catalog.promotion_logic_fingerprint('lwin-conservative-v1');
  v_f text; v_ok boolean; v_dettaglio text := '';
begin
  perform pg_temp.rec('S1', 'superficie dello schema catalog conforme (surface_audit senza violazioni)',
    not exists (select 1 from catalog.surface_audit() where not ok),
    coalesce((select string_agg(fn || ': ' || why, ' | ') from catalog.surface_audit() where not ok), ''));
  perform pg_temp.rec('S2', 'funzioni nuove: STABLE, non definer, nessun EXECUTE ad anon/authenticated/service_role/loader',
    (select count(*) from pg_proc p
      where p.oid in ('catalog.promotion_retired_producers()'::regprocedure, 'catalog.promotion_report(uuid)'::regprocedure,
                      'catalog.promotion_lot(uuid,integer,integer)'::regprocedure, 'catalog.promotion_analysis(uuid,integer)'::regprocedure)
        and p.provolatile = 's' and not p.prosecdef
        and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and not has_function_privilege('service_role', p.oid, 'EXECUTE') and not has_function_privilege('catalog_loader', p.oid, 'EXECUTE')) = 4);

  -- ogni dipendenza nuova del lotto reale invalida l'impronta se alterata (sotto-transazione che si annulla)
  foreach v_f in array array['catalog.promotion_retired_producers()', 'catalog.promotion_report(uuid)',
                             'catalog.promotion_lot(uuid,integer,integer)'] loop
    v_ok := false;
    begin
      execute format('alter function %s volatile', v_f);
      v_ok := catalog.promotion_logic_fingerprint('lwin-conservative-v1') is distinct from v_fp;
      raise exception 'annulla' using errcode = 'P0001';
    exception when sqlstate 'P0001' then null;
    end;
    if not v_ok then v_dettaglio := v_dettaglio || v_f || ' '; end if;
  end loop;
  perform pg_temp.rec('S3', 'l''impronta copre le tre dipendenze nuove del lotto', v_dettaglio = '', v_dettaglio);
  perform pg_temp.rec('S4', 'la vista conserva security_invoker',
    (select 'security_invoker=on' = any (reloptions) or 'security_invoker=true' = any (reloptions)
       from pg_class where oid = 'catalog.wine_candidate_report'::regclass));
end $$;

-- ---------------------------------------------------------------------------------------------
-- R. Lotto reale con produttore ritirato, a lotti piccoli (regola approvata SOLO in questa transazione)
-- ---------------------------------------------------------------------------------------------
update catalog.promotion_rules set status = 'approved', approved_by = 'founder-test', approved_at = now()
 where version = 'lwin-conservative-v1';
update catalog.promotion_settings set enabled = true, max_batch = 10;

do $$
declare v_p uuid; v_res jsonb;
begin
  -- il produttore esiste già (stessa chiave naturale delle fixture 'Ritirata') e viene ritirato
  insert into catalog.producers (name, name_key, natural_key, origin)
  values ('Ritirata', 'ritirata', 'ritirata' || chr(31) || 'italy', 'manual') returning id into v_p;
  set local role catalog_curator;
  perform catalog.retire_canonical_entity('producer', v_p, 'wi008c: ritirato', 'qa');
  reset role;
end $$;

select pg_temp.equivalenza('B', 'con produttore ritirato');

do $$
declare r1 jsonb; r2 jsonb; v_atteso text[]; v_ottenuto text[];
begin
  select array_agg(o.lwin order by o.lwin) into v_atteso
    from (select lwin from pg_temp.oracolo_candidati((select v::uuid from ctx where k = 'source'))
           where blocked_producer_id is null order by lwin limit 10) o;
  set local role catalog_curator;
  r1 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi008c', p_limit => 10);
  reset role;
  select array_agg(lwin7 order by lwin7) into v_ottenuto from catalog.wines;
  perform pg_temp.rec('R1', 'primo lotto: esattamente i 10 vini che l''oracolo prevede, 2 eccezioni per il produttore ritirato',
    v_ottenuto = v_atteso and (r1 ->> 'wines_created')::int = 10 and (r1 ->> 'exceptions_recorded')::int = 2
    and (r1 ->> 'producers_created')::int = 7 and (r1 ->> 'combined_aliases_created')::int = 1, r1::text);
  set local role catalog_curator;
  r2 := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi008c', p_limit => 10);
  reset role;
  perform pg_temp.rec('R2', 'secondo lotto: 10 vini diversi, nessuna eccezione ripetuta, nessun produttore doppio',
    (r2 ->> 'wines_created')::int = 10 and (r2 ->> 'exceptions_recorded')::int = 0 and (r2 ->> 'producers_created')::int = 0
    and (r2 ->> 'combined_aliases_created')::int = 0
    and (select count(*) from catalog.wines) = 20 and (select count(distinct lwin7) from catalog.wines) = 20, r2::text);
end $$;

select pg_temp.equivalenza('P', 'parzialmente promosso (20 vini)');

do $$
declare r jsonb; v_tot int := 0; v_giri int := 0;
begin
  loop
    set local role catalog_curator;
    r := catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi008c', p_limit => 10);
    reset role;
    v_tot := v_tot + (r ->> 'wines_created')::int;
    v_giri := v_giri + 1;
    exit when (r ->> 'wines_created')::int = 0 or v_giri > 10;
  end loop;
  perform pg_temp.rec('R3', 'lotti fino a esaurimento: 40 vini in totale, i 2 del produttore ritirato mai promossi, idempotente a esaurimento',
    v_tot = 20 and (select count(*) from catalog.wines) = 40
    and not exists (select 1 from catalog.wines where lwin7 in ('4000101', '4000102', '4000201', '4000202', '4000303', '4000501', '4000502', '4000601'))
    and (select count(*) from catalog.promotion_exceptions) = 2, v_tot || ' in ' || v_giri);
end $$;

select pg_temp.equivalenza('E', 'a promozione esaurita');

update catalog.promotion_settings set enabled = false;

select id, descrizione, passed, detail from esiti_wi008c order by id;

do $$
begin
  if exists (select 1 from esiti_wi008c where not passed) then
    raise exception 'wi008c: % casi rossi: %', (select count(*) from esiti_wi008c where not passed),
      (select string_agg(id || ' [' || left(detail, 300) || ']', ', ' order by id) from esiti_wi008c where not passed);
  end if;
end $$;

rollback;
