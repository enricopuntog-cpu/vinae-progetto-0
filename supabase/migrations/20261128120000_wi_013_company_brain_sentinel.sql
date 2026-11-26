-- WI-013 — fondamenta del «Company Brain» e registro delle anomalie di Sentinel.
--
-- Non è un secondo database aziendale: Supabase resta la fonte autorevole dei dati operativi, e il catalogo conserva il
-- proprio storico (`catalog.canonical_events`). Qui c'è solo il CONTRATTO comune con cui futuri agenti si scambiano
-- eventi, task, evidenze e approvazioni, e il registro unico delle anomalie.
--
-- Chiuso per difetto: schema non esposto alla Data API; nessun privilegio ad anon, authenticated o service_role; gli
-- agenti esistono solo se registrati, nascono SPENTI e vedono solo i tipi di task che elencano; il ruolo `brain_worker`
-- è NOLOGIN e nessun membro gli è assegnato. Sentinel legge e registra: NON modifica account, pagamenti, ordini,
-- catalogo o dati personali e non invia notifiche. NESSUNO scheduler è attivato da questa migration.

do $ruolo$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'brain_worker') then
    create role brain_worker nologin noinherit;
  end if;
end $ruolo$;

create schema if not exists brain;
revoke all on schema brain from public, anon, authenticated, service_role;
grant usage on schema brain to brain_worker;

-- Nessun segreto né dato personale nella memoria condivisa: chiavi sospette e indirizzi di posta sono rifiutati,
-- e la dimensione è limitata. È una rete, non una licenza: i produttori mandano riferimenti, non contenuti.
create or replace function brain.payload_ammesso(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select p is not null and jsonb_typeof(p) = 'object' and pg_catalog.octet_length(p::text) <= 4096
     and p::text !~* '"[a-z0-9_]*(password|passwd|secret|token|api_?key|authorization|cookie|email|telefono|phone|indirizzo|address|iban|card)[a-z0-9_]*"[[:space:]]*:'
     and p::text !~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}';
$$;

-- ---------------------------------------------------------------------------------------------
-- Eventi (in sola aggiunta)
-- ---------------------------------------------------------------------------------------------
create table brain.events (
  id bigint generated always as identity primary key,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_]{1,30}\.[a-z][a-z0-9_]{1,50}$'),
  source text not null check (source ~ '^[a-z][a-z0-9_:-]{1,60}$'),
  correlation_id uuid not null,
  dedup_key text unique check (dedup_key is null or length(dedup_key) between 1 and 200),
  subject_type text check (subject_type is null or length(subject_type) <= 60),
  subject_ref text check (subject_ref is null or length(subject_ref) <= 200),
  payload jsonb not null default '{}'::jsonb check (brain.payload_ammesso(payload)),
  schema_version smallint not null default 1 check (schema_version between 1 and 1000),
  recorded_at timestamptz not null default now()
);
create index events_correlation_idx on brain.events (correlation_id, id);
create index events_type_idx on brain.events (event_type, id desc);

create or replace function brain.append_only()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'brain: % è in sola aggiunta', tg_table_name using errcode = '55000';
end;
$$;
create trigger events_append_only before update or delete on brain.events for each row execute function brain.append_only();
create trigger events_no_truncate before truncate on brain.events for each statement execute function brain.append_only();

