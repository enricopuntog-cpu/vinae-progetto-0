-- WI-013 (griglia wi013): contratto del Company Brain e registro Sentinel.
--
-- Prova: schema chiuso ai ruoli API; niente segreti o indirizzi nella memoria condivisa; eventi in sola aggiunta e
-- deduplicati; agenti spenti e limitati ai propri tipi; lease, scadenza e tentativi limitati; con approvazione il task
-- non si chiude da sé; Sentinel deduplica, risolve, riapre, rispetta «ignorata», dichiara i controlli non eseguiti e
-- la mancata esecuzione; porte di amministrazione chiuse a chi non è admin.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi013: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_wi013 (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create temp table fx (k text primary key, v text) on commit drop;
create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti_wi013 values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;
create function pg_temp.f(p_k text) returns text language sql as $f$ select v from fx where k = p_k $f$;

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
values ('13000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@wi013.test'),
       ('13000000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi013.test');
insert into public.user_roles (user_id, role) values ('13000000-0000-4000-8000-0000000000ad', 'admin') on conflict do nothing;
insert into fx values ('a', '13000000-0000-4000-8000-00000000000a'), ('admin', '13000000-0000-4000-8000-0000000000ad');

-- Stato di partenza della sola transazione.
set local session_replication_role = replica;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.sentinel_runs;
delete from brain.events;
set local session_replication_role = origin;

-- 1. Superficie
select pg_temp.rec(1, 'schema brain senza privilegi per anon, authenticated e service_role',
  (select bool_and(not has_schema_privilege(r, 'brain', 'USAGE,CREATE')) from unnest(array['anon', 'authenticated', 'service_role']) r)
  and not exists (select 1 from information_schema.role_table_grants where table_schema = 'brain'
                   and grantee in ('anon', 'authenticated', 'service_role', 'brain_worker', 'PUBLIC')));
-- WI-015: postgres (e supabase_admin) hanno la sola membership amministrativa concessa da PostgreSQL 16 a chi crea il
-- ruolo (SET e INHERIT falsi): nessun membro OPERATIVO. Il rinnovo del lease e la quarta porta dell'agente.
select pg_temp.rec(2, 'brain_worker è NOLOGIN, senza membri operativi, ed esegue solo le porte dell''agente (più la rete sul payload)',
  (select not rolcanlogin from pg_roles where rolname = 'brain_worker')
  and not exists (select 1 from pg_auth_members m join pg_roles g on g.oid = m.roleid
                   join pg_roles u on u.oid = m.member where g.rolname = 'brain_worker' and u.rolname not in ('postgres', 'supabase_admin'))
  and (select string_agg(p.proname, ',' order by p.proname) from pg_proc p
        where p.pronamespace = 'brain'::regnamespace and has_function_privilege('brain_worker', p.oid, 'EXECUTE'))
      = 'add_evidence,claim_task,finish_task,payload_ammesso,renew_lease');
select pg_temp.rec(3, 'ogni funzione di brain ha search_path vuoto',
  not exists (select 1 from pg_proc p where p.pronamespace = 'brain'::regnamespace
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c in ('search_path=""', 'search_path='))));

-- 2. Memoria condivisa senza segreti né dati personali
select pg_temp.rec(4, 'chiavi sospette, indirizzi di posta e payload enormi sono rifiutati',
  (select bool_and(not brain.payload_ammesso(p::jsonb)) from unnest(array[
     '{"password":"x"}', '{"api_key":"x"}', '{"a":{"access_token":"x"}}', '{"user_email":"x"}', '{"nota":"scrivi a mario@example.test"}', '[]']) p)
  and not brain.payload_ammesso(jsonb_build_object('x', repeat('a', 5000)))
  and brain.payload_ammesso('{"conteggio":3,"code":"x","scartati":1}'));

-- 3. Eventi
insert into fx values ('e1', brain.record_event('catalogo.proposta_ricevuta', 'catalogo', null, 'k-1', 'proposta', '1', '{}')::text);
insert into fx values ('e2', brain.record_event('catalogo.proposta_ricevuta', 'catalogo', null, 'k-1', 'proposta', '1', '{}')::text);
select pg_temp.rec(5, 'evento ripetuto: stessa riga', pg_temp.f('e1') = pg_temp.f('e2') and (select count(*) from brain.events) = 1);
select pg_temp.rec(6, 'eventi in sola aggiunta',
  pg_temp.prova('with u as (update brain.events set source = ''x'' returning 1) select count(*)::text from u') = '55000'
  and pg_temp.prova('with d as (delete from brain.events returning 1) select count(*)::text from d') = '55000');

