-- WI-015 (griglia wi015a): correzione dei finding dell'audit indipendente WI-009→WI-014.
--
-- C-01 identita dell'agente legata alla credenziale; A-01 vini nativi in conflitto con la fonte; B-02 quota consumata
-- dagli invii non validi; B-03 LWIN assegnato nascosto anche alla ricerca per codice; B-04 contatore alla
-- cancellazione dell'account e minimizzazione disattivata; C-02/C-03 approvazione obbligatoria ed evidenze protette;
-- D-01 «ignorata» temporanea e riapribile; D-02 controllo annullato dichiarato; D-03 tetto mensile.
-- La concorrenza e le identita con sessioni reali sono in `wi015_identita_concorrenza.sh`.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi015a: il database contiene utenti reali, griglia rifiutata.';
  end if;
  if (select count(*) from catalog.wines) <> 0 or (select count(*) from catalog.source_records) <> 0 then
    raise exception 'Guard wi015a: il catalogo canonico non e vuoto, griglia rifiutata.';
  end if;
end $$;

create temp table esiti (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create temp table fx (k text primary key, v text) on commit drop;

create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;
create function pg_temp.fai(p anyelement) returns void language sql as $f$ select $f$;
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
values ('15000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@wi015.test'),
       ('15000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@wi015.test'),
       ('15000000-0000-4000-8000-0000000000ad', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@wi015.test');
insert into public.user_roles (user_id, role) values ('15000000-0000-4000-8000-0000000000ad', 'admin') on conflict do nothing;
insert into fx values ('a', '15000000-0000-4000-8000-00000000000a'), ('b', '15000000-0000-4000-8000-00000000000b'),
                      ('admin', '15000000-0000-4000-8000-0000000000ad');

set local session_replication_role = replica;
delete from brain.task_evidence;
delete from brain.tasks;
delete from brain.anomalies;
delete from brain.sentinel_runs;
delete from brain.events;
insert into catalog.source_records (source_id, external_id, status, scope, country, payload, raw, content_hash, first_seen_run, changed_in_run)
select s.id, x.lwin, 'Live', 'wine', 'Italy', jsonb_build_object('producer_name', x.p, 'wine', x.w), '{}'::jsonb, repeat('a', 64), gen_random_uuid(), gen_random_uuid()
  from catalog.sources s,
       (values ('7150001', 'Cantina Wi015 Aurelia', 'Vermentino Scoglio'),
               ('7150002', 'Wi015 Assegnata', 'Nebbia Alta'),
               ('7150003', 'Wi015 Omonima', 'Rosso Gemello')) as x(lwin, p, w)
 where s.code = 'LIVEX-LWIN7';
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------------------------
-- C-01: identita dell'agente
-- ---------------------------------------------------------------------------------------------
create role wi015_agente_ok login inherit;
grant brain_worker to wi015_agente_ok;
create role wi015_estraneo login;
create role wi015_potente login createrole;
grant brain_worker to wi015_potente;
create role wi015_doppio login;
grant brain_worker, catalog_curator to wi015_doppio;

select pg_temp.rec(1, 'claim_task non accetta piu un nome di agente come parametro',
  to_regprocedure('brain.claim_task(text,integer)') is null and to_regprocedure('brain.claim_task(integer)') is not null);
select pg_temp.rec(2, 'un agente non si accende senza credenziale propria',
  pg_temp.prova($q$insert into brain.agents (agent_key, descrizione, enabled, task_types) values ('senza_id', 'x', true, '{catalogo.verifica}') returning agent_key$q$) = '23514');
select pg_temp.rec(3, 'credenziali non ammesse: proprietario, authenticator, service_role, ruolo non membro, con CREATEROLE o con altre membership',
  (select bool_and(pg_temp.prova(format(
      'insert into brain.agents (agent_key, descrizione, db_role, task_types) values (''x_%s'', ''x'', %L, ''{catalogo.verifica}'') returning agent_key',
      md5(r), r)) = '22023')
     from unnest(array['postgres', 'authenticator', 'service_role', 'wi015_estraneo', 'wi015_potente', 'wi015_doppio', 'brain_worker', 'inesistente']) r));
insert into brain.agents (agent_key, descrizione, db_role, enabled, task_types)
values ('agente_ok', 'agente di prova', 'wi015_agente_ok', true, '{catalogo.verifica}');
select pg_temp.rec(4, 'la stessa credenziale non serve due agenti',
  pg_temp.prova($q$insert into brain.agents (agent_key, descrizione, db_role, task_types) values ('secondo', 'x', 'wi015_agente_ok', '{catalogo.verifica}') returning agent_key$q$) = '23505');
select pg_temp.fai((brain.enqueue_task('catalogo.verifica', 'Identita', 1, '{}', 'wi015-1', true))::text);
select pg_temp.rec(5, 'la sessione del proprietario non prende task: l''identita viene da session_user',
  pg_temp.prova('select task_id::text from brain.claim_task(60)') = '42501');
select pg_temp.rec(6, 'SET ROLE sull''agente non basta: session_user resta il proprietario',
  pg_temp.come('wi015_agente_ok', null, 'select task_id::text from brain.claim_task(60)') in ('42501'));
select pg_temp.rec(7, 'ruoli API senza accesso alle porte degli agenti',
  (select bool_and(not has_function_privilege(r, 'brain.claim_task(integer)', 'EXECUTE')) from unnest(array['anon', 'authenticated', 'service_role']) r));
insert into fx values ('rev', pg_temp.prova($q$select brain.disable_agent('agente_ok', 'prova di revoca', 'founder')::text$q$));
select pg_temp.rec(8, 'la disabilitazione e solo del proprietario, libera i lease e resta tracciata',
  not has_function_privilege('brain_worker', 'brain.disable_agent(text,text,text)', 'EXECUTE')
  and pg_temp.f('rev') like 'OK:%'
  and (select not enabled and disabled_reason = 'prova di revoca' from brain.agents where agent_key = 'agente_ok')
  and exists (select 1 from brain.events where event_type = 'agente.disabilitato'));
select pg_temp.rec(9, 'approvazione obbligatoria: nessun task puo chiudersi senza decisione (C-02)',
  pg_temp.prova($q$select brain.enqueue_task('catalogo.verifica', 'Senza approvazione', 1, '{}', 'wi015-2', false)::text$q$) = '23514');
select pg_temp.rec(10, 'le evidenze sono protette anche da TRUNCATE (C-03)',
  pg_temp.prova('truncate brain.task_evidence') = '55000');
select pg_temp.rec(11, 'la decisione approva senza dichiarare eseguito; l''esecuzione si conferma a parte',
  true);
update brain.tasks set status = 'in_approvazione' where dedup_key = 'wi015-1';
insert into fx values ('tk', (select id::text from brain.tasks where dedup_key = 'wi015-1'));
update esiti set passed =
      pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_task_decidi(%L, ''approva'', ''ok'')', pg_temp.f('tk'))) = 'OK:approvato'
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_task_decidi(%L, ''conferma_eseguito'', ''fatto dal pannello'')', pg_temp.f('tk'))) = 'OK:completato'
 where id = 11;

-- ---------------------------------------------------------------------------------------------
-- B-02: gli invii non validi consumano la quota
-- ---------------------------------------------------------------------------------------------
update catalog.intake_settings set user_proposals_enabled = true, user_daily_limit = 3;
insert into fx values ('nv', (select string_agg(pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"P","nome":"N","prezzo":1}'::jsonb, true)$q$), ',') from generate_series(1, 3)));
select pg_temp.rec(12, 'tre invii non validi rispondono «non_valida» senza scrivere proposte',
  pg_temp.f('nv') = 'OK:non_valida,OK:non_valida,OK:non_valida' and (select count(*) from catalog.contributions) = 0, pg_temp.f('nv'));
insert into fx values ('dopo', pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi015","nome":"Valido"}'::jsonb, true)$q$));
select pg_temp.rec(13, 'e il successivo invio valido trova la quota esaurita',
  pg_temp.f('dopo') = 'PGRST' and (select count(*) from catalog.contributions) = 0, pg_temp.f('dopo'));
update catalog.intake_settings set user_daily_limit = 50;

-- ---------------------------------------------------------------------------------------------
-- B-04: cancellazione dell'account e minimizzazione disattivata
-- ---------------------------------------------------------------------------------------------
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi015","nome":"Solo B"}'::jsonb, true)$q$))::text);
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('b')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi015","nome":"Condivisa"}'::jsonb, true)$q$))::text);
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('a')::uuid,
  $q$select public.catalogo_proponi('manuale', '{"produttore":"Cantina Wi015","nome":"Condivisa"}'::jsonb, true)$q$))::text);
delete from auth.users where id = pg_temp.f('b')::uuid;
select pg_temp.rec(14, 'cancellato l''account: la proposta rimasta senza partecipanti e ritirata con contatore corretto, la condivisa resta aperta',
  (select status = 'ritirata' and submissions_count = 0 from catalog.contributions where identity ->> 'nome' = 'Solo B')
  and (select status = 'aperta' and submissions_count = 1 from catalog.contributions where identity ->> 'nome' = 'Condivisa'),
  (select string_agg(identity ->> 'nome' || ':' || status || ':' || submissions_count, ' ') from catalog.contributions));
update catalog.contributions set status = 'rifiutata', reviewed_by = 'admin:x', reviewed_at = now() - interval '400 days'
 where identity ->> 'nome' = 'Condivisa';
select pg_temp.rec(15, 'minimizzazione: senza un periodo scelto non tocca nulla (nessuna conservazione automatica)',
  (select user_link_retention_days is null from catalog.intake_settings)
  and catalog.minimize_decided_submissions('founder') = 0
  and (select count(*) from catalog.contribution_submissions where user_id is not null) = 1);
update catalog.intake_settings set user_link_retention_days = 365;
insert into fx values ('min', catalog.minimize_decided_submissions('founder')::text);
select pg_temp.rec(16, 'con un periodo configurato scollega il solo utente dalle proposte decise e oltre il periodo; il contributo resta',
  pg_temp.f('min') = '1'
  and (select count(*) from catalog.contribution_submissions where user_id is not null) = 0
  and (select submissions_count = 1 from catalog.contributions where identity ->> 'nome' = 'Condivisa')
  and not has_function_privilege('authenticated', 'catalog.minimize_decided_submissions(text)', 'EXECUTE'));
update catalog.intake_settings set user_link_retention_days = null;

-- ---------------------------------------------------------------------------------------------
-- B-03: il LWIN assegnato non si trova per codice se la fonte non lo sostiene piu
-- ---------------------------------------------------------------------------------------------
insert into fx values ('nat', (pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  $q$select public.catalogo_admin_azione('nuovo_vino', '{"produttore":"Wi015 Assegnata","nome":"Nebbia Alta","conferma_non_duplicato":true}'::jsonb, 'curatore')$q$)));
insert into fx values ('natid', substr(pg_temp.f('nat'), 4)::jsonb ->> 'id');
select pg_temp.fai((catalog.assign_official_lwin(pg_temp.f('natid')::uuid, '7150002', 'codice ufficiale', 'founder'))::text);
select pg_temp.fai((catalog.set_native_publication(pg_temp.f('natid')::uuid, true, null, 'founder'))::text);
update catalog.public_projection_settings set enabled = true;
create function pg_temp.per_codice() returns integer language sql as $f$
  select count(*)::integer from public.vini_canonici_cerca('', '', 5, '7150002') $f$;
select pg_temp.rec(17, 'fonte autorizzata e record Live: il codice trova il vino e lo mostra',
  pg_temp.per_codice() = 1
  and (select lwin7 from public.vini_canonici_cerca('', '', 5, '7150002')) = '7150002');
set local session_replication_role = replica;
update catalog.source_records set status = 'Deleted' where external_id = '7150002';
set local session_replication_role = origin;
select pg_temp.rec(18, 'record ritirato dalla fonte: il codice non trova e non si mostra, il nome si',
  pg_temp.per_codice() = 0
  and (select count(*) = 1 and bool_and(lwin7 is null) from public.vini_canonici_cerca('Wi015 Assegnata', 'Nebbia Alta', 5)));
set local session_replication_role = replica;
update catalog.source_records set status = 'Live' where external_id = '7150002';
set local session_replication_role = origin;
create temp table fonte_prec on commit drop as select id, authorization_status from catalog.sources where code = 'LIVEX-LWIN7';
update catalog.sources set authorization_status = 'revoked' where code = 'LIVEX-LWIN7';
select pg_temp.rec(19, 'fonte revocata: nemmeno per codice',
  pg_temp.per_codice() = 0
  and (select count(*) = 1 and bool_and(lwin7 is null) from public.vini_canonici_cerca('Wi015 Assegnata', 'Nebbia Alta', 5)));
update catalog.sources s set authorization_status = p.authorization_status from fonte_prec p where p.id = s.id;
update catalog.public_projection_settings set enabled = false;

-- ---------------------------------------------------------------------------------------------
-- A-01: nativo con la chiave di un candidato
-- ---------------------------------------------------------------------------------------------
insert into fx values ('conf', pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  $q$select public.catalogo_admin_azione('nuovo_vino', '{"produttore":"Wi015 Omonima","nome":"Rosso Gemello","conferma_non_duplicato":true}'::jsonb, 'curatore')$q$));
insert into fx values ('confid', substr(pg_temp.f('conf'), 4)::jsonb ->> 'id');
select pg_temp.rec(20, 'il nativo con la chiave di un record non promosso e un conflitto',
  (select count(*) from catalog.lwin_native_conflicts(10) c where c.wine_id = pg_temp.f('confid')::uuid and c.lwin7 = '7150003') = 1);
