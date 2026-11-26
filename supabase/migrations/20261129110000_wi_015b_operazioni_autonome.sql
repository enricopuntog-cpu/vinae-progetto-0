-- WI-015 B — operazioni autonome del Company Brain, completamento del Living Catalog e costi AI.
--
-- Tutto nasce SPENTO: nessun agente registrato, nessun lavoro dello scheduler acceso, nessuna fonte di monitoraggio
-- accesa, nessuna tariffa e nessun tetto di spesa; `pg_cron` NON e installato qui (script separati in
-- `tools/company-brain/scheduler/`). Nessun catalogo, coda, scheduler o monitor parallelo: si estendono `catalog.*`,
-- `brain.*` e il budget AI di WI-010. Nessun worker modifica il catalogo: produce evidenze e proposte.

-- =============================================================================================
-- D — acquisizione dagli annunci: ripetizioni limitate
-- =============================================================================================
alter table catalog.intake_settings
  add column harvest_max_attempts integer not null default 3 check (harvest_max_attempts between 1 and 10);

-- Le sole acquisizioni fallite: il riferimento dell'evento e il codice dell'errore, nessun contenuto.
create table catalog.intake_failures (
  source_ref text primary key check (length(source_ref) between 1 and 200),
  attempts integer not null default 1 check (attempts >= 1),
  last_sqlstate text not null check (length(last_sqlstate) = 5),
  first_failed_at timestamptz not null default now(),
  last_failed_at timestamptz not null default now()
);
alter table catalog.intake_failures enable row level security;
revoke all on catalog.intake_failures from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- Come WI-011, con le ripetizioni limitate: un annuncio che fallisce non resta in testa alla coda per sempre. Ogni
-- annuncio e un sottoblocco: un errore non ferma gli altri. La presenza della partecipazione e il checkpoint.
create or replace function catalog.harvest_listings(p_limit integer, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_row record;
  v_result record;
  v_data jsonb;
  v_ml integer;
  v_max integer;
  v_ref text;
  v_read integer := 0;
  v_new integer := 0;
  v_skipped integer := 0;
begin
  if not coalesce((select s.listing_harvest_enabled from catalog.intake_settings s), false) then
    return jsonb_build_object('abilitata', false, 'letti', 0, 'nuove_proposte', 0, 'scartati', 0, 'restanti', null, 'esauriti', null);
  end if;
  select s.harvest_max_attempts into v_max from catalog.intake_settings s;
  for v_row in
    select l.id, l.wine_id, l.produttore, l.nome, l.annata, l.regione, l.denominazione, l.tipo, l.formato
      from public.public_listings l
     where not exists (select 1 from catalog.contribution_submissions s where s.source_ref = 'annuncio:' || l.id::text)
       and not exists (select 1 from catalog.intake_failures f where f.source_ref = 'annuncio:' || l.id::text and f.attempts >= v_max)
     order by l.published_at nulls last, l.id
     limit least(greatest(coalesce(p_limit, 0), 0), 200)
  loop
    v_read := v_read + 1;
    v_ref := 'annuncio:' || v_row.id::text;
    v_ml := catalog.parse_format_ml(v_row.formato);
    v_data := jsonb_strip_nulls(jsonb_build_object(
      'produttore', v_row.produttore, 'nome', v_row.nome,
      'annata', case when v_row.annata between 1800 and extract(year from now())::integer + 1 then v_row.annata end,
      'regione', nullif(btrim(v_row.regione), ''), 'denominazione', nullif(btrim(v_row.denominazione), ''),
      'tipo', nullif(btrim(v_row.tipo), ''), 'formato_ml', v_ml));
    begin
      select * into v_result from catalog.contribution_register('annuncio', v_data, null, v_row.wine_id, v_ref);
      if v_result.nuova then v_new := v_new + 1; end if;
      delete from catalog.intake_failures where source_ref = v_ref;
    exception when others then
      v_skipped := v_skipped + 1;
      insert into catalog.intake_failures as f (source_ref, last_sqlstate) values (v_ref, sqlstate)
      on conflict (source_ref) do update set attempts = f.attempts + 1, last_sqlstate = excluded.last_sqlstate, last_failed_at = now();
    end;
  end loop;
  perform catalog.record_canonical_event('harvest_listings', 'intake', null, v_actor,
    jsonb_build_object('letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped));
  return jsonb_build_object('abilitata', true, 'letti', v_read, 'nuove_proposte', v_new, 'scartati', v_skipped,
    'esauriti', (select count(*) from catalog.intake_failures f where f.attempts >= v_max),
    'restanti', (select count(*) from public.public_listings l
                  where not exists (select 1 from catalog.contribution_submissions s where s.source_ref = 'annuncio:' || l.id::text)
                    and not exists (select 1 from catalog.intake_failures f
                                     where f.source_ref = 'annuncio:' || l.id::text and f.attempts >= v_max)));
end;
$$;

-- =============================================================================================
-- E — lavoro del Catalog Manager e del Data Quality
-- =============================================================================================
-- Ogni proposta aperta ha al massimo UN task che conta. Un task chiuso dalla regola (proposta gia decisa o ritirata)
-- non conta: se un nuovo invio la riapre, torna in coda. Un task annullato o deciso da una persona invece resta la
-- risposta. Nessuna seconda coda: e quella del brain.
create index tasks_contributo_idx on brain.tasks ((payload ->> 'contributo_id')) where task_type = 'catalogo.proposta';

create or replace function brain.contribution_has_task(p_contribution bigint)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from brain.tasks t
                  where t.task_type = 'catalogo.proposta' and t.payload ->> 'contributo_id' = p_contribution::text
                    and not (t.status = 'annullato' and t.decided_by is not distinct from 'regola:chiusura_consentita'));
$$;

create or replace function brain.enqueue_catalog_work(p_limit integer, p_actor text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v record;
  v_n integer := 0;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  for v in
    select c.id, c.match_kind from catalog.contributions c
     where c.status = 'aperta'
       and not brain.contribution_has_task(c.id)
     order by c.created_at, c.id
     limit least(greatest(coalesce(p_limit, 100), 1), 500)
  loop
    perform brain.enqueue_task('catalogo.proposta', 'Proposta al catalogo n. ' || v.id::text,
      case v.match_kind when 'ambiguo' then 1 when 'sconosciuto' then 2 else 3 end,
      jsonb_build_object('contributo_id', v.id),
      -- il numero dei task precedenti rende unica la chiave della riapertura e identica quella di due giri concorrenti
      'contributo:' || v.id::text || ':' || (select count(*) from brain.tasks t
          where t.task_type = 'catalogo.proposta' and t.payload ->> 'contributo_id' = v.id::text)::text, true, null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function brain.enqueue_quality_scan(p_actor text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_key text := 'qualita:' || (now() at time zone 'utc')::date::text;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('brain.quality_scan', 0));
  -- una sola scansione aperta e una al giorno: nessun arretrato
  if exists (select 1 from brain.tasks t where t.task_type = 'qualita.scansione'
              and (t.dedup_key = v_key or t.status in ('in_attesa', 'assegnato', 'in_approvazione'))) then
    return 0;
  end if;
  perform brain.enqueue_task('qualita.scansione', 'Scansione di qualità del catalogo ' || substr(v_key, 9), 3,
    '{}'::jsonb, v_key, true, null);
  return 1;
end;
$$;

-- Chiusura consentita senza giudizio, SOLO quando il server verifica che non resta nulla da decidere.
create or replace function brain.close_task_by_rule(p_task uuid, p_reason text)
returns void language plpgsql volatile set search_path = '' as $$
declare v_corr uuid;
begin
  update brain.tasks
     set status = 'annullato', decided_by = 'regola:chiusura_consentita', decided_at = clock_timestamp(),
         decision_note = p_reason, lease_agent = null, lease_token = null, lease_expires_at = null, lease_started_at = null,
         updated_at = now(), version = version + 1
   where id = p_task
  returning correlation_id into v_corr;
  perform brain.record_event('task.chiusura_consentita', 'brain', v_corr, 'chiusura:' || p_task::text, 'task', p_task::text,
    jsonb_build_object('motivo', p_reason));
end;
$$;

create or replace function brain.close_obsolete_catalog_tasks(p_actor text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v record;
  v_n integer := 0;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  for v in
    select t.id from brain.tasks t
     where t.task_type = 'catalogo.proposta' and t.status in ('in_attesa', 'in_approvazione')
       and not exists (select 1 from catalog.contributions c
                        where c.id = (t.payload ->> 'contributo_id')::bigint and c.status = 'aperta')
     order by t.id limit 500 for update of t skip locked
  loop
    perform brain.close_task_by_rule(v.id, 'La proposta è già stata decisa o ritirata.');
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Rilievi di qualita: sole query deterministiche, conteggi e riferimenti (mai testi liberi o dati di persone).
create or replace function brain.quality_findings()
returns jsonb language sql stable set search_path = '' as $$
  with rilievi as (
    select 'duplicati_aperti' as codice, 'P2' as severita, count(*) as conteggio,
           (array_agg(d.id::text order by d.id))[1:10] as esempi
      from catalog.duplicate_candidates d where d.review_status = 'open'
    union all
    select 'omonimi_attivi', 'P3', count(*), (array_agg(g.primo order by g.primo))[1:10]
      from (select min(w.id::text) as primo from catalog.wines w where w.status = 'active'
             group by w.search_key having count(*) > 1) g
    union all
    select 'conflitti_nativi', 'P2', count(*), (array_agg(c.wine_id::text order by c.wine_id))[1:10]
      from catalog.lwin_native_conflicts(1000) c
    union all
    select 'canonici_non_piu_live', 'P2', count(*), (array_agg(w.id::text order by w.id))[1:10]
      from catalog.wines w join catalog.source_records r on r.id = coalesce(w.source_record_id, w.lwin_assigned_record_id)
     where w.status = 'active' and (r.status <> 'Live' or r.removed_from_source_at is not null)
    union all
    select 'nativi_senza_annata', 'P3', count(*), (array_agg(w.id::text order by w.id))[1:10]
      from catalog.wines w where w.status = 'active' and w.origin = 'manual'
       and not exists (select 1 from catalog.wine_vintages a where a.wine_id = w.id)
    union all
    select 'produttori_senza_paese', 'P3', count(*), (array_agg(p.id::text order by p.id))[1:10]
      from catalog.producers p where p.status = 'active' and p.country_territory_id is null
       and exists (select 1 from catalog.wines w where w.producer_id = p.id and w.status = 'active')
    union all
    select 'proposte_incoerenti', 'P2', count(*), (array_agg(c.id::text order by c.id))[1:10]
      from catalog.contributions c
      left join lateral (select count(*) as n from catalog.contribution_submissions s where s.contribution_id = c.id) x on true
     where c.submissions_count <> x.n or (c.status = 'aperta' and x.n = 0)
    union all
    select 'importazioni_ferme', 'P2', count(*), (array_agg(i.seq::text order by i.seq))[1:10]
      from catalog.import_runs i where i.status = 'running' and i.heartbeat_at < now() - interval '2 hours')
  select coalesce(jsonb_agg(jsonb_build_object('codice', codice, 'severita', severita, 'conteggio', conteggio,
           'esempi', to_jsonb(coalesce(esempi, array[]::text[]))) order by severita, codice), '[]'::jsonb)
    from rilievi where conteggio > 0;
$$;

-- I dati del dominio che un agente puo leggere: SOLO quelli del task che ha in mano, scelti qui.
create or replace function brain.agent_context_core(p_agent text, p_task uuid, p_lease uuid)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  c catalog.contributions%rowtype;
  v_public uuid;
  v_match record;
  v_source text;
  v_anomaly bigint;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if t.task_type = 'catalogo.proposta' then
    select * into c from catalog.contributions x where x.id = (t.payload ->> 'contributo_id')::bigint;
    if not found or c.status <> 'aperta' then
      return jsonb_build_object('tipo', t.task_type, 'stato', 'gia_decisa');
    end if;
    select s.public_wine_id into v_public from catalog.contribution_submissions s
     where s.contribution_id = c.id and s.public_wine_id is not null order by s.id limit 1;
    select * into v_match from catalog.contribution_match(c.identity, v_public);
    return jsonb_build_object('tipo', t.task_type, 'stato', 'aperta', 'contributo_id', c.id, 'dati', c.identity,
      'origine', c.first_origin, 'affidabilita', c.trust, 'mancanti', to_jsonb(c.missing_fields),
      'corrispondenza', v_match.match_kind,
      'candidati', coalesce((select jsonb_agg(k.cand || coalesce(
            (select jsonb_build_object('produttore', p.name, 'nome', w.name)
               from catalog.wines w join catalog.producers p on p.id = w.producer_id where w.id = (k.cand ->> 'wine_id')::uuid),
            (select jsonb_build_object('produttore', r.payload ->> 'producer_name', 'nome', r.payload ->> 'wine')
               from catalog.source_records r where r.id = (k.cand ->> 'source_record_id')::bigint), '{}'::jsonb))
          from (select e.cand from jsonb_array_elements(v_match.candidates) with ordinality as e(cand, n) where e.n <= 10) k),
        '[]'::jsonb),
      'proposte_stesso_nome', (select count(*) from catalog.contributions o
                                where o.identity_key = c.identity_key and o.id <> c.id and o.status = 'aperta'));
  elsif t.task_type = 'qualita.scansione' then
    return jsonb_build_object('tipo', t.task_type, 'rilievi', brain.quality_findings());
  elsif t.task_type = 'tecnico.segnale' then
    v_source := t.payload ->> 'fonte';
    return jsonb_build_object('tipo', t.task_type, 'fonte', v_source,
      'intervallo_atteso_minuti', (select m.expected_interval_minutes from brain.monitor_sources m where m.source_key = v_source),
      'segnali', coalesce((select jsonb_agg(jsonb_build_object('stato', x.status, 'osservato', x.observed_at,
                    'ricevuto', x.received_at, 'riferimento', x.evidence_ref, 'conteggi', x.counts) order by x.observed_at desc, x.id desc)
          from (select * from brain.monitor_signals s where s.source_key = v_source order by s.observed_at desc, s.id desc limit 30) x),
        '[]'::jsonb),
      'anomalia', (select jsonb_build_object('stato', a.status, 'ricorrenze', a.occurrences, 'prima', a.first_seen_at)
                     from brain.anomalies a where a.fingerprint = 'segnale_monitor:' || v_source));
  elsif t.task_type = 'anomalia.verifica' then
    v_anomaly := (t.payload ->> 'anomalia_id')::bigint;
    return jsonb_build_object('tipo', t.task_type, 'anomalia', (select jsonb_build_object('codice', a.code,
             'severita', a.severity, 'stato', a.status, 'evidenza', a.evidence, 'ricorrenze', a.occurrences,
             'azione_proposta', a.azione_proposta) from brain.anomalies a where a.id = v_anomaly));
  end if;
  raise exception 'brain: nessun contesto per questo tipo di task' using errcode = '22023';
end;
$$;

create or replace function brain.close_if_allowed_core(p_agent text, p_task uuid, p_lease uuid)
returns text language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if t.task_type = 'catalogo.proposta' and not exists (select 1 from catalog.contributions c
       where c.id = (t.payload ->> 'contributo_id')::bigint and c.status = 'aperta') then
    perform brain.close_task_by_rule(p_task, 'La proposta è già stata decisa o ritirata.');
  elsif t.task_type = 'qualita.scansione' and jsonb_array_length(brain.quality_findings()) = 0 then
    perform brain.close_task_by_rule(p_task, 'Nessun rilievo: nulla da decidere.');
  else
    raise exception 'brain: chiusura non consentita, serve una decisione' using errcode = '42501';
  end if;
  return 'annullato';
end;
$$;

create or replace function brain.agent_context(p_task uuid, p_lease uuid)
returns jsonb language sql volatile security definer set search_path = '' as $$
  select brain.agent_context_core(brain.current_agent(), p_task, p_lease);
$$;
create or replace function brain.close_if_allowed(p_task uuid, p_lease uuid)
returns text language sql volatile security definer set search_path = '' as $$
  select brain.close_if_allowed_core(brain.current_agent(), p_task, p_lease);
$$;

-- =============================================================================================
-- H — ingestione ristretta dei segnali tecnici
-- =============================================================================================
do $ruoli$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'brain_ingest') then
    create role brain_ingest nologin noinherit;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'brain_monitor_read') then
    create role brain_monitor_read nologin noinherit;
  end if;
end $ruoli$;
grant usage on schema brain to brain_ingest, brain_monitor_read;

create table brain.monitor_sources (
  source_key text primary key check (source_key ~ '^[a-z][a-z0-9_]{1,40}$'),
  descrizione text not null,
  severity text not null check (severity in ('P1', 'P2', 'P3')),
  expected_interval_minutes integer not null check (expected_interval_minutes between 5 and 43200),
  enabled boolean not null default false
);
insert into brain.monitor_sources (source_key, descrizione, severity, expected_interval_minutes) values
  ('technical_heartbeat', 'Workflow GitHub technical-heartbeat (sito e scheduler dei payout)', 'P2', 720),
  ('offsite_backup_freshness', 'Workflow GitHub offsite-backup-freshness (backup cifrato fuori sede)', 'P1', 1440),
  ('ci_main', 'CI del ramo principale', 'P3', 10080),
  ('app_health', 'Health check dell''applicazione', 'P2', 720),
  ('app_errors', 'Conteggi aggregati degli errori applicativi', 'P3', 1440),
  ('supabase_logs', 'Conteggi aggregati dei registri Supabase', 'P3', 1440),
  ('ai_budget', 'Consumo del budget AI', 'P3', 1440);

create table brain.monitor_signals (
  id bigint generated always as identity primary key,
  source_key text not null references brain.monitor_sources(source_key),
  event_id text not null check (event_id ~ '^[A-Za-z0-9_:.-]{1,120}$'),
  status text not null check (status in ('ok', 'degradato', 'guasto', 'sconosciuto')),
  observed_at timestamptz not null,
  -- solo un riferimento alla prova: un collegamento a GitHub o un identificativo, mai testo libero o log
  evidence_ref text check (evidence_ref is null
    or evidence_ref ~ '^(https://github\.com/[A-Za-z0-9_./-]{1,200}|[A-Za-z0-9_:.-]{1,120})$'),
  counts jsonb not null default '{}'::jsonb check (jsonb_typeof(counts) = 'object' and octet_length(counts::text) <= 1024),
  received_at timestamptz not null default clock_timestamp(),
  received_from text not null,
  unique (source_key, event_id)
);
create index monitor_signals_recent_idx on brain.monitor_signals (source_key, observed_at desc, id desc);
create trigger monitor_signals_append_only before update or delete on brain.monitor_signals
  for each row execute function brain.append_only();
create trigger monitor_signals_no_truncate before truncate on brain.monitor_signals
  for each statement execute function brain.append_only();
alter table brain.monitor_sources enable row level security;
alter table brain.monitor_signals enable row level security;
revoke all on brain.monitor_sources, brain.monitor_signals
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

create or replace function brain.ingest_signal_core(p_sender text, p_source text, p_event_id text, p_status text,
  p_observed_at timestamptz, p_evidence_ref text, p_counts jsonb)
returns text language plpgsql volatile set search_path = '' as $$
declare
  s brain.monitor_sources%rowtype;
  v_counts jsonb := coalesce(p_counts, '{}'::jsonb);
  v_latest timestamptz;
  v_id bigint;
  v_anomaly bigint;
  v_severity text;
begin
  select * into s from brain.monitor_sources m where m.source_key = p_source for update;
  if not found or not s.enabled then
    raise exception 'brain: fonte di monitoraggio inesistente o spenta' using errcode = '42501';
  end if;
  if p_observed_at is null or p_observed_at > clock_timestamp() + interval '5 minutes'
     or p_observed_at < clock_timestamp() - interval '30 days'
     or p_status is null or p_status not in ('ok', 'degradato', 'guasto', 'sconosciuto')
     or p_event_id is null or p_event_id !~ '^[A-Za-z0-9_:.-]{1,120}$'
     or (p_evidence_ref is not null
         and p_evidence_ref !~ '^(https://github\.com/[A-Za-z0-9_./-]{1,200}|[A-Za-z0-9_:.-]{1,120})$')
     or jsonb_typeof(v_counts) <> 'object' then
    raise exception 'brain: segnale non valido' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_each(v_counts) e where e.key !~ '^[a-z_]{1,40}$' or jsonb_typeof(e.value) <> 'number')
     or (select count(*) from jsonb_object_keys(v_counts)) > 12 then
    raise exception 'brain: i conteggi accettano solo numeri' using errcode = '22023';
  end if;
  if exists (select 1 from brain.monitor_signals x where x.source_key = p_source and x.event_id = p_event_id) then
    return 'duplicato';
  end if;
  if (select count(*) from brain.monitor_signals x where x.source_key = p_source
       and x.received_at > clock_timestamp() - interval '1 hour') >= 120 then
    raise exception 'brain: troppi segnali per questa fonte' using errcode = '53400';
  end if;
  select max(x.observed_at) into v_latest from brain.monitor_signals x where x.source_key = p_source;
  insert into brain.monitor_signals (source_key, event_id, status, observed_at, evidence_ref, counts, received_from)
  values (p_source, p_event_id, p_status, p_observed_at, p_evidence_ref, v_counts, p_sender)
  returning id into v_id;
  -- un segnale vecchio arrivato in ritardo e storia, non stato attuale
  if v_latest is not null and p_observed_at < v_latest then
    return 'registrato';
  end if;
  if p_status in ('guasto', 'degradato') then
    v_severity := case when p_status = 'guasto' then s.severity else 'P3' end;
    v_anomaly := brain.report_anomaly('segnale_monitor', p_source, 'monitor', 'operativo', v_severity,
      left('Segnale ' || p_status || ': ' || s.descrizione, 200),
      jsonb_strip_nulls(jsonb_build_object('stato', p_status, 'evento', p_event_id, 'riferimento', p_evidence_ref,
        'osservato', p_observed_at)),
      'Verificare la causa con le evidenze; chiudere solo con la prova della risoluzione, non per un successivo verde.', true);
    if not exists (select 1 from brain.tasks t where t.task_type = 'tecnico.segnale' and t.payload ->> 'fonte' = p_source
                    and t.status in ('in_attesa', 'assegnato', 'in_approvazione')) then
      perform brain.enqueue_task('tecnico.segnale', left('Verifica tecnica: ' || s.descrizione, 200),
        case v_severity when 'P1' then 1 when 'P2' then 2 else 3 end,
        jsonb_build_object('fonte', p_source, 'anomalia_id', v_anomaly), 'segnale:' || v_id::text, true,
        (select a.correlation_id from brain.anomalies a where a.id = v_anomaly));
    end if;
  elsif p_status = 'ok' then
    -- il verde si annota; NON chiude (la chiusura richiede una persona e il motivo)
    update brain.anomalies a
       set evidence = a.evidence || jsonb_build_object('tornato_verde', coalesce(a.evidence ->> 'tornato_verde', p_observed_at::text))
     where a.fingerprint = 'segnale_monitor:' || p_source and a.status in ('aperta', 'presa_in_carico', 'ignorata');
  end if;
  return 'registrato';
end;
$$;

-- Porta del mittente: un login dedicato membro SOLO di brain_ingest. Nessun potere di amministrazione.
create or replace function brain.ingest_signal(p_source text, p_event_id text, p_status text, p_observed_at timestamptz,
  p_evidence_ref text default null, p_counts jsonb default '{}'::jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_roles r
                  where r.rolname = session_user
                    and not (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)
                    and r.rolname::text !~ '^(postgres$|authenticator$|anon$|authenticated$|service_role$|supabase_|pg_|catalog_)'
                    and exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                 where m.member = r.oid and g.rolname = 'brain_ingest')
                    and not exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                                     where m.member = r.oid and g.rolname <> 'brain_ingest')) then
    raise exception 'brain: sessione non autorizzata a inviare segnali' using errcode = '42501';
  end if;
  return brain.ingest_signal_core(session_user::text, p_source, p_event_id, p_status, p_observed_at, p_evidence_ref, p_counts);
