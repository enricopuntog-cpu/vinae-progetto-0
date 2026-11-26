-- Banco della promozione: `public.vini_canonici_cerca` sul catalogo sintetico PROMOSSO dalla procedura (non inserito
-- a mano come in wi007): stessi dati, alias Combined, omonimi e chiavi di ricerca prodotti dai trigger veri.
-- La proiezione si accende dentro la transazione e il ROLLBACK la rispegne. SOLO stack effimero.
\set ON_ERROR_STOP on
begin;
update catalog.public_projection_settings set enabled = true;

create temp table misure (n serial, caso text, ms numeric, righe integer, livello text) on commit drop;
grant all on misure to authenticated;
grant usage on sequence misure_n_seq to authenticated;

-- Tre esecuzioni, si riporta la mediana. Ruolo authenticated senza identità: nessun contatore consumato.
create function pg_temp.misura(p_caso text, p_prod text, p_nome text, p_cod text default null) returns void
language plpgsql as $f$
declare t0 timestamptz; t numeric[] := '{}'; n integer; liv text; i integer;
begin
  set local role authenticated;
  for i in 1..3 loop
    t0 := clock_timestamp();
    select count(*), string_agg(distinct livello, ',') into n, liv from public.vini_canonici_cerca(p_prod, p_nome, 15, p_cod);
    t := t || (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
  end loop;
  reset role;
  insert into misure (caso, ms, righe, livello)
    values (p_caso, (select round(x, 1) from unnest(t) x order by x offset 1 limit 1), n, liv);
end $f$;

create temp table campioni on commit drop as
select
  (select jsonb_build_object('p', p.name, 'w', w.name, 'c', w.lwin7) from catalog.wines w join catalog.producers p on p.id = w.producer_id
    where w.name like 'Vino %' order by w.lwin7 offset 90000 limit 1) as vino,
  (select jsonb_build_object('p', p.name, 'w', w.name) from catalog.wines w join catalog.producers p on p.id = w.producer_id
    where w.name = 'Omonimo 1' limit 1) as omonimo,
  (select a.alias_key from catalog.entity_aliases a where a.kind = 'combined_lwin' order by a.alias_key offset 2000 limit 1) as alias;

select pg_temp.misura('riscaldamento', 'Produttore 77', 'Vino 77');
select pg_temp.misura('identificativo LWIN-7', '', '', vino ->> 'c') from campioni;
select pg_temp.misura('identificativo: LWIN di un record Combined', '', '', alias) from campioni;
select pg_temp.misura('identificativo: LWIN inesistente', '', '', '9999999') from campioni;
select pg_temp.misura('esatto produttore e nome', vino ->> 'p', vino ->> 'w') from campioni;
select pg_temp.misura('omonimi (stesso produttore e nome)', omonimo ->> 'p', omonimo ->> 'w') from campioni;
select pg_temp.misura('prefisso', vino ->> 'p', left(vino ->> 'w', 8)) from campioni;
select pg_temp.misura('testo (parole sparse)', '', (vino ->> 'w') || ' ' || (vino ->> 'p')) from campioni;
select pg_temp.misura('refuso', replace(vino ->> 'p', 'Produttore', 'Produtore'), vino ->> 'w') from campioni;
select pg_temp.misura('nessun risultato', 'Zzzzzz', 'Qqqqqq');
select pg_temp.misura('solo produttore', 'Produttore 500', '');
select pg_temp.misura('termine comune a quasi tutto il catalogo', '', 'Produttore');
select pg_temp.misura('input enorme', repeat('produttore ', 800), repeat('vino ', 800));

select caso, ms as mediana_ms, righe, livello from misure order by n;

\echo 'Piani (sottoquery dei livelli, come proprietario)'
explain (analyze, costs off, timing off, summary on)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key = (select public.vini_normalizza((vino ->> 'p') || ' ' || (vino ->> 'w')) from campioni) order by w.search_key, w.lwin7, w.id limit 15;
explain (analyze, costs off, timing off, summary on)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key like '%vino 90123%' order by w.search_key, w.lwin7, w.id limit 15;
select set_config('pg_trgm.similarity_threshold', '0.4', true);
explain (analyze, costs off, timing off, summary on)
  select w.id from catalog.wines w where w.status = 'active' and w.origin = 'promotion'
   and w.search_key operator(extensions.%) 'produtore 500 vino 90123' order by w.search_key, w.lwin7, w.id limit 15;
rollback;