select pg_temp.rec(21, 'solo l''admin puo dichiarare la coppia distinta (omonimia), con motivo',
  pg_temp.come('authenticated', pg_temp.f('a')::uuid, format('select public.catalogo_admin_distingui_lwin(%L, ''7150003'', ''x'')', pg_temp.f('confid'))) = '42501'
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.catalogo_admin_distingui_lwin(%L, ''7150003'', null)', pg_temp.f('confid'))) = '22023'
  and pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.catalogo_admin_distingui_lwin(%L, ''7150001'', ''non in conflitto'')', pg_temp.f('confid'))) = 'P0002'
  and not has_table_privilege('authenticated', 'catalog.native_lwin_distinct', 'SELECT'));
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('admin')::uuid,
  format('select public.catalogo_admin_distingui_lwin(%L, ''7150003'', ''produttori omonimi verificati'')', pg_temp.f('confid'))))::text);
select pg_temp.rec(22, 'dichiarata distinta, la coppia non blocca piu, resta tracciata e nulla e stato fuso',
  (select count(*) from catalog.lwin_native_conflicts(10)) = 0
  and exists (select 1 from catalog.canonical_events where action = 'native_lwin_distinct' and entity_ref = pg_temp.f('confid'))
  and (select status = 'active' and lwin7 is null from catalog.wines where id = pg_temp.f('confid')::uuid));
