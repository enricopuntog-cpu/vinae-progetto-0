-- VPM-018-DB-GRID-01 (griglia 12zu): rate limit e capability delle porte anonime
-- che scrivono (GAP-009).
--
-- Le griglie 12r-12w provano il rifiuto delle capability ma nessuna superava mai
-- un limite. Qui ogni porta anonima di scrittura viene portata oltre soglia.
--
-- SOLO stack Supabase locale/effimero. Tutto vive nella transazione e sparisce con
-- ROLLBACK (bucket compresi). Il guard rifiuta utenti Auth reali.
--
-- Casi «LIMITE NOTO»: descrivono il comportamento attuale di un limite documentato
-- in docs/VPM_018_DB_GRID_01.md, non una proprieta' desiderata. Se il limite viene
-- corretto il caso diventa rosso e va aggiornato insieme alla correzione.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email is null or email not like '%.test') then
    raise exception 'Guard 12zu: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zu (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zu (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Esegue una chiamata come `anon` e riporta l'esito senza far cadere la griglia.
-- Un errore annulla il sottoblocco: e' la stessa semantica della transazione di
-- PostgREST, dove un errore annulla anche l'incremento del contatore.
create function pg_temp.anon_esito(p_sql text) returns jsonb language plpgsql as $f$
declare v_stato text; v_msg text; v_detail text;
begin
  begin
    set local role anon;
    execute p_sql;
    reset role;
    return jsonb_build_object('ok', true);
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
    reset role;
    return jsonb_build_object('ok', false, 'stato', v_stato, 'msg', v_msg, 'detail', v_detail);
  end;
end;
$f$;

-- Vero solo per il rifiuto del limitatore: errore PGRST, codice e stato HTTP 429.
create function pg_temp.limitato(p jsonb) returns boolean language sql as $f$
  select coalesce(p ->> 'stato' = 'PGRST'
    and (p ->> 'msg')::jsonb ->> 'code' = 'rate_limit_exceeded'
    and ((p ->> 'detail')::jsonb ->> 'status')::int = 429, false);
$f$;

-- Vero solo per il rifiuto della porta: un permesso negato ha lo stesso SQLSTATE.
create function pg_temp.non_autorizzata(p jsonb) returns boolean language sql as $f$
  select coalesce(p ->> 'stato' = '42501' and p ->> 'msg' = 'Sessione Market Validation non autorizzata.', false);
$f$;

-- Il limitatore conta per finestre di 60 s allineate all'orologio: una prova a cavallo
-- di due finestre ripartirebbe da zero. Si aspetta la finestra nuova se manca poco.
create function pg_temp.lontano_dal_bordo() returns void language plpgsql as $f$
declare v_secondi numeric := extract(epoch from clock_timestamp())::numeric % 60;
begin
  if v_secondi > 40 then perform pg_sleep(60 - v_secondi + 0.2); end if;
end;
$f$;

-- Porta il contatore della finestra corrente a un valore noto: la porta deve usare
-- davvero questo scope e questo soggetto, altrimenti il caso resta rosso.
create function pg_temp.semina(p_scope text, p_cap text, p_conteggio int) returns void language plpgsql as $f$
declare v_inizio timestamptz := to_timestamp(floor(extract(epoch from clock_timestamp()) / 60) * 60);
begin
  insert into private.rate_limit_buckets (scope, subject, window_started_at, window_seconds, request_count, expires_at)
  values (p_scope, 'capability:' || private.beta_validation_capability_hash(p_cap), v_inizio, 60, p_conteggio, v_inizio + interval '120 seconds')
  on conflict (scope, subject, window_started_at) do update set request_count = excluded.request_count;
end;
$f$;

create function pg_temp.qv2(p_cap text) returns uuid language plpgsql as $f$
declare v uuid;
begin
  set local role anon;
  select x.session_id into v from public.beta_validation_qv2_start(p_cap) x;
  reset role;
  return v;
exception when others then reset role; raise;
end;
$f$;

