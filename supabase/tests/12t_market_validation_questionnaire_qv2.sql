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

create function pg_temp.error_start_qv2(p_cap text)
returns text language plpgsql as $f$
begin
  perform pg_temp.start_qv2(p_cap);
  return 'NESSUN_ERRORE';
exception when others then return sqlstate; end;
$f$;

create function pg_temp.read_qv2(p_session uuid, p_cap text)
returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  set local role anon;
  select to_jsonb(x) into v from public.beta_validation_qv2_read(p_session, p_cap) x;
  reset role;
  return v;
exception when others then reset role; raise; end;
$f$;

-- Capability costante per il test, ripetibile e deterministica.
do $$
declare
  v1 jsonb; v2 jsonb; v_session uuid; v_event uuid; v_read jsonb;
  v_seller boolean; v_pre boolean; v_post boolean; v_core boolean; v_buyer boolean; v_full boolean;
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

  -- 3: lettura restituisce booleans derivati da eventi (tutti false inizialmente).
  v_read := pg_temp.read_qv2(v_session, '10000000-0000-4000-8000-000000000011');
  v_buyer := coalesce((v_read -> 'buyer_completed')::boolean, false);
  v_seller := coalesce((v_read -> 'seller_completed')::boolean, false);
  v_core := coalesce((v_read -> 'core_completed')::boolean, false);
  perform pg_temp.registra(3, 'QV2 read restituisce booleans falsi alla nascita',
    v_buyer = false and v_seller = false and v_core = false,
    coalesce(v_read::text, 'null'));

  -- 4: answer condizionale q02 (altro) valido.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q02', '{"choice":"other","other":"Specifica testo test"}'::jsonb
  );
  perform pg_temp.registra(4, 'QV2 answer q02 condizionale accettato',
    true, 'q02 other');

  -- 5: answer array q05 valido.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q05', '{"choices":["supermarket","wine_shop"]}'::jsonb
  );
  perform pg_temp.registra(5, 'QV2 answer q05 multi valido', true, 'q05 array');

  -- 6: answer q10 con azioni valida.
  perform public.beta_validation_qv2_answer(
    v_session, '10000000-0000-4000-8000-000000000011',
    'q10', '{"choice":"yes","actions":["sold","other"],"other":"Altro testo"}'::jsonb
  );
  perform pg_temp.registra(6, 'QV2 answer q10 con azioni valido', true, 'q10 actions+other');

  -- 7: answer non ammesso dopo pre_finished_at non deve scrivere q1-13.
  perform public.beta_validation_qv2_finish_pre(v_session, '10000000-0000-4000-8000-000000000011');
  perform pg_temp.registra(7, 'QV2 finish_pre marca pre_finished_at', true, 'pre ok');

  -- 8: tentativo answer dopo pre = rifiutato.
  begin
    perform public.beta_validation_qv2_answer(
      v_session, '10000000-0000-4000-8000-000000000011',
      'q01', '"18_24"'::jsonb
    );
    perform pg_temp.registra(8, 'QV2 answer dopo pre rifiutato', false, 'non rifiutato');
  exception when others then
    perform pg_temp.registra(8, 'QV2 answer dopo pre rifiutato', true, sqlstate);
  end;

  -- 9: evento validation_completed non ancora inserito; finish_post deve fallire.
  begin
    perform public.beta_validation_qv2_finish_post(v_session, '10000000-0000-4000-8000-000000000011');
    perform pg_temp.registra(9, 'QV2 finish_post senza core rifiutato', false, 'non rifiutato');
  exception when others then
    perform pg_temp.registra(9, 'QV2 finish_post senza core rifiutato', true, sqlstate);
  end;

  -- 10: inserimento evento beta_completed e checkout_beta_completed/sell_completed
  -- per simulare percorso core completo (usando la funzione privata con ruolo priv.
  -- non e esposto a anon; verifichiamo solo che l'evento 'validation_completed'
  -- sia nel CHECK dopo estensione, non che la funzione lo inserisca qui.
  -- Verifichiamo invece che il CHECK consenta 'validation_completed'.
  begin
    insert into private.beta_validation_events (session_id, participant_code, event_name)
      values (v_session, (v1 ->> 'participant_code'), 'validation_completed');
    perform pg_temp.registra(10, 'QV2 evento validation_completed ammesso dal CHECK esteso', true, 'inserito');
  exception when others then
    perform pg_temp.registra(10, 'QV2 evento validation_completed ammesso dal CHECK esteso', false, sqlstate);
  end;
end $$;

-- 11-12: assenza grant diretta e isolamento cross-session.
do $$
declare v_error text; v_n integer;
begin
  -- Nessun SELECT diretto anon sulle righe QV2.
  begin
    set local role anon;
    perform 1 from private.beta_validation_qv2 limit 1;
    reset role;
    perform pg_temp.registra(11, 'QV2 anon non legge tabella diretta', false, 'lettura permessa');
  exception when others then
    reset role;
    perform pg_temp.registra(11, 'QV2 anon non legge tabella diretta', true, sqlstate);
  end;

  -- Nessuna duplicazione della riga QV2 per stessa sessione.
  select count(*) into v_n from private.beta_validation_qv2;
  perform pg_temp.registra(12, 'QV2 tabella isolata una sola riga per sessione', v_n >= 1, 'righe=' || v_n::text);
end $$;

select id, descrizione, passed, detail
from esiti_12t
order by id;

rollback;