end;
$$;

-- =============================================================================================
-- G — scheduler unico
-- =============================================================================================
create table brain.jobs (
  job_key text primary key check (job_key ~ '^[a-z][a-z0-9_]{1,40}$'),
  descrizione text not null,
  interval_minutes integer not null check (interval_minutes between 5 and 43200),
  enabled boolean not null default false,
  max_failures integer not null default 5 check (max_failures between 1 and 20),
  consecutive_failures integer not null default 0,
  next_due_at timestamptz,
  last_started_at timestamptz,
  last_finished_at timestamptz,
  last_status text check (last_status in ('ok', 'errore', 'sospeso')),
  last_sqlstate text,
  last_result jsonb
);
insert into brain.jobs (job_key, descrizione, interval_minutes) values
  ('sentinel', 'Controlli deterministici di Sentinel', 60),
  ('lease_scaduti', 'Recupero dei lease scaduti', 15),
  ('attivita_ferme', 'Attività ferme: task senza agente, approvazioni in attesa, task falliti', 60),
  ('lavoro_catalogo', 'Proposte aperte in coda e chiusura consentita dei task superati', 60),
  ('proposte_dagli_annunci', 'Acquisizione periodica dagli annunci pubblici (solo se accesa anche nel catalogo)', 360),
  ('qualita_catalogo', 'Scansione giornaliera di qualità del catalogo', 1440);