-- 1: elenco chiuso. Una nuova porta anonima di scrittura deve entrare in questa griglia.
do $$
declare v_porte text[]; v_senza text[];
begin
  select array_agg(p.proname::text order by p.proname),
         coalesce(array_agg(p.proname::text order by p.proname)
           filter (where pg_get_functiondef(p.oid) not ilike '%rate_limit_consume%'), '{}')
    into v_porte, v_senza
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v'
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
  perform pg_temp.registra(1, 'elenco chiuso delle porte anonime di scrittura, tutte con limitatore',
    v_porte = array['beta_validation_event_record','beta_validation_qv2_answer','beta_validation_qv2_finish_post',
                    'beta_validation_qv2_finish_pre','beta_validation_qv2_read','beta_validation_qv2_start',
                    'beta_validation_session_start'] and v_senza = '{}',
    'porte=' || v_porte::text || ' senza=' || v_senza::text);
end $$;

-- 2-8: oltre soglia, ogni porta rifiuta con 429 e con il proprio scope e limite.
do $$
declare
  c_cap constant text := '20000000-0000-4000-8000-000000000001';
  c_mv1 constant text := '20000000-0000-4000-8000-000000000002';
  v_sessione uuid; v_mv1 uuid; v_codice text; v jsonb;
begin
  perform pg_temp.lontano_dal_bordo();
  v_sessione := pg_temp.qv2(c_cap);
  select participant_code into v_codice from private.beta_validation_sessions where id = v_sessione;

  perform pg_temp.semina('market-validation-qv2-start', c_cap, 12);
  v := pg_temp.anon_esito(format('select * from public.beta_validation_qv2_start(%L)', c_cap));
  perform pg_temp.registra(2, 'qv2_start oltre 12/min rifiuta con 429', pg_temp.limitato(v), v::text);

  perform pg_temp.semina('market-validation-qv2-read', c_cap, 120);
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, c_cap));
  perform pg_temp.registra(3, 'qv2_read oltre 120/min rifiuta con 429', pg_temp.limitato(v), v::text);

  perform pg_temp.semina('market-validation-qv2-answer', c_cap, 120);
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_answer(%L, %L, %L, %L::jsonb)',
    v_sessione, c_cap, 'q02', '{"choice":"other","other":"testo"}'));
  perform pg_temp.registra(4, 'qv2_answer oltre 120/min rifiuta con 429 e non scrive',
    pg_temp.limitato(v) and (select q.q02 is null from private.beta_validation_qv2 q where q.session_id = v_sessione), v::text);

  perform pg_temp.semina('market-validation-qv2-finish', c_cap, 30);
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_pre(%L, %L)', v_sessione, c_cap));
  perform pg_temp.registra(5, 'qv2_finish_pre oltre 30/min rifiuta con 429',
    pg_temp.limitato(v) and (select q.pre_finished_at is null from private.beta_validation_qv2 q where q.session_id = v_sessione), v::text);

  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_post(%L, %L)', v_sessione, c_cap));
  perform pg_temp.registra(6, 'qv2_finish_post oltre 30/min rifiuta con 429',
    pg_temp.limitato(v) and (select q.post_finished_at is null from private.beta_validation_qv2 q where q.session_id = v_sessione), v::text);

  perform pg_temp.semina('market-validation-event', c_cap, 120);
  v := pg_temp.anon_esito(format('select public.beta_validation_event_record(%L, %L, %L, %L, %L::jsonb)',
    v_sessione, v_codice, c_cap, 'cellar_viewed', '{}'));
  perform pg_temp.registra(7, 'event_record oltre 120/min rifiuta con 429 e non scrive',
    pg_temp.limitato(v) and (select count(*) = 1 from private.beta_validation_events e where e.session_id = v_sessione), v::text);

  perform pg_temp.semina('market-validation-session-start', c_mv1, 12);
  v := pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V777', c_mv1));
  perform pg_temp.registra(8, 'session_start oltre 12/min rifiuta con 429 e non crea sessioni',
    pg_temp.limitato(v) and not exists (
      select 1 from private.beta_validation_sessions s
      where s.capability_hash = private.beta_validation_capability_hash(c_mv1)), v::text);
end $$;

