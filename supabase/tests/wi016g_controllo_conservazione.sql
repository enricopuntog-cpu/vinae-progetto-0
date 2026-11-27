-- WI-016 G (griglia wi016g): porte amministrative, kill switch sulle superfici di WI-016, Price Intelligence utente
-- spenta, conservazione configurabile (anteprima e applicazione su fixture) e superficie dell'acquisizione.
-- L'acquisizione con un login vero e il CLI è in `wi016_concorrenza.sh`.
--
-- SOLO stack Supabase locale/effimero. Tutto chiuso da ROLLBACK: nessuna cancellazione sopravvive.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard wi016g: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti (id integer primary key, descrizione text not null, passed boolean not null, detail text not null)
  on commit drop;
create temp table prove (k text primary key, v text) on commit drop;
create function pg_temp.rec(p_id integer, p_desc text, p_ok boolean, p_detail text default '')
returns void language sql as $f$ insert into esiti values (p_id, p_desc, coalesce(p_ok, false), coalesce(p_detail, '')) $f$;
create function pg_temp.salva(p_k text, p_v text) returns void language sql as $f$
  insert into prove values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.v(p_k text) returns text language sql stable as $f$ select v from prove where k = p_k $f$;
create function pg_temp.fai(p anyelement) returns void language sql as $f$ select $f$;

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
    case when p_uid is null then '' else jsonb_build_object('sub', p_uid, 'role', p_ruolo)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    execute format('set local role %I', p_ruolo);
    execute p_sql into v;
    reset role;
    return 'OK:' || coalesce(v, '');
  exception when others then
    reset role;
    return sqlstate;
  end;
end;
$f$;
create function pg_temp.utente(p_sql text) returns text language sql as $f$
  select pg_temp.come('authenticated', '16600000-0000-4000-8000-00000000000a', p_sql) $f$;
create function pg_temp.admin(p_sql text) returns text language sql as $f$
  select pg_temp.come('authenticated', '16600000-0000-4000-8000-0000000000ad', p_sql) $f$;
create function pg_temp.dati(p_k text) returns jsonb language sql stable as $f$ select substr(pg_temp.v(p_k), 4)::jsonb $f$;

insert into auth.users (id, instance_id, aud, role, email, created_at)
select x.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, now() - interval '60 days'
  from (values ('16600000-0000-4000-8000-00000000000a', 'a@wi016g.test'),
               ('16600000-0000-4000-8000-0000000000ad', 'admin@wi016g.test')) x(id, email);
insert into public.profiles (id, username, dob)
select u.id, 'wi016g-' || right(u.id::text, 2), date '1980-01-01' from auth.users u where u.email like '%@wi016g.test'
on conflict (id) do nothing;
insert into public.user_roles (user_id, role) values ('16600000-0000-4000-8000-0000000000ad', 'admin') on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- Superfici amministrative
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(1, 'ogni porta amministrativa di catalogo, azienda e prezzi verifica l''admin nel database e non è eseguibile da anon né da PUBLIC',
  count(*) >= 37
  and bool_and(p.prosrc ~ 'catalog_admin_richiedi' and p.prosecdef
               and not has_function_privilege('anon', p.oid, 'EXECUTE')
               and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)),
  count(*) || ' porte; fuori regola: ' || coalesce(string_agg(p.proname, ',') filter (
    where not (p.prosrc ~ 'catalog_admin_richiedi' and p.prosecdef and not has_function_privilege('anon', p.oid, 'EXECUTE'))), '-'))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(azienda_admin|catalogo_admin|prezzi_admin)';

select pg_temp.rec(2, 'un utente comune non legge le protezioni; l''admin le legge senza identificativi di persone',
  pg_temp.utente('select public.azienda_admin_protezioni()::text') = '42501'
  and pg_temp.admin('select public.azienda_admin_protezioni()::text') like 'OK:%'
  and pg_temp.admin('select public.azienda_admin_protezioni()::text') !~ '16600000');