create table brain.scheduler_state (
  singleton boolean primary key default true check (singleton),
  tick_expected_minutes integer not null default 15 check (tick_expected_minutes between 1 and 1440),
  last_tick_at timestamptz,
  last_tick_by text,
  last_scheduled_tick_at timestamptz,
  ticks bigint not null default 0
);
insert into brain.scheduler_state default values;
alter table brain.jobs enable row level security;
alter table brain.scheduler_state enable row level security;
revoke all on brain.jobs, brain.scheduler_state
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

create or replace function brain.check_stale_work()
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v record;
  v_found integer := 0;
begin
  for v in
    select * from (values
      ('task_senza_agente', 'P3', 'Task in coda da oltre 24 ore senza un agente acceso per il loro tipo',
       (select count(*) from brain.tasks t where t.status = 'in_attesa' and t.created_at < now() - interval '24 hours'
         and not exists (select 1 from brain.agents a where a.enabled and t.task_type = any (a.task_types))),
       'Rivedere i task o accendere l''agente dopo il suo gate.'),
      ('approvazioni_in_attesa', 'P3', 'Proposte in attesa di decisione da oltre 7 giorni',
       (select count(*) from brain.tasks t where t.status = 'in_approvazione' and t.updated_at < now() - interval '7 days'),
       'Decidere dal cruscotto.'),
      ('task_falliti', 'P2', 'Task falliti dopo tutti i tentativi',
       (select count(*) from brain.tasks t where t.status = 'fallito'),
       'Leggere le evidenze, correggere la causa e annullare o ricreare il task.')
    ) as c(code, severity, titolo, n, azione)
  loop
    if v.n > 0 then
      v_found := v_found + 1;
      perform brain.report_anomaly(v.code, '', 'scheduler', 'operativo', v.severity, v.titolo,
        jsonb_build_object('conteggio', v.n), v.azione, true);
    else
      update brain.anomalies set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'scheduler',
             ignored_until = null, ignored_severity = null
       where fingerprint = v.code and status in ('aperta', 'presa_in_carico', 'ignorata');
    end if;
  end loop;
  return jsonb_build_object('rilievi', v_found);
