-- WI-008 — simulazione, anteprima e lotto di promozione valutano il rapporto dei candidati UNA SOLA VOLTA.
--
-- Misurato in Production (sola lettura, 212.894 record): `catalog.source_records` pesa 639 MB e ogni valutazione di
-- `catalog.wine_candidate_report` la rilegge per intero (decine di secondi). Chiamate ridondanti trovate:
--   * `promotion_simulation`  ~10 valutazioni → timeout (57014);
--   * `promotion_preview` (cioè la prova a secco di `promote_wine_candidates`)  3 valutazioni;
--   * `promote_wine_candidates` reale, per OGNI lotto: `promotion_blocked` + `promotion_batch` (produttori) +
--     `promotion_batch` (vini) = 3 valutazioni, più il join di ritorno su `source_records` per l'id del record;
--     con il limite di 2 minuti per istruzione un lotto non era sostenibile.
--
-- Correzione, senza tabelle né copie persistenti (nessuna seconda fonte di verità):
--   1. la vista espone in coda `source_record_id` (niente join di ritorno);
--   2. `promotion_report(fonte)` è l'UNICA definizione di candidato (idoneità, chiave del produttore, produttore
--      ritirato, già promosso); `promotion_candidates`, `promotion_lot`, anteprima e simulazione derivano da lì;
--   3. `promotion_lot` restituisce lotto e bloccati da una sola valutazione; `promotion_batch` e `promotion_blocked`
--      ne diventano filtri (stesse firme, stessi privilegi);
--   4. `promotion_analysis` calcola riepilogo e sezioni della simulazione da un solo CTE materializzato;
--   5. il lotto reale legge `promotion_lot` una volta e lavora sul risultato (al più 20.000 righe in memoria).
--
-- Invariati: firme pubbliche, lock, ordine delle operazioni, idempotenza, regola conservativa, esclusioni, alias,
-- audit, volatilità (`promotion_simulation` resta STABLE: PostgreSQL le rifiuta qualunque scrittura).
-- La vista e le funzioni cambiano: la regola `lwin-conservative-v1` è in BOZZA, nessuna approvazione si perde.

-- ---------------------------------------------------------------------------------------------
-- 1. Vista: stesse colonne, nello stesso ordine, più `source_record_id` in coda
-- ---------------------------------------------------------------------------------------------
create or replace view catalog.wine_candidate_report with (security_invoker = on) as
with base as (
  select r.source_id, r.external_id as lwin, r.territory_id, r.country, r.region, r.sub_region,
         r.payload ->> 'producer_name' as producer_name, r.payload ->> 'wine' as wine,
         r.payload ->> 'colour' as colour, r.payload ->> 'type' as wine_type, r.payload ->> 'sub_type' as sub_type,
         r.payload ->> 'designation' as designation, r.payload ->> 'classification' as classification,
         -- posizionale: un campo vuoto resta al suo posto (concat_ws li farebbe scivolare)
         coalesce(catalog.fold_text(r.payload ->> 'producer_name'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'wine'), '') || chr(31)
         || coalesce(catalog.fold_text(r.country), '') || chr(31) || coalesce(catalog.fold_text(r.region), '') || chr(31)
         || coalesce(catalog.fold_text(r.sub_region), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'site'), '') || chr(31)
         || coalesce(catalog.fold_text(r.payload ->> 'colour'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'sub_type'), '') || chr(31)
         || coalesce(catalog.fold_text(r.payload ->> 'designation'), '') || chr(31) || coalesce(catalog.fold_text(r.payload ->> 'classification'), '') as natural_key,
         r.id as source_record_id
    from catalog.source_records r
   where r.scope = 'wine' and r.status = 'Live' and r.removed_from_source_at is null
),
grp as (select b.*, count(*) over (partition by b.source_id, b.natural_key) as natural_group_size from base b)
select g.source_id, g.lwin, g.producer_name, g.wine, g.colour, g.wine_type, g.sub_type, g.designation, g.classification,
       g.country, g.region, g.sub_region, g.territory_id, g.natural_group_size,
       array_remove(array[
         case when g.producer_name is null then 'producer_name' end,
         case when g.wine is null then 'wine' end,
         case when g.country is null then 'country' end,
         case when g.region is null then 'region' end,
         case when g.colour is null then 'colour' end], null) as missing_fields,
       array_remove(array[
         case when g.producer_name is null then 'missing_producer' end,
         case when g.wine is null then 'missing_wine_name' end,
         case when g.country is null then 'missing_country' end,
         case when g.natural_group_size > 1 then 'possible_duplicate' end], null) as review_reasons,
       case when g.producer_name is null or g.wine is null or g.country is null or g.natural_group_size > 1
            then 'needs_review' else 'fields_complete' end as readiness,
       g.source_record_id
  from grp g;