-- 4. Task e agenti
insert into brain.agents (agent_key, descrizione, enabled, task_types) values
  ('collaudo', 'agente di prova', false, array['catalogo.verifica']);
insert into fx values ('t1', brain.enqueue_task('catalogo.verifica', 'Verifica A', 2, '{"rif":1}', 'd-1', true)::text);
insert into fx values ('t1bis', brain.enqueue_task('catalogo.verifica', 'Verifica A', 2, '{"rif":1}', 'd-1', true)::text);
insert into fx values ('t2', brain.enqueue_task('pagamenti.verifica', 'Altro dominio', 0, '{}', 'd-2', true)::text);
select pg_temp.rec(7, 'task deduplicato', pg_temp.f('t1') = pg_temp.f('t1bis') and (select count(*) from brain.tasks) = 2);
-- WI-015: la coda si prova col nucleo (che nessun ruolo esegue); l'identita reale con login propri e in
-- `wi015_identita_concorrenza.sh`.
select pg_temp.rec(8, 'agente spento o sconosciuto non prende nulla',
  pg_temp.prova('select task_id::text from brain.claim_task_core(''collaudo'', 300)') = '42501'
  and pg_temp.prova('select task_id::text from brain.claim_task_core(''ignoto'', 300)') = '42501');
create role wi013_agente login;
grant brain_worker to wi013_agente;
update brain.agents set db_role = 'wi013_agente', enabled = true where agent_key = 'collaudo';
create temp table presa on commit drop as select * from brain.claim_task_core('collaudo', 60);
select pg_temp.rec(9, 'prende solo i propri tipi, anche se un altro task è più urgente',
  (select count(*) = 1 and bool_and(task_id::text = pg_temp.f('t1') and attempt = 1) from presa)
  and (select status from brain.tasks where id = pg_temp.f('t2')::uuid) = 'in_attesa');
select pg_temp.rec(10, 'lo stesso task non si prende due volte', (select count(*) from brain.claim_task_core('collaudo', 300)) = 0);
select pg_temp.rec(11, 'lease sbagliato: né evidenza né esito',
  pg_temp.prova(format('select brain.add_evidence_core(''collaudo'', %L, %L, ''lettura'', ''{}'')::text', pg_temp.f('t1'), gen_random_uuid())) = '42501'
  and pg_temp.prova(format('select brain.finish_task_core(''collaudo'', %L, %L, true, null)', pg_temp.f('t1'), gen_random_uuid())) = '42501');

-- lease scaduto -> torna in coda; al terzo tentativo scaduto -> fallito
update brain.tasks set lease_expires_at = clock_timestamp() - interval '1 second' where id = pg_temp.f('t1')::uuid;
select pg_temp.rec(12, 'lease scaduto: l''esito tardivo è rifiutato',
  pg_temp.prova(format('select brain.finish_task_core(''collaudo'', %L, %L, true, null)', pg_temp.f('t1'), (select lease_token from presa))) = '42501');
select brain.reap_expired_leases() into temp table r1;
select pg_temp.rec(13, 'e il task torna in coda', (select status from brain.tasks where id = pg_temp.f('t1')::uuid) = 'in_attesa');
create temp table presa2 on commit drop as select * from brain.claim_task_core('collaudo', 60);
update brain.tasks set lease_expires_at = clock_timestamp() - interval '1 second' where id = pg_temp.f('t1')::uuid;
create temp table presa3 on commit drop as select * from brain.claim_task_core('collaudo', 60);
update brain.tasks set lease_expires_at = clock_timestamp() - interval '1 second' where id = pg_temp.f('t1')::uuid;
select brain.reap_expired_leases() into temp table r2;
select pg_temp.rec(14, 'tentativi limitati: dopo il terzo è fallito e non si riprende',
  (select attempt from presa3) = 3 and (select status from brain.tasks where id = pg_temp.f('t1')::uuid) = 'fallito'
  and (select count(*) from brain.claim_task_core('collaudo', 300)) = 0);