select pg_temp.rec(3, 'acquisizione: la porta è del solo ruolo dedicato, le tabelle non hanno privilegi, il proprietario non è un adattatore',
  has_function_privilege('research_ingest', 'brain.research_ingest(jsonb)', 'EXECUTE')
  and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role', 'brain_worker', 'brain_ingest', 'brain_monitor_read', 'catalog_loader', 'catalog_curator']) r(ruolo)
       where has_function_privilege(r.ruolo, 'brain.research_ingest(jsonb)', 'EXECUTE'))
  and not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role', 'research_ingest']) r(ruolo),
        unnest(array['catalog.research_adapters', 'catalog.research_ingested', 'brain.retention_settings']) t(tabella)
       where has_table_privilege(r.ruolo, t.tabella, 'SELECT') or has_table_privilege(r.ruolo, t.tabella, 'INSERT'))
  and not exists (select 1 from pg_class c where c.oid in ('catalog.research_adapters'::regclass,
        'catalog.research_ingested'::regclass, 'brain.retention_settings'::regclass) and not c.relrowsecurity)
  and pg_temp.prova($q$select brain.research_ingest('[{}]')::text$q$) = '42501'
  and (select count(*) from catalog.research_adapters) = 0
  and (select count(*) from catalog.surface_audit() where not ok) = 0);

-- ---------------------------------------------------------------------------------------------
-- Kill switch
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(4, 'richieste di verifica: spente alla nascita', public.cellar_verifica_autenticita_disponibile() = false);
update private.autenticita_settings set richieste_enabled = true;
select pg_temp.salva('k1', public.cellar_verifica_autenticita_disponibile()::text);
select pg_temp.fai(brain.suspend('globale', 'tutto', 'prova wi016g', 'wi016g'));
select pg_temp.rec(5, 'la sospensione generale ferma le richieste di verifica NUOVE anche con l''interruttore acceso',
  pg_temp.v('k1') = 'true' and public.cellar_verifica_autenticita_disponibile() = false
  and pg_temp.utente($q$select public.cellar_verifica_autenticita_richiedi(gen_random_uuid(), array['condizioni_da_verificare'], true)$q$) = 'P0001');
select pg_temp.rec(6, 'sospensione generale: anche la registrazione di una ricerca si ferma (acquisizione)',
  pg_temp.admin($q$select public.catalogo_admin_ricerca_registra('{}'::jsonb)::text$q$) = 'P0001'
  and pg_temp.utente($q$select public.catalogo_admin_ricerca_registra('{}'::jsonb)::text$q$) = '42501');
select pg_temp.fai(brain.lift_suspension('globale', 'tutto', 'fine prova', 'wi016g'));
update private.autenticita_settings set richieste_enabled = false;
select pg_temp.rec(7, 'il ripristino non accende nulla: con l''interruttore spento le richieste restano spente',
  public.cellar_verifica_autenticita_disponibile() = false);

-- ---------------------------------------------------------------------------------------------
-- Price Intelligence per scheda e Cantina
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(8, 'valutazione utente SPENTA: solo {abilitata:false}; anon non esegue la porta',
  pg_temp.utente($q$select public.prezzi_vino_osservazioni('qualunque', '0,75 L')::text$q$) = 'OK:{"abilitata": false}'
  and not has_function_privilege('anon', 'public.prezzi_vino_osservazioni(text,text)', 'EXECUTE')
  and (select not valutazione_utenti_enabled and not valutazione_admin_enabled from private.prezzi_settings));
update private.prezzi_settings set valutazione_utenti_enabled = true;
select pg_temp.salva('pz', pg_temp.utente($q$select public.prezzi_vino_osservazioni('inesistente-wi016g', '0,75 L')::text$q$));
select pg_temp.rec(9, 'accesa su un vino senza storico: nessun prezzo inventato',
  pg_temp.dati('pz') ->> 'abilitata' = 'true' and jsonb_array_length(pg_temp.dati('pz') -> 'osservazioni') = 0
  and pg_temp.dati('pz') -> 'soggetto' = 'null'::jsonb, pg_temp.v('pz'));
