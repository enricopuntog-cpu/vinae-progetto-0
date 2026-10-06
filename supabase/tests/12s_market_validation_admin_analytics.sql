-- Market Validation / MV3 (griglia 12s).
--
-- SOLO stack Supabase locale/effimero. Le fixture pseudonime e i due utenti
-- Auth vivono nella transazione e spariscono con ROLLBACK. La griglia prova il
-- gate admin reale, aggregazione per codice, tassi zero-safe, privacy, limiti e
-- assenza di mutazioni MV/commerciali.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12s: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12s (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12s (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.chiama(
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated',
  out esito text,
  out dati jsonb
) returns record language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config(
    'request.jwt.claims',
    case
      when p_uid is null then json_build_object('role', p_ruolo)::text
      else json_build_object('sub', p_uid, 'role', p_ruolo)::text
    end,
    true
  );
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql into dati;
    esito := 'NESSUN_ERRORE';
  exception when others then
    esito := sqlstate;
    dati := null;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end;
$f$;


-- UUID riservati alla griglia.
\set admin_id '12aa0000-0000-4000-8000-000000000001'
\set user_id  '12aa0000-0000-4000-8000-000000000002'
\set v017_s1  '12aa0000-0000-4000-8000-000000000101'
\set v017_s2  '12aa0000-0000-4000-8000-000000000102'
\set v018_s1  '12aa0000-0000-4000-8000-000000000103'
\set v019_s1  '12aa0000-0000-4000-8000-000000000104'

set local session_replication_role = replica;

insert into auth.users (id, email, raw_user_meta_data) values
  (:'admin_id', 'admin-12s@market-validation.test', '{}'::jsonb),
  (:'user_id', 'user-12s@market-validation.test', '{}'::jsonb);

insert into public.profiles (id, username, dob) values
  (:'admin_id', 'admin-12s', date '1990-01-01'),
  (:'user_id', 'user-12s', date '1990-01-01');

insert into public.user_roles (user_id, role) values
  (:'admin_id', 'admin'),
  (:'user_id', 'user');

insert into private.beta_validation_sessions (
  id, participant_code, capability_hash, started_at, completed_at
) values
  (:'v017_s1', 'V017', repeat('1', 64), timestamptz '2026-10-01 09:00:00+00', timestamptz '2026-10-01 09:30:00+00'),
  (:'v017_s2', 'V017', repeat('2', 64), timestamptz '2026-10-02 10:00:00+00', null),
  (:'v018_s1', 'V018', repeat('3', 64), timestamptz '2026-10-03 11:00:00+00', null),
  (:'v019_s1', 'V019', repeat('4', 64), timestamptz '2026-10-04 12:00:00+00', timestamptz '2026-10-04 12:20:00+00');

insert into private.beta_validation_events (
  session_id, participant_code, event_name, metadata, created_at
) values
  (:'v017_s1', 'V017', 'beta_started', '{}', timestamptz '2026-10-01 09:00:00+00'),
  (:'v017_s1', 'V017', 'marketplace_viewed', '{}', timestamptz '2026-10-01 09:01:00+00'),
  (:'v017_s1', 'V017', 'demo_listing_viewed', '{}', timestamptz '2026-10-01 09:02:00+00'),
  (:'v017_s1', 'V017', 'favorite_added', '{}', timestamptz '2026-10-01 09:03:00+00'),
  (:'v017_s1', 'V017', 'checkout_started', '{}', timestamptz '2026-10-01 09:04:00+00'),
  (:'v017_s1', 'V017', 'shipping_cost_viewed', '{}', timestamptz '2026-10-01 09:05:00+00'),
  (:'v017_s1', 'V017', 'checkout_beta_completed', '{}', timestamptz '2026-10-01 09:06:00+00'),
  (:'v017_s1', 'V017', 'sell_started', '{}', timestamptz '2026-10-01 09:07:00+00'),
  (:'v017_s1', 'V017', 'sell_completed', '{}', timestamptz '2026-10-01 09:08:00+00'),
  (:'v017_s1', 'V017', 'ai_preview_viewed', '{}', timestamptz '2026-10-01 09:09:00+00'),
  (:'v017_s1', 'V017', 'ai_interest_clicked', '{}', timestamptz '2026-10-01 09:10:00+00'),
  (:'v017_s1', 'V017', 'club_viewed', '{}', timestamptz '2026-10-01 09:11:00+00'),
  (:'v017_s1', 'V017', 'beta_completed', '{}', timestamptz '2026-10-01 09:30:00+00'),
  (:'v017_s2', 'V017', 'beta_started', '{}', timestamptz '2026-10-02 10:00:00+00'),
  (:'v017_s2', 'V017', 'marketplace_viewed', '{}', timestamptz '2026-10-02 10:01:00+00'),
  (:'v017_s2', 'V017', 'favorite_added', '{}', timestamptz '2026-10-02 10:02:00+00'),
  (:'v018_s1', 'V018', 'beta_started', '{}', timestamptz '2026-10-03 11:00:00+00'),
  (:'v018_s1', 'V018', 'marketplace_viewed', '{}', timestamptz '2026-10-03 11:01:00+00'),
  (:'v018_s1', 'V018', 'demo_listing_viewed', '{}', timestamptz '2026-10-03 11:02:00+00'),
  (:'v018_s1', 'V018', 'checkout_started', '{}', timestamptz '2026-10-03 11:03:00+00'),
  (:'v018_s1', 'V018', 'sell_started', '{}', timestamptz '2026-10-03 11:04:00+00'),
  (:'v018_s1', 'V018', 'sell_photo_selected', '{}', timestamptz '2026-10-03 11:05:00+00'),
  (:'v018_s1', 'V018', 'sell_completed', '{}', timestamptz '2026-10-03 11:06:00+00'),
  (:'v018_s1', 'V018', 'ai_preview_viewed', '{}', timestamptz '2026-10-03 11:07:00+00'),
  (:'v019_s1', 'V019', 'beta_started', '{}', timestamptz '2026-10-04 12:00:00+00'),
  (:'v019_s1', 'V019', 'beta_completed', '{}', timestamptz '2026-10-04 12:20:00+00');

set local session_replication_role = origin;

create temp table snapshot_12s on commit drop as
select
  (select count(*) from private.beta_validation_sessions) as mv_sessions,
  (select count(*) from private.beta_validation_events) as mv_events,
  (select count(*) from public.orders) as orders_count,
  (select count(*) from public.listings) as listings_count,
  (select count(*) from public.bottle_units) as inventory_count,
  (select count(*) from public.payments) as payments_count;

do $$
declare
  c_admin constant uuid := '12aa0000-0000-4000-8000-000000000001';
  c_user constant uuid := '12aa0000-0000-4000-8000-000000000002';
  v_esito text;
  v_dati jsonb;
  v_row jsonb;
  v_n bigint;
  v_empty_ok boolean := false;
  v_empty_detail text := '';
  b snapshot_12s%rowtype;
begin
  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_admin_summary()', null, 'anon') c;
  perform pg_temp.registra(1, 'anon summary negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_admin_summary()', c_user) c;
  perform pg_temp.registra(2, 'authenticated non-admin summary negato', v_esito = '42501', v_esito);

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama('select public.beta_validation_admin_summary()', c_admin) c;
  perform pg_temp.registra(3, 'admin summary ammesso',
    v_esito = 'NESSUN_ERRORE' and jsonb_typeof(v_dati) = 'object', coalesce(v_dati::text, v_esito));

  perform pg_temp.registra(4, 'KPI distinct code e sessioni multiple',
    (v_dati->>'testersStarted')::int = 3
      and (v_dati->>'uniqueCodes')::int = 3
      and (v_dati->>'totalSessions')::int = 4,
    coalesce(v_dati::text, 'null'));

  perform pg_temp.registra(5, 'completion almeno una sessione per codice',
    (v_dati->>'testersCompleted')::int = 2
      and (v_dati->>'completionRate')::numeric = 66.67,
    coalesce(v_dati::text, 'null'));

  perform pg_temp.registra(6, 'buyer funnel usa distinct participant_code',
    (v_dati#>>'{buyer,started}')::int = 3
      and (v_dati#>>'{buyer,marketplaceViewed}')::int = 2
      and (v_dati#>>'{buyer,demoListingViewed}')::int = 2
      and (v_dati#>>'{buyer,checkoutStarted}')::int = 2
      and (v_dati#>>'{buyer,shippingCostViewed}')::int = 1
      and (v_dati#>>'{buyer,checkoutBetaCompleted}')::int = 1,
    coalesce((v_dati->'buyer')::text, 'null'));

  perform pg_temp.registra(7, 'seller foto non obbligatoria per completion',
    (v_dati#>>'{seller,sellStarted}')::int = 2
      and (v_dati#>>'{seller,sellPhotoSelected}')::int = 1
      and (v_dati#>>'{seller,sellCompleted}')::int = 2,
    coalesce((v_dati->'seller')::text, 'null'));

  perform pg_temp.registra(8, 'AI rate usa preview come denominatore',
    (v_dati#>>'{ai,previewViewed}')::int = 2
      and (v_dati#>>'{ai,interestClicked}')::int = 1
      and (v_dati#>>'{ai,interestRate}')::numeric = 50,
    coalesce((v_dati->'ai')::text, 'null'));

  perform pg_temp.registra(9, 'Club conta codici e percentuale sugli iniziati',
    (v_dati#>>'{club,viewed}')::int = 1
      and (v_dati#>>'{club,viewedRate}')::numeric = 33.33,
    coalesce((v_dati->'club')::text, 'null'));

  select c.esito into v_esito
  from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), ''[]''::jsonb) from public.beta_validation_admin_participants(null, 100, 0) p', null, 'anon') c;
  perform pg_temp.registra(10, 'anon participants negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), ''[]''::jsonb) from public.beta_validation_admin_participants(null, 100, 0) p', c_user) c;
  perform pg_temp.registra(11, 'authenticated non-admin participants negato', v_esito = '42501', v_esito);

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), ''[]''::jsonb) from public.beta_validation_admin_participants(null, 100, 0) p', c_admin) c;
  perform pg_temp.registra(12, 'admin participants ammesso con una riga per codice',
    v_esito = 'NESSUN_ERRORE' and jsonb_array_length(v_dati) = 3,
    coalesce(v_dati::text, v_esito));

  select x into v_row
  from jsonb_array_elements(v_dati) x
  where x->>'participant_code' = 'V017';
  perform pg_temp.registra(13, 'sessioni stesso codice aggregate in una riga',
    (v_row->>'sessions_count')::int = 2
      and v_row->>'first_started_at' like '2026-10-01%'
      and v_row->>'last_started_at' like '2026-10-02%'
      and (v_row->>'completed')::boolean
      and (v_row->>'marketplace_viewed')::int = 2
      and (v_row->>'favorite_added')::int = 2,
    coalesce(v_row::text, 'null'));

  perform pg_temp.registra(14, 'proiezione non espone segreti o identificatori di sessione',
    lower(v_dati::text) !~ '(capability|session_id|metadata|email|user_id|ip_address|user_agent|fingerprint|gps)',
    left(v_dati::text, 300));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), '[]'::jsonb) from public.beta_validation_admin_participants(' v017 ', 100, 0) p$q$, c_admin) c;
  perform pg_temp.registra(15, 'filtro V017 canonicalizzato e server-side',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 1
      and v_dati->0->>'participant_code' = 'V017',
    coalesce(v_dati::text, v_esito));

  select c.esito into v_esito from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.beta_validation_admin_participants('V000', 100, 0) p$q$, c_admin) c;
  perform pg_temp.registra(16, 'V000 negato', v_esito = '22023', v_esito);

  select c.esito into v_esito from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.beta_validation_admin_participants('V1000', 100, 0) p$q$, c_admin) c;
  perform pg_temp.registra(17, 'V1000 negato', v_esito = '22023', v_esito);

  select c.esito into v_esito from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.beta_validation_admin_participants(null, 201, 0) p$q$, c_admin) c;
  perform pg_temp.registra(18, 'limit oltre 200 negato', v_esito = '22023', v_esito);

  select c.esito into v_esito from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from public.beta_validation_admin_participants(null, 100, -1) p$q$, c_admin) c;
  perform pg_temp.registra(19, 'offset negativo negato', v_esito = '22023', v_esito);

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(
    $q$select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), '[]'::jsonb) from public.beta_validation_admin_participants(null, 1, 1) p$q$, c_admin) c;
  perform pg_temp.registra(20, 'pagination limit e offset effettivi',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 1
      and v_dati->0->>'participant_code' = 'V018',
    coalesce(v_dati::text, v_esito));

  -- Dentro il blocco, una subtransazione rende temporaneamente vuoto il dataset:
  -- il summary deve restare valido e non dividere per zero; il rollback della
  -- subtransazione ripristina le fixture per i controlli successivi.
  begin
    delete from private.beta_validation_events;
    delete from private.beta_validation_sessions;
    select c.dati into v_dati
    from pg_temp.chiama('select public.beta_validation_admin_summary()', c_admin) c;
    v_empty_ok := (v_dati->>'testersStarted')::int = 0
      and (v_dati->>'completionRate')::numeric = 0
      and (v_dati#>>'{ai,interestRate}')::numeric = 0
      and (v_dati#>>'{club,viewedRate}')::numeric = 0;
    v_empty_detail := coalesce(v_dati::text, 'null');
    raise exception '__12s_restore__';
  exception when others then
    if sqlerrm <> '__12s_restore__' then raise; end if;
  end;
  perform pg_temp.registra(21, 'dataset vuoto zero-safe', v_empty_ok, v_empty_detail);

  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'beta_validation_admin_summary',
      'beta_validation_admin_participants'
    )
    and p.provolatile = 's'
    and p.prosecdef
    and p.proconfig @> array['search_path=""']
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
    and not has_function_privilege('service_role', p.oid, 'execute');
  perform pg_temp.registra(22, 'due RPC stable, definer, search_path vuoto e ACL chiuse',
    v_n = 2, 'conformi=' || v_n::text || '/2');

  select * into b from snapshot_12s;
  perform pg_temp.registra(23, 'RPC non mutano tabelle MV',
    (select count(*) from private.beta_validation_sessions) = b.mv_sessions
      and (select count(*) from private.beta_validation_events) = b.mv_events,
    'sessioni/eventi invariati');

  perform pg_temp.registra(24, 'RPC non mutano domini commerciali',
    (select count(*) from public.orders) = b.orders_count
      and (select count(*) from public.listings) = b.listings_count
      and (select count(*) from public.bottle_units) = b.inventory_count
      and (select count(*) from public.payments) = b.payments_count,
    'ordini/annunci/inventario/pagamenti invariati');
end $$;

select id, descrizione, passed, detail
from esiti_12s
order by id;

rollback;
