-- WI-008 (griglia wi008a): l'impronta della logica di promozione copre le dipendenze introdotte da WI-007, le guardie
-- dei dati già promossi e la definizione/lo stato dei trigger.
--
-- Metodo: la regola `lwin-conservative-v1` viene approvata DENTRO la transazione (interruttore acceso, fixture assenti);
-- poi ogni dipendenza viene alterata in una sotto-transazione che si annulla da sola, e si verifica che l'impronta cambi
-- e che `promotion_authorized()` diventi falso. Controlli negativi: un commento, un indice o una funzione non coperta
-- NON devono invalidare l'approvazione (altrimenti l'impronta sarebbe rumore e ogni migrazione la romperebbe).
--
-- SOLO stack Supabase locale/effimero. Tutto vive nella transazione chiusa da ROLLBACK: nessun residuo.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi008a: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 then
    raise exception 'Guard wi008a: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
  if (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') <> 'draft' then
    raise exception 'Guard wi008a: la regola non e in bozza, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi008a (id text primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;

create function pg_temp.registra(p_id text, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$
  insert into esiti_wi008a values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, ''));
$f$;

-- Esegue p_sql in una sotto-transazione, misura, poi annulla (eccezione intenzionale P0001).
-- p_atteso_cambio = true: l'impronta DEVE cambiare e la promozione DEVE risultare non autorizzata.
-- p_atteso_cambio = false: l'impronta DEVE restare uguale e la promozione DEVE restare autorizzata.
create function pg_temp.muta(p_id text, p_desc text, p_sql text, p_atteso_cambio boolean)
returns void language plpgsql as $f$
declare
  v_fp0 text := catalog.promotion_logic_fingerprint('lwin-conservative-v1');
  v_fp1 text;
  v_aut boolean;
  v_ok boolean;
  v_err text := '';
begin
  begin
    execute p_sql;
    v_fp1 := catalog.promotion_logic_fingerprint('lwin-conservative-v1');
    v_aut := catalog.promotion_authorized();
    if p_atteso_cambio then
      v_ok := v_fp1 is distinct from v_fp0 and not v_aut;
    else
      v_ok := v_fp1 = v_fp0 and v_aut;
    end if;
    raise exception 'annulla la prova' using errcode = 'P0001';
  exception
    when sqlstate 'P0001' then null;
    when others then v_ok := false; v_err := sqlstate || ' ' || sqlerrm;
  end;
  insert into esiti_wi008a values (p_id, p_desc, coalesce(v_ok, false), v_err);
end;
$f$;

-- ---------------------------------------------------------------------------------------------
-- Approvazione (dentro la transazione) e controllo di base
-- ---------------------------------------------------------------------------------------------
update catalog.promotion_settings set enabled = true, max_batch = 10;
update catalog.promotion_rules set status = 'approved', approved_by = 'founder-test', approved_at = now()
  where version = 'lwin-conservative-v1';

do $$
declare
  v_rule catalog.promotion_rules%rowtype;
  v_fp text := catalog.promotion_logic_fingerprint('lwin-conservative-v1');
begin
  select * into v_rule from catalog.promotion_rules where version = 'lwin-conservative-v1';
  perform pg_temp.registra('A01', 'l''impronta è un md5 e la regola approvata la registra',
    v_fp ~ '^[0-9a-f]{32}$' and v_rule.approved_fingerprint = v_fp);
  perform pg_temp.registra('A02', 'con la regola approvata e l''interruttore acceso la promozione è autorizzata',
    catalog.promotion_authorized());
  perform pg_temp.registra('A03', 'una versione sconosciuta non ha impronta',
    catalog.promotion_logic_fingerprint('lwin-sconosciuta') is null);
  perform pg_temp.registra('A04', 'le nove dipendenze aggiunte da WI-008 esistono tutte (l''impronta nasce solo se esistono tutte le 25)',
    (select count(*) from unnest(array[
      'catalog.wines_search_key()', 'public.vini_normalizza(text)', 'catalog.wines_guard()', 'catalog.producers_guard()',
      'catalog.claims_guard()', 'catalog.aliases_guard()', 'catalog.entity_merges_guard()', 'catalog.wine_links_guard()',
      'catalog.wine_links_insert_guard()']) s where to_regprocedure(s) is not null) = 9);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Controlli negativi: queste modifiche NON devono invalidare l'approvazione
-- ---------------------------------------------------------------------------------------------
select pg_temp.muta('N01', 'nessuna modifica: impronta uguale e promozione ancora autorizzata', 'select 1', false);
select pg_temp.muta('N02', 'un commento su una funzione coperta non cambia l''impronta',
  $$comment on function catalog.wines_search_key() is 'commento di prova'$$, false);
select pg_temp.muta('N03', 'un indice aggiuntivo su catalog.wines non cambia l''impronta',
  $$create index wi008a_tmp_idx on catalog.wines (lwin7)$$, false);
select pg_temp.muta('N04', 'una funzione fuori dall''elenco (anteprima di sola lettura) non cambia l''impronta',
  $$create or replace function catalog.promotion_preview(p_source_code text default 'LIVEX-LWIN7', p_rule_version text default 'lwin-conservative-v1')
    returns jsonb language sql stable set search_path = '' as 'select ''{}''::jsonb'$$, false);