select pg_temp.rec(10, 'la porta legge solo la vista pubblica dei prezzi: mai la tabella base né il riferimento di origine',
  (select prosrc ~ 'public\.wine_price_history' and prosrc !~ 'wine_price_observations' and prosrc !~ 'o\.origine_ref'
     from pg_proc where oid = 'public.prezzi_vino_osservazioni(text,text)'::regprocedure));
select pg_temp.fai(brain.suspend('globale', 'tutto', 'prova wi016g', 'wi016g'));
select pg_temp.rec(11, 'la sospensione generale spegne anche la valutazione utente',
  pg_temp.utente($q$select public.prezzi_vino_osservazioni('inesistente-wi016g', '0,75 L')::text$q$) = 'OK:{"abilitata": false}');
select pg_temp.fai(brain.lift_suspension('globale', 'tutto', 'fine prova', 'wi016g'));
update private.prezzi_settings set valutazione_utenti_enabled = false;

-- ---------------------------------------------------------------------------------------------
-- Conservazione
-- ---------------------------------------------------------------------------------------------
select pg_temp.rec(12, 'alla nascita: cinque aree, nessun periodo, nulla abilitato; senza configurazione non si cancella nulla',
  (select count(*) = 5 and bool_and(giorni is null and not abilitata) from brain.retention_settings)
  and (select bool_and(e ->> 'oltre_la_soglia' is null) from jsonb_array_elements(brain.retention_anteprima()) e)
  and (select bool_and(brain.retention_applica(area, 'wi016g') = '{"esito": "non_configurata", "cancellate": 0}'::jsonb)
         from brain.retention_settings)
  and not exists (select 1 from brain.jobs where job_key ~ 'conserv|retention'));
select pg_temp.rec(13, 'vincoli: consumi AI sotto 62 giorni rifiutati (azzererebbero il budget); il registro eventi non si abilita; senza periodo non si abilita',
  pg_temp.prova($q$update brain.retention_settings set giorni = 30 where area = 'consumi_ai' returning area$q$) = '23514'
  and pg_temp.prova($q$update brain.retention_settings set giorni = 400, abilitata = true where area = 'eventi' returning area$q$) = '23514'
  and pg_temp.prova($q$update brain.retention_settings set abilitata = true where area = 'task' returning area$q$) = '23514');

-- Fixture: un'operazione vecchia e chiusa (con evidenza), una vecchia ancora aperta con un task chiuso al suo interno,
-- una chiusa recente, e una chiusa vecchia da cui dipende un task aperto.
set local session_replication_role = replica;
delete from brain.task_dependencies;
delete from brain.task_evidence;
delete from brain.tasks;
set local session_replication_role = origin;
insert into brain.tasks (id, task_type, titolo, status, created_at, updated_at) values
  ('16600000-0000-4000-8000-000000000001', 'qualita.scansione', 'vecchia chiusa', 'completato', now() - interval '500 days', now() - interval '500 days'),
  ('16600000-0000-4000-8000-000000000002', 'qualita.scansione', 'vecchia con figlio aperto', 'completato', now() - interval '500 days', now() - interval '500 days'),
  ('16600000-0000-4000-8000-000000000004', 'qualita.scansione', 'chiusa recente', 'completato', now(), now()),
  ('16600000-0000-4000-8000-000000000005', 'qualita.scansione', 'chiusa da cui dipende un aperto', 'completato', now() - interval '500 days', now() - interval '500 days'),
  ('16600000-0000-4000-8000-000000000006', 'qualita.scansione', 'aperto dipendente', 'in_attesa', now() - interval '500 days', now() - interval '500 days');
