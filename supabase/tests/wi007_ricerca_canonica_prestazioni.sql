-- WI-007: misure di `public.vini_canonici_cerca` su un catalogo canonico sintetico grande.
-- SOLO stack locale/effimero. 200.000 vini promossi sintetici (≈20.000 produttori) in una transazione
-- chiusa da ROLLBACK. Un solo record di fonte condiviso (la prova non riguarda l'import). Non è Production.
-- Tempi da una macchina di sviluppo: indicano l'ordine di grandezza e l'uso degli indici, non una garanzia.

begin;
\set ON_ERROR_STOP on

do $$
begin
  if (select count(*) from catalog.wines) <> 0 then
    raise exception 'Guard wi007-perf: il catalogo canonico non e vuoto.';
  end if;
end $$;

set local session_replication_role = replica;

do $$
declare
  v_src uuid := (select id from catalog.sources where code = 'LIVEX-LWIN7');
  v_run uuid := gen_random_uuid();
  v_rec bigint;
  v_it bigint;
begin
  insert into catalog.territories (source_id, kind, name, name_key, natural_key) values (v_src, 'country', 'Italia', 'italia', 'it') returning id into v_it;
  insert into catalog.source_records (source_id, external_id, status, scope, payload, raw, content_hash, first_seen_run, changed_in_run)
    values (v_src, '9999999', 'Live', 'wine', '{}', '{}', repeat('e', 64), v_run, v_run) returning id into v_rec;
  insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, status, source_id, source_record_id)
    select 'Produttore ' || n || ' ' || (array['Barolo','Chianti','Brunello','Amarone','Soave','Franciacorta','Etna','Taurasi'])[1 + n % 8],
           'produttore ' || n, v_it, 'produttore ' || n || chr(31) || 'italia', 'promotion', 'active', v_src, v_rec
      from generate_series(1, 20000) n;
  insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, origin, status, source_id, source_record_id, search_key)
    select lpad((1000000 + n)::text, 7, '0'), p.id,
           (array['Barolo','Chianti Classico','Brunello di Montalcino','Amarone della Valpolicella','Soave','Franciacorta Brut','Etna Rosso','Taurasi'])[1 + n % 8]
             || ' Riserva ' || (n % 997),
           'vino ' || n, 'Red', 'Still', 'promotion', 'active', v_src, v_rec,
           public.vini_normalizza(p.name || ' ' || (array['Barolo','Chianti Classico','Brunello di Montalcino','Amarone della Valpolicella','Soave','Franciacorta Brut','Etna Rosso','Taurasi'])[1 + n % 8] || ' Riserva ' || (n % 997))
      from generate_series(1, 200000) n
      join lateral (select id, name from catalog.producers where natural_key = 'produttore ' || (1 + n % 20000) || chr(31) || 'italia') p on true;
  update catalog.public_projection_settings set enabled = true;
end $$;

set local session_replication_role = origin;
analyze catalog.wines;
analyze catalog.producers;

create temp table misure (caso text, ms numeric, righe integer, livello text) on commit drop;
grant all on misure to authenticated;

create function pg_temp.misura(p_caso text, p_prod text, p_nome text, p_cod text default null) returns void
language plpgsql as $f$
declare t0 timestamptz; n integer; liv text;
begin
  set local role authenticated;
  t0 := clock_timestamp();
  select count(*), min(livello) into n, liv from public.vini_canonici_cerca(p_prod, p_nome, 15, p_cod);
  reset role;
  insert into misure values (p_caso, round(extract(epoch from clock_timestamp() - t0) * 1000, 1), n, liv);
end $f$;

select pg_temp.misura('riscaldamento', 'Produttore 77', 'Barolo');
-- Un vino reale della fixture (produttore e nome come sono nel catalogo), ripetuto per scartare il freddo.
select pg_temp.misura('esatto', p.name, w.name)
  from catalog.wines w join catalog.producers p on p.id = w.producer_id where w.lwin7 = '1001234';
select pg_temp.misura('esatto (2)', p.name, w.name)
  from catalog.wines w join catalog.producers p on p.id = w.producer_id where w.lwin7 = '1150001';
select pg_temp.misura('identificativo', '', '', '1100500');
select pg_temp.misura('identificativo (2)', '', '', '1100501');
select pg_temp.misura('nessun risultato', 'Zzzzzz', 'Qqqqqq');
select pg_temp.misura('refuso', 'Produtore 1234', 'Chianti Clasico Riserva');
select pg_temp.misura('testo (due parole)', 'Produttore 500', 'Brunello');
select pg_temp.misura('termine comune da solo (~25.000 candidati)', '', 'Barolo');
select pg_temp.misura('termine comune da solo, ripetuto', '', 'Riserva');
select pg_temp.misura('input enorme', repeat('barolo ', 800), repeat('riserva ', 800));

select caso, ms, righe, livello from misure order by 1;

-- Piani: gli indici sono usati? (come proprietario, senza il ruolo anon che non legge catalog.*)
explain (costs off)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key like '%monfortino%' limit 2000;
explain (costs off)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key = 'produttore 1234 chianti classico riserva 237';
select set_config('pg_trgm.similarity_threshold', '0.4', true);
explain (costs off)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key operator(extensions.%) 'produtore 1234 chianti clasico riserva' limit 2000;
explain (costs off)
  select w.id from catalog.wines w where w.id in (select x.id from catalog.wines x where x.lwin7 = '1100500'
   union select r.current_wine_id from catalog.entity_aliases a join catalog.wine_resolution r on r.wine_id = a.wine_id
   where a.kind = 'combined_lwin' and a.alias_key = '1100500') and w.status = 'active' and w.origin = 'promotion';

rollback;