create or replace function brain.record_event(p_type text, p_source text, p_correlation uuid default null,
  p_dedup text default null, p_subject_type text default null, p_subject_ref text default null,
  p_payload jsonb default '{}'::jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into brain.events (event_type, source, correlation_id, dedup_key, subject_type, subject_ref, payload)
  values (p_type, p_source, coalesce(p_correlation, gen_random_uuid()), p_dedup, p_subject_type, p_subject_ref,
          coalesce(p_payload, '{}'::jsonb))
  on conflict (dedup_key) do nothing
  returning id into v_id;
  if v_id is null then
    select e.id into v_id from brain.events e where e.dedup_key = p_dedup;
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Agenti e task
-- ---------------------------------------------------------------------------------------------
create table brain.agents (
  agent_key text primary key check (agent_key ~ '^[a-z][a-z0-9_]{1,40}$'),
  descrizione text not null,
  enabled boolean not null default false,
  task_types text[] not null default '{}'
);

create table brain.tasks (
  id uuid primary key default gen_random_uuid(),
  task_type text not null check (task_type ~ '^[a-z][a-z0-9_]{1,30}\.[a-z][a-z0-9_]{1,50}$'),
  titolo text not null check (length(btrim(titolo)) between 1 and 200),
  priority smallint not null default 2 check (priority between 0 and 3),
  status text not null default 'in_attesa'
    check (status in ('in_attesa', 'assegnato', 'in_approvazione', 'completato', 'respinto', 'fallito', 'annullato')),
  correlation_id uuid not null default gen_random_uuid(),
  dedup_key text unique check (dedup_key is null or length(dedup_key) between 1 and 200),
  payload jsonb not null default '{}'::jsonb check (brain.payload_ammesso(payload)),
  proposta jsonb check (proposta is null or brain.payload_ammesso(proposta)),
  requires_approval boolean not null default true,
  decided_by text,
  decided_at timestamptz,
  decision_note text check (decision_note is null or length(decision_note) <= 1000),
  attempts smallint not null default 0,
  max_attempts smallint not null default 3 check (max_attempts between 1 and 10),
  lease_agent text references brain.agents(agent_key),
  lease_token uuid,
  lease_expires_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'assegnato') = (lease_token is not null and lease_expires_at is not null and lease_agent is not null))
);
create index tasks_queue_idx on brain.tasks (priority, created_at) where status = 'in_attesa';
create index tasks_status_idx on brain.tasks (status, updated_at desc);
create index tasks_lease_agent_idx on brain.tasks (lease_agent) where lease_agent is not null;

create table brain.task_evidence (
  id bigint generated always as identity primary key,
  task_id uuid not null references brain.tasks(id),
  kind text not null check (kind ~ '^[a-z][a-z0-9_]{1,40}$'),
  detail jsonb not null check (brain.payload_ammesso(detail)),
  recorded_by text not null,
  recorded_at timestamptz not null default now()
);
create index task_evidence_task_idx on brain.task_evidence (task_id, id);
create trigger task_evidence_append_only before update or delete on brain.task_evidence
  for each row execute function brain.append_only();

create or replace function brain.enqueue_task(p_type text, p_titolo text, p_priority integer default 2,
  p_payload jsonb default '{}'::jsonb, p_dedup text default null, p_requires_approval boolean default true,
  p_correlation uuid default null)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid;
begin
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

-- Lease scaduti: il task torna in coda finché ha tentativi, poi è fallito.
create or replace function brain.reap_expired_leases()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_n integer;
begin
  update brain.tasks
     set status = case when attempts >= max_attempts then 'fallito' else 'in_attesa' end,
         lease_agent = null, lease_token = null, lease_expires_at = null, updated_at = now(), version = version + 1
   where status = 'assegnato' and lease_expires_at < clock_timestamp();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Un agente acceso prende UN task fra i soli tipi che gli sono assegnati; SKIP LOCKED evita doppie prese.
create or replace function brain.claim_task(p_agent text, p_lease_seconds integer default 300)
returns table (task_id uuid, lease_token uuid, task_type text, titolo text, payload jsonb, correlation_id uuid, attempt integer)
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_types text[];
  v_id uuid;
  v_token uuid := gen_random_uuid();
begin
  select a.task_types into v_types from brain.agents a where a.agent_key = p_agent and a.enabled;
  if v_types is null then
    raise exception 'brain: agente inesistente o spento' using errcode = '42501';
  end if;
  perform brain.reap_expired_leases();
  select t.id into v_id from brain.tasks t
   where t.status = 'in_attesa' and t.task_type = any (v_types)
   order by t.priority, t.created_at, t.id
   limit 1 for update skip locked;
  if v_id is null then
    return;
  end if;
  update brain.tasks t
     set status = 'assegnato', lease_agent = p_agent, lease_token = v_token,
         lease_expires_at = clock_timestamp() + make_interval(secs => least(greatest(coalesce(p_lease_seconds, 300), 30), 3600)),
         attempts = t.attempts + 1, updated_at = now(), version = t.version + 1
   where t.id = v_id;
  return query select t.id, v_token, t.task_type, t.titolo, t.payload, t.correlation_id, t.attempts::integer
    from brain.tasks t where t.id = v_id;
end;
$$;

