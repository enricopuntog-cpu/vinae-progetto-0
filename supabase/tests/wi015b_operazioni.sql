-- WI-015B (griglia wi015b): operazioni autonome. Acquisizione dagli annunci con ripetizioni limitate; lavoro del
-- catalogo e della qualita nel Company Brain (evento -> task -> lease -> contesto -> evidenza -> proposta ->
-- approvazione o chiusura consentita); scheduler unico con arretramento e sospensione; ingestione ristretta dei
-- segnali tecnici che non si chiude col solo verde; costi AI con prenotazione sotto lock; cruscotto e rapporto.
-- La prova con login reali e pg_cron vero e in `wi015_operazioni.sh`.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi015b: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi015b: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
end $$;

create temp table esiti (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create temp table fx (k text primary key, v text) on commit drop;

create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;
create function pg_temp.fai(p anyelement) returns void language sql as $f$ select $f$;
create function pg_temp.f(p_k text) returns text language sql as $f$ select v from fx where k = p_k $f$;
create function pg_temp.j(p_k text) returns jsonb language sql as $f$ select v::jsonb from fx where k = p_k $f$;

create function pg_temp.prova(p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  execute p_sql into v;
  return 'OK:' || coalesce(v, '');
exception when others then
  return sqlstate;
end;
$f$;

create function pg_temp.come(p_ruolo text, p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    execute format('set local role %I', p_ruolo);
    execute p_sql into v;
    reset role;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    return 'OK:' || coalesce(v, '');
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    return sqlstate;
  end;
end;
$f$;

insert into auth.users (id, instance_id, aud, role, email)
values ('15100000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@wi015b.test'),
       ('15100000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi015b.test');
insert into public.user_roles (user_id, role) values ('15100000-0000-4000-8000-0000000000ad', 'admin') on conflict do nothing;
insert into fx values ('a', '15100000-0000-4000-8000-00000000000a'), ('admin', '15100000-0000-4000-8000-0000000000ad');

set local session_replication_role = replica;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.sentinel_runs;
delete from brain.monitor_signals;
delete from brain.events;
-- i costi AI delle prove precedenti del gate (wi004 usa la function vera) non devono contare qui
delete from private.ai_chiamate;
delete from private.ai_consumo_giornaliero;
delete from private.ai_tariffe;
insert into catalog.source_records (source_id, external_id, status, scope, country, payload, raw, content_hash, first_seen_run, changed_in_run)
select s.id, x.lwin, x.stato, 'wine', 'Italy',
       jsonb_build_object('producer_name', x.p, 'wine', x.w, 'colour', x.colore), '{}'::jsonb, repeat('a', 64), gen_random_uuid(), gen_random_uuid()
  from catalog.sources s,
       (values ('7151001', 'Live', 'Wi015b Fonte', 'Collina', 'Red'),
               ('7151002', 'Deleted', 'Wi015b Ritirato', 'Vecchio', 'Red')) as x(lwin, stato, p, w, colore)
 where s.code = 'LIVEX-LWIN7';
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------------------------
-- D: acquisizione dagli annunci con ripetizioni limitate
-- ---------------------------------------------------------------------------------------------
insert into public.wines (id, slug, produttore, nome, annata, regione, denominazione, tipo, formato, provenienza)
values ('15100000-0000-4000-8000-000000000101', 'wi015b-buono', 'Wi015b Cantina', 'Vino Buono', 2020, 'Liguria', 'IGT', 'Rosso', '0,75 L', 'staff'),
       ('15100000-0000-4000-8000-000000000102', 'wi015b-rotto', 'vedi https://x.test', 'Vino Rotto', 2020, 'Liguria', 'IGT', 'Rosso', '0,75 L', 'staff');
-- La vista pubblica e il confine dell'acquisizione: qui la si sostituisce con due righe controllate.
create schema zz_wi015b;
create table zz_wi015b.annunci (id uuid, wine_id uuid, produttore text, nome text, annata integer, regione text,
  denominazione text, tipo text, formato text, published_at timestamptz);
insert into zz_wi015b.annunci values
 ('15100000-0000-4000-8000-000000000302', '15100000-0000-4000-8000-000000000102', 'vedi https://x.test', 'Vino Rotto', 2020, 'Liguria', 'IGT', 'Rosso', '0,75 L', now() - interval '2 days'),
 ('15100000-0000-4000-8000-000000000301', '15100000-0000-4000-8000-000000000101', 'Wi015b Cantina', 'Vino Buono', 2020, 'Liguria', 'IGT', 'Rosso', '0,75 L', now() - interval '1 day');
insert into fx values ('vista', pg_get_viewdef('public.public_listings'::regclass));
do $v$
declare v_colonne text;
begin
  select string_agg(case when a.attname in ('id', 'wine_id', 'produttore', 'nome', 'annata', 'regione', 'denominazione', 'tipo', 'formato', 'published_at')
                         then format('z.%I::%s as %I', a.attname, format_type(a.atttypid, a.atttypmod), a.attname)
                         else format('null::%s as %I', format_type(a.atttypid, a.atttypmod), a.attname) end, ', ' order by a.attnum)
    into v_colonne
    from pg_attribute a where a.attrelid = 'public.public_listings'::regclass and a.attnum > 0 and not a.attisdropped;
  execute format('create or replace view public.public_listings as select %s from zz_wi015b.annunci z', v_colonne);
end $v$;

update catalog.intake_settings set listing_harvest_enabled = true, harvest_max_attempts = 2;
insert into fx values ('h1', catalog.harvest_listings(1, 'wi015b')::text);
insert into fx values ('h2', catalog.harvest_listings(1, 'wi015b')::text);
insert into fx values ('h3', catalog.harvest_listings(1, 'wi015b')::text);
select pg_temp.rec(1, 'un annuncio non valido si ritenta un numero limitato di volte e poi non blocca la coda',
  (pg_temp.j('h1') ->> 'scartati') = '1' and (pg_temp.j('h2') ->> 'scartati') = '1'
  and (pg_temp.j('h3') ->> 'nuove_proposte') = '1' and (pg_temp.j('h3') ->> 'esauriti') = '1'
  and (select attempts = 2 and last_sqlstate = '22023' from catalog.intake_failures where source_ref = 'annuncio:15100000-0000-4000-8000-000000000302'),
  pg_temp.f('h1') || pg_temp.f('h2') || pg_temp.f('h3'));
insert into fx values ('h4', catalog.harvest_listings(10, 'wi015b')::text);
select pg_temp.rec(2, 'ripetuta: idempotente, nessuna nuova lettura e nessun doppione',
  (pg_temp.j('h4') ->> 'letti') = '0' and (select count(*) from catalog.contributions) = 1
  and (select count(*) from catalog.contribution_submissions) = 1
  and not has_table_privilege('authenticated', 'catalog.intake_failures', 'SELECT'));

-- ---------------------------------------------------------------------------------------------
-- E: lavoro del catalogo
-- ---------------------------------------------------------------------------------------------
insert into fx values ('q1', brain.enqueue_catalog_work(100, 'wi015b')::text);
insert into fx values ('q2', brain.enqueue_catalog_work(100, 'wi015b')::text);
select pg_temp.rec(3, 'una proposta aperta diventa un task una volta sola',
  pg_temp.f('q1') = '1' and pg_temp.f('q2') = '0' and (select count(*) from brain.tasks where task_type = 'catalogo.proposta') = 1);

create role wi015b_cm login;
create role wi015b_dq login;
create role wi015b_tm login;
grant brain_worker to wi015b_cm, wi015b_dq, wi015b_tm;
insert into brain.agents (agent_key, descrizione, db_role, enabled, task_types) values
  ('catalog_manager', 'prova', 'wi015b_cm', true, '{catalogo.proposta}'),
  ('data_quality', 'prova', 'wi015b_dq', true, '{qualita.scansione}'),
  ('technical_monitor', 'prova', 'wi015b_tm', true, '{tecnico.segnale}');
create temp table presa_cm on commit drop as select * from brain.claim_task_core('catalog_manager', 300);
insert into fx values ('ctx', brain.agent_context_core('catalog_manager', (select task_id from presa_cm), (select lease_token from presa_cm))::text);
select pg_temp.rec(4, 'il contesto porta i dati del vino, la corrispondenza e i candidati, senza dati della persona',
  pg_temp.j('ctx') ->> 'stato' = 'aperta' and pg_temp.j('ctx') -> 'dati' ->> 'nome' = 'Vino Buono'
  and pg_temp.j('ctx') ->> 'corrispondenza' = 'sconosciuto' and jsonb_typeof(pg_temp.j('ctx') -> 'candidati') = 'array'
  and pg_temp.f('ctx') !~* 'user|15100000-0000-4000-8000-00000000000a|@', pg_temp.f('ctx'));
select pg_temp.rec(5, 'un altro agente non legge il contesto di un lease non suo',
  pg_temp.prova(format('select brain.agent_context_core(''data_quality'', %L, %L)::text', (select task_id from presa_cm), (select lease_token from presa_cm))) = '42501');
select pg_temp.rec(6, 'chiusura consentita rifiutata finche la proposta e aperta',
  pg_temp.prova(format('select brain.close_if_allowed_core(''catalog_manager'', %L, %L)', (select task_id from presa_cm), (select lease_token from presa_cm))) = '42501');
select pg_temp.fai((brain.add_evidence_core('catalog_manager', (select task_id from presa_cm), (select lease_token from presa_cm), 'corrispondenza', '{"candidati":0}'))::text);
select pg_temp.fai((brain.finish_task_core('catalog_manager', (select task_id from presa_cm), (select lease_token from presa_cm), true, '{"azione":"crea"}'))::text);
-- il curatore decide la proposta: il task residuo si chiude con la sola regola consentita
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_proposta_decidi(%s, ''rifiuta'', ''{}'', ''prova'')', (select id from catalog.contributions limit 1))))::text);
insert into fx values ('obs', brain.close_obsolete_catalog_tasks('wi015b')::text);
select pg_temp.rec(7, 'proposta decisa dal curatore: il task in attesa di giudizio si chiude con la regola, con evento',
  pg_temp.f('obs') = '1'
  and (select status = 'annullato' and decided_by = 'regola:chiusura_consentita' from brain.tasks where task_type = 'catalogo.proposta')
  -- (al momento di questo caso esiste un solo task di catalogo)
  and exists (select 1 from brain.events where event_type = 'task.chiusura_consentita'));

-- una proposta riaperta da un nuovo invio torna in coda: la chiusura per regola non la nasconde per sempre
update catalog.contributions set status = 'aperta', reviewed_by = null, reviewed_at = null, review_note = null;
insert into fx values ('rq1', brain.enqueue_catalog_work(100, 'wi015b')::text);
insert into fx values ('rq2', brain.enqueue_catalog_work(100, 'wi015b')::text);
select pg_temp.rec(37, 'proposta riaperta: un nuovo task, una volta sola; il vecchio resta nello storico',
  pg_temp.f('rq1') = '1' and pg_temp.f('rq2') = '0'
  and (select count(*) = 2 and count(*) filter (where status = 'in_attesa') = 1 from brain.tasks where task_type = 'catalogo.proposta'));
update catalog.contributions set status = 'rifiutata', reviewed_by = 'admin:prova', reviewed_at = now(), review_note = 'prova';
select pg_temp.fai((brain.close_obsolete_catalog_tasks('wi015b'))::text);

-- E: qualita dei dati
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  $q$select public.catalogo_admin_azione('nuovo_vino', '{"produttore":"Wi015b Fonte","nome":"Collina","conferma_non_duplicato":true}'::jsonb, 'curatore')$q$))::text);
select pg_temp.rec(8, 'la scansione di qualita nasce una volta al giorno e non si accumula',
  brain.enqueue_quality_scan('wi015b') = 1 and brain.enqueue_quality_scan('wi015b') = 0);
