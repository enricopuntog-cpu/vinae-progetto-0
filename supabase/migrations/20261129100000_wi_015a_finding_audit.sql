-- WI-015 A — correzione dei finding dell'audit indipendente WI-009→WI-014
-- (docs/audits/WI-009-014-RELEASE-AUDIT.md). Nulla viene acceso: regola, promozione, proiezione, proposte, acquisizione,
-- agenti, scheduler e AI restano come sono. Le funzioni toccate NON sono nell'impronta della logica di promozione.
--
--   C-01  l'identita di un agente e la sua credenziale di database (`session_user`), mai un parametro;
--   C-02  nessun task si chiude senza una decisione; «approvato» non significa «eseguito»;
--   C-03  le evidenze sono protette anche da TRUNCATE;
--   A-01  un vino nativo non nasce mentre un lotto di promozione e aperto; l'omonimia si dichiara con un atto tracciato;
--   B-01  ritiro del consenso e decisione del curatore hanno lo stesso ordine di lock;
--   B-02  un invio non valido consuma la quota;
--   B-03  un LWIN assegnato non si trova per codice se la fonte non lo sostiene piu;
--   B-04  cancellare l'account non lascia contatori falsi; minimizzazione predisposta e SPENTA;
--   D-01  «ignorata» e temporanea, riapribile se scade o se la gravita sale;
--   D-02  un controllo annullato non fa sparire l'esecuzione;
--   D-03  il budget AI sorveglia anche il tetto mensile.

-- =============================================================================================
-- C-01 — identita degli agenti
-- =============================================================================================
alter table brain.agents
  add column db_role name unique,
  add column expires_at timestamptz,
  add column disabled_reason text check (disabled_reason is null or length(disabled_reason) between 1 and 500),
  add column max_claims_per_hour integer not null default 60 check (max_claims_per_hour between 1 and 3600),
  add column claim_window_start timestamptz,
  add column claims_in_window integer not null default 0 check (claims_in_window >= 0),
  add column last_claim_at timestamptz;

alter table brain.agents add constraint agents_enabled_needs_identity check (not enabled or db_role is not null);

comment on column brain.agents.db_role is
  'WI-015 (C-01). Login PostgreSQL individuale dell''agente: e la sola prova di identita (session_user). Nessuna password qui.';

-- Una credenziale d'agente non puo essere un ruolo con poteri propri: solo membro di brain_worker.
create or replace function brain.role_is_least_privilege(p_role name)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from pg_catalog.pg_roles r
     where r.rolname = p_role
       and not (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolreplication)
       and r.rolname not in ('postgres', 'authenticator', 'anon', 'authenticated', 'service_role', 'dashboard_user',
                             'brain_worker')
       and r.rolname::text !~ '^(supabase_|pg_|catalog_)'
       and exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                    where m.member = r.oid and g.rolname = 'brain_worker')
       and not exists (select 1 from pg_catalog.pg_auth_members m join pg_catalog.pg_roles g on g.oid = m.roleid
                        where m.member = r.oid and g.rolname <> 'brain_worker'));
$$;

create or replace function brain.agents_identity_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.db_role is not null
     and (tg_op = 'INSERT' or new.db_role is distinct from old.db_role or (new.enabled and not old.enabled))
     and not brain.role_is_least_privilege(new.db_role) then
    raise exception 'brain: la credenziale dell''agente deve essere un login dedicato, membro solo di brain_worker'
      using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger agents_identity_guard before insert or update on brain.agents
  for each row execute function brain.agents_identity_guard();

-- L'identita si legge dalla SESSIONE: in una SECURITY DEFINER `current_user` e il proprietario, mentre `session_user`
-- resta il login autenticato, che `SET ROLE` non cambia (e `SET SESSION AUTHORIZATION` richiede un superuser).
create or replace function brain.current_agent()
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_agent text;
begin
  select a.agent_key into v_agent from brain.agents a
   where a.db_role = session_user and a.enabled and (a.expires_at is null or a.expires_at > clock_timestamp());
  -- ricontrollo a ogni chiamata: un privilegio concesso dopo la registrazione chiude l'agente
  if v_agent is null or not brain.role_is_least_privilege(session_user) then
    raise exception 'brain: sessione non associata a un agente attivo' using errcode = '42501';
  end if;
  return v_agent;
end;
$$;

alter table brain.tasks add column lease_started_at timestamptz;

-- C-02: nessuna chiusura senza decisione; «approvato» e distinto da «completato» (eseguito).
alter table brain.tasks drop constraint tasks_status_check;
alter table brain.tasks add constraint tasks_status_check check (status in
  ('in_attesa', 'assegnato', 'in_approvazione', 'approvato', 'completato', 'respinto', 'fallito', 'annullato'));
alter table brain.tasks add constraint tasks_requires_approval check (requires_approval);

-- C-03
create trigger task_evidence_no_truncate before truncate on brain.task_evidence
  for each statement execute function brain.append_only();
create unique index task_evidence_replay_idx on brain.task_evidence (task_id, kind, md5(detail::text));

-- Il nucleo della coda: nessun ruolo lo esegue; lo chiamano solo le porte dell'agente qui sotto.
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
  if not found or not a.enabled then
    raise exception 'brain: agente inesistente o spento' using errcode = '42501';
  end if;
  if a.claim_window_start is null or a.claim_window_start < clock_timestamp() - interval '1 hour' then
    a.claim_window_start := clock_timestamp();
    a.claims_in_window := 0;
  end if;
  if a.claims_in_window >= a.max_claims_per_hour then
    raise exception 'brain: limite orario di prese raggiunto' using errcode = '53400';
  end if;
  perform brain.reap_expired_leases();
  if exists (select 1 from brain.tasks t where t.lease_agent = p_agent and t.status = 'assegnato') then
    return;
  end if;
  select t.id into v_id from brain.tasks t
   where t.status = 'in_attesa' and t.task_type = any (a.task_types)
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
         attempts = t.attempts + 1, updated_at = now(), version = t.version + 1
   where t.id = v_id;
  perform brain.record_event('task.preso', 'agent:' || p_agent, (select t.correlation_id from brain.tasks t where t.id = v_id),
    'presa:' || v_id::text || ':' || v_token::text, 'task', v_id::text, '{}'::jsonb);
  return query select t.id, v_token, t.task_type, t.titolo, t.payload, t.correlation_id, t.attempts::integer
    from brain.tasks t where t.id = v_id;