insert into fx values ('t3', brain.enqueue_task('catalogo.verifica', 'Con approvazione', 1, '{}', 'd-3', true)::text);
create temp table presa4 on commit drop as select * from brain.claim_task_core('collaudo', 60);
insert into fx values ('ev', pg_temp.prova(format('select brain.add_evidence_core(''collaudo'', %L, %L, ''lettura'', ''{"righe":4}'')::text', pg_temp.f('t3'), (select lease_token from presa4))));
insert into fx values ('fin', pg_temp.prova(format('select brain.finish_task_core(''collaudo'', %L, %L, true, ''{"proposta":"controllare"}'')', pg_temp.f('t3'), (select lease_token from presa4))));
select pg_temp.rec(15, 'con approvazione richiesta il task non si chiude da sé; evidenza ed evento correlati',
  pg_temp.f('fin') = 'OK:in_approvazione' and pg_temp.f('ev') like 'OK:%'
  and (select count(*) from brain.task_evidence where task_id = pg_temp.f('t3')::uuid) = 1
  and exists (select 1 from brain.events e join brain.tasks t on t.correlation_id = e.correlation_id
               where t.id = pg_temp.f('t3')::uuid and e.event_type = 'task.esito'),
  pg_temp.f('fin') || ' ' || pg_temp.f('ev'));

-- 5. Porte di amministrazione
select pg_temp.rec(16, 'chi non è admin non legge e non decide',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('a')::uuid, q) = '42501' and pg_temp.come('anon', null, q) = '42501')
     from unnest(array[
       'select public.azienda_admin_riepilogo()::text', 'select public.azienda_admin_anomalie()::text',
       'select public.azienda_admin_sentinel_esegui()::text', 'select public.azienda_admin_task()::text',
       'select public.azienda_admin_anomalia_aggiorna(1, ''ignora'', ''x'')',
       format('select public.azienda_admin_task_decidi(%L, ''approva'', ''x'')', pg_temp.f('t3'))]) q));