select pg_temp.rec(23, 'la guardia non cambia l''impronta approvabile della promozione',
  catalog.promotion_logic_fingerprint('lwin-conservative-v1') = '64e038526a78f44070a54498fd0ff607',
  catalog.promotion_logic_fingerprint('lwin-conservative-v1'));

-- ---------------------------------------------------------------------------------------------
-- D-01: ignorata e temporanea e riapribile
-- ---------------------------------------------------------------------------------------------
select pg_temp.fai((brain.report_anomaly('wi015_prova', '', 'wi015', 'operativo', 'P2', 'Prova', '{}', 'azione'))::text);
insert into fx values ('an', (select id::text from brain.anomalies where fingerprint = 'wi015_prova'));
insert into fx values ('ig1', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''x'', 2161)', pg_temp.f('an'))));
insert into fx values ('ig2', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''rumore noto'', 48)', pg_temp.f('an'))));
select pg_temp.rec(24, 'ignorare richiede un termine entro il massimo della gravita (P2: 2160 ore)',
  pg_temp.f('ig1') = '22023' and pg_temp.f('ig2') = 'OK:ignorata'
  and (select ignored_until between now() + interval '47 hours' and now() + interval '49 hours' and ignored_severity = 'P2'
         from brain.anomalies where id = pg_temp.f('an')::bigint));