end;
$$;

-- Il task del lease: SOLO se e dell'agente, ancora assegnato e non scaduto. Riga bloccata fino al commit.
create or replace function brain.lease_task(p_agent text, p_task uuid, p_lease uuid)
returns brain.tasks language plpgsql volatile set search_path = '' as $$
declare t brain.tasks%rowtype;
begin
  select * into t from brain.tasks x
   where x.id = p_task and x.status = 'assegnato' and x.lease_token = p_lease and x.lease_agent = p_agent
     and x.lease_expires_at >= clock_timestamp()
   for update;
  if not found then
    raise exception 'brain: lease non valido o scaduto' using errcode = '42501';
  end if;
  return t;
end;
$$;

create or replace function brain.add_evidence_core(p_agent text, p_task uuid, p_lease uuid, p_kind text, p_detail jsonb)
returns bigint language plpgsql volatile set search_path = '' as $$
declare v_id bigint;
begin
  perform brain.lease_task(p_agent, p_task, p_lease);
  -- ripetizione della stessa evidenza: stessa riga (nessun doppione da un invio ripetuto)
  select e.id into v_id from brain.task_evidence e
   where e.task_id = p_task and e.kind = p_kind and md5(e.detail::text) = md5(p_detail::text);
  if v_id is not null then
    return v_id;
  end if;
  if (select count(*) from brain.task_evidence e where e.task_id = p_task) >= 50 then
    raise exception 'brain: troppe evidenze per un task' using errcode = '53400';
  end if;
  insert into brain.task_evidence (task_id, kind, detail, recorded_by) values (p_task, p_kind, p_detail, 'agent:' || p_agent)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function brain.finish_task_core(p_agent text, p_task uuid, p_lease uuid, p_success boolean, p_proposta jsonb)
returns text language plpgsql volatile set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  v_status text;
begin
  t := brain.lease_task(p_agent, p_task, p_lease);
  if p_success is null then
    raise exception 'brain: esito mancante' using errcode = '22023';
  end if;
  v_status := case when not p_success then (case when t.attempts >= t.max_attempts then 'fallito' else 'in_attesa' end)
                   else 'in_approvazione' end;
  update brain.tasks
     set status = v_status, proposta = coalesce(p_proposta, proposta), lease_agent = null, lease_token = null,
         lease_expires_at = null, lease_started_at = null, updated_at = now(), version = version + 1
   where id = p_task;
  perform brain.record_event('task.esito', 'agent:' || p_agent, t.correlation_id,
    'task:' || p_task::text || ':' || t.attempts::text, 'task', p_task::text, jsonb_build_object('stato', v_status));
  return v_status;
end;
$$;

-- Porte dell'agente: l'identita e quella della sessione, nessun parametro di identita.
drop function brain.claim_task(text, integer);

create or replace function brain.claim_task(p_lease_seconds integer default 300)
returns table (task_id uuid, lease_token uuid, task_type text, titolo text, payload jsonb, correlation_id uuid, attempt integer)
language sql volatile security definer set search_path = '' as $$
  select * from brain.claim_task_core(brain.current_agent(), p_lease_seconds);
$$;

create or replace function brain.add_evidence(p_task uuid, p_lease uuid, p_kind text, p_detail jsonb)
returns bigint language sql volatile security definer set search_path = '' as $$
  select brain.add_evidence_core(brain.current_agent(), p_task, p_lease, p_kind, p_detail);
$$;

create or replace function brain.finish_task(p_task uuid, p_lease uuid, p_success boolean, p_proposta jsonb default null)
returns text language sql volatile security definer set search_path = '' as $$
  select brain.finish_task_core(brain.current_agent(), p_task, p_lease, p_success, p_proposta);
$$;

-- Rinnovo: solo il proprio lease ancora valido, mai oltre due ore dalla presa.
create or replace function brain.renew_lease(p_task uuid, p_lease uuid, p_lease_seconds integer default 300)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  t brain.tasks%rowtype;
  v_until timestamptz;
begin
  t := brain.lease_task(brain.current_agent(), p_task, p_lease);
  v_until := least(clock_timestamp() + make_interval(secs => least(greatest(coalesce(p_lease_seconds, 300), 30), 3600)),
                   t.lease_started_at + interval '2 hours');
  update brain.tasks set lease_expires_at = v_until, updated_at = now() where id = p_task;
  return v_until;
end;
$$;

