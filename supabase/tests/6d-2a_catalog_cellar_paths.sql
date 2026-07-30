-- ============================================================================
-- Fase 6d-2a — provenienza catalogo e percorsi Cantina.
--
-- Eseguire dopo 20260730184956_catalog_cellar_paths.sql.
-- Crea e cancella due utenti, due vini, due bottiglie, un annuncio e un
-- ambiente temporanei. Richiede autorizzazione fixture separata.
-- Atteso: 18 PASSA, 0 FALLISCE, nessuna riga 99.
-- ============================================================================

drop table if exists esiti_6d2a;

create temporary table esiti_6d2a (
  n integer primary key,
  caso text not null,
  atteso text not null,
  esito text not null,
  dettaglio text not null default ''
);

create or replace function pg_temp.impersona_6d2a(p_ruolo text, p_uid uuid)
returns void
language plpgsql
as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text,
      true
    );
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
  end if;
  perform set_config('role', p_ruolo, true);
end;
$$;

create or replace function pg_temp.att_numero_6d2a(
  p_n integer,
  p_caso text,
  p_ruolo text,
  p_uid uuid,
  p_sql text,
  p_atteso bigint
)
returns void
language plpgsql
as $$
declare
  v_ottenuto bigint;
begin
  perform pg_temp.impersona_6d2a(p_ruolo, p_uid);
  execute p_sql into v_ottenuto;
  perform set_config('role', 'postgres', true);
  insert into esiti_6d2a values (
    p_n, p_caso, 'valore = ' || p_atteso,
    case when v_ottenuto is not distinct from p_atteso then 'PASSA' else 'FALLISCE' end,
    'ottenuto ' || coalesce(v_ottenuto::text, 'NULL')
  );
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_6d2a values (
    p_n, p_caso, 'valore = ' || p_atteso, 'FALLISCE',
    'errore inatteso ' || sqlstate || ': ' || sqlerrm
  );
end;
$$;

create or replace function pg_temp.att_errore_6d2a(
  p_n integer,
  p_caso text,
  p_ruolo text,
  p_uid uuid,
  p_sql text,
  p_frammento text
)
returns void
language plpgsql
as $$
declare
  v_msg text;
begin
  perform pg_temp.impersona_6d2a(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);
  insert into esiti_6d2a values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    'FALLISCE', 'nessun errore sollevato'
  );
exception when others then
  v_msg := sqlerrm;
  perform set_config('role', 'postgres', true);
  insert into esiti_6d2a values (
    p_n, p_caso, 'errore con «' || p_frammento || '»',
    case
      when position(lower(p_frammento) in lower(v_msg)) > 0 then 'PASSA'
      else 'FALLISCE'
    end,
    sqlstate || ': ' || v_msg
  );
end;
$$;

