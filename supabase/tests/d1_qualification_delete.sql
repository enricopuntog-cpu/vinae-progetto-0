-- D1 - griglia usa e getta per l'eliminazione di una bozza e per la proiezione
-- del titolare senza le pratiche ritirate.
-- Eseguire su PostgreSQL 17 creato dal vuoto, dopo il bootstrap 9c e tutte le
-- migrazioni in ordine, incluse 20260827160000, 20260827160500 e la nuova
-- 20260831130000.
-- Non eseguire sul progetto reale: questa griglia crea e modifica fixture.
--
-- Che cosa prova, e che cosa non prova. Prova il confine della porta:
-- chi puo eliminare, in quale stato, e che cosa resta dopo. NON prova la
-- rimozione degli oggetti da Storage - quella e' del client, e il servizio
-- la esegue PRIMA di chiamare questa RPC: qui non si scrive storage.objects,
-- e la coerenza fra le due meta e' sorvegliata dai test del servizio.
--
-- Le righe si creano con INSERT diretti come `postgres`: il trigger di ciclo
-- di vita e' `before update`, quindi uno stato iniziale arbitrario e' lecito e
-- non aggira nessuna regola di transizione.

\set ON_ERROR_STOP on

create temporary table esiti_qd (
  n integer primary key,
  categoria text not null,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_categoria text, p_caso text, p_ok boolean,
  p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_qd (n, categoria, caso, esito, dettaglio)
  values (p_n, p_categoria, p_caso,
          case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

-- Esegue come un ruolo, con una identita' finta, e restituisce lo SQLSTATE.
create or replace function pg_temp.esegui(
  p_sql text, p_uid uuid default null, p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  return v_esito;
end;
$$;

create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid default null, p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- Tutte le fixture e le mutazioni della prova vivono in una sola transazione.
-- La pulizia esplicita e il controllo residui avvengono prima del commit finale:
-- ogni errore abortisce la transazione e rende non-zero l'exit di psql.
begin;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------

insert into auth.users (id, email)
values
  ('d1de0000-0000-4000-8000-000000000001', 'qd-titolare@example.invalid'),
  ('d1de0000-0000-4000-8000-000000000002', 'qd-estraneo@example.invalid')
on conflict (id) do nothing;

-- Una riga per stato, tutte dello stesso titolare, piu una bozza dell'estraneo.
insert into public.professional_qualifications
  (id, user_id, titolo, ente_emittente, stato, submitted_at, reviewed_at, expires_on)
values
  ('d1de1000-0000-4000-8000-000000000001', 'd1de0000-0000-4000-8000-000000000001',
   'Sommelier', 'AIS', 'bozza', null, null, null),
  ('d1de1000-0000-4000-8000-000000000002', 'd1de0000-0000-4000-8000-000000000001',
   'Enologo', 'Universita', 'inviata', now(), null, null),
  ('d1de1000-0000-4000-8000-000000000003', 'd1de0000-0000-4000-8000-000000000001',
   'Agronomo', 'Ordine', 'approvata', now(), now(), current_date + 365),
  ('d1de1000-0000-4000-8000-000000000004', 'd1de0000-0000-4000-8000-000000000001',
   'Assaggiatore', 'ONAV', 'rifiutata', now(), now(), null),
  ('d1de1000-0000-4000-8000-000000000005', 'd1de0000-0000-4000-8000-000000000001',
   'Wine Educator', 'WSET', 'ritirata', now(), null, null),
  ('d1de1000-0000-4000-8000-000000000006', 'd1de0000-0000-4000-8000-000000000002',
   'Bozza altrui', 'Ente', 'bozza', null, null, null);

-- Due metadati sulla bozza del titolare: devono sparire per cascade, senza che
-- la porta li nomini. Nessun oggetto Storage viene creato: la griglia non
-- scrive storage.objects, e i metadati non lo richiedono.
insert into public.professional_qualification_documents
  (id, qualification_id, owner_id, storage_path, mime_type, size_bytes)
values
  ('d1de2000-0000-4000-8000-000000000001', 'd1de1000-0000-4000-8000-000000000001',
   'd1de0000-0000-4000-8000-000000000001',
   'd1de0000-0000-4000-8000-000000000001/d1de1000-0000-4000-8000-000000000001/d1de3000-0000-4000-8000-000000000001.pdf',
   'application/pdf', 1024),
  ('d1de2000-0000-4000-8000-000000000002', 'd1de1000-0000-4000-8000-000000000001',
   'd1de0000-0000-4000-8000-000000000001',
   'd1de0000-0000-4000-8000-000000000001/d1de1000-0000-4000-8000-000000000001/d1de3000-0000-4000-8000-000000000002.png',
   'image/png', 2048);

-- ---------------------------------------------------------------------------
-- [A] Chi non puo' eliminare
-- ---------------------------------------------------------------------------

select pg_temp.registra(1, 'autorizzazione', 'anon non raggiunge la porta',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    null, 'anon') like '42501|%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    null, 'anon'));

select pg_temp.registra(2, 'autorizzazione', 'senza sessione: serve una sessione',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    null, 'authenticated') like '42501|Serve una sessione.%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    null, 'authenticated'));

-- La bozza altrui e' indistinguibile da una inesistente: stesso messaggio.
select pg_temp.registra(3, 'autorizzazione', 'estraneo: bozza altrui non trovata',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    'd1de0000-0000-4000-8000-000000000002') like 'P0001|Qualifica non trovata.%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    'd1de0000-0000-4000-8000-000000000002'));

select pg_temp.registra(4, 'autorizzazione', 'identificativo inesistente: stesso messaggio',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-0000000000ff'')',
    'd1de0000-0000-4000-8000-000000000001') like 'P0001|Qualifica non trovata.%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-0000000000ff'')',
    'd1de0000-0000-4000-8000-000000000001'));

