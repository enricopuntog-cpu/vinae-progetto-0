-- WI-008 — impronta della logica di promozione: dipendenze introdotte da WI-007 e stato dei trigger.
--
-- Additiva: nessuna migration distribuita viene toccata. Sostituisce SOLO il corpo di
-- `catalog.promotion_logic_fingerprint(text)` (stessa firma, stessi privilegi, stesso comportamento di
-- `promotion_rules_guard` e `promotion_authorized`). La regola `lwin-conservative-v1` è ancora in BOZZA, quindi
-- nessuna approvazione già registrata viene invalidata; una regola approvata dopo questa migration registra
-- l'impronta nuova.
--
-- Lacuna chiusa. L'impronta v1 copriva 16 funzioni (per corpo, SECURITY DEFINER e `search_path`) ma NON:
--   * `catalog.wines_search_key()` e `public.vini_normalizza(text)` (WI-007): determinano `catalog.wines.search_key`,
--     cioè ciò che la ricerca canonica confronta; cambiarle dopo l'approvazione produrrebbe chiavi diverse da
--     quelle dei vini già promossi senza invalidare nulla;
--   * le guardie di aggiornamento/collegamento (`wines_guard`, `producers_guard`, `claims_guard`, `aliases_guard`,
--     `entity_merges_guard`, `wine_links_guard`, `wine_links_insert_guard`): fanno rispettare l'immutabilità
--     dell'identità e l'integrità dei dati già promossi;
--   * la DEFINIZIONE e lo STATO dei trigger sulle tabelle canoniche: una guardia ancora esistente ma disattivata,
--     spostata (BEFORE/AFTER, ordine dei nomi) o ricollegata non cambiava nessun corpo di funzione, quindi
--     nemmeno l'impronta.
-- L'impronta nuova include inoltre la volatilità delle funzioni (`vini_normalizza` è IMMUTABLE e alimenta gli indici).
--
-- Non include `promotion_preview` / `promotion_simulation` (sola lettura, nessun effetto sull'identità o sui dati).

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
      'catalog.wine_links_insert_guard()'])),
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
                         'wine_vintages', 'wine_formats'))
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
  'WI-008. Impronta della logica eseguibile che la regola di promozione approva: corpo, SECURITY DEFINER, volatilità e '
  'configurazione di 25 funzioni (promozione, guardie, chiave di ricerca) e definizione/stato dei trigger sulle tabelle '
  'canoniche. Null se manca una funzione o la versione è sconosciuta.';
