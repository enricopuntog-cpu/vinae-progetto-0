-- Vinea Partner — Blocco A: inviti, identita aziendale, stati (griglia 12x).
--
-- SOLO stack Supabase locale/effimero. Utenti Auth `.test` e ogni riga Partner
-- vivono nella transazione e spariscono con ROLLBACK. Prova la migrazione
-- 20261011150000: inviti monouso legati all'email (validi, scaduti, revocati,
-- usati, replay), compilazione e consegna dei dati, esiti amministrativi
-- (approva, restituisci, sospendi, riattiva, revoca), anti-autoapprovazione,
-- marcatore dedicato legato alla riga, scritture dirette rifiutate anche a un
-- writer privilegiato, audit append-only, gate sul checkout, superficie
-- pubblica chiusa, privilegi e invarianza di ruoli e configurazione economica.
--
-- La 12l e la griglia dei metadati logistici: questa e la 12x.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12x: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12x (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12x (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

-- Esegue p_sql con il ruolo e i claim di PostgREST. esito = SQLSTATE o
-- NESSUN_ERRORE; hint = HINT dell'eccezione; dati = risultato jsonb.
create function pg_temp.chiama(
  p_sql text,
  p_uid uuid,
  p_ruolo text default 'authenticated',
  out esito text,
  out hint text,
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
    hint := '';
  exception when others then
    get stacked diagnostics hint = pg_exception_hint;
    esito := sqlstate;
    dati := null;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
end;
$f$;

-- Scrittura privilegiata diretta (postgres, cioe piu di service_role).
create function pg_temp.diretto(p_sql text, out esito text) returns text language plpgsql as $f$
begin
  execute p_sql;
  esito := 'NESSUN_ERRORE';
exception when others then
  esito := sqlstate;
end;
$f$;

\set a1 '12ee0000-0000-4000-8000-000000000001'
\set a2 '12ee0000-0000-4000-8000-000000000002'
\set u1 '12ee0000-0000-4000-8000-000000000011'
\set u2 '12ee0000-0000-4000-8000-000000000012'
\set u3 '12ee0000-0000-4000-8000-000000000013'
\set u4 '12ee0000-0000-4000-8000-000000000014'
\set u5 '12ee0000-0000-4000-8000-000000000015'
\set u6 '12ee0000-0000-4000-8000-000000000016'

-- a1, a2: admin. u1: Partner principale. u2: estraneo. u3: email non
-- confermata. u4: venditore privato. u5: rimosso. u6: seconda partita IVA.
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12x.test', now(), '{}'::jsonb),
  (:'a2', 'a2@grid-12x.test', now(), '{}'::jsonb),
  (:'u1', 'u1@grid-12x.test', now(), '{}'::jsonb),
  (:'u2', 'u2@grid-12x.test', now(), '{}'::jsonb),
  (:'u3', 'u3@grid-12x.test', null, '{}'::jsonb),
  (:'u4', 'u4@grid-12x.test', now(), '{}'::jsonb),
  (:'u5', 'u5@grid-12x.test', now(), '{}'::jsonb),
  (:'u6', 'u6@grid-12x.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12x', date '1980-01-01'),
  (:'a2', 'a2-12x', date '1980-01-01'),
  (:'u1', 'u1-12x', date '1980-01-01'),
  (:'u2', 'u2-12x', date '1980-01-01'),
  (:'u3', 'u3-12x', date '1980-01-01'),
  (:'u4', 'u4-12x', date '1980-01-01'),
  (:'u5', 'u5-12x', date '1980-01-01'),
  (:'u6', 'u6-12x', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'a2', 'admin'),
  (:'u1', 'user'), (:'u2', 'user'), (:'u3', 'user'),
  (:'u4', 'user'), (:'u5', 'user'), (:'u6', 'user');
update public.profiles set stato_utente = 'rimosso' where id = :'u5';
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-000000000001';
  c_a2 constant uuid := '12ee0000-0000-4000-8000-000000000002';
  c_u1 constant uuid := '12ee0000-0000-4000-8000-000000000011';
  c_u2 constant uuid := '12ee0000-0000-4000-8000-000000000012';
  c_u3 constant uuid := '12ee0000-0000-4000-8000-000000000013';
  c_u4 constant uuid := '12ee0000-0000-4000-8000-000000000014';
  c_u5 constant uuid := '12ee0000-0000-4000-8000-000000000015';
  c_u6 constant uuid := '12ee0000-0000-4000-8000-000000000016';
  c_piva1 constant text := '12345678903';
  c_piva2 constant text := '01234567897';
  v_ruoli_prima integer;
  v_c record;
  v_inv1 jsonb; v_tok1 text; v_id1 uuid;
  v_inv text; v_tok text; v_idinv uuid;
  v_p1 uuid; v_pa2 uuid; v_p6 uuid;
  v_tok_scad text; v_tok_rev text; v_id_rev uuid;
  v_tok_u3 text; v_tok_u5 text; v_tok_a2 text; v_tok_u6 text;
  v_dati jsonb;
  v_n integer;
  v_s text;
  c_dati_u1 constant text :=
    'select public.partner_dati_aggiorna(''Enoteca Dodici Srl'', ''Enoteca 12x'', %L, ''info@enoteca-12x.test'', ''enoteca'', ''Via Roma 1'', ''12051'', ''Alba'', ''cn'')';
begin
  select count(*) into v_ruoli_prima from public.user_roles;

  -- 01: privilegi. Porte solo ad authenticated; tabelle private senza grant.
  perform pg_temp.registra(1, 'porte partner_* eseguibili solo da authenticated; tabelle private chiuse',
    (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     and not has_function_privilege('anon', p.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
                     and p.prosecdef and p.proconfig = array['search_path=""'])
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'partner\_%')
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'partner\_%') = 12
    and not has_table_privilege('authenticated', 'private.partners', 'SELECT')
    and not has_table_privilege('authenticated', 'private.partner_inviti', 'SELECT')
    and not has_table_privilege('anon', 'private.partner_eventi', 'SELECT')
    and not has_function_privilege('authenticated', 'private.partner_admin_richiesto()', 'EXECUTE')
    and (select bool_and(c.relrowsecurity) from pg_class c
         where c.oid in ('private.partners'::regclass, 'private.partner_inviti'::regclass,
                         'private.partner_eventi'::regclass)));

  -- 02: anon e non-admin non creano inviti.
  select * into v_c from pg_temp.chiama(
    'select public.partner_admin_invito_crea(''u1@grid-12x.test'')', null, 'anon');
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    'select public.partner_admin_invito_crea(''u1@grid-12x.test'')', c_u2);
  perform pg_temp.registra(2, 'anon e utente non admin non creano inviti (42501)',
    v_s = '42501' and v_c.esito = '42501', v_s || '/' || v_c.esito);

  -- 03: admin crea l'invito per u1; token di 64 esadecimali.
  select * into v_c from pg_temp.chiama(
    'select public.partner_admin_invito_crea(''  U1@Grid-12x.TEST '', 14, ''Enoteca di prova'')', c_a1);
  v_inv1 := v_c.dati; v_tok1 := v_inv1 ->> 'token'; v_id1 := (v_inv1 ->> 'invito_id')::uuid;
  perform pg_temp.registra(3, 'admin crea invito: email normalizzata, token 64 hex, scadenza 14 giorni',
    v_c.esito = 'NESSUN_ERRORE' and v_tok1 ~ '^[0-9a-f]{64}$'
      and v_inv1 ->> 'email' = 'u1@grid-12x.test'
      and (v_inv1 ->> 'scade_at')::timestamptz between now() + interval '13 days 23 hours' and now() + interval '14 days 1 hour',
    coalesce(v_c.esito, '') || ' ' || coalesce(v_inv1::text, ''));

  -- 04: il token in chiaro non e memorizzato; c'e solo il suo sha256.
  perform pg_temp.registra(4, 'token non memorizzato in chiaro, solo sha256',
    not exists (select 1 from private.partner_inviti i where i.token_hash = v_tok1)
      and exists (select 1 from private.partner_inviti i
                  where i.id = v_id1 and i.token_hash = encode(sha256(convert_to(v_tok1, 'UTF8')), 'hex')));

  -- 05: secondo invito valido per la stessa email rifiutato.
  select * into v_c from pg_temp.chiama(
    'select public.partner_admin_invito_crea(''u1@grid-12x.test'')', c_a2);
  perform pg_temp.registra(5, 'secondo invito valido per la stessa email rifiutato',
    v_c.esito = 'P0001' and v_c.hint = 'invito_gia_valido', v_c.esito || ' ' || v_c.hint);

  -- 06: un admin non invita la propria email; validita fuori intervallo; email malformata.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''a1@grid-12x.test'')', c_a1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''x@grid-12x.test'', 31)', c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''x@grid-12x.test'', 0)', c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''non-una-email'')', c_a1);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(6, 'auto-invito 42501; validita 31 e 0 e email malformata 22023',
    v_s = '42501/22023/22023/22023', v_s);

  -- 07: scritture dirette privilegiate senza porta rifiutate dal trigger.
  v_s := pg_temp.diretto(format(
    'insert into private.partner_inviti (email, token_hash, creato_da, scade_at) values (%L, %L, %L, now() + interval ''1 day'')',
    'z@grid-12x.test', repeat('a', 64), c_a1));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'update private.partner_inviti set revocato_at = now(), revocato_da = %L where id = %L', c_a1, v_id1));
  v_s := v_s || '/' || pg_temp.diretto(format('delete from private.partner_inviti where id = %L', v_id1));
  v_s := v_s || '/' || pg_temp.diretto('truncate private.partner_inviti cascade');
  perform pg_temp.registra(7, 'insert, revoca, delete e truncate diretti degli inviti rifiutati (42501)',
    v_s = '42501/42501/42501/42501', v_s);

  -- 08: lettura diretta delle tabelle private negata ad authenticated.
  select * into v_c from pg_temp.chiama('select to_jsonb(count(*)) from private.partner_inviti', c_a1);
  perform pg_temp.registra(8, 'authenticated (anche admin) non legge le tabelle private',
    v_c.esito = '42501', v_c.esito);

  -- 09: token malformato o sconosciuto.
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invito_accetta(''abc''))', c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_invito_accetta(%L))', repeat('b', 64)), c_u1);
  perform pg_temp.registra(9, 'token malformato o sconosciuto: invito_non_valido',
    v_s = 'P0001:invito_non_valido' and v_c.esito = 'P0001' and v_c.hint = 'invito_non_valido',
    v_s || ' ' || v_c.esito || ':' || v_c.hint);

  -- 10: un altro account non usa l'invito di u1.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok1), c_u2);
  perform pg_temp.registra(10, 'invito di u1 rifiutato a u2: invito_email_diversa',
    v_c.esito = '42501' and v_c.hint = 'invito_email_diversa', v_c.esito || ':' || v_c.hint);

  -- 11: email non confermata.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u3@grid-12x.test'')', c_a1);
  v_tok_u3 := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_u3), c_u3);
  perform pg_temp.registra(11, 'email non confermata: email_non_confermata',
    v_c.esito = '42501' and v_c.hint = 'email_non_confermata', v_c.esito || ':' || v_c.hint);

  -- 12: account rimosso.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u5@grid-12x.test'')', c_a1);
  v_tok_u5 := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_u5), c_u5);
  perform pg_temp.registra(12, 'account rimosso non accetta inviti (42501)', v_c.esito = '42501', v_c.esito);

  -- 13: u1 accetta. Il marcatore e azzerato all'uscita della porta.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_invito_accetta(upper(%L)))', v_tok1), c_u1);
  v_p1 := (v_c.dati #>> '{}')::uuid;
  perform pg_temp.registra(13, 'u1 accetta: Partner invitato, invito usato, marcatore azzerato',
    v_c.esito = 'NESSUN_ERRORE'
      and (select p.stato = 'invitato' and p.titolare_id = c_u1 and p.invito_id = v_id1
           from private.partners p where p.id = v_p1)
      and (select i.usato_at is not null and i.usato_da = c_u1 and i.partner_id = v_p1
           from private.partner_inviti i where i.id = v_id1)
      and coalesce(current_setting('vinea.partner_porta', true), '') = '',
    v_c.esito);

  -- 14: replay dello stesso destinatario: stesso Partner, nessuna nuova riga.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok1), c_u1);
  perform pg_temp.registra(14, 'replay di u1: stesso Partner, nessuna riga nuova',
    v_c.esito = 'NESSUN_ERRORE' and (v_c.dati #>> '{}')::uuid = v_p1
      and (select count(*) from private.partners where titolare_id = c_u1) = 1,
    v_c.esito);

  -- 15: invito usato non riusabile da un altro.
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok1), c_u2);
  perform pg_temp.registra(15, 'invito usato rifiutato a un altro account (invito_email_diversa o invito_usato)',
    v_c.esito in ('P0001', '42501') and v_c.hint in ('invito_usato', 'invito_email_diversa'),
    v_c.esito || ':' || v_c.hint);

  -- 16: nuovo invito per u1 mentre il Partner e aperto: rifiutato.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u1@grid-12x.test'')', c_a1);
  perform pg_temp.registra(16, 'nuovo invito per un titolare con Partner aperto: partner_gia_presente',
    v_c.esito = 'P0001' and v_c.hint = 'partner_gia_presente', v_c.esito || ':' || v_c.hint);

  -- 17: invito scaduto. La scadenza si simula spostando indietro le due date
  -- con i trigger disattivati: e l'unico modo, perche il guardiano vieta di
  -- riscriverle e il CHECK vieta di nascere gia scaduti.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u2@grid-12x.test'', 1)', c_a1);
  v_tok_scad := v_c.dati ->> 'token';
  set local session_replication_role = replica;
  update private.partner_inviti
  set created_at = now() - interval '3 days', scade_at = now() - interval '2 days'
  where id = (v_c.dati ->> 'invito_id')::uuid;
  set local session_replication_role = origin;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_scad), c_u2);
  perform pg_temp.registra(17, 'invito scaduto: invito_scaduto, nessun Partner',
    v_c.esito = 'P0001' and v_c.hint = 'invito_scaduto'
      and not exists (select 1 from private.partners where titolare_id = c_u2),
    v_c.esito || ':' || v_c.hint);

  -- 18: revoca. Dopo la scadenza si puo invitare di nuovo la stessa email.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u2@grid-12x.test'')', c_a1);
  v_tok_rev := v_c.dati ->> 'token'; v_id_rev := (v_c.dati ->> 'invito_id')::uuid;
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_invito_revoca(%L))', v_id_rev), c_u2);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_invito_revoca(%L, ''errore di indirizzo''))', v_id_rev), c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_invito_revoca(%L))', v_id_rev), c_a2);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_rev), c_u2);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_invito_revoca(%L))', v_id1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(18, 'reinvito dopo scadenza; revoca solo admin, idempotente; invito revocato o usato non si riapre',
    v_s = 'NESSUN_ERRORE/42501/NESSUN_ERRORE/NESSUN_ERRORE:revocato/P0001:invito_revocato/P0001:invito_usato', v_s);

  -- 19: dati non validi rifiutati; consegna incompleta rifiutata.
  select * into v_c from pg_temp.chiama(format(c_dati_u1, '12345678901'), c_u1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    'select public.partner_dati_aggiorna(''Enoteca Dodici Srl'', null, null, null, null, null, ''123'', null, null)', c_u1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    'select public.partner_dati_aggiorna(''Enoteca Dodici Srl'', ''Enoteca 12x'', null, null, null, null, null, null, null)', c_u1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(19, 'P.IVA e CAP non validi 22023; salvataggio parziale ammesso; consegna incompleta dati_incompleti',
    v_s = '22023/22023/NESSUN_ERRORE/22023:dati_incompleti', v_s);

  -- 20: dati completi (P.IVA con prefisso IT e spazi, provincia minuscola).
  select * into v_c from pg_temp.chiama(format(c_dati_u1, 'IT 1234567 8903'), c_u1);
  v_dati := v_c.dati;
  perform pg_temp.registra(20, 'dati validi normalizzati: P.IVA senza IT, provincia maiuscola, paese IT',
    v_c.esito = 'NESSUN_ERRORE' and v_dati ->> 'partita_iva' = c_piva1
      and v_dati ->> 'sede_provincia' = 'CN' and v_dati ->> 'paese' = 'IT'
      and v_dati ->> 'stato' = 'invitato',
    v_c.esito || ' ' || coalesce(v_dati::text, ''));

  -- 21: consegna, replay, dati congelati, partner_me.
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_u1);
  v_s := v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(format(c_dati_u1, c_piva1), c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_u1);
  perform pg_temp.registra(21, 'consegna in_verifica, replay, dati congelati, partner_me coerente',
    v_s = 'NESSUN_ERRORE:in_verifica/NESSUN_ERRORE:in_verifica/P0001:dati_congelati'
      and v_c.dati ->> 'stato' = 'in_verifica' and v_c.dati ->> 'inviato_verifica_at' is not null,
    v_s);

  -- 22: il titolare non si approva: niente porta admin, niente scrittura diretta.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_p1), c_u1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('update private.partners set stato = ''attivo'' where id = %L returning to_jsonb(stato)', v_p1), c_u1);
  perform pg_temp.registra(22, 'il titolare non si approva ne via porta admin ne via UPDATE (42501)',
    v_s = '42501' and v_c.esito = '42501', v_s || '/' || v_c.esito);

  -- 23: writer privilegiato senza marcatore, con marcatore di un'altra riga,
  -- con marcatore da titolare e con il marcatore delle qualifiche personali.
  v_s := pg_temp.diretto(format('update private.partners set stato = ''attivo'' where id = %L', v_p1));
  perform set_config('vinea.partner_porta', 'admin:partner:' || gen_random_uuid()::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set stato = ''attivo'' where id = %L', v_p1));
  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_p1::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set stato = ''attivo'' where id = %L', v_p1));
  perform set_config('vinea.partner_porta', '', true);
  perform set_config('vinea.pq_review', 'on', true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set stato = ''attivo'' where id = %L', v_p1));
  perform set_config('vinea.pq_review', 'off', true);
  v_s := v_s || '/' || pg_temp.diretto(format('delete from private.partners where id = %L', v_p1));
  perform pg_temp.registra(23, 'UPDATE privilegiata: senza marcatore, marcatore altrui, da titolare, pq_review, DELETE: tutte 42501',
    v_s = '42501/42501/42501/42501/42501'
      and (select stato = 'in_verifica' from private.partners where id = v_p1),
    v_s);

  -- 24: marcatore admin corretto ma la scrittura tocca i dati dichiarati o le marcature.
  perform set_config('vinea.partner_porta', 'admin:partner:' || v_p1::text, true);
  v_s := pg_temp.diretto(format('update private.partners set ragione_sociale = ''Altra Srl'' where id = %L', v_p1));
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set attivo_dal = now() where id = %L', v_p1));
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set titolare_id = %L where id = %L', c_u2, v_p1));
  perform set_config('vinea.partner_porta', '', true);
  perform pg_temp.registra(24, 'anche con marcatore admin: dati dichiarati, marcature e titolare immutabili',
    v_s = '42501/42501/42501', v_s);

  -- 25: azione sconosciuta, motivo mancante, partner inesistente.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''promuovi''))', v_p1), c_a1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, null))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''restituisci'', ''  ''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', gen_random_uuid()), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(25, 'azione sconosciuta o nulla 22023; motivo vuoto 22023; Partner inesistente',
    v_s = '22023/22023/22023/P0001:partner_non_trovato', v_s);

  -- 26: restituisci -> invitato, il titolare corregge e riconsegna.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''restituisci'', ''Verifica la sede legale''))', v_p1), c_a1);
  v_s := v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_u1);
  v_dati := v_c.dati;
  select * into v_c from pg_temp.chiama(format(c_dati_u1, c_piva1), c_u1);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  perform pg_temp.registra(26, 'restituisci: invitato con motivo visibile, correzione, riconsegna',
    v_s = 'NESSUN_ERRORE:invitato/NESSUN_ERRORE/NESSUN_ERRORE:in_verifica'
      and v_dati ->> 'stato' = 'invitato' and v_dati ->> 'ultimo_motivo' = 'Verifica la sede legale'
      and v_dati ->> 'inviato_verifica_at' is null,
    v_s);

  -- 27: anti-autoapprovazione fra admin: a2 diventa titolare e non si approva.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''a2@grid-12x.test'')', c_a1);
  v_tok_a2 := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_a2), c_a2);
  v_pa2 := (v_c.dati #>> '{}')::uuid;
  select * into v_c from pg_temp.chiama(
    'select public.partner_dati_aggiorna(''Cantina A2 Srl'', ''Cantina A2'', ''00000000000'', ''a2@cantina-12x.test'', ''cantina_produttore'', ''Via Po 2'', ''10100'', ''Torino'', ''TO'')', c_a2);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_a2);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_pa2), c_a2);
  v_s := v_s || '/' || v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_pa2), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  perform pg_temp.registra(27, 'un admin titolare non approva il proprio Partner; un altro admin si',
    v_s = 'NESSUN_ERRORE/NESSUN_ERRORE/42501/NESSUN_ERRORE:attivo', v_s);

  -- 28: P.IVA gia registrata da un Partner consegnato.
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u6@grid-12x.test'')', c_a1);
  v_tok_u6 := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok_u6), c_u6);
  v_p6 := (v_c.dati #>> '{}')::uuid;
  select * into v_c from pg_temp.chiama(format(c_dati_u1, c_piva1), c_u6);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', c_u6);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(28, 'partita IVA gia consegnata da un altro Partner: partita_iva_gia_registrata',
    v_s = 'NESSUN_ERRORE/P0001:partita_iva_gia_registrata'
      and (select stato = 'invitato' from private.partners where id = v_p6),
    v_s);

  -- 29: approva u1; ripetizione senza effetti; azione non ammessa da attivo.
  select count(*) into v_n from private.partner_eventi where partner_id = v_p1;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_p1), c_a2);
  v_s := v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''restituisci'', ''tardi''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(29, 'approva -> attivo; ripetizione senza evento; restituisci da attivo rifiutata',
    v_s = 'NESSUN_ERRORE:attivo/NESSUN_ERRORE:attivo/P0001:transizione_non_ammessa'
      and (select count(*) from private.partner_eventi where partner_id = v_p1) = v_n + 1
      and (select attivo_dal is not null from private.partners where id = v_p1),
    v_s);

  -- 30: gate sul checkout. Ordini con identificativi fittizi: i trigger BEFORE
  -- girano prima dei vincoli, quindi il gate risponde per primo per un
  -- venditore Partner, mentre per un venditore privato l'errore e il vincolo
  -- di chiave esterna (cioe il gate non interviene).
  v_s := pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-1'', now())', c_u2, c_u1));
  begin
    insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode,
                               prezzo_cents, idempotency_key, reservation_expires_at)
    values (gen_random_uuid(), c_u2, c_u1, gen_random_uuid(), 'spedizione', 4500, 'grid-12x-2', now());
    v_dati := '"nessun errore"'::jsonb;
  exception when others then
    declare v_h text; begin
      get stacked diagnostics v_h = pg_exception_hint;
      v_dati := to_jsonb(sqlstate || ':' || v_h);
    end;
  end;
  v_s := v_s || '/' || (v_dati #>> '{}');
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-3'', now())', c_u2, c_u4));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-4'', now())', c_u1, c_u4));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-5'', now())', c_u2, c_u6));
  perform pg_temp.registra(30, 'gate: venditore Partner attivo 42501 partner_checkout_non_disponibile; privato, Partner compratore e Partner invitato non toccati',
    v_s like '42501/42501:partner_checkout_non_disponibile/%'
      and split_part(v_s, '/', 3) <> '42501'
      and split_part(v_s, '/', 4) <> '42501'
      and split_part(v_s, '/', 5) <> '42501',
    v_s);

  -- 31: superficie pubblica: solo attivi, colonne chiuse, leggibile da anon.
  select * into v_c from pg_temp.chiama(
    'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.public_partners x', null, 'anon');
  perform pg_temp.registra(31, 'public_partners: anon legge i 2 attivi, 7 colonne, niente P.IVA/indirizzo/titolare',
    v_c.esito = 'NESSUN_ERRORE'
      and jsonb_array_length(v_c.dati) = 2
      and (select bool_and((select count(*) from jsonb_object_keys(r)) = 7
                           and not (r ? 'partita_iva') and not (r ? 'sede_indirizzo')
                           and not (r ? 'titolare_id') and not (r ? 'email_commerciale'))
           from jsonb_array_elements(v_c.dati) r)
      and not exists (select 1 from jsonb_array_elements(v_c.dati) r where (r ->> 'id')::uuid = v_p6),
    v_c.esito || ' ' || coalesce(v_c.dati::text, ''));

  -- 32: sospendi (motivo obbligatorio), gate attivo anche da sospeso, sparisce
  -- dalla superficie pubblica; riattiva.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''sospendi''))', v_p1), c_a1);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''sospendi'', ''Documenti da aggiornare''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-6'', now())', c_u2, c_u1));
  v_n := (select count(*) from public.public_partners where id = v_p1);
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''riattiva''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  perform pg_temp.registra(32, 'sospendi senza motivo 22023; sospeso: gate attivo e assente dal pubblico; riattiva',
    v_s = '22023/NESSUN_ERRORE:sospeso/42501/NESSUN_ERRORE:attivo' and v_n = 0
      and (select sospeso_at is null and stato = 'attivo' from private.partners where id = v_p1),
    v_s);

  -- 33: revoca terminale.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''revoca'', ''Cessata attivita''))', v_p1), c_a1);
  v_s := v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''revoca'', ''ancora''))', v_p1), c_a2);
  v_s := v_s || '/' || v_c.esito || ':' || (v_c.dati #>> '{}');
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''riattiva''))', v_p1), c_a1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform set_config('vinea.partner_porta', 'admin:partner:' || v_p1::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partners set stato = ''attivo'' where id = %L', v_p1));
  perform set_config('vinea.partner_porta', '', true);
  select * into v_c from pg_temp.chiama(format(c_dati_u1, c_piva1), c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_u1);
  perform pg_temp.registra(33, 'revoca terminale: replay ok, riattiva rifiutata anche con marcatore, titolare vede revocato',
    v_s = 'NESSUN_ERRORE:revocato/NESSUN_ERRORE:revocato/P0001:transizione_non_ammessa/42501/P0001:partner_non_trovato'
      and v_c.dati ->> 'stato' = 'revocato' and v_c.dati ->> 'revocato_at' is not null,
    v_s);

  -- 34: dopo la revoca il gate continua a bloccare (decisione del titolare
  -- del 13 ottobre 2026, migrazione 20261013120000: nessuna vendita fino a
  -- riabilitazione) e un nuovo invito per u1 e ammesso.
  v_s := pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12x-7'', now())', c_u2, c_u1));
  select * into v_c from pg_temp.chiama('select public.partner_admin_invito_crea(''u1@grid-12x.test'')', c_a1);
  perform pg_temp.registra(34, 'Partner revocato non riabilitato: il gate rifiuta (42501); reinvito ammesso',
    v_s = '42501' and v_c.esito = 'NESSUN_ERRORE', v_s || '/' || v_c.esito);

  -- 35: audit completo, senza valori dei dati, append-only.
  v_s := pg_temp.diretto('update private.partner_eventi set motivo = ''x''');
  v_s := v_s || '/' || pg_temp.diretto('delete from private.partner_eventi');
  perform pg_temp.registra(35, 'audit: inviti e stati tracciati con attore e porta; nessun valore dei dati; append-only',
    v_s = '42501/42501'
      and exists (select 1 from private.partner_eventi where invito_id = v_id1 and evento = 'invito_creato' and attore_id = c_a1 and porta = 'admin')
      and exists (select 1 from private.partner_eventi where invito_id = v_id1 and evento = 'invito_usato' and attore_id = c_u1 and porta = 'titolare')
      and exists (select 1 from private.partner_eventi where invito_id = v_id_rev and evento = 'invito_revocato' and motivo = 'errore di indirizzo')
      and exists (select 1 from private.partner_eventi where partner_id = v_p1 and evento = 'partner_creato')
      and (select array_agg(a_stato::text order by id) from private.partner_eventi
           where partner_id = v_p1 and evento = 'stato_cambiato')
          = array['in_verifica', 'invitato', 'in_verifica', 'attivo', 'sospeso', 'attivo', 'revocato']
      and exists (select 1 from private.partner_eventi where partner_id = v_p1 and evento = 'stato_cambiato'
                  and a_stato = 'attivo' and da_stato = 'in_verifica' and attore_id = c_a2 and porta = 'admin')
      and not exists (select 1 from private.partner_eventi
                      where dettagli::text like '%' || c_piva1 || '%' or dettagli::text like '%Enoteca%')
      and exists (select 1 from private.partner_eventi where partner_id = v_p1 and evento = 'dati_aggiornati'
                  and dettagli -> 'campi' ? 'partita_iva'),
    v_s);

  -- 36: letture admin: niente token, niente hash; negate ai non admin.
  select * into v_c from pg_temp.chiama('select public.partner_admin_inviti()', c_a1);
  v_dati := v_c.dati;
  select * into v_c from pg_temp.chiama('select public.partner_admin_elenco()', c_u2);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select public.partner_admin_elenco(''attivo'')', c_a1);
  perform pg_temp.registra(36, 'admin elenca inviti senza token/hash e Partner per stato; non admin 42501',
    jsonb_array_length(v_dati) >= 8
      and v_dati::text not like '%' || v_tok1 || '%'
      and not exists (select 1 from jsonb_array_elements(v_dati) r where r ? 'token' or r ? 'token_hash')
      and exists (select 1 from jsonb_array_elements(v_dati) r where r ->> 'id' = v_id1::text and r ->> 'stato' = 'usato')
      and exists (select 1 from jsonb_array_elements(v_dati) r where r ->> 'id' = v_id_rev::text and r ->> 'stato' = 'revocato')
      and exists (select 1 from jsonb_array_elements(v_dati) r where r ->> 'stato' = 'scaduto')
      and v_s = '42501'
      and jsonb_array_length(v_c.dati) = 1 and v_c.dati -> 0 ->> 'id' = v_pa2::text
      and v_c.dati -> 0 ->> 'titolare_email' = 'a2@grid-12x.test',
    v_s);

  -- 37: chi non ha un Partner vede null; anon non chiama partner_me.
  select * into v_c from pg_temp.chiama('select public.partner_me()', c_u4);
  v_s := v_c.esito || ':' || coalesce(v_c.dati::text, 'null');
  select * into v_c from pg_temp.chiama('select public.partner_me()', null, 'anon');
  perform pg_temp.registra(37, 'partner_me: null senza Partner; anon senza privilegio',
    v_s = 'NESSUN_ERRORE:null' and v_c.esito = '42501', v_s || '/' || v_c.esito);

  -- 38: invarianza: nessun ruolo scritto, margine privato 800 bps intatto,
  -- una sola riga corrente privata (dopo VP-D esiste anche la riga Partner).
  perform pg_temp.registra(38, 'user_roles invariato; marketplace_config: una riga corrente privata a 800 bps',
    (select count(*) from public.user_roles) = v_ruoli_prima
      and (select count(*) from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 1
      and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 800);
end $$;

select id, descrizione, passed, detail
from esiti_12x
order by id;

rollback;