create or replace function brain.add_evidence(p_task uuid, p_lease uuid, p_kind text, p_detail jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare
  v_agent text;
  v_id bigint;
begin
  select t.lease_agent into v_agent from brain.tasks t
   where t.id = p_task and t.status = 'assegnato' and t.lease_token = p_lease and t.lease_expires_at >= clock_timestamp()
   for update;
  if v_agent is null then
    raise exception 'brain: lease non valido o scaduto' using errcode = '42501';
  end if;
  insert into brain.task_evidence (task_id, kind, detail, recorded_by) values (p_task, p_kind, p_detail, 'agent:' || v_agent)
  returning id into v_id;
  return v_id;
end;
$$;

-- L'agente consegna una PROPOSTA o un guasto. Con approvazione richiesta, il task non si chiude da sé.
create or replace function brain.finish_task(p_task uuid, p_lease uuid, p_success boolean, p_proposta jsonb default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  v_status text;
begin
  select * into t from brain.tasks
   where id = p_task and status = 'assegnato' and lease_token = p_lease and lease_expires_at >= clock_timestamp()
   for update;
  if not found then
    raise exception 'brain: lease non valido o scaduto' using errcode = '42501';
  end if;
  if p_success is null then
    raise exception 'brain: esito mancante' using errcode = '22023';
  end if;
  v_status := case when not p_success then (case when t.attempts >= t.max_attempts then 'fallito' else 'in_attesa' end)
                   when t.requires_approval then 'in_approvazione'
                   else 'completato' end;
  update brain.tasks
     set status = v_status, proposta = coalesce(p_proposta, proposta), lease_agent = null, lease_token = null,
         lease_expires_at = null, updated_at = now(), version = version + 1
   where id = p_task;
  perform brain.record_event('task.esito', 'agent:' || t.lease_agent, t.correlation_id,
    'task:' || p_task::text || ':' || t.attempts::text, 'task', p_task::text, jsonb_build_object('stato', v_status));
  return v_status;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Sentinel: registro unico delle anomalie
-- ---------------------------------------------------------------------------------------------
create table brain.anomalies (
  id bigint generated always as identity primary key,
  fingerprint text not null unique check (length(fingerprint) between 1 and 200),
  code text not null check (code ~ '^[a-z][a-z0-9_]{2,60}$'),
  source text not null check (length(source) between 1 and 60),
  category text not null check (category in ('sicurezza', 'pagamenti', 'catalogo', 'ai', 'operativo', 'sentinel')),
  severity text not null check (severity in ('P0', 'P1', 'P2', 'P3')),
  titolo text not null check (length(titolo) between 1 and 200),
  evidence jsonb not null default '{}'::jsonb check (brain.payload_ammesso(evidence)),
  correlation_id uuid not null default gen_random_uuid(),
  status text not null default 'aperta' check (status in ('aperta', 'presa_in_carico', 'risolta', 'ignorata')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  occurrences integer not null default 1 check (occurrences >= 1),
  responsabile text,
  azione_proposta text not null,
  requires_approval boolean not null default true,
  nota text check (nota is null or length(nota) <= 1000),
  check ((status = 'risolta') = (resolved_at is not null))
);
create index anomalies_open_idx on brain.anomalies (severity, last_seen_at desc) where status in ('aperta', 'presa_in_carico');

create table brain.sentinel_runs (
  id bigint generated always as identity primary key,
  started_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz,
  triggered_by text not null,
  checks_run integer not null default 0,
  checks_failed integer not null default 0,
  findings integer not null default 0
);
create index sentinel_runs_recent_idx on brain.sentinel_runs (id desc);

create table brain.sentinel_settings (
  singleton boolean primary key default true check (singleton),
  -- ogni quanto ci si ASPETTA un'esecuzione: oltre il doppio Sentinel è dichiarato fermo
  expected_interval_minutes integer not null default 60 check (expected_interval_minutes between 5 and 10080),
  -- vero solo quando esiste davvero uno scheduler che chiama `brain.sentinel_run` (nessuno lo è oggi)
  scheduled boolean not null default false
);
insert into brain.sentinel_settings default values;

alter table brain.events enable row level security;
alter table brain.agents enable row level security;
alter table brain.tasks enable row level security;
alter table brain.task_evidence enable row level security;
alter table brain.anomalies enable row level security;
alter table brain.sentinel_runs enable row level security;
alter table brain.sentinel_settings enable row level security;
revoke all on all tables in schema brain from public, anon, authenticated, service_role, brain_worker;

-- Un reperto: deduplicato per impronta. Una anomalia risolta che ricompare si riapre; una ignorata resta ignorata.
create or replace function brain.report_anomaly(p_code text, p_subject text, p_source text, p_category text, p_severity text,
  p_titolo text, p_evidence jsonb, p_azione text, p_requires_approval boolean default true)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare
  v_fingerprint text := p_code || case when coalesce(p_subject, '') = '' then '' else ':' || p_subject end;
  v_old text;
  v_id bigint;
  v_corr uuid;
begin
  select a.status into v_old from brain.anomalies a where a.fingerprint = v_fingerprint for update;
  insert into brain.anomalies as a (fingerprint, code, source, category, severity, titolo, evidence, azione_proposta, requires_approval)
  values (v_fingerprint, p_code, p_source, p_category, p_severity, p_titolo, coalesce(p_evidence, '{}'::jsonb), p_azione,
          coalesce(p_requires_approval, true))
  on conflict (fingerprint) do update
     set last_seen_at = clock_timestamp(), occurrences = a.occurrences + 1, evidence = excluded.evidence,
         severity = excluded.severity, titolo = excluded.titolo,
         status = case when a.status = 'risolta' then 'aperta' else a.status end,
         resolved_at = case when a.status = 'risolta' then null else a.resolved_at end
  returning a.id, a.correlation_id into v_id, v_corr;
  -- Solo l'APERTURA (o riapertura) è un evento; le ricorrenze no. Le P0/P1 aprono anche un task da approvare.
  if v_old is null or v_old = 'risolta' then
    perform brain.record_event('sentinel.anomalia_aperta', 'sentinel', v_corr, null, 'anomalia', v_id::text,
      jsonb_build_object('code', p_code, 'severita', p_severity));
    if p_severity in ('P0', 'P1') then
      perform brain.enqueue_task('anomalia.verifica', p_titolo, case p_severity when 'P0' then 0 else 1 end,
        jsonb_build_object('anomalia_id', v_id, 'code', p_code), 'anomalia:' || v_id::text || ':' ||
        (select a.occurrences::text from brain.anomalies a where a.id = v_id), true, v_corr);
    end if;
  end if;
  return v_id;
end;
$$;

-- Controlli deterministici, uno per blocco: un controllo che fallisce diventa esso stesso un'anomalia e non ferma gli
-- altri. Un controllo riuscito che non trova più il problema chiude la sua anomalia. Solo conteggi nelle evidenze.
create or replace function brain.sentinel_run(p_actor text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_run bigint;
  v_check record;
  v_n bigint;
  v_total integer := 0;
  v_failed integer := 0;
  v_found integer := 0;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  -- Una sola esecuzione alla volta.
  if not pg_try_advisory_xact_lock(hashtextextended('brain.sentinel_run', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso');
  end if;
  insert into brain.sentinel_runs (triggered_by) values (btrim(p_actor)) returning id into v_run;
  perform brain.reap_expired_leases();

  for v_check in
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
       'Fuori da un''importazione autorizzata va riportato a NOLOGIN.'),
      ('importazione_ferma', 'catalog.import_runs', 'catalogo', 'P2', 'Importazione in corso senza segnali da oltre 2 ore',
       'select count(*) from catalog.import_runs where status = ''running'' and heartbeat_at < now() - interval ''2 hours''',
       'Riconciliare l''importazione secondo il runbook prima di ripeterla.'),
      ('interruttore_ai_aperto', 'private.ai_budget_settings', 'ai', 'P2', 'Interruttore sui guasti del fornitore AI aperto',
       'select count(*) from private.ai_budget_settings where aperto_fino_a > now()',
       'Controllare il fornitore e i log delle function AI.'),
      ('budget_ai_quasi_esaurito', 'private.ai_consumo_giornaliero', 'ai', 'P3', 'Budget AI giornaliero oltre l''80%',
       'select count(*) from private.ai_budget_settings s where s.richieste_giorno > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno = (now() at time zone ''utc'')::date) >= 0.8 * s.richieste_giorno',
       'Valutare i tetti: li imposta solo il proprietario del database.'),
      ('proposte_catalogo_vecchie', 'catalog.contributions', 'catalogo', 'P3', 'Proposte al catalogo aperte da oltre 14 giorni',
       'select count(*) from catalog.contributions where status = ''aperta'' and created_at < now() - interval ''14 days''',
       'Rivedere la coda dal pannello del catalogo.'),
      ('conflitti_lwin_nativi', 'catalog.lwin_native_conflicts', 'catalogo', 'P2', 'Vini nativi che la fonte LWIN ora conosce',
       'select count(*) from catalog.lwin_native_conflicts(1000)',
       'Associare il LWIN o registrare il duplicato prima di qualunque promozione.')
    ) as c(code, source, category, severity, titolo, query, azione)
  loop
    v_total := v_total + 1;
    begin
      execute v_check.query into v_n;
      if v_n > 0 then
        v_found := v_found + 1;
        perform brain.report_anomaly(v_check.code, '', v_check.source, v_check.category, v_check.severity, v_check.titolo,
          jsonb_build_object('conteggio', v_n), v_check.azione, true);
      else
        update brain.anomalies set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel'
         where fingerprint = v_check.code and status in ('aperta', 'presa_in_carico');
      end if;
      update brain.anomalies set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel'
       where fingerprint = 'controllo_non_eseguito:' || v_check.code and status in ('aperta', 'presa_in_carico');
    exception when others then
      -- si registra il solo codice SQL: il messaggio potrebbe contenere dati
      v_failed := v_failed + 1;
      perform brain.report_anomaly('controllo_non_eseguito', v_check.code, 'sentinel', 'sentinel', 'P2',
        'Un controllo di Sentinel non è stato eseguito', jsonb_build_object('controllo', v_check.code, 'sqlstate', sqlstate),
        'Correggere il controllo: finché fallisce, quel rischio non è sorvegliato.', true);
    end;
  end loop;

  update brain.sentinel_runs
     set finished_at = clock_timestamp(), checks_run = v_total, checks_failed = v_failed, findings = v_found
   where id = v_run;
  return jsonb_build_object('esito', case when v_failed = 0 then 'completato' else 'parziale' end,
    'controlli', v_total, 'non_eseguiti', v_failed, 'problemi', v_found);
end;
$$;

-- Heartbeat e mancata esecuzione, calcolati alla lettura: nessuno scheduler → «non pianificato», mai «attivo».
create or replace function brain.sentinel_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'pianificato', s.scheduled,
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

revoke all on all functions in schema brain from public, anon, authenticated, service_role, brain_worker;
-- Il solo contratto di un agente. Registrare, accendere un agente o creare task resta del proprietario.
grant execute on function brain.claim_task(text, integer), brain.add_evidence(uuid, uuid, text, jsonb),
  brain.finish_task(uuid, uuid, boolean, jsonb) to brain_worker;
grant execute on function brain.payload_ammesso(jsonb) to brain_worker;

-- ---------------------------------------------------------------------------------------------
-- Porte di amministrazione (cruscotto del founder)
-- ---------------------------------------------------------------------------------------------
create or replace function public.azienda_admin_riepilogo()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.catalog_admin_richiedi();
  return jsonb_build_object(
    'sentinel', brain.sentinel_status(),
    'anomalie', (select jsonb_build_object(
        'aperte', count(*) filter (where status in ('aperta', 'presa_in_carico')),
        'p0', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P0'),
        'p1', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P1'),
        'p2', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P2'),
        'p3', count(*) filter (where status in ('aperta', 'presa_in_carico') and severity = 'P3')) from brain.anomalies),
    'task', (select jsonb_build_object(
        'da_approvare', count(*) filter (where status = 'in_approvazione'),
        'in_attesa', count(*) filter (where status = 'in_attesa'),
        'assegnati', count(*) filter (where status = 'assegnato'),
        'falliti', count(*) filter (where status = 'fallito')) from brain.tasks),
    'agenti', jsonb_build_object('registrati', (select count(*) from brain.agents),
                                 'accesi', (select count(*) from brain.agents where enabled)),
    'catalogo', public.catalogo_admin_riepilogo(),
    'ai', public.ai_budget_stato(),
    -- Sorgenti che esistono ma non scrivono qui: si dichiarano non collegate, non si inventa un valore.
    'sorgenti_non_collegate', jsonb_build_array(
      'Heartbeat tecnico (workflow GitHub technical-heartbeat)',
      'Freschezza del backup offsite (workflow GitHub offsite-backup-freshness)',
      'Log di errore dell''applicazione (log Netlify e Supabase)',
      'Spesa monetaria dei fornitori (cruscotti dei fornitori)'));
end;
$$;

create or replace function public.azienda_admin_anomalie(p_aperte boolean default true, p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.severita, r.ultima desc, r.id desc) from (
    select a.id, a.code as codice, a.source as fonte, a.category as categoria, a.severity as severita, a.titolo,
           a.evidence as evidenza, a.correlation_id as correlazione, a.status as stato, a.first_seen_at as prima,
           a.last_seen_at as ultima, a.occurrences as ricorrenze, a.responsabile, a.azione_proposta,
           a.requires_approval as richiede_approvazione, a.nota
      from brain.anomalies a
     where (a.status in ('aperta', 'presa_in_carico')) = coalesce(p_aperte, true)
     order by a.severity, a.last_seen_at desc, a.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

create or replace function public.azienda_admin_anomalia_aggiorna(p_id bigint, p_azione text, p_nota text default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_status text;
begin
  if p_azione is null or p_azione not in ('prendi_in_carico', 'ignora', 'riapri', 'risolvi') then
    raise exception 'Azione non valida.' using errcode = '22023';
  end if;
  if p_azione in ('ignora', 'risolvi') and v_note is null then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  v_status := case p_azione when 'prendi_in_carico' then 'presa_in_carico' when 'ignora' then 'ignorata'
                            when 'riapri' then 'aperta' else 'risolta' end;
  update brain.anomalies
     set status = v_status, responsabile = v_actor, nota = coalesce(v_note, nota),
         resolved_at = case when v_status = 'risolta' then clock_timestamp() end
   where id = p_id and status <> v_status;
  if not found then
    raise exception 'Anomalia inesistente o già in quello stato.' using errcode = 'P0002';
  end if;
  perform brain.record_event('sentinel.anomalia_aggiornata', 'admin', (select a.correlation_id from brain.anomalies a where a.id = p_id),
    null, 'anomalia', p_id::text, jsonb_build_object('stato', v_status, 'esecutore', v_actor));
  return v_status;
end;
$$;

create or replace function public.azienda_admin_sentinel_esegui()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_actor text := private.catalog_admin_richiedi();
begin
  perform private.rate_limit_consume('sentinel-manuale', v_actor, 12, 3600);
  return brain.sentinel_run(v_actor);
end;
$$;

create or replace function public.azienda_admin_task(p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.ordine, r.priorita, r.creato) from (
    select case t.status when 'in_approvazione' then 0 when 'in_attesa' then 1 when 'assegnato' then 2 else 3 end as ordine,
           t.id, t.task_type as tipo, t.titolo, t.priority as priorita, t.status as stato, t.requires_approval as richiede_approvazione,
           t.proposta, t.attempts as tentativi, t.lease_agent as agente, t.correlation_id as correlazione,
           t.created_at as creato, t.updated_at as aggiornato,
           (select count(*) from brain.task_evidence e where e.task_id = t.id) as evidenze
      from brain.tasks t where t.status in ('in_attesa', 'assegnato', 'in_approvazione', 'fallito')
     order by 1, t.priority, t.created_at limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

-- La decisione registra il giudizio. Nessuna azione sui domini parte da qui.
create or replace function public.azienda_admin_task_decidi(p_id uuid, p_decisione text, p_nota text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_status text;
  v_corr uuid;
begin
  if p_decisione is null or p_decisione not in ('approva', 'respingi', 'annulla') then
    raise exception 'Decisione non valida.' using errcode = '22023';
  end if;
  if v_note is null then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  v_status := case p_decisione when 'approva' then 'completato' when 'respingi' then 'respinto' else 'annullato' end;
  update brain.tasks
     set status = v_status, decided_by = v_actor, decided_at = clock_timestamp(), decision_note = v_note,
         updated_at = now(), version = version + 1
   where id = p_id
     and ((p_decisione in ('approva', 'respingi') and status = 'in_approvazione')
          or (p_decisione = 'annulla' and status in ('in_attesa', 'in_approvazione', 'fallito')))
  returning correlation_id into v_corr;
  if v_corr is null then
    raise exception 'Il task non esiste o non è in uno stato decidibile.' using errcode = 'P0002';
  end if;
  perform brain.record_event('task.decisione', 'admin', v_corr, 'decisione:' || p_id::text, 'task', p_id::text,
    jsonb_build_object('stato', v_status, 'esecutore', v_actor));
  return v_status;
end;
$$;

revoke all on function public.azienda_admin_riepilogo(), public.azienda_admin_anomalie(boolean, integer),
  public.azienda_admin_anomalia_aggiorna(bigint, text, text), public.azienda_admin_sentinel_esegui(),
  public.azienda_admin_task(integer), public.azienda_admin_task_decidi(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.azienda_admin_riepilogo(), public.azienda_admin_anomalie(boolean, integer),
  public.azienda_admin_anomalia_aggiorna(bigint, text, text), public.azienda_admin_sentinel_esegui(),
  public.azienda_admin_task(integer), public.azienda_admin_task_decidi(uuid, text, text)
  to authenticated;

notify pgrst, 'reload schema';