-- ---------------------------------------------------------------------------------------------
-- 2. Una sola definizione di candidato
-- ---------------------------------------------------------------------------------------------

-- Produttori che bloccano la promozione: la chiave naturale esiste ma il produttore EFFETTIVO non è attivo.
-- Il prefiltro sullo stato è esatto: `merged_into` è valorizzato solo con status 'merged' (vincolo di tabella).
create or replace function catalog.promotion_retired_producers()
returns table (natural_key text, producer_id uuid)
language sql stable set search_path = '' as $$
  select p.natural_key, p.id
    from catalog.producers p
   where p.status <> 'active' and p.natural_key is not null
     and (select f.status from catalog.producers f where f.id = catalog.producer_final(p.id)) is distinct from 'active';
$$;

-- Il rapporto di una fonte, valutato una volta, con i fatti da cui dipende la promozione.
create or replace function catalog.promotion_report(p_source_id uuid)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, region text, sub_region text,
               natural_group_size bigint, review_reasons text[], readiness text,
               lwin_ok boolean, promoted boolean, candidate boolean, producer_key text, blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  select c.source_record_id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation, c.classification,
         c.territory_id, c.country, c.region, c.sub_region, c.natural_group_size, c.review_reasons, c.readiness,
         f.lwin_ok, f.promoted,
         (c.readiness = 'fields_complete' and f.lwin_ok and not f.promoted
          and k.producer_fold is not null and catalog.fold_text(c.wine) is not null) as candidate,
         k.producer_fold || chr(31) || coalesce(catalog.fold_text(c.country), '') as producer_key,
         x.producer_id
    from catalog.wine_candidate_report c
    cross join lateral (select c.lwin ~ '^[0-9]{7}$' as lwin_ok,
                               exists (select 1 from catalog.wines w where w.lwin7 = c.lwin) as promoted) f
    cross join lateral (select catalog.fold_text(c.producer_name) as producer_fold) k
    left join catalog.promotion_retired_producers() x
      on x.natural_key = k.producer_fold || chr(31) || coalesce(catalog.fold_text(c.country), '')
   where c.source_id = p_source_id;
$$;

-- Stessa firma di prima.
create or replace function catalog.promotion_candidates(p_source_id uuid)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text, blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  select r.source_record_id, r.lwin, r.producer_name, r.wine, r.colour, r.wine_type, r.sub_type, r.designation, r.classification,
         r.territory_id, r.country, r.producer_key, r.blocked_producer_id
    from catalog.promotion_report(p_source_id) r
   where r.candidate;
$$;