select pg_temp.fai((brain.report_anomaly('wi015_prova', '', 'wi015', 'operativo', 'P2', 'Prova', '{}', 'azione'))::text);
select pg_temp.rec(25, 'entro il termine e con la stessa gravita resta ignorata, senza task',
  (select status = 'ignorata' from brain.anomalies where id = pg_temp.f('an')::bigint)
  and not exists (select 1 from brain.tasks where payload ->> 'anomalia_id' = pg_temp.f('an')));
select pg_temp.fai((brain.report_anomaly('wi015_prova', '', 'wi015', 'operativo', 'P1', 'Prova', '{}', 'azione'))::text);
select pg_temp.rec(26, 'un aggravamento riapre l''ignorata, con evento e un solo task P1',
  (select status = 'aperta' and ignored_until is null and severity = 'P1' from brain.anomalies where id = pg_temp.f('an')::bigint)
  and (select count(*) from brain.tasks where payload ->> 'anomalia_id' = pg_temp.f('an') and priority = 1) = 1
  and exists (select 1 from brain.events where event_type = 'sentinel.anomalia_aperta' and subject_ref = pg_temp.f('an')));
select pg_temp.fai((brain.report_anomaly('wi015_prova', '', 'wi015', 'operativo', 'P0', 'Prova', '{}', 'azione'))::text);
select pg_temp.rec(27, 'un ulteriore aggravamento non duplica il task: ne alza la priorita ed emette l''evento',
  (select count(*) from brain.tasks where payload ->> 'anomalia_id' = pg_temp.f('an')) = 1
  and (select priority from brain.tasks where payload ->> 'anomalia_id' = pg_temp.f('an')) = 0
  and exists (select 1 from brain.events where event_type = 'sentinel.anomalia_aggravata' and subject_ref = pg_temp.f('an')));