create temp table presa_dq on commit drop as select * from brain.claim_task_core('data_quality', 300);
insert into fx values ('dq', brain.agent_context_core('data_quality', (select task_id from presa_dq), (select lease_token from presa_dq))::text);
select pg_temp.rec(9, 'rileva con query deterministiche il conflitto nativo/fonte e il vino senza annata, con soli riferimenti',
  (select bool_and(exists (select 1 from jsonb_array_elements(pg_temp.j('dq') -> 'rilievi') r where r ->> 'codice' = c and (r ->> 'conteggio')::int >= 1))
     from unnest(array['conflitti_nativi', 'nativi_senza_annata', 'produttori_senza_paese']) c), pg_temp.f('dq'));
select pg_temp.rec(10, 'con rilievi la chiusura autonoma e rifiutata',
  pg_temp.prova(format('select brain.close_if_allowed_core(''data_quality'', %L, %L)', (select task_id from presa_dq), (select lease_token from presa_dq))) = '42501');
select pg_temp.fai((brain.finish_task_core('data_quality', (select task_id from presa_dq), (select lease_token from presa_dq), true, '{"azione":"rivedi_coda"}'))::text);

-- ---------------------------------------------------------------------------------------------
-- H: ingestione dei segnali tecnici
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(11, 'ingestione chiusa: ruoli API e brain_worker senza porta; il proprietario non e un mittente',
  (select bool_and(not has_function_privilege(r, 'brain.ingest_signal(text,text,text,timestamptz,text,jsonb)', 'EXECUTE'))
     from unnest(array['anon', 'authenticated', 'service_role', 'brain_worker']) r)
  and has_function_privilege('brain_ingest', 'brain.ingest_signal(text,text,text,timestamptz,text,jsonb)', 'EXECUTE')
  and pg_temp.prova('select brain.ingest_signal(''technical_heartbeat'', ''x'', ''ok'', now(), null, ''{}'')') = '42501');
