-- 12t: Market Validation QV2 questionnaire grid.
-- Solo stack locale/effimero. Fixture private, ROLLBACK alla fine.
-- Verifica: start/resume deterministico, lettura con booleans derivati
-- dagli eventi autorizzati, answer condizionale validato, finish_pre/post,
-- evento 'validation_completed' ammesso dal CHECK esteso, assenza PII.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12t: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12t (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12t (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.start_qv2(p_cap text)
returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  set local role anon;
  select to_jsonb(x) into v from public.beta_validation_qv2_start(p_cap) x;
  reset role;
  return v;
exception when others then reset role; raise; end;
$f$;

create function pg_temp.read_qv2(p_session uuid, p_cap text)
returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  set local role anon;
  select public.beta_validation_qv2_read(p_session, p_cap) into v;
  reset role;
  return v;
exception when others then reset role; raise; end;
$f$;

-- Capability costante per il test, ripetibile e deterministica.
do $$
declare
  v1 jsonb; v2 jsonb; v_session uuid; v_read jsonb;
  v_code text;
begin
  -- 1: start QV2 deterministico.
  v1 := pg_temp.start_qv2('10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(1, 'QV2 start crea sessione con codice valido',
    (v1 ->> 'participant_code') ~ '^V[0-9]{3}$' and (v1 ->> 'resumed')::boolean = false,
    coalesce(v1::text, 'null'));

  -- 2: resume stesso capability = stessa sessione (non duplicata).
  v2 := pg_temp.start_qv2('10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(2, 'QV2 resume non duplica sessione',
    (v1 ->> 'session_id') = (v2 ->> 'session_id') and (v2 ->> 'resumed')::boolean = true,
    'prima=' || coalesce(v1 ->> 'session_id', 'null') || ' seconda=' || coalesce(v2 ->> 'session_id', 'null'));

  v_session := (v1 ->> 'session_id')::uuid;
  v_code := v1 ->> 'participant_code';

  -- 3: lettura restituisce booleans derivati da eventi (tutti false inizialmente).
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(3, 'QV2 read restituisce booleans falsi alla nascita',
    (v_read ->> 'buyer_completed')::boolean = false
      and (v_read ->> 'seller_completed')::boolean = false
      and (v_read ->> 'core_completed')::boolean = false,
    coalesce(v_read::text, 'null'));

  -- 14: una seconda capability riceve un'altra sessione e un altro codice
  -- automatico, e non legge né scrive la sessione della prima.
  v2 := pg_temp.start_qv2('10000000-0000-4000-8000-000000000012');
  begin
    perform pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000012');
    perform pg_temp.registra(14, 'QV2 capability isolata da altre sessioni', false, 'lettura incrociata permessa');
  exception when insufficient_privilege then
    begin
      perform public.beta_validation_qv2_answer(
        v_session, '10000000-0000-4000-8000-000000000012', 'q01', '"18_24"'::jsonb);
      perform pg_temp.registra(14, 'QV2 capability isolata da altre sessioni', false, 'scrittura incrociata permessa');
    exception when insufficient_privilege then
      perform pg_temp.registra(14, 'QV2 capability isolata da altre sessioni',
        (v2 ->> 'session_id') <> v_session::text
          and (v2 ->> 'participant_code') <> v_code
          and (v2 ->> 'resumed')::boolean = false
          and (pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011') -> 'answers' ->> 'q01') is null,
        'seconda=' || coalesce(v2 ->> 'participant_code', 'null') || ' prima=' || v_code);
    end;
  end;

  -- 4: answer condizionale q02 (altro) valido.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q02', '{"choice":"other","other":"Specifica testo test"}'::jsonb
  );
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(4, 'QV2 answer q02 condizionale accettato',
    v_read -> 'answers' ->> 'q02' = 'other'
      and v_read -> 'answers' ->> 'q02_other' = 'Specifica testo test',
    'q02=' || coalesce(v_read -> 'answers' ->> 'q02', 'null'));

  -- 5: answer array q05 valido.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q05', '{"choices":["supermarket","wine_shop"]}'::jsonb
  );
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(5, 'QV2 answer q05 multi valido',
    v_read -> 'answers' -> 'q05' = '["supermarket","wine_shop"]'::jsonb,
    'q05=' || coalesce(v_read -> 'answers' -> 'q05', 'null'::jsonb)::text);

  -- 6: answer q10 con azioni valida.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q10', '{"choice":"yes","actions":["sold","other"],"other":"Altro testo"}'::jsonb
  );
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(6, 'QV2 answer q10 con azioni valido',
    v_read -> 'answers' ->> 'q10' = 'yes'
      and v_read -> 'answers' -> 'q10_actions' = '["sold","other"]'::jsonb
      and v_read -> 'answers' ->> 'q10_other' = 'Altro testo',
    'q10=' || coalesce(v_read -> 'answers' ->> 'q10', 'null'));

  -- Il finish_pre richiede tutti i campi q01-q13, non solo i tre casi
  -- condizionali gia verificati. Risposte minimali ma valide via porta pubblica.
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q01', '"25_34"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q03', '"one_two_month"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q04', '"20_40"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q06', '{"choice":"no"}'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q07', '["authenticity"]'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q08', '"Una risposta tecnica senza dati personali"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q09', '"one_five"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q11', '{"choice":"never"}'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q12', '"six_nine"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q13', '"ten_twelve"'::jsonb);

  -- 7: finish_pre deve salvare il timestamp solo dopo le tredici risposte.
  perform public.beta_validation_qv2_finish_pre(v_session, '10000000-0000-4000-8000-000000000011');
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(7, 'QV2 finish_pre marca pre_finished_at',
    v_read ->> 'pre_finished_at' is not null
      and (v_read -> 'answers' ->> 'q13') = 'ten_twelve',
    'pre_finished_at=' || coalesce(v_read ->> 'pre_finished_at', 'null'));

  -- 8: risposta PRE dopo il finish rifiutata e valore conservato.
  begin
    perform public.beta_validation_qv2_answer(
      v_session, '10000000-0000-4000-8000-000000000011',
      'q01', '"18_24"'::jsonb
    );
    perform pg_temp.registra(8, 'QV2 answer dopo pre rifiutato', false, 'non rifiutato');
  exception when sqlstate '22023' then
    v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(8, 'QV2 answer dopo pre rifiutato',
      (v_read -> 'answers' ->> 'q01') = '25_34',
      'q01=' || coalesce(v_read -> 'answers' ->> 'q01', 'null'));
  end;

  -- Completa le sette risposte POST e poi il percorso core attraverso la porta MV1.
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q14', '"buy"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q15', '{"choice":"yes"}'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q16', '"maybe"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q17', '"Ricerca di bottiglie"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q18', '"Flusso comprensibile"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q19', '["protected_payment"]'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'q20', '"both"'::jsonb);
  -- 9: anche con POST completo, l'assenza del core impedisce il finish.
  begin
    perform public.beta_validation_qv2_finish_post(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(9, 'QV2 finish_post senza core rifiutato', false, 'non rifiutato');
  exception when sqlstate '22023' then
    v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(9, 'QV2 finish_post senza core rifiutato',
      v_read ->> 'post_finished_at' is null
        and not exists(select 1 from private.beta_validation_events
                       where session_id = v_session and event_name = 'validation_completed'),
      '22023; nessun evento validation_completed');
  end;

  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'checkout_beta_completed');
  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'sell_completed');
  -- Dalla 20261008230000 beta_completed QV2 richiede anche AI, Club e Cantina.
  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'ai_preview_viewed');
  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'club_viewed');
  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'cellar_viewed');
  perform public.beta_validation_event_record(v_session, v_code, '10000000-0000-4000-8000-000000000011', 'beta_completed');
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(10, 'QV2 read deriva completamento buyer seller e core',
    (v_read ->> 'buyer_completed')::boolean
      and (v_read ->> 'seller_completed')::boolean
      and (v_read ->> 'core_completed')::boolean,
    'buyer=' || coalesce(v_read ->> 'buyer_completed', 'null')
      || ' seller=' || coalesce(v_read ->> 'seller_completed', 'null')
      || ' core=' || coalesce(v_read ->> 'core_completed', 'null'));

  -- 15: final_feedback è facoltativo: si salva, si può rimuovere con null
  -- (unica risposta che lo ammette) e si salva di nuovo prima della chiusura.
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'final_feedback', '"Primo feedback"'::jsonb);
  perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'final_feedback', 'null'::jsonb);
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  if v_read -> 'answers' ->> 'final_feedback' is not null then
    perform pg_temp.registra(15, 'QV2 final_feedback facoltativo e persistito', false, 'null non rimuove il feedback');
  else
    perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'final_feedback', '"  Feedback finale facoltativo  "'::jsonb);
    v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(15, 'QV2 final_feedback facoltativo e persistito',
      v_read -> 'answers' ->> 'final_feedback' = 'Feedback finale facoltativo'
        and v_read -> 'answers' ->> 'q20' = 'both',
      'final_feedback=' || coalesce(v_read -> 'answers' ->> 'final_feedback', 'null'));
  end if;

  -- Il finish_post deve inserire l'evento ammesso dal CHECK; replay idempotente.
  perform public.beta_validation_qv2_finish_post(v_session, '10000000-0000-4000-8000-000000000011');
  perform public.beta_validation_qv2_finish_post(v_session, '10000000-0000-4000-8000-000000000011');
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(13, 'QV2 finish_post conclude una volta con evento valido',
    v_read ->> 'post_finished_at' is not null
      and v_read ->> 'validation_completed_at' is not null
      and (select count(*) from private.beta_validation_events
           where session_id = v_session and event_name = 'validation_completed') = 1,
    'post_finished_at=' || coalesce(v_read ->> 'post_finished_at', 'null'));

  -- 16: dopo validation_completed nessuna risposta, nemmeno il feedback, cambia.
  begin
    perform public.beta_validation_qv2_answer(v_session, '10000000-0000-4000-8000-000000000011', 'final_feedback', '"Modifica tardiva"'::jsonb);
    perform pg_temp.registra(16, 'QV2 risposte bloccate dopo la chiusura', false, 'modifica permessa');
  exception when sqlstate '22023' then
    v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(16, 'QV2 risposte bloccate dopo la chiusura',
      v_read -> 'answers' ->> 'final_feedback' = 'Feedback finale facoltativo',
      'final_feedback=' || coalesce(v_read -> 'answers' ->> 'final_feedback', 'null'));
  end;
end $$;

-- 11-12: assenza grant diretta e una sola riga per la sessione fixture.
do $$
declare v_n integer;
begin
  -- Nessun SELECT diretto anon sulle righe QV2.
  begin
    set local role anon;
    perform 1 from private.beta_validation_qv2 limit 1;
    reset role;
    perform pg_temp.registra(11, 'QV2 anon non legge tabella diretta', false, 'lettura permessa');
  exception when insufficient_privilege then
    reset role;
    perform pg_temp.registra(11, 'QV2 anon non legge tabella diretta', true, sqlstate);
  end;

  -- Una sola riga QV2 per la capability della fixture, anche dopo resume.
  select count(*) into v_n from private.beta_validation_qv2 q
    join private.beta_validation_sessions s on s.id = q.session_id
    where s.capability_hash = private.beta_validation_capability_hash('10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(12, 'QV2 resume conserva una sola riga della fixture',
    v_n = 1, 'righe=' || v_n::text);
end $$;

select id, descrizione, passed, detail
from esiti_12t
order by id;

rollback;