end;
$$;

-- Elenco CHIUSO dei lavori: nessuna stringa SQL nella tabella.
create or replace function brain.run_job(p_job text, p_actor text)
returns jsonb language plpgsql volatile set search_path = '' as $$
begin
  case p_job
    when 'sentinel' then
      return brain.sentinel_run(p_actor);
    when 'lease_scaduti' then
      return jsonb_build_object('liberati', brain.reap_expired_leases());
    when 'attivita_ferme' then
      return brain.check_stale_work();
    when 'lavoro_catalogo' then
      return jsonb_build_object('chiusi', brain.close_obsolete_catalog_tasks(p_actor),
                                'accodati', brain.enqueue_catalog_work(200, p_actor));
    when 'proposte_dagli_annunci' then
      return catalog.harvest_listings(200, p_actor);
    when 'qualita_catalogo' then
      return jsonb_build_object('accodati', brain.enqueue_quality_scan(p_actor));
    else
      raise exception 'brain: lavoro sconosciuto' using errcode = '22023';
  end case;
end;
$$;

-- Un giro: un solo esecutore, i soli lavori accesi e scaduti, al massimo `p_max_jobs`; ogni lavoro in un sottoblocco.
-- La prossima scadenza parte da ADESSO (nessun arretrato). Dopo un guasto l'attesa raddoppia; oltre il limite il
-- lavoro si sospende e apre un'anomalia. Un annullamento (timeout del giro) interrompe il giro.
create or replace function brain.scheduler_tick(p_actor text, p_max_jobs integer default 4)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  j record;
  v_result jsonb;
  v_done jsonb := '[]'::jsonb;
  v_state text;
  v_failures integer;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('brain.scheduler', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso', 'eseguiti', '[]'::jsonb);
  end if;
  update brain.scheduler_state
     set last_tick_at = clock_timestamp(), last_tick_by = btrim(p_actor), ticks = ticks + 1,
         last_scheduled_tick_at = case when p_actor like 'pg_cron%' then clock_timestamp() else last_scheduled_tick_at end;
  for j in
    select * from brain.jobs x where x.enabled and (x.next_due_at is null or x.next_due_at <= clock_timestamp())
     order by x.next_due_at nulls first, x.job_key
     limit least(greatest(coalesce(p_max_jobs, 4), 1), 10)
     for update skip locked
  loop
    v_state := null;
    update brain.jobs set last_started_at = clock_timestamp() where job_key = j.job_key;
    begin
      perform set_config('lock_timeout', '5s', true);
      v_result := brain.run_job(j.job_key, p_actor);
      update brain.jobs
         set last_status = 'ok', last_sqlstate = null, last_result = v_result, consecutive_failures = 0,
             last_finished_at = clock_timestamp(),
             next_due_at = clock_timestamp() + make_interval(mins => interval_minutes)
       where job_key = j.job_key;
    exception
      when query_canceled then v_state := '57014';
      when others then v_state := sqlstate;
    end;
    if v_state is not null then
      v_failures := j.consecutive_failures + 1;
      update brain.jobs
         set consecutive_failures = v_failures, last_sqlstate = v_state, last_result = null,
             last_finished_at = clock_timestamp(),
             last_status = case when v_failures >= j.max_failures then 'sospeso' else 'errore' end,
             enabled = v_failures < j.max_failures,
             next_due_at = clock_timestamp() + make_interval(mins => j.interval_minutes * least(power(2, v_failures)::integer, 16))
       where job_key = j.job_key;
      if v_failures >= j.max_failures then
        perform brain.report_anomaly('job_sospeso', j.job_key, 'scheduler', 'operativo', 'P2',
          'Un lavoro pianificato è stato sospeso dopo guasti ripetuti',
          jsonb_build_object('lavoro', j.job_key, 'sqlstate', v_state, 'tentativi', v_failures),
          'Correggere la causa e riaccendere il lavoro dal proprietario.', true);
      end if;
    end if;
    v_done := v_done || jsonb_build_array(jsonb_build_object('lavoro', j.job_key, 'esito', coalesce(v_state, 'ok')));
    exit when v_state = '57014';
  end loop;
  return jsonb_build_object('esito', 'completato', 'eseguiti', v_done);
end;
$$;

create or replace function brain.scheduler_status()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  s brain.scheduler_state%rowtype;
  v_cron boolean := false;
begin
  select * into s from brain.scheduler_state;
  if to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''vinea-brain-tick'' and active)' into v_cron;
  end if;
  return jsonb_build_object(
    'pg_cron_installato', exists (select 1 from pg_catalog.pg_extension e where e.extname = 'pg_cron'),
    'job_cron_attivo', v_cron,
    'ultimo_giro', s.last_tick_at, 'ultimo_giro_da', s.last_tick_by, 'ultimo_giro_pianificato', s.last_scheduled_tick_at,
    'intervallo_giro_minuti', s.tick_expected_minutes,
    'stato', case when s.last_tick_at is null then 'mai_eseguito'
                  when s.last_tick_at < now() - make_interval(mins => 2 * s.tick_expected_minutes) then 'in_ritardo'
                  else 'recente' end,
    'lavori', (select coalesce(jsonb_agg(jsonb_build_object('chiave', x.job_key, 'descrizione', x.descrizione,
                 'acceso', x.enabled, 'intervallo_minuti', x.interval_minutes, 'ultimo', x.last_finished_at,
                 'esito', x.last_status, 'errore', x.last_sqlstate, 'guasti_consecutivi', x.consecutive_failures,
                 'prossimo', case when x.enabled then x.next_due_at end) order by x.job_key), '[]'::jsonb) from brain.jobs x));