select pg_temp.rec(12, 'fonte spenta, sconosciuta, orario futuro, riferimento libero o conteggi non numerici: rifiutati',
  pg_temp.prova('select brain.ingest_signal_core(''wi015b'', ''technical_heartbeat'', ''e0'', ''guasto'', now(), null, ''{}'')') = '42501'
  and pg_temp.prova('select brain.ingest_signal_core(''wi015b'', ''ignota'', ''e0'', ''ok'', now(), null, ''{}'')') = '42501');
update brain.monitor_sources set enabled = true where source_key in ('technical_heartbeat', 'offsite_backup_freshness');
update esiti set passed = passed
  and pg_temp.prova('select brain.ingest_signal_core(''wi015b'', ''technical_heartbeat'', ''e1'', ''guasto'', now() + interval ''1 hour'', null, ''{}'')') = '22023'
  and pg_temp.prova('select brain.ingest_signal_core(''wi015b'', ''technical_heartbeat'', ''e1'', ''guasto'', now(), ''scrivi a mario@example.test'', ''{}'')') = '22023'
  and pg_temp.prova('select brain.ingest_signal_core(''wi015b'', ''technical_heartbeat'', ''e1'', ''guasto'', now(), null, ''{"log":"testo libero"}'')') = '22023'
 where id = 12;
