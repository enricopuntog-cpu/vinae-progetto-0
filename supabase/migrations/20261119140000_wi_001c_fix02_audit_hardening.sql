-- WI-001C-FIX-02 — hardening del catalogo canonico dopo la QA indipendente (audit D-6 residuo, produttori fusi, bersagli attivi,
-- alias Combined, TRUNCATE, controllo della superficie SECURITY DEFINER).
--
-- ADDITIVA: le migration 20261119100000 e 20261119120000 sono pubblicate e CONGELATE; questa le corregge senza toccarle.
-- Non popola nulla, non attiva la promozione (interruttore spento, regola in bozza), non fonde, non cancella dati.
-- ATTENZIONE: cambia il testo eseguibile di promote_wine_candidates e della sua impronta (promotion_logic_fingerprint): una regola
-- già approvata con l'impronta precedente non abiliterebbe più nulla (oggi nessuna regola è approvata: bozza).
--
--  B1  detect_duplicate_candidates era una porta SECURITY DEFINER eseguibile dal curatore che SCRIVEVA candidati senza esecutore
--      né evento di audit. Diventa una funzione INTERNA (nessun EXECUTE a nessun ruolo), invocata solo da promote_wine_candidates, che
--      ne registra l'esito (`duplicates`) nell'evento di promozione. La vecchia firma è eliminata. Nessuna fusione automatica.
--  B2  catalog.surface_audit(): controllo DERIVATO DAL CATALOGO DI SISTEMA (pg_proc/ACL) di ogni funzione dello schema, classificata in
--      porta del curatore / lettura del curatore / porta del caricatore / interna, con le regole di ciascuna classe.
--  B3  i produttori già fusi: rilevamento dei candidati e validazione della fusione dei vini usano il produttore EFFETTIVO
--      (producer_final); la provenienza dei produttori originali resta nel dettaglio del candidato; nessun dato storico è riscritto.
--  B4  bersagli attivi per annate/formati/rivendicazioni/collegamenti, alias combined_lwin solo se verificati dal collegamento
--      di fonte, TRUNCATE rifiutato sui registri append-only (anche al proprietario: NON impedisce un DROP TRIGGER del proprietario
--      né l'intervento di un superuser: nessuna garanzia è dichiarata oltre il trigger).

-- ---------------------------------------------------------------------------------------------
-- B3/B1: rilevamento duplicati INTERNO, con produttore effettivo e provenienza
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.detect_duplicate_candidates_internal(p_limit integer, p_actor text)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_p integer;
  v_w integer;
  v_lim integer := least(greatest(coalesce(p_limit, 500), 1), 10000);
begin
  -- produttori con lo stesso nome senza accenti (entrambi attivi)
  with pairs as (
    select a.id as x, b.id as y from catalog.producers a
      join catalog.producers b on b.name_key = a.name_key and a.id < b.id
     where a.status = 'active' and b.status = 'active'
       and not exists (select 1 from catalog.duplicate_candidates d where d.producer_a = a.id and d.producer_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (producer_a, producer_b, reason, detail, detected_by)
    select x, y, 'same_name_key', jsonb_build_object('via', 'promote_wine_candidates'), 'promotion:' || v_actor from pairs
    on conflict do nothing returning 1)
  select count(*) into v_p from ins;
  -- vini con lo stesso nome senza accenti e lo stesso produttore EFFETTIVO: un produttore già fuso conta come quello di destinazione.
  -- L'identità storica non cambia: i produttori originali restano nel dettaglio del candidato.
  with wp as (
    select w.id, w.name_key, w.producer_id,
           case when p.status = 'merged' then catalog.producer_final(p.id) else p.id end as final_producer
      from catalog.wines w join catalog.producers p on p.id = w.producer_id
     where w.status = 'active'),
  pairs as (
    select a.id as x, b.id as y, a.producer_id as pa, b.producer_id as pb
      from wp a join wp b on b.final_producer = a.final_producer and b.name_key = a.name_key and a.id < b.id
     where not exists (select 1 from catalog.duplicate_candidates d where d.wine_a = a.id and d.wine_b = b.id)
     order by a.id, b.id limit v_lim),
  ins as (
    insert into catalog.duplicate_candidates (wine_a, wine_b, reason, detail, detected_by)
    select x, y, 'same_name_key',
           jsonb_build_object('via', 'promote_wine_candidates')
             || case when pa <> pb then jsonb_build_object('via_merged_producer', true, 'producer_a', pa, 'producer_b', pb) else '{}'::jsonb end,
           'promotion:' || v_actor
      from pairs
    on conflict do nothing returning 1)
  select count(*) into v_w from ins;
  return jsonb_build_object('producer_pairs_opened', v_p, 'wine_pairs_opened', v_w);
end;
$$;

-- La vecchia porta (firma senza esecutore, definer, eseguibile dal curatore) lascia il posto alla funzione interna: nessuna firma residua.
drop function catalog.detect_duplicate_candidates(integer);

-- ---------------------------------------------------------------------------------------------
-- B3: fusione di vini — «stesso produttore» = stesso produttore EFFETTIVO (catena delle fusioni)
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.entity_merges_insert_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  c catalog.duplicate_candidates%rowtype;
  v_keep uuid;
  v_drop uuid;
begin
  if new.reverted_at is not null or new.reverted_by is not null then
    raise exception 'catalog: una fusione nasce non annullata' using errcode = '55000';
  end if;
  select * into c from catalog.duplicate_candidates where id = new.candidate_id;
  if not found or c.review_status <> 'same' then
    raise exception 'catalog: una fusione richiede un candidato rivisto "same"' using errcode = '55000';
  end if;
  if exists (select 1 from catalog.entity_merges m where m.candidate_id = new.candidate_id and m.reverted_at is null) then
    raise exception 'catalog: candidato già fuso' using errcode = '55000';
  end if;
  if c.producer_a is not null then
    v_keep := case new.kept_side when 'a' then c.producer_a else c.producer_b end;
    v_drop := case new.kept_side when 'a' then c.producer_b else c.producer_a end;
    if (select status from catalog.producers where id = v_keep) is distinct from 'active'
       or (select status from catalog.producers where id = v_drop) is distinct from 'active' then
      raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
    end if;
  else
    v_keep := case new.kept_side when 'a' then c.wine_a else c.wine_b end;
    v_drop := case new.kept_side when 'a' then c.wine_b else c.wine_a end;
    if (select status from catalog.wines where id = v_keep) is distinct from 'active'
       or (select status from catalog.wines where id = v_drop) is distinct from 'active' then
      raise exception 'catalog: entrambe le entità devono essere attive per la fusione' using errcode = '55000';
    end if;
    -- stesso produttore EFFETTIVO: un produttore già fuso in un altro conta come quello di destinazione (la storia dei vini non si riscrive)
    if catalog.producer_final((select producer_id from catalog.wines where id = v_keep)) is distinct from catalog.producer_final((select producer_id from catalog.wines where id = v_drop)) then
      raise exception 'catalog: due vini di produttori diversi non si fondono (si fondono prima i produttori)' using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- B1: la promozione usa la funzione interna e ne registra l'esito nell'evento
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.promote_wine_candidates(
  p_source_code text default 'LIVEX-LWIN7',
  p_rule_version text default 'lwin-conservative-v1',
  p_limit integer default 500,
  p_dry_run boolean default true,
  p_actor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  c_logic constant text := 'lwin-conservative-v1';
  v_source uuid;
  v_auth text;
  v_actor text;
  v_rule_status text;
  v_rule_fp text;
  v_rule_view text;
  v_enabled boolean;
  v_max integer;
  v_complete uuid;
  v_busy boolean;
  v_producers integer := 0;
  v_wines integer := 0;
  v_aliases integer := 0;
  v_exceptions integer := 0;
  v_dups jsonb;
begin
  select id, authorization_status into v_source, v_auth from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  if p_dry_run is not false then
    return catalog.promotion_preview(p_source_code, p_rule_version) || jsonb_build_object('dry_run', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('catalog.promote:' || v_source::text));
  perform pg_advisory_xact_lock(hashtext('catalog.import:' || v_source::text));  -- stesso lock di begin_import_run
  perform pg_advisory_xact_lock(hashtext('catalog.merge:producer'));  -- serializza con fusioni e ritiri di produttori (nessun vino su un produttore appena ritirato)
  v_actor := catalog.require_actor(p_actor);
  -- D-1: la versione richiesta DEVE essere quella che questa logica realizza; la regola deve essere approvata con l'impronta
  -- (funzioni e vista) della logica attuale. Un'altra regola, anche approvata, non abilita il comportamento v1.
  if p_rule_version is distinct from c_logic then
    raise exception 'catalog: la regola % non corrisponde alla logica implementata (%)', p_rule_version, c_logic using errcode = '42501';
  end if;
  select status, approved_fingerprint, approved_view_digest into v_rule_status, v_rule_fp, v_rule_view
    from catalog.promotion_rules where version = c_logic;
  if v_rule_status is distinct from 'approved' then
    raise exception 'catalog: regola di promozione % non approvata (%)', c_logic, coalesce(v_rule_status, 'inesistente') using errcode = '42501';
  end if;
  if v_rule_fp is distinct from catalog.promotion_logic_fingerprint(c_logic) or v_rule_view is distinct from catalog.promotion_view_digest() then
    raise exception 'catalog: la logica eseguibile è cambiata dopo l''approvazione della regola %: serve una nuova approvazione', c_logic using errcode = '42501';
  end if;
  select enabled, max_batch into v_enabled, v_max from catalog.promotion_settings;
  if v_enabled is not true then
    raise exception 'catalog: promozione disattivata (promotion_settings.enabled = false)' using errcode = '42501';
  end if;
  if v_auth <> 'authorized' then
    raise exception 'catalog: fonte non autorizzata (%)', v_auth using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > v_max then
    raise exception 'catalog: limite del lotto fuori intervallo (1..%)', v_max using errcode = '22023';
  end if;
  select complete_run_id, attempt_in_progress into v_complete, v_busy from catalog.complete_versions where source_id = v_source;
  if v_complete is null then
    raise exception 'catalog: nessuna versione completa della fonte da cui promuovere' using errcode = '55000';
  end if;
  if v_busy then
    raise exception 'catalog: import in corso per la fonte: promozione rifiutata' using errcode = '55P03';
  end if;

  -- D-4: i record con produttore ritirato non entrano nel lotto (non lo occupano) e sono tracciati come eccezioni.
  insert into catalog.promotion_exceptions (source_id, source_record_id, lwin, reason, producer_id, rule_version)
  select v_source, x.source_record_id, x.lwin, 'producer_retired', x.blocked_producer_id, c_logic
    from catalog.promotion_blocked(v_source, 10000) x
  on conflict (source_record_id, reason) do nothing;
  get diagnostics v_exceptions = row_count;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.producers (name, name_key, country_territory_id, natural_key, origin, source_id, source_record_id)
    select distinct on (b.producer_key) b.producer_name, catalog.fold_text(b.producer_name), t.id, b.producer_key,
           'promotion', v_source, b.source_record_id
      from batch b
      left join catalog.territories t on t.source_id = v_source and t.natural_key = 'country' || chr(31) || b.country
     order by b.producer_key, b.lwin
    on conflict (natural_key) do nothing
    returning 1)
  select count(*) into v_producers from ins;

  with batch as (select * from catalog.promotion_batch(v_source, p_limit)),
  ins as (
    insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, sub_type, designation, classification,
                               territory_id, origin, source_id, source_record_id)
    select b.lwin, catalog.producer_final(p.id), b.wine, catalog.fold_text(b.wine), b.colour, b.wine_type, b.sub_type,
           b.designation, b.classification, b.territory_id, 'promotion', v_source, b.source_record_id
      from batch b
      join catalog.producers p on p.natural_key = b.producer_key and p.status <> 'retired'
    on conflict (lwin7) do nothing
    returning 1)
  select count(*) into v_wines from ins;

  with ins as (
    insert into catalog.entity_aliases (wine_id, lang, alias, alias_key, kind, source_id, source_record_id)
    select w.id, null, l.from_external_id, l.from_external_id, 'combined_lwin', v_source, sr.id
      from catalog.record_links l
      join catalog.wines w on w.lwin7 = l.final_external_id and w.status = 'active'
      join catalog.source_records sr on sr.source_id = v_source and sr.external_id = l.from_external_id
     where l.source_id = v_source and l.link_state = 'active'
    on conflict do nothing
    returning 1)
  select count(*) into v_aliases from ins;

  v_dups := catalog.detect_duplicate_candidates_internal(500, v_actor);
  perform catalog.record_canonical_event('promote_wine_candidates', 'source', p_source_code, v_actor,
    jsonb_build_object('rule', c_logic, 'fingerprint', v_rule_fp, 'producers_created', v_producers, 'wines_created', v_wines,
                       'aliases_created', v_aliases, 'exceptions_recorded', v_exceptions, 'duplicates', v_dups, 'limit', p_limit, 'from_run', v_complete));
  return jsonb_build_object('dry_run', false, 'rule_version', c_logic, 'producers_created', v_producers,
                            'wines_created', v_wines, 'combined_aliases_created', v_aliases,
                            'exceptions_recorded', v_exceptions, 'duplicates', v_dups, 'from_run', v_complete);
end;
$$;

-- L'impronta della logica segue la nuova funzione interna (la vecchia firma non esiste più).
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

-- ---------------------------------------------------------------------------------------------
-- B4: bersagli ATTIVI per annate, formati, rivendicazioni e collegamenti (nuove righe)
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.fix02_target_active_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_wine uuid;
  v_status text;
begin
  if tg_table_name = 'wine_vintages' then
    v_wine := new.wine_id;
  elsif tg_table_name = 'wine_formats' then
    select v.wine_id into v_wine from catalog.wine_vintages v where v.id = new.vintage_id;
  elsif tg_table_name = 'wine_links' then
    select v.wine_id into v_wine from catalog.wine_vintages v where v.id = new.vintage_id;
  elsif tg_table_name = 'attribute_claims' then
    if new.producer_id is not null then
      select p.status into v_status from catalog.producers p where p.id = new.producer_id;
      if v_status is distinct from 'active' then
        raise exception 'catalog: una nuova rivendicazione richiede un produttore attivo' using errcode = '55000';
      end if;
      return new;
    elsif new.wine_id is not null then
      v_wine := new.wine_id;
    elsif new.vintage_id is not null then
      select v.wine_id into v_wine from catalog.wine_vintages v where v.id = new.vintage_id;
    else
      select v.wine_id into v_wine from catalog.wine_formats f join catalog.wine_vintages v on v.id = f.vintage_id where f.id = new.format_id;
    end if;
  end if;
  select w.status into v_status from catalog.wines w where w.id = v_wine;
  if v_status is distinct from 'active' then
    raise exception 'catalog: il bersaglio di una nuova riga (%) deve essere un vino attivo (stato: %)', tg_table_name, coalesce(v_status, 'inesistente') using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger zz_fix02_target_active before insert on catalog.wine_vintages for each row execute function catalog.fix02_target_active_guard();
create trigger zz_fix02_target_active before insert on catalog.wine_formats for each row execute function catalog.fix02_target_active_guard();
create trigger zz_fix02_target_active before insert on catalog.attribute_claims for each row execute function catalog.fix02_target_active_guard();
create trigger zz_fix02_target_active before insert on catalog.wine_links for each row execute function catalog.fix02_target_active_guard();

-- ---------------------------------------------------------------------------------------------
-- B4: alias `combined_lwin` solo se VERIFICATI dal collegamento di fonte (record_links attivo, vino = destinazione finale)
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.fix02_combined_alias_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.kind <> 'combined_lwin' then
    return new;
  end if;
  if new.wine_id is null or new.source_id is null or new.source_record_id is null then
    raise exception 'catalog: un alias combined_lwin richiede vino, fonte e record di fonte' using errcode = '23514';
  end if;
  if not exists (
       select 1
         from catalog.record_links l
         join catalog.source_records sr on sr.id = new.source_record_id and sr.source_id = l.source_id and sr.external_id = l.from_external_id
         join catalog.wines w on w.id = new.wine_id and w.lwin7 = l.final_external_id and w.status = 'active'
        where l.source_id = new.source_id and l.link_state = 'active' and l.from_external_id = new.alias) then
    raise exception 'catalog: alias combined_lwin non verificato (nessun collegamento Combined attivo di fonte verso questo vino)' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger zz_fix02_combined_alias before insert on catalog.entity_aliases for each row execute function catalog.fix02_combined_alias_guard();

-- ---------------------------------------------------------------------------------------------
-- B4: TRUNCATE rifiutato sui registri append-only (il curatore e il caricatore non hanno comunque TRUNCATE; le altre tabelle canoniche
-- sono referenziate da FK, che già rifiuta il TRUNCATE senza CASCADE)
-- ---------------------------------------------------------------------------------------------

create trigger canonical_events_no_truncate before truncate on catalog.canonical_events
  for each statement execute function catalog.append_only_guard();
create trigger promotion_exceptions_no_truncate before truncate on catalog.promotion_exceptions
  for each statement execute function catalog.append_only_guard();

-- ---------------------------------------------------------------------------------------------
-- B2: controllo della superficie, DERIVATO DAL CATALOGO DI SISTEMA (nessun elenco fisso di funzioni)
-- ---------------------------------------------------------------------------------------------
-- Classi:
--   curator_door  — eseguibile dal curatore, SECURITY DEFINER, volatile (scrive): richiede search_path vuoto, esecutore obbligatorio
--                   (require_actor) ed evento di audit (record_canonical_event) nel corpo; non eseguibile dal caricatore;
--   curator_read  — eseguibile dal curatore, di sola lettura: né volatile né SECURITY DEFINER;
--   loader_door   — eseguibile dal caricatore: non eseguibile dal curatore;
--   internal      — nessun EXECUTE né al curatore né al caricatore (le chiama il proprietario o altre funzioni definer).
-- In ogni classe: nessun EXECUTE a PUBLIC/anon/authenticated/service_role e search_path vuoto. Eccezioni: elenco ESPLICITO e MOTIVATO
-- nella CTE `waivers` (oggi vuoto); una funzione non classificabile come ok fa fallire la griglia 12zy.
create or replace function catalog.surface_audit()
returns table (fn text, kind text, ok boolean, why text)
language sql stable set search_path = '' as $$
  with f as (
    select p.oid, p.oid::pg_catalog.regprocedure::text as sig, p.prosecdef, p.provolatile, p.prosrc, p.proconfig,
           has_function_privilege('catalog_curator', p.oid, 'EXECUTE') as cur_x,
           has_function_privilege('catalog_loader', p.oid, 'EXECUTE') as ldr_x,
           (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE')
            or has_function_privilege('service_role', p.oid, 'EXECUTE')
            or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0)) as client_x
      from pg_catalog.pg_proc p
     where p.pronamespace = 'catalog'::regnamespace
       and not exists (select 1 from pg_catalog.pg_depend d where d.objid = p.oid and d.deptype = 'e')),
  k as (
    select f.*, case when f.cur_x and f.prosecdef and f.provolatile = 'v' then 'curator_door'
                     when f.cur_x then 'curator_read'
                     when f.ldr_x then 'loader_door'
                     else 'internal' end as kind
      from f),
  waivers(sig, motive) as (select null::text, null::text where false),
  v as (
    select k.sig, k.kind,
           concat_ws('; ',
             case when k.client_x then 'eseguibile da PUBLIC/anon/authenticated/service_role' end,
             case when not exists (select 1 from unnest(coalesce(k.proconfig, '{}'::text[])) c where c in ('search_path=""', 'search_path=')) then 'search_path non vuoto' end,
             case when k.kind = 'curator_door' and k.ldr_x then 'porta del curatore eseguibile anche dal caricatore' end,
             case when k.kind = 'curator_door' and k.prosrc not like '%catalog.require_actor(%' then 'porta senza esecutore obbligatorio (require_actor)' end,
             case when k.kind = 'curator_door' and k.prosrc not like '%catalog.record_canonical_event(%' then 'porta senza evento di audit (record_canonical_event)' end,
             case when k.kind = 'curator_read' and k.provolatile = 'v' then 'funzione volatile eseguibile dal curatore ma non porta SECURITY DEFINER (scriverebbe con i suoi privilegi)' end,
             case when k.kind = 'curator_read' and k.prosecdef then 'lettura SECURITY DEFINER eseguibile dal curatore' end,
             case when k.kind = 'loader_door' and k.cur_x then 'funzione del caricatore eseguibile dal curatore' end) as why
      from k)
  select v.sig, v.kind, (v.why = '' or w.sig is not null),
         case when w.sig is not null and v.why <> '' then 'ECCEZIONE (' || w.motive || '): ' || v.why else v.why end
    from v left join waivers w on w.sig = v.sig
   order by v.sig;
$$;

-- ---------------------------------------------------------------------------------------------
-- Privilegi: le funzioni nuove NON sono eseguibili da nessun ruolo applicativo (le chiama il proprietario o una porta definer)
-- ---------------------------------------------------------------------------------------------

revoke all on function catalog.detect_duplicate_candidates_internal(integer, text) from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
revoke all on function catalog.fix02_target_active_guard() from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
revoke all on function catalog.fix02_combined_alias_guard() from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
revoke all on function catalog.surface_audit() from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

comment on function catalog.detect_duplicate_candidates_internal(integer, text) is
  'WI-001C-FIX-02: rilevamento deterministico INTERNO (nessun EXECUTE ai ruoli applicativi). Chiamata solo da promote_wine_candidates, che ne registra l''esito nell''evento di promozione. Confronta i produttori EFFETTIVI (catena delle fusioni).';
comment on function catalog.surface_audit() is
  'WI-001C-FIX-02: classifica ogni funzione dello schema catalog dal catalogo di sistema e verifica le regole di ogni classe (porte del curatore, letture, porte del caricatore, interne). Solo proprietario.';