end;
$$;

-- «Pianificato» e un fatto: il lavoro e acceso E un giro e arrivato DA pg_cron nel doppio dell'intervallo.
create or replace function brain.sentinel_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'pianificato', coalesce((select j.enabled from brain.jobs j where j.job_key = 'sentinel'), false)
       and coalesce((select x.last_scheduled_tick_at >= now() - make_interval(mins => 2 * x.tick_expected_minutes)
                       from brain.scheduler_state x), false),
    'intervallo_atteso_minuti', s.expected_interval_minutes,
    'ultima_esecuzione', (select jsonb_build_object('conclusa', r.finished_at, 'avviata_da', r.triggered_by,
          'controlli', r.checks_run, 'non_eseguiti', r.checks_failed, 'problemi', r.findings)
        from brain.sentinel_runs r where r.finished_at is not null order by r.id desc limit 1),
    'stato', case
       when not exists (select 1 from brain.sentinel_runs r where r.finished_at is not null) then 'mai_eseguito'
       when (select max(r.finished_at) from brain.sentinel_runs r)
            < now() - make_interval(mins => 2 * s.expected_interval_minutes) then 'in_ritardo'
       else 'recente' end)
    from brain.sentinel_settings s;
$$;

-- Controllo ESTERNO dello scheduler: due soli numeri, per un osservatore indipendente (da scegliere).
create or replace function brain.heartbeat_minimo()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'minuti_dall_ultimo_giro', (select floor(extract(epoch from now() - s.last_tick_at) / 60)::integer from brain.scheduler_state s),
    'minuti_dall_ultima_sentinel', (select floor(extract(epoch from now() - max(r.finished_at)) / 60)::integer from brain.sentinel_runs r));
$$;

create or replace function brain.sentinel_checks()
returns table (code text, source text, category text, severity text, titolo text, query text, azione text)
language sql immutable set search_path = '' as $$
  select * from (values
    ('superficie_catalogo', 'catalog.surface_audit', 'sicurezza', 'P1', 'Violazioni della superficie del catalogo',
     'select count(*) from catalog.surface_audit() where not ok',
     'Leggere catalog.surface_audit() e revocare il privilegio non previsto con una migration.'),
    ('prelievi_esito_incerto', 'public.balance_withdrawals', 'pagamenti', 'P1', 'Prelievi con esito incerto',
     'select count(*) from public.balance_withdrawals where stato = ''esito_incerto''',
     'Seguire docs/PRELIEVI_ESITO_INCERTO_RUNBOOK.md: nessun nuovo tentativo con una chiave diversa.'),
    ('prelievi_in_corso_fermi', 'public.balance_withdrawals', 'pagamenti', 'P1', 'Prelievi in corso da oltre 30 minuti',
     'select count(*) from public.balance_withdrawals where stato = ''in_corso'' and updated_at < now() - interval ''30 minutes''',
     'Verificare l''esecutore: un orfano va marcato incerto, mai fallito.'),
    ('rimborsi_dovuti_vecchi', 'private.accessori_pagamenti', 'pagamenti', 'P1', 'Rimborsi dovuti da oltre 72 ore',
     'select count(*) from private.accessori_pagamenti where stato = ''refund_due'' and aggiornato_at < now() - interval ''72 hours''',
     'Rivedere l''elenco amministrativo dei rimborsi dovuti.'),
    ('promozione_accesa', 'catalog.promotion_settings', 'catalogo', 'P1', 'Interruttore di promozione rimasto acceso',
     'select count(*) from catalog.promotion_settings s where s.enabled',
     'Fuori da una finestra approvata va spento (procedura 05_chiudi_finestra.sql).'),
    ('login_importazione_attivo', 'pg_roles', 'sicurezza', 'P2', 'Il login di importazione del catalogo può accedere',
     'select count(*) from pg_catalog.pg_roles where rolname = ''catalog_import_login'' and rolcanlogin',
     'Atteso solo durante un''importazione autorizzata; altrimenti va riportato a NOLOGIN.'),
    ('importazione_ferma', 'catalog.import_runs', 'catalogo', 'P2', 'Importazione in corso senza segnali da oltre 2 ore',
     'select count(*) from catalog.import_runs where status = ''running'' and heartbeat_at < now() - interval ''2 hours''',
     'Riconciliare l''importazione secondo il runbook prima di ripeterla.'),
    ('interruttore_ai_aperto', 'private.ai_budget_settings', 'ai', 'P2', 'Interruttore sui guasti del fornitore AI aperto',
     'select count(*) from private.ai_budget_settings where aperto_fino_a > now()',
     'Controllare il fornitore e i log delle function AI.'),
    ('budget_ai_quasi_esaurito', 'private.ai_consumo_giornaliero', 'ai', 'P3', 'Budget AI di oggi o del mese oltre l''80%',
     'select count(*) from private.ai_budget_settings s where (s.richieste_giorno > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno = (now() at time zone ''utc'')::date) >= 0.8 * s.richieste_giorno) or (s.richieste_mese > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno >= date_trunc(''month'', now() at time zone ''utc'')::date) >= 0.8 * s.richieste_mese) or (s.spesa_giorno_usd > 0 and (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0) from private.ai_chiamate k where (k.richiesta_il at time zone ''utc'')::date = (now() at time zone ''utc'')::date) >= 0.8 * s.spesa_giorno_usd) or (s.spesa_mese_usd > 0 and (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0) from private.ai_chiamate k where date_trunc(''month'', k.richiesta_il at time zone ''utc'') = date_trunc(''month'', now() at time zone ''utc'')) >= 0.8 * s.spesa_mese_usd)',
     'Valutare i tetti: li imposta solo il proprietario del database.'),
    ('proposte_catalogo_vecchie', 'catalog.contributions', 'catalogo', 'P3', 'Proposte al catalogo aperte da oltre 14 giorni',
     'select count(*) from catalog.contributions where status = ''aperta'' and created_at < now() - interval ''14 days''',
     'Rivedere la coda dal pannello del catalogo.'),
    ('conflitti_lwin_nativi', 'catalog.lwin_native_conflicts', 'catalogo', 'P2', 'Vini nativi che la fonte LWIN ora conosce',
     'select count(*) from catalog.lwin_native_conflicts(1000)',
     'Associare il LWIN o dichiarare l''omonimia prima di qualunque promozione.'),
    ('sorgente_monitor_ferma', 'brain.monitor_sources', 'operativo', 'P2', 'Fonti di monitoraggio accese senza segnali nei tempi attesi',
     'select count(*) from brain.monitor_sources m where m.enabled and not exists (select 1 from brain.monitor_signals s where s.source_key = m.source_key and s.received_at > now() - make_interval(mins => 2 * m.expected_interval_minutes))',
     'Verificare il mittente: l''assenza di segnali non è un esito verde.'),
    ('chiamate_ai_senza_consuntivo', 'private.ai_chiamate', 'ai', 'P3', 'Chiamate AI prenotate e mai consuntivate',
     'select count(*) from private.ai_chiamate where conclusa_il is null and richiesta_il < now() - interval ''15 minutes''',
     'Controllare le function AI: il costo resta contato al valore prenotato.')
  ) as c(code, source, category, severity, titolo, query, azione);
