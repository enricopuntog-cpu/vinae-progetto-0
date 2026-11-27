-- WI-016 C — contratto di orchestrazione del Company Brain e agenti Wine Intelligence.
--
-- Si estende `brain.*` (nessun framework parallelo). Nulla viene registrato o acceso: nessun agente, nessun lavoro,
-- nessuna richiesta di verifica, nessuna lettura di prezzi dal pannello.
--
--   * dipendenze fra task (senza cicli), attesa crescente dopo un guasto, limiti per operazione: profondità, figli,
--     task totali e coda per tipo; un agente può derivare solo i tipi che il proprietario gli assegna e mai un tipo
--     già presente nella propria catena (niente ping-pong fra agenti);
--   * comunicazione fra agenti SOLO tramite risultati strutturati delle dipendenze e del genitore, più la memoria
--     pertinente delle decisioni passate sullo stesso soggetto; nessun testo libero, nessun dato personale;
--   * Wine Research: informazioni solo da fonti AUTORIZZATE con diritti dichiarati, con provenienza, data e
--     attendibilità; entrano come rivendicazioni PROPOSTE e le decide il curatore;
--   * Authenticity Assistant: richieste di verifica su segnali strutturati, mai immagini, mai un esito di autenticità;
--   * Price Intelligence: porta amministrativa sulle osservazioni GIÀ minimizzate dello storico, spenta;
--   * Sommelier: scheda documentata (annate e rivendicazioni accettate con fonte) per il solo codice richiesto.

-- =============================================================================================
-- 1. Orchestrazione
-- =============================================================================================
alter table brain.tasks
  add column parent_task_id uuid references brain.tasks(id),
  add column root_task_id uuid references brain.tasks(id),
  add column depth smallint not null default 0 check (depth between 0 and 5),
  add column not_before timestamptz,
  add constraint tasks_tree_shape check ((parent_task_id is null) = (root_task_id is null) and (parent_task_id is null) = (depth = 0));
create index tasks_parent_idx on brain.tasks (parent_task_id) where parent_task_id is not null;
create index tasks_root_idx on brain.tasks (root_task_id) where root_task_id is not null;
create index tasks_type_pending_idx on brain.tasks (task_type) where status = 'in_attesa';

alter table brain.agents
  add column spawn_types text[] not null default '{}',
  -- ultima richiesta di lavoro, anche a coda vuota: è la prova che un esecutore esiste davvero
  add column last_poll_at timestamptz;

create table brain.task_dependencies (
  task_id uuid not null references brain.tasks(id),
  depends_on uuid not null references brain.tasks(id),
  created_at timestamptz not null default now(),
  primary key (task_id, depends_on),
  check (task_id <> depends_on)
);
create index task_dependencies_depends_idx on brain.task_dependencies (depends_on);
alter table brain.task_dependencies enable row level security;
revoke all on brain.task_dependencies from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

create or replace function brain.task_dependencies_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'brain: una dipendenza non si modifica' using errcode = '55000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('brain.task_dependencies', 0));
  if exists (
       with recursive su(id) as (
         select d.depends_on from brain.task_dependencies d where d.task_id = new.depends_on
         union
         select d.depends_on from brain.task_dependencies d join su on d.task_id = su.id)
       select 1 from su where su.id = new.task_id) then
    raise exception 'brain: la dipendenza creerebbe un ciclo' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger task_dependencies_guard before insert or update on brain.task_dependencies
  for each row execute function brain.task_dependencies_guard();

create table brain.orchestration_settings (
  singleton boolean primary key default true check (singleton),
  max_depth smallint not null default 3 check (max_depth between 0 and 5),
  max_children_per_task smallint not null default 5 check (max_children_per_task between 0 and 50),
  max_tasks_per_operation smallint not null default 20 check (max_tasks_per_operation between 1 and 200),
  max_pending_per_type integer not null default 2000 check (max_pending_per_type between 1 and 100000),
  retry_backoff_max_minutes integer not null default 60 check (retry_backoff_max_minutes between 0 and 1440)
);
insert into brain.orchestration_settings default values;
alter table brain.orchestration_settings enable row level security;
revoke all on brain.orchestration_settings from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;

-- Una dipendenza è soddisfatta se eseguita (completato) o chiusa dalla regola perché non restava nulla da decidere.
create or replace function brain.dependencies_met(p_task uuid)
returns boolean language sql stable set search_path = '' as $$
  select not exists (
    select 1 from brain.task_dependencies d join brain.tasks x on x.id = d.depends_on
     where d.task_id = p_task
       and not (x.status = 'completato' or (x.status = 'annullato' and x.decided_by is not distinct from 'regola:chiusura_consentita')));
$$;

-- Una dipendenza fallita, respinta o annullata da una persona non si sbloccherà più: chi dipende si chiude, motivato.
create or replace function brain.cancel_blocked_tasks()
returns integer language plpgsql volatile set search_path = '' as $$
declare
  r record;
  v_n integer := 0;
begin
  for r in
    select t.id, t.correlation_id from brain.tasks t
     where t.status = 'in_attesa'
       and exists (select 1 from brain.task_dependencies d join brain.tasks x on x.id = d.depends_on
                    where d.task_id = t.id and x.status in ('respinto', 'fallito', 'annullato')
                      and x.decided_by is distinct from 'regola:chiusura_consentita')
     order by t.id limit 200 for update of t skip locked
  loop
    update brain.tasks
       set status = 'annullato', decided_by = 'regola:dipendenza_non_riuscita', decided_at = clock_timestamp(),
           decision_note = 'Una dipendenza non è andata a buon fine.', updated_at = now(), version = version + 1
     where id = r.id;
    perform brain.record_event('task.dipendenza_non_riuscita', 'brain', r.correlation_id, null, 'task', r.id::text, '{}'::jsonb);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Coda limitata per tipo: oltre il limite non si accoda e l'anomalia lo dice. La deduplicazione viene prima.