-- ---------------------------------------------------------------------------
-- [B] Quali stati non si eliminano
-- ---------------------------------------------------------------------------

select pg_temp.registra(5, 'stato', 'inviata non eliminabile',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000002'')',
    'd1de0000-0000-4000-8000-000000000001') like '42501|Si elimina solo una qualifica in bozza%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000002'')',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(6, 'stato', 'approvata non eliminabile',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000003'')',
    'd1de0000-0000-4000-8000-000000000001') like '42501|%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000003'')',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(7, 'stato', 'rifiutata non eliminabile',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000004'')',
    'd1de0000-0000-4000-8000-000000000001') like '42501|%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000004'')',
    'd1de0000-0000-4000-8000-000000000001'));

-- Ritirata e' il record storico prodotto da un ritiro: non si cancella.
select pg_temp.registra(8, 'stato', 'ritirata non eliminabile',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000005'')',
    'd1de0000-0000-4000-8000-000000000001') like '42501|%',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000005'')',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(9, 'stato', 'dopo i rifiuti nessuna riga e sparita',
  (select count(*) from public.professional_qualifications
     where user_id::text like 'd1de0000%') = 6,
  (select count(*)::text from public.professional_qualifications
     where user_id::text like 'd1de0000%'));

-- ---------------------------------------------------------------------------
-- [C] La proiezione del titolare
-- ---------------------------------------------------------------------------

select pg_temp.registra(10, 'proiezione', 'la ritirata non compare nell elenco',
  pg_temp.leggi(
    'select coalesce(string_agg(stato::text, '','' order by stato::text), ''VUOTO'')
       from public.professional_qualifications_me()',
    'd1de0000-0000-4000-8000-000000000001') = 'approvata,bozza,inviata,rifiutata',
  pg_temp.leggi(
    'select coalesce(string_agg(stato::text, '','' order by stato::text), ''VUOTO'')
       from public.professional_qualifications_me()',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(11, 'proiezione', 'la riga ritirata resta nel database',
  (select stato::text from public.professional_qualifications
     where id = 'd1de1000-0000-4000-8000-000000000005') = 'ritirata',
  coalesce((select stato::text from public.professional_qualifications
     where id = 'd1de1000-0000-4000-8000-000000000005'), 'ASSENTE'));

select pg_temp.registra(12, 'proiezione', 'un anonimo non legge nulla',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                null, 'anon') like '42501|%',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                null, 'anon'));

select pg_temp.registra(13, 'proiezione', 'il titolare non vede le righe altrui',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1de0000-0000-4000-8000-000000000002') = '1',
  pg_temp.leggi('select count(*)::text from public.professional_qualifications_me()',
                'd1de0000-0000-4000-8000-000000000002'));