-- 9-10: conteggio reale, senza semina: la soglia e' esattamente quella dichiarata.
do $$
declare
  c_mv1 constant text := '20000000-0000-4000-8000-000000000003';
  c_qv2 constant text := '20000000-0000-4000-8000-000000000004';
  v_sessione uuid; v jsonb; v_ok int := 0; i int;
begin
  perform pg_temp.lontano_dal_bordo();
  for i in 1..12 loop
    v := pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V778', c_mv1));
    if (v ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
  end loop;
  v := pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V778', c_mv1));
  perform pg_temp.registra(9, 'session_start: 12 chiamate passano, la 13a e rifiutata',
    v_ok = 12 and pg_temp.limitato(v), 'ok=' || v_ok || ' ultima=' || v::text);

  perform pg_temp.lontano_dal_bordo();
  v_sessione := pg_temp.qv2(c_qv2);
  v_ok := 0;
  for i in 1..120 loop
    v := pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, c_qv2));
    if (v ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
  end loop;
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, c_qv2));
  perform pg_temp.registra(10, 'qv2_read: 120 chiamate passano, la 121a e rifiutata',
    v_ok = 120 and pg_temp.limitato(v), 'ok=' || v_ok || ' ultima=' || v::text);
end $$;

-- 11-12: isolamento fra capability e nessuna capability in chiaro nei bucket.
do $$
declare
  c_a constant text := '20000000-0000-4000-8000-000000000005';
  c_b constant text := '20000000-0000-4000-8000-000000000006';
  v_a uuid; v_b uuid; v jsonb; v_in_chiaro boolean;
begin
  perform pg_temp.lontano_dal_bordo();
  v_a := pg_temp.qv2(c_a);
  v_b := pg_temp.qv2(c_b);
  perform pg_temp.semina('market-validation-qv2-read', c_a, 120);
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_b, c_b));
  perform pg_temp.registra(11, 'il limite di una capability non blocca le altre', (v ->> 'ok')::boolean, v::text);

  select exists (
    select 1 from private.rate_limit_buckets b
    where b.subject ~* '[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
  ) into v_in_chiaro;
  perform pg_temp.registra(12, 'i bucket conservano solo l''impronta della capability', not v_in_chiaro, v_in_chiaro::text);
end $$;

-- 13-18: capability errata o malformata su ogni porta legata alla sessione.
do $$
declare
  c_cap constant text := '20000000-0000-4000-8000-000000000007';
  c_altra constant text := '20000000-0000-4000-8000-000000000008';
  v_sessione uuid; v_codice text; v jsonb; v_eventi bigint;
begin
  perform pg_temp.lontano_dal_bordo();
  v_sessione := pg_temp.qv2(c_cap);
  select participant_code into v_codice from private.beta_validation_sessions where id = v_sessione;
  select count(*) into v_eventi from private.beta_validation_events where session_id = v_sessione;

  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, c_altra));
  perform pg_temp.registra(13, 'qv2_read con capability errata: rifiuto della porta', pg_temp.non_autorizzata(v), v::text);

  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_answer(%L, %L, %L, %L::jsonb)',
    v_sessione, c_altra, 'q02', '{"choice":"other","other":"intruso"}'));
  perform pg_temp.registra(14, 'qv2_answer con capability errata: rifiuto della porta e nessuna scrittura',
    pg_temp.non_autorizzata(v) and (select q.q02 is null from private.beta_validation_qv2 q where q.session_id = v_sessione), v::text);

  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_pre(%L, %L)', v_sessione, c_altra));
  perform pg_temp.registra(15, 'qv2_finish_pre con capability errata: rifiuto della porta', pg_temp.non_autorizzata(v), v::text);

  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_post(%L, %L)', v_sessione, c_altra));
  perform pg_temp.registra(16, 'qv2_finish_post con capability errata: rifiuto della porta', pg_temp.non_autorizzata(v), v::text);

  v := pg_temp.anon_esito(format('select public.beta_validation_event_record(%L, %L, %L, %L, %L::jsonb)',
    v_sessione, v_codice, c_altra, 'cellar_viewed', '{}'));
  perform pg_temp.registra(17, 'event_record con capability errata: rifiuto della porta e nessun evento',
    pg_temp.non_autorizzata(v) and (select count(*) = v_eventi from private.beta_validation_events where session_id = v_sessione), v::text);

  v := pg_temp.anon_esito(format('select * from public.beta_validation_qv2_start(%L)', 'non-una-capability'));
  perform pg_temp.registra(18, 'capability malformata rifiutata con 22023 su apertura MV1, apertura QV2 e lettura',
    v ->> 'stato' = '22023'
      and pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V780', 'non-una-capability')) ->> 'stato' = '22023'
      and pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, 'non-una-capability')) ->> 'stato' = '22023',
    v::text);