create or replace function brain.enqueue_task(p_type text, p_titolo text, p_priority integer default 2,
  p_payload jsonb default '{}'::jsonb, p_dedup text default null, p_requires_approval boolean default true,
  p_correlation uuid default null)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id uuid;
  v_max integer;
begin
  if p_dedup is not null then
    select t.id into v_id from brain.tasks t where t.dedup_key = p_dedup;
    if v_id is not null then return v_id; end if;
  end if;
  select s.max_pending_per_type into v_max from brain.orchestration_settings s;
  if (select count(*) from brain.tasks t where t.task_type = p_type and t.status = 'in_attesa') >= v_max then
    perform brain.report_anomaly('coda_satura', p_type, 'brain', 'operativo', 'P2',
      'Coda del brain oltre il limite per tipo', jsonb_build_object('tipo', p_type, 'limite', v_max),
      'Verificare che un esecutore consumi la coda: i nuovi task di questo tipo non vengono accodati.', true);
    return null;
  end if;
  insert into brain.tasks (task_type, titolo, priority, payload, dedup_key, requires_approval, correlation_id)
  values (p_type, p_titolo, coalesce(p_priority, 2), coalesce(p_payload, '{}'::jsonb), p_dedup,
          coalesce(p_requires_approval, true), coalesce(p_correlation, gen_random_uuid()))
  on conflict (dedup_key) do nothing
  returning id into v_id;
  if v_id is null then
    select t.id into v_id from brain.tasks t where t.dedup_key = p_dedup;
  end if;
  return v_id;
end;
$$;

-- Come WI-015A, con ultima richiesta, attesa dopo un guasto e dipendenze.
create or replace function brain.claim_task_core(p_agent text, p_lease_seconds integer)
returns table (task_id uuid, lease_token uuid, task_type text, titolo text, payload jsonb, correlation_id uuid, attempt integer)
language plpgsql volatile set search_path = '' as $$
#variable_conflict use_column
declare
  a brain.agents%rowtype;
  v_id uuid;
  v_token uuid := gen_random_uuid();
begin
  -- La riga dell'agente serializza le sue prese: limite orario e un solo lease attivo per agente.
  select * into a from brain.agents x where x.agent_key = p_agent for update;
  if not found or not a.enabled or brain.is_suspended('agente', p_agent) then
    raise exception 'brain: agente inesistente, spento o sospeso' using errcode = '42501';
  end if;
  update brain.agents x set last_poll_at = clock_timestamp() where x.agent_key = p_agent;
  if a.claim_window_start is null or a.claim_window_start < clock_timestamp() - interval '1 hour' then
    a.claim_window_start := clock_timestamp();
    a.claims_in_window := 0;
  end if;
  if a.claims_in_window >= a.max_claims_per_hour then
    raise exception 'brain: limite orario di prese raggiunto' using errcode = '53400';
  end if;
  perform brain.reap_expired_leases();
  perform brain.cancel_blocked_tasks();
  if exists (select 1 from brain.tasks t where t.lease_agent = p_agent and t.status = 'assegnato') then
    return;
  end if;
  select t.id into v_id from brain.tasks t
   where t.status = 'in_attesa' and t.task_type = any (a.task_types)
     and (t.not_before is null or t.not_before <= clock_timestamp())
     and brain.dependencies_met(t.id)
   order by t.priority, t.created_at, t.id
   limit 1 for update skip locked;
  if v_id is null then
    return;
  end if;
  update brain.agents x set claim_window_start = a.claim_window_start, claims_in_window = a.claims_in_window + 1,
         last_claim_at = clock_timestamp()
   where x.agent_key = p_agent;
  update brain.tasks t
     set status = 'assegnato', lease_agent = p_agent, lease_token = v_token, lease_started_at = clock_timestamp(),
         lease_expires_at = clock_timestamp() + make_interval(secs => least(greatest(coalesce(p_lease_seconds, 300), 30), 3600)),
         attempts = t.attempts + 1, not_before = null, updated_at = now(), version = t.version + 1
   where t.id = v_id;
  perform brain.record_event('task.preso', 'agent:' || p_agent, (select t.correlation_id from brain.tasks t where t.id = v_id),
    'presa:' || v_id::text || ':' || v_token::text, 'task', v_id::text, '{}'::jsonb);
  return query select t.id, v_token, t.task_type, t.titolo, t.payload, t.correlation_id, t.attempts::integer
    from brain.tasks t where t.id = v_id;
end;
$$;

create or replace function brain.finish_task_core(p_agent text, p_task uuid, p_lease uuid, p_success boolean, p_proposta jsonb)
returns text language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  v_status text;
  v_backoff integer;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if p_success is null then
    raise exception 'brain: esito mancante' using errcode = '22023';
  end if;
  v_status := case when not p_success then (case when t.attempts >= t.max_attempts then 'fallito' else 'in_attesa' end)
                   else 'in_approvazione' end;
  select s.retry_backoff_max_minutes into v_backoff from brain.orchestration_settings s;
  update brain.tasks
     set status = v_status, proposta = coalesce(p_proposta, proposta), lease_agent = null, lease_token = null,
         lease_expires_at = null, lease_started_at = null,
         not_before = case when v_status = 'in_attesa' and v_backoff > 0
                           then clock_timestamp() + make_interval(mins => least(power(2, t.attempts)::integer, v_backoff)) end,
         updated_at = now(), version = version + 1
   where id = p_task;
  perform brain.record_event('task.esito', 'agent:' || p_agent, t.correlation_id,
    'task:' || p_task::text || ':' || t.attempts::text, 'task', p_task::text, jsonb_build_object('stato', v_status));
  return v_status;
