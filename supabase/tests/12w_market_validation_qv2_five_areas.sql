-- Market Validation QV2: le cinque aree obbligatorie della Prova Vinea (griglia 12w).
--
-- SOLO stack Supabase locale/effimero. Fixture pseudonime e due utenti Auth
-- `.test` vivono nella transazione e spariscono con ROLLBACK. La griglia prova
-- la migrazione 20261008230000: evento cellar_viewed, stato derivato
-- experience_completed (ACQUISTO + VENDITA + AI + CLUB + CANTINA), rifiuto di
-- beta_completed e di finish_post con meno di 5/5 anche da client manipolato,
-- sessione chiusa con la regola precedente non reinterpretata, semantica MV1
-- invariata, resume e letture admin (tester, dettaglio, KPI) negate ad anon e
-- non-admin.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12w: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12w (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12w (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Esegue p_sql con il ruolo e i claim di PostgREST; restituisce SQLSTATE o
-- NESSUN_ERRORE e l'eventuale risultato jsonb.
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

-- Porte pubbliche del tester, sempre come anon.
create function pg_temp.start_qv2(p_cap text) returns jsonb language sql as $f$
  select c.dati from pg_temp.chiama(
    format('select to_jsonb(x) from public.beta_validation_qv2_start(%L) x', p_cap), null, 'anon') c;
$f$;

create function pg_temp.leggi(p_session uuid, p_cap text) returns jsonb language sql as $f$
  select c.dati from pg_temp.chiama(
    format('select public.beta_validation_qv2_read(%L::uuid, %L)', p_session, p_cap), null, 'anon') c;
$f$;

create function pg_temp.rispondi(p_session uuid, p_cap text, p_q text, p_answer jsonb) returns text language sql as $f$
  select c.esito from pg_temp.chiama(
    format('select to_jsonb(public.beta_validation_qv2_answer(%L::uuid, %L, %L, %L::jsonb))', p_session, p_cap, p_q, p_answer),
    null, 'anon') c;
$f$;

create function pg_temp.evento(p_session uuid, p_code text, p_cap text, p_event text) returns text language sql as $f$
  select c.esito from pg_temp.chiama(
    format('select to_jsonb(public.beta_validation_event_record(%L::uuid, %L, %L, %L))', p_session, p_code, p_cap, p_event),
    null, 'anon') c;
$f$;

create function pg_temp.fine(p_fase text, p_session uuid, p_cap text) returns text language sql as $f$
  select c.esito from pg_temp.chiama(
    format('select to_jsonb(public.beta_validation_qv2_finish_%s(%L::uuid, %L))', p_fase, p_session, p_cap),
    null, 'anon') c;
$f$;

-- PRE completo e chiuso, poi POST Q14-Q20 risposto (non chiuso).
create function pg_temp.pre_e_post(p_session uuid, p_cap text) returns text language plpgsql as $f$
declare v_esiti text[] := array[]::text[];
begin
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q01', '"35_44"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q02', '{"choice":"enthusiast"}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q03', '"one_two_month"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q04', '"20_40"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q05', '{"choices":["wine_shop"]}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q06', '{"choice":"no"}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q07', '["authenticity"]');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q08', '"Garanzie chiare"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q09', '"one_five"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q10', '{"choice":"no"}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q11', '{"choice":"never"}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q12', '"ten_twelve"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q13', '"sixteen_twenty"');
  v_esiti := v_esiti || pg_temp.fine('pre', p_session, p_cap);
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q14', '"buy"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q15', '{"choice":"yes"}');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q16', '"maybe"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q17', '"Fiducia"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q18', '"Piu foto"');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q19', '["reviews"]');
  v_esiti := v_esiti || pg_temp.rispondi(p_session, p_cap, 'q20', '"both"');
  return case when v_esiti <@ array['NESSUN_ERRORE'] then 'OK' else array_to_string(v_esiti, ',') end;
end;
$f$;

\set admin_id '12dd0000-0000-4000-8000-000000000001'
\set user_id  '12dd0000-0000-4000-8000-000000000002'

