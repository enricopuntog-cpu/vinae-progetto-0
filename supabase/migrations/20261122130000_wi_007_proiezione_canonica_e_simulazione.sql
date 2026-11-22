-- WI-007 — catalogo canonico: simulazione della promozione e proiezione pubblica per la ricerca.
--
-- Additiva: nessuna migration distribuita viene toccata, nessun corpo di funzione esistente cambia
-- (quindi l'impronta di `promotion_logic_fingerprint` e la regola `lwin-conservative-v1`, in bozza,
-- restano invariate). Non scrive nel catalogo, non importa LWIN, non approva nessuna regola.
--
-- 1. `catalog.promotion_simulation(...)`: prova della promozione RECORD PER RECORD (candidati, esclusi
--    con motivo, gruppi di possibili duplicati, informazioni mancanti, conflitti, azioni per il
--    curatore, provenienza). Sola lettura, nessuna fusione, nessun EXECUTE alle API.
-- 2. `catalog.public_projection_settings`: interruttore della proiezione pubblica, SPENTO di default.
-- 3. `catalog.wines.search_key` (+ trigger di inserimento, indici): chiave di ricerca normalizzata
--    come `vini_normalizza`, calcolata una volta (identità del vino immutabile per `wines_guard`).
-- 4. `public.vini_canonici_cerca(...)`: UNICA porta pubblica sul catalogo canonico. Non espone `catalog.*`:
--    restituisce solo dati enologici consentiti dei vini PROMOSSI (origine `promotion`, attivi, con
--    produttore attivo), con provenienza e attribuzione della fonte, e solo se l'interruttore è acceso.
--    Nessun prezzo, nessun dato personale, nessuna rivendicazione non accettata.

-- ---------------------------------------------------------------------------------------------
-- 1. Simulazione della promozione
-- ---------------------------------------------------------------------------------------------