end;
$$;

-- Un agente deriva un task figlio SOLO dal proprio lease, solo dei tipi che gli sono assegnati, entro i limiti
-- dell'operazione. La chiave è nello spazio dell'operazione: ripetere la stessa richiesta restituisce lo stesso task.
create or replace function brain.spawn_task_core(p_agent text, p_task uuid, p_lease uuid, p_type text, p_titolo text,
  p_payload jsonb, p_key text, p_depend boolean)
returns uuid language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  s brain.orchestration_settings%rowtype;
  v_root uuid;
  v_id uuid;
  v_dedup text;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if p_key is null or p_key !~ '^[A-Za-z0-9_.:-]{1,80}$' then
    raise exception 'brain: chiave del task derivato non valida' using errcode = '22023';
  end if;
  if not exists (select 1 from brain.agents a where a.agent_key = p_agent and p_type = any (a.spawn_types)) then
    raise exception 'brain: tipo di task non derivabile da questo agente' using errcode = '42501';
  end if;
  v_root := coalesce(t.root_task_id, t.id);
  v_dedup := 'derivato:' || v_root::text || ':' || p_type || ':' || p_key;
  select x.id into v_id from brain.tasks x where x.dedup_key = v_dedup;
  if v_id is not null then return v_id; end if;
  -- una sola derivazione per operazione alla volta: i limiti sono conteggi
  perform pg_advisory_xact_lock(hashtextextended('brain.operation:' || v_root::text, 0));
  select * into s from brain.orchestration_settings;
  if exists (
       with recursive catena(id, task_type, parent_task_id) as (
         select x.id, x.task_type, x.parent_task_id from brain.tasks x where x.id = t.id
         union all
         select x.id, x.task_type, x.parent_task_id from brain.tasks x join catena c on x.id = c.parent_task_id)
       select 1 from catena where catena.task_type = p_type) then
    raise exception 'brain: tipo già presente nella catena, un ciclo non è ammesso' using errcode = '22023';
  end if;
  if t.depth + 1 > s.max_depth then
    raise exception 'brain: profondità massima dell''operazione raggiunta' using errcode = '53400';
  end if;
  if (select count(*) from brain.tasks x where x.parent_task_id = t.id) >= s.max_children_per_task then
    raise exception 'brain: troppi task derivati da un solo task' using errcode = '53400';
  end if;
  if 1 + (select count(*) from brain.tasks x where x.root_task_id = v_root) >= s.max_tasks_per_operation then
    raise exception 'brain: limite di task dell''operazione raggiunto' using errcode = '53400';
  end if;
  if (select count(*) from brain.tasks x where x.task_type = p_type and x.status = 'in_attesa') >= s.max_pending_per_type then
    raise exception 'brain: coda satura per questo tipo' using errcode = '53400';
  end if;
  insert into brain.tasks (task_type, titolo, priority, payload, dedup_key, requires_approval, correlation_id,
                           parent_task_id, root_task_id, depth)
  values (p_type, p_titolo, t.priority, coalesce(p_payload, '{}'::jsonb), v_dedup, true, t.correlation_id,
          t.id, v_root, t.depth + 1)
  returning id into v_id;
  -- `p_depend`: il figlio parte solo dopo che il genitore è stato eseguito (non solo proposto)
  if coalesce(p_depend, true) then
    insert into brain.task_dependencies (task_id, depends_on) values (v_id, t.id);
  end if;
  perform brain.record_event('task.derivato', 'agent:' || p_agent, t.correlation_id, 'derivato:' || v_id::text, 'task',
    v_id::text, jsonb_build_object('tipo', p_type, 'profondita', t.depth + 1));
  return v_id;
end;
$$;

create or replace function brain.spawn_task(p_task uuid, p_lease uuid, p_type text, p_titolo text, p_payload jsonb,
  p_key text, p_depend boolean default true)
returns uuid language sql volatile security definer set search_path = '' as $$
  select brain.spawn_task_core(brain.current_agent(), p_task, p_lease, p_type, p_titolo, p_payload, p_key, p_depend);
$$;

-- Revoca di un'intera operazione: tutti i task non conclusi, lease compresi.
create or replace function brain.cancel_operation(p_task uuid, p_reason text, p_actor text)
returns integer language plpgsql volatile set search_path = '' as $$
declare
  v_root uuid;
  v_corr uuid;
  v_n integer;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'brain: servono esecutore e motivo' using errcode = '22023';
  end if;
  select coalesce(t.root_task_id, t.id), t.correlation_id into v_root, v_corr from brain.tasks t where t.id = p_task;
  if v_root is null then
    raise exception 'brain: task inesistente' using errcode = 'P0002';
  end if;
  update brain.tasks
     set status = 'annullato', decided_by = btrim(p_actor), decided_at = clock_timestamp(),
         decision_note = left(btrim(p_reason), 1000), lease_agent = null, lease_token = null, lease_expires_at = null,
         lease_started_at = null, updated_at = now(), version = version + 1
   where (id = v_root or root_task_id = v_root) and status in ('in_attesa', 'assegnato', 'in_approvazione', 'approvato');
  get diagnostics v_n = row_count;
  perform brain.record_event('operazione.annullata', 'brain', v_corr, null, 'task', v_root::text,
    jsonb_build_object('esecutore', btrim(p_actor), 'annullati', v_n));
  return v_n;