-- ---------------------------------------------------------------------------------------------
-- Dipendenze di WI-007: chiave di ricerca e normalizzatore
-- ---------------------------------------------------------------------------------------------
select pg_temp.muta('B01', 'cambiare il corpo di wines_search_key() invalida l''approvazione',
  $$create or replace function catalog.wines_search_key() returns trigger language plpgsql set search_path = ''
    as 'begin new.search_key := public.vini_normalizza(new.name); return new; end'$$, true);
select pg_temp.muta('B02', 'cambiare il corpo di vini_normalizza() invalida l''approvazione',
  $$create or replace function public.vini_normalizza(p_testo text) returns text language sql immutable parallel safe
    set search_path = '' as 'select lower(coalesce(p_testo, ''''))'$$, true);
select pg_temp.muta('B03', 'cambiare la volatilità di vini_normalizza() invalida l''approvazione',
  $$alter function public.vini_normalizza(text) volatile$$, true);

-- ---------------------------------------------------------------------------------------------
-- Guardie dei dati già promossi: ciascuna sostituita da una versione che lascia passare tutto
-- ---------------------------------------------------------------------------------------------
select pg_temp.muta('C0' || n, 'cambiare il corpo di ' || g || '() invalida l''approvazione',
  format($q$create or replace function catalog.%I() returns trigger language plpgsql set search_path = ''
            as 'begin return new; end'$q$, g), true)
  from (values (1, 'wines_guard'), (2, 'producers_guard'), (3, 'claims_guard'), (4, 'aliases_guard'),
               (5, 'entity_merges_guard'), (6, 'wine_links_guard'), (7, 'wine_links_insert_guard')) t(n, g);

-- ---------------------------------------------------------------------------------------------
-- Trigger: definizione e stato
-- ---------------------------------------------------------------------------------------------
select pg_temp.muta('D01', 'disattivare il trigger wines_a_search_key invalida l''approvazione',
  $$alter table catalog.wines disable trigger wines_a_search_key$$, true);
select pg_temp.muta('D02', 'disattivare la guardia di aggiornamento dei vini invalida l''approvazione',
  $$alter table catalog.wines disable trigger wines_guard$$, true);
select pg_temp.muta('D03', 'disattivare la guardia dei produttori invalida l''approvazione',
  $$alter table catalog.producers disable trigger producers_guard$$, true);
select pg_temp.muta('D04', 'ricreare wines_a_search_key AFTER invece di BEFORE (stessa funzione) invalida l''approvazione',
  $$drop trigger wines_a_search_key on catalog.wines;
    create trigger wines_a_search_key after insert on catalog.wines for each row execute function catalog.wines_search_key()$$, true);
select pg_temp.muta('D05', 'rinominare il trigger (cambia l''ordine di esecuzione) invalida l''approvazione',
  $$alter trigger wines_a_search_key on catalog.wines rename to wines_z_search_key$$, true);
select pg_temp.muta('D06', 'aggiungere un trigger a catalog.wines invalida l''approvazione',
  $$create trigger wi008a_extra before insert on catalog.wines for each row execute function catalog.wines_search_key()$$, true);
select pg_temp.muta('D07', 'rimuovere la guardia dei collegamenti invalida l''approvazione',
  $$drop trigger wine_links_insert_guard on catalog.wine_links$$, true);

-- ---------------------------------------------------------------------------------------------
-- Effetto sulla promozione: con la dipendenza alterata, la promozione reale è rifiutata
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_ok boolean := false;
  v_msg text := '';
begin
  begin
    create or replace function catalog.wines_search_key() returns trigger language plpgsql set search_path = ''
      as 'begin new.search_key := public.vini_normalizza(new.name); return new; end';
    set local role catalog_curator;
    begin
      perform catalog.promote_wine_candidates(p_dry_run => false, p_actor => 'qa-wi008a', p_limit => 1);
      v_ok := false;
    exception when insufficient_privilege then
      v_ok := true; v_msg := sqlerrm;
    end;
    reset role;
    raise exception 'annulla la prova' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null;
  end;
  perform pg_temp.registra('E01', 'la promozione reale rifiuta la chiave di ricerca cambiata dopo l''approvazione',
    v_ok and v_msg like '%cambiata dopo l''approvazione%', v_msg);
end $$;

-- Dopo tutte le prove annullate l'approvazione originale è ancora valida.
do $$
begin
  perform pg_temp.registra('Z01', 'dopo le sotto-transazioni annullate l''impronta è quella approvata e la promozione è autorizzata',
    catalog.promotion_authorized()
    and (select approved_fingerprint from catalog.promotion_rules where version = 'lwin-conservative-v1')
        = catalog.promotion_logic_fingerprint('lwin-conservative-v1'));
end $$;

select id, descrizione, passed, detail from esiti_wi008a order by id;

do $$
begin
  if exists (select 1 from esiti_wi008a where not passed) then
    raise exception 'wi008a: casi rossi: %', (select string_agg(id || ' ' || left(detail, 200), ' | ') from esiti_wi008a where not passed);
  end if;
end $$;

rollback;