end $$;

-- 19: una capability di sessione MV1 non apre una sessione QV2.
do $$
declare c_mv1 constant text := '20000000-0000-4000-8000-000000000009'; v jsonb;
begin
  perform pg_temp.lontano_dal_bordo();
  v := pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V779', c_mv1));
  v := pg_temp.anon_esito(format('select * from public.beta_validation_qv2_start(%L)', c_mv1));
  perform pg_temp.registra(19, 'capability MV1 rifiutata sulla porta QV2',
    v ->> 'stato' = '42501' and v ->> 'msg' like 'Capability gia associata%', v::text);
end $$;

-- 20: limitatore e dati restano fuori dalla portata dei client.
do $$
declare v_chiuso boolean; v jsonb;
begin
  select not has_function_privilege('anon', 'private.rate_limit_consume(text,text,integer,integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.rate_limit_consume(text,text,integer,integer)', 'EXECUTE')
    and not has_table_privilege('anon', 'private.rate_limit_buckets', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated', 'private.rate_limit_buckets', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'private.beta_validation_sessions', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated', 'private.beta_validation_sessions', 'SELECT,INSERT,UPDATE,DELETE')
    into v_chiuso;
  v := pg_temp.anon_esito('select count(*) from private.beta_validation_sessions');
  perform pg_temp.registra(20, 'limitatore e sessioni chiusi ai client', v_chiuso and v ->> 'stato' = '42501', v::text);
end $$;

-- 21: il tetto globale per IP sui percorsi non RPC resta 120/min.
do $$
declare
  v_inizio timestamptz := to_timestamp(floor(extract(epoch from clock_timestamp()) / 60) * 60);
  v_bloccato boolean := false; v_stato text;
begin
  perform pg_temp.lontano_dal_bordo();
  v_inizio := to_timestamp(floor(extract(epoch from clock_timestamp()) / 60) * 60);
  perform set_config('request.method', 'POST', true);
  perform set_config('request.path', '/prova_12zu', true);
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1"}', true);
  insert into private.rate_limit_buckets (scope, subject, window_started_at, window_seconds, request_count, expires_at)
  values ('postgrest:/prova_12zu', 'ip:203.0.113.7', v_inizio, 60, 120, v_inizio + interval '120 seconds');
  begin
    perform private.vinea_check_request();
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate;
    v_bloccato := v_stato = 'PGRST';
  end;
  perform pg_temp.registra(21, 'tetto globale: oltre 120 POST/min dallo stesso IP rifiuta', v_bloccato, coalesce(v_stato, 'nessun errore'));
end $$;