end;
$$;

-- Memoria pertinente: solo risultati strutturati delle dipendenze e del genitore, più l'esito delle decisioni passate
-- sullo STESSO soggetto. Nessun testo libero (le note delle persone restano fuori).
create or replace function brain.task_memory(p_task uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  v_key text;
  v_previous jsonb := '[]'::jsonb;
begin
  select * into t from brain.tasks x where x.id = p_task;
  if not found then return '{}'::jsonb; end if;
  if t.task_type = 'catalogo.proposta' then
    select c.identity_key into v_key from catalog.contributions c where c.id = (t.payload ->> 'contributo_id')::bigint;
    select coalesce(jsonb_agg(jsonb_build_object('contributo_id', c.id, 'stato', c.status, 'deciso', c.reviewed_at,
             'quarantena', c.quarantine_reason) order by c.reviewed_at desc nulls last), '[]'::jsonb) into v_previous
      from (select * from catalog.contributions o
             where o.identity_key = v_key and o.id <> (t.payload ->> 'contributo_id')::bigint and o.status <> 'aperta'
             order by o.reviewed_at desc nulls last limit 5) c;
  elsif t.task_type = 'tecnico.segnale' then
    select coalesce(jsonb_agg(jsonb_build_object('stato', x.status, 'classe', x.proposta ->> 'classe', 'deciso', x.decided_at)
             order by x.decided_at desc), '[]'::jsonb) into v_previous
      from (select * from brain.tasks o where o.task_type = 'tecnico.segnale' and o.id <> t.id
             and o.payload ->> 'fonte' = t.payload ->> 'fonte' and o.decided_at is not null
             order by o.decided_at desc limit 5) x;
  end if;
  return jsonb_build_object(
    'precedenti', v_previous,
    'dipendenze', (select coalesce(jsonb_agg(jsonb_build_object('tipo', x.task_type, 'stato', x.status, 'risultato', x.proposta)
                     order by x.created_at), '[]'::jsonb)
                     from brain.task_dependencies d join brain.tasks x on x.id = d.depends_on where d.task_id = t.id),
    'genitore', (select jsonb_build_object('tipo', x.task_type, 'stato', x.status, 'risultato', x.proposta)
                   from brain.tasks x where x.id = t.parent_task_id));
end;
$$;

-- =============================================================================================
-- 2. Wine Research
-- =============================================================================================
create table catalog.research_provenance (
  claim_id bigint primary key references catalog.attribute_claims(id),
  reference text not null check (length(reference) between 3 and 500),
  retrieved_at timestamptz not null,
  confidence smallint not null check (confidence between 1 and 5),
  -- i diritti dichiarati AL MOMENTO dell'acquisizione (licenza o attribuzione della fonte)
  rights text not null check (length(rights) between 1 and 500),
  submitted_by text not null,
  created_at timestamptz not null default now()
);
alter table catalog.research_provenance enable row level security;
revoke all on catalog.research_provenance from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
create trigger research_provenance_append_only before update or delete on catalog.research_provenance
  for each row execute function brain.append_only();

create or replace function catalog.research_submit(p_source_code text, p_subject_type text, p_subject_id uuid,
  p_attribute text, p_value jsonb, p_reference text, p_retrieved_at timestamptz, p_confidence integer, p_actor text)
returns bigint language plpgsql volatile set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  s catalog.sources%rowtype;
  v_rights text;
  v_reference text := btrim(coalesce(p_reference, ''));
  v_claim bigint;
begin
  select * into s from catalog.sources x where x.code = p_source_code;
  -- fail-closed: senza autorizzazione verificata e diritti dichiarati la fonte non si usa
  if not found or s.authorization_status <> 'authorized' or s.verified_at is null then
    raise exception 'catalog: fonte non autorizzata per la ricerca' using errcode = '42501';
  end if;
  v_rights := coalesce(nullif(btrim(coalesce(s.license, '')), ''), nullif(btrim(coalesce(s.attribution_text, '')), ''));
  if v_rights is null then
    raise exception 'catalog: la fonte non dichiara diritti di utilizzo' using errcode = '42501';
  end if;
  if length(v_reference) not between 3 and 500 or v_reference ~ '[[:cntrl:]<>@]'
     or (v_reference ~* '^[a-z]+://' and v_reference !~* '^https://') then
    raise exception 'catalog: riferimento della fonte non valido' using errcode = '22023';
  end if;
  if p_retrieved_at is null or p_retrieved_at > clock_timestamp() + interval '5 minutes'
     or p_retrieved_at < clock_timestamp() - interval '5 years' then
    raise exception 'catalog: data di acquisizione non valida' using errcode = '22023';
  end if;
  if p_confidence is null or p_confidence not between 1 and 5 then
    raise exception 'catalog: attendibilità da 1 a 5' using errcode = '22023';
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' or octet_length(p_value::text) > 4000
     or p_value::text ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    raise exception 'catalog: valore non ammesso' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog.research:' || coalesce(p_subject_id::text, '') || ':' || coalesce(p_attribute, ''), 0));
  select c.id into v_claim from catalog.attribute_claims c
   where c.attribute_key = p_attribute and c.source_id = s.id and c.value = p_value and c.status = 'proposed'
     and coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id) = p_subject_id
   limit 1;
  if v_claim is not null then
    return v_claim;
  end if;
  v_claim := catalog.propose_attribute_claim(p_attribute, p_subject_type, p_subject_id, p_value, s.id, null,
    left('Ricerca: ' || v_reference, 1000), v_actor);
  insert into catalog.research_provenance (claim_id, reference, retrieved_at, confidence, rights, submitted_by)
  values (v_claim, v_reference, p_retrieved_at, p_confidence, left(v_rights, 500), v_actor);
  perform brain.enqueue_task('ricerca.verifica', 'Informazione di ricerca da verificare n. ' || v_claim::text, 3,
    jsonb_build_object('rivendicazione_id', v_claim), 'ricerca:' || v_claim::text, true, null);
  return v_claim;
