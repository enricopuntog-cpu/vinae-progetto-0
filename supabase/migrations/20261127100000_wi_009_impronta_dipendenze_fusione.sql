-- WI-009 (audit indipendente WI-008, finding F-07): l'impronta della logica di promozione copre anche le dipendenze
-- dello stato di fusione e le guardie delle coppie «possibile duplicato».
--
--   * `catalog.merge_state_check` (chiamata da `wines_guard` e `producers_guard`, già coperte) e le due funzioni che
--     decidono se la transizione è ammessa, `merge_authorized` e `revert_authorized`;
--   * `duplicate_candidates_guard` e `duplicate_candidates_insert_guard`: ogni lotto scrive in quella tabella;
--   * definizione e stato dei trigger di `catalog.duplicate_candidates`.
--
-- Nessun cambiamento di comportamento: cambia SOLO che cosa invalida un'approvazione. Il corpo qui sotto è quello
-- della 20261125130000 con cinque firme e una tabella in più (28 -> 33 funzioni, 8 -> 9 tabelle). La regola
-- `lwin-conservative-v1` resta `draft`; il valore dell'impronta cambia: quello precedente (b87e7b51…) non va più
-- sottoposto all'approvazione. Additiva; le migration distribuite non sono modificate.

create or replace function catalog.promotion_logic_fingerprint(p_version text)
returns text
language sql
stable
set search_path = ''
as $$
  with sigs(s) as (
    select unnest(array[
      'catalog.promote_wine_candidates(text,text,integer,boolean,text)',
      'catalog.promotion_candidates(uuid)',
      'catalog.promotion_batch(uuid,integer)',
      'catalog.promotion_blocked(uuid,integer)',
      -- WI-008: una sola definizione di candidato
      'catalog.promotion_report(uuid)',
      'catalog.promotion_lot(uuid,integer,integer)',
      'catalog.promotion_retired_producers()',
      'catalog.producer_final(uuid)',
      'catalog.canonical_insert_guard()',
      'catalog.detect_duplicate_candidates_internal(integer,text)',
      'catalog.fix02_combined_alias_guard()',
      'catalog.fix02_target_active_guard()',
      'catalog.entity_merges_insert_guard()',
      'catalog.fold_text(text)',
      'catalog.promotion_authorized()',
      'catalog.promotion_logic_fingerprint(text)',
      'catalog.promotion_view_digest()',
      'catalog.require_actor(text)',
      'catalog.record_canonical_event(text,text,text,text,jsonb)',
      -- WI-008: dipendenze di WI-007 e guardie dei dati già promossi
      'catalog.wines_search_key()',
      'public.vini_normalizza(text)',
      'catalog.wines_guard()',
      'catalog.producers_guard()',
      'catalog.claims_guard()',
      'catalog.aliases_guard()',
      'catalog.entity_merges_guard()',
      'catalog.wine_links_guard()',
      'catalog.wine_links_insert_guard()',
      -- WI-009: stato di fusione e guardie delle coppie «possibile duplicato»
      'catalog.merge_state_check(text,uuid,text,uuid,bigint,text,uuid,bigint)',
      'catalog.merge_authorized(text,uuid,uuid,bigint)',
      'catalog.revert_authorized(text,uuid,uuid,bigint)',
      'catalog.duplicate_candidates_guard()',
      'catalog.duplicate_candidates_insert_guard()'])),
  f as (select s, to_regprocedure(s) as fn from sigs),
  trg as (
    select t.tgrelid::regclass::text || chr(29) || t.tgname || chr(29) || t.tgenabled::text || chr(29)
           || pg_catalog.pg_get_triggerdef(t.oid, true) as d
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_class c on c.oid = t.tgrelid
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where not t.tgisinternal
       and n.nspname = 'catalog'
       and c.relname in ('wines', 'producers', 'wine_links', 'entity_aliases', 'entity_merges', 'attribute_claims',
                         'wine_vintages', 'wine_formats', 'duplicate_candidates'))
  select case when p_version = 'lwin-conservative-v1' and (select count(*) = count(fn) from f) then
    md5(
      (select string_agg(f.s || chr(29) || p.prosecdef::text || chr(29) || p.provolatile::text || chr(29)
                         || coalesce(p.proconfig::text, '') || chr(29) || p.prosrc,
                         chr(30) order by f.s)
         from f join pg_catalog.pg_proc p on p.oid = f.fn)
      || chr(28) ||
      coalesce((select string_agg(d, chr(30) order by d) from trg), ''))
  end;
$$;

comment on function catalog.promotion_logic_fingerprint(text) is
  'WI-009. Impronta della logica eseguibile che la regola di promozione approva: corpo, SECURITY DEFINER, volatilità e '
  'configurazione di 33 funzioni (promozione, guardie, chiave di ricerca, stato di fusione) e definizione/stato dei '
  'trigger sulle tabelle canoniche e sulle coppie «possibile duplicato». Null se manca una funzione o la versione è sconosciuta.';

-- La regola non deve risultare approvata: un'approvazione precedente con l'impronta vecchia non esiste e, se esistesse,
-- questa migration la renderebbe inutilizzabile senza dirlo. Meglio fermarsi.
do $guardia$
begin
  if (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') is distinct from 'draft' then
    raise exception 'WI-009: la regola non è in bozza: l''impronta non va cambiata sotto un''approvazione';
  end if;
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-009: una dipendenza elencata non esiste';
  end if;
end $guardia$;