insert into fx values ('s1', brain.ingest_signal_core('wi015b', 'technical_heartbeat', 'run:1', 'guasto', now() - interval '20 minutes',
  'https://github.com/example/repo/actions/runs/1', '{"findings":1}'));
insert into fx values ('s1b', brain.ingest_signal_core('wi015b', 'technical_heartbeat', 'run:1', 'guasto', now() - interval '20 minutes', null, '{}'));
select pg_temp.rec(13, 'segnale idempotente per evento; un guasto apre anomalia e un solo task tecnico',
  pg_temp.f('s1') = 'registrato' and pg_temp.f('s1b') = 'duplicato'
  and (select count(*) from brain.monitor_signals) = 1
  and (select status = 'aperta' from brain.anomalies where fingerprint = 'segnale_monitor:technical_heartbeat')
  and (select count(*) from brain.tasks where task_type = 'tecnico.segnale') = 1);
select pg_temp.fai((brain.ingest_signal_core('wi015b', 'technical_heartbeat', 'run:2', 'ok', now() - interval '5 minutes', null, '{}'))::text);
select pg_temp.rec(14, 'un verde successivo NON chiude il problema: resta aperto, con la nota del ritorno al verde (issue #322)',
  (select status = 'aperta' and evidence ->> 'tornato_verde' is not null from brain.anomalies where fingerprint = 'segnale_monitor:technical_heartbeat'));
