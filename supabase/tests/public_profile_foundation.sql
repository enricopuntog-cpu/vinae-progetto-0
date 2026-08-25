-- Profilo pubblico utente - griglia comportamentale della fondazione D8.
-- Eseguire esclusivamente su PostgreSQL 17 usa e getta, dopo:
--   1. supabase/tests/9c_bootstrap_postgres_locale.sql;
--   2. tutte le migrazioni del repository, in ordine di filename e ciascuna
--      nella propria transazione.
--
-- La griglia NON e adatta al progetto reale: crea sei utenti e applica tre
-- provvedimenti tramite il motore di moderazione, che scrive nell'audit
-- append-only. Fixture, provvedimenti ed audit vivono percio in una singola
-- transazione e vengono annullati insieme con ROLLBACK. Dopo il rollback la
-- griglia misura esplicitamente i residui.
--
-- SQL diretto prova struttura, privilegi PostgreSQL e comportamento della RPC.
-- Non prova PostgREST, la traduzione HTTP degli errori, il browser o rendering UI.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------

drop table if exists esiti_public_profile;
create temporary table esiti_public_profile (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer,
  p_caso text,
  p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_public_profile (n, caso, esito, dettaglio)
  values (
    p_n,
    p_caso,
    case when p_ok then 'PASSA' else 'FALLISCE' end,
    p_dettaglio
  );
$$;

-- Esegue una lettura impersonando il ruolo e l'identita indicati. Gli errori
-- diventano `SQLSTATE|messaggio`, cosi un diniego atteso e misurabile senza
-- interrompere l'intera griglia.
create or replace function pg_temp.leggi(
  p_sql text,
  p_uid uuid default null,
  p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare
  v_risultato text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v_risultato;
  reset role;
  return v_risultato;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- La transazione racchiude anche le righe append-only prodotte dai tre
-- provvedimenti. Stampiamo gli esiti prima del ROLLBACK, poi verifichiamo fuori
-- dalla transazione che non sia rimasto nulla.
begin;

-- ---------------------------------------------------------------------------
-- Fixture minime: attivo, sospeso, rimosso, chiamante attivo, chiamante rimosso
-- e moderatore. Il trigger reale su auth.users crea i profili.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('d8000000-0000-4000-8000-000000000001', 'active-target@d8-profile.test',
   '{"username":"d8_profile_active","dob":"1990-01-01"}'),
  ('d8000000-0000-4000-8000-000000000002', 'suspended-target@d8-profile.test',
   '{"username":"d8_profile_suspended","dob":"1990-01-01"}'),
  ('d8000000-0000-4000-8000-000000000003', 'removed-target@d8-profile.test',
   '{"username":"d8_profile_removed","dob":"1990-01-01"}'),
  ('d8000000-0000-4000-8000-000000000004', 'active-caller@d8-profile.test',
   '{"username":"d8_profile_caller","dob":"1990-01-01"}'),
  ('d8000000-0000-4000-8000-000000000005', 'removed-caller@d8-profile.test',
   '{"username":"d8_profile_removed_caller","dob":"1990-01-01"}'),
  ('d8000000-0000-4000-8000-000000000006', 'moderator@d8-profile.test',
   '{"username":"d8_profile_moderator","dob":"1990-01-01"}');

update public.profiles
set bio = case id
      when 'd8000000-0000-4000-8000-000000000001' then 'Bio pubblica D8'
      when 'd8000000-0000-4000-8000-000000000002' then 'Bio sospesa D8'
      else bio
    end,
    citta = case id
      when 'd8000000-0000-4000-8000-000000000001' then 'Torino'
      when 'd8000000-0000-4000-8000-000000000002' then 'Asti'
      else citta
    end,
    provincia = case id
      when 'd8000000-0000-4000-8000-000000000001' then 'TO'
      when 'd8000000-0000-4000-8000-000000000002' then 'AT'
      else provincia
    end,
    esperienza = case id
      when 'd8000000-0000-4000-8000-000000000001' then 'appassionato'
      when 'd8000000-0000-4000-8000-000000000002' then 'esperto'
      else esperienza
    end,
    avatar_url = case id
      when 'd8000000-0000-4000-8000-000000000001'
        then 'd8000000-0000-4000-8000-000000000001/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp'
      else avatar_url
    end
where id between
  'd8000000-0000-4000-8000-000000000001'
  and 'd8000000-0000-4000-8000-000000000006';

insert into public.user_roles (user_id, role)
values ('d8000000-0000-4000-8000-000000000006', 'admin');

-- Gli stati non sono scritti direttamente: passano dalla porta reale, quindi
-- restano valide sia la guardia di profiles sia la semantica 7.6b.
select private.moderazione_utente_provvedimento(
  'd8000000-0000-4000-8000-000000000006',
  'd8000000-0000-4000-8000-000000000002',
  'Sospensione fixture D8.'
);

select private.moderazione_utente_provvedimento(
  'd8000000-0000-4000-8000-000000000006',
  'd8000000-0000-4000-8000-000000000003',
  'Rimozione fixture D8.', null, null, true
);

select private.moderazione_utente_provvedimento(
  'd8000000-0000-4000-8000-000000000006',
  'd8000000-0000-4000-8000-000000000005',
  'Rimozione chiamante fixture D8.', null, null, true
);

-- ---------------------------------------------------------------------------
-- [1] Projection chiusa e porte strette
-- ---------------------------------------------------------------------------

select pg_temp.registra(1,
  'La vista privata espone esattamente le sette colonne ammesse',
  pg_temp.leggi($$
    select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
    from information_schema.columns
    where table_schema = 'private' and table_name = 'profili_pubblici'
  $$) = 'user_id,username,bio,citta,provincia,esperienza,avatar_url',
  'id, username, bio, citta, provincia, esperienza e riferimento avatar; nessun *');

select pg_temp.registra(2,
  'La funzione restituisce la stessa allowlist chiusa della vista',
  pg_temp.leggi($$
    select pg_get_function_result('public.profilo_pubblico(uuid)'::regprocedure)
  $$) = 'TABLE(user_id uuid, username text, bio text, citta text, provincia text, esperienza text, avatar_url text)');

select pg_temp.registra(3,
  'La RPC e stable, security definer e con search_path vuoto',
  pg_temp.leggi($$
    select (
      (case when p.provolatile = 's' then 'S' else '-' end) ||
      (case when p.prosecdef then 'D' else '-' end) ||
      (case when array_to_string(p.proconfig, ',') like '%search_path=""%'
        then 'P' else '-' end)
    )
    from pg_proc p
    where p.oid = 'public.profilo_pubblico(uuid)'::regprocedure
  $$) = 'SDP');

select pg_temp.registra(4,
  'La RPC ha un solo ingresso UUID e nessun overload enumerabile',
  pg_temp.leggi($$
    select count(*)::text || '/' || min(oidvectortypes(p.proargtypes))
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'profilo_pubblico'
  $$) = '1/uuid',
  'nessuna ricerca, limite, offset o funzione senza identificativo');

select pg_temp.registra(5,
  'Anon e authenticated eseguono la RPC ma non leggono la vista privata',
  has_function_privilege('anon', 'public.profilo_pubblico(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.profilo_pubblico(uuid)', 'EXECUTE')
  and pg_temp.leggi($$ select count(*)::text from private.profili_pubblici $$,
    null, 'anon') like '42501|%'
  and pg_temp.leggi($$ select count(*)::text from private.profili_pubblici $$,
    'd8000000-0000-4000-8000-000000000004', 'authenticated') like '42501|%',
  'la collezione completa resta irraggiungibile ai ruoli client');

select pg_temp.registra(6,
  'La fondazione non concede SELECT sulle tabelle base o le certificazioni',
  position(
    'grant select on public.profiles'
    in lower(pg_get_functiondef('public.profilo_pubblico(uuid)'::regprocedure))
  ) = 0
  and position(
    'profile_certifications'
    in lower(pg_get_viewdef('private.profili_pubblici'::regclass, true))
  ) = 0
  and not has_table_privilege('anon', 'public.profile_certifications', 'SELECT'),
  'il bootstrap locale amplia profiles per default; D8 non usa quel grant e non tocca certificazioni');

-- ---------------------------------------------------------------------------
-- [2] Comportamento della lettura singola
-- ---------------------------------------------------------------------------

select pg_temp.registra(7,
  'Anon legge tutti e soli i sette valori del profilo attivo richiesto',
  pg_temp.leggi($$
    select concat_ws('|', user_id::text, username, bio, citta, provincia,
      esperienza, avatar_url)
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000001')
  $$, null, 'anon') =
    'd8000000-0000-4000-8000-000000000001|d8_profile_active|Bio pubblica D8|Torino|TO|appassionato|d8000000-0000-4000-8000-000000000001/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp');

select pg_temp.registra(8,
  'Un chiamante authenticated attivo legge il profilo di un altro utente',
  pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000001')
  $$, 'd8000000-0000-4000-8000-000000000004', 'authenticated') = '1');

select pg_temp.registra(9,
  'Il profilo esiste anche senza annunci',
  pg_temp.leggi($$
    select
      (select count(*) from public.profilo_pubblico(
        'd8000000-0000-4000-8000-000000000001'))::text
      || '/' ||
      (select count(*) from public.public_listings
        where seller_id = 'd8000000-0000-4000-8000-000000000001')::text
  $$, null, 'anon') = '1/0',
  'profilo USER-level: zero annunci e una riga profilo');

select pg_temp.registra(10,
  'Un UUID inesistente restituisce zero righe senza rivelare altro',
  pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000099')
  $$, null, 'anon') = '0');