set local session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
  (:'admin_id', 'admin-12w@market-validation.test', '{}'::jsonb),
  (:'user_id', 'user-12w@market-validation.test', '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'admin_id', 'admin-12w', date '1990-01-01'),
  (:'user_id', 'user-12w', date '1990-01-01');
insert into public.user_roles (user_id, role) values
  (:'admin_id', 'admin'),
  (:'user_id', 'user');
set local session_replication_role = origin;

do $$
declare
  c_cap constant text := '12dd0000-0000-4000-8000-0000000000c1';
  c_cap_noclub constant text := '12dd0000-0000-4000-8000-0000000000c2';
  c_cap_noai constant text := '12dd0000-0000-4000-8000-0000000000c3';
  c_cap_old constant text := '12dd0000-0000-4000-8000-0000000000c4';
  c_cap_mv1 constant text := '12dd0000-0000-4000-8000-0000000000c5';
  c_admin constant uuid := '12dd0000-0000-4000-8000-000000000001';
  c_user constant uuid := '12dd0000-0000-4000-8000-000000000002';
  v_start jsonb;
  v_again jsonb;
  v_session uuid;
  v_code text;
  s_noclub uuid; k_noclub text;
  s_noai uuid; k_noai text;
  s_old uuid; k_old text;
  s_mv1 uuid;
  v_read jsonb;
  v_esito text;
  v_dati jsonb;
  v_row jsonb;
  v_e1 text; v_e2 text; v_e3 text;
begin
  -- 1: schema e privilegi. cellar_viewed ammesso dal CHECK, helper privato
  -- non eseguibile dai client, porte tester secdef con search_path vuoto.
  perform pg_temp.registra(1, 'cellar_viewed nel CHECK; helper 5/5 privato; porte secdef con search_path vuoto',
    pg_get_constraintdef((select oid from pg_constraint where conname = 'beta_validation_events_event_name_check'
                          and conrelid = 'private.beta_validation_events'::regclass)) like '%cellar_viewed%'
      and not has_function_privilege('anon', 'private.beta_validation_qv2_experience_completed(uuid)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'private.beta_validation_qv2_experience_completed(uuid)', 'EXECUTE')
      and not has_function_privilege('service_role', 'private.beta_validation_qv2_experience_completed(uuid)', 'EXECUTE')
      and not has_function_privilege('anon', 'private.beta_validation_qv2_admin_rows()', 'EXECUTE')
      and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in (
              'beta_validation_event_record', 'beta_validation_qv2_read', 'beta_validation_qv2_finish_post',
              'beta_validation_qv2_admin_summary', 'beta_validation_qv2_admin_participants',
              'beta_validation_qv2_admin_participant_detail'))
      and has_function_privilege('anon', 'public.beta_validation_event_record(uuid,text,text,text,jsonb)', 'EXECUTE')
      and has_function_privilege('anon', 'public.beta_validation_qv2_finish_post(uuid,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE'),
    'check/acl');

  v_start := pg_temp.start_qv2(c_cap);
  v_session := (v_start ->> 'session_id')::uuid;
  v_code := v_start ->> 'participant_code';

  -- 2: la sessione nuova parte 0/5; start e read non registrano aree.
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(2, 'sessione nuova 0/5: start e read non registrano aree',
    not (v_read ->> 'buyer_completed')::boolean
      and not (v_read ->> 'seller_completed')::boolean
      and not (v_read ->> 'ai_viewed')::boolean
      and not (v_read ->> 'club_viewed')::boolean
      and not (v_read ->> 'cellar_viewed')::boolean
      and not (v_read ->> 'experience_completed')::boolean
      and (select count(*) from private.beta_validation_events where session_id = v_session) = 1,
    coalesce(v_read::text, 'null'));

  -- 3: evento inventato e codice partecipante falso rifiutati.
  v_e1 := pg_temp.evento(v_session, v_code, c_cap, 'cantina_vista');
  v_e2 := pg_temp.evento(v_session, 'V998', c_cap, 'cellar_viewed');
  v_e3 := pg_temp.evento(v_session, v_code, c_cap_noclub, 'cellar_viewed');
  perform pg_temp.registra(3, 'evento fuori allowlist, codice o capability diversi rifiutati',
    v_e1 = '22023' and v_e2 = '42501' and v_e3 = '42501'
      and not exists (select 1 from private.beta_validation_events
                      where session_id = v_session and event_name = 'cellar_viewed'),
    concat_ws(' ', v_e1, v_e2, v_e3));

  -- 4: PRE + POST risposti ma nessuna area: finish_post rifiutato.
  v_esito := pg_temp.pre_e_post(v_session, c_cap);
  v_e1 := pg_temp.fine('post', v_session, c_cap);
  perform pg_temp.registra(4, 'POST risposto senza Prova Vinea: finish_post rifiutato',
    v_esito = 'OK'
      and v_e1 = '22023'
      and not exists (select 1 from private.beta_validation_events
                      where session_id = v_session and event_name = 'validation_completed'),
    v_esito);

  -- 5: ACQUISTO + VENDITA non bastano piu: beta_completed rifiutato.
  perform pg_temp.evento(v_session, v_code, c_cap, 'checkout_beta_completed');
  perform pg_temp.evento(v_session, v_code, c_cap, 'sell_completed');
  v_esito := pg_temp.evento(v_session, v_code, c_cap, 'beta_completed');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(5, 'BUY+SELL: beta_completed rifiutato, sessione aperta, 2/5',
    v_esito = '22023'
      and (v_read ->> 'buyer_completed')::boolean
      and (v_read ->> 'seller_completed')::boolean
      and not (v_read ->> 'experience_completed')::boolean
      and not (v_read ->> 'core_completed')::boolean
      and (select completed_at is null from private.beta_validation_sessions where id = v_session),
    v_esito);

  -- 6: BUY + SELL + AI + CLUB senza CANTINA: ancora bloccato (4/5).
  perform pg_temp.evento(v_session, v_code, c_cap, 'ai_preview_viewed');
  perform pg_temp.evento(v_session, v_code, c_cap, 'club_viewed');
  v_esito := pg_temp.evento(v_session, v_code, c_cap, 'beta_completed');
  v_e1 := pg_temp.fine('post', v_session, c_cap);
  perform pg_temp.registra(6, 'BUY+SELL+AI+CLUB senza Cantina: beta_completed e finish_post rifiutati',
    v_esito = '22023'
      and v_e1 = '22023'
      and not (pg_temp.leggi(v_session, c_cap) ->> 'experience_completed')::boolean,
    v_esito);

  -- 7: cellar_viewed registrato solo dalla porta eventi, letto dal server.
  v_esito := pg_temp.evento(v_session, v_code, c_cap, 'cellar_viewed');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(7, 'cellar_viewed registrato dalla porta eventi e 5/5 derivato dal server',
    v_esito = 'NESSUN_ERRORE'
      and (v_read ->> 'cellar_viewed')::boolean
      and (v_read ->> 'ai_viewed')::boolean
      and (v_read ->> 'club_viewed')::boolean
      and (v_read ->> 'experience_completed')::boolean
      and (select count(*) from private.beta_validation_events
           where session_id = v_session and event_name = 'cellar_viewed'
             and participant_code = v_code and metadata = '{}'::jsonb) = 1,
    v_esito);

  -- 8: resume con la stessa capability: stesso codice e stesse cinque aree.
  v_again := pg_temp.start_qv2(c_cap);
  v_read := pg_temp.leggi((v_again ->> 'session_id')::uuid, c_cap);
  perform pg_temp.registra(8, 'resume conserva codice e stato delle cinque aree',
    v_again ->> 'participant_code' = v_code
      and (v_again ->> 'resumed')::boolean
      and (v_read ->> 'experience_completed')::boolean
      and (v_read ->> 'cellar_viewed')::boolean,
    coalesce(v_again::text, 'null'));

  -- 9: 5/5 senza beta_completed: finish_post ancora rifiutato.
  v_e1 := pg_temp.fine('post', v_session, c_cap);
  perform pg_temp.registra(9, '5/5 senza chiusura Prova Vinea: finish_post rifiutato',
    v_e1 = '22023', v_e1);

  -- 10: 5/5 + beta_completed + POST: validation_completed una sola volta.
  v_esito := pg_temp.evento(v_session, v_code, c_cap, 'beta_completed');
  v_e1 := pg_temp.fine('post', v_session, c_cap);
  v_e2 := pg_temp.fine('post', v_session, c_cap);
  perform pg_temp.registra(10, '5/5 sblocca beta_completed e finish_post; validation_completed idempotente',
    v_esito = 'NESSUN_ERRORE'
      and v_e1 = 'NESSUN_ERRORE'
      and v_e2 = 'NESSUN_ERRORE'
      and (select count(*) from private.beta_validation_events
           where session_id = v_session and event_name = 'validation_completed') = 1
      and pg_temp.leggi(v_session, c_cap) ->> 'validation_completed_at' is not null,
    concat_ws(' ', v_esito, v_e1, v_e2));

  -- 11: BUY + SELL + AI + CANTINA senza CLUB.
  v_start := pg_temp.start_qv2(c_cap_noclub);
  s_noclub := (v_start ->> 'session_id')::uuid;
  k_noclub := v_start ->> 'participant_code';
  perform pg_temp.pre_e_post(s_noclub, c_cap_noclub);
  perform pg_temp.evento(s_noclub, k_noclub, c_cap_noclub, 'checkout_beta_completed');
  perform pg_temp.evento(s_noclub, k_noclub, c_cap_noclub, 'sell_completed');
  perform pg_temp.evento(s_noclub, k_noclub, c_cap_noclub, 'ai_preview_viewed');
  perform pg_temp.evento(s_noclub, k_noclub, c_cap_noclub, 'cellar_viewed');
  v_e1 := pg_temp.evento(s_noclub, k_noclub, c_cap_noclub, 'beta_completed');
  v_e2 := pg_temp.fine('post', s_noclub, c_cap_noclub);
  perform pg_temp.registra(11, 'BUY+SELL+AI+CANTINA senza Club: bloccato',
    v_e1 = '22023'
      and v_e2 = '22023'
      and not (pg_temp.leggi(s_noclub, c_cap_noclub) ->> 'experience_completed')::boolean,
    k_noclub);

  -- 12: BUY + SELL + CLUB + CANTINA senza AI.
  v_start := pg_temp.start_qv2(c_cap_noai);
  s_noai := (v_start ->> 'session_id')::uuid;
  k_noai := v_start ->> 'participant_code';
  perform pg_temp.pre_e_post(s_noai, c_cap_noai);
  perform pg_temp.evento(s_noai, k_noai, c_cap_noai, 'checkout_beta_completed');
  perform pg_temp.evento(s_noai, k_noai, c_cap_noai, 'sell_completed');
  perform pg_temp.evento(s_noai, k_noai, c_cap_noai, 'club_viewed');
  perform pg_temp.evento(s_noai, k_noai, c_cap_noai, 'cellar_viewed');
  perform pg_temp.evento(s_noai, k_noai, c_cap_noai, 'ai_interest_clicked');
  v_e1 := pg_temp.evento(s_noai, k_noai, c_cap_noai, 'beta_completed');
  v_e2 := pg_temp.fine('post', s_noai, c_cap_noai);
  perform pg_temp.registra(12, 'BUY+SELL+CLUB+CANTINA senza AI (anche con ai_interest_clicked): bloccato',
    v_e1 = '22023'
      and v_e2 = '22023'
      and not (pg_temp.leggi(s_noai, c_cap_noai) ->> 'experience_completed')::boolean,
    k_noai);

  -- 13: sessione chiusa con la regola precedente (beta_completed con BUY+SELL,
  -- scritto qui da un writer privilegiato): non viene reinterpretata e non
  -- puo produrre validation_completed.
  v_start := pg_temp.start_qv2(c_cap_old);
  s_old := (v_start ->> 'session_id')::uuid;
  k_old := v_start ->> 'participant_code';
  perform pg_temp.pre_e_post(s_old, c_cap_old);
  perform pg_temp.evento(s_old, k_old, c_cap_old, 'checkout_beta_completed');
  perform pg_temp.evento(s_old, k_old, c_cap_old, 'sell_completed');
  perform pg_temp.evento(s_old, k_old, c_cap_old, 'ai_preview_viewed');
  insert into private.beta_validation_events (session_id, participant_code, event_name)
    values (s_old, k_old, 'beta_completed');
  update private.beta_validation_sessions set completed_at = clock_timestamp() where id = s_old;
  v_read := pg_temp.leggi(s_old, c_cap_old);
  v_e1 := pg_temp.fine('post', s_old, c_cap_old);
  v_e2 := pg_temp.evento(s_old, k_old, c_cap_old, 'cellar_viewed');
  perform pg_temp.registra(13, 'sessione chiusa con BUY+SELL: core vero, esperienza 3/5, POST bloccato, nessun evento aggiunto',
    (v_read ->> 'core_completed')::boolean
      and not (v_read ->> 'experience_completed')::boolean
      and not (v_read ->> 'club_viewed')::boolean
      and v_e1 = '22023'
      and v_e2 = '22023'
      and not exists (select 1 from private.beta_validation_events
                      where session_id = s_old and event_name in ('cellar_viewed', 'validation_completed'))
      and v_read ->> 'post_finished_at' is null,
    coalesce(v_read::text, 'null'));

  -- 14: MV1 legacy invariata: beta_completed senza le cinque aree.
  select (x).session_id into s_mv1
  from (select public.beta_validation_session_start('V950', c_cap_mv1) as x) t;
  v_e1 := pg_temp.evento(s_mv1, 'V950', c_cap_mv1, 'checkout_beta_completed');
  v_e2 := pg_temp.evento(s_mv1, 'V950', c_cap_mv1, 'beta_completed');
  perform pg_temp.registra(14, 'sessione MV1 legacy: beta_completed ammesso come prima',
    v_e1 = 'NESSUN_ERRORE'
      and v_e2 = 'NESSUN_ERRORE'
      and (select completed_at is not null from private.beta_validation_sessions where id = s_mv1),
    concat_ws(' ', s_mv1, v_e1, v_e2));

  -- 15: gate admin.
  perform pg_temp.registra(15, 'anon e non-admin negati su KPI, tester e dettaglio',
    (select c.esito from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', null, 'anon') c) = '42501'
      and (select c.esito from pg_temp.chiama('select public.beta_validation_qv2_admin_summary()', c_user) c) = '42501'
      and (select c.esito from pg_temp.chiama(
        'select coalesce(jsonb_agg(to_jsonb(p)), ''[]'') from public.beta_validation_qv2_admin_participants(null, null, 50, 0) p',
        c_user) c) = '42501'
      and (select c.esito from pg_temp.chiama(
        format('select public.beta_validation_qv2_admin_participant_detail(%L)', v_code), null, 'anon') c) = '42501',
    'gate');

  -- 16: tabella tester: cellar_viewed ed experience_completed per codice.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(p) order by p.participant_code), ''[]'') from public.beta_validation_qv2_admin_participants(null, ''qv2'', 50, 0) p',
    c_admin) c;
  perform pg_temp.registra(16, 'admin participants: cellar_viewed ed experience_completed per codice, senza capability',
    v_esito = 'NESSUN_ERRORE'
      and (select (r ->> 'experience_completed')::boolean and (r ->> 'cellar_viewed')::int = 1
             and r ->> 'validation_completed_at' is not null
           from jsonb_array_elements(v_dati) r where r ->> 'participant_code' = v_code)
      and (select not (r ->> 'experience_completed')::boolean and (r ->> 'club_viewed')::int = 0
           from jsonb_array_elements(v_dati) r where r ->> 'participant_code' = k_noclub)
      and (select not (r ->> 'experience_completed')::boolean and (r ->> 'ai_preview_viewed')::int = 0
             and (r ->> 'ai_interest_clicked')::int = 1
           from jsonb_array_elements(v_dati) r where r ->> 'participant_code' = k_noai)
      and (select not (r ->> 'experience_completed')::boolean and (r ->> 'beta_completed')::int = 1
           from jsonb_array_elements(v_dati) r where r ->> 'participant_code' = k_old)
      and not exists (select 1 from jsonb_array_elements(v_dati) r
                      where r ?| array['capability', 'capability_hash', 'session_id', 'qv2_session_id']),
    v_esito);

  -- 17: dettaglio con cellar_viewed nella sequenza e completion.experienceCompleted.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    format('select public.beta_validation_qv2_admin_participant_detail(%L)', v_code), c_admin) c;
  perform pg_temp.registra(17, 'admin dettaglio: 14 eventi con cellar_viewed ed esperienza 5/5',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati -> 'events') = 14
      and (select (x ->> 'count')::int from jsonb_array_elements(v_dati -> 'events') x
           where x ->> 'event' = 'cellar_viewed') = 1
      and (v_dati #>> '{completion,experienceCompleted}')::boolean
      and v_dati #>> '{completion,validationCompletedAt}' is not null,
    v_esito);

  -- 18: KPI della coorte QV2 con esperienza 5/5 e Cantina.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    'select public.beta_validation_qv2_admin_summary()', c_admin) c;
  perform pg_temp.registra(18, 'admin KPI: 4 iniziati, 1 esperienza 5/5, 3 Cantina, 1 completo',
    v_esito = 'NESSUN_ERRORE'
      and (v_dati #>> '{qv2,started}')::int = 4
      and (v_dati #>> '{qv2,experienceCompleted}')::int = 1
      and (v_dati #>> '{qv2,cellarViewed}')::int = 3
      and (v_dati #>> '{qv2,coreCompleted}')::int = 2
      and (v_dati #>> '{qv2,validationCompleted}')::int = 1,
    coalesce(v_dati::text, v_esito));
end $$;

select id, descrizione, passed, detail
from esiti_12w
order by id;

rollback;