-- Revoca: del solo proprietario. Effetto immediato anche sulle sessioni gia aperte (ogni porta ricontrolla `enabled`).
create or replace function brain.disable_agent(p_agent text, p_reason text, p_actor text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_released integer;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'brain: servono esecutore e motivo' using errcode = '22023';
  end if;
  update brain.agents set enabled = false, disabled_reason = btrim(p_reason) where agent_key = p_agent;
  if not found then
    raise exception 'brain: agente inesistente' using errcode = 'P0002';
  end if;
  update brain.tasks
     set status = case when attempts >= max_attempts then 'fallito' else 'in_attesa' end,
         lease_agent = null, lease_token = null, lease_expires_at = null, lease_started_at = null,
         updated_at = now(), version = version + 1
   where lease_agent = p_agent and status = 'assegnato';
  get diagnostics v_released = row_count;
  perform brain.record_event('agente.disabilitato', 'brain', null, null, 'agente', p_agent,
    jsonb_build_object('esecutore', btrim(p_actor), 'motivo', btrim(p_reason), 'lease_liberati', v_released));
  return v_released;
end;
$$;

create or replace function brain.reap_expired_leases()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_n integer;
begin
  update brain.tasks
     set status = case when attempts >= max_attempts then 'fallito' else 'in_attesa' end,
         lease_agent = null, lease_token = null, lease_expires_at = null, lease_started_at = null,
         updated_at = now(), version = version + 1
   where status = 'assegnato' and lease_expires_at < clock_timestamp();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- =============================================================================================
-- D-01 / D-02 / D-03 — Sentinel
-- =============================================================================================
alter table brain.anomalies
  add column ignored_until timestamptz,
  add column ignored_severity text check (ignored_severity in ('P0', 'P1', 'P2', 'P3'));
update brain.anomalies set status = 'aperta' where status = 'ignorata';
alter table brain.anomalies add constraint anomalies_ignored_temporary
  check ((status = 'ignorata') = (ignored_until is not null and ignored_severity is not null));

-- Massimi della soppressione per gravita (modificabili solo dal proprietario): una P0 o P1 torna visibile da sola.
alter table brain.sentinel_settings
  add column ignore_max_hours_p0 integer not null default 24 check (ignore_max_hours_p0 between 1 and 72),
  add column ignore_max_hours_p1 integer not null default 168 check (ignore_max_hours_p1 between 1 and 720),
  add column ignore_max_hours_p23 integer not null default 2160 check (ignore_max_hours_p23 between 1 and 8760);

create or replace function brain.report_anomaly(p_code text, p_subject text, p_source text, p_category text, p_severity text,
  p_titolo text, p_evidence jsonb, p_azione text, p_requires_approval boolean default true)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare
  v_fingerprint text := p_code || case when coalesce(p_subject, '') = '' then '' else ':' || p_subject end;
  o brain.anomalies%rowtype;
  n brain.anomalies%rowtype;
  v_existed boolean;
  v_reopen boolean;
  v_opened boolean;
  v_escalated boolean;
  v_task uuid;
  v_priority integer := case p_severity when 'P0' then 0 else 1 end;
begin
  -- La riga di un'anomalia nuova non esiste ancora: due segnalazioni concorrenti si accodano sull'impronta.
  perform pg_advisory_xact_lock(hashtextextended('brain.anomaly:' || v_fingerprint, 0));
  select * into o from brain.anomalies a where a.fingerprint = v_fingerprint for update;
  v_existed := found;
  v_reopen := v_existed and (o.status = 'risolta'
    or (o.status = 'ignorata' and (o.ignored_until <= clock_timestamp() or p_severity < o.ignored_severity)));
  insert into brain.anomalies as a (fingerprint, code, source, category, severity, titolo, evidence, azione_proposta, requires_approval)
  values (v_fingerprint, p_code, p_source, p_category, p_severity, p_titolo, coalesce(p_evidence, '{}'::jsonb), p_azione,
          coalesce(p_requires_approval, true))
  on conflict (fingerprint) do update
     set last_seen_at = clock_timestamp(), occurrences = a.occurrences + 1, evidence = excluded.evidence,
         severity = excluded.severity, titolo = excluded.titolo,
         status = case when v_reopen then 'aperta' else a.status end,
         resolved_at = case when v_reopen then null else a.resolved_at end,
         ignored_until = case when v_reopen then null else a.ignored_until end,
         ignored_severity = case when v_reopen then null else a.ignored_severity end
  returning a.* into n;
  v_opened := not v_existed or v_reopen;
  v_escalated := v_existed and not v_opened and n.status <> 'ignorata' and p_severity < o.severity;
  -- Solo apertura, riapertura e aggravamento sono eventi; le ricorrenze no.
  if v_opened then
    perform brain.record_event('sentinel.anomalia_aperta', 'sentinel', n.correlation_id, null, 'anomalia', n.id::text,
      jsonb_build_object('code', p_code, 'severita', p_severity));
  elsif v_escalated then
    perform brain.record_event('sentinel.anomalia_aggravata', 'sentinel', n.correlation_id, null, 'anomalia', n.id::text,
      jsonb_build_object('code', p_code, 'da', o.severity, 'a', p_severity));
  end if;
  if (v_opened or v_escalated) and p_severity in ('P0', 'P1') then
    -- Un solo task aperto per anomalia: un aggravamento ne alza la priorita.
    select t.id into v_task from brain.tasks t
     where t.task_type = 'anomalia.verifica' and t.payload ->> 'anomalia_id' = n.id::text
       and t.status in ('in_attesa', 'assegnato', 'in_approvazione')
     limit 1;
    if v_task is null then
      perform brain.enqueue_task('anomalia.verifica', p_titolo, v_priority,
        jsonb_build_object('anomalia_id', n.id, 'code', p_code), 'anomalia:' || n.id::text || ':' || n.occurrences::text,
        true, n.correlation_id);
    else
      update brain.tasks set priority = least(priority, v_priority), updated_at = now() where id = v_task;
    end if;
  end if;
  return n.id;
end;
$$;

-- Controlli deterministici, uno per blocco. Un controllo che fallisce diventa un'anomalia e non ferma gli altri; un
-- annullamento (statement_timeout) viene catturato e i controlli successivi sono dichiarati non eseguiti, cosi
-- l'esecuzione resta sempre registrata. Un controllo riuscito che non trova piu il problema chiude la sua anomalia,
-- anche se era ignorata. Solo conteggi nelle evidenze.
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
     'select count(*) from private.ai_budget_settings s where (s.richieste_giorno > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno = (now() at time zone ''utc'')::date) >= 0.8 * s.richieste_giorno) or (s.richieste_mese > 0 and (select coalesce(sum(c.consentite), 0) from private.ai_consumo_giornaliero c where c.giorno >= date_trunc(''month'', now() at time zone ''utc'')::date) >= 0.8 * s.richieste_mese)',
     'Valutare i tetti: li imposta solo il proprietario del database.'),
    ('proposte_catalogo_vecchie', 'catalog.contributions', 'catalogo', 'P3', 'Proposte al catalogo aperte da oltre 14 giorni',
     'select count(*) from catalog.contributions where status = ''aperta'' and created_at < now() - interval ''14 days''',
     'Rivedere la coda dal pannello del catalogo.'),
    ('conflitti_lwin_nativi', 'catalog.lwin_native_conflicts', 'catalogo', 'P2', 'Vini nativi che la fonte LWIN ora conosce',
     'select count(*) from catalog.lwin_native_conflicts(1000)',
     'Associare il LWIN o dichiarare l''omonimia prima di qualunque promozione.')
  ) as c(code, source, category, severity, titolo, query, azione);
$$;