-- Lotto e bloccati non ancora tracciati, da UNA sola valutazione. Un limite 0 esclude la rispettiva parte.
create or replace function catalog.promotion_lot(p_source_id uuid, p_batch_limit integer, p_blocked_limit integer)
returns table (kind text, source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text,
               sub_type text, designation text, classification text, territory_id bigint, country text, producer_key text,
               blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  with cand as materialized (select * from catalog.promotion_candidates(p_source_id))
  (select 'batch', c.source_record_id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation,
          c.classification, c.territory_id, c.country, c.producer_key, c.blocked_producer_id
     from cand c
    where c.blocked_producer_id is null
    order by c.lwin
    limit least(greatest(coalesce(p_batch_limit, 0), 0), 10000))
  union all
  (select 'blocked', c.source_record_id, c.lwin, c.producer_name, c.wine, c.colour, c.wine_type, c.sub_type, c.designation,
          c.classification, c.territory_id, c.country, c.producer_key, c.blocked_producer_id
     from cand c
    where c.blocked_producer_id is not null
      and not exists (select 1 from catalog.promotion_exceptions e
                       where e.source_record_id = c.source_record_id and e.reason = 'producer_retired')
    order by c.lwin
    limit least(greatest(coalesce(p_blocked_limit, 0), 0), 10000));
$$;

create or replace function catalog.promotion_batch(p_source_id uuid, p_limit integer)
returns table (source_record_id bigint, lwin text, producer_name text, wine text, colour text, wine_type text, sub_type text,
               designation text, classification text, territory_id bigint, country text, producer_key text)
language sql stable set search_path = '' as $$
  select l.source_record_id, l.lwin, l.producer_name, l.wine, l.colour, l.wine_type, l.sub_type, l.designation, l.classification,
         l.territory_id, l.country, l.producer_key
    from catalog.promotion_lot(p_source_id, greatest(coalesce(p_limit, 1), 1), 0) l
   order by l.lwin;
$$;

create or replace function catalog.promotion_blocked(p_source_id uuid, p_limit integer)
returns table (source_record_id bigint, lwin text, blocked_producer_id uuid)
language sql stable set search_path = '' as $$
  select l.source_record_id, l.lwin, l.blocked_producer_id
    from catalog.promotion_lot(p_source_id, 0, greatest(coalesce(p_limit, 1), 1)) l
   order by l.lwin;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3. Riepilogo e sezioni della simulazione da un solo CTE materializzato
-- ---------------------------------------------------------------------------------------------
create or replace function catalog.promotion_analysis(p_source_id uuid, p_sample integer)
returns jsonb language sql stable set search_path = '' as $$
  with rep as materialized (
    select r.*, (p.natural_key is not null) as producer_exists
      from catalog.promotion_report(p_source_id) r
      left join catalog.producers p on p.natural_key = r.producer_key),
  tot as (
    select count(*) as live,
           count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted) as complete_open,
           count(*) filter (where promoted) as already_promoted,
           count(*) filter (where 'missing_producer' = any (review_reasons)) as missing_producer,
           count(*) filter (where 'missing_wine_name' = any (review_reasons)) as missing_wine_name,
           count(*) filter (where 'missing_country' = any (review_reasons)) as missing_country,
           count(*) filter (where 'possible_duplicate' = any (review_reasons)) as possible_duplicate,
           count(*) filter (where not lwin_ok) as invalid_lwin7,
           count(*) filter (where candidate and blocked_producer_id is not null) as producer_retired,
           count(distinct producer_key) filter (where readiness = 'fields_complete' and lwin_ok and not promoted
                                                  and not producer_exists) as producers_to_create,
           count(*) filter (where natural_group_size > 1) as duplicate_records,
           count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted and territory_id is null) as without_territory,
           count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted and region is null) as without_region,
           count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted and colour is null) as without_colour,
           count(*) filter (where readiness = 'fields_complete' and lwin_ok and not promoted and wine_type is null) as without_wine_type
      from rep)
  select jsonb_build_object(
    'preview', jsonb_build_object(
      'live_wine_records', t.live,
      'eligible', t.complete_open - t.producer_retired,
      'already_promoted', t.already_promoted,
      'blocked_missing_producer', t.missing_producer,
      'blocked_missing_wine_name', t.missing_wine_name,
      'blocked_missing_country', t.missing_country,
      'blocked_possible_duplicate', t.possible_duplicate,
      'blocked_invalid_lwin7', t.invalid_lwin7,
      'blocked_producer_retired', t.producer_retired,
      'producers_to_create_upper_bound', t.producers_to_create),
    'candidates', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'lwin', b.lwin, 'producer', b.producer_name, 'wine', b.wine, 'country', b.country,
               'colour', b.colour, 'wine_type', b.wine_type, 'territory_id', b.territory_id,
               'producer_exists', b.producer_exists, 'source_record_id', b.source_record_id) order by b.lwin), '[]'::jsonb)
        from (select * from rep where candidate and blocked_producer_id is null order by lwin
               limit greatest(coalesce(p_sample, 0), 0)) b),
    'excluded_by_reason', (
      select coalesce(jsonb_object_agg(m.reason, m.n), '{}'::jsonb)
        from (select u.reason, count(*) as n
                from (select unnest(review_reasons) as reason from rep where readiness = 'needs_review'
                      union all select 'invalid_lwin7' from rep where not lwin_ok
                      union all select 'already_promoted' from rep where promoted) u
               group by u.reason) m),
    'excluded_sample', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'lwin', e.lwin, 'producer', e.producer_name, 'wine', e.wine, 'country', e.country, 'reasons', e.reasons)
               order by e.lwin), '[]'::jsonb)
        from (select lwin, producer_name, wine, country,
                     review_reasons || case when not lwin_ok then array['invalid_lwin7'] else array[]::text[] end as reasons
                from rep
               where readiness = 'needs_review' or not lwin_ok
               order by lwin
               limit greatest(coalesce(p_sample, 0), 0)) e),
    'possible_duplicate_records', t.duplicate_records,
    'possible_duplicate_groups', (
      select coalesce(jsonb_agg(x.g order by (x.g ->> 'records')::int desc, x.g ->> 'producer', x.g ->> 'wine'), '[]'::jsonb)
        from (select jsonb_build_object('producer', min(c.producer_name), 'wine', min(c.wine), 'country', min(c.country),
                       'records', count(*), 'lwins', (array_agg(c.lwin order by c.lwin))[1:10]) as g
                from rep c
               where c.natural_group_size > 1 and coalesce(p_sample, 0) > 0
               group by c.natural_group_size, catalog.fold_text(c.producer_name), catalog.fold_text(c.wine),
                        catalog.fold_text(c.country), catalog.fold_text(c.region), catalog.fold_text(c.sub_region),
                        catalog.fold_text(c.designation), catalog.fold_text(c.classification),
                        catalog.fold_text(c.colour), catalog.fold_text(c.sub_type)
               order by count(*) desc, min(c.producer_name), min(c.wine)
               limit greatest(coalesce(p_sample, 0), 0)) x),
    'missing_information', jsonb_build_object(
      'without_territory', t.without_territory, 'without_region', t.without_region, 'without_colour', t.without_colour,
      'without_wine_type', t.without_wine_type,
      'not_provided_by_source', jsonb_build_array('vintage', 'format', 'grapes', 'price')))
    from tot t;