create or replace function catalog.promotion_simulation(
  p_source_code text default 'LIVEX-LWIN7',
  p_rule_version text default 'lwin-conservative-v1',
  p_sample integer default 20
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_n integer := least(greatest(coalesce(p_sample, 20), 1), 200);
  v_source uuid;
  v_src jsonb;
  v_rule jsonb;
  v_complete jsonb;
  v_summary jsonb;
  v_candidates jsonb;
  v_reasons jsonb;
  v_excluded jsonb;
  v_groups jsonb;
  v_missing jsonb;
  v_conflicts jsonb;
  v_actions jsonb := '[]'::jsonb;
  v_open_dups bigint;
  v_open_findings bigint;
  v_blocked bigint;
  v_possible_dups bigint;
  v_rule_status text;
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
  select enabled into v_enabled from catalog.promotion_settings;
  select enabled into v_projection from catalog.public_projection_settings;

  select to_jsonb(c) into v_complete
    from (select cv.complete_run_id, cv.complete_at, cv.complete_sha256, cv.attempt_in_progress
            from catalog.complete_versions cv where cv.source_id = v_source) c;

  v_summary := catalog.promotion_preview(p_source_code, p_rule_version);

  -- Candidati che la regola promuoverebbe ora (stessa funzione del lotto reale: nessuna logica duplicata).
  select coalesce(jsonb_agg(jsonb_build_object(
           'lwin', b.lwin, 'producer', b.producer_name, 'wine', b.wine, 'country', b.country,
           'colour', b.colour, 'wine_type', b.wine_type, 'territory_id', b.territory_id,
           'producer_exists', exists (select 1 from catalog.producers p where p.natural_key = b.producer_key),
           'source_record_id', b.source_record_id) order by b.lwin), '[]'::jsonb)
    into v_candidates from catalog.promotion_batch(v_source, v_n) b;

  -- Esclusi: un record può avere più motivi; i conteggi sono per motivo.
  with r as (
    select c.*, (c.lwin ~ '^[0-9]{7}$') as lwin_ok,
           exists (select 1 from catalog.wines w where w.lwin7 = c.lwin) as promoted
      from catalog.wine_candidate_report c where c.source_id = v_source),
  m as (
    select unnest(review_reasons) as reason from r where readiness = 'needs_review'
    union all select 'invalid_lwin7' from r where not lwin_ok
    union all select 'already_promoted' from r where promoted)
  select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) into v_reasons
    from (select reason, count(*) as n from m group by reason) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'lwin', e.lwin, 'producer', e.producer_name, 'wine', e.wine, 'country', e.country,
           'reasons', e.reasons) order by e.lwin), '[]'::jsonb)
    into v_excluded
    from (
      select c.lwin, c.producer_name, c.wine, c.country,
             c.review_reasons || case when c.lwin !~ '^[0-9]{7}$' then array['invalid_lwin7'] else array[]::text[] end as reasons
        from catalog.wine_candidate_report c
       where c.source_id = v_source
         and (c.readiness = 'needs_review' or c.lwin !~ '^[0-9]{7}$')
       order by c.lwin
       limit v_n) e;

  -- Possibili duplicati: record con la stessa identità naturale ma LWIN diversi. Mai fusi qui.
  select coalesce(jsonb_agg(g order by (g ->> 'records')::int desc, g ->> 'producer', g ->> 'wine'), '[]'::jsonb)
    into v_groups
    from (
      select jsonb_build_object('producer', min(c.producer_name), 'wine', min(c.wine), 'country', min(c.country),
               'records', count(*), 'lwins', (array_agg(c.lwin order by c.lwin))[1:10]) as g
        from catalog.wine_candidate_report c
       where c.source_id = v_source and c.natural_group_size > 1
       group by c.natural_group_size, catalog.fold_text(c.producer_name), catalog.fold_text(c.wine),
                catalog.fold_text(c.country), catalog.fold_text(c.region), catalog.fold_text(c.sub_region),
                catalog.fold_text(c.designation), catalog.fold_text(c.classification),
                catalog.fold_text(c.colour), catalog.fold_text(c.sub_type)
       order by count(*) desc, min(c.producer_name), min(c.wine)
       limit v_n) x;
  select count(*) into v_possible_dups from catalog.wine_candidate_report c
   where c.source_id = v_source and c.natural_group_size > 1;

  -- Informazioni mancanti sui soli candidati idonei (LWIN-7 non fornisce annata, formato, vitigni, prezzi).
  select jsonb_build_object(
           'without_territory', count(*) filter (where c.territory_id is null),
           'without_region', count(*) filter (where c.region is null),
           'without_colour', count(*) filter (where c.colour is null),
           'without_wine_type', count(*) filter (where c.wine_type is null),
           'not_provided_by_source', jsonb_build_array('vintage', 'format', 'grapes', 'price'))
    into v_missing
    from catalog.wine_candidate_report c
   where c.source_id = v_source and c.readiness = 'fields_complete' and c.lwin ~ '^[0-9]{7}$'
     and not exists (select 1 from catalog.wines w where w.lwin7 = c.lwin);

  select count(*) into v_blocked from catalog.promotion_candidates(v_source) where blocked_producer_id is not null;
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
    'candidates', v_candidates,
    'excluded_by_reason', v_reasons,
    'excluded_sample', v_excluded,
    'possible_duplicate_records', v_possible_dups,
    'possible_duplicate_groups', v_groups,
    'missing_information', v_missing,
    'source_conflicts', v_conflicts,
    'curator_actions', v_actions);
end;
$$;

comment on function catalog.promotion_simulation(text, text, integer) is
  'WI-007. Simulazione della promozione record per record (candidati, esclusi con motivo, gruppi di possibili duplicati, '
  'informazioni mancanti, conflitti, azioni del curatore, provenienza). Sola lettura: nessuna scrittura, nessuna fusione.';

revoke all on function catalog.promotion_simulation(text, text, integer) from public, anon, authenticated, service_role;
grant execute on function catalog.promotion_simulation(text, text, integer) to catalog_curator;

-- ---------------------------------------------------------------------------------------------
-- 2. Interruttore della proiezione pubblica (fail-closed)
-- ---------------------------------------------------------------------------------------------

create table catalog.public_projection_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  changed_at timestamptz not null default now(),
  note text
);
insert into catalog.public_projection_settings (id, enabled, note)
  values (true, false, 'WI-007: spenta. Si accende solo con una decisione esplicita del founder, dopo la promozione approvata.');
alter table catalog.public_projection_settings enable row level security;
revoke all on table catalog.public_projection_settings from public, anon, authenticated, service_role;

comment on table catalog.public_projection_settings is
  'WI-007. Una riga. enabled=false (default): public.vini_canonici_cerca non restituisce nulla.';