end;
$$;

-- Ciò che il Wine Research può leggere: la rivendicazione, le altre sullo stesso attributo e la provenienza.
create or replace function catalog.research_context(p_claim bigint)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'rivendicazione_id', c.id, 'attributo', c.attribute_key, 'stato', c.status, 'valore', c.value,
    'fonte', jsonb_build_object('codice', s.code, 'affidabilita', s.trust_tier, 'autorizzata', s.authorization_status = 'authorized'),
    'provenienza', (select jsonb_build_object('riferimento', p.reference, 'acquisita', p.retrieved_at, 'attendibilita', p.confidence)
                      from catalog.research_provenance p where p.claim_id = c.id),
    'accettata', (select jsonb_build_object('id', a.id, 'valore', a.value, 'fonte', x.code, 'affidabilita', x.trust_tier)
                    from catalog.attribute_claims a join catalog.sources x on x.id = a.source_id
                   where a.attribute_key = c.attribute_key and a.status = 'accepted'
                     and coalesce(a.producer_id, a.wine_id, a.vintage_id, a.format_id)
                       = coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id)),
    'altre_proposte', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'valore', o.value, 'fonte', x.code,
                          'affidabilita', x.trust_tier) order by o.id)
                      from (select * from catalog.attribute_claims q
                             where q.attribute_key = c.attribute_key and q.status = 'proposed' and q.id <> c.id
                               and coalesce(q.producer_id, q.wine_id, q.vintage_id, q.format_id)
                                 = coalesce(c.producer_id, c.wine_id, c.vintage_id, c.format_id)
                             order by q.id limit 10) o
                      join catalog.sources x on x.id = o.source_id), '[]'::jsonb))
    from catalog.attribute_claims c join catalog.sources s on s.id = c.source_id
   where c.id = p_claim;
$$;

create or replace function public.catalogo_admin_ricerca_registra(p_dati jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_data jsonb := coalesce(p_dati, '{}'::jsonb);
begin
  if exists (select 1 from jsonb_object_keys(v_data) k where k not in
       ('fonte', 'soggetto', 'soggetto_id', 'attributo', 'valore', 'riferimento', 'acquisita', 'attendibilita')) then
    raise exception 'Campo non ammesso.' using errcode = '22023';
  end if;
  return jsonb_build_object('id', catalog.research_submit(v_data ->> 'fonte', v_data ->> 'soggetto',
    (v_data ->> 'soggetto_id')::uuid, v_data ->> 'attributo', v_data -> 'valore', v_data ->> 'riferimento',
    (v_data ->> 'acquisita')::timestamptz, (v_data ->> 'attendibilita')::integer, v_actor));
end;
$$;

-- =============================================================================================
-- 3. Authenticity Assistant: richieste di verifica su segnali strutturati
-- =============================================================================================
create table private.autenticita_settings (
  singleton boolean primary key default true check (singleton),
  richieste_enabled boolean not null default false
);
insert into private.autenticita_settings default values;

create table private.autenticita_richieste (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  bottle_unit_id uuid not null references public.bottle_units(id) on delete cascade,
  -- elenco CHIUSO di segnali: nessun testo libero, nessuna immagine
  anomalie text[] not null check (cardinality(anomalie) between 1 and 6 and anomalie <@ array[
    'etichetta_non_coerente', 'annata_non_coerente', 'produttore_non_coerente', 'qualita_foto_insufficiente',
    'provenienza_non_documentata', 'condizioni_da_verificare']::text[]),
  consenso_il timestamptz not null default now(),
  -- di proposito NON esiste uno stato «autentica» o «falsa»
  stato text not null default 'aperta' check (stato in ('aperta', 'in_verifica', 'documenti_richiesti', 'chiusa')),
  nota_admin text check (nota_admin is null or length(nota_admin) <= 1000),
  decisa_da text,
  aggiornata_il timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index autenticita_richieste_una_aperta on private.autenticita_richieste (bottle_unit_id)
  where stato <> 'chiusa';
create index autenticita_richieste_owner_idx on private.autenticita_richieste (owner_id, created_at desc);
create index autenticita_richieste_stato_idx on private.autenticita_richieste (stato, created_at);
alter table private.autenticita_settings enable row level security;
alter table private.autenticita_richieste enable row level security;
revoke all on private.autenticita_settings, private.autenticita_richieste from public, anon, authenticated, service_role;

create or replace function public.cellar_verifica_autenticita_disponibile()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select s.richieste_enabled from private.autenticita_settings s), false);
$$;