select pg_temp.registra(11,
  'La RPC non puo restituire piu di una riga per identificativo',
  pg_temp.leggi($$
    select max(n)::text from (
      values
        ((select count(*) from public.profilo_pubblico(
          'd8000000-0000-4000-8000-000000000001'))),
        ((select count(*) from public.profilo_pubblico(
          'd8000000-0000-4000-8000-000000000002'))),
        ((select count(*) from public.profilo_pubblico(
          'd8000000-0000-4000-8000-000000000003')))
    ) as conteggi(n)
  $$, null, 'anon') = '1');

-- ---------------------------------------------------------------------------
-- [3] Decisione 7.6b nelle due direzioni
-- ---------------------------------------------------------------------------

select pg_temp.registra(12,
  'Un account sospeso resta pubblicamente visibile',
  pg_temp.leggi($$
    select username
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000002')
  $$, null, 'anon') = 'd8_profile_suspended'
  and pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000002')
  $$, 'd8000000-0000-4000-8000-000000000004', 'authenticated') = '1',
  'primo provvedimento: scrittura sociale bloccata, visibilita invariata');

select pg_temp.registra(13,
  'Un account rimosso non e visibile in uscita',
  pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000003')
  $$, null, 'anon') = '0'
  and pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000003')
  $$, 'd8000000-0000-4000-8000-000000000004', 'authenticated') = '0');