-- ---------------------------------------------------------------------------------------------
-- 3. Chiave di ricerca dei vini canonici
-- ---------------------------------------------------------------------------------------------

alter table catalog.wines add column search_key text not null default '';

-- Calcolata all'inserimento: nome del vino e produttore sono immutabili (`wines_guard`, `producers_guard`).
create or replace function catalog.wines_search_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_key := public.vini_normalizza(
    coalesce((select p.name from catalog.producers p where p.id = new.producer_id), '') || ' ' || new.name);
  return new;
end;
$$;

create trigger wines_search_key
  before insert on catalog.wines
  for each row execute function catalog.wines_search_key();

revoke all on function catalog.wines_search_key() from public, anon, authenticated, service_role;

create index wines_search_key_trgm_idx on catalog.wines using gin (search_key extensions.gin_trgm_ops)
  where status = 'active' and origin = 'promotion';
create index wines_search_key_eq_idx on catalog.wines (search_key) where status = 'active' and origin = 'promotion';
create index wine_aliases_combined_idx on catalog.entity_aliases (alias_key)
  where kind = 'combined_lwin' and wine_id is not null;

-- ---------------------------------------------------------------------------------------------
-- 4. Porta pubblica di ricerca sul catalogo canonico
-- ---------------------------------------------------------------------------------------------