-- 22-24: LIMITI NOTI (vedi l'intestazione). Stato attuale, non proprieta' desiderate.
do $$
declare
  v_ok int := 0; i int; v jsonb; v_prima int; v_dopo int; v_bloccato boolean := false; v_stato text;
  c_cap constant text := '20000000-0000-4000-8000-00000000000a';
  v_sessione uuid; v_conteggio int;
begin
  perform pg_temp.lontano_dal_bordo();
  -- 22: la capability la sceglie il client: cambiandola il limite per capability riparte.
  select count(*) into v_prima from private.beta_validation_sessions;
  for i in 1..40 loop
    v := pg_temp.anon_esito(format('select * from public.beta_validation_qv2_start(%L)',
      format('30000000-0000-4000-8000-%s', lpad(i::text, 12, '0'))));
    if (v ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
  end loop;
  select count(*) into v_dopo from private.beta_validation_sessions;
  perform pg_temp.registra(22, 'LIMITE NOTO: ruotando la capability il limite per capability non vincola le sessioni',
    v_ok = 40 and v_dopo - v_prima = 40, 'ok=' || v_ok || ' nuove=' || (v_dopo - v_prima));

  -- 23: il tetto globale si fida del primo valore di x-forwarded-for.
  perform set_config('request.method', 'POST', true);
  perform set_config('request.path', '/rpc/prova_12zu', true);
  perform set_config('request.headers', '{"x-forwarded-for":"198.51.100.9"}', true);
  begin
    perform private.vinea_check_request();
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate;
    v_bloccato := true;
  end;
  perform pg_temp.registra(23, 'LIMITE NOTO: il tetto globale conta per il valore di x-forwarded-for ricevuto',
    not v_bloccato, coalesce(v_stato, 'non bloccato'));
  perform set_config('request.method', '', true);
  perform set_config('request.path', '', true);
  perform set_config('request.headers', '', true);

  -- 24: una chiamata che fallisce annulla anche il proprio incremento del contatore.
  v_sessione := pg_temp.qv2(c_cap);
  v := pg_temp.anon_esito(format('select public.beta_validation_qv2_answer(%L, %L, %L, %L::jsonb)',
    v_sessione, c_cap, 'q02', '{"choice":"valore-non-ammesso"}'));
  select coalesce(sum(request_count), 0) into v_conteggio from private.rate_limit_buckets
    where scope = 'market-validation-qv2-answer'
      and subject = 'capability:' || private.beta_validation_capability_hash(c_cap);
  perform pg_temp.registra(24, 'LIMITE NOTO: le risposte rifiutate non consumano il limite della porta',
    not (v ->> 'ok')::boolean and v_conteggio = 0, 'esito=' || v::text || ' contatore=' || v_conteggio);
end $$;

-- 25: un passo sotto la soglia nessuna porta rifiuta: i casi 2-8 provano il limite esatto.
do $$
declare
  c_cap constant text := '20000000-0000-4000-8000-00000000000b';
  c_mv1 constant text := '20000000-0000-4000-8000-00000000000c';
  v_sessione uuid; v_codice text; v_limitate text[] := '{}';
begin
  perform pg_temp.lontano_dal_bordo();
  v_sessione := pg_temp.qv2(c_cap);
  select participant_code into v_codice from private.beta_validation_sessions where id = v_sessione;
  perform pg_temp.semina('market-validation-qv2-start', c_cap, 11);
  if pg_temp.limitato(pg_temp.anon_esito(format('select * from public.beta_validation_qv2_start(%L)', c_cap))) then v_limitate := array_append(v_limitate, 'start'); end if;
  perform pg_temp.semina('market-validation-qv2-read', c_cap, 119);
  if pg_temp.limitato(pg_temp.anon_esito(format('select public.beta_validation_qv2_read(%L, %L)', v_sessione, c_cap))) then v_limitate := array_append(v_limitate, 'read'); end if;
  perform pg_temp.semina('market-validation-qv2-answer', c_cap, 119);
  if pg_temp.limitato(pg_temp.anon_esito(format('select public.beta_validation_qv2_answer(%L, %L, %L, %L::jsonb)', v_sessione, c_cap, 'q02', '{"choice":"other","other":"testo"}'))) then v_limitate := array_append(v_limitate, 'answer'); end if;
  perform pg_temp.semina('market-validation-qv2-finish', c_cap, 29);
  if pg_temp.limitato(pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_pre(%L, %L)', v_sessione, c_cap))) then v_limitate := array_append(v_limitate, 'finish_pre'); end if;
  perform pg_temp.semina('market-validation-qv2-finish', c_cap, 29);
  if pg_temp.limitato(pg_temp.anon_esito(format('select public.beta_validation_qv2_finish_post(%L, %L)', v_sessione, c_cap))) then v_limitate := array_append(v_limitate, 'finish_post'); end if;
  perform pg_temp.semina('market-validation-event', c_cap, 119);
  if pg_temp.limitato(pg_temp.anon_esito(format('select public.beta_validation_event_record(%L, %L, %L, %L, %L::jsonb)', v_sessione, v_codice, c_cap, 'cellar_viewed', '{}'))) then v_limitate := array_append(v_limitate, 'event'); end if;
  perform pg_temp.semina('market-validation-session-start', c_mv1, 11);
  if pg_temp.limitato(pg_temp.anon_esito(format('select * from public.beta_validation_session_start(%L, %L)', 'V781', c_mv1))) then v_limitate := array_append(v_limitate, 'session_start'); end if;
  perform pg_temp.registra(25, 'a soglia meno uno nessuna delle 7 porte rifiuta per limite', v_limitate = '{}', v_limitate::text);
end $$;

-- 26: il tetto globale e' davvero montato sulle richieste PostgREST.
do $$
declare v_montato boolean;
begin
  select exists (
    select 1 from pg_roles r, unnest(r.rolconfig) c
    where r.rolname = 'authenticator' and c = 'pgrst.db_pre_request=private.vinea_check_request'
  ) into v_montato;
  perform pg_temp.registra(26, 'il controllo delle richieste e montato su authenticator', v_montato, coalesce(v_montato::text, 'null'));
end $$;

-- 27: R-RL-01 corretto: la 61a RPC sul percorso reale deve essere rifiutata.
do $$
declare
  v_inizio timestamptz; v_bloccato boolean := false; v_stato text; v_msg text; v_detail text;
begin
  perform pg_temp.lontano_dal_bordo();
  v_inizio := to_timestamp(floor(extract(epoch from clock_timestamp()) / 60) * 60);
  perform set_config('request.method', 'POST', true);
  perform set_config('request.path', '/rpc/prova_12zu_b', true);
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.8"}', true);
  insert into private.rate_limit_buckets (scope, subject, window_started_at, window_seconds, request_count, expires_at)
  values ('postgrest:/rpc/prova_12zu_b', 'ip:203.0.113.8', v_inizio, 60, 60, v_inizio + interval '120 seconds');
  begin
    perform private.vinea_check_request();
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
    v_bloccato := pg_temp.limitato(jsonb_build_object('stato', v_stato, 'msg', v_msg, 'detail', v_detail));
  end;
  perform set_config('request.method', '', true);
  perform set_config('request.path', '', true);
  perform set_config('request.headers', '', true);
  perform pg_temp.registra(27, 'RPC: oltre 60/min rifiuta con rate_limit_exceeded e HTTP 429',
    v_bloccato, coalesce(v_stato, 'non bloccato'));
end $$;

-- Esegue l'hook con i claim e il ruolo della richiesta; il rifiuto annulla il
-- proprio incremento, come la transazione PostgREST. Nessuna nuova porta pubblica.
create function pg_temp.hook_esito(p_path text, p_uid uuid default null,
  p_ip text default '203.0.113.90', p_method text default 'POST')
returns jsonb language plpgsql as $f$
declare v_stato text; v_msg text; v_detail text;
begin
  perform set_config('request.path', p_path, true);
  perform set_config('request.method', p_method, true);
  perform set_config('request.headers', jsonb_build_object('x-forwarded-for', p_ip)::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid,
    'role', case when p_uid is null then 'anon' else 'authenticated' end)::text, true);
  begin
    if p_uid is null then set local role anon; else set local role authenticated; end if;
    perform private.vinea_check_request();
    reset role;
    return jsonb_build_object('ok', true);
  exception when others then
    get stacked diagnostics v_stato = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
    reset role;
    return jsonb_build_object('ok', false, 'stato', v_stato, 'msg', v_msg, 'detail', v_detail);
  end;
end;
$f$;

do $$
declare
  i int; v_ok int := 0; v jsonb; v_ip jsonb; v_unknown jsonb; v_path text; v_tutti boolean := true;
  c_a constant uuid := '220a0000-0000-4000-8000-000000000001';
  c_b constant uuid := '220a0000-0000-4000-8000-000000000002';
begin
  perform pg_temp.lontano_dal_bordo();
  for i in 1..60 loop
    v := pg_temp.hook_esito('/rpc/prova_12zu_60');
    if (v ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
  end loop;
  v := pg_temp.hook_esito('/rpc/prova_12zu_60');
  perform pg_temp.registra(28, 'RPC: 60 passano, 61a e tentativo ripetuto rifiutati, contatore resta 60',
    v_ok = 60 and pg_temp.limitato(v)
      and pg_temp.limitato(pg_temp.hook_esito('/rpc/prova_12zu_60'))
      and (select sum(request_count) = 60 from private.rate_limit_buckets
        where scope = 'postgrest:/rpc/prova_12zu_60' and subject = 'ip:203.0.113.90'),
    'ok=' || v_ok || ' ultima=' || v::text);

  -- Confine del prefisso: nessun match per segmenti simili o RPC annidate.
  foreach v_path in array array['/profiles', '/rpcish/prova', '/x/rpc/prova', ''] loop
    perform pg_temp.lontano_dal_bordo();
    v_ok := 0;
    for i in 1..120 loop
      v := pg_temp.hook_esito(v_path);
      if (v ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
    end loop;
    v_tutti := v_tutti and v_ok = 120 and pg_temp.limitato(pg_temp.hook_esito(v_path));
  end loop;
  perform pg_temp.registra(29, 'non RPC: 120 passano e 121a rifiuta su quattro percorsi, prefisso esatto', v_tutti);

  perform pg_temp.lontano_dal_bordo();
  for i in 1..60 loop
    v := pg_temp.hook_esito('/rpc/prova_12zu_user', c_a);
  end loop;
  v := pg_temp.hook_esito('/rpc/prova_12zu_user', c_a, '203.0.113.91');
  perform pg_temp.registra(30, 'autenticato: il soggetto e user:uid, cambiare IP non rinnova la soglia',
    pg_temp.limitato(v) and (select sum(request_count) = 60 from private.rate_limit_buckets
      where scope = 'postgrest:/rpc/prova_12zu_user' and subject = 'user:' || c_a::text)
      and not exists (select 1 from private.rate_limit_buckets
        where scope = 'postgrest:/rpc/prova_12zu_user' and subject like 'ip:%'), v::text);
  perform pg_temp.registra(31, 'utenti e percorsi conservano bucket distinti',
    (pg_temp.hook_esito('/rpc/prova_12zu_user', c_b) ->> 'ok')::boolean
    and (pg_temp.hook_esito('/rpc/prova_12zu_user_altra', c_a) ->> 'ok')::boolean);

  -- Il modello XFF esistente resta invariato; non attesta il gateway hosted.
  v := pg_temp.hook_esito('/rpc/prova_12zu_60', null, '203.0.113.90, 10.0.0.2');
  v_ip := pg_temp.hook_esito('/rpc/prova_12zu_60', null, '203.0.113.92');
  v_unknown := pg_temp.hook_esito('/rpc/prova_12zu_unknown', null, '');
  perform pg_temp.registra(32, 'anonimo: prima voce XFF, IP distinto e fallback unknown invariati',
    pg_temp.limitato(v)
    and (v_ip ->> 'ok')::boolean and (v_unknown ->> 'ok')::boolean
    and exists (select 1 from private.rate_limit_buckets
      where scope = 'postgrest:/rpc/prova_12zu_unknown' and subject = 'ip:unknown'));

  v_tutti := true;
  foreach v_path in array array['GET', 'HEAD', 'OPTIONS'] loop
    v_tutti := v_tutti and (pg_temp.hook_esito('/rpc/prova_12zu_skip', null, '203.0.113.90', v_path) ->> 'ok')::boolean;
  end loop;
  perform pg_temp.registra(33, 'GET HEAD OPTIONS non consumano bucket', v_tutti
    and not exists (select 1 from private.rate_limit_buckets where scope = 'postgrest:/rpc/prova_12zu_skip'));
end $$;

select id, descrizione, passed, detail from esiti_12zu order by id;

rollback;

-- Transazione separata: riproduce la modalita delle RPC stable chiamate in POST.
begin read only;
select set_config('request.method', 'POST', true) as metodo \gset
select set_config('request.path', '/rpc/prova_12zu_readonly', true) as percorso \gset
select private.vinea_check_request() as controllo \gset
select 34, 'POST in transazione read only: hook non scrive e non genera 25006',
  not exists (select 1 from private.rate_limit_buckets where scope = 'postgrest:/rpc/prova_12zu_readonly'), '';
rollback;