$$;

-- =============================================================================================
-- I — costi AI: tariffe, prenotazione sotto lo stesso lock, consuntivo
-- =============================================================================================
-- Nessuna tariffa e inserita qui: i prezzi li registra il proprietario, con la loro versione.
create table private.ai_tariffe (
  id bigint generated always as identity primary key,
  provider text not null check (provider ~ '^[a-z0-9_-]{1,40}$'),
  modello text not null check (modello ~ '^[A-Za-z0-9._:/-]{1,80}$'),
  versione text not null check (length(versione) between 1 and 80),
  input_per_milione numeric(12, 6) not null check (input_per_milione >= 0),
  output_per_milione numeric(12, 6) not null check (output_per_milione >= 0),
  valida_dal timestamptz not null,
  inserita_da text not null,
  inserita_il timestamptz not null default now(),
  unique (provider, modello, versione)
);

create table private.ai_chiamate (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('ai:chat', 'ai:pairing', 'ai:catalogo')),
  provider text not null,
  modello text not null,
  richiesta_il timestamptz not null default clock_timestamp(),
  conclusa_il timestamptz,
  esito text check (esito in ('ok', 'guasto_fornitore', 'errore_richiesta', 'interrotta_client', 'formato_non_valido')),
  token_input_stimati integer not null check (token_input_stimati >= 0),
  token_output_massimi integer not null check (token_output_massimi >= 0),
  token_input integer check (token_input >= 0),
  token_output integer check (token_output >= 0),
  tariffa_id bigint references private.ai_tariffe(id),
  -- tre valori distinti: prenotato (massimo), stimato (dai token veri), effettivo (solo da fattura)
  costo_riservato numeric(14, 6) check (costo_riservato >= 0),
  costo_stimato numeric(14, 6) check (costo_stimato >= 0),
  costo_effettivo numeric(14, 6) check (costo_effettivo >= 0)
);
create index ai_chiamate_giorno_idx on private.ai_chiamate (richiesta_il);
create index ai_chiamate_aperte_idx on private.ai_chiamate (richiesta_il) where conclusa_il is null;
create index ai_chiamate_tariffa_idx on private.ai_chiamate (tariffa_id) where tariffa_id is not null;
alter table private.ai_tariffe enable row level security;
alter table private.ai_chiamate enable row level security;
revoke all on private.ai_tariffe, private.ai_chiamate from public, anon, authenticated, service_role;

alter table private.ai_budget_settings
  add column spesa_giorno_usd numeric(12, 4) check (spesa_giorno_usd >= 0),
  add column spesa_mese_usd numeric(12, 4) check (spesa_mese_usd >= 0);

