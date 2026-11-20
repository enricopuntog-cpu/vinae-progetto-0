-- WI-001C-FIX-02 (2) — l'impronta della logica di promozione copre anche le guardie che cambiano l'esito di un INSERT della promozione
-- o la validazione delle fusioni (alias Combined verificati, bersagli attivi, guardia delle fusioni). ADDITIVA: la migration 20261119140000 è
-- già pubblicata e congelata. Cambia l'impronta: oggi nessuna regola è approvata (bozza), quindi nessuna approvazione si invalida.

create or replace function catalog.promotion_logic_fingerprint(p_version text)
returns text language sql stable set search_path = '' as $$
  with sigs(s) as (
    select unnest(array[
      'catalog.promote_wine_candidates(text,text,integer,boolean,text)',
      'catalog.promotion_candidates(uuid)',
      'catalog.promotion_batch(uuid,integer)',
      'catalog.promotion_blocked(uuid,integer)',
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
      'catalog.record_canonical_event(text,text,text,text,jsonb)'])),
  f as (select s, to_regprocedure(s) as fn from sigs)
  select case when p_version = 'lwin-conservative-v1' and (select count(*) = count(fn) from f) then
    md5((select string_agg(f.s || chr(29) || p.prosecdef::text || chr(29) || coalesce(p.proconfig::text, '') || chr(29) || p.prosrc,
                           chr(30) order by f.s)
           from f join pg_catalog.pg_proc p on p.oid = f.fn)) end;
$$;