create temp table presa_tm on commit drop as select * from brain.claim_task_core('technical_monitor', 300);
insert into fx values ('tm', brain.agent_context_core('technical_monitor', (select task_id from presa_tm), (select lease_token from presa_tm))::text);
select pg_temp.rec(15, 'il Technical Monitor vede la storia dei segnali della sola fonte del task',
  pg_temp.j('tm') ->> 'fonte' = 'technical_heartbeat' and jsonb_array_length(pg_temp.j('tm') -> 'segnali') = 2, pg_temp.f('tm'));
select pg_temp.rec(16, 'segnali in sola aggiunta',
  pg_temp.prova('with u as (update brain.monitor_signals set status = ''ok'' returning 1) select count(*)::text from u') = '55000');

-- ---------------------------------------------------------------------------------------------
-- G: scheduler unico
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(17, 'nessun lavoro nasce acceso e nessuna porta dello scheduler e raggiungibile dai ruoli API o dagli agenti',
  (select not bool_or(enabled) from brain.jobs)
  and (select bool_and(not has_function_privilege(r, 'brain.scheduler_tick(text,integer)', 'EXECUTE'))
         from unnest(array['anon', 'authenticated', 'service_role', 'brain_worker', 'brain_ingest']) r)
  and brain.sentinel_status() ->> 'pianificato' = 'false');
insert into fx values ('t0', brain.scheduler_tick('manuale', 10)::text);
select pg_temp.rec(18, 'giro senza lavori accesi: solo heartbeat, e un giro manuale non conta come pianificato',
  jsonb_array_length(pg_temp.j('t0') -> 'eseguiti') = 0 and (select ticks = 1 from brain.scheduler_state)
  and brain.sentinel_status() ->> 'pianificato' = 'false' and brain.scheduler_status() ->> 'stato' = 'recente');
update brain.jobs set enabled = true where job_key in ('sentinel', 'lavoro_catalogo', 'lease_scaduti', 'attivita_ferme');
insert into fx values ('t1', brain.scheduler_tick('manuale', 10)::text);
insert into fx values ('t2', brain.scheduler_tick('manuale', 10)::text);
select pg_temp.rec(19, 'esegue i lavori scaduti una volta; il giro successivo non li ripete prima dell''intervallo',
  jsonb_array_length(pg_temp.j('t1') -> 'eseguiti') = 4 and jsonb_array_length(pg_temp.j('t2') -> 'eseguiti') = 0
  and (select bool_and(last_status = 'ok' and next_due_at > now()) from brain.jobs where enabled), pg_temp.f('t1'));
update brain.jobs set next_due_at = now() - interval '10 days';
insert into fx values ('t3', brain.scheduler_tick('manuale', 2)::text);
select pg_temp.rec(20, 'dopo un''interruzione non accumula arretrati: al massimo il limite per giro, una volta per lavoro',
  jsonb_array_length(pg_temp.j('t3') -> 'eseguiti') = 2);