-- Prenota: la riga singleton resta bloccata fino al commit, quindi due richieste concorrenti non superano nessun
-- tetto. Un rifiuto monetario non consuma una richiesta. Chiuso per difetto sui tetti di richieste (WI-010).
create or replace function public.ai_budget_prenota(p_scope text, p_provider text, p_modello text,
  p_token_input integer, p_token_output_max integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s private.ai_budget_settings%rowtype;
  t private.ai_tariffe%rowtype;
  v_cost numeric(14, 6);
  v_day timestamptz := date_trunc('day', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_month timestamptz := date_trunc('month', clock_timestamp() at time zone 'utc') at time zone 'utc';
  v_refusal text;
  v_outcome text;
  v_id uuid;
begin
  if p_provider is null or p_modello is null or p_token_input is null or p_token_input < 0
     or p_token_output_max is null or p_token_output_max < 0 or p_token_input > 2000000 or p_token_output_max > 200000 then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  select * into strict s from private.ai_budget_settings where singleton for update;
  select * into t from private.ai_tariffe x
   where x.provider = p_provider and x.modello = p_modello and x.valida_dal <= clock_timestamp()
   order by x.valida_dal desc, x.id desc limit 1;
  if t.id is not null then
    v_cost := ceil((p_token_input * t.input_per_milione + p_token_output_max * t.output_per_milione)) / 1000000;
  end if;
  if s.richieste_giorno is not null and s.richieste_mese is not null
     and (s.spesa_giorno_usd is not null or s.spesa_mese_usd is not null) then
    if t.id is null then
      v_refusal := 'tariffa_mancante';
    elsif s.spesa_giorno_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_day) > s.spesa_giorno_usd then
      v_refusal := 'spesa_giorno_esaurita';
    elsif s.spesa_mese_usd is not null and v_cost + (select coalesce(sum(coalesce(k.costo_effettivo, k.costo_stimato, k.costo_riservato)), 0)
            from private.ai_chiamate k where k.richiesta_il >= v_month) > s.spesa_mese_usd then
      v_refusal := 'spesa_mese_esaurita';
    end if;
  end if;
  if v_refusal is not null then
    insert into private.ai_consumo_giornaliero as c (giorno, scope, rifiutate_budget)
    values ((clock_timestamp() at time zone 'utc')::date, p_scope, 1)
    on conflict (giorno, scope) do update set rifiutate_budget = c.rifiutate_budget + 1;
    return jsonb_build_object('esito', v_refusal);
  end if;
  v_outcome := public.ai_budget_consuma(p_scope);
  if v_outcome <> 'consentito' then
    return jsonb_build_object('esito', v_outcome);
  end if;
  insert into private.ai_chiamate (scope, provider, modello, token_input_stimati, token_output_massimi, tariffa_id, costo_riservato)
  values (p_scope, p_provider, p_modello, p_token_input, p_token_output_max, t.id, v_cost)
  returning id into v_id;
  return jsonb_build_object('esito', 'consentito', 'richiesta_id', v_id);
end;
$$;

-- Consuntivo, una volta sola. Senza i token veri il costo resta quello prenotato (mai sottostimato).
create or replace function public.ai_budget_consuntivo(p_richiesta uuid, p_esito text, p_token_input integer default null,
  p_token_output integer default null)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_richiesta is null or p_esito is null
     or p_esito not in ('ok', 'guasto_fornitore', 'errore_richiesta', 'interrotta_client', 'formato_non_valido')
     or p_token_input < 0 or p_token_output < 0 then
    raise exception 'ai_budget: parametri non validi' using errcode = '22023';
  end if;
  update private.ai_chiamate k
     set conclusa_il = clock_timestamp(), esito = p_esito, token_input = p_token_input, token_output = p_token_output,
         costo_stimato = case when p_token_input is not null and p_token_output is not null and k.tariffa_id is not null then
           (select ceil((p_token_input * t.input_per_milione + p_token_output * t.output_per_milione)) / 1000000
              from private.ai_tariffe t where t.id = k.tariffa_id) end
   where k.id = p_richiesta and k.conclusa_il is null;
  return found;
end;
$$;

create or replace function public.ai_budget_stato()
returns jsonb language sql stable security definer set search_path = '' as $$
  with oggi as (select (now() at time zone 'utc')::date as g),
  mese as (
    select c.* from private.ai_consumo_giornaliero c, oggi
     where c.giorno >= date_trunc('month', oggi.g)::date and c.giorno <= oggi.g),
  chiamate as (
    select k.*, (k.richiesta_il at time zone 'utc')::date = oggi.g as di_oggi from private.ai_chiamate k, oggi
     where (k.richiesta_il at time zone 'utc')::date >= date_trunc('month', oggi.g)::date)
  select jsonb_build_object(
    'configurato', s.richieste_giorno is not null and s.richieste_mese is not null,
    'richieste_giorno', s.richieste_giorno, 'richieste_mese', s.richieste_mese,
    'interruttore_aperto_fino_a', case when s.aperto_fino_a > now() then s.aperto_fino_a end,
    'oggi', (select jsonb_build_object('consentite', coalesce(sum(m.consentite), 0),
               'rifiutate_budget', coalesce(sum(m.rifiutate_budget), 0),
               'rifiutate_interruttore', coalesce(sum(m.rifiutate_interruttore), 0),
               'guasti_fornitore', coalesce(sum(m.guasti_fornitore), 0)) from mese m, oggi where m.giorno = oggi.g),
    'mese', (select jsonb_build_object('consentite', coalesce(sum(m.consentite), 0),
               'rifiutate_budget', coalesce(sum(m.rifiutate_budget), 0),
               'guasti_fornitore', coalesce(sum(m.guasti_fornitore), 0)) from mese m),
    'spesa', jsonb_build_object(
       'limite_giorno_usd', s.spesa_giorno_usd, 'limite_mese_usd', s.spesa_mese_usd,
       'stimata_oggi_usd', (select coalesce(sum(costo_stimato), 0) from chiamate where di_oggi),
       'riservata_aperta_oggi_usd', (select coalesce(sum(costo_riservato), 0) from chiamate where di_oggi and costo_stimato is null),
       'stimata_mese_usd', (select coalesce(sum(costo_stimato), 0) from chiamate),
       -- nulla finche non arriva una fattura: la stima non e un addebito
       'effettiva_mese_usd', (select sum(costo_effettivo) from chiamate),
       'chiamate_senza_tariffa_mese', (select count(*) from chiamate where tariffa_id is null),
       'per_funzione', (select coalesce(jsonb_agg(to_jsonb(x) order by x.funzione, x.modello), '[]'::jsonb) from (
           select scope as funzione, modello, count(*) as chiamate, coalesce(sum(token_input), 0) as token_input,
                  coalesce(sum(token_output), 0) as token_output, coalesce(sum(costo_stimato), 0) as stimato_usd
             from chiamate group by scope, modello) x)),
    'tariffe_registrate', (select count(*) from private.ai_tariffe))
    from private.ai_budget_settings s where s.singleton;
$$;

revoke all on function public.ai_budget_prenota(text, text, text, integer, integer),
  public.ai_budget_consuntivo(uuid, text, integer, integer), public.ai_budget_stato() from public, anon, authenticated;
grant execute on function public.ai_budget_prenota(text, text, text, integer, integer),
  public.ai_budget_consuntivo(uuid, text, integer, integer), public.ai_budget_stato() to service_role;

-- =============================================================================================
-- F — aggiornamento periodico LWIN: che cosa deve guardare il curatore (sola lettura)
-- =============================================================================================
create or replace function catalog.update_summary()
returns jsonb language sql stable security definer set search_path = '' as $$
  with fuori as (
    select w.id, w.name, w.lwin7, w.origin, r.status as stato_fonte, r.removed_from_source_at is not null as rimosso,
           l.final_external_id as destinazione_lwin,
           (select x.id from catalog.wines x where x.lwin7 = l.final_external_id) as destinazione_wine_id
      from catalog.wines w
      join catalog.source_records r on r.id = coalesce(w.source_record_id, w.lwin_assigned_record_id)
      left join catalog.record_links l on l.source_id = r.source_id and l.from_external_id = r.external_id and l.link_state = 'active'
     where w.status = 'active' and (r.status <> 'Live' or r.removed_from_source_at is not null)),
  cambiati as (
    select w.id, w.name, w.lwin7,
           jsonb_strip_nulls(jsonb_build_object(
             'colore', case when w.colour is distinct from nullif(r.payload ->> 'colour', '') then
                         jsonb_build_object('catalogo', w.colour, 'fonte', r.payload ->> 'colour') end,
             'denominazione', case when r.payload ? 'designation' and w.designation is distinct from nullif(r.payload ->> 'designation', '') then
                         jsonb_build_object('catalogo', w.designation, 'fonte', r.payload ->> 'designation') end,
             'classificazione', case when r.payload ? 'classification' and w.classification is distinct from nullif(r.payload ->> 'classification', '') then
                         jsonb_build_object('catalogo', w.classification, 'fonte', r.payload ->> 'classification') end)) as differenze
      from catalog.wines w join catalog.source_records r on r.id = w.source_record_id
     where w.status = 'active' and w.origin = 'promotion' and r.status = 'Live'
       and (w.colour is distinct from nullif(r.payload ->> 'colour', '')
            or (r.payload ? 'designation' and w.designation is distinct from nullif(r.payload ->> 'designation', ''))
            or (r.payload ? 'classification' and w.classification is distinct from nullif(r.payload ->> 'classification', '')))
     limit 1001)
  select jsonb_build_object(
    'ultima_importazione', (select jsonb_build_object('seq', i.seq, 'stato', i.status, 'conclusa', i.finished_at,
          'file', n.file_name, 'sha256', n.file_sha256, 'righe', i.rows_read, 'conteggi', i.counts)
        from catalog.import_runs i join catalog.import_snapshots n on n.id = i.snapshot_id order by i.seq desc limit 1),
    'versione_completa', (select jsonb_build_object('sha256', cv.complete_sha256, 'completata', cv.complete_at,
          'import_in_corso', cv.attempt_in_progress)
        from catalog.sources s join catalog.complete_versions cv on cv.source_id = s.id where s.code = 'LIVEX-LWIN7'),
    'canonici_non_piu_live', jsonb_build_object('conteggio', (select count(*) from fuori),
        'esempi', coalesce((select jsonb_agg(jsonb_build_object('wine_id', f.id, 'nome', f.name, 'lwin7', f.lwin7,
              'origine', f.origin, 'stato_fonte', f.stato_fonte, 'rimosso_dalla_fonte', f.rimosso,
              'destinazione_lwin', f.destinazione_lwin, 'destinazione_wine_id', f.destinazione_wine_id) order by f.lwin7)
            from (select * from fuori order by lwin7 limit 20) f), '[]'::jsonb)),
    -- proposte di aggiornamento: si accettano solo con le rivendicazioni del curatore, mai in automatico
    'attributi_cambiati', jsonb_build_object('conteggio', least((select count(*) from cambiati), 1000),
        'oltre', (select count(*) from cambiati) > 1000,
        'esempi', coalesce((select jsonb_agg(jsonb_build_object('wine_id', c.id, 'nome', c.name, 'lwin7', c.lwin7,
              'differenze', c.differenze) order by c.lwin7) from (select * from cambiati order by lwin7 limit 20) c), '[]'::jsonb)),
    'conflitti_nativi', coalesce((select jsonb_agg(to_jsonb(x)) from catalog.lwin_native_conflicts(50) x), '[]'::jsonb),
    'omonimie_dichiarate', (select count(*) from catalog.native_lwin_distinct),
    'regola', (select jsonb_build_object('stato', r.status,
          'impronta_invariata', r.approved_fingerprint is not distinct from catalog.promotion_logic_fingerprint(r.version))
        from catalog.promotion_rules r where r.version = 'lwin-conservative-v1'));
$$;
revoke all on function catalog.update_summary() from public, anon, authenticated, service_role, catalog_loader;
grant execute on function catalog.update_summary() to catalog_curator;

create or replace function public.catalogo_admin_aggiornamento()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return catalog.update_summary();
end;
$$;
revoke all on function public.catalogo_admin_aggiornamento() from public, anon, authenticated, service_role;
grant execute on function public.catalogo_admin_aggiornamento() to authenticated;

-- =============================================================================================
-- J — cruscotto e rapporto periodico (solo dati letti; ogni stato e dichiarato)
-- =============================================================================================
create or replace function brain.monitor_state()
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('chiave', m.source_key, 'descrizione', m.descrizione,
           'ultimo', u.observed_at, 'ultimo_stato', u.status, 'riferimento', u.evidence_ref,
           'intervallo_atteso_minuti', m.expected_interval_minutes,
           'stato', case when not m.enabled then 'disattivata'
                         when u.id is null then 'non_verificata'
                         when u.received_at < now() - make_interval(mins => 2 * m.expected_interval_minutes) then 'in_ritardo'
                         when u.status = 'guasto' then 'errore'
                         when u.status = 'degradato' then 'degradata'
                         when u.status = 'ok' then 'disponibile'
                         else 'non_verificata' end) order by m.source_key), '[]'::jsonb)
    from brain.monitor_sources m
    left join lateral (select s.* from brain.monitor_signals s where s.source_key = m.source_key
                        order by s.observed_at desc, s.id desc limit 1) u on true;
