-- ============================================================================
-- Fase 6d-1 — Regressione della migrazione follow-up.
--
-- Eseguire dopo:
--   20260729230000_security_invariants.sql
--   20260729234500_security_invariants_followup.sql
--   20260729235500_security_helper_invoker.sql
--
-- Crea due utenti, due bottiglie e un ambiente di cantina temporanei. La
-- pulizia usa soltanto gli UUID generati nello script e non tocca dati reali.
-- Atteso: 11 PASSA, 0 FALLISCE, nessuna riga 99.
-- ============================================================================

drop table if exists esiti_6d1_followup;

create temporary table esiti_6d1_followup (
  n         integer primary key,
  caso      text not null,
  atteso    text not null,
  esito     text not null,
  dettaglio text not null default ''
);

create or replace function pg_temp.impersona_6d1f(p_ruolo text, p_uid uuid)
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

create or replace function pg_temp.att_numero_6d1f(
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
  perform pg_temp.impersona_6d1f(p_ruolo, p_uid);
  execute p_sql into v_ottenuto;
  perform set_config('role', 'postgres', true);

  insert into esiti_6d1_followup values (
    p_n,
    p_caso,
    'valore = ' || p_atteso,
    case
      when v_ottenuto is not distinct from p_atteso then 'PASSA'
      else 'FALLISCE'
    end,
    'ottenuto ' || coalesce(v_ottenuto::text, 'NULL')
  );
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1_followup values (
    p_n,
    p_caso,
    'valore = ' || p_atteso,
    'FALLISCE',
    'errore inatteso ' || sqlstate || ': ' || sqlerrm
  );
end;
$$;

create or replace function pg_temp.att_messaggio_6d1f(
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
  v_stato text;
  v_msg   text;
begin
  perform pg_temp.impersona_6d1f(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);

  insert into esiti_6d1_followup values (
    p_n,
    p_caso,
    'messaggio con «' || p_frammento || '»',
    'FALLISCE',
    'nessun errore sollevato'
  );
exception when others then
  v_stato := sqlstate;
  v_msg := sqlerrm;
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1_followup values (
    p_n,
    p_caso,
    'messaggio con «' || p_frammento || '»',
    case
      when position(lower(p_frammento) in lower(v_msg)) > 0 then 'PASSA'
      else 'FALLISCE'
    end,
    v_stato || ': ' || v_msg
  );
end;
$$;

do $test$
declare
  v_venditore  uuid := gen_random_uuid();
  v_altro       uuid := gen_random_uuid();
  v_tag         text := substr(replace(v_venditore::text, '-', ''), 1, 12);
  v_l_bozza     uuid;
  v_b_bozza     uuid;
  v_l_vendita   uuid;
  v_b_vendita   uuid;
  v_ambiente    uuid;
  v_modulo      uuid;
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  )
  values
    (
      '00000000-0000-0000-0000-000000000000',
      v_venditore,
      'authenticated',
      'authenticated',
      'vinea-test-6d1f-seller-' || v_tag || '@example.invalid',
      '',
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      json_build_object(
        'username', 'vinea_6d1f_s_' || v_tag,
        'dob', '1990-01-01'
      )::jsonb
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      v_altro,
      'authenticated',
      'authenticated',
      'vinea-test-6d1f-other-' || v_tag || '@example.invalid',
      '',
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      json_build_object(
        'username', 'vinea_6d1f_o_' || v_tag,
        'dob', '1988-05-12'
      )::jsonb
    );

  insert into public.user_roles (user_id, role)
  values (v_venditore, 'moderator');

  perform pg_temp.impersona_6d1f('authenticated', v_venditore);

  select annuncio_id
  into v_l_bozza
  from public.listing_crea(
    p_produttore := 'Test6D1Followup',
    p_nome := 'Bozza protetta',
    p_annata := 2018,
    p_regione := 'Piemonte',
    p_tipo := 'Rosso',
    p_prezzo_cents := 10000
  );

  select annuncio_id
  into v_l_vendita
  from public.listing_crea(
    p_produttore := 'Test6D1Followup',
    p_nome := 'Vendita protetta',
    p_annata := 2019,
    p_regione := 'Toscana',
    p_tipo := 'Rosso',
    p_prezzo_cents := 12000
  );

  select bottle_unit_id
  into v_b_bozza
  from public.listings
  where id = v_l_bozza;

  select bottle_unit_id
  into v_b_vendita
  from public.listings
  where id = v_l_vendita;

  insert into public.cellar_environments (
    owner_id,
    nome,
    forma,
    tema,
    materiale,
    illuminazione,
    larghezza_cm,
    altezza_cm,
    profondita_cm
  )
  values (
    v_venditore,
    'Cantina test follow-up',
    'parete_lineare',
    'moderna',
    'rovere',
    'calda',
    200,
    220,
    60
  )
  returning id into v_ambiente;

  insert into public.cellar_modules (
    environment_id,
    etichetta,
    righe,
    colonne,
    profondita
  )
  values (v_ambiente, 'Modulo test', 2, 2, 1)
  returning id into v_modulo;

  perform public.cellar_posiziona(v_b_vendita, v_modulo, 0, 0);
  perform set_config('role', 'postgres', true);

  perform pg_temp.att_messaggio_6d1f(
    1,
    'Una bozza impedisce di aprire la bottiglia',
    'authenticated',
    v_venditore,
    format('select public.bottiglia_apri(%L)', v_b_bozza),
    'annuncio in corso'
  );

  perform pg_temp.att_messaggio_6d1f(
    2,
    'Una bozza impedisce di togliere la bottiglia dalla cantina',
    'authenticated',
    v_venditore,
    format('select public.bottiglia_cancella(%L)', v_b_bozza),
    'annuncio in corso'
  );

  perform pg_temp.att_messaggio_6d1f(
    3,
    'Il trigger lato bottiglia impedisce una modifica diretta incoerente',
    'postgres',
    null,
    format(
      'update public.bottle_units set stato = ''aperta'' where id = %L',
      v_b_bozza
    ),
    'annuncio in corso'
  );

  perform pg_temp.att_messaggio_6d1f(
    4,
    'Il trigger lato annuncio impedisce di cambiare il venditore',
    'postgres',
    null,
    format(
      'update public.listings set seller_id = %L where id = %L',
      v_altro,
      v_l_bozza
    ),
    'deve essere il proprietario'
  );

  perform pg_temp.att_numero_6d1f(
    5,
    'has_role non rivela i ruoli di un altro utente',
    'authenticated',
    v_altro,
    format(
      'select count(*) from (select public.has_role(%L, ''moderator'') as ok) q where ok',
      v_venditore
    ),
    0
  );

  -- La vendita è una transizione server-side: deve marcare la bottiglia come
  -- ceduta e liberare nello stesso passaggio la sua posizione fisica.
  perform set_config('role', 'postgres', true);
  update public.listings
  set stato = 'venduto'
  where id = v_l_vendita;

  perform pg_temp.att_numero_6d1f(
    6,
    'La vendita marca la bottiglia ceduta e libera lo slot',
    'postgres',
    null,
    format(
      'select count(*) from public.bottle_units bu
       where bu.id = %L
         and bu.ceduta_at is not null
         and not exists (
           select 1 from public.cellar_slots cs
           where cs.bottle_unit_id = bu.id
         )',
      v_b_vendita
    ),
    1
  );

  perform pg_temp.att_numero_6d1f(
    7,
    'La bottiglia ceduta non compare più nella cantina del venditore',
    'authenticated',
    v_venditore,
    format(
      'select count(*) from public.bottle_units where id = %L',
      v_b_vendita
    ),
    0
  );

  perform pg_temp.att_messaggio_6d1f(
    8,
    'Una bottiglia ceduta non può essere aperta',
    'authenticated',
    v_venditore,
    format('select public.bottiglia_apri(%L)', v_b_vendita),
    'già stata venduta'
  );

  perform pg_temp.att_messaggio_6d1f(
    9,
    'Una bottiglia ceduta non può essere cancellata',
    'authenticated',
    v_venditore,
    format('select public.bottiglia_cancella(%L)', v_b_vendita),
    'già stata venduta'
  );

  perform pg_temp.att_messaggio_6d1f(
    10,
    'Una bottiglia ceduta non può essere riposizionata',
    'authenticated',
    v_venditore,
    format(
      'select public.cellar_posiziona(%L, %L, 0, 0)',
      v_b_vendita,
      v_modulo
    ),
    'non è nella tua cantina'
  );

  perform pg_temp.att_messaggio_6d1f(
    11,
    'Una bottiglia ceduta non può modificare la posizione',
    'authenticated',
    v_venditore,
    format('select public.cellar_togli_posizione(%L)', v_b_vendita),
    'non è nella tua cantina'
  );

  perform set_config('role', 'postgres', true);
  delete from public.listings where id in (v_l_bozza, v_l_vendita);
  delete from public.bottle_units where id in (v_b_bozza, v_b_vendita);
  delete from public.wines where produttore = 'Test6D1Followup';
  delete from public.cellar_modules where id = v_modulo;
  delete from public.cellar_environments where id = v_ambiente;
  delete from auth.users where id in (v_venditore, v_altro);
exception when others then
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1_followup values (
    99,
    'ESECUZIONE DELLO SCRIPT',
    'nessun errore fuori dai casi',
    'FALLISCE',
    sqlstate || ': ' || sqlerrm
  )
  on conflict (n) do update
  set esito = excluded.esito,
      dettaglio = excluded.dettaglio;

  delete from public.listings
  where seller_id in (v_venditore, v_altro);
  delete from public.bottle_units
  where owner_id in (v_venditore, v_altro);
  delete from public.wines
  where produttore = 'Test6D1Followup';
  delete from public.cellar_modules
  where environment_id = v_ambiente;
  delete from public.cellar_environments
  where id = v_ambiente;
  delete from auth.users
  where id in (v_venditore, v_altro);
end;
$test$;

select n, esito, caso, atteso, dettaglio
from esiti_6d1_followup
order by n;

select
  count(*) filter (where esito = 'PASSA') as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*) as totale
from esiti_6d1_followup;