-- guasto: il lavoro del catalogo non puo girare
update brain.jobs set enabled = false;
update brain.jobs set enabled = true, next_due_at = now() - interval '1 minute', max_failures = 2 where job_key = 'lavoro_catalogo';
alter table catalog.contributions rename to contributions_wi015b;
select pg_temp.fai((brain.scheduler_tick('manuale', 10))::text);
insert into fx values ('g1', (select jsonb_build_object('f', consecutive_failures, 'e', enabled, 'attesa', extract(epoch from next_due_at - now()) / 60,
  'stato', last_status, 'sqlstate', last_sqlstate)::text from brain.jobs where job_key = 'lavoro_catalogo'));
update brain.jobs set next_due_at = now() - interval '1 minute' where job_key = 'lavoro_catalogo';
select pg_temp.fai((brain.scheduler_tick('manuale', 10))::text);
alter table catalog.contributions_wi015b rename to contributions;
select pg_temp.rec(21, 'guasto: arretramento esponenziale, poi sospensione con anomalia; nessun ritentativo infinito',
  pg_temp.j('g1') ->> 'stato' = 'errore' and (pg_temp.j('g1') ->> 'attesa')::numeric > 90 and pg_temp.j('g1') ->> 'sqlstate' = '42P01'
  and (select not enabled and last_status = 'sospeso' and consecutive_failures = 2 from brain.jobs where job_key = 'lavoro_catalogo')
  and exists (select 1 from brain.anomalies where fingerprint = 'job_sospeso:lavoro_catalogo' and status = 'aperta'), pg_temp.f('g1'));
update brain.scheduler_state set last_tick_at = now() - interval '2 hours';
select pg_temp.rec(22, 'scheduler fermo oltre il doppio dell''intervallo: dichiarato in ritardo',
  brain.scheduler_status() ->> 'stato' = 'in_ritardo');
select pg_temp.rec(23, 'il controllo esterno ha una sola lettura minima con un ruolo dedicato',
  has_function_privilege('brain_monitor_read', 'brain.heartbeat_minimo()', 'EXECUTE')
  and not has_function_privilege('anon', 'brain.heartbeat_minimo()', 'EXECUTE')
  and (select count(*) from pg_proc p where p.pronamespace = 'brain'::regnamespace and has_function_privilege('brain_monitor_read', p.oid, 'EXECUTE')) = 2
  and (select array_agg(k order by k) from jsonb_object_keys(brain.heartbeat_minimo()) k) = array['minuti_dall_ultima_sentinel', 'minuti_dall_ultimo_giro']);

-- Sentinel sorveglia anche le fonti collegate
select pg_temp.fai((brain.sentinel_run('wi015b'))::text);
select pg_temp.rec(24, 'una fonte accesa che non manda segnali diventa anomalia',
  (select (evidence ->> 'conteggio')::int = 1 from brain.anomalies where fingerprint = 'sorgente_monitor_ferma' and status = 'aperta'));

-- ---------------------------------------------------------------------------------------------
-- I: costi AI
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(25, 'chiuso per difetto: senza tetti richieste nessuna prenotazione; nessuna tariffa inventata',
  public.ai_budget_prenota('ai:chat', 'openai', 'modello-prova', 1000, 800) ->> 'esito' = 'non_configurato'
  and (select count(*) from private.ai_tariffe) = 0 and (select count(*) from private.ai_chiamate) = 0
  and (select spesa_giorno_usd is null and spesa_mese_usd is null from private.ai_budget_settings));
update private.ai_budget_settings set richieste_giorno = 100, richieste_mese = 1000, spesa_giorno_usd = 0.01;
select pg_temp.rec(26, 'con un tetto di spesa e senza tariffa non si chiama',
  public.ai_budget_prenota('ai:chat', 'openai', 'modello-prova', 1000, 800) ->> 'esito' = 'tariffa_mancante');