$$;

create or replace function public.azienda_admin_riepilogo()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_sources jsonb;
begin
  perform private.catalog_admin_richiedi();
  v_sources := brain.monitor_state();
  return jsonb_build_object(
    'sentinel', brain.sentinel_status(),
    'scheduler', brain.scheduler_status(),
    'anomalie', (select jsonb_build_object(
        'aperte', count(*) filter (where status in ('aperta', 'presa_in_carico')),
        'ignorate', count(*) filter (where status = 'ignorata'),
        'p0', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P0'),
        'p1', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P1'),
        'p2', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P2'),
        'p3', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P3')) from brain.anomalies),
    'task', (select jsonb_build_object(
        'da_approvare', count(*) filter (where status = 'in_approvazione'),
        'approvati', count(*) filter (where status = 'approvato'),
        'in_attesa', count(*) filter (where status = 'in_attesa'),
        'assegnati', count(*) filter (where status = 'assegnato'),
        'bloccati', count(*) filter (where status = 'fallito' or (status = 'assegnato' and lease_expires_at < now())),
        'falliti', count(*) filter (where status = 'fallito')) from brain.tasks),
    'evidenze', (select count(*) from brain.task_evidence),
    -- «operativo» e un fatto: acceso, con credenziale e con una presa nelle ultime 24 ore
    'agenti', jsonb_build_object(
        'registrati', (select count(*) from brain.agents),
        'accesi', (select count(*) from brain.agents where enabled),
        'operativi', (select count(*) from brain.agents where enabled and last_claim_at > now() - interval '24 hours'),
        'elenco', (select coalesce(jsonb_agg(jsonb_build_object('chiave', a.agent_key, 'descrizione', a.descrizione,
              'tipi', a.task_types, 'ultima_presa', a.last_claim_at,
              'stato', case when not a.enabled then 'spento'
                            when a.expires_at <= now() then 'credenziale_scaduta'
                            when a.last_claim_at > now() - interval '24 hours' then 'operativo'
                            else 'acceso_senza_attivita' end,
              'task_in_corso', (select count(*) from brain.tasks t where t.lease_agent = a.agent_key)) order by a.agent_key), '[]'::jsonb)
            from brain.agents a)),
    'catalogo', public.catalogo_admin_riepilogo(),
    'coda_catalogo', jsonb_build_object(
        'proposte_senza_task', (select count(*) from catalog.contributions c where c.status = 'aperta'
            and not brain.contribution_has_task(c.id)),
        'acquisizioni_fallite', (select count(*) from catalog.intake_failures)),
    'ai', public.ai_budget_stato(),
    'fonti', v_sources,
    -- compatibilita col cruscotto precedente: cio che non e collegato resta dichiarato
    'sorgenti_non_collegate', (select coalesce(jsonb_agg(f ->> 'descrizione'), '[]'::jsonb)
        from jsonb_array_elements(v_sources) f where f ->> 'stato' in ('disattivata', 'non_verificata'))
      || jsonb_build_array('Fatture dei fornitori AI (la spesa mostrata è una stima)'));
end;
$$;

create or replace function public.azienda_admin_rapporto(p_giorni integer default 7)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_days integer := least(greatest(coalesce(p_giorni, 7), 1), 90);
  v_from timestamptz;
begin
  perform private.catalog_admin_richiedi();
  v_from := now() - make_interval(days => v_days);
  return jsonb_build_object('giorni', v_days, 'generato_il', now(),
    'anomalie_aperte', (select coalesce(jsonb_agg(jsonb_build_object('severita', g.severity, 'categoria', g.category,
          'conteggio', g.n, 'codici', g.codici) order by g.severity, g.category), '[]'::jsonb)
        from (select severity, category, count(*) as n, to_jsonb((array_agg(distinct code))[1:10]) as codici
                from brain.anomalies where status in ('aperta', 'presa_in_carico') group by severity, category) g),
    'nel_periodo', jsonb_build_object(
        'aperte', (select count(*) from brain.anomalies where first_seen_at >= v_from),
        'risolte', (select count(*) from brain.anomalies where resolved_at >= v_from),
        'decisioni', (select count(*) from brain.events where event_type = 'task.decisione' and recorded_at >= v_from),
        'chiusure_per_regola', (select count(*) from brain.events where event_type = 'task.chiusura_consentita' and recorded_at >= v_from),
        'esecuzioni_sentinel', (select count(*) from brain.sentinel_runs where finished_at >= v_from)),
    'segnali', (select jsonb_build_object('totali', count(*), 'guasti', count(*) filter (where status = 'guasto'),
          'degradati', count(*) filter (where status = 'degradato')) from brain.monitor_signals where received_at >= v_from),
    'lavori_con_problemi', (select coalesce(jsonb_agg(jsonb_build_object('chiave', job_key, 'esito', last_status,
          'errore', last_sqlstate) order by job_key), '[]'::jsonb) from brain.jobs where last_status in ('errore', 'sospeso')),
    'ai_richieste', (select coalesce(sum(consentite), 0) from private.ai_consumo_giornaliero where giorno >= (v_from at time zone 'utc')::date));
end;
$$;

revoke all on function public.azienda_admin_riepilogo(), public.azienda_admin_rapporto(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.azienda_admin_riepilogo(), public.azienda_admin_rapporto(integer) to authenticated;

-- Privilegi delle funzioni del brain: tutto revocato, poi le sole porte elencate.
revoke all on all functions in schema brain
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;
grant execute on function brain.claim_task(integer), brain.add_evidence(uuid, uuid, text, jsonb),
  brain.finish_task(uuid, uuid, boolean, jsonb), brain.renew_lease(uuid, uuid, integer), brain.agent_context(uuid, uuid),
  brain.close_if_allowed(uuid, uuid), brain.payload_ammesso(jsonb) to brain_worker;
grant execute on function brain.ingest_signal(text, text, text, timestamptz, text, jsonb) to brain_ingest;
grant execute on function brain.heartbeat_minimo(), brain.payload_ammesso(jsonb) to brain_monitor_read;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-015B: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