$$;

-- Stesse chiavi di prima.
create or replace function catalog.promotion_preview(p_source_code text default 'LIVEX-LWIN7', p_rule_version text default 'lwin-conservative-v1')
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_source uuid;
  v_rule_status text;
  v_enabled boolean;
begin
  select id into v_source from catalog.sources where code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;
  select status into v_rule_status from catalog.promotion_rules where version = p_rule_version;
  select enabled into v_enabled from catalog.promotion_settings;

  return (catalog.promotion_analysis(v_source, 0) -> 'preview') || jsonb_build_object(
    'rule_version', p_rule_version, 'rule_status', coalesce(v_rule_status, 'unknown'),
    'promotion_enabled', coalesce(v_enabled, false), 'database_writes', 0);
end;
$$;

create or replace function catalog.promotion_simulation(
  p_source_code text default 'LIVEX-LWIN7',
  p_rule_version text default 'lwin-conservative-v1',
  p_sample integer default 20
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_n integer := least(greatest(coalesce(p_sample, 20), 1), 200);
  v_source uuid;
  v_src jsonb;
  v_rule jsonb;
  v_complete jsonb;
  v_analysis jsonb;
  v_summary jsonb;
  v_conflicts jsonb;
  v_actions jsonb := '[]'::jsonb;
  v_open_dups bigint;
  v_open_findings bigint;
  v_blocked bigint;
  v_possible_dups bigint;
  v_rule_status text;
  v_summary_rule_status text;
  v_enabled boolean;
  v_projection boolean;
begin
  select s.id, jsonb_build_object('code', s.code, 'name', s.name, 'license', s.license,
           'attribution', s.attribution_text, 'authorization_status', s.authorization_status)
    into v_source, v_src from catalog.sources s where s.code = p_source_code;
  if v_source is null then
    raise exception 'catalog: fonte sconosciuta' using errcode = 'P0002';
  end if;

  select r.status, jsonb_build_object('version', r.version, 'status', r.status,
           'approved_fingerprint', r.approved_fingerprint,
           'current_fingerprint', catalog.promotion_logic_fingerprint(r.version))
    into v_rule_status, v_rule from catalog.promotion_rules r where r.version = p_rule_version;
  v_summary_rule_status := coalesce(v_rule_status, 'unknown');
  select enabled into v_enabled from catalog.promotion_settings;
  select enabled into v_projection from catalog.public_projection_settings;

  select to_jsonb(c) into v_complete
    from (select cv.complete_run_id, cv.complete_at, cv.complete_sha256, cv.attempt_in_progress
            from catalog.complete_versions cv where cv.source_id = v_source) c;

  -- UNA sola valutazione del rapporto: riepilogo, candidati (stessa definizione del lotto reale), esclusi, gruppi.
  v_analysis := catalog.promotion_analysis(v_source, v_n);
  v_summary := (v_analysis -> 'preview') || jsonb_build_object(
    'rule_version', p_rule_version, 'rule_status', v_summary_rule_status,
    'promotion_enabled', coalesce(v_enabled, false), 'database_writes', 0);
  v_possible_dups := (v_analysis ->> 'possible_duplicate_records')::bigint;
  v_blocked := (v_summary ->> 'blocked_producer_retired')::bigint;

  select count(*) into v_open_dups from catalog.duplicate_candidates where review_status = 'open';
  select count(*) into v_open_findings from catalog.import_findings where source_id = v_source and review_status = 'open';

  -- Conflitti tra fonti: rivendicazioni accettate con valori diversi per lo stesso attributo e soggetto.
  select jsonb_build_object(
           'attribute_claims_conflicting', count(*),
           'sample', coalesce(jsonb_agg(jsonb_build_object('attribute_key', t.attribute_key, 'subject', t.subject)
                                         order by t.attribute_key, t.subject) filter (where t.rn <= v_n), '[]'::jsonb))
    into v_conflicts
    from (select s.attribute_key, s.subject, row_number() over (order by s.attribute_key, s.subject) as rn
            from (select ac.attribute_key,
                         coalesce(ac.wine_id, ac.producer_id, ac.vintage_id, ac.format_id)::text as subject
                    from catalog.attribute_claims ac where ac.status = 'accepted'
                   group by 1, 2 having count(distinct ac.value) > 1) s) t;

  -- Azioni che richiedono una persona. Ordine: prima ciò che blocca, poi ciò che migliora.
  if v_rule_status is distinct from 'approved' then
    v_actions := v_actions || jsonb_build_object('action', 'approve_promotion_rule', 'detail', p_rule_version, 'count', 1);
  end if;
  if coalesce(v_enabled, false) is false then
    v_actions := v_actions || jsonb_build_object('action', 'enable_promotion', 'detail', 'promotion_settings.enabled = false', 'count', 1);
  end if;
  if v_possible_dups > 0 then
    v_actions := v_actions || jsonb_build_object('action', 'review_possible_duplicates', 'detail', 'record con la stessa identita naturale e LWIN diversi', 'count', v_possible_dups);
  end if;
  if v_blocked > 0 then
    v_actions := v_actions || jsonb_build_object('action', 'resolve_retired_producers', 'detail', 'produttore ritirato o fuso', 'count', v_blocked);
  end if;
  if v_open_dups > 0 then
    v_actions := v_actions || jsonb_build_object('action', 'review_open_duplicate_candidates', 'detail', 'catalog.duplicate_candidates', 'count', v_open_dups);
  end if;
  if v_open_findings > 0 then
    v_actions := v_actions || jsonb_build_object('action', 'review_import_findings', 'detail', 'catalog.import_findings', 'count', v_open_findings);
  end if;
  if coalesce(v_projection, false) is false then
    v_actions := v_actions || jsonb_build_object('action', 'enable_public_projection', 'detail', 'public_projection_settings.enabled = false', 'count', 1);
  end if;

  return jsonb_build_object(
    'database_writes', 0,
    'dry_run', true,
    'source', v_src,
    'rule', coalesce(v_rule, jsonb_build_object('version', p_rule_version, 'status', 'unknown')),
    'promotion_enabled', coalesce(v_enabled, false),
    'public_projection_enabled', coalesce(v_projection, false),
    'source_version', coalesce(v_complete, '{}'::jsonb),
    'summary', v_summary,
    'candidates', v_analysis -> 'candidates',
    'excluded_by_reason', v_analysis -> 'excluded_by_reason',
    'excluded_sample', v_analysis -> 'excluded_sample',
    'possible_duplicate_records', v_possible_dups,
    'possible_duplicate_groups', v_analysis -> 'possible_duplicate_groups',
    'missing_information', v_analysis -> 'missing_information',
    'source_conflicts', v_conflicts,
    'curator_actions', v_actions);
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. Lotto reale: corpo della 20261119140000, con UNA sola lettura di `promotion_lot`
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
  v_lot jsonb;
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

  -- Lotto e bloccati da UNA sola valutazione del rapporto; sotto i tre lock l'insieme non cambia fino al commit.
  select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb) into v_lot
    from catalog.promotion_lot(v_source, p_limit, 10000) l;

  -- D-4: i record con produttore ritirato non entrano nel lotto (non lo occupano) e sono tracciati come eccezioni.
  insert into catalog.promotion_exceptions (source_id, source_record_id, lwin, reason, producer_id, rule_version)
  select v_source, x.source_record_id, x.lwin, 'producer_retired', x.blocked_producer_id, c_logic
    from jsonb_to_recordset(v_lot) as x(kind text, source_record_id bigint, lwin text, blocked_producer_id uuid)
   where x.kind = 'blocked'
   order by x.lwin
  on conflict (source_record_id, reason) do nothing;
  get diagnostics v_exceptions = row_count;

  with batch as (
    select * from jsonb_to_recordset(v_lot) as b(kind text, source_record_id bigint, lwin text, producer_name text,
             country text, producer_key text)
     where b.kind = 'batch'),
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

  with batch as (
    select * from jsonb_to_recordset(v_lot) as b(kind text, source_record_id bigint, lwin text, wine text, colour text,
             wine_type text, sub_type text, designation text, classification text, territory_id bigint, producer_key text)
     where b.kind = 'batch'),
  ins as (
    insert into catalog.wines (lwin7, producer_id, name, name_key, colour, wine_type, sub_type, designation, classification,
                               territory_id, origin, source_id, source_record_id)
    select b.lwin, catalog.producer_final(p.id), b.wine, catalog.fold_text(b.wine), b.colour, b.wine_type, b.sub_type,
           b.designation, b.classification, b.territory_id, 'promotion', v_source, b.source_record_id
      from batch b
      join catalog.producers p on p.natural_key = b.producer_key and p.status <> 'retired'
     order by b.lwin
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

-- ---------------------------------------------------------------------------------------------
-- 5. Impronta: la logica del lotto ha tre dipendenze in più (28 funzioni)
-- ---------------------------------------------------------------------------------------------
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
  'configurazione di 28 funzioni (promozione, guardie, chiave di ricerca) e definizione/stato dei trigger sulle tabelle '
  'canoniche. Null se manca una funzione o la versione è sconosciuta.';

comment on function catalog.promotion_report(uuid) is
  'WI-008. Unica definizione di candidato alla promozione: il rapporto di una fonte, valutato una volta.';
comment on function catalog.promotion_lot(uuid, integer, integer) is
  'WI-008. Lotto e record bloccati non ancora tracciati da una sola valutazione del rapporto. Sola lettura.';
comment on function catalog.promotion_analysis(uuid, integer) is
  'WI-008. Riepilogo e sezioni della simulazione da un solo CTE materializzato. Sola lettura.';

-- Le funzioni nuove: nessun EXECUTE alle API né al caricatore. Il curatore ne ha bisogno perché anteprima, lotto e
-- candidati sono funzioni invoker che può già chiamare.
revoke all on function catalog.promotion_retired_producers(), catalog.promotion_report(uuid),
  catalog.promotion_lot(uuid, integer, integer), catalog.promotion_analysis(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function catalog.promotion_retired_producers(), catalog.promotion_report(uuid),
  catalog.promotion_lot(uuid, integer, integer), catalog.promotion_analysis(uuid, integer)
  to catalog_curator;
