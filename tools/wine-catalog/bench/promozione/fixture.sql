-- Banco della promozione: catalogo di fonte SINTETICO con le proporzioni misurate in Production il 26 novembre 2026,
-- caricato con le RPC vere del caricatore (quindi con lo stesso «inserisci e poi aggiorna il territorio» dell'import).
-- Nessun dato LWIN reale. SOLO stack effimero/locale; committa (il banco usa uno stack che poi distrugge).
--
--   212.894 record = Live vino 185.761 (159.614 candidati, di cui 7.208 omonimi in 2.617 gruppi; 26.099 senza nome;
--   48 solo possibile duplicato) + Combined vino 4.879 (4.206 verso candidati) + Deleted vino 313 +
--   fuori ambito: Live 20.406, Combined 1.342, Deleted 193. 27.410 produttori, 59 paesi.
\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard banco: il database contiene utenti reali.';
  end if;
  if (select count(*) from catalog.source_records) <> 0 or (select count(*) from catalog.wines) <> 0 then
    raise exception 'Guard banco: il catalogo non è vuoto.';
  end if;
end $$;

drop table if exists public.zz_banco_fx;
create unlogged table public.zz_banco_fx (
  n bigint primary key, external_id text not null, status text not null, scope text not null, reference_external_id text,
  producer_name text, wine text, country text, region text, colour text, designation text, classification text);

-- 1. Candidati: i primi 27.410 danno un vino a ogni produttore, gli altri si distribuiscono in modo asimmetrico.
select setseed(0.42);
insert into public.zz_banco_fx
select g, (1000000 + g)::text, 'Live', 'wine', null, 'Produttore ' || p, 'Vino ' || g,
       'Paese ' || (case when p <= 59 then p else 1 + (p * 7919::bigint % 59 * (p * 104729::bigint % 59)) / 59 end),
       case when g % 27 = 0 then null else 'Regione ' || (g % 400) end,
       case when g % 57 = 0 then null else (array['Red','Red','Red','White','White','Rose','Mixed'])[1 + g % 7] end,
       case when g % 8 = 0 then null else 'Denominazione ' || (g % 900) end,
       case when g % 30 = 0 then 'Classificazione ' || (g % 40) end
  from (select g, case when g <= 27410 then g else 1 + floor(18682 * power(random(), 2))::int end as p
          from generate_series(1, 159614) g) t;

-- Omonimie: 2.617 gruppi (1.974 da tre e 643 da due) = 7.208 vini; stesso produttore e nome, regione diversa.
with scelti as (
  select producer_name, row_number() over (order by producer_name) as k
    from public.zz_banco_fx group by producer_name having count(*) >= 3 order by producer_name limit 2617),
righe as (
  select f.n, s.k, row_number() over (partition by f.producer_name order by f.n) as i
    from public.zz_banco_fx f join scelti s using (producer_name))
update public.zz_banco_fx f
   set wine = 'Omonimo ' || r.k, region = 'Regione omonima ' || r.i
  from righe r
 where r.n = f.n and r.i <= case when r.k <= 1974 then 3 else 2 end;

-- 2. Live vino esclusi: 26.099 senza nome del vino, 48 (24 coppie) solo possibile duplicato.
insert into public.zz_banco_fx
select 159614 + g, (1159614 + g)::text, 'Live', 'wine', null, 'Produttore ' || (1 + g % 27410), null,
       'Paese ' || (1 + g % 59), 'Regione ' || (g % 400), 'Red', null, null
  from generate_series(1, 26099) g;
insert into public.zz_banco_fx
select 185713 + g, (1185713 + g)::text, 'Live', 'wine', null, 'Doppio ' || ((g + 1) / 2), 'Identico ' || ((g + 1) / 2),
       'Paese 1', 'Regione 1', 'Red', null, null
  from generate_series(1, 48) g;
-- 3. Combined e Deleted in ambito vino.
insert into public.zz_banco_fx
select 185761 + g, (1185761 + g)::text, 'Combined', 'wine',
       case when g <= 4206 then (1000000 + g * 37 % 159614 + 1)::text else (1159614 + g - 4206)::text end,
       'Produttore ' || g, 'Accorpato ' || g, 'Paese 1', 'Regione 1', 'Red', null, null
  from generate_series(1, 4879) g;
insert into public.zz_banco_fx
select 190640 + g, (1190640 + g)::text, 'Deleted', 'wine', null, 'Produttore ' || g, 'Eliminato ' || g, 'Paese 1', 'Regione 1', 'Red', null, null
  from generate_series(1, 313) g;
-- 4. Fuori ambito vino.
insert into public.zz_banco_fx
select 190953 + g, (1190953 + g)::text,
       case when g <= 20406 then 'Live' when g <= 21748 then 'Combined' else 'Deleted' end, 'other',
       case when g > 20406 and g <= 21748 then (1190953 + g - 20406)::text end,
       'Distilleria ' || (g % 3000), 'Prodotto ' || g, 'Paese ' || (1 + g % 59), null, null, null, null
  from generate_series(1, 21941) g;

do $$
begin
  if (select count(*) from public.zz_banco_fx) <> 212894 then
    raise exception 'Banco: fixture di % righe, attese 212894', (select count(*) from public.zz_banco_fx);
  end if;
end $$;

-- Righe di fonte con peso simile a quelle vere (≈1,4 KB per riga viva misurati in Production).
create or replace view public.zz_banco_record as
select f.n, jsonb_build_object(
  'external_id', f.external_id, 'status', f.status, 'scope', f.scope, 'reference_external_id', f.reference_external_id,
  'country', f.country, 'region', f.region, 'sub_region', null,
  'payload', jsonb_build_object('lwin', f.external_id, 'status', f.status, 'producer_name', f.producer_name, 'wine', f.wine,
     'country', f.country, 'region', f.region, 'colour', f.colour, 'type', 'Wine', 'sub_type', 'Still',
     'designation', f.designation, 'classification', f.classification,
     'display_name', coalesce(f.producer_name, '') || ', ' || coalesce(f.wine, ''), 'nota', repeat('x', 190)),
  'raw', jsonb_build_object('LWIN', f.external_id, 'STATUS', f.status, 'PRODUCER_NAME', f.producer_name, 'WINE', f.wine,
     'COUNTRY', f.country, 'REGION', f.region, 'COLOUR', f.colour, 'TYPE', 'Wine', 'NOTA', repeat('y', 270)),
  'content_hash', encode(sha256(convert_to(concat_ws('|', f.external_id, f.status, f.reference_external_id, f.producer_name, f.wine, f.country, f.region, f.colour), 'UTF8')), 'hex')) as r
  from public.zz_banco_fx f;
grant select on public.zz_banco_record, public.zz_banco_fx to catalog_loader;

create unlogged table public.zz_banco_run (id uuid);
grant select, insert on public.zz_banco_run to catalog_loader;

set statement_timeout = 0;
set role catalog_loader;
insert into public.zz_banco_run select (catalog.begin_import_run('LIVEX-LWIN7', repeat('b', 64), 'sintetico-banco-promozione.xlsx', null, 'banco-promozione') ->> 'run_id')::uuid;
do $$
declare v_run uuid := (select id from public.zz_banco_run); i bigint := 0;
begin
  while i < 212894 loop
    perform catalog.stage_source_records(v_run, (select jsonb_agg(r order by n) from public.zz_banco_record where n > i and n <= i + 2000));
    i := i + 2000;
  end loop;
end $$;
select catalog.finish_import_run((select id from public.zz_banco_run), 212894) as fine_import;
reset role;

drop view public.zz_banco_record;
drop table public.zz_banco_fx, public.zz_banco_run;
analyze;