select pg_temp.rec(17, 'decisione: motivo obbligatorio, una volta sola',
  pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_task_decidi(%L, ''approva'', null)', pg_temp.f('t3'))) = '22023');
insert into fx values ('dec', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.azienda_admin_task_decidi(%L, ''approva'', ''verificato'')', pg_temp.f('t3'))));
select pg_temp.rec(18, 'approvato una volta, la seconda decisione è rifiutata',
  pg_temp.f('dec') = 'OK:approvato'
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_task_decidi(%L, ''respingi'', ''no'')', pg_temp.f('t3'))) = 'P0002',
  pg_temp.f('dec'));

-- 6. Sentinel
select pg_temp.rec(19, 'mai eseguito e non pianificato: dichiarato, mai «attivo»',
  brain.sentinel_status() ->> 'stato' = 'mai_eseguito' and (brain.sentinel_status() ->> 'pianificato') = 'false');
update catalog.promotion_settings set enabled = true;
insert into fx values ('s1', brain.sentinel_run('collaudo')::text);
select pg_temp.rec(20, 'rileva l''interruttore acceso come P1 con evidenza di soli conteggi, evento e task da approvare',
  (select severity = 'P1' and status = 'aperta' and evidence = '{"conteggio":1}' and requires_approval
     from brain.anomalies where fingerprint = 'promozione_accesa')
  and (pg_temp.f('s1')::jsonb ->> 'non_eseguiti') = '0'
  and (select count(*) from brain.events where event_type = 'sentinel.anomalia_aperta' and payload ->> 'code' = 'promozione_accesa') = 1
  and (select count(*) from brain.tasks where task_type = 'anomalia.verifica' and payload ->> 'code' = 'promozione_accesa') = 1,
  pg_temp.f('s1'));
select brain.sentinel_run('collaudo') into temp table s2;
select pg_temp.rec(21, 'ripetuta: una sola anomalia, ricorrenze contate, nessun secondo evento o task',
  (select count(*) = 1 and min(occurrences) = 2 from brain.anomalies where code = 'promozione_accesa')
  and (select count(*) from brain.tasks where task_type = 'anomalia.verifica' and payload ->> 'code' = 'promozione_accesa') = 1);
update catalog.promotion_settings set enabled = false;
select brain.sentinel_run('collaudo') into temp table s3;
select pg_temp.rec(22, 'il problema sparito chiude l''anomalia',
  (select status = 'risolta' and resolved_at is not null and responsabile = 'sentinel' from brain.anomalies where fingerprint = 'promozione_accesa'));
update catalog.promotion_settings set enabled = true;
select brain.sentinel_run('collaudo') into temp table s4;
select pg_temp.rec(23, 'e se ricompare si riapre',
  (select status = 'aperta' and resolved_at is null from brain.anomalies where fingerprint = 'promozione_accesa'));
insert into fx values ('ign', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format(
  'select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''finestra di prova'')', (select id from brain.anomalies where fingerprint = 'promozione_accesa'))));
select brain.sentinel_run('collaudo') into temp table s5;
select pg_temp.rec(24, 'una anomalia ignorata resta ignorata entro il termine (WI-015: mai senza scadenza)',
  pg_temp.f('ign') = 'OK:ignorata' and (select status from brain.anomalies where fingerprint = 'promozione_accesa') = 'ignorata', pg_temp.f('ign'));
update catalog.promotion_settings set enabled = false;

-- Un controllo che non si può eseguire diventa un'anomalia di Sentinel e non ferma gli altri.
alter table catalog.contributions rename to contributions_nascoste_wi013;
insert into fx values ('s6', brain.sentinel_run('collaudo')::text);
select pg_temp.rec(25, 'controllo non eseguito: dichiarato (solo SQLSTATE), gli altri continuano',
  (pg_temp.f('s6')::jsonb ->> 'esito') = 'parziale' and (pg_temp.f('s6')::jsonb ->> 'non_eseguiti') = '1'
  and (select category = 'sentinel' and evidence ->> 'sqlstate' = '42P01' from brain.anomalies
        where fingerprint = 'controllo_non_eseguito:proposte_catalogo_vecchie')
  and (select checks_run = 11 from brain.sentinel_runs order by id desc limit 1), pg_temp.f('s6'));
alter table catalog.contributions_nascoste_wi013 rename to contributions;
select brain.sentinel_run('collaudo') into temp table s7;
select pg_temp.rec(26, 'tornato eseguibile, l''anomalia del controllo si chiude',
  (select status from brain.anomalies where fingerprint = 'controllo_non_eseguito:proposte_catalogo_vecchie') = 'risolta');

select pg_temp.rec(27, 'eseguito di recente', brain.sentinel_status() ->> 'stato' = 'recente');
set local session_replication_role = replica;
update brain.sentinel_runs set finished_at = now() - interval '3 hours';
set local session_replication_role = origin;
select pg_temp.rec(28, 'mancata esecuzione rilevata oltre il doppio dell''intervallo', brain.sentinel_status() ->> 'stato' = 'in_ritardo');

-- Sentinel non tocca i domini
select pg_temp.rec(29, 'Sentinel non ha modificato interruttori, regola o proiezione',
  (select status from catalog.promotion_rules where version = 'lwin-conservative-v1') = 'draft'
  and not (select enabled from catalog.promotion_settings) and not (select enabled from catalog.public_projection_settings));

insert into fx values ('dash', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, 'select public.azienda_admin_riepilogo()::text'));
select pg_temp.rec(30, 'cruscotto: dati reali e sorgenti non collegate dichiarate',
  pg_temp.f('dash') like 'OK:%'
  and jsonb_array_length(substr(pg_temp.f('dash'), 4)::jsonb -> 'sorgenti_non_collegate') = 4
  and (substr(pg_temp.f('dash'), 4)::jsonb -> 'ai' ->> 'configurato') = 'false'
  and (substr(pg_temp.f('dash'), 4)::jsonb -> 'agenti' ->> 'accesi') = '1', left(pg_temp.f('dash'), 200));
select pg_temp.rec(31, 'esecuzione manuale dal cruscotto e liste leggibili dall''admin',
  (select bool_and(pg_temp.come('authenticated', pg_temp.f('admin')::uuid, q) like 'OK:%')
     from unnest(array['select public.azienda_admin_sentinel_esegui()::text', 'select public.azienda_admin_anomalie()::text',
                       'select public.azienda_admin_anomalie(false)::text', 'select public.azienda_admin_task()::text']) q));

select id::text, descrizione, passed, detail from esiti_wi013 order by id;
rollback;