select pg_temp.registra(14,
  'Un chiamante rimosso non legge profili pubblici in entrata',
  pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000001')
  $$, 'd8000000-0000-4000-8000-000000000005', 'authenticated') = '0');

select pg_temp.registra(15,
  'Anon resta una controprova valida del filtro entrante',
  pg_temp.leggi($$
    select count(*)::text
    from public.profilo_pubblico('d8000000-0000-4000-8000-000000000001')
  $$, null, 'anon') = '1',
  'auth.uid() nullo non viene scambiato per un chiamante rimosso');

select pg_temp.registra(16,
  'Profilo nascosto e UUID inesistente hanno lo stesso esito osservabile',
  pg_temp.leggi($$
    select
      (select count(*) from public.profilo_pubblico(
        'd8000000-0000-4000-8000-000000000003'))::text
      || '/' ||
      (select count(*) from public.profilo_pubblico(
        'd8000000-0000-4000-8000-000000000099'))::text
  $$, null, 'anon') = '0/0',
  'nessuno stato o dettaglio di moderazione trapela dalla risposta');

-- ---------------------------------------------------------------------------
-- Esito prima del rollback atomico
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio
from esiti_public_profile
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_public_profile;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_public_profile
\gset d8_

rollback;

-- ---------------------------------------------------------------------------
-- Residui dopo il rollback: utenti, profili, ruoli e audit devono essere zero.
-- ---------------------------------------------------------------------------

select
  (select count(*) from auth.users
    where email like '%@d8-profile.test') as utenti_residui,
  (select count(*) from public.profiles
    where username like 'd8\_profile\_%') as profili_residui,
  (select count(*) from public.user_roles
    where user_id between
      'd8000000-0000-4000-8000-000000000001'
      and 'd8000000-0000-4000-8000-000000000006') as ruoli_residui,
  (select count(*) from public.audit_log
    where target_id between
      'd8000000-0000-4000-8000-000000000001'
      and 'd8000000-0000-4000-8000-000000000006') as audit_residui;

select
  (
    (select count(*) from auth.users
      where email like '%@d8-profile.test') +
    (select count(*) from public.profiles
      where username like 'd8\_profile\_%') +
    (select count(*) from public.user_roles
      where user_id between
        'd8000000-0000-4000-8000-000000000001'
        and 'd8000000-0000-4000-8000-000000000006') +
    (select count(*) from public.audit_log
      where target_id between
        'd8000000-0000-4000-8000-000000000001'
        and 'd8000000-0000-4000-8000-000000000006')
  ) as totale
\gset d8_residui_

select ((:d8_fallisce::integer + :d8_residui_totale::bigint) > 0)::text as fallita
\gset d8_finale_

\if :d8_finale_fallita
  \echo 'D8 PUBLIC PROFILE GRID: FALLISCE'
  -- ON_ERROR_STOP rende questa query sentinella un exit code non-zero di psql.
  select 1 / 0;
\endif

\echo 'D8 PUBLIC PROFILE GRID: PASSA - 16 casi, residui zero'
