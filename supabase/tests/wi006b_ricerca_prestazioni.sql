-- WI-006B — misura MANUALE (non nel gate) del motore `vini_cerca` su un catalogo sintetico grande.
--
--   psql -v n=200000 -f supabase/tests/wi006b_ricerca_prestazioni.sql      (solo stack locale/effimero)
--
-- Carica `:n` vini sintetici con vocabolario variegato (sillabe combinate: nomi di produttori e di vini
-- plausibili, con parole molto comuni come «barolo» o «riserva»), esegue ANALYZE, e misura con
-- EXPLAIN ANALYZE la RPC vera come `authenticated`. Stampa i tempi, non pretende soglie: i numeri
-- vanno riportati nel documento con la data, la versione di PostgreSQL e la macchina. Tutto dentro
-- una transazione chiusa da ROLLBACK (nessun residuo). Rifiuta un database con utenti non `.test`.

\if :{?n}
\else
  \set n 200000
\endif

begin;

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Misura wi006b: il database contiene utenti reali, rifiutata.';
  end if;
end $$;

create temp table syl on commit drop as
  select s, row_number() over () as i from unnest(array[
    'ba','be','bi','bo','ca','ce','ci','co','cu','da','de','di','do','fa','fe','fi','fo','ga','ge','gi','go',
    'la','le','li','lo','lu','ma','me','mi','mo','na','ne','ni','no','pa','pe','pi','po','ra','re','ri','ro',
    'sa','se','si','so','ta','te','ti','to','va','ve','vi','vo','za','ze','zi','zo','tor','ren','sol','mar',
    'gal','ber','cas','mon','ter','nel']) s;
create function pg_temp.w(n bigint, ns int) returns text language sql as $f$
  select string_agg((select s from syl where i = 1 + ((n * 7919 + k * 104729 + (n / (k + 3))) % 68)), '')
  from generate_series(1, ns) k $f$;

insert into public.wines (slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
select 'perf-' || x,
  initcap(case when x % 5 = 0 then (array['tenuta','cantina','azienda agricola','domaine','chateau'])[1 + x % 4] || ' ' else '' end
          || pg_temp.w((x * 13) % 30000, 3) || ' ' || pg_temp.w((x * 29) % 9000, 2)),
  initcap((array['barolo','chianti classico','amarone','brunello di montalcino','soave','franciacorta',
                 'etna rosso','langhe nebbiolo','bolgheri','valpolicella'])[1 + x % 10]
          || ' ' || pg_temp.w((x * 31) % 4000, 3) || case when x % 3 = 0 then ' riserva' else '' end),
  1950 + x % 70, 'Veneto', 'DOC', 'Rosso', (array['0,75 L', '1,5 L', '0,375 L'])[1 + x % 3], 'staff'
from generate_series(1, :n) x
on conflict do nothing;
analyze public.wines;

select count(*) as vini, count(*) filter (where slug like 'perf-%') as sintetici from public.wines;

-- Un produttore e un nome realmente presenti, per le domande «esatte» e «con refuso».
select produttore as p, nome as v, annata as a from public.wines where slug = 'perf-1000' \gset
select :'p' as produttore, :'v' as nome, :a as annata;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);

\echo '--- esatto (livello 2): produttore + nome + annata'
explain (analyze, buffers, costs off) select * from public.vini_cerca(:'p', :'v', :a);
\echo '--- testo (livello 3): produttore parziale + nome'
explain (analyze, buffers, costs off) select * from public.vini_cerca(split_part(:'p', ' ', 1), split_part(:'v', ' ', 1));
\echo '--- refuso (livello 4): una lettera in piu nel produttore e nel nome'
explain (analyze, buffers, costs off) select * from public.vini_cerca(:'p' || 'x', :'v' || 'x');
\echo '--- identificativo (livello 1)'
explain (analyze, buffers, costs off) select * from public.vini_cerca(p_codice => 'perf-1000');
\echo '--- termine molto comune da solo (caso peggiore: migliaia di candidati)'
explain (analyze, buffers, costs off) select * from public.vini_cerca('', 'Barolo');
\echo '--- nessun risultato'
explain (analyze, buffers, costs off) select * from public.vini_cerca('Zzqxjw Inesistente', 'Vinoqwzxc');

rollback;