create or replace function brain.sentinel_run(p_actor text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_run bigint;
  v_check record;
  v_n bigint;
  v_total integer := 0;
  v_failed integer := 0;
  v_found integer := 0;
  v_cancelled boolean := false;
  v_state text;
begin
  if p_actor is null or length(btrim(p_actor)) = 0 or length(p_actor) > 200 then
    raise exception 'brain: serve un esecutore identificato' using errcode = '22023';
  end if;
  -- Una sola esecuzione alla volta.
  if not pg_try_advisory_xact_lock(hashtextextended('brain.sentinel_run', 0)) then
    return jsonb_build_object('esito', 'gia_in_corso');
  end if;
  -- un controllo non resta fermo ad attendere un lock di dominio
  perform set_config('lock_timeout', '3s', true);
  insert into brain.sentinel_runs (triggered_by) values (btrim(p_actor)) returning id into v_run;
  perform brain.reap_expired_leases();

  for v_check in select * from brain.sentinel_checks() loop
    v_total := v_total + 1;
    v_state := null;
    if v_cancelled then
      v_state := '57014';
    else
      begin
        execute v_check.query into v_n;
        if v_n > 0 then
          v_found := v_found + 1;
          perform brain.report_anomaly(v_check.code, '', v_check.source, v_check.category, v_check.severity, v_check.titolo,
            jsonb_build_object('conteggio', v_n), v_check.azione, true);
        else
          update brain.anomalies
             set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel',
                 ignored_until = null, ignored_severity = null
           where fingerprint = v_check.code and status in ('aperta', 'presa_in_carico', 'ignorata');
        end if;
        update brain.anomalies
           set status = 'risolta', resolved_at = clock_timestamp(), responsabile = 'sentinel',
               ignored_until = null, ignored_severity = null
         where fingerprint = 'controllo_non_eseguito:' || v_check.code and status in ('aperta', 'presa_in_carico', 'ignorata');
      exception
        -- `others` non include l'annullamento: va nominato. Il timer di statement_timeout scatta una volta sola.
        when query_canceled then
          v_cancelled := true;
          v_state := '57014';
        when others then
          -- si registra il solo codice SQL: il messaggio potrebbe contenere dati
          v_state := sqlstate;
      end;
    end if;
    if v_state is not null then
      v_failed := v_failed + 1;
      perform brain.report_anomaly('controllo_non_eseguito', v_check.code, 'sentinel', 'sentinel', 'P2',
        'Un controllo di Sentinel non è stato eseguito', jsonb_build_object('controllo', v_check.code, 'sqlstate', v_state),
        'Correggere il controllo: finché fallisce, quel rischio non è sorvegliato.', true);
    end if;
  end loop;

  update brain.sentinel_runs
     set finished_at = clock_timestamp(), checks_run = v_total, checks_failed = v_failed, findings = v_found
   where id = v_run;
  return jsonb_build_object('esito', case when v_failed = 0 then 'completato' else 'parziale' end,
    'controlli', v_total, 'non_eseguiti', v_failed, 'problemi', v_found);
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
           a.requires_approval as richiede_approvazione, a.nota, a.ignored_until as ignorata_fino_al
      from brain.anomalies a
     where (a.status in ('aperta', 'presa_in_carico')) = coalesce(p_aperte, true)
     order by a.severity, a.last_seen_at desc, a.id desc limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

drop function public.azienda_admin_anomalia_aggiorna(bigint, text, text);
create or replace function public.azienda_admin_anomalia_aggiorna(p_id bigint, p_azione text, p_nota text default null,
  p_ore integer default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_status text;
  a brain.anomalies%rowtype;
  v_max integer;
  v_hours integer;
begin
  if p_azione is null or p_azione not in ('prendi_in_carico', 'ignora', 'riapri', 'risolvi') then
    raise exception 'Azione non valida.' using errcode = '22023';
  end if;
  if p_azione in ('ignora', 'risolvi') and v_note is null then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  v_status := case p_azione when 'prendi_in_carico' then 'presa_in_carico' when 'ignora' then 'ignorata'
                            when 'riapri' then 'aperta' else 'risolta' end;
  select * into a from brain.anomalies where id = p_id for update;
  if not found or a.status = v_status then
    raise exception 'Anomalia inesistente o già in quello stato.' using errcode = 'P0002';
  end if;
  if p_azione = 'ignora' then
    select case a.severity when 'P0' then s.ignore_max_hours_p0 when 'P1' then s.ignore_max_hours_p1
                           else s.ignore_max_hours_p23 end into v_max from brain.sentinel_settings s;
    v_hours := coalesce(p_ore, v_max);
    if v_hours < 1 or v_hours > v_max then
      raise exception 'Una % si può ignorare al massimo per % ore.', a.severity, v_max using errcode = '22023';
    end if;
  end if;
  update brain.anomalies
     set status = v_status, responsabile = v_actor, nota = coalesce(v_note, nota),
         resolved_at = case when v_status = 'risolta' then clock_timestamp() end,
         ignored_until = case when v_status = 'ignorata' then clock_timestamp() + make_interval(hours => v_hours) end,
         ignored_severity = case when v_status = 'ignorata' then a.severity end
   where id = p_id;
  perform brain.record_event('sentinel.anomalia_aggiornata', 'admin', a.correlation_id, null, 'anomalia', p_id::text,
    jsonb_strip_nulls(jsonb_build_object('stato', v_status, 'esecutore', v_actor, 'ore', v_hours)));
  return v_status;
end;
$$;

create or replace function public.azienda_admin_task(p_pagina integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_page record;
begin
  perform private.catalog_admin_richiedi();
  select * into v_page from private.catalog_admin_pagina(p_pagina, 20);
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.ordine, r.priorita, r.creato) from (
    select case t.status when 'in_approvazione' then 0 when 'approvato' then 1 when 'in_attesa' then 2
                         when 'assegnato' then 3 else 4 end as ordine,
           t.id, t.task_type as tipo, t.titolo, t.priority as priorita, t.status as stato, t.requires_approval as richiede_approvazione,
           t.proposta, t.attempts as tentativi, t.lease_agent as agente, t.correlation_id as correlazione,
           t.created_at as creato, t.updated_at as aggiornato,
           (select count(*) from brain.task_evidence e where e.task_id = t.id) as evidenze,
           coalesce((select jsonb_agg(jsonb_build_object('tipo', e.kind, 'dettaglio', e.detail, 'registrata_da', e.recorded_by,
                       'quando', e.recorded_at) order by e.id)
              from (select * from brain.task_evidence x where x.task_id = t.id order by x.id desc limit 10) e), '[]'::jsonb)
             as ultime_evidenze
      from brain.tasks t where t.status in ('in_attesa', 'assegnato', 'in_approvazione', 'approvato', 'fallito')
     order by 1, t.priority, t.created_at limit v_page.righe offset v_page.salto) r), '[]'::jsonb);