insert into fx values ('ig3', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''x'', 25)', pg_temp.f('an'))));
insert into fx values ('ig4', pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''intervento in corso'')', pg_temp.f('an'))));
select pg_temp.rec(28, 'P0 si ignora al massimo 24 ore e senza indicazione prende il massimo',
  pg_temp.f('ig3') = '22023' and pg_temp.f('ig4') = 'OK:ignorata'
  and (select ignored_until <= now() + interval '24 hours' + interval '1 minute' from brain.anomalies where id = pg_temp.f('an')::bigint));
update brain.anomalies set ignored_until = now() - interval '1 minute' where id = pg_temp.f('an')::bigint;
select pg_temp.fai((brain.report_anomaly('wi015_prova', '', 'wi015', 'operativo', 'P0', 'Prova', '{}', 'azione'))::text);
select pg_temp.rec(29, 'scaduto il termine la ricorrenza la riapre; il task ancora aperto non si duplica',
  (select status = 'aperta' and ignored_until is null from brain.anomalies where id = pg_temp.f('an')::bigint)
  and (select count(*) from brain.tasks where payload ->> 'anomalia_id' = pg_temp.f('an')) = 1);

update catalog.promotion_settings set enabled = true;
select pg_temp.fai((brain.sentinel_run('wi015'))::text);
select pg_temp.fai((pg_temp.come('authenticated', pg_temp.f('admin')::uuid, format('select public.azienda_admin_anomalia_aggiorna(%s, ''ignora'', ''finestra'')',
  (select id from brain.anomalies where fingerprint = 'promozione_accesa'))))::text);