insert into brain.tasks (id, task_type, titolo, status, created_at, updated_at, parent_task_id, root_task_id, depth) values
  ('16600000-0000-4000-8000-000000000003', 'ricerca.verifica', 'figlio aperto', 'in_attesa', now() - interval '500 days', now() - interval '500 days',
   '16600000-0000-4000-8000-000000000002', '16600000-0000-4000-8000-000000000002', 1);
insert into brain.task_dependencies (task_id, depends_on) values
  ('16600000-0000-4000-8000-000000000006', '16600000-0000-4000-8000-000000000005');
insert into brain.task_evidence (task_id, kind, detail, recorded_by)
values ('16600000-0000-4000-8000-000000000001', 'prova', '{"n":1}', 'wi016g');

update brain.retention_settings set giorni = 365 where area = 'task';
select pg_temp.salva('ant', brain.retention_anteprima()::text);
select pg_temp.rec(14, 'anteprima: conta la sola operazione vecchia, intera, conclusa e senza dipendenti aperti; non cancella',
  (select e ->> 'oltre_la_soglia' = '1' from jsonb_array_elements(pg_temp.v('ant')::jsonb) e where e ->> 'area' = 'task')
  and (select count(*) = 6 from brain.tasks), pg_temp.v('ant'));
update brain.retention_settings set abilitata = true where area = 'task';
select pg_temp.salva('app', brain.retention_applica('task', 'wi016g')::text);
select pg_temp.rec(15, 'applicazione (solo su fixture): cade solo quell''operazione, con le sue evidenze, e resta traccia',
  pg_temp.v('app')::jsonb = '{"esito": "applicata", "cancellate": 1}'::jsonb
  and not exists (select 1 from brain.tasks where id = '16600000-0000-4000-8000-000000000001')
  and (select count(*) = 5 from brain.tasks) and (select count(*) = 0 from brain.task_evidence)
  and exists (select 1 from brain.events where event_type = 'conservazione.applicata'), pg_temp.v('app'));

select pg_temp.rec(16, 'la sola aggiunta resta: senza conservazione nessuna cancellazione; il registro eventi non ha eccezioni nemmeno con il contrassegno',
  pg_temp.prova($q$delete from brain.events returning id$q$) = '55000'
  and pg_temp.prova($q$select set_config('brain.retention_delete', 'events', true)$q$) like 'OK:%'
  and pg_temp.prova($q$delete from brain.events returning id$q$) = '55000'
  and pg_temp.prova($q$update brain.events set source = 'x' returning id$q$) = '55000');
select pg_temp.fai(set_config('brain.retention_delete', '', true));
insert into brain.monitor_signals (source_key, event_id, status, observed_at, received_from, received_at)
values ('ci_main', 'wi016g-1', 'ok', now() - interval '500 days', 'wi016g', now() - interval '500 days');
select pg_temp.rec(17, 'segnali: cancellazione diretta rifiutata; solo la conservazione configurata li toglie',
  pg_temp.prova($q$delete from brain.monitor_signals returning id$q$) = '55000');
update brain.retention_settings set giorni = 365, abilitata = true where area = 'segnali';
select pg_temp.salva('sg', brain.retention_applica('segnali', 'wi016g')::text);
select pg_temp.rec(18, 'segnali oltre la soglia tolti dalla conservazione, e subito dopo la sola aggiunta è di nuovo chiusa',
  (pg_temp.v('sg')::jsonb ->> 'cancellate')::int >= 1
  and coalesce(current_setting('brain.retention_delete', true), '') = '', pg_temp.v('sg'));

select pg_temp.rec(19, 'osservatore esterno: fonte registrata e spenta; l''impronta della promozione resta calcolabile',
  (select not enabled and severity = 'P1' from brain.monitor_sources where source_key = 'osservatore_esterno')
  and catalog.promotion_logic_fingerprint('lwin-conservative-v1') is not null);

select id::text, descrizione, passed, detail from esiti order by esiti.id;
rollback;
