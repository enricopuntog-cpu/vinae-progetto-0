-- Market Validation QV2: opzione «Altro» di Q7 e Q19 (griglia 12v).
--
-- SOLO stack Supabase locale/effimero. Fixture pseudonime e due utenti Auth
-- `.test` vivono nella transazione e spariscono con ROLLBACK. La griglia prova
-- la migrazione 20261008220000: colonne q07_other/q19_other private, «Altro»
-- che conta nel massimo, specifica obbligatoria solo con «Altro», rifiuto di
-- testo senza selezione, compatibilita del formato array e di Q5, percorso
-- completo PRE/BUY/SELL/CORE/POST fino a validation_completed idempotente,
-- resume dopo la chiusura, isolamento delle capability e lettura admin
-- (tester, dettaglio, distribuzioni) negata ad anon e non-admin.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12v: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12v (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12v (id, descrizione, passed, detail)
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

create function pg_temp.porta(p_sql text, p_cap text) returns text language sql as $f$
  select c.esito from pg_temp.chiama(p_sql, null, 'anon') c;
$f$;

\set admin_id '12dc0000-0000-4000-8000-000000000001'
\set user_id  '12dc0000-0000-4000-8000-000000000002'

set local session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
  (:'admin_id', 'admin-12v@market-validation.test', '{}'::jsonb),
  (:'user_id', 'user-12v@market-validation.test', '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'admin_id', 'admin-12v', date '1990-01-01'),
  (:'user_id', 'user-12v', date '1990-01-01');
insert into public.user_roles (user_id, role) values
  (:'admin_id', 'admin'),
  (:'user_id', 'user');
set local session_replication_role = origin;

do $$
declare
  c_cap constant text := '12dc0000-0000-4000-8000-0000000000c1';
  c_cap2 constant text := '12dc0000-0000-4000-8000-0000000000c2';
  c_admin constant uuid := '12dc0000-0000-4000-8000-000000000001';
  c_user constant uuid := '12dc0000-0000-4000-8000-000000000002';
  v_start jsonb;
  v_again jsonb;
  v_other jsonb;
  v_session uuid;
  v_code text;
  v_read jsonb;
  v_esito text;
  v_dati jsonb;
  v_row jsonb;
begin
  -- 1: schema. Colonne nuove nella sola tabella privata, senza grant client.
  perform pg_temp.registra(1, 'q07_other e q19_other presenti e senza privilegi client',
    exists (select 1 from information_schema.columns
            where table_schema = 'private' and table_name = 'beta_validation_qv2' and column_name = 'q07_other')
      and exists (select 1 from information_schema.columns
            where table_schema = 'private' and table_name = 'beta_validation_qv2' and column_name = 'q19_other')
      and not has_column_privilege('anon', 'private.beta_validation_qv2', 'q07_other', 'SELECT')
      and not has_column_privilege('authenticated', 'private.beta_validation_qv2', 'q19_other', 'SELECT')
      and not has_table_privilege('anon', 'private.beta_validation_qv2', 'SELECT,INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated', 'private.beta_validation_qv2', 'SELECT,INSERT,UPDATE,DELETE'),
    'colonne/privilegi');

  -- 2: porte invariate nella forma: security definer, search_path vuoto, ACL minime.
  perform pg_temp.registra(2, 'porte answer/participants/detail secdef con search_path vuoto e ACL minime',
    (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in (
        'beta_validation_qv2_answer', 'beta_validation_qv2_admin_participants', 'beta_validation_qv2_admin_participant_detail'))
      and has_function_privilege('anon', 'public.beta_validation_qv2_answer(uuid,text,text,jsonb)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.beta_validation_qv2_admin_participant_detail(text)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.beta_validation_qv2_admin_participants(text,text,integer,integer)', 'EXECUTE'),
    'prosecdef/proconfig/acl');

  v_start := pg_temp.start_qv2(c_cap);
  v_session := (v_start ->> 'session_id')::uuid;
  v_code := v_start ->> 'participant_code';

  -- 3: Q7 con «Altro» e specifica: tre scelte, «Altro» compreso.
  v_esito := pg_temp.rispondi(v_session, c_cap, 'q07',
    '{"choices":["authenticity","price","other"],"other":"  Annata non verificabile  "}');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(3, 'Q7 Altro con specifica salvato (conta nel massimo di 3)',
    v_esito = 'NESSUN_ERRORE'
      and v_read -> 'answers' -> 'q07' = '["authenticity","price","other"]'::jsonb
      and v_read -> 'answers' ->> 'q07_other' = 'Annata non verificabile',
    v_esito || ' ' || coalesce(v_read -> 'answers' ->> 'q07_other', 'null'));

  -- 4: specifica senza «Altro» rifiutata, valore precedente conservato.
  v_esito := pg_temp.rispondi(v_session, c_cap, 'q07', '{"choices":["authenticity"],"other":"Testo orfano"}');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(4, 'Q7 specifica senza Altro rifiutata',
    v_esito = '22023' and v_read -> 'answers' ->> 'q07_other' = 'Annata non verificabile', v_esito);

  -- 5: «Altro» senza specifica rifiutato, in forma array e oggetto.
  perform pg_temp.registra(5, 'Q7 Altro senza specifica rifiutato',
    pg_temp.rispondi(v_session, c_cap, 'q07', '["other"]') = '22023'
      and pg_temp.rispondi(v_session, c_cap, 'q07', '{"choices":["other"]}') = '22023'
      and pg_temp.rispondi(v_session, c_cap, 'q07', '{"choices":["other"],"other":"   "}') = '22023',
    'array/oggetto/spazi');

  -- 6: quattro scelte con «Altro» superano il massimo di 3.
  perform pg_temp.registra(6, 'Q7 quattro scelte con Altro rifiutate',
    pg_temp.rispondi(v_session, c_cap, 'q07',
      '{"choices":["authenticity","price","payment","other"],"other":"Troppo"}') = '22023', 'max 3');

  -- 7: specifica oltre 500 caratteri e chiave estranea rifiutate.
  perform pg_temp.registra(7, 'Q7 specifica troppo lunga o campo estraneo rifiutati',
    pg_temp.rispondi(v_session, c_cap, 'q07',
      jsonb_build_object('choices', jsonb_build_array('other'), 'other', repeat('x', 501))) = '22023'
      and pg_temp.rispondi(v_session, c_cap, 'q07', '{"choices":["other"],"other":"ok","extra":"no"}') = '22023',
    '501/extra');

  -- 8: il formato array resta valido e azzera la specifica precedente.
  v_esito := pg_temp.rispondi(v_session, c_cap, 'q07', '["storage","shipping"]');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(8, 'Q7 array senza Altro accettato e specifica azzerata',
    v_esito = 'NESSUN_ERRORE'
      and v_read -> 'answers' -> 'q07' = '["storage","shipping"]'::jsonb
      and v_read -> 'answers' -> 'q07_other' = 'null'::jsonb,
    v_esito);

  -- 9: il CHECK di tabella vincola anche un writer privilegiato.
  begin
    update private.beta_validation_qv2 set q07_other = 'Senza Altro' where session_id = v_session;
    perform pg_temp.registra(9, 'CHECK di tabella: specifica senza Altro e Altro senza specifica', false, 'update permesso');
  exception when check_violation then
    begin
      update private.beta_validation_qv2 set q19 = array['other'] where session_id = v_session;
      perform pg_temp.registra(9, 'CHECK di tabella: specifica senza Altro e Altro senza specifica', false, 'q19 other senza specifica permesso');
    exception when check_violation then
      perform pg_temp.registra(9, 'CHECK di tabella: specifica senza Altro e Altro senza specifica', true, '23514');
    end;
  end;

  -- 10: Q5 conserva la semantica QV1 («Altro» con specifica facoltativa lato DB).
  perform pg_temp.registra(10, 'Q5 invariata: Altro senza specifica ammesso, con specifica salvata',
    pg_temp.rispondi(v_session, c_cap, 'q05', '{"choices":["wine_shop","other"]}') = 'NESSUN_ERRORE'
      and pg_temp.rispondi(v_session, c_cap, 'q05', '{"choices":["wine_shop","other"],"other":"Fiere"}') = 'NESSUN_ERRORE'
      and pg_temp.leggi(v_session, c_cap) -> 'answers' ->> 'q05_other' = 'Fiere',
    'q05');

  -- 11: un'altra capability non scrive la Q7 di questa sessione.
  v_other := pg_temp.start_qv2(c_cap2);
  perform pg_temp.registra(11, 'capability isolata: scrittura Q7 incrociata negata e nuovo codice distinto',
    pg_temp.rispondi(v_session, c_cap2, 'q07', '{"choices":["other"],"other":"Intruso"}') = '42501'
      and v_other ->> 'participant_code' <> v_code
      and pg_temp.leggi(v_session, c_cap) -> 'answers' -> 'q07' = '["storage","shipping"]'::jsonb,
    coalesce(v_other ->> 'participant_code', 'null') || ' vs ' || v_code);

  -- 12: Q19 prima della chiusura PRE rifiutata (fase non aperta).
  perform pg_temp.registra(12, 'Q19 prima del PRE concluso rifiutata',
    pg_temp.rispondi(v_session, c_cap, 'q19', '{"choices":["other"],"other":"Presto"}') = '22023', 'fase');

  -- PRE completo con Q7 «Altro».
  perform pg_temp.rispondi(v_session, c_cap, 'q01', '"35_44"');
  perform pg_temp.rispondi(v_session, c_cap, 'q02', '{"choice":"enthusiast"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q03', '"one_two_month"');
  perform pg_temp.rispondi(v_session, c_cap, 'q04', '"20_40"');
  perform pg_temp.rispondi(v_session, c_cap, 'q06', '{"choice":"no"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q07', '{"choices":["seller_reliability","other"],"other":"Tempi di consegna"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q08', '"Garanzie chiare"');
  perform pg_temp.rispondi(v_session, c_cap, 'q09', '"one_five"');
  perform pg_temp.rispondi(v_session, c_cap, 'q10', '{"choice":"no"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q11', '{"choice":"never"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q12', '"would_not_buy"');
  perform pg_temp.rispondi(v_session, c_cap, 'q13', '"would_not_buy"');
  v_esito := pg_temp.porta(format('select to_jsonb(public.beta_validation_qv2_finish_pre(%L::uuid, %L))', v_session, c_cap), c_cap);
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(13, 'PRE concluso con Q7 Altro',
    v_esito = 'NESSUN_ERRORE' and v_read ->> 'pre_finished_at' is not null
      and v_read -> 'answers' ->> 'q07_other' = 'Tempi di consegna',
    v_esito);

  -- 14: Q7 bloccata dopo la chiusura del PRE.
  perform pg_temp.registra(14, 'Q7 non modificabile dopo il PRE',
    pg_temp.rispondi(v_session, c_cap, 'q07', '["price"]') = '22023'
      and pg_temp.leggi(v_session, c_cap) -> 'answers' ->> 'q07_other' = 'Tempi di consegna', 'fase');

  -- 15-17: Q19 con «Altro».
  v_esito := pg_temp.rispondi(v_session, c_cap, 'q19', '{"choices":["protected_payment","other"],"other":"Ritiro in cantina"}');
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(15, 'Q19 Altro con specifica salvato (conta nel massimo di 2)',
    v_esito = 'NESSUN_ERRORE'
      and v_read -> 'answers' -> 'q19' = '["protected_payment","other"]'::jsonb
      and v_read -> 'answers' ->> 'q19_other' = 'Ritiro in cantina',
    v_esito);
  perform pg_temp.registra(16, 'Q19 specifica senza Altro e Altro senza specifica rifiutati',
    pg_temp.rispondi(v_session, c_cap, 'q19', '{"choices":["reviews"],"other":"Orfano"}') = '22023'
      and pg_temp.rispondi(v_session, c_cap, 'q19', '["reviews","other"]') = '22023'
      and pg_temp.leggi(v_session, c_cap) -> 'answers' ->> 'q19_other' = 'Ritiro in cantina',
    'q19');
  perform pg_temp.registra(17, 'Q19 tre scelte con Altro oltre il massimo di 2',
    pg_temp.rispondi(v_session, c_cap, 'q19',
      '{"choices":["reviews","support","other"],"other":"Troppo"}') = '22023', 'max 2');

  -- Resto del POST e percorso core tramite la porta eventi MV1.
  perform pg_temp.rispondi(v_session, c_cap, 'q14', '"buy"');
  perform pg_temp.rispondi(v_session, c_cap, 'q15', '{"choice":"yes"}');
  perform pg_temp.rispondi(v_session, c_cap, 'q16', '"maybe"');
  perform pg_temp.rispondi(v_session, c_cap, 'q17', '"Fiducia nel venditore"');
  perform pg_temp.rispondi(v_session, c_cap, 'q18', '"Piu foto delle etichette"');
  perform pg_temp.rispondi(v_session, c_cap, 'q20', '"both"');
  perform public.beta_validation_event_record(v_session, v_code, c_cap, 'checkout_beta_completed');
  perform public.beta_validation_event_record(v_session, v_code, c_cap, 'sell_completed');
  perform public.beta_validation_event_record(v_session, v_code, c_cap, 'beta_completed');
  v_esito := pg_temp.porta(format('select to_jsonb(public.beta_validation_qv2_finish_post(%L::uuid, %L))', v_session, c_cap), c_cap);
  perform pg_temp.porta(format('select to_jsonb(public.beta_validation_qv2_finish_post(%L::uuid, %L))', v_session, c_cap), c_cap);
  v_read := pg_temp.leggi(v_session, c_cap);
  perform pg_temp.registra(18, 'BUY/SELL/CORE/POST e validation_completed una sola volta (replay idempotente)',
    v_esito = 'NESSUN_ERRORE'
      and (v_read ->> 'buyer_completed')::boolean
      and (v_read ->> 'seller_completed')::boolean
      and (v_read ->> 'core_completed')::boolean
      and v_read ->> 'post_finished_at' is not null
      and v_read ->> 'validation_completed_at' is not null
      and (select count(*) from private.beta_validation_events
           where session_id = v_session and event_name = 'validation_completed') = 1,
    v_esito);

  -- 19: dopo la chiusura nessuna risposta cambia.
  perform pg_temp.registra(19, 'Q19 bloccata dopo validation_completed',
    pg_temp.rispondi(v_session, c_cap, 'q19', '["reviews"]') = '22023'
      and pg_temp.leggi(v_session, c_cap) -> 'answers' ->> 'q19_other' = 'Ritiro in cantina', 'chiusa');

  -- 20: la stessa capability dopo la chiusura riprende lo stesso codice
  -- (schermata GRAZIE persistente), senza allocarne uno nuovo.
  v_again := pg_temp.start_qv2(c_cap);
  perform pg_temp.registra(20, 'resume dopo la chiusura: stesso codice e sessione',
    v_again ->> 'participant_code' = v_code
      and v_again ->> 'session_id' = v_session::text
      and (v_again ->> 'resumed')::boolean
      and (select count(*) from private.beta_validation_sessions
           where capability_hash = private.beta_validation_capability_hash(c_cap)) = 1,
    coalesce(v_again::text, 'null'));

  -- 21: gate admin sulle porte di lettura.
  perform pg_temp.registra(21, 'anon e non-admin negati su tester e dettaglio; anon non legge la tabella',
    (select c.esito from pg_temp.chiama(
       'select coalesce(jsonb_agg(to_jsonb(p)), ''[]'') from public.beta_validation_qv2_admin_participants(null, null, 50, 0) p',
       null, 'anon') c) = '42501'
      and (select c.esito from pg_temp.chiama(
       'select coalesce(jsonb_agg(to_jsonb(p)), ''[]'') from public.beta_validation_qv2_admin_participants(null, null, 50, 0) p',
       c_user) c) = '42501'
      and (select c.esito from pg_temp.chiama(
       format('select public.beta_validation_qv2_admin_participant_detail(%L)', v_code), c_user) c) = '42501'
      and (select c.esito from pg_temp.chiama(
       'select to_jsonb(count(*)) from private.beta_validation_qv2', null, 'anon') c) = '42501',
    'gate');

  -- 22: admin legge q07_other/q19_other nella tabella tester.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    format('select coalesce(jsonb_agg(to_jsonb(p)), ''[]'') from public.beta_validation_qv2_admin_participants(%L, null, 50, 0) p', v_code),
    c_admin) c;
  v_row := v_dati -> 0;
  perform pg_temp.registra(22, 'admin participants espone q07_other e q19_other senza capability',
    v_esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_dati) = 1
      and v_row -> 'q07' = '["seller_reliability","other"]'::jsonb
      and v_row ->> 'q07_other' = 'Tempi di consegna'
      and v_row -> 'q19' = '["protected_payment","other"]'::jsonb
      and v_row ->> 'q19_other' = 'Ritiro in cantina'
      and v_row ->> 'validation_completed_at' is not null
      and not (v_row ?| array['capability', 'capability_hash', 'session_id', 'qv2_session_id']),
    v_esito || ' ' || coalesce(v_row::text, 'null'));

  -- 23: dettaglio admin con le due specifiche.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    format('select public.beta_validation_qv2_admin_participant_detail(%L)', v_code), c_admin) c;
  perform pg_temp.registra(23, 'admin dettaglio espone q07_other e q19_other',
    v_esito = 'NESSUN_ERRORE'
      and v_dati #>> '{questionnaire,q07_other}' = 'Tempi di consegna'
      and v_dati #>> '{questionnaire,q19_other}' = 'Ritiro in cantina'
      and v_dati #>> '{completion,validationCompletedAt}' is not null,
    v_esito);

  -- 24: le distribuzioni contano «other» come ogni altra opzione.
  select c.esito, c.dati into v_esito, v_dati from pg_temp.chiama(
    'select public.beta_validation_qv2_admin_distributions()', c_admin) c;
  perform pg_temp.registra(24, 'distribuzioni Q7/Q19 contano Altro',
    v_esito = 'NESSUN_ERRORE'
      and (v_dati #>> '{questions,q07,counts,other}')::int = 1
      and (v_dati #>> '{questions,q19,counts,other}')::int = 1
      and (v_dati #>> '{questions,q19,base}')::int = 1,
    v_esito || ' ' || coalesce(v_dati #>> '{questions,q07}', 'null'));
end $$;

select id, descrizione, passed, detail
from esiti_12v
order by id;

rollback;