end;
$$;

-- La decisione registra il giudizio; l'esecuzione e un'altra cosa e si conferma a parte. Nessuna azione parte da qui.
create or replace function public.azienda_admin_task_decidi(p_id uuid, p_decisione text, p_nota text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
  v_status text;
  v_corr uuid;
begin
  if p_decisione is null or p_decisione not in ('approva', 'respingi', 'annulla', 'conferma_eseguito') then
    raise exception 'Decisione non valida.' using errcode = '22023';
  end if;
  if v_note is null then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  v_status := case p_decisione when 'approva' then 'approvato' when 'respingi' then 'respinto'
                               when 'conferma_eseguito' then 'completato' else 'annullato' end;
  update brain.tasks
     set status = v_status, decided_by = v_actor, decided_at = clock_timestamp(), decision_note = v_note,
         updated_at = now(), version = version + 1
   where id = p_id
     and ((p_decisione in ('approva', 'respingi') and status = 'in_approvazione')
          or (p_decisione = 'conferma_eseguito' and status = 'approvato')
          or (p_decisione = 'annulla' and status in ('in_attesa', 'in_approvazione', 'approvato', 'fallito')))
  returning correlation_id into v_corr;
  if v_corr is null then
    raise exception 'Il task non esiste o non è in uno stato decidibile.' using errcode = 'P0002';
  end if;
  perform brain.record_event('task.decisione', 'admin', v_corr, 'decisione:' || p_id::text || ':' || v_status, 'task',
    p_id::text, jsonb_build_object('stato', v_status, 'esecutore', v_actor));
  return v_status;
end;
$$;

revoke all on function brain.role_is_least_privilege(name), brain.agents_identity_guard(), brain.current_agent(),
  brain.claim_task_core(text, integer), brain.lease_task(text, uuid, uuid), brain.add_evidence_core(text, uuid, uuid, text, jsonb),
  brain.finish_task_core(text, uuid, uuid, boolean, jsonb), brain.claim_task(integer),
  brain.add_evidence(uuid, uuid, text, jsonb), brain.finish_task(uuid, uuid, boolean, jsonb),
  brain.renew_lease(uuid, uuid, integer), brain.disable_agent(text, text, text), brain.reap_expired_leases(),
  brain.report_anomaly(text, text, text, text, text, text, jsonb, text, boolean), brain.sentinel_checks(), brain.sentinel_run(text)
  from public, anon, authenticated, service_role, brain_worker;
grant execute on function brain.claim_task(integer), brain.add_evidence(uuid, uuid, text, jsonb),
  brain.finish_task(uuid, uuid, boolean, jsonb), brain.renew_lease(uuid, uuid, integer) to brain_worker;

revoke all on function public.azienda_admin_anomalie(boolean, integer),
  public.azienda_admin_anomalia_aggiorna(bigint, text, text, integer), public.azienda_admin_task(integer),
  public.azienda_admin_task_decidi(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.azienda_admin_anomalie(boolean, integer),
  public.azienda_admin_anomalia_aggiorna(bigint, text, text, integer), public.azienda_admin_task(integer),
  public.azienda_admin_task_decidi(uuid, text, text) to authenticated;

-- =============================================================================================
-- A-01 — vini nativi e promozione
-- =============================================================================================
-- Omonimia accertata dal curatore: il nome coincide ma l'identita e un'altra. Nessuna fusione, nessuna modifica.
create table catalog.native_lwin_distinct (
  wine_id uuid not null references catalog.wines(id),
  lwin7 text not null check (lwin7 ~ '^[0-9]{7}$'),
  note text not null check (length(btrim(note)) between 1 and 1000),
  declared_by text not null,
  declared_at timestamptz not null default now(),
  primary key (wine_id, lwin7)
);
alter table catalog.native_lwin_distinct enable row level security;
revoke all on catalog.native_lwin_distinct from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

create or replace function catalog.lwin_native_conflicts(p_limit integer default 200)
returns table (wine_id uuid, produttore text, nome text, source_record_id bigint, lwin7 text)
language sql stable security definer set search_path = '' as $$
  select w.id, p.name, w.name, r.id, r.external_id
    from catalog.wines w
    join catalog.producers p on p.id = w.producer_id
    join catalog.source_records r
      on r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null
     and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = w.search_key
   where w.origin = 'manual' and w.status = 'active' and w.lwin7 is null
     and not exists (select 1 from catalog.wines x where x.lwin7 = r.external_id)
     and not exists (select 1 from catalog.native_lwin_distinct d where d.wine_id = w.id and d.lwin7 = r.external_id)
   order by w.id, r.external_id
   limit least(greatest(coalesce(p_limit, 200), 1), 1000);
$$;

-- Un vino nativo prende lo stesso lock del motore in modo CONDIVISO e senza attesa: mentre un lotto e aperto (lock
-- esclusivo) non nasce, e mentre sta nascendo il lotto non parte. Dentro il lotto la procedura ricontrolla i conflitti.
create or replace function catalog.add_manual_wine(p_producer_id uuid, p_name text, p_colour text, p_wine_type text, p_sub_type text,
  p_designation text, p_classification text, p_territory_id bigint, p_note text, p_actor text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_key text := catalog.fold_text(p_name);
  v_id uuid;
  v_lock bigint;
begin
  if v_key is null then
    raise exception 'catalog: nome del vino vuoto' using errcode = '22023';
  end if;
  select hashtext('catalog.promote:' || s.id::text) into v_lock from catalog.sources s where s.code = 'LIVEX-LWIN7';
  if v_lock is not null and not pg_try_advisory_xact_lock_shared(v_lock) then
    raise exception 'catalog: una promozione è in corso: riprova al termine del lotto' using errcode = '55P03';
  end if;
  if (select status from catalog.producers where id = p_producer_id) is distinct from 'active' then
    raise exception 'catalog: il produttore deve esistere ed essere attivo' using errcode = 'P0002';
  end if;
  insert into catalog.wines (producer_id, name, name_key, colour, wine_type, sub_type, designation, classification, territory_id, origin, provenance_note)
  values (p_producer_id, btrim(p_name), v_key, p_colour, p_wine_type, p_sub_type, p_designation, p_classification, p_territory_id, 'manual', p_note)
  returning id into v_id;
  perform catalog.record_canonical_event('add_manual_wine', 'wine', v_id::text, v_actor, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function public.catalogo_admin_distingui_lwin(p_wine_id uuid, p_lwin7 text, p_nota text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := private.catalog_admin_richiedi();
  v_note text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if v_note is null then
    raise exception 'Il motivo è obbligatorio.' using errcode = '22023';
  end if;
  if not exists (select 1 from catalog.wines w join catalog.source_records r
                   on r.status = 'Live' and r.scope = 'wine' and r.removed_from_source_at is null and r.external_id = p_lwin7
                  and public.vini_normalizza(coalesce(r.payload ->> 'producer_name', '') || ' ' || coalesce(r.payload ->> 'wine', '')) = w.search_key
                  where w.id = p_wine_id and w.origin = 'manual' and w.status = 'active' and w.lwin7 is null
                    and not exists (select 1 from catalog.wines x where x.lwin7 = r.external_id)) then
    raise exception 'La coppia indicata non è un conflitto aperto.' using errcode = 'P0002';
  end if;
  insert into catalog.native_lwin_distinct (wine_id, lwin7, note, declared_by) values (p_wine_id, p_lwin7, v_note, v_actor)
  on conflict do nothing;
  perform catalog.record_canonical_event('native_lwin_distinct', 'wine', p_wine_id::text, v_actor,
    jsonb_build_object('lwin7', p_lwin7, 'motivo', v_note));
  return true;
end;
$$;
revoke all on function public.catalogo_admin_distingui_lwin(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.catalogo_admin_distingui_lwin(uuid, text, text) to authenticated;

-- =============================================================================================
-- B — proposte al catalogo
-- =============================================================================================
-- B-04: periodo di conservazione del legame utente -> proposta DECISA. NULL (default) = nessuna azione: lo sceglie il
-- founder. Nessuno scheduler lo chiama.
alter table catalog.intake_settings
  add column user_link_retention_days integer check (user_link_retention_days between 30 and 3650);

create or replace function catalog.minimize_decided_submissions(p_actor text)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor text := catalog.require_actor(p_actor);
  v_days integer;
  v_n integer := 0;
begin
  select user_link_retention_days into v_days from catalog.intake_settings;
  if v_days is null then
    return 0;
  end if;
  update catalog.contribution_submissions s
     set user_id = null, public_wine_id = null, source_ref = coalesce(s.source_ref, 'minimizzata:' || s.id::text)
    from catalog.contributions c
   where c.id = s.contribution_id and s.user_id is not null
     and c.status in ('collegata', 'creata', 'rifiutata', 'duplicata', 'gia_collegata')
     and coalesce(c.reviewed_at, c.last_seen_at) < now() - make_interval(days => v_days);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform catalog.record_canonical_event('minimize_submissions', 'intake', null, v_actor,
      jsonb_build_object('scollegate', v_n, 'giorni', v_days));
  end if;
  return v_n;
end;
$$;
revoke all on function catalog.minimize_decided_submissions(text)
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;

-- B-01/B-04: il contatore e lo stato seguono le partecipazioni, qualunque cosa le tolga (ritiro o cancellazione
-- dell'account). Ordine dei lock: la riga della proposta prima di ogni conteggio; il conteggio e un'istruzione
-- successiva, quindi vede cio che un decisore concorrente ha gia confermato.
create or replace function catalog.contribution_submissions_removed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from catalog.contributions c where c.id = old.contribution_id for update;
  update catalog.contributions c
     set submissions_count = (select count(*) from catalog.contribution_submissions x where x.contribution_id = c.id),
         status = case when c.status = 'aperta'
                        and not exists (select 1 from catalog.contribution_submissions x where x.contribution_id = c.id)
                       then 'ritirata' else c.status end
   where c.id = old.contribution_id;
  return null;
end;
$$;
revoke all on function catalog.contribution_submissions_removed()
  from public, anon, authenticated, service_role, catalog_curator, catalog_loader;
create trigger contribution_submissions_removed after delete on catalog.contribution_submissions
  for each row execute function catalog.contribution_submissions_removed();

create or replace function public.catalogo_proposta_ritira(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_contribution bigint;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  -- prima la proposta (stesso ordine della decisione del curatore), poi la partecipazione
  select c.id, c.status into v_contribution, v_status
    from catalog.contributions c
   where c.id = (select s.contribution_id from catalog.contribution_submissions s where s.id = p_id and s.user_id = v_uid)
     for update;
  if v_contribution is null or v_status <> 'aperta' then
    return false;
  end if;
  delete from catalog.contribution_submissions s where s.id = p_id and s.user_id = v_uid;
  return found;
end;
$$;

-- Come WI-011, con la riga della proposta bloccata prima di aggiungere la partecipazione.
create or replace function catalog.contribution_register(p_origin text, p_data jsonb, p_user_id uuid,
  p_public_wine_id uuid, p_source_ref text)
returns table (contribution_id bigint, nuova boolean)
language plpgsql volatile set search_path = '' as $$
#variable_conflict use_column
declare
  v_identity jsonb := catalog.contribution_identity(p_data);
  v_key text;
  v_hash text;
  v_id bigint;
  v_new boolean := false;
  v_match record;
  v_missing text[] := '{}';
  v_submission bigint;
  v_auto boolean;
  v_candidate jsonb;
begin
  v_key := public.vini_normalizza((v_identity ->> 'produttore') || ' ' || (v_identity ->> 'nome'));
  v_hash := md5(public.vini_normalizza(v_identity ->> 'produttore') || chr(31)
             || public.vini_normalizza(v_identity ->> 'nome') || chr(31)
             || coalesce(v_identity ->> 'annata', case when (v_identity ->> 'non_millesimato')::boolean then 'nv' else '' end)
             || chr(31) || coalesce(v_identity ->> 'formato_ml', '') || chr(31) || coalesce(v_identity ->> 'lwin7', ''));
  -- Eventi concorrenti sulla stessa identità si accodano qui: nasce una sola proposta.
  perform pg_advisory_xact_lock(hashtextextended('catalog.contribution:' || v_hash, 0));

  select c.id into v_id from catalog.contributions c where c.identity_hash = v_hash for update;
  if v_id is null then
    select * into v_match from catalog.contribution_match(v_identity, p_public_wine_id);
    if not (v_identity ? 'annata') and not coalesce((v_identity ->> 'non_millesimato')::boolean, false) then
      v_missing := v_missing || 'annata'::text;
    end if;
    if not (v_identity ? 'formato_ml') then v_missing := v_missing || 'formato'::text; end if;
    if not (v_identity ? 'paese') then v_missing := v_missing || 'paese'::text; end if;
    if not (v_identity ? 'regione') then v_missing := v_missing || 'regione'::text; end if;
    insert into catalog.contributions (identity_hash, identity, identity_key, first_origin, trust, match_kind,
                                       match_candidates, missing_fields)
    values (v_hash, v_identity, v_key, p_origin,
            case when p_origin = 'ocr' then 'ocr_confermato_utente'
                 when p_origin = 'annuncio' then 'annuncio_pubblico' else 'dichiarato_utente' end,
            v_match.match_kind, v_match.candidates, v_missing)
    returning id into v_id;
    v_new := true;

    -- Regola deterministica, SPENTA di default: collegamento già approvato, annata coincidente, nulla di nuovo.
    select s.auto_close_known_enabled into v_auto from catalog.intake_settings s;
    if v_auto and v_match.match_kind = 'autorevole' and p_origin <> 'correzione' and not (v_identity ? 'formato_ml') then
      v_candidate := v_match.candidates -> 0;
      if (v_identity ->> 'annata') is not distinct from (v_candidate ->> 'annata') then
        update catalog.contributions
           set status = 'gia_collegata', resolved_wine_id = (v_candidate ->> 'wine_id')::uuid,
               resolved_vintage_id = (v_candidate ->> 'vintage_id')::uuid
         where id = v_id;
        perform catalog.record_canonical_event('contribution_auto_close', 'contribution', v_id::text,
                                               'regola:auto_close_known', '{}'::jsonb);
      end if;
    end if;
  end if;

  insert into catalog.contribution_submissions (contribution_id, origin, user_id, public_wine_id, source_ref)
  values (v_id, p_origin, p_user_id, p_public_wine_id, p_source_ref)
  on conflict do nothing
  returning id into v_submission;
  if v_submission is not null then
    update catalog.contributions c
       set submissions_count = c.submissions_count + 1, last_seen_at = now(),
           status = case when c.status = 'ritirata' then 'aperta' else c.status end
     where c.id = v_id;
  end if;
  return query select v_id, v_new;
end;
$$;

-- B-02: un invio con dati non validi non solleva un errore (che annullerebbe anche il consumo della quota): risponde
-- `non_valida`. La quota si consuma una volta per richiesta, valida o no.
create or replace function public.catalogo_proponi(p_origine text, p_dati jsonb, p_consenso boolean,
  p_wine_slug text default null)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_settings catalog.intake_settings%rowtype;
  v_wine uuid;
  v_result record;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  select * into v_settings from catalog.intake_settings;
  if not coalesce(v_settings.user_proposals_enabled, false) then
    raise exception 'Le proposte al catalogo non sono attive.' using errcode = 'P0001';
  end if;
  if p_consenso is not true then
    raise exception 'Serve il tuo consenso per inviare questi dati al catalogo.' using errcode = 'P0001';
  end if;
  if p_origine is null or p_origine not in ('cantina', 'manuale', 'ocr', 'correzione') then
    raise exception 'Origine non valida.' using errcode = '22023';
  end if;
  if p_wine_slug is not null then
    -- Un solo messaggio per «non esiste» e «non è tuo»: nessun modo di sondare i vini altrui.
    select w.id into v_wine from public.wines w
     where w.slug = p_wine_slug
       and exists (select 1 from public.bottle_units bu
                    where bu.owner_id = v_uid and bu.wine_id = w.id and bu.deleted_at is null);
    if v_wine is null then
      raise exception 'Puoi proporre solo i vini presenti nella tua Cantina.' using errcode = 'P0001';
    end if;
  elsif p_origine in ('cantina', 'correzione') then
    raise exception 'Serve il vino della tua Cantina.' using errcode = '22023';
  end if;
  perform private.rate_limit_consume('catalogo-proposte', 'user:' || v_uid::text, v_settings.user_daily_limit, 86400);
  begin
    select * into v_result from catalog.contribution_register(p_origine, p_dati, v_uid, v_wine, null);
  exception when sqlstate '22023' then
    return 'non_valida';
  end;
  -- Nessun dettaglio sulle corrispondenze: potrebbero riguardare identità non ancora pubbliche.
  return 'ricevuta';
end;
$$;

-- =============================================================================================
-- B-03 — ricerca canonica: il LWIN assegnato vale solo finche la fonte autorizzata lo sostiene (record Live)
-- =============================================================================================
create or replace function public.vini_canonici_cerca(
  p_produttore text default ''::text,
  p_nome text default ''::text,
  p_limite integer default 15,
  p_codice text default null::text
) returns table(
  fonte text, vino_id uuid, lwin7 text, produttore text, nome text, paese text, territorio text, territorio_tipo text,
  denominazione text, tipo text, colore text, punteggio integer, livello text, fonte_nome text, fonte_licenza text,
  attribuzione text)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  c_stop constant text[] := array[
    'il','lo','la','gli','le','un','una','di','del','dello','della','dei','degli','delle',
    'de','da','the','of','et','and','en','des','du','docg','doc','igt','igp','dop','aoc','aop'];
  c_filler constant text[] := array[
    'azienda','agricola','az','agr','societa','soc','cantina','cantine','tenuta','tenute',
    'fattoria','casa','vinicola','cascina','cooperativa','srl','spa','ss','domaine','chateau',
    'bodega','weingut','vigneti','vignaioli'];
  c_limite_utente constant integer := 40;
  v_qp text := public.vini_normalizza(left(p_produttore, 120));
  v_qn text := public.vini_normalizza(left(p_nome, 120));
  v_qk text;
  v_limite integer := least(greatest(coalesce(p_limite, 15), 1), 20);
  -- WI-011: l'identificativo è il LWIN-7 oppure l'UUID del vino (l'identità stabile, anche senza LWIN).
  v_uuid uuid := case when btrim(coalesce(p_codice, '')) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                      then btrim(p_codice)::uuid end;
  v_codice text;
  v_uid uuid := auth.uid();
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
  -- Interruttore spento (default) o assente: nulla è pubblico e nulla viene consumato.
  if not coalesce((select s.enabled from catalog.public_projection_settings s), false) then
    return;
  end if;
  if v_uuid is null then
    v_codice := nullif(regexp_replace(left(coalesce(p_codice, ''), 40), '[^0-9]', '', 'g'), '');
  end if;
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tp
    from unnest(string_to_array(v_qp, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t <> all (c_filler) and t !~ '^(19|20)[0-9]{2}$';
  select coalesce(array_agg(distinct t), array[]::text[]) into v_tn
    from unnest(string_to_array(v_qn, ' ')) t
    where length(t) >= 3 and t <> all (c_stop) and t !~ '^(19|20)[0-9]{2}$' and t <> all (v_tp);
  v_tok := (v_tp || v_tn)[1:6];
  v_qk := btrim(v_qp || ' ' || v_qn);
  if v_codice is null and v_uuid is null and coalesce(array_length(v_tok, 1), 0) = 0 then
    return;
  end if;
  -- Limite per identità (WI-008): l'identità viene dal token, mai da parametri. Solo le sessioni utente: il percorso di
  -- servizio è limitato per utente dal gate AI, in una transazione propria.
  if v_uid is not null then
    perform private.rate_limit_consume('ricerca-canonica', 'user:' || v_uid::text, c_limite_utente, 60);
  end if;

  for v_tier in 1..4 loop
    exit when jsonb_array_length(v_acc) >= v_limite;
    if v_tier = 1 then
      if v_uuid is not null then
        -- UUID: la riga stessa o il vino in cui è confluita (al massimo 20 passi).
        v_where := format('w.id in (with recursive r(cur, depth) as (select %L::uuid, 0 '
                          'union all select m.merged_into, r.depth + 1 from r '
                          'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                          'select cur from r)', v_uuid);
      else
        -- Identificativo LWIN-7 (anche di un record Combined, risolto sul vino di destinazione).
        continue when v_codice is null or length(v_codice) <> 7;
        -- Un solo `IN` su due rami indicizzati (btree su lwin7, indice parziale sugli alias): con un `OR`
        -- il piano ricadeva sulla scansione sequenziale dei vini.
        -- Il Combined si risolve sul vino di destinazione seguendo le fusioni (al massimo 20 passi) SOLO a
        -- partire dall'alias cercato: `catalog.wine_resolution` calcolerebbe la chiusura di tutti i vini.
        v_where := format('w.id in (select x.id from catalog.wines x where x.lwin7 = %1$L '
                          'and (x.origin <> ''manual'' or exists (select 1 from catalog.source_records lr '
                          'join catalog.sources ls on ls.id = lr.source_id and ls.authorization_status = ''authorized'' '
                          'where lr.id = x.lwin_assigned_record_id and lr.status = ''Live'' and lr.removed_from_source_at is null)) '
                          'union select t.cur from (with recursive r(cur, depth) as ('
                          'select a.wine_id, 0 from catalog.entity_aliases a '
                          'where a.kind = ''combined_lwin'' and a.alias_key = %1$L and a.wine_id is not null '
                          'union all select m.merged_into, r.depth + 1 from r '
                          'join catalog.wines m on m.id = r.cur where m.merged_into is not null and r.depth < 20) '
                          'select cur from r) t)', v_codice);
      end if;
      v_score := '1000';
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

    -- Visibilità scritta qui, mai da parametri: vini promossi da una fonte ancora autorizzata, oppure identità
    -- native che un curatore ha pubblicato. In entrambi i casi vino e produttore attivi.
    -- L'ordine (punteggio, search_key, lwin7, id) si applica all'INSIEME COMPLETO delle corrispondenze e il tetto
    -- delle righe richieste viene DOPO: nessun limite di scansione precede l'ordinamento.
    -- Il LWIN assegnato a un'identità nativa si mostra solo finché la fonte che lo attesta resta autorizzata.
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb) from (
        select c.*, %3$s as livello_n,
               row_number() over (order by c.punteggio desc, c.search_key, c.lwin7, c.vino_id) as ord
        from (
          select w.id as vino_id,
                 case when w.origin = 'promotion' or als.id is not null then w.lwin7 end as lwin7,
                 w.search_key, p.name as produttore, w.name as nome,
                 cp.name as paese, t.name as territorio, t.kind as territorio_tipo,
                 w.designation as denominazione, w.wine_type as tipo, w.colour as colore,
                 (%1$s) as punteggio,
                 coalesce(s.name, 'Catalogo Vinea') as fonte_nome,
                 s.license as fonte_licenza,
                 case when w.origin = 'promotion' then s.attribution_text
                      else 'Scheda del catalogo Vinea, verificata da un curatore.'
                           || coalesce(' Codice LWIN: ' || als.attribution_text, '') end as attribuzione
          from catalog.wines w
          join catalog.producers p0 on p0.id = w.producer_id
          join catalog.producers p on p.id = case when p0.status = 'merged' then catalog.producer_final(p0.id) else p0.id end
                                  and p.status = 'active'
          left join catalog.territories cp on cp.id = p.country_territory_id
          left join catalog.territories t on t.id = w.territory_id
          left join catalog.sources s on s.id = w.source_id and s.authorization_status = 'authorized'
          left join lateral (
            select x.id, x.attribution_text from catalog.source_records ar
              join catalog.sources x on x.id = ar.source_id and x.authorization_status = 'authorized'
             where ar.id = w.lwin_assigned_record_id and ar.status = 'Live' and ar.removed_from_source_at is null) als on true
          where w.status = 'active'
            and ((w.origin = 'promotion' and s.id is not null)
                 or (w.origin = 'manual' and w.native_published_at is not null))
            and (%2$s)
            and not (w.id = any (%4$L::uuid[]))
          order by punteggio desc, w.search_key, w.lwin7, w.id
          limit %5$s
        ) c
        order by ord
      ) r$q$, v_score, v_where, v_tier, v_seen, v_limite - jsonb_array_length(v_acc))
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
$function$;

revoke all on function public.vini_canonici_cerca(text, text, integer, text) from public, anon;
grant execute on function public.vini_canonici_cerca(text, text, integer, text) to authenticated, service_role;

do $verifica$
begin
  if catalog.promotion_logic_fingerprint('lwin-conservative-v1') is null then
    raise exception 'WI-015: una dipendenza dell''impronta non esiste piu';
  end if;
end $verifica$;

notify pgrst, 'reload schema';