create or replace function public.cellar_verifica_autenticita_richiedi(p_bottle_unit_id uuid, p_anomalie text[], p_consenso boolean)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_anomalie text[];
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  if not public.cellar_verifica_autenticita_disponibile() then
    raise exception 'Le richieste di verifica non sono attive.' using errcode = 'P0001';
  end if;
  if p_consenso is not true then
    raise exception 'Serve il tuo consenso per richiedere una verifica.' using errcode = 'P0001';
  end if;
  -- un solo messaggio per «non esiste» e «non è tua»
  if not exists (select 1 from public.bottle_units b
                  where b.id = p_bottle_unit_id and b.owner_id = v_uid and b.deleted_at is null and b.ceduta_at is null) then
    raise exception 'Questa bottiglia non è nella tua cantina.' using errcode = '42501';
  end if;
  select array_agg(distinct a order by a) into v_anomalie from unnest(p_anomalie) a;
  if v_anomalie is null then
    raise exception 'Indica almeno un segnale da verificare.' using errcode = '22023';
  end if;
  select r.id into v_id from private.autenticita_richieste r where r.bottle_unit_id = p_bottle_unit_id and r.stato <> 'chiusa';
  if v_id is not null then
    return 'gia_aperta';
  end if;
  perform private.rate_limit_consume('autenticita', 'user:' || v_uid::text, 3, 86400);
  begin
    insert into private.autenticita_richieste (owner_id, bottle_unit_id, anomalie)
    values (v_uid, p_bottle_unit_id, v_anomalie) returning id into v_id;
  exception
    when check_violation then
      raise exception 'Segnale non riconosciuto.' using errcode = '22023';
    when unique_violation then
      return 'gia_aperta';
  end;
  -- nel bus solo il riferimento opaco: nessun proprietario, nessuna bottiglia
  perform brain.enqueue_task('autenticita.verifica', 'Richiesta di verifica di una bottiglia', 2,
    jsonb_build_object('richiesta_id', v_id), 'autenticita:' || v_id::text, true, null);
  return 'ricevuta';
end;
$$;