update catalog.promotion_settings set enabled = false;
select pg_temp.fai((brain.sentinel_run('wi015'))::text);
select pg_temp.rec(30, 'il problema sparito chiude anche l''ignorata, cosi la ricomparsa e di nuovo visibile',
  (select status = 'risolta' and ignored_until is null from brain.anomalies where fingerprint = 'promozione_accesa'));

-- ---------------------------------------------------------------------------------------------
-- D-02: un controllo annullato (statement_timeout) non fa sparire l'esecuzione
-- ---------------------------------------------------------------------------------------------
alter table catalog.contributions rename to contributions_wi015;
create function public.wi015_annulla() returns setof catalog.contributions_wi015 language plpgsql as $f$
begin raise exception using errcode = '57014', message = 'canceling statement due to statement timeout'; end $f$;
-- la funzione e la sorgente stessa della vista: il planner non puo escluderla
create view catalog.contributions as select * from public.wi015_annulla();
insert into fx values ('s1', pg_temp.prova('select brain.sentinel_run(''wi015'')::text'));
select pg_temp.rec(31, 'l''esecuzione si conclude «parziale», il controllo annullato e quelli successivi sono dichiarati non eseguiti',
  pg_temp.f('s1') like 'OK:%'
  and (substr(pg_temp.f('s1'), 4)::jsonb ->> 'esito') = 'parziale'
  -- non eseguiti = il controllo annullato e TUTTI quelli che lo seguono nell'elenco, qualunque sia la sua lunghezza
  and (substr(pg_temp.f('s1'), 4)::jsonb ->> 'non_eseguiti')::integer =
      (select count(*) from brain.sentinel_checks())
      - (select c.n - 1 from (select code, row_number() over () as n from brain.sentinel_checks()) c
          where c.code = 'proposte_catalogo_vecchie')
  and (select finished_at is not null from brain.sentinel_runs order by id desc limit 1)
  and (select evidence ->> 'sqlstate' = '57014' from brain.anomalies where fingerprint = 'controllo_non_eseguito:proposte_catalogo_vecchie')
  and exists (select 1 from brain.anomalies where fingerprint = 'controllo_non_eseguito:conflitti_lwin_nativi' and status = 'aperta'),
  pg_temp.f('s1'));
drop view catalog.contributions;
drop function public.wi015_annulla();
alter table catalog.contributions_wi015 rename to contributions;

-- ---------------------------------------------------------------------------------------------
-- D-03: tetto mensile del budget AI
-- ---------------------------------------------------------------------------------------------
update private.ai_budget_settings set richieste_giorno = 1000, richieste_mese = 10;
insert into private.ai_consumo_giornaliero (giorno, scope, consentite) values ((now() at time zone 'utc')::date, 'ai:chat', 9)
on conflict (giorno, scope) do update set consentite = 9;
select pg_temp.fai((brain.sentinel_run('wi015'))::text);
select pg_temp.rec(32, 'oltre l''80% del tetto mensile l''anomalia del budget si apre',
  exists (select 1 from brain.anomalies where fingerprint = 'budget_ai_quasi_esaurito' and status = 'aperta'));

select id::text, descrizione, passed, detail from esiti order by id;
rollback;
