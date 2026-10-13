-- Vinea Partner — Blocco B: vetrina pubblica, media, gate sulle proposte
-- (griglia 12y).
--
-- SOLO stack Supabase locale/effimero. Utenti Auth `.test`, Partner, vetrine e
-- oggetti Storage vivono nella transazione e spariscono con ROLLBACK. Prova la
-- migrazione 20261011200000: vetrina pubblica solo per Partner attivi con
-- profilo visibile e colonne chiuse (nessuna P.IVA, ragione sociale,
-- indirizzo, email, motivo); salvataggio solo dal titolare, nei soli stati
-- ammessi e con account attivo; forma, quantita, unicita ed esistenza dei
-- media; policy di Storage a privilegi del chiamante; marcatore dedicato
-- legato alla riga; audit senza valori; specchio del gate; gate sulle
-- proposte; invarianza di Blocco A, ruoli e configurazione economica.
--
-- Lo Storage vieta da se ogni DELETE diretta su `storage.objects` (vedi 12m):
-- la policy di cancellazione si prova sul suo predicato valutato dal
-- chiamante, con il testo della policy fissato dal caso 22.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12y: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12y (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12y (id, descrizione, passed, detail)
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

-- Come chiama, per istruzioni che non restituiscono righe (INSERT su
-- storage.objects come lo scrive il client).
create function pg_temp.esegui(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare
  v_esito text;
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
    execute p_sql;
    v_esito := 'ok';
  exception when others then
    v_esito := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  return v_esito;
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

-- Partita IVA valida da un prefisso di dieci cifre: la cifra di controllo la
-- sceglie la funzione autorevole del Blocco A, non un secondo algoritmo.
create function pg_temp.piva(p_prefisso text) returns text language sql as $f$
  select p_prefisso || d::text
  from generate_series(0, 9) d
  where private.partita_iva_valida(p_prefisso || d::text)
  limit 1;
$f$;

-- Porta un account fino allo stato richiesto passando SOLO dalle porte del
-- Blocco A (invito → accettazione → dati → consegna → decisioni admin).
create function pg_temp.partner_fino(
  p_admin uuid, p_uid uuid, p_email text, p_piva text, p_stato text
) returns uuid language plpgsql as $f$
declare
  v_c record;
  v_tok text;
  v_id uuid;
begin
  select * into v_c from pg_temp.chiama(format('select public.partner_admin_invito_crea(%L)', p_email), p_admin);
  v_tok := v_c.dati ->> 'token';
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_invito_accetta(%L))', v_tok), p_uid);
  v_id := (v_c.dati #>> '{}')::uuid;
  if v_id is null then
    raise exception 'fixture 12y: accettazione fallita per % (%)', p_email, v_c.esito;
  end if;
  if p_stato = 'invitato' then
    return v_id;
  end if;
  select * into v_c from pg_temp.chiama(format(
    'select public.partner_dati_aggiorna(''Ragione %s Srl'', ''Vetrina %s'', %L, %L, ''enoteca'', ''Via Segreta 7'', ''12051'', ''Alba'', ''CN'')',
    p_email, p_email, p_piva, 'commerciale.' || p_email), p_uid);
  select * into v_c from pg_temp.chiama('select to_jsonb(public.partner_invia_verifica())', p_uid);
  if p_stato = 'in_verifica' then
    return v_id;
  end if;
  select * into v_c from pg_temp.chiama(format('select to_jsonb(public.partner_admin_decidi(%L, ''approva''))', v_id), p_admin);
  if p_stato = 'sospeso' then
    select * into v_c from pg_temp.chiama(
      format('select to_jsonb(public.partner_admin_decidi(%L, ''sospendi'', ''verifica documenti''))', v_id), p_admin);
  elsif p_stato = 'revocato' then
    select * into v_c from pg_temp.chiama(
      format('select to_jsonb(public.partner_admin_decidi(%L, ''revoca'', ''motivo interno riservato''))', v_id), p_admin);
  end if;
  if (select stato::text from private.partners where id = v_id) <> p_stato then
    raise exception 'fixture 12y: % non e arrivato a %', p_email, p_stato;
  end if;
  return v_id;
end;
$f$;

create function pg_temp.percorso(p_uid uuid, p_partner uuid) returns text language sql as $f$
  select p_uid::text || '/' || p_partner::text || '/' || gen_random_uuid()::text || '.webp';
$f$;

-- Un oggetto come lo lascia lo Storage dopo un caricamento riuscito.
create function pg_temp.oggetto_fixture(p_name text, p_owner uuid, p_mime text default 'image/webp')
returns void language sql as $f$
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('partner-vetrine', p_name, p_owner,
          jsonb_build_object('mimetype', p_mime, 'size', 120000));
$f$;

-- In plpgsql e non in SQL: in una sola espressione il conteggio, che non
-- dipende dall'INSERT, diventerebbe un InitPlan valutato PRIMA del caricamento.
create function pg_temp.carica(p_uid uuid, p_name text, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare
  v_esito text;
begin
  v_esito := pg_temp.esegui(format(
    'insert into storage.objects (bucket_id, name, owner, metadata) '
    'values (''partner-vetrine'', %L, %L::uuid, ''{"mimetype":"image/webp","size":1000}''::jsonb)',
    p_name, p_uid), p_uid, p_ruolo);
  return v_esito || ' / oggetti ' || (select count(*) from storage.objects
                                       where bucket_id = 'partner-vetrine' and name = p_name)::text;
end;
$f$;

-- Predicato della policy di DELETE, valutato dal chiamante.
create function pg_temp.cancellabile(p_uid uuid, p_name text) returns text language plpgsql as $f$
declare
  v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb((storage.foldername(%L))[1] = (select auth.uid())::text '
    'and private.partner_media_cancellabile_dal_chiamante(%L))', p_name, p_name), p_uid);
  return coalesce(v_c.dati #>> '{}', v_c.esito);
end;
$f$;

\set a1 '12ee0000-0000-4000-8000-0000000000a1'
\set u1 '12ee0000-0000-4000-8000-0000000000b1'
\set u2 '12ee0000-0000-4000-8000-0000000000b2'
\set u3 '12ee0000-0000-4000-8000-0000000000b3'
\set u4 '12ee0000-0000-4000-8000-0000000000b4'
\set u5 '12ee0000-0000-4000-8000-0000000000b5'
\set u6 '12ee0000-0000-4000-8000-0000000000b6'
\set u7 '12ee0000-0000-4000-8000-0000000000b7'
\set u8 '12ee0000-0000-4000-8000-0000000000b8'

-- a1: admin. u1: Partner attivo. u2: estraneo senza Partner. u3: venditore
-- privato. u4: Partner in verifica. u5: Partner sospeso. u6: Partner
-- revocato. u7: Partner invitato. u8: utente rimosso (lettore).
set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'a1', 'a1@grid-12y.test', now(), '{}'::jsonb),
  (:'u1', 'u1@grid-12y.test', now(), '{}'::jsonb),
  (:'u2', 'u2@grid-12y.test', now(), '{}'::jsonb),
  (:'u3', 'u3@grid-12y.test', now(), '{}'::jsonb),
  (:'u4', 'u4@grid-12y.test', now(), '{}'::jsonb),
  (:'u5', 'u5@grid-12y.test', now(), '{}'::jsonb),
  (:'u6', 'u6@grid-12y.test', now(), '{}'::jsonb),
  (:'u7', 'u7@grid-12y.test', now(), '{}'::jsonb),
  (:'u8', 'u8@grid-12y.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'a1', 'a1-12y', date '1980-01-01'),
  (:'u1', 'u1-12y', date '1980-01-01'),
  (:'u2', 'u2-12y', date '1980-01-01'),
  (:'u3', 'u3-12y', date '1980-01-01'),
  (:'u4', 'u4-12y', date '1980-01-01'),
  (:'u5', 'u5-12y', date '1980-01-01'),
  (:'u6', 'u6-12y', date '1980-01-01'),
  (:'u7', 'u7-12y', date '1980-01-01'),
  (:'u8', 'u8-12y', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'a1', 'admin'), (:'u1', 'user'), (:'u2', 'user'), (:'u3', 'user'), (:'u4', 'user'),
  (:'u5', 'user'), (:'u6', 'user'), (:'u7', 'user'), (:'u8', 'user');
update public.profiles set stato_utente = 'rimosso' where id = :'u8';
set local session_replication_role = origin;

do $$
declare
  c_a1 constant uuid := '12ee0000-0000-4000-8000-0000000000a1';
  c_u1 constant uuid := '12ee0000-0000-4000-8000-0000000000b1';
  c_u2 constant uuid := '12ee0000-0000-4000-8000-0000000000b2';
  c_u3 constant uuid := '12ee0000-0000-4000-8000-0000000000b3';
  c_u4 constant uuid := '12ee0000-0000-4000-8000-0000000000b4';
  c_u5 constant uuid := '12ee0000-0000-4000-8000-0000000000b5';
  c_u6 constant uuid := '12ee0000-0000-4000-8000-0000000000b6';
  c_u7 constant uuid := '12ee0000-0000-4000-8000-0000000000b7';
  c_u8 constant uuid := '12ee0000-0000-4000-8000-0000000000b8';
  c_chiavi constant text[] := array[
    'aggiornata_at', 'attivo_dal', 'copertina_path', 'descrizione', 'foto_paths',
    'logo_path', 'nome_commerciale', 'paese', 'partner_id', 'presentazione',
    'sede_citta', 'sede_provincia', 'tipologia', 'titolare_id'];
  v_ruoli_prima integer;
  v_config_prima text;
  v_p1 uuid; v_p4 uuid; v_p5 uuid; v_p6 uuid; v_p7 uuid;
  v_logo text; v_cop text; v_f1 text; v_f2 text; v_f3 text; v_f4 text; v_f5 text;
  v_libero text; v_p4_file text; v_altrui text;
  v_c record;
  v_s text;
  v_dati jsonb;
  v_ok boolean;
  v_id text;
begin
  select count(*) into v_ruoli_prima from public.user_roles;
  select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
    into v_config_prima from public.marketplace_config;

  v_p1 := pg_temp.partner_fino(c_a1, c_u1, 'u1@grid-12y.test', pg_temp.piva('1112223330'), 'attivo');
  v_p4 := pg_temp.partner_fino(c_a1, c_u4, 'u4@grid-12y.test', pg_temp.piva('1112223340'), 'in_verifica');
  v_p5 := pg_temp.partner_fino(c_a1, c_u5, 'u5@grid-12y.test', pg_temp.piva('1112223350'), 'sospeso');
  v_p6 := pg_temp.partner_fino(c_a1, c_u6, 'u6@grid-12y.test', pg_temp.piva('1112223360'), 'revocato');
  v_p7 := pg_temp.partner_fino(c_a1, c_u7, 'u7@grid-12y.test', null, 'invitato');

  -- 01: privilegi e forma delle nuove porte.
  perform pg_temp.registra(1, 'porte vetrina: mia/salva solo authenticated, pubblica e specchio anche anon; security definer, search_path vuoto',
    has_function_privilege('authenticated', 'public.vetrina_partner_mia()', 'EXECUTE')
      and not has_function_privilege('anon', 'public.vetrina_partner_mia()', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.vetrina_partner_salva(text, text, text, text, text[])', 'EXECUTE')
      and not has_function_privilege('anon', 'public.vetrina_partner_salva(text, text, text, text, text[])', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.vetrina_partner_salva(text, text, text, text, text[])', 'EXECUTE')
      and has_function_privilege('anon', 'public.vetrina_partner_pubblica(uuid)', 'EXECUTE')
      and has_function_privilege('anon', 'public.acquisto_da_venditore_disponibile(uuid)', 'EXECUTE')
      and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('vetrina_partner_mia', 'vetrina_partner_salva',
                               'vetrina_partner_pubblica', 'acquisto_da_venditore_disponibile'))
      and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'partner\_%') = 12);

  -- 02: tabella privata chiusa, RLS attiva, helper privati non ad anon.
  perform pg_temp.registra(2, 'private.partner_vetrine senza grant client e con RLS; helper di Storage non eseguibili da anon',
    not has_table_privilege('authenticated', 'private.partner_vetrine', 'SELECT')
      and not has_table_privilege('anon', 'private.partner_vetrine', 'SELECT')
      and not has_table_privilege('authenticated', 'private.partner_vetrine', 'INSERT')
      and (select c.relrowsecurity from pg_class c where c.oid = 'private.partner_vetrine'::regclass)
      and not has_function_privilege('anon', 'private.partner_vetrina_cartella_del_chiamante(text)', 'EXECUTE')
      and not has_function_privilege('anon', 'private.partner_media_cancellabile_dal_chiamante(text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'private.partner_vetrina_json(private.partners, private.partner_vetrine)', 'EXECUTE'));

  -- 03: bucket dedicato, pubblico, solo WebP fino a 2 MB.
  perform pg_temp.registra(3, 'bucket partner-vetrine: pubblico, 2 MB, solo image/webp',
    exists (select 1 from storage.buckets b
            where b.id = 'partner-vetrine' and b.public
              and b.file_size_limit = 2097152
              and b.allowed_mime_types = array['image/webp']));

  -- 04: Partner attivo senza contenuti: vetrina pubblica con chiavi chiuse.
  select * into v_c from pg_temp.chiama(format('select public.vetrina_partner_pubblica(%L)', c_u1), null, 'anon');
  v_dati := v_c.dati;
  perform pg_temp.registra(4, 'anon legge la vetrina del Partner attivo: elenco chiuso di 14 chiavi, foto vuote',
    v_c.esito = 'NESSUN_ERRORE'
      and (select array_agg(k order by k) from jsonb_object_keys(v_dati) k) = c_chiavi
      and v_dati ->> 'partner_id' = v_p1::text
      and v_dati ->> 'titolare_id' = c_u1::text
      and v_dati ->> 'nome_commerciale' = 'Vetrina u1@grid-12y.test'
      and v_dati -> 'foto_paths' = '[]'::jsonb
      and v_dati ->> 'logo_path' is null,
    coalesce(v_c.esito, '') || ' ' || coalesce(v_dati::text, 'null'));

  -- 05: nessun dato amministrativo nella proiezione pubblica.
  perform pg_temp.registra(5, 'nessuna P.IVA, ragione sociale, indirizzo, email, stato o motivo nella vetrina pubblica',
    v_dati::text not like '%' || (select partita_iva from private.partners where id = v_p1) || '%'
      and v_dati::text not like '%Ragione%'
      and v_dati::text not like '%Via Segreta%'
      and v_dati::text not like '%commerciale.%'
      and not (v_dati ? 'stato') and not (v_dati ? 'ultimo_motivo'),
    v_dati::text);

  -- 06: nessuna vetrina pubblica fuori da `attivo`, ne per privati o sconosciuti.
  v_s := '';
  foreach v_id in array array[c_u4::text, c_u5::text, c_u6::text, c_u7::text, c_u3::text, gen_random_uuid()::text] loop
    select * into v_c from pg_temp.chiama(format('select public.vetrina_partner_pubblica(%L)', v_id), null, 'anon');
    v_s := v_s || coalesce(v_c.dati::text, 'null') || '/';
  end loop;
  perform pg_temp.registra(6, 'in verifica, sospeso, revocato, invitato, privato e uuid sconosciuto: null',
    v_s = 'null/null/null/null/null/null/', v_s);

  -- 07: vetrina_partner_mia: cartella, stato, modificabilita; null senza Partner; anon 42501.
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', c_u1);
  v_dati := v_c.dati;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', c_u5);
  v_s := coalesce(v_c.dati ->> 'modificabile', 'x') || ':' || coalesce(v_c.dati ->> 'stato', 'x');
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', c_u6);
  v_s := v_s || '/' || coalesce(v_c.dati ->> 'modificabile', 'x') || ':' || coalesce(v_c.dati ->> 'stato', 'x');
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', c_u3);
  v_s := v_s || '/' || v_c.esito || ':' || coalesce(v_c.dati::text, 'null');
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', null, 'anon');
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(7, 'vetrina_partner_mia: cartella del titolare; sospeso e revocato in sola lettura; privato null; anon 42501',
    v_dati ->> 'cartella' = c_u1::text || '/' || v_p1::text
      and v_dati ->> 'modificabile' = 'true' and v_dati ->> 'stato' = 'attivo'
      and v_s = 'false:sospeso/false:revocato/NESSUN_ERRORE:null/42501',
    v_s);

  -- 08: salvataggio dei soli testi, normalizzati.
  select * into v_c from pg_temp.chiama(
    'select public.vetrina_partner_salva(''  Vini naturali dal 1998  '', ''Enoteca di quartiere.'', null, null, null)', c_u1);
  perform pg_temp.registra(8, 'il titolare salva presentazione e descrizione (spazi tolti, foto vuote)',
    v_c.esito = 'NESSUN_ERRORE'
      and v_c.dati ->> 'presentazione' = 'Vini naturali dal 1998'
      and v_c.dati ->> 'descrizione' = 'Enoteca di quartiere.'
      and v_c.dati -> 'foto_paths' = '[]'::jsonb,
    coalesce(v_c.esito, '') || ' ' || coalesce(v_c.dati::text, ''));

  -- 09: limiti dei testi.
  select * into v_c from pg_temp.chiama(
    format('select public.vetrina_partner_salva(%L, null, null, null, null)', repeat('a', 161)), c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    format('select public.vetrina_partner_salva(null, %L, null, null, null)', repeat('b', 2001)), c_u1);
  perform pg_temp.registra(9, 'presentazione oltre 160 e descrizione oltre 2000 caratteri rifiutate (22023)',
    v_s = '22023:presentazione_lunga' and v_c.esito = '22023' and v_c.hint = 'descrizione_lunga',
    v_s || '/' || v_c.esito || ':' || v_c.hint);

  -- 10-14: policy di caricamento a privilegi del chiamante.
  v_logo := pg_temp.percorso(c_u1, v_p1);
  v_s := pg_temp.carica(c_u1, v_logo);
  perform pg_temp.registra(10, 'il titolare attivo carica un WebP nella propria cartella di vetrina',
    v_s = 'ok / oggetti 1', v_s);

  v_s := pg_temp.carica(c_u1, pg_temp.percorso(c_u1, v_p4));
  v_s := v_s || ' | ' || pg_temp.carica(c_u2, pg_temp.percorso(c_u2, v_p1));
  v_s := v_s || ' | ' || pg_temp.carica(c_u2, pg_temp.percorso(c_u1, v_p1));
  v_s := v_s || ' | ' || pg_temp.carica(c_u1, c_u1::text || '/' || v_p1::text || '/' || gen_random_uuid()::text || '.png');
  v_s := v_s || ' | ' || pg_temp.carica(c_u1, c_u1::text || '/' || v_p1::text || '/../' || gen_random_uuid()::text || '.webp');
  perform pg_temp.registra(11, 'rifiutati: Partner altrui, cartella altrui, estraneo, estensione non WebP, path traversal',
    v_s = '42501 / oggetti 0 | 42501 / oggetti 0 | 42501 / oggetti 0 | 42501 / oggetti 0 | 42501 / oggetti 0', v_s);

  v_s := pg_temp.carica(c_u5, pg_temp.percorso(c_u5, v_p5));
  v_s := v_s || ' | ' || pg_temp.carica(c_u6, pg_temp.percorso(c_u6, v_p6));
  v_s := v_s || ' | ' || pg_temp.carica(null, pg_temp.percorso(c_u1, v_p1), 'anon');
  perform pg_temp.registra(12, 'Partner sospeso, revocato e anon non caricano',
    v_s = '42501 / oggetti 0 | 42501 / oggetti 0 | 42501 / oggetti 0', v_s);

  v_p4_file := pg_temp.percorso(c_u4, v_p4);
  v_s := pg_temp.carica(c_u4, v_p4_file);
  v_s := v_s || ' | ' || pg_temp.carica(c_u7, pg_temp.percorso(c_u7, v_p7));
  perform pg_temp.registra(13, 'Partner in verifica e invitato preparano la vetrina (caricano)',
    v_s = 'ok / oggetti 1 | ok / oggetti 1', v_s);

  -- 14: lettura della cartella: ognuno vede solo la propria.
  select * into v_c from pg_temp.chiama(
    'select to_jsonb(count(*)) from storage.objects where bucket_id = ''partner-vetrine''', c_u2);
  v_s := v_c.dati #>> '{}';
  select * into v_c from pg_temp.chiama(
    'select to_jsonb(count(*)) from storage.objects where bucket_id = ''partner-vetrine''', c_u1);
  perform pg_temp.registra(14, 'SELECT su storage.objects: l estraneo non elenca nulla, il titolare solo la propria cartella',
    v_s = '0' and v_c.dati #>> '{}' = '1', v_s || '/' || (v_c.dati #>> '{}'));

  -- 15: salvataggio con media validi gia caricati.
  v_cop := pg_temp.percorso(c_u1, v_p1);
  v_f1 := pg_temp.percorso(c_u1, v_p1); v_f2 := pg_temp.percorso(c_u1, v_p1);
  v_f3 := pg_temp.percorso(c_u1, v_p1); v_f4 := pg_temp.percorso(c_u1, v_p1);
  v_f5 := pg_temp.percorso(c_u1, v_p1); v_libero := pg_temp.percorso(c_u1, v_p1);
  perform pg_temp.oggetto_fixture(v_cop, c_u1);
  perform pg_temp.oggetto_fixture(v_f1, c_u1); perform pg_temp.oggetto_fixture(v_f2, c_u1);
  perform pg_temp.oggetto_fixture(v_f3, c_u1); perform pg_temp.oggetto_fixture(v_f4, c_u1);
  perform pg_temp.oggetto_fixture(v_f5, c_u1); perform pg_temp.oggetto_fixture(v_libero, c_u1);
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(''Vini naturali dal 1998'', ''Enoteca di quartiere.'', %L, %L, %L::text[])',
    v_logo, v_cop, array[v_f1, v_f2, v_f3, v_f4]), c_u1);
  perform pg_temp.registra(15, 'logo, copertina e quattro foto salvati; la vetrina pubblica li espone in ordine',
    v_c.esito = 'NESSUN_ERRORE'
      and (select v.logo_path = v_logo and v.copertina_path = v_cop
                  and v.foto_paths = array[v_f1, v_f2, v_f3, v_f4]
           from private.partner_vetrine v where v.partner_id = v_p1)
      and (public.vetrina_partner_pubblica(c_u1) -> 'foto_paths') = to_jsonb(array[v_f1, v_f2, v_f3, v_f4]),
    coalesce(v_c.esito, ''));

  -- 16: piu di quattro foto, file duplicati.
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, null, null, %L::text[])',
    array[v_f1, v_f2, v_f3, v_f4, v_f5]), c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, %L, null, %L::text[])', v_f1, array[v_f1]), c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.vetrina_partner_salva(null, null, null, null, array[null]::text[])', c_u1);
  perform pg_temp.registra(16, 'cinque foto, file usato due volte ed elemento nullo rifiutati',
    v_s = '22023:troppe_foto/22023:media_duplicato' and v_c.esito = '22023' and v_c.hint = 'media_non_valido',
    v_s || '/' || v_c.esito || ':' || v_c.hint);

  -- 17: media di un altro titolare o di un altro Partner, URL esterno, path
  -- traversal: rifiutati prima di guardare lo Storage.
  v_altrui := v_p4_file;
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, %L, null, null)', v_altrui), c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(
    'select public.vetrina_partner_salva(null, null, ''https://esempio.test/logo.webp'', null, null)', c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, %L, null, null)',
    c_u1::text || '/' || v_p1::text || '/../' || v_p4_file), c_u1);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  perform pg_temp.registra(17, 'file di un altro Partner, URL esterno e path traversal rifiutati (media_non_valido)',
    v_s = '22023:media_non_valido/22023:media_non_valido/22023:media_non_valido', v_s);

  -- 18: percorso ben formato ma mai caricato, oppure caricato con un tipo diverso.
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, %L, null, null)', pg_temp.percorso(c_u1, v_p1)), c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  v_f5 := pg_temp.percorso(c_u1, v_p1);
  perform pg_temp.oggetto_fixture(v_f5, c_u1, 'image/svg+xml');
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(null, null, %L, null, null)', v_f5), c_u1);
  perform pg_temp.registra(18, 'file inesistente o non WebP: media_non_trovato',
    v_s = 'P0001:media_non_trovato' and v_c.esito = 'P0001' and v_c.hint = 'media_non_trovato',
    v_s || '/' || v_c.esito || ':' || v_c.hint);

  -- 19: chi non puo salvare.
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''x'', null, null, null, null)', c_u5);
  v_s := v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''x'', null, null, null, null)', c_u6);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''x'', null, null, null, null)', c_u2);
  v_s := v_s || '/' || v_c.esito || ':' || v_c.hint;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''x'', null, null, null, null)', null, 'anon');
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(19, 'sospeso: vetrina_non_modificabile; revocato ed estraneo: partner_non_trovato; anon 42501',
    v_s = 'P0001:vetrina_non_modificabile/P0001:partner_non_trovato/P0001:partner_non_trovato/42501', v_s);

  -- 20: in verifica e invitato preparano, ma nulla diventa pubblico.
  select * into v_c from pg_temp.chiama(format(
    'select public.vetrina_partner_salva(''Pronta per il lancio'', null, %L, null, null)', v_p4_file), c_u4);
  v_s := v_c.esito;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''Bozza'', null, null, null, null)', c_u7);
  v_s := v_s || '/' || v_c.esito;
  perform pg_temp.registra(20, 'in verifica e invitato salvano la vetrina; resta non pubblica',
    v_s = 'NESSUN_ERRORE/NESSUN_ERRORE'
      and public.vetrina_partner_pubblica(c_u4) is null
      and public.vetrina_partner_pubblica(c_u7) is null,
    v_s);

  -- 21: titolare sospeso dalla moderazione: non salva e non carica.
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'sospeso' where id = c_u1;
  set local session_replication_role = origin;
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_salva(''x'', null, null, null, null)', c_u1);
  v_s := v_c.esito || ':' || v_c.hint;
  v_s := v_s || '/' || pg_temp.carica(c_u1, pg_temp.percorso(c_u1, v_p1));
  select * into v_c from pg_temp.chiama('select public.vetrina_partner_mia()', c_u1);
  v_s := v_s || '/' || coalesce(v_c.dati ->> 'modificabile', 'x');
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'attivo' where id = c_u1;
  set local session_replication_role = origin;
  perform pg_temp.registra(21, 'titolare con account sospeso: niente salvataggio, niente caricamento, modificabile false',
    v_s = '42501:utente_non_attivo/42501 / oggetti 0/false', v_s);

  -- 22: cancellazione: predicato della policy e suo testo.
  v_s := pg_temp.cancellabile(c_u1, v_logo) || '/' || pg_temp.cancellabile(c_u1, v_f1)
    || '/' || pg_temp.cancellabile(c_u1, v_libero) || '/' || pg_temp.cancellabile(c_u2, v_libero);
  perform pg_temp.registra(22, 'si cancella solo un proprio file non in uso; la policy di DELETE e quel predicato',
    v_s = 'false/false/true/false'
      and exists (select 1 from pg_policies
                  where schemaname = 'storage' and tablename = 'objects'
                    and policyname = 'partner_vetrine_delete_propria_non_in_uso'
                    and cmd = 'DELETE' and roles = '{authenticated}'
                    and qual like '%partner_media_cancellabile_dal_chiamante(name)%'
                    and qual like '%foldername(name)%')
      and not exists (select 1 from pg_policies
                      where schemaname = 'storage' and tablename = 'objects'
                        and policyname like 'partner_vetrine%' and cmd = 'UPDATE'),
    v_s);

  -- 23: scritture dirette privilegiate rifiutate; marcatore per un'altra riga
  -- non apre questa; il trigger rifiuta un percorso altrui anche con marcatore.
  v_s := pg_temp.diretto(format('update private.partner_vetrine set descrizione = ''x'' where partner_id = %L', v_p1));
  v_s := v_s || '/' || pg_temp.diretto(format('delete from private.partner_vetrine where partner_id = %L', v_p1));
  v_s := v_s || '/' || pg_temp.diretto('truncate private.partner_vetrine');
  perform set_config('vinea.partner_porta', 'titolare:vetrina:' || v_p4::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partner_vetrine set descrizione = ''x'' where partner_id = %L', v_p1));
  perform set_config('vinea.partner_porta', 'titolare:partner:' || v_p1::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format('update private.partner_vetrine set descrizione = ''x'' where partner_id = %L', v_p1));
  perform set_config('vinea.partner_porta', 'titolare:vetrina:' || v_p1::text, true);
  v_s := v_s || '/' || pg_temp.diretto(format(
    'update private.partner_vetrine set logo_path = %L where partner_id = %L', v_altrui, v_p1));
  perform set_config('vinea.partner_porta', '', true);
  perform pg_temp.registra(23, 'update/delete/truncate diretti, marcatore di altra riga o di altra porta, percorso altrui: 42501',
    v_s = '42501/42501/42501/42501/42501/42501', v_s);

  -- 24: Partner sospeso: la vetrina sparisce subito, i contenuti restano; con
  -- la riattivazione torna identica.
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''sospendi'', ''controllo''))', v_p1), c_a1);
  v_s := coalesce(public.vetrina_partner_pubblica(c_u1)::text, 'null');
  v_ok := exists (select 1 from private.partner_vetrine where partner_id = v_p1 and logo_path = v_logo);
  select * into v_c from pg_temp.chiama(
    format('select to_jsonb(public.partner_admin_decidi(%L, ''riattiva''))', v_p1), c_a1);
  perform pg_temp.registra(24, 'sospensione: vetrina pubblica null, contenuti conservati; riattivazione: torna',
    v_s = 'null' and v_ok
      and public.vetrina_partner_pubblica(c_u1) ->> 'logo_path' = v_logo,
    v_s);

  -- 25: profilo non visibile: titolare rimosso, oppure lettore rimosso.
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'rimosso' where id = c_u1;
  set local session_replication_role = origin;
  v_s := coalesce(public.vetrina_partner_pubblica(c_u1)::text, 'null');
  set local session_replication_role = replica;
  update public.profiles set stato_utente = 'attivo' where id = c_u1;
  set local session_replication_role = origin;
  select * into v_c from pg_temp.chiama(format('select public.vetrina_partner_pubblica(%L)', c_u1), c_u8);
  v_s := v_s || '/' || coalesce(v_c.dati::text, 'null');
  select * into v_c from pg_temp.chiama(format('select public.vetrina_partner_pubblica(%L)', c_u1), c_u2);
  perform pg_temp.registra(25, 'titolare rimosso o lettore rimosso: null (regole di profilo_pubblico); estraneo la vede',
    v_s = 'null/null' and v_c.dati ->> 'partner_id' = v_p1::text, v_s);

  -- 26: audit: nomi dei campi, mai testi o percorsi; porta titolare.
  perform pg_temp.registra(26, 'audit vetrina_aggiornata con attore, porta titolare e soli nomi dei campi',
    exists (select 1 from private.partner_eventi e
            where e.partner_id = v_p1 and e.evento = 'vetrina_aggiornata'
              and e.attore_id = c_u1 and e.porta = 'titolare'
              and e.dettagli -> 'campi' ?& array['logo', 'copertina', 'foto'])
      and not exists (select 1 from private.partner_eventi e
                      where e.evento = 'vetrina_aggiornata'
                        and (e.dettagli::text like '%Vini naturali%'
                             or e.dettagli::text like '%.webp%')));

  -- 27: specchio del gate.
  v_s := '';
  foreach v_id in array array[c_u1::text, c_u5::text, c_u4::text, c_u6::text, c_u7::text, c_u3::text] loop
    select * into v_c from pg_temp.chiama(
      format('select to_jsonb(public.acquisto_da_venditore_disponibile(%L))', v_id), null, 'anon');
    v_s := v_s || (v_c.dati #>> '{}') || '/';
  end loop;
  -- Dal 20261013120000 anche il revocato non riabilitato (u6) non vende.
  perform pg_temp.registra(27, 'acquisto non disponibile per Partner attivo, sospeso e revocato non riabilitato (come il gate degli ordini)',
    v_s = 'false/false/true/false/true/true/', v_s);

  -- 28: lo specchio coincide con il gate reale sugli ordini.
  v_s := pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12y-1'', now())', c_u2, c_u1));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.orders (listing_id, buyer_id, seller_id, seller_bottle_unit_id, delivery_mode, prezzo_cents, idempotency_key, reservation_expires_at)
     values (gen_random_uuid(), %L, %L, gen_random_uuid(), ''spedizione'', 4500, ''grid-12y-2'', now())', c_u2, c_u3));
  perform pg_temp.registra(28, 'gate ordini: Partner attivo 42501, privato non bloccato dal gate (errore di vincolo)',
    split_part(v_s, '/', 1) = '42501' and split_part(v_s, '/', 2) <> '42501', v_s);

  -- 29: gate sulle proposte: Partner attivo e sospeso bloccati, privato no.
  v_s := pg_temp.diretto(format(
    'insert into public.proposals (listing_id, buyer_id, seller_id, prezzo_richiesto_cents, prezzo_proposto_cents, scadenza)
     values (gen_random_uuid(), %L, %L, 5000, 4500, now() + interval ''1 day'')', c_u2, c_u1));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.proposals (listing_id, buyer_id, seller_id, prezzo_richiesto_cents, prezzo_proposto_cents, scadenza)
     values (gen_random_uuid(), %L, %L, 5000, 4500, now() + interval ''1 day'')', c_u2, c_u5));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.proposals (listing_id, buyer_id, seller_id, prezzo_richiesto_cents, prezzo_proposto_cents, scadenza)
     values (gen_random_uuid(), %L, %L, 5000, 4500, now() + interval ''1 day'')', c_u2, c_u3));
  v_s := v_s || '/' || pg_temp.diretto(format(
    'insert into public.proposals (listing_id, buyer_id, seller_id, prezzo_richiesto_cents, prezzo_proposto_cents, scadenza)
     values (gen_random_uuid(), %L, %L, 5000, 4500, now() + interval ''1 day'')', c_u1, c_u3));
  perform pg_temp.registra(29, 'proposte: venditore Partner attivo/sospeso 42501; privato e compratore Partner non bloccati dal gate',
    split_part(v_s, '/', 1) = '42501' and split_part(v_s, '/', 2) = '42501'
      and split_part(v_s, '/', 3) <> '42501' and split_part(v_s, '/', 4) <> '42501'
      and exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.proposals'::regclass
                    and t.tgname = 'proposals_partner_gate' and not t.tgisinternal),
    v_s);

  -- 30: invarianza: Blocco A, ruoli, configurazione economica, vista pubblica.
  perform pg_temp.registra(30, 'user_roles e marketplace_config invariati; public_partners resta a 7 colonne; gate ordini intatto',
    (select count(*) from public.user_roles) = v_ruoli_prima
      and (select string_agg(concat_ws(':', id, margine_obiettivo_bps, valida_fino), ',' order by id)
           from public.marketplace_config) = v_config_prima
      and (select margine_obiettivo_bps from public.marketplace_config where valida_fino is null and classe_venditore = 'privato') = 800
      and (select count(*) from information_schema.columns
           where table_schema = 'public' and table_name = 'public_partners') = 7
      and exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.orders'::regclass
                    and t.tgname = 'orders_partner_checkout_gate' and not t.tgisinternal));
end $$;

select id, descrizione, passed, detail
from esiti_12y
order by id;

rollback;