-- tariffa di fantasia, solo per la prova
insert into private.ai_tariffe (provider, modello, versione, input_per_milione, output_per_milione, valida_dal, inserita_da)
values ('openai', 'modello-prova', 'prova-1', 1.0, 4.0, now() - interval '1 day', 'wi015b');
insert into fx values ('p1', public.ai_budget_prenota('ai:chat', 'openai', 'modello-prova', 1000, 1000)::text);
insert into fx values ('p2', public.ai_budget_prenota('ai:pairing', 'openai', 'modello-prova', 1000, 1000)::text);
insert into fx values ('p3', public.ai_budget_prenota('ai:chat', 'openai', 'modello-prova', 1000, 1000)::text);
select pg_temp.rec(27, 'la prenotazione conta il costo massimo: la terza supera il tetto e non consuma richieste',
  pg_temp.j('p1') ->> 'esito' = 'consentito' and pg_temp.j('p2') ->> 'esito' = 'consentito'
  and pg_temp.j('p3') ->> 'esito' = 'spesa_giorno_esaurita'
  and (select sum(consentite) from private.ai_consumo_giornaliero where giorno = (now() at time zone 'utc')::date) = 2,
  pg_temp.f('p1') || pg_temp.f('p3'));
select pg_temp.fai((public.ai_budget_consuntivo((pg_temp.j('p1') ->> 'richiesta_id')::uuid, 'ok', 500, 100))::text);
insert into fx values ('c2', public.ai_budget_consuntivo((pg_temp.j('p1') ->> 'richiesta_id')::uuid, 'ok', 5000000, 5000000)::text);
select pg_temp.rec(28, 'consuntivo una volta sola, con tariffa e versione; il costo stimato non e mai l''effettivo',
  (select costo_stimato = 0.000900 and costo_effettivo is null and token_input = 500 and token_output = 100
          and tariffa_id is not null and conclusa_il is not null
     from private.ai_chiamate where id = (pg_temp.j('p1') ->> 'richiesta_id')::uuid)
  and pg_temp.f('c2') = 'false',
  (select to_jsonb(c)::text from private.ai_chiamate c where id = (pg_temp.j('p1') ->> 'richiesta_id')::uuid));
select pg_temp.rec(29, 'costi senza dati dell''utente e porte solo per il servizio',
  not exists (select 1 from information_schema.columns where table_schema = 'private' and table_name = 'ai_chiamate'
               and column_name ~ 'user|owner|prompt|testo|session')
  and (select bool_and(not has_function_privilege(r, f, 'EXECUTE')) from unnest(array['anon', 'authenticated']) r,
         unnest(array['public.ai_budget_prenota(text,text,text,integer,integer)', 'public.ai_budget_consuntivo(uuid,text,integer,integer)']) f));
insert into fx values ('st', public.ai_budget_stato()::text);
select pg_temp.rec(30, 'lo stato separa richieste, spesa riservata e spesa stimata',
  (pg_temp.j('st') -> 'spesa' ->> 'limite_giorno_usd')::numeric = 0.01
  and (pg_temp.j('st') -> 'spesa' ->> 'stimata_oggi_usd')::numeric = 0.000900
  and (pg_temp.j('st') -> 'spesa' ->> 'riservata_aperta_oggi_usd')::numeric = 0.005000
  and pg_temp.j('st') -> 'spesa' -> 'effettiva_mese_usd' = 'null'::jsonb, pg_temp.f('st'));

-- ---------------------------------------------------------------------------------------------
-- F: aggiornamento LWIN
-- ---------------------------------------------------------------------------------------------
select pg_temp.fai((catalog.assign_official_lwin((select id from catalog.wines where name = 'Collina'), '7151001', 'prova', 'wi015b'))::text);
set local session_replication_role = replica;
update catalog.source_records set status = 'Combined' where external_id = '7151001';
set local session_replication_role = origin;
insert into fx values ('up', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, 'select public.catalogo_admin_aggiornamento()::text'));
select pg_temp.rec(31, 'aggiornamento: il vino il cui record e accorpato e segnalato per il curatore, mai modificato',
  pg_temp.f('up') like 'OK:%' and (substr(pg_temp.f('up'), 4)::jsonb -> 'canonici_non_piu_live' ->> 'conteggio')::int = 1
  and substr(pg_temp.f('up'), 4)::jsonb -> 'canonici_non_piu_live' -> 'esempi' -> 0 ->> 'stato_fonte' = 'Combined'
  and (select status = 'active' and lwin7 = '7151001' from catalog.wines where name = 'Collina'), left(pg_temp.f('up'), 600));