do $test$
declare
  v_owner      uuid := gen_random_uuid();
  v_other      uuid := gen_random_uuid();
  v_private    uuid;
  v_public     uuid;
  v_wine       uuid;
  v_listing    uuid;
  v_environment uuid;
  v_module      uuid;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_owner,
     'authenticated', 'authenticated', 'vinea-test-6d2a-owner@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_6d2a_owner","dob":"1990-01-01"}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_other,
     'authenticated', 'authenticated', 'vinea-test-6d2a-other@example.invalid',
     '', now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb,
     '{"username":"vinea_test_6d2a_other","dob":"1991-02-02"}'::jsonb);

  perform pg_temp.impersona_6d2a('authenticated', v_owner);

  select x.bottle_unit_id, x.wine_id
  into v_private, v_wine
  from public.cellar_bottiglia_aggiungi(
    'Test6D2A', 'Privato', 2020, 'Piemonte', 'Rosso', 'privata', '{}'
  ) x;

  select x.bottle_unit_id
  into v_public
  from public.cellar_bottiglia_aggiungi(
    'Test6D2A', 'Pubblico', 2021, 'Toscana', 'Bianco',
    'cantina_pubblica', '{}'
  ) x;

  select x.annuncio_id
  into v_listing
  from public.listing_crea_da_bottiglia(
    v_private, 12345, 'Ottimo', 'Cantina climatizzata', 'Fixture 6d-2a', '{}'
  ) x;

  select x.environment_id, x.module_id
  into v_environment, v_module
  from public.cellar_ambiente_crea(
    'Ambiente Test 6d-2a', 'parete_lineare', 'moderna', 3, 4
  ) x;

  perform public.listing_pubblica(v_listing);
  perform set_config('role', 'postgres', true);

  perform pg_temp.att_numero_6d2a(
    1, 'Le otto righe seed sono curate dallo staff',
    'anon', null,
    'select count(*) from public.wines where provenienza = ''staff'' and slug in ('
      '''monfortino-2015'',''sassicaia-2018'',''tignanello-2019'','
      '''dom-perignon-2013'',''ornellaia-2017'',''biondi-santi-2016'','
      '''rinaldi-brunate-2018'',''cadelbosco-annamaria-2015'')',
    8
  );

  insert into esiti_6d2a
  select
    2,
    'La scheda utente conserva autore e provenienza',
    'provenienza utente e creato_da owner',
    case when provenienza = 'utente' and creato_da = v_owner then 'PASSA' else 'FALLISCE' end,
    'provenienza=' || provenienza || ', creato_da=' || coalesce(creato_da::text, 'NULL')
  from public.wines
  where id = v_wine;

  perform pg_temp.att_numero_6d2a(
    3, 'Il proprietario legge il proprio vino utente',
    'authenticated', v_owner,
    format('select count(*) from public.wines where id = %L', v_wine), 1
  );

  perform pg_temp.att_numero_6d2a(
    4, 'Un altro utente non legge il vino utente dalla tabella base',
    'authenticated', v_other,
    format('select count(*) from public.wines where id = %L', v_wine), 0
  );

  perform pg_temp.att_numero_6d2a(
    5, 'La vendita non conia una seconda bottle_unit privata',
    'authenticated', v_owner,
    format(
      'select count(*) from public.bottle_units bu where bu.id = %L '
      'and bu.visibilita = ''privata'' and '
      '(select count(*) from public.bottle_units altre where altre.wine_id = bu.wine_id) = 1 and '
      '(select count(*) from public.listings l where l.bottle_unit_id = bu.id) = 1',
      v_private
    ),
    1
  );

  perform pg_temp.att_numero_6d2a(
    6, 'L’aggiunta pubblica non crea annunci',
    'authenticated', v_owner,
    format(
      'select count(*) from public.bottle_units bu where bu.id = %L '
      'and bu.visibilita = ''cantina_pubblica'' and '
      'not exists (select 1 from public.listings l where l.bottle_unit_id = bu.id)',
      v_public
    ),
    1
  );

  perform pg_temp.att_errore_6d2a(
    7, 'La vecchia via listing_crea non è eseguibile dal client',
    'authenticated', v_owner,
    'select * from public.listing_crea('
      'p_produttore := ''Test6D2A'', p_nome := ''Legacy'', p_annata := 2022, '
      'p_regione := ''Veneto'', p_tipo := ''Rosso'', p_prezzo_cents := 1000)',
    'permission denied'
  );

  perform pg_temp.att_numero_6d2a(
    8, 'La vendita riusa la bottle_unit esistente',
    'authenticated', v_owner,
    format(
      'select count(*) from public.listings where id = %L and bottle_unit_id = %L',
      v_listing, v_private
    ),
    1
  );

  perform pg_temp.att_errore_6d2a(
    9, 'Un altro utente non vende la bottiglia del proprietario',
    'authenticated', v_other,
    format(
      'select * from public.listing_crea_da_bottiglia(%L, 1000)',
      v_public
    ),
    'non è nella tua cantina'
  );

  perform pg_temp.att_errore_6d2a(
    10, 'Il client non inserisce bottle_units direttamente',
    'authenticated', v_owner,
    format(
      'insert into public.bottle_units (wine_id, visibilita) values (%L, ''privata'')',
      v_wine
    ),
    'permission denied'
  );

  perform pg_temp.att_numero_6d2a(
    11, 'L’inizializzazione atomica crea ambiente e modulo',
    'authenticated', v_owner,
    format(
      'select count(*) from public.cellar_environments e '
      'join public.cellar_modules m on m.environment_id = e.id '
      'where e.id = %L and m.id = %L',
      v_environment, v_module
    ),
    1
  );

  perform pg_temp.att_errore_6d2a(
    12, 'Il client non inserisce ambienti senza modulo',
    'authenticated', v_owner,
    'insert into public.cellar_environments '
      '(nome, forma, tema, materiale, illuminazione, larghezza_cm, altezza_cm, profondita_cm) '
      'values (''Orfano'', ''parete_lineare'', ''moderna'', ''rovere'', ''neutra'', 100, 100, 40)',
    'permission denied'
  );

  perform pg_temp.att_errore_6d2a(
    13, 'Il client non inserisce moduli fuori dalla RPC atomica',
    'authenticated', v_owner,
    format(
      'insert into public.cellar_modules (environment_id, etichetta, righe, colonne) '
      'values (%L, ''Fuori RPC'', 2, 2)',
      v_environment
    ),
    'permission denied'
  );

  perform pg_temp.att_numero_6d2a(
    14, 'Il bucket Cantina è privato',
    'postgres', null,
    'select count(*) from storage.buckets where id = ''cantina'' and public = false', 1
  );

  perform pg_temp.att_numero_6d2a(
    15, 'La vista pubblica espone la provenienza senza autore',
    'anon', null,
    format(
      'select count(*) from public.public_listings '
      'where id = %L and wine_provenienza = ''utente''',
      v_listing
    ),
    1
  );

  perform pg_temp.att_errore_6d2a(
    16, 'creato_da non è leggibile da un ruolo client',
    'authenticated', v_owner,
    format('select creato_da from public.wines where id = %L', v_wine),
    'permission denied'
  );

  perform pg_temp.att_numero_6d2a(
    17, 'Solo la nuova RPC di vendita è eseguibile da authenticated',
    'postgres', null,
    'select (not has_function_privilege(''authenticated'', '
      '''public.listing_crea(text,text,integer,text,text,integer,text,text,text,text[],uuid)'', '
      '''execute'') and has_function_privilege(''authenticated'', '
      '''public.listing_crea_da_bottiglia(uuid,integer,text,text,text,text[])'', '
      '''execute''))::integer',
    1
  );

  perform set_config('role', 'postgres', true);
  delete from public.listings where seller_id in (v_owner, v_other);
  delete from public.bottle_units where owner_id in (v_owner, v_other);
  delete from public.wines where produttore = 'Test6D2A';
  delete from public.cellar_environments where id = v_environment;
  delete from auth.users where id in (v_owner, v_other);
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_6d2a values (
    99, 'ESECUZIONE DELLO SCRIPT', 'nessun errore fuori dai casi',
    'FALLISCE', sqlstate || ': ' || sqlerrm
  )
  on conflict (n) do update
  set esito = excluded.esito,
      dettaglio = excluded.dettaglio;

  delete from public.listings where seller_id in (v_owner, v_other);
  delete from public.bottle_units where owner_id in (v_owner, v_other);
  delete from public.wines where produttore = 'Test6D2A';
  delete from public.cellar_environments where owner_id in (v_owner, v_other);
  delete from auth.users where id in (v_owner, v_other);
end;
$test$;

with residui as (
  select
    (select count(*)
     from auth.users
     where email like 'vinea-test-6d2a-%@example.invalid')
    + (select count(*)
       from public.profiles
       where username like 'vinea_test_6d2a_owner%'
          or username like 'vinea_test_6d2a_other%')
    + (select count(*)
       from public.wines
       where produttore = 'Test6D2A')
    + (select count(*)
       from public.cellar_environments
       where nome = 'Ambiente Test 6d-2a') as totale
)
insert into esiti_6d2a
select
  18,
  'La pulizia finale non lascia residui fixture 6d-2a',
  'residui = 0',
  case when totale = 0 then 'PASSA' else 'FALLISCE' end,
  'residui trovati ' || totale
from residui;

select n, esito, caso, atteso, dettaglio
from esiti_6d2a
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_6d2a;