-- ---------------------------------------------------------------------------
-- [D] Il ritiro di una richiesta inviata sparisce dall'elenco ma resta storico
-- ---------------------------------------------------------------------------

select pg_temp.registra(14, 'ritiro', 'ritira la inviata',
  pg_temp.esegui(
    'select public.professional_qualification_withdraw(''d1de1000-0000-4000-8000-000000000002'')',
    'd1de0000-0000-4000-8000-000000000001') = 'NESSUN_ERRORE',
  pg_temp.esegui(
    'select public.professional_qualification_withdraw(''d1de1000-0000-4000-8000-000000000002'')',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(15, 'ritiro', 'sparita dall elenco, presente in tabella',
  pg_temp.leggi(
    'select count(*)::text from public.professional_qualifications_me()
       where id = ''d1de1000-0000-4000-8000-000000000002''',
    'd1de0000-0000-4000-8000-000000000001') = '0'
  and (select stato::text from public.professional_qualifications
        where id = 'd1de1000-0000-4000-8000-000000000002') = 'ritirata',
  pg_temp.leggi(
    'select count(*)::text from public.professional_qualifications_me()
       where id = ''d1de1000-0000-4000-8000-000000000002''',
    'd1de0000-0000-4000-8000-000000000001'));

-- ---------------------------------------------------------------------------
-- [E] L'eliminazione che riesce
-- ---------------------------------------------------------------------------

select pg_temp.registra(16, 'eliminazione', 'la bozza propria si elimina',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    'd1de0000-0000-4000-8000-000000000001') = 'NESSUN_ERRORE',
  pg_temp.esegui(
    'select public.professional_qualification_delete(''d1de1000-0000-4000-8000-000000000001'')',
    'd1de0000-0000-4000-8000-000000000001'));

select pg_temp.registra(17, 'eliminazione', 'la riga e sparita',
  (select count(*) from public.professional_qualifications
     where id = 'd1de1000-0000-4000-8000-000000000001') = 0,
  (select count(*)::text from public.professional_qualifications
     where id = 'd1de1000-0000-4000-8000-000000000001'));

-- I metadati seguono per cascade: la porta non li nomina.
select pg_temp.registra(18, 'eliminazione', 'i metadati dei documenti seguono per cascade',
  (select count(*) from public.professional_qualification_documents
     where qualification_id = 'd1de1000-0000-4000-8000-000000000001') = 0,
  (select count(*)::text from public.professional_qualification_documents
     where qualification_id = 'd1de1000-0000-4000-8000-000000000001'));

select pg_temp.registra(19, 'eliminazione', 'le altre righe del titolare restano',
  (select count(*) from public.professional_qualifications
     where user_id = 'd1de0000-0000-4000-8000-000000000001') = 4,
  (select count(*)::text from public.professional_qualifications
     where user_id = 'd1de0000-0000-4000-8000-000000000001'));

-- ---------------------------------------------------------------------------
-- [F] La spunta pubblica non cambia semantica
-- ---------------------------------------------------------------------------

select pg_temp.registra(20, 'badge', 'approvata e non scaduta: spunta ancora accesa',
  pg_temp.leggi(
    'select professionista_verificato::text
       from public.profilo_pubblico(''d1de0000-0000-4000-8000-000000000001'')',
    null, 'anon') in ('true', ''),
  coalesce(pg_temp.leggi(
    'select professionista_verificato::text
       from public.profilo_pubblico(''d1de0000-0000-4000-8000-000000000001'')',
    null, 'anon'), 'NULL'));

-- Nessuna qualifica approvata per l'estraneo: nessuna spunta.
select pg_temp.registra(21, 'badge', 'senza approvata: nessuna spunta',
  coalesce(pg_temp.leggi(
    'select professionista_verificato::text
       from public.profilo_pubblico(''d1de0000-0000-4000-8000-000000000002'')',
    null, 'anon'), '') in ('false', ''),
  coalesce(pg_temp.leggi(
    'select professionista_verificato::text
       from public.profilo_pubblico(''d1de0000-0000-4000-8000-000000000002'')',
    null, 'anon'), 'NULL'));

-- Nessun percorso Storage nella proiezione pubblica: la colonna non esiste.
select pg_temp.registra(22, 'badge', 'il profilo pubblico non ha una colonna per i documenti',
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and column_name in ('storage_path', 'credential_reference')
      and table_name = 'profilo_pubblico'
  ),
  'colonne pubbliche verificate');