create or replace function public.vini_canonici_cerca(
  p_produttore text default '',
  p_nome text default '',
  p_limite integer default 15,
  p_codice text default null
)
returns table (
  fonte text,
  vino_id uuid,
  lwin7 text,
  produttore text,
  nome text,
  paese text,
  territorio text,
  territorio_tipo text,
  denominazione text,
  tipo text,
  colore text,
  punteggio integer,
  livello text,
  fonte_nome text,
  fonte_licenza text,
  attribuzione text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_esame constant integer := 2000;
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  v_codice text := nullif(regexp_replace(left(coalesce(p_codice, ''), 40), '[^0-9]', '', 'g'), '');
  v_tp text[];
  v_tn text[];
  v_tok text[];
  v_where text;
  v_score text;
  v_acc jsonb := '[]'::jsonb;
  v_seen uuid[] := array[]::uuid[];
  v_rows jsonb;
  v_tier integer;
  v_esatto boolean := false;
  v_soglia_prec text;
begin
  -- Interruttore spento (default) o assente: nulla è pubblico.
  if not coalesce((select s.enabled from catalog.public_projection_settings s), false) then
    return;
  end if;

  select coalesce(array_agg(distinct t), array[]::text[]) into v_tp
    from unnest(string_to_array(v_qp, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t <> all (c_filler) and t !~ '^(19|20)[0-9]{2}$';
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tn
    from unnest(string_to_array(v_qn, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t !~ '^(19|20)[0-9]{2}$' and t <> all (v_tp);
  v_tok := (v_tp || v_tn)[1:6];
  v_qk := btrim(v_qp || ' ' || v_qn);

  if v_codice is null and coalesce(array_length(v_tok, 1), 0) = 0 then
    return;
  end if;

  for v_tier in 1..4 loop
    exit when jsonb_array_length(v_acc) >= v_limite;
    if v_tier = 1 then
      -- Identificativo LWIN-7 (anche di un record Combined, risolto sul vino di destinazione).
      continue when v_codice is null or length(v_codice) <> 7;
      v_score := '1000';
      -- Un solo `IN` su due rami indicizzati (btree su lwin7, indice parziale sugli alias): con un `OR`
      -- il piano ricadeva sulla scansione sequenziale dei vini.
      -- Il Combined si risolve sul vino di destinazione seguendo le fusioni (al massimo 20 passi) SOLO a
      -- partire dall'alias cercato: `catalog.wine_resolution` calcolerebbe la chiusura di tutti i vini.
      v_where := format('w.id in (select x.id from catalog.wines x where x.lwin7 = %1$L '
                        'union select t.cur from (with recursive r(cur, depth) as ('
                        'select a.wine_id, 0 from catalog.entity_aliases a '
                        'where a.kind = ''combined_lwin'' and a.alias_key = %1$L and a.wine_id is not null '
                        'union all select m.merged_into, r.depth + 1 from r '
                        'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                        'select cur from r) t)', v_codice);
    elsif v_tier = 2 then
      continue when v_qp = '' or v_qn = '';
      v_score := '100';
      v_where := format('w.search_key = %L', v_qk);
    elsif v_tier = 3 then
      continue when coalesce(array_length(v_tok, 1), 0) = 0;
      v_score := format('case when w.search_key like %L then 90 else 60 end', v_qk || '%');
      v_where := (select string_agg(format('w.search_key like %L', '%' || t || '%'), ' and ') from unnest(v_tok) t);
    else
      continue when v_esatto or jsonb_array_length(v_acc) >= 5 or length(v_qk) < 4;
      v_score := format('round(extensions.similarity(w.search_key, %L) * 50)::int', v_qk);
      v_where := format('w.search_key operator(extensions.%%) %L', v_qk);
    end if;

    if v_tier = 4 then
      perform extensions.similarity('a', 'a');
      v_soglia_prec := current_setting('pg_trgm.similarity_threshold', true);
      perform set_config('pg_trgm.similarity_threshold', '0.4', true);
    end if;

    -- Solo vini promossi, attivi, con produttore attivo. Visibilità scritta qui, mai da parametri.
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select c.*, %3$s as livello_n,
               row_number() over (order by c.punteggio desc, c.produttore, c.nome, c.lwin7, c.vino_id) as ord
        from (
          select w.id as vino_id, w.lwin7, p.name as produttore, w.name as nome,
                 cp.name as paese, t.name as territorio, t.kind as territorio_tipo,
                 w.designation as denominazione, w.wine_type as tipo, w.colour as colore,
                 (%1$s) as punteggio, s.name as fonte_nome, s.license as fonte_licenza,
                 s.attribution_text as attribuzione
          from catalog.wines w
          join catalog.producers p on p.id = w.producer_id and p.status = 'active'
          left join catalog.territories cp on cp.id = p.country_territory_id
          left join catalog.territories t on t.id = w.territory_id
          left join catalog.sources s on s.id = w.source_id
          where w.status = 'active' and w.origin = 'promotion' and (%2$s)
            and not (w.id = any (%4$L::uuid[]))
          limit %6$s
        ) c
        order by ord
        limit %5$s
      ) r$q$, v_score, v_where, v_tier, v_seen, v_limite - jsonb_array_length(v_acc), c_esame)
    into v_rows;

    if v_tier = 4 then
      perform set_config('pg_trgm.similarity_threshold', coalesce(nullif(v_soglia_prec, ''), '0.3'), true);
    end if;
    if v_tier <= 2 and jsonb_array_length(v_rows) > 0 then
      v_esatto := true;
    end if;
    v_acc := v_acc || v_rows;
    v_seen := v_seen || array(select (e ->> 'vino_id')::uuid from jsonb_array_elements(v_rows) e);
  end loop;

  return query
    select 'catalogo_canonico'::text, x.vino_id, x.lwin7, x.produttore, x.nome, x.paese, x.territorio,
           x.territorio_tipo, x.denominazione, x.tipo, x.colore, x.punteggio,
           case x.livello_n when 1 then 'identificativo' when 2 then 'esatto'
             when 3 then case when x.punteggio >= 90 then 'prefisso' else 'testo' end
             else 'simile' end,
           x.fonte_nome, x.fonte_licenza, x.attribuzione
    from jsonb_to_recordset(v_acc) as x(
      vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text,
      territorio_tipo text, denominazione text, tipo text, colore text, punteggio integer,
      fonte_nome text, fonte_licenza text, attribuzione text, livello_n integer, ord bigint)
    order by x.livello_n, x.ord;
end;
$$;

comment on function public.vini_canonici_cerca(text, text, integer, text) is
  'WI-007. Ricerca sui vini del catalogo canonico PROMOSSI (origine promotion, attivi), solo se '
  'catalog.public_projection_settings.enabled. SECURITY DEFINER con elenco chiuso di colonne enologiche, '
  'provenienza e attribuzione. Al massimo 20 righe e 2.000 candidati per livello. Non espone catalog.*, '
  'nessun prezzo, nessun dato personale.';

revoke all on function public.vini_canonici_cerca(text, text, integer, text) from public;
grant execute on function public.vini_canonici_cerca(text, text, integer, text)
  to anon, authenticated, service_role;