-- ---------------------------------------------------------------------------------------------
-- J: cruscotto e rapporto
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(32, 'porte nuove chiuse a chi non e admin',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('a')::uuid, q) = '42501' and pg_temp.come('anon', null, q) = '42501')
     from unnest(array['select public.azienda_admin_riepilogo()::text', 'select public.azienda_admin_rapporto()::text',
                       'select public.catalogo_admin_aggiornamento()::text']) q));
insert into brain.agents (agent_key, descrizione, task_types) values ('solo_registrato', 'mai acceso', '{catalogo.proposta}');
insert into fx values ('d', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, 'select public.azienda_admin_riepilogo()::text'));
insert into fx values ('dj', substr(pg_temp.f('d'), 4));
select pg_temp.rec(33, 'cruscotto: agenti registrati distinti dagli operativi, scheduler, fonti con stato dichiarato, backup',
  pg_temp.f('d') like 'OK:%'
  and (pg_temp.j('dj') -> 'agenti' ->> 'registrati')::int = 4 and (pg_temp.j('dj') -> 'agenti' ->> 'operativi')::int = 3
  and (select e ->> 'stato' from jsonb_array_elements(pg_temp.j('dj') -> 'agenti' -> 'elenco') e where e ->> 'chiave' = 'solo_registrato') = 'spento'
  and pg_temp.j('dj') -> 'scheduler' ->> 'stato' = 'in_ritardo'
  and (select count(*) from jsonb_array_elements(pg_temp.j('dj') -> 'fonti') f where f ->> 'stato' = 'disattivata') >= 4
  and (select f ->> 'stato' from jsonb_array_elements(pg_temp.j('dj') -> 'fonti') f where f ->> 'chiave' = 'offsite_backup_freshness') = 'non_verificata'
  and (select f ->> 'stato' from jsonb_array_elements(pg_temp.j('dj') -> 'fonti') f where f ->> 'chiave' = 'technical_heartbeat') = 'disponibile'
  and pg_temp.j('dj') -> 'task' ? 'approvati' and pg_temp.j('dj') -> 'evidenze' is not null, left(pg_temp.f('d'), 900));
insert into fx values ('r', substr(pg_temp.come('authenticated', pg_temp.f('admin')::uuid, 'select public.azienda_admin_rapporto(7)::text'), 4));
select pg_temp.rec(34, 'rapporto deterministico: anomalie raggruppate per gravita, decisioni e segnali del periodo',
  pg_temp.j('r') -> 'anomalie_aperte' is not null and pg_temp.j('r') ->> 'giorni' = '7'
  and jsonb_typeof(pg_temp.j('r') -> 'anomalie_aperte') = 'array'
  and (pg_temp.j('r') -> 'segnali' ->> 'totali')::int = 2, left(pg_temp.f('r'), 400));

select pg_temp.rec(35, 'ogni funzione nuova di brain ha search_path vuoto e nessun ruolo API ha privilegi sulle tabelle',
  not exists (select 1 from pg_proc p where p.pronamespace = 'brain'::regnamespace
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c in ('search_path=""', 'search_path=')))
  and not exists (select 1 from information_schema.role_table_grants where table_schema = 'brain'
                   and grantee in ('anon', 'authenticated', 'service_role', 'brain_worker', 'brain_ingest', 'brain_monitor_read', 'PUBLIC')));
select pg_temp.rec(36, 'nulla acceso nei domini: regola in bozza, promozione e proiezione spente',
  (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft'
  and not (select enabled from catalog.promotion_settings) and not (select enabled from catalog.public_projection_settings)
  and catalog.promotion_logic_fingerprint('lwin-conservative-v1') = '64e038526a78f44070a54498fd0ff607');

select id::text, descrizione, passed, detail from esiti order by id;
rollback;