-- ---------------------------------------------------------------------------
-- [G] I privilegi della nuova porta
-- ---------------------------------------------------------------------------

select pg_temp.registra(23, 'privilegi', 'execute solo ad authenticated',
  has_function_privilege('authenticated', 'public.professional_qualification_delete(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.professional_qualification_delete(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.professional_qualification_delete(uuid)', 'EXECUTE')
  and not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'professional_qualification_delete'
      and grantee = 'PUBLIC'
      and privilege_type = 'EXECUTE'
  ),
  format('authenticated=%s anon=%s service_role=%s PUBLIC=%s',
    has_function_privilege('authenticated', 'public.professional_qualification_delete(uuid)', 'EXECUTE'),
    has_function_privilege('anon', 'public.professional_qualification_delete(uuid)', 'EXECUTE'),
    has_function_privilege('service_role', 'public.professional_qualification_delete(uuid)', 'EXECUTE'),
    exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'public'
        and routine_name = 'professional_qualification_delete'
        and grantee = 'PUBLIC'
        and privilege_type = 'EXECUTE'
    )));

-- Il `set search_path = ''` della porta e' registrato in `pg_proc.proconfig`, ma
-- la sua FORMA dipende dalla versione: PostgreSQL puo' scriverlo `search_path=`
-- oppure `search_path=""`. Qui conta il valore — vuoto — non la sua scrittura,
-- quindi l'impostazione viene cercata per nome e il valore letto senza apici.
select pg_temp.registra(24, 'privilegi', 'security definer con search_path chiuso',
  (select p.prosecdef and exists (
            select 1
            from unnest(coalesce(p.proconfig, '{}'::text[])) as impostazione
            where split_part(impostazione, '=', 1) = 'search_path'
              and btrim(split_part(impostazione, '=', 2), '"''') = ''
          )
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'professional_qualification_delete'),
  (select coalesce(array_to_string(p.proconfig, ','), 'NESSUNA')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'professional_qualification_delete'));

select pg_temp.registra(25, 'privilegi', 'volatile: non e una funzione di sola lettura',
  (select p.provolatile = 'v'
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'professional_qualification_delete'),
  (select p.provolatile::text
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'professional_qualification_delete'));

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, categoria, caso, esito, dettaglio from esiti_qd order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  0 as salta,
  count(*) as totale
from esiti_qd;

-- Un caso fallito o mancante rende non-zero l'exit di psql con ON_ERROR_STOP.
do $$
begin
  if (select count(*) from esiti_qd where esito = 'PASSA') <> 25
     or (select count(*) from esiti_qd where esito = 'FALLISCE') <> 0 then
    raise exception 'Griglia qualification delete non verde: % PASS, % FAIL, attesi 25/0',
      (select count(*) from esiti_qd where esito = 'PASSA'),
      (select count(*) from esiti_qd where esito = 'FALLISCE');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pulizia e verifica dei residui
-- ---------------------------------------------------------------------------

delete from public.professional_qualification_documents
where owner_id::text like 'd1de0000%';
delete from public.professional_qualifications where user_id::text like 'd1de0000%';
delete from auth.users where id::text like 'd1de0000%';

select
  (select count(*) from public.professional_qualifications
    where user_id::text like 'd1de0000%') as qualifiche_residue,
  (select count(*) from public.professional_qualification_documents
    where owner_id::text like 'd1de0000%') as documenti_residui,
  (select count(*) from auth.users where id::text like 'd1de0000%') as utenti_residui,
  (select count(*) from storage.objects
    where bucket_id = 'professional-qualifications'
      and name like 'd1de0000%') as oggetti_residui;

do $$
begin
  if exists (select 1 from public.professional_qualifications where user_id::text like 'd1de0000%')
     or exists (select 1 from public.professional_qualification_documents where owner_id::text like 'd1de0000%')
     or exists (select 1 from auth.users where id::text like 'd1de0000%')
     or exists (
       select 1 from storage.objects
       where bucket_id = 'professional-qualifications' and name like 'd1de0000%'
     ) then
    raise exception 'La griglia qualification delete ha lasciato residui';
  end if;
end;
$$;

commit;
