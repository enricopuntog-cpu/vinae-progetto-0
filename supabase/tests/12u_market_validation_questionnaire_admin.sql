-- Market Validation / QV2 admin (griglia 12u).
--
-- SOLO stack Supabase locale/effimero. Fixture pseudonime e due utenti Auth
-- vivono nella transazione e spariscono con ROLLBACK. La griglia prova il gate
-- admin reale delle quattro porte QV2 admin, la coorte QV2 separata dai legacy,
-- KPI PRE/CORE/POST/FULL, distribuzioni (anche multi-select), il collegamento
-- risposte-sessione senza incroci, una riga per codice, paginazione stabile,
-- assenza di capability/UUID/PII e di scritture.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12u: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12u (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12u (id, descrizione, passed, detail)
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

-- Righe della porta participants come array JSON ordinato per codice.
create function pg_temp.partecipanti(p_args text)
returns text language sql as $f$
  select format(
    'select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), ''[]''::jsonb) from public.beta_validation_qv2_admin_participants(%s) p',
    p_args
  );
$f$;

-- UUID riservati alla griglia.
\set admin_id  '12bc0000-0000-4000-8000-000000000001'
\set user_id   '12bc0000-0000-4000-8000-000000000002'
\set v001_s    '12bc0000-0000-4000-8000-000000000101'
\set v002_s    '12bc0000-0000-4000-8000-000000000102'
\set v003_s    '12bc0000-0000-4000-8000-000000000103'
\set v020_qv2  '12bc0000-0000-4000-8000-000000000104'
\set v020_leg  '12bc0000-0000-4000-8000-000000000105'
\set v017_s1   '12bc0000-0000-4000-8000-000000000106'
\set v017_s2   '12bc0000-0000-4000-8000-000000000107'
\set v018_s1   '12bc0000-0000-4000-8000-000000000108'

set local session_replication_role = replica;

insert into auth.users (id, email, raw_user_meta_data) values
  (:'admin_id', 'admin-12u@market-validation.test', '{}'::jsonb),
  (:'user_id', 'user-12u@market-validation.test', '{}'::jsonb);

insert into public.profiles (id, username, dob) values
  (:'admin_id', 'admin-12u', date '1990-01-01'),
  (:'user_id', 'user-12u', date '1990-01-01');

insert into public.user_roles (user_id, role) values
  (:'admin_id', 'admin'),
  (:'user_id', 'user');

-- V001/V002/V003 solo QV2; V020 QV2 piu una sessione legacy successiva con lo
-- stesso codice (non deve contaminare la riga QV2); V017/V018 solo legacy.
insert into private.beta_validation_sessions (
  id, participant_code, capability_hash, started_at, completed_at
) values
  (:'v001_s', 'V001', repeat('a', 64), timestamptz '2026-10-05 09:00:00+00', timestamptz '2026-10-05 09:40:00+00'),
  (:'v002_s', 'V002', repeat('b', 64), timestamptz '2026-10-05 10:00:00+00', null),
  (:'v003_s', 'V003', repeat('c', 64), timestamptz '2026-10-05 11:00:00+00', null),
  (:'v020_qv2', 'V020', repeat('d', 64), timestamptz '2026-10-06 09:00:00+00', null),
  (:'v020_leg', 'V020', repeat('e', 64), timestamptz '2026-10-07 09:00:00+00', timestamptz '2026-10-07 09:30:00+00'),
  (:'v017_s1', 'V017', repeat('1', 64), timestamptz '2026-10-01 09:00:00+00', timestamptz '2026-10-01 09:30:00+00'),
  (:'v017_s2', 'V017', repeat('2', 64), timestamptz '2026-10-02 10:00:00+00', null),
  (:'v018_s1', 'V018', repeat('3', 64), timestamptz '2026-10-03 11:00:00+00', null);

insert into private.beta_validation_qv2 (
  session_id, pre_finished_at, post_finished_at,
  q01, q02, q02_other, q03, q04, q05, q05_other, q06, q06_where, q06_why,
  q07, q08, q09, q10, q10_actions, q10_other, q11, q11_where, q11_main_difficulty,
  q12, q13, q14, q15, q15_why_not, q16, q17, q18, q19, q20, final_feedback
) values
  (:'v001_s', timestamptz '2026-10-05 09:10:00+00', timestamptz '2026-10-05 09:50:00+00',
   '25_34', 'other', 'Sommelier amatoriale', 'one_two_month', '20_40',
   array['wine_shop', 'producer', 'other'], '=Mercatini', 'yes', 'Mercatino', 'Prezzo',
   array['authenticity', 'shipping'], 'Garanzia di autenticità', 'one_five', 'yes',
   array['gifted', 'other'], 'Asta di beneficenza', 'once', 'Forum', 'Fiducia',
   'six_nine', 'ten_twelve', 'buy', 'no', 'Prezzi alti', 'maybe',
   'Spedizione', 'Più foto', array['protected_payment', 'authenticity_guarantee'], 'both', 'Ottimo'),
  (:'v002_s', timestamptz '2026-10-05 10:10:00+00', null,
   '25_34', 'enthusiast', null, 'under_month', '40_80',
   array['wine_shop'], null, 'no', null, null,
   array['authenticity'], 'Recensioni', 'none', 'no',
   null, null, 'never', null, null,
   'five_or_less', 'six_nine', null, null, null, null,
   null, null, null, null, null),
  (:'v003_s', null, null,
   '45_54', null, null, null, null,
   null, null, null, null, null,
   null, null, null, null,
   null, null, null, null, null,
   null, null, null, null, null, null,
   null, null, null, null, null),
  (:'v020_qv2', timestamptz '2026-10-06 09:10:00+00', null,
   '65_plus', 'collector', null, 'multiple_week', 'over_150',
   array['auction', 'producer'], null, 'no', null, null,
   array['storage', 'price', 'claims'], 'Certificati', 'over_fifty', 'no',
   null, null, 'regularly', 'Aste', null,
   'would_not_buy', 'over_twenty', null, null, null, null,
   null, null, null, null, null);

insert into private.beta_validation_events (
  session_id, participant_code, event_name, metadata, created_at
) values
  (:'v001_s', 'V001', 'beta_started', '{}', timestamptz '2026-10-05 09:00:00+00'),
  (:'v001_s', 'V001', 'marketplace_viewed', '{}', timestamptz '2026-10-05 09:11:00+00'),
  (:'v001_s', 'V001', 'marketplace_viewed', '{}', timestamptz '2026-10-05 09:12:00+00'),
  (:'v001_s', 'V001', 'demo_listing_viewed', '{}', timestamptz '2026-10-05 09:13:00+00'),
  (:'v001_s', 'V001', 'favorite_added', '{}', timestamptz '2026-10-05 09:14:00+00'),
  (:'v001_s', 'V001', 'checkout_started', '{}', timestamptz '2026-10-05 09:15:00+00'),
  (:'v001_s', 'V001', 'shipping_cost_viewed', '{}', timestamptz '2026-10-05 09:16:00+00'),
  (:'v001_s', 'V001', 'checkout_beta_completed', '{}', timestamptz '2026-10-05 09:17:00+00'),
  (:'v001_s', 'V001', 'sell_started', '{}', timestamptz '2026-10-05 09:20:00+00'),
  (:'v001_s', 'V001', 'sell_completed', '{}', timestamptz '2026-10-05 09:25:00+00'),
  (:'v001_s', 'V001', 'ai_preview_viewed', '{}', timestamptz '2026-10-05 09:30:00+00'),
  (:'v001_s', 'V001', 'club_viewed', '{}', timestamptz '2026-10-05 09:35:00+00'),
  (:'v001_s', 'V001', 'beta_completed', '{}', timestamptz '2026-10-05 09:40:00+00'),
  (:'v001_s', 'V001', 'validation_completed', '{}', timestamptz '2026-10-05 09:50:00+00'),
  (:'v002_s', 'V002', 'beta_started', '{}', timestamptz '2026-10-05 10:00:00+00'),
  (:'v002_s', 'V002', 'marketplace_viewed', '{}', timestamptz '2026-10-05 10:11:00+00'),
  (:'v002_s', 'V002', 'checkout_started', '{}', timestamptz '2026-10-05 10:12:00+00'),
  (:'v002_s', 'V002', 'checkout_beta_completed', '{}', timestamptz '2026-10-05 10:13:00+00'),
  (:'v003_s', 'V003', 'beta_started', '{}', timestamptz '2026-10-05 11:00:00+00'),
  (:'v020_qv2', 'V020', 'beta_started', '{}', timestamptz '2026-10-06 09:00:00+00'),
  (:'v020_qv2', 'V020', 'sell_started', '{}', timestamptz '2026-10-06 09:20:00+00'),
  (:'v020_qv2', 'V020', 'sell_completed', '{}', timestamptz '2026-10-06 09:25:00+00'),
  (:'v020_leg', 'V020', 'beta_started', '{}', timestamptz '2026-10-07 09:00:00+00'),
  (:'v020_leg', 'V020', 'checkout_beta_completed', '{}', timestamptz '2026-10-07 09:10:00+00'),
  (:'v020_leg', 'V020', 'club_viewed', '{}', timestamptz '2026-10-07 09:20:00+00'),
  (:'v020_leg', 'V020', 'beta_completed', '{}', timestamptz '2026-10-07 09:30:00+00'),
  (:'v017_s1', 'V017', 'beta_started', '{}', timestamptz '2026-10-01 09:00:00+00'),
  (:'v017_s1', 'V017', 'marketplace_viewed', '{}', timestamptz '2026-10-01 09:01:00+00'),
  (:'v017_s1', 'V017', 'checkout_beta_completed', '{}', timestamptz '2026-10-01 09:06:00+00'),
  (:'v017_s1', 'V017', 'sell_completed', '{}', timestamptz '2026-10-01 09:08:00+00'),
  (:'v017_s1', 'V017', 'beta_completed', '{}', timestamptz '2026-10-01 09:30:00+00'),
  (:'v017_s2', 'V017', 'beta_started', '{}', timestamptz '2026-10-02 10:00:00+00'),
  (:'v017_s2', 'V017', 'marketplace_viewed', '{}', timestamptz '2026-10-02 10:01:00+00'),
  (:'v018_s1', 'V018', 'beta_started', '{}', timestamptz '2026-10-03 11:00:00+00'),
  (:'v018_s1', 'V018', 'ai_preview_viewed', '{}', timestamptz '2026-10-03 11:07:00+00');

set local session_replication_role = origin;

create temp table snapshot_12u on commit drop as
select
  (select count(*) from private.beta_validation_sessions) as mv_sessions,
  (select count(*) from private.beta_validation_events) as mv_events,
  (select count(*) from private.beta_validation_qv2) as qv2_rows,
  (select md5(string_agg(to_jsonb(q)::text, ',' order by q.session_id))
     from private.beta_validation_qv2 q) as qv2_hash,
  (select md5(string_agg(s.id::text || ':' || s.capability_hash || ':' || coalesce(s.completed_at::text, ''), ',' order by s.id))
     from private.beta_validation_sessions s) as sessions_hash;

do $$
declare
  c_admin constant uuid := '12bc0000-0000-4000-8000-000000000001';
  c_user constant uuid := '12bc0000-0000-4000-8000-000000000002';
  c_uuid constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  c_leak constant text := '(capability|session_id|metadata|email|user_id|ip_address|user_agent|fingerprint)';
  v_esito text;
  v_dati jsonb;
  v_row jsonb;
  v_pages jsonb;
  v_n bigint;
  v_empty_ok boolean := false;
  v_empty_detail text := '';
  b snapshot_12u%rowtype;
begin
  -- Gate: anon e authenticated non-admin negati su tutte le quattro porte.
  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', null, 'anon') c;
  perform pg_temp.registra(1, 'anon summary QV2 negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', c_user) c;
  perform pg_temp.registra(2, 'authenticated non-admin summary QV2 negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti('null, null, 50, 0'), null, 'anon') c;
  perform pg_temp.registra(3, 'anon participants QV2 negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti('null, null, 50, 0'), c_user) c;
  perform pg_temp.registra(4, 'authenticated non-admin participants QV2 negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('V001')$q$, null, 'anon') c;
  perform pg_temp.registra(5, 'anon dettaglio negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('V001')$q$, c_user) c;
  perform pg_temp.registra(6, 'authenticated non-admin dettaglio negato', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_qv2_admin_distributions()', null, 'anon') c;
  perform pg_temp.registra(7, 'anon distribuzioni negate', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select public.beta_validation_qv2_admin_distributions()', c_user) c;
  perform pg_temp.registra(8, 'authenticated non-admin distribuzioni negate', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select to_jsonb(count(*)) from private.beta_validation_qv2', c_admin) c;
  perform pg_temp.registra(9, 'tabella privata QV2 non leggibile dal client admin', v_esito = '42501', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama('select to_jsonb(count(*)) from private.beta_validation_qv2_admin_rows()', c_admin) c;
  perform pg_temp.registra(10, 'helper privato non eseguibile dal client', v_esito = '42501', v_esito);

  -- KPI: coorte QV2 = V001, V002, V003, V020; legacy = V017, V018.
  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', c_admin) c;
  perform pg_temp.registra(11, 'admin summary QV2 ammesso',
    v_esito = 'NESSUN_ERRORE' and jsonb_typeof(v_dati) = 'object', coalesce(v_dati::text, v_esito));

  perform pg_temp.registra(12, 'KPI QV2 iniziati/PRE/BUY/SELL senza legacy nel denominatore',
    (v_dati#>>'{qv2,started}')::int = 4
      and (v_dati#>>'{qv2,preCompleted}')::int = 3
      and (v_dati#>>'{qv2,buyCompleted}')::int = 2
      and (v_dati#>>'{qv2,sellCompleted}')::int = 2,
    coalesce((v_dati->'qv2')::text, 'null'));

  perform pg_temp.registra(13, 'CORE (beta_completed) distinto da FULL (validation_completed)',
    (v_dati#>>'{qv2,coreCompleted}')::int = 1
      and (v_dati#>>'{qv2,postCompleted}')::int = 1
      and (v_dati#>>'{qv2,validationCompleted}')::int = 1
      and (v_dati#>>'{qv2,completionRate}')::numeric = 25,
    coalesce((v_dati->'qv2')::text, 'null'));

  perform pg_temp.registra(14, 'AI, Club e Preferiti QV2 contano solo la sessione QV2',
    (v_dati#>>'{qv2,aiViewed}')::int = 1
      and (v_dati#>>'{qv2,clubViewed}')::int = 1
      and (v_dati#>>'{qv2,favoriteAdded}')::int = 1
      and (v_dati#>>'{legacy,favoriteAdded}')::int = 0,
    coalesce((v_dati->'qv2')::text, 'null'));

  perform pg_temp.registra(15, 'metriche legacy separate',
    (v_dati#>>'{legacy,codes}')::int = 2
      and (v_dati#>>'{legacy,coreCompleted}')::int = 1
      and (v_dati#>>'{legacy,coreCompletionRate}')::numeric = 50
      and (v_dati->>'allCodes')::int = 6,
    coalesce(v_dati::text, 'null'));

  -- Participants: una riga per codice, risposte collegate alla sessione QV2.
  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(pg_temp.partecipanti('null, null, 50, 0'), c_admin) c;
  perform pg_temp.registra(16, 'admin participants: una riga per codice, ordinata',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 6
      and (select string_agg(x->>'participant_code', ',' order by o) from jsonb_array_elements(v_dati) with ordinality t(x, o))
          = 'V001,V002,V003,V017,V018,V020'
      and (select bool_and((x->>'total_count')::int = 6) from jsonb_array_elements(v_dati) x),
    coalesce(left(v_dati::text, 300), v_esito));

  select x into v_row from jsonb_array_elements(v_dati) x where x->>'participant_code' = 'V001';
  perform pg_temp.registra(17, 'V001 risposte, condizionali e multi-select collegati',
    v_row->>'cohort' = 'qv2'
      and v_row->>'q02' = 'other'
      and v_row->>'q02_other' = 'Sommelier amatoriale'
      and v_row->'q05' = '["wine_shop", "producer", "other"]'::jsonb
      and v_row->>'q05_other' = '=Mercatini'
      and v_row->>'q06_where' = 'Mercatino'
      and v_row->'q10_actions' = '["gifted", "other"]'::jsonb
      and v_row->>'q15_why_not' = 'Prezzi alti'
      and v_row->'q19' = '["protected_payment", "authenticity_guarantee"]'::jsonb
      and v_row->>'final_feedback' = 'Ottimo'
      and (v_row->>'marketplace_viewed')::int = 2
      and v_row->>'pre_completed_at' is not null
      and v_row->>'validation_completed_at' is not null,
    coalesce(v_row::text, 'null'));

  select x into v_row from jsonb_array_elements(v_dati) x where x->>'participant_code' = 'V020';
  perform pg_temp.registra(18, 'V020: nessun incrocio tra sessione QV2 e sessione legacy',
    v_row->>'cohort' = 'qv2'
      and (v_row->>'sessions_count')::int = 2
      and (v_row->>'checkout_beta_completed')::int = 0
      and (v_row->>'beta_completed')::int = 0
      and (v_row->>'club_viewed')::int = 0
      and (v_row->>'sell_completed')::int = 1
      and v_row->>'core_completed_at' is null
      and v_row->>'started_at' like '2026-10-06%'
      and v_row->>'last_activity_at' like '2026-10-06%'
      and v_row->>'q01' = '65_plus',
    coalesce(v_row::text, 'null'));

  select x into v_row from jsonb_array_elements(v_dati) x where x->>'participant_code' = 'V017';
  perform pg_temp.registra(19, 'legacy senza questionario: risposte vuote, aggregazione MV3',
    v_row->>'cohort' = 'legacy'
      and (v_row->>'sessions_count')::int = 2
      and v_row->>'q01' is null
      and v_row->'q05' = 'null'::jsonb
      and v_row->>'pre_completed_at' is null
      and v_row->>'post_completed_at' is null
      and (v_row->>'marketplace_viewed')::int = 2
      and (v_row->>'beta_completed')::int = 1
      and v_row->>'started_at' like '2026-10-01%'
      and v_row->>'last_activity_at' like '2026-10-02%',
    coalesce(v_row::text, 'null'));

  select x into v_row from jsonb_array_elements(v_dati) x where x->>'participant_code' = 'V003';
  perform pg_temp.registra(20, 'QV2 avviato senza PRE: solo risposte registrate',
    v_row->>'cohort' = 'qv2'
      and v_row->>'q01' = '45_54'
      and v_row->>'q02' is null
      and v_row->>'pre_completed_at' is null,
    coalesce(v_row::text, 'null'));

  perform pg_temp.registra(21, 'participants senza capability, UUID o PII',
    lower(v_dati::text) !~ c_leak and v_dati::text !~ c_uuid,
    left(v_dati::text, 300));

  -- Paginazione stabile: tre pagine da due coprono esattamente l'elenco.
  v_pages := '[]'::jsonb;
  for v_n in 0..2 loop
    select c.dati into v_dati
    from pg_temp.chiama(pg_temp.partecipanti(format('null, null, 2, %s', v_n * 2)), c_admin) c;
    v_pages := v_pages || coalesce(v_dati, '[]'::jsonb);
  end loop;
  perform pg_temp.registra(22, 'paginazione stabile senza duplicati ne buchi',
    (select string_agg(x->>'participant_code', ',' order by o) from jsonb_array_elements(v_pages) with ordinality t(x, o))
      = 'V001,V002,V003,V017,V018,V020'
      and (select bool_and((x->>'total_count')::int = 6) from jsonb_array_elements(v_pages) x),
    left(v_pages::text, 200));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(pg_temp.partecipanti($a$' v020 ', null, 50, 0$a$), c_admin) c;
  perform pg_temp.registra(23, 'filtro codice canonicalizzato server-side',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 1
      and v_dati->0->>'participant_code' = 'V020'
      and (v_dati->0->>'total_count')::int = 1,
    coalesce(v_dati::text, v_esito));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama(pg_temp.partecipanti($a$null, 'legacy', 50, 0$a$), c_admin) c;
  perform pg_temp.registra(24, 'filtro coorte legacy',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 2
      and (select bool_and(x->>'cohort' = 'legacy') from jsonb_array_elements(v_dati) x),
    coalesce(v_dati::text, v_esito));

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti($a$'V000', null, 50, 0$a$), c_admin) c;
  perform pg_temp.registra(25, 'codice V000 negato', v_esito = '22023', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti($a$null, 'tutti', 50, 0$a$), c_admin) c;
  perform pg_temp.registra(26, 'coorte non ammessa negata', v_esito = '22023', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti('null, null, 201, 0'), c_admin) c;
  perform pg_temp.registra(27, 'limit oltre 200 negato', v_esito = '22023', v_esito);

  select c.esito into v_esito
  from pg_temp.chiama(pg_temp.partecipanti('null, null, 50, -1'), c_admin) c;
  perform pg_temp.registra(28, 'offset negativo negato', v_esito = '22023', v_esito);

  -- Dettaglio per participant_code.
  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail(' v001 ')$q$, c_admin) c;
  perform pg_temp.registra(29, 'dettaglio V001: questionario, eventi e completion',
    v_esito = 'NESSUN_ERRORE'
      and v_dati->>'participantCode' = 'V001'
      and v_dati->>'cohort' = 'qv2'
      and v_dati#>>'{questionnaire,q02_other}' = 'Sommelier amatoriale'
      and v_dati#>'{questionnaire,q07}' = '["authenticity", "shipping"]'::jsonb
      and v_dati#>>'{questionnaire,q17}' = 'Spedizione'
      -- 14 eventi dalla 20261008230000 (cellar_viewed).
      and jsonb_array_length(v_dati->'events') = 14
      and (select (x->>'count')::int from jsonb_array_elements(v_dati->'events') x where x->>'event' = 'marketplace_viewed') = 2
      and v_dati#>>'{completion,preCompletedAt}' is not null
      and v_dati#>>'{completion,coreCompletedAt}' is not null
      and v_dati#>>'{completion,postCompletedAt}' is not null
      and v_dati#>>'{completion,validationCompletedAt}' is not null,
    coalesce(left(v_dati::text, 300), v_esito));

  perform pg_temp.registra(30, 'dettaglio senza capability, UUID o PII',
    lower(v_dati::text) !~ c_leak and v_dati::text !~ c_uuid,
    left(coalesce(v_dati::text, 'null'), 300));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('V020')$q$, c_admin) c;
  perform pg_temp.registra(31, 'dettaglio V020 isolato dalla sessione legacy',
    v_esito = 'NESSUN_ERRORE'
      and (select (x->>'count')::int from jsonb_array_elements(v_dati->'events') x where x->>'event' = 'checkout_beta_completed') = 0
      and (select (x->>'count')::int from jsonb_array_elements(v_dati->'events') x where x->>'event' = 'club_viewed') = 0
      and (select (x->>'count')::int from jsonb_array_elements(v_dati->'events') x where x->>'event' = 'sell_completed') = 1
      and v_dati#>>'{completion,coreCompletedAt}' is null
      and v_dati#>>'{questionnaire,q11}' = 'regularly',
    coalesce(left(v_dati::text, 300), v_esito));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('V017')$q$, c_admin) c;
  perform pg_temp.registra(32, 'dettaglio legacy: questionario non disponibile, eventi aggregati',
    v_esito = 'NESSUN_ERRORE'
      and v_dati->>'cohort' = 'legacy'
      and v_dati->'questionnaire' = 'null'::jsonb
      and (v_dati->>'sessionsCount')::int = 2
      and (select (x->>'count')::int from jsonb_array_elements(v_dati->'events') x where x->>'event' = 'marketplace_viewed') = 2
      and v_dati#>>'{completion,coreCompletedAt}' is not null
      and v_dati#>>'{completion,preCompletedAt}' is null,
    coalesce(left(v_dati::text, 300), v_esito));

  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('V999')$q$, c_admin) c;
  perform pg_temp.registra(33, 'dettaglio codice inesistente: null',
    v_esito = 'NESSUN_ERRORE' and v_dati is null, coalesce(v_dati::text, v_esito));

  select c.esito into v_esito
  from pg_temp.chiama($q$select public.beta_validation_qv2_admin_participant_detail('X12')$q$, c_admin) c;
  perform pg_temp.registra(34, 'dettaglio codice malformato negato', v_esito = '22023', v_esito);

  -- Distribuzioni: sole risposte registrate dalla coorte QV2.
  select c.esito, c.dati into v_esito, v_dati
  from pg_temp.chiama('select public.beta_validation_qv2_admin_distributions()', c_admin) c;
  perform pg_temp.registra(35, 'distribuzioni: rispondenti e basi',
    v_esito = 'NESSUN_ERRORE'
      and (v_dati->>'respondents')::int = 4
      and (v_dati->>'preCompleted')::int = 3
      and (v_dati->>'postCompleted')::int = 1
      and (v_dati#>>'{questions,q01,base}')::int = 4
      and (v_dati#>>'{questions,q01,counts,25_34}')::int = 2
      and (v_dati#>>'{questions,q01,counts,45_54}')::int = 1
      and (v_dati#>>'{questions,q01,counts,65_plus}')::int = 1
      and (v_dati#>>'{questions,q12,base}')::int = 3
      and (v_dati#>>'{questions,q14,base}')::int = 1,
    coalesce(left(v_dati::text, 300), v_esito));

  perform pg_temp.registra(36, 'multi-select: una persona su piu opzioni, base per rispondenti',
    (v_dati#>>'{questions,q05,base}')::int = 3
      and (v_dati#>>'{questions,q05,counts,wine_shop}')::int = 2
      and (v_dati#>>'{questions,q05,counts,producer}')::int = 2
      and (v_dati#>>'{questions,q05,counts,other}')::int = 1
      and (v_dati#>>'{questions,q05,counts,auction}')::int = 1
      and (v_dati#>>'{questions,q07,base}')::int = 3
      and (v_dati#>>'{questions,q07,counts,authenticity}')::int = 2
      and (v_dati#>>'{questions,q19,base}')::int = 1
      and (v_dati#>>'{questions,q19,counts,protected_payment}')::int = 1
      and (v_dati#>>'{questions,q10_actions,base}')::int = 1,
    coalesce((v_dati#>'{questions,q05}')::text, 'null'));

  perform pg_temp.registra(37, 'distribuzioni senza testo libero ne identificatori',
    v_dati->'questions' ? 'q08' = false
      and v_dati->'questions' ? 'q17' = false
      and v_dati::text !~ 'Sommelier|Garanzia|Prezzi alti'
      and v_dati::text !~ c_uuid,
    left(v_dati::text, 300));

  -- ACL, volatilita e assenza di scritture.
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'beta_validation_qv2_admin_summary',
      'beta_validation_qv2_admin_participants',
      'beta_validation_qv2_admin_participant_detail',
      'beta_validation_qv2_admin_distributions'
    )
    and p.provolatile = 's'
    and p.prosecdef
    and p.proconfig @> array['search_path=""']
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
    and not has_function_privilege('service_role', p.oid, 'execute');
  perform pg_temp.registra(38, 'quattro RPC stable, definer, search_path vuoto e ACL chiuse',
    v_n = 4, 'conformi=' || v_n::text || '/4');

  perform pg_temp.registra(39, 'helper privato senza execute client e senza definer',
    not has_function_privilege('anon', 'private.beta_validation_qv2_admin_rows()', 'execute')
      and not has_function_privilege('authenticated', 'private.beta_validation_qv2_admin_rows()', 'execute')
      and not (select p.prosecdef from pg_proc p where p.oid = 'private.beta_validation_qv2_admin_rows()'::regprocedure),
    'helper');

  perform pg_temp.registra(40, 'porte MV3 invariate e ancora presenti',
    to_regprocedure('public.beta_validation_admin_summary()') is not null
      and to_regprocedure('public.beta_validation_admin_participants(text, integer, integer)') is not null,
    'MV3');

  select * into b from snapshot_12u;
  perform pg_temp.registra(41, 'nessuna scrittura su sessioni, eventi e risposte',
    (select count(*) from private.beta_validation_sessions) = b.mv_sessions
      and (select count(*) from private.beta_validation_events) = b.mv_events
      and (select count(*) from private.beta_validation_qv2) = b.qv2_rows
      and (select md5(string_agg(to_jsonb(q)::text, ',' order by q.session_id))
             from private.beta_validation_qv2 q) = b.qv2_hash
      and (select md5(string_agg(s.id::text || ':' || s.capability_hash || ':' || coalesce(s.completed_at::text, ''), ',' order by s.id))
             from private.beta_validation_sessions s) = b.sessions_hash,
    'sessioni/eventi/risposte invariati');

  -- Dataset vuoto in una subtransazione annullata: zero-safe, nessuna
  -- divisione per zero, nessuna riga e nessuna distribuzione inventata.
  begin
    delete from private.beta_validation_events;
    delete from private.beta_validation_qv2;
    delete from private.beta_validation_sessions;
    select c.dati into v_dati
    from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', c_admin) c;
    v_empty_ok := (v_dati#>>'{qv2,started}')::int = 0
      and (v_dati#>>'{qv2,completionRate}')::numeric = 0
      and (v_dati#>>'{legacy,coreCompletionRate}')::numeric = 0;
    v_empty_detail := coalesce(v_dati::text, 'null');
    select c.dati into v_dati
    from pg_temp.chiama('select public.beta_validation_qv2_admin_distributions()', c_admin) c;
    v_empty_ok := v_empty_ok
      and (v_dati->>'respondents')::int = 0
      and v_dati->'questions' = '{}'::jsonb;
    select c.dati into v_dati
    from pg_temp.chiama(pg_temp.partecipanti('null, null, 50, 0'), c_admin) c;
    v_empty_ok := v_empty_ok and v_dati = '[]'::jsonb;
    v_empty_detail := v_empty_detail || ' ' || coalesce(v_dati::text, 'null');
    raise exception '__12u_restore__';
  exception when others then
    if sqlerrm <> '__12u_restore__' then raise; end if;
  end;
  perform pg_temp.registra(42, 'dataset vuoto zero-safe', v_empty_ok, v_empty_detail);
end $$;

select id, descrizione, passed, detail
from esiti_12u
order by id;

rollback;