create or replace function public.azienda_admin_autenticita(p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r)) from (
    select a.id, a.anomalie, a.stato, a.created_at as creata, a.aggiornata_il as aggiornata, a.nota_admin as nota,
           w.produttore, w.nome, w.annata
      from private.autenticita_richieste a
      join public.bottle_units b on b.id = a.bottle_unit_id
      join public.wines w on w.id = b.wine_id
     order by (a.stato = 'chiusa'), a.created_at limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

create or replace function public.azienda_admin_autenticita_decidi(p_id uuid, p_azione text, p_nota text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_stato text;
begin
  v_stato := case p_azione when 'avvia_verifica' then 'in_verifica' when 'richiedi_documenti' then 'documenti_richiesti'
                           when 'chiudi' then 'chiusa' end;
  if v_stato is null then
    raise exception 'Azione non valida.' using errcode = '22023';
  end if;
  if v_note is null or length(v_note) > 1000 then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  update private.autenticita_richieste
     set stato = v_stato, nota_admin = v_note, decisa_da = v_actor, aggiornata_il = now()
   where id = p_id and stato <> 'chiusa' and stato <> v_stato;
  if not found then
    raise exception 'La richiesta non è in uno stato decidibile.' using errcode = 'P0002';
  end if;
  perform brain.record_event('autenticita.decisione', 'admin', null, null, 'richiesta', p_id::text,
    jsonb_build_object('stato', v_stato, 'esecutore', v_actor));
  return v_stato;
end;
$$;

-- =============================================================================================
-- 4. Contesto degli agenti: i nuovi tipi e la memoria
-- =============================================================================================
create or replace function brain.agent_context_core(p_agent text, p_task uuid, p_lease uuid)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  c catalog.contributions%rowtype;
  v_public uuid;
  v_match record;
  v_source text;
  v_anomaly bigint;
  v_context jsonb;
  v_request private.autenticita_richieste%rowtype;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if t.task_type = 'catalogo.proposta' then
    select * into c from catalog.contributions x where x.id = (t.payload ->> 'contributo_id')::bigint;
    if not found or c.status <> 'aperta' then
      v_context := jsonb_build_object('tipo', t.task_type, 'stato', 'gia_decisa');
    else
      select s.public_wine_id into v_public from catalog.contribution_submissions s
       where s.contribution_id = c.id and s.public_wine_id is not null order by s.id limit 1;
      select * into v_match from catalog.contribution_match(c.identity, v_public);
      v_context := jsonb_build_object('tipo', t.task_type, 'stato', 'aperta', 'contributo_id', c.id,
        -- una proposta in quarantena arriva senza testi: l'agente non li analizza, li rimanda a una persona
        'dati', case when c.quarantine_reason is null then c.identity else '{}'::jsonb end,
        'quarantena', c.quarantine_reason,
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
    end if;
  elsif t.task_type = 'qualita.scansione' then
    v_context := jsonb_build_object('tipo', t.task_type, 'rilievi', brain.quality_findings());
  elsif t.task_type = 'tecnico.segnale' then
    v_source := t.payload ->> 'fonte';
    v_context := jsonb_build_object('tipo', t.task_type, 'fonte', v_source,
      'intervallo_atteso_minuti', (select m.expected_interval_minutes from brain.monitor_sources m where m.source_key = v_source),
      'segnali', coalesce((select jsonb_agg(jsonb_build_object('stato', x.status, 'osservato', x.observed_at,
                    'ricevuto', x.received_at, 'riferimento', x.evidence_ref, 'conteggi', x.counts) order by x.observed_at desc, x.id desc)
          from (select * from brain.monitor_signals s where s.source_key = v_source order by s.observed_at desc, s.id desc limit 30) x),
        '[]'::jsonb),
      'anomalia', (select jsonb_build_object('stato', a.status, 'ricorrenze', a.occurrences, 'prima', a.first_seen_at)
                     from brain.anomalies a where a.fingerprint = 'segnale_monitor:' || v_source));
  elsif t.task_type = 'anomalia.verifica' then
    v_anomaly := (t.payload ->> 'anomalia_id')::bigint;
    v_context := jsonb_build_object('tipo', t.task_type, 'anomalia', (select jsonb_build_object('codice', a.code,
             'severita', a.severity, 'stato', a.status, 'evidenza', a.evidence, 'ricorrenze', a.occurrences,
             'azione_proposta', a.azione_proposta) from brain.anomalies a where a.id = v_anomaly));
  elsif t.task_type = 'ricerca.verifica' then
    v_context := coalesce(catalog.research_context((t.payload ->> 'rivendicazione_id')::bigint), '{}'::jsonb)
      || jsonb_build_object('tipo', t.task_type);
  elsif t.task_type = 'autenticita.verifica' then
    select * into v_request from private.autenticita_richieste r where r.id = (t.payload ->> 'richiesta_id')::uuid;
    v_context := case when v_request.id is null or v_request.stato = 'chiusa'
      then jsonb_build_object('tipo', t.task_type, 'stato', 'gia_decisa')
      else jsonb_build_object('tipo', t.task_type, 'stato', v_request.stato, 'anomalie', to_jsonb(v_request.anomalie)) end;
  else
    raise exception 'brain: nessun contesto per questo tipo di task' using errcode = '22023';
  end if;
  return v_context || jsonb_build_object('memoria', brain.task_memory(t.id));
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
  elsif t.task_type = 'ricerca.verifica' and not exists (select 1 from catalog.attribute_claims c
       where c.id = (t.payload ->> 'rivendicazione_id')::bigint and c.status = 'proposed') then
    perform brain.close_task_by_rule(p_task, 'La rivendicazione è già stata decisa.');
  elsif t.task_type = 'autenticita.verifica' and not exists (select 1 from private.autenticita_richieste r
       where r.id = (t.payload ->> 'richiesta_id')::uuid and r.stato <> 'chiusa') then
    perform brain.close_task_by_rule(p_task, 'La richiesta è già stata chiusa.');
  else
    raise exception 'brain: chiusura non consentita, serve una decisione' using errcode = '42501';
  end if;
  return 'annullato';
end;
$$;

-- =============================================================================================
-- 5. Rilievi di qualità estesi (soli conteggi e riferimenti)
-- =============================================================================================
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
      from catalog.import_runs i where i.status = 'running' and i.heartbeat_at < now() - interval '2 hours'
    union all
    select 'proposte_in_quarantena', 'P2', count(*), (array_agg(c.id::text order by c.id))[1:10]
      from catalog.contributions c where c.status = 'aperta' and c.quarantine_reason is not null
    union all
    -- annata dichiarata nel futuro: impossibile per una bottiglia esistente
    select 'annate_future', 'P2', count(*), (array_agg(v.id::text order by v.id))[1:10]
      from catalog.wine_vintages v where v.vintage_year > extract(year from now())::integer
    union all
    select 'fonti_in_conflitto', 'P2', count(*), (array_agg(g.primo order by g.primo))[1:10]
      from (select min(a.id::text) as primo from catalog.attribute_claims a where a.status = 'proposed'
             group by a.attribute_key, coalesce(a.producer_id, a.wine_id, a.vintage_id, a.format_id)
            having count(distinct a.value) > 1) g
    union all
    -- un dato accettato la cui fonte non è più autorizzata non va più mostrato come documentato
    select 'dati_con_fonte_revocata', 'P1', count(*), (array_agg(a.id::text order by a.id))[1:10]
      from catalog.attribute_claims a join catalog.sources s on s.id = a.source_id
     where a.status = 'accepted' and s.authorization_status <> 'authorized')
  select coalesce(jsonb_agg(jsonb_build_object('codice', codice, 'severita', severita, 'conteggio', conteggio,
           'esempi', to_jsonb(coalesce(esempi, array[]::text[]))) order by severita, codice), '[]'::jsonb)
    from rilievi where conteggio > 0;
$$;

-- Le proposte in quarantena non entrano nella coda automatica: le vede il curatore (quarantena e Sentinel).
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
     where c.status = 'aperta' and c.quarantine_reason is null
       and not brain.contribution_has_task(c.id)
     order by c.created_at, c.id
     limit least(greatest(coalesce(p_limit, 100), 1), 500)
  loop
    if brain.enqueue_task('catalogo.proposta', 'Proposta al catalogo n. ' || v.id::text,
      case v.match_kind when 'ambiguo' then 1 when 'sconosciuto' then 2 else 3 end,
      jsonb_build_object('contributo_id', v.id),
      -- il numero dei task precedenti rende unica la chiave della riapertura e identica quella di due giri concorrenti
      'contributo:' || v.id::text || ':' || (select count(*) from brain.tasks t
          where t.task_type = 'catalogo.proposta' and t.payload ->> 'contributo_id' = v.id::text)::text, true, null) is null then
      exit;
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- =============================================================================================
-- 6. Price Intelligence: adattatore sullo storico GIÀ minimizzato (nessun acquirente, venditore o ordine)
-- =============================================================================================
create table private.prezzi_settings (
  singleton boolean primary key default true check (singleton),
  -- finalità da approvare dal founder prima di mostrare i dati nel pannello
  valutazione_admin_enabled boolean not null default false
);
insert into private.prezzi_settings default values;
alter table private.prezzi_settings enable row level security;
revoke all on private.prezzi_settings from public, anon, authenticated, service_role;

create or replace function public.prezzi_admin_osservazioni(p_wine_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  w public.wines%rowtype;
begin
  perform private.catalog_admin_richiedi();
  if not coalesce((select s.valutazione_admin_enabled from private.prezzi_settings s), false) then
    return jsonb_build_object('abilitata', false);
  end if;
  select * into w from public.wines x where x.slug = left(coalesce(p_wine_slug, ''), 200);
  if not found then
    raise exception 'Vino inesistente.' using errcode = 'P0002';
  end if;
  return jsonb_build_object('abilitata', true,
    'vino', jsonb_build_object('produttore', w.produttore, 'nome', w.nome),
    'soggetto', jsonb_build_object('vinoId', w.id, 'annata', w.annata, 'formatoMl', catalog.parse_format_ml(w.formato), 'valuta', 'eur'),
    -- elenco CHIUSO uguale al contratto di acquisizione: `origine_ref` (annuncio o ordine) non esce mai
    'osservazioni', coalesce((select jsonb_agg(jsonb_build_object('id', o.id,
          'tipo', case o.tipo when 'vendita' then 'realizzato' else 'richiesto' end,
          'centesimi', o.prezzo_cents, 'valuta', o.valuta, 'osservatoIl', o.observed_at, 'fonte', o.fonte::text,
          'vinoId', o.wine_id, 'annata', w.annata, 'formatoMl', catalog.parse_format_ml(o.formato), 'condizione', null)
          order by o.observed_at desc, o.id)
        from (select * from public.wine_price_observations p where p.wine_id = w.id order by p.observed_at desc limit 500) o),
      '[]'::jsonb));
end;
$$;

-- =============================================================================================
-- 7. Sommelier: scheda documentata del solo codice richiesto
-- =============================================================================================
create or replace function public.vini_canonici_scheda_servizio(p_codice text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_wine uuid;
begin
  -- stessa visibilità della ricerca canonica (proiezione, pubblicazione, fonte autorizzata): niente scorciatoie
  select c.vino_id into v_wine from public.vini_canonici_cerca('', '', 1, left(coalesce(p_codice, ''), 40)) c
   where c.livello = 'identificativo' limit 1;
  if v_wine is null then
    return null;
  end if;
  return jsonb_build_object(
    'annate', coalesce((select jsonb_agg(jsonb_build_object('anno', v.vintage_year, 'non_millesimato', v.is_non_vintage)
                 order by v.vintage_year desc nulls last)
               from (select * from catalog.wine_vintages x where x.wine_id = v_wine order by x.vintage_year desc nulls last limit 20) v),
              '[]'::jsonb),
    'dati_documentati', coalesce((select jsonb_agg(jsonb_build_object('attributo', r.attribute_key, 'valore', r.value,
                   'fonte', r.name, 'affidabilita', r.trust_tier, 'annata', r.vintage_year) order by r.attribute_key, r.vintage_year)
               from (select a.attribute_key, a.value, s.name, s.trust_tier, v.vintage_year
                       from catalog.attribute_claims a
                       join catalog.sources s on s.id = a.source_id and s.authorization_status = 'authorized'
                       left join catalog.wine_vintages v on v.id = a.vintage_id
                      where a.status = 'accepted' and (a.wine_id = v_wine or v.wine_id = v_wine)
                      order by a.attribute_key, v.vintage_year limit 20) r), '[]'::jsonb));
end;
$$;

-- =============================================================================================
-- 8. Privilegi
-- =============================================================================================
revoke all on function public.catalogo_admin_ricerca_registra(jsonb), public.cellar_verifica_autenticita_disponibile(),
  public.cellar_verifica_autenticita_richiedi(uuid, text[], boolean), public.azienda_admin_autenticita(integer),
  public.azienda_admin_autenticita_decidi(uuid, text, text), public.prezzi_admin_osservazioni(text),
  public.vini_canonici_scheda_servizio(text) from public, anon, authenticated, service_role;
grant execute on function public.catalogo_admin_ricerca_registra(jsonb), public.cellar_verifica_autenticita_disponibile(),
  public.cellar_verifica_autenticita_richiedi(uuid, text[], boolean), public.azienda_admin_autenticita(integer),
  public.azienda_admin_autenticita_decidi(uuid, text, text), public.prezzi_admin_osservazioni(text) to authenticated;
grant execute on function public.vini_canonici_scheda_servizio(text) to service_role;

revoke all on function catalog.research_submit(text, text, uuid, text, jsonb, text, timestamptz, integer, text),
  catalog.research_context(bigint)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

revoke all on function brain.task_dependencies_guard(), brain.dependencies_met(uuid), brain.cancel_blocked_tasks(),
  brain.enqueue_task(text, text, integer, jsonb, text, boolean, uuid), brain.claim_task_core(text, integer),
  brain.finish_task_core(text, uuid, uuid, boolean, jsonb),
  brain.spawn_task_core(text, uuid, uuid, text, text, jsonb, text, boolean),
  brain.spawn_task(uuid, uuid, text, text, jsonb, text, boolean), brain.cancel_operation(uuid, text, text),
  brain.task_memory(uuid), brain.agent_context_core(text, uuid, uuid), brain.close_if_allowed_core(text, uuid, uuid),
  brain.quality_findings(), brain.enqueue_catalog_work(integer, text)
  from public, anon, authenticated, service_role, brain_worker, brain_ingest, brain_monitor_read;
grant execute on function brain.spawn_task(uuid, uuid, text, text, jsonb, text, boolean) to brain_worker;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-016C: una dipendenza dell''impronta non esiste più';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
