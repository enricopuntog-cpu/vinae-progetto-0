-- Market Validation / MV1 (griglia 12r).
--
-- SOLO stack Supabase locale/effimero. Tutte le fixture sono private, vivono
-- nella transazione e spariscono con ROLLBACK. Il guard rifiuta utenti Auth
-- reali. La griglia verifica porte anonime, capability, tassonomia/metadata,
-- grant chiusi e assenza di side effect sui quattro domini commerciali.

begin;

\set ON_ERROR_STOP on

DO $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12r: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12r (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12r (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

create function pg_temp.start_session(p_code text, p_cap text)
returns jsonb
language plpgsql
as $f$
declare v jsonb;
begin
  set local role anon;
  select to_jsonb(x) into v
  from public.beta_validation_session_start(p_code, p_cap) x;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$f$;

create function pg_temp.record_event(
  p_session uuid,
  p_code text,
  p_cap text,
  p_event text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
as $f$
declare v uuid;
begin
  set local role anon;
  select public.beta_validation_event_record(
    p_session, p_code, p_cap, p_event, p_metadata
  ) into v;
  reset role;
  return v;
exception when others then
  reset role;
  raise;
end;
$f$;

create function pg_temp.error_start(p_code text, p_cap text)
returns text
language plpgsql
as $f$
begin
  perform pg_temp.start_session(p_code, p_cap);
  return 'NESSUN_ERRORE';
exception when others then
  return sqlstate;
end;
$f$;

create function pg_temp.error_event(
  p_session uuid,
  p_code text,
  p_cap text,
  p_event text,
  p_metadata jsonb default '{}'::jsonb
) returns text
language plpgsql
as $f$
begin
  perform pg_temp.record_event(p_session, p_code, p_cap, p_event, p_metadata);
  return 'NESSUN_ERRORE';
exception when others then
  return sqlstate;
end;
$f$;

create function pg_temp.direct_table_error(p_operation text)
returns text
language plpgsql
as $f$
begin
  set local role anon;
  if p_operation = 'select' then
    perform 1 from private.beta_validation_sessions limit 1;
  elsif p_operation = 'insert' then
    insert into private.beta_validation_events (
      session_id, participant_code, event_name
    ) values (
      '00000000-0000-4000-8000-000000000001', 'V001', 'marketplace_viewed'
    );
  elsif p_operation = 'update' then
    update private.beta_validation_events set event_name = 'club_viewed';
  elsif p_operation = 'delete' then
    delete from private.beta_validation_events;
  else
    raise exception 'Operazione test sconosciuta.';
  end if;
  reset role;
  return 'NESSUN_ERRORE';
exception when others then
  reset role;
  return sqlstate;
end;
$f$;

-- Snapshot prima di qualunque fixture MV: questi conteggi devono restare uguali.
create temp table commercial_before on commit drop as
select
  (select count(*) from public.orders) as orders_count,
  (select count(*) from public.listings) as listings_count,
  (select count(*) from public.bottle_units) as inventory_count,
  (select count(*) from public.payments) as payments_count;

-- Capability UUID costanti, distinte e ripetibili. Sono letterali SQL dentro i
-- DO block: psql non espande variabili dentro un corpo dollar-quoted.

-- 1-5: estremi, canonicalizzazione e rifiuti.
do $$
declare v jsonb; v_error text;
begin
  v := pg_temp.start_session('V001', '10000000-0000-4000-8000-000000000001');
  perform pg_temp.registra(1, 'V001 apre una sessione anonima valida',
    v ->> 'participant_code' = 'V001' and (v ->> 'resumed')::boolean = false,
    coalesce(v::text, 'null'));

  v := pg_temp.start_session('V999', '10000000-0000-4000-8000-000000000002');
  perform pg_temp.registra(2, 'V999 apre una sessione anonima valida',
    v ->> 'participant_code' = 'V999', coalesce(v::text, 'null'));

  v_error := pg_temp.error_start('V000', '10000000-0000-4000-8000-000000000004');
  perform pg_temp.registra(3, 'V000 e negato', v_error = '22023', v_error);
  v_error := pg_temp.error_start('V1000', '10000000-0000-4000-8000-000000000004');
  perform pg_temp.registra(4, 'V1000 e negato', v_error = '22023', v_error);

  v := pg_temp.start_session(' v017 ', '10000000-0000-4000-8000-000000000003');
  perform pg_temp.registra(5, 'lowercase e spazi vengono canonicalizzati in V017',
    v ->> 'participant_code' = 'V017', coalesce(v::text, 'null'));
end $$;

-- 6-8: resume deterministico, una sola beta_started, capability non trasferibile.
do $$
declare v1 jsonb; v2 jsonb; v_n integer; v_error text;
begin
  v1 := pg_temp.start_session('V001', '10000000-0000-4000-8000-000000000001');
  v2 := pg_temp.start_session('V001', '10000000-0000-4000-8000-000000000001');
  perform pg_temp.registra(6, 'la sessione incompleta recente viene ripresa',
    v1 ->> 'session_id' = v2 ->> 'session_id'
      and (v2 ->> 'resumed')::boolean,
    'prima=' || (v1 ->> 'session_id') || ' seconda=' || (v2 ->> 'session_id'));

  select count(*) into v_n
  from private.beta_validation_events
  where session_id = (v1 ->> 'session_id')::uuid and event_name = 'beta_started';
  perform pg_temp.registra(7, 'il resume non duplica beta_started',
    v_n = 1, 'eventi=' || v_n::text);

  v_error := pg_temp.error_start('V002', '10000000-0000-4000-8000-000000000001');
  perform pg_temp.registra(8, 'la capability non puo cambiare participant_code',
    v_error = '42501', v_error);
end $$;

-- 9-17: append, isolamento cross-session, allowlist e metadata.
do $$
declare
  v jsonb; v_session uuid; v_b jsonb; v_b_session uuid;
  v_event uuid; v_n integer; v_code text; v_error text;
begin
  v := pg_temp.start_session('V017', '10000000-0000-4000-8000-000000000003');
  v_session := (v ->> 'session_id')::uuid;
  v_b := pg_temp.start_session('V018', '10000000-0000-4000-8000-000000000005');
  v_b_session := (v_b ->> 'session_id')::uuid;

  v_event := pg_temp.record_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000003',
    'demo_listing_viewed',
    '{"demo_listing_id":"mv_demo_brunello_2017","price_cents":7200,"price_band":"60–100"}'::jsonb
  );
  select count(*), min(participant_code) into v_n, v_code
  from private.beta_validation_events where id = v_event;
  perform pg_temp.registra(9, 'un evento allowlisted con metadata validi viene appeso',
    v_n = 1 and v_code = 'V017', 'righe=' || v_n::text || ' code=' || coalesce(v_code, 'null'));

  v_error := pg_temp.error_event(
    v_session, 'V018', '10000000-0000-4000-8000-000000000003', 'marketplace_viewed');
  perform pg_temp.registra(10, 'participant mismatch e negato', v_error = '42501', v_error);

  v_error := pg_temp.error_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000004', 'marketplace_viewed');
  perform pg_temp.registra(11, 'una capability diversa non raggiunge la sessione',
    v_error = '42501', v_error);

  v_error := pg_temp.error_event(
    v_b_session, 'V018', '10000000-0000-4000-8000-000000000003', 'marketplace_viewed');
  select count(*) into v_n from private.beta_validation_events
  where session_id = v_b_session and event_name = 'marketplace_viewed';
  perform pg_temp.registra(12, 'la capability della sessione A non registra eventi sulla sessione B',
    v_error = '42501' and v_n = 0, v_error || ' eventi_b=' || v_n::text);

  v_error := pg_temp.error_event(
    v_b_session, 'V018', '10000000-0000-4000-8000-000000000003', 'beta_completed');
  select count(*) into v_n from private.beta_validation_events
  where session_id = v_b_session and event_name = 'beta_completed';
  perform pg_temp.registra(13, 'la capability della sessione A non completa la sessione B',
    v_error = '42501' and v_n = 0, v_error || ' completion_b=' || v_n::text);

  v_error := pg_temp.error_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000003', 'order_created');
  perform pg_temp.registra(14, 'event_name arbitrario e negato', v_error = '22023', v_error);

  v_error := pg_temp.error_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000003', 'beta_started');
  perform pg_temp.registra(15, 'beta_started non e scrivibile dal client',
    v_error = '22023', v_error);

  v_error := pg_temp.error_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000003',
    'marketplace_viewed', '{"email":"persona@example.test"}'::jsonb);
  perform pg_temp.registra(16, 'chiavi metadata PII-like sono negate',
    v_error = '22023', v_error);

  v_error := pg_temp.error_event(
    v_session, 'V017', '10000000-0000-4000-8000-000000000003',
    'demo_listing_viewed', '{"demo_listing_id":"listing-reale"}'::jsonb);
  perform pg_temp.registra(17, 'un id demo deve avere namespace mv_demo_',
    v_error = '22023', v_error);
end $$;

-- 18-21: evento shipping senza valore DB, completion atomica e nuova sessione.
do $$
declare v jsonb; v_session uuid; v_new jsonb; v_completed timestamptz; v_n integer; v_error text;
begin
  v := pg_temp.start_session('V999', '10000000-0000-4000-8000-000000000002');
  v_session := (v ->> 'session_id')::uuid;

  perform pg_temp.record_event(
    v_session, 'V999', '10000000-0000-4000-8000-000000000002',
    'shipping_cost_viewed', '{}'::jsonb
  );
  select count(*) into v_n from private.beta_validation_events
  where session_id = v_session and event_name = 'shipping_cost_viewed';
  perform pg_temp.registra(18, 'shipping_cost_viewed e un evento MV isolato',
    v_n = 1, 'eventi=' || v_n::text);

  v_error := pg_temp.error_event(
    v_session, 'V999', '10000000-0000-4000-8000-000000000002',
    'shipping_cost_viewed', '{"shipping_fee_cents":1290}'::jsonb);
  perform pg_temp.registra(19, 'il costo shipping non viene duplicato nei metadata DB',
    v_error = '22023', v_error);

  perform pg_temp.record_event(
    v_session, 'V999', '10000000-0000-4000-8000-000000000002', 'beta_completed');
  select completed_at into v_completed
  from private.beta_validation_sessions where id = v_session;
  select count(*) into v_n from private.beta_validation_events
  where session_id = v_session and event_name = 'beta_completed';
  perform pg_temp.registra(20, 'beta_completed appende e conclude atomicamente',
    v_completed is not null and v_n = 1,
    'completed=' || coalesce(v_completed::text, 'null') || ' eventi=' || v_n::text);

  v_new := pg_temp.start_session('V999', '10000000-0000-4000-8000-000000000002');
  perform pg_temp.registra(21, 'lo stesso codice puo aprire una sessione nuova dopo completion',
    v_new ->> 'session_id' <> v_session::text
      and (v_new ->> 'resumed')::boolean = false,
    'prima=' || v_session::text || ' nuova=' || (v_new ->> 'session_id'));
end $$;

-- 22-25: grant/RLS con tentativi effettivi dal ruolo anon.
do $$
declare
  v_start boolean; v_event boolean; v_insert text; v_update text; v_delete text; v_select text;
begin
  select has_function_privilege('anon',
    'public.beta_validation_session_start(text,text)', 'EXECUTE') into v_start;
  select has_function_privilege('anon',
    'public.beta_validation_event_record(uuid,text,text,text,jsonb)', 'EXECUTE') into v_event;
  perform pg_temp.registra(22, 'anon esegue soltanto le due porte MV',
    v_start and v_event, 'start=' || v_start::text || ' event=' || v_event::text);

  v_insert := pg_temp.direct_table_error('insert');
  perform pg_temp.registra(23, 'INSERT diretto anon e negato',
    v_insert = '42501', v_insert);

  v_update := pg_temp.direct_table_error('update');
  v_delete := pg_temp.direct_table_error('delete');
  perform pg_temp.registra(24, 'UPDATE e DELETE diretti anon sono negati',
    v_update = '42501' and v_delete = '42501',
    'update=' || v_update || ' delete=' || v_delete);

  v_select := pg_temp.direct_table_error('select');
  perform pg_temp.registra(25, 'anon non legge righe o analytics MV',
    v_select = '42501', v_select);
end $$;

-- 26-29: nessun effetto commerciale.
do $$
declare b commercial_before%rowtype; v integer;
begin
  select * into b from commercial_before;
  select count(*) into v from public.orders;
  perform pg_temp.registra(26, 'MV non crea o modifica ordini',
    v = b.orders_count, 'prima=' || b.orders_count::text || ' dopo=' || v::text);
  select count(*) into v from public.listings;
  perform pg_temp.registra(27, 'MV non crea o modifica annunci',
    v = b.listings_count, 'prima=' || b.listings_count::text || ' dopo=' || v::text);
  select count(*) into v from public.bottle_units;
  perform pg_temp.registra(28, 'MV non crea o modifica inventario',
    v = b.inventory_count, 'prima=' || b.inventory_count::text || ' dopo=' || v::text);
  select count(*) into v from public.payments;
  perform pg_temp.registra(29, 'MV non crea o modifica pagamenti',
    v = b.payments_count, 'prima=' || b.payments_count::text || ' dopo=' || v::text);
end $$;

-- 30-33: forma dello schema, coerenza privilegiata e append-only.
do $$
declare v_fk integer; v_unique integer; v_error text; v_helpers boolean;
begin
  select count(*) into v_fk
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'private' and t.relname = 'beta_validation_events'
    and c.conname = 'beta_validation_events_session_participant_fk';
  perform pg_temp.registra(30, 'events lega sessione e participant_code con FK composita',
    v_fk = 1, 'fk=' || v_fk::text);

  select count(*) into v_unique
  from pg_indexes
  where schemaname = 'private'
    and tablename = 'beta_validation_sessions'
    and indexdef ilike 'create unique index%'
    and indexdef ilike '%(participant_code)%';
  perform pg_temp.registra(31, 'participant_code non e globalmente unique',
    v_unique = 0, 'unique_code=' || v_unique::text);

  begin
    insert into private.beta_validation_events (
      session_id, participant_code, event_name
    ) values (
      (
        select id from private.beta_validation_sessions
        where participant_code = 'V001' limit 1
      ),
      'V998',
      'marketplace_viewed'
    );
    v_error := 'NESSUN_ERRORE';
  exception when others then
    v_error := sqlstate;
  end;
  perform pg_temp.registra(32, 'anche uno scrittore privilegiato non puo disallineare il codice',
    v_error = '23503', v_error);

  select
    not has_function_privilege('anon',
      'private.beta_validation_capability_hash(text)', 'EXECUTE')
    and not has_function_privilege('authenticated',
      'private.beta_validation_capability_hash(text)', 'EXECUTE')
    and not has_function_privilege('anon',
      'private.beta_validation_metadata_valida(text,jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated',
      'private.beta_validation_metadata_valida(text,jsonb)', 'EXECUTE')
    into v_helpers;
  perform pg_temp.registra(33, 'le helper private non sono eseguibili dai client',
    v_helpers, 'anon/auth chiuse=' || v_helpers::text);
end $$;

select id, descrizione, passed, detail
from esiti_12r
order by id;

rollback;
