-- VPM-015B3 — Annunci Accessori: pubblicazione automatica e moderazione
-- successiva (griglia 12zk).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori, annunci,
-- segnalazioni e oggetti Storage di prova vivono nella transazione e spariscono
-- con ROLLBACK. Dati SINTETICI.
--
-- Prova la migrazione 20261022091000:
--   - interruttore di pubblicazione spento di default, accensione riservata al
--     ruolo accessori_release, anche per i writer privilegiati; nessun ruolo di
--     rilascio assegnato dalla migrazione;
--   - categorie pubblicabili separate da `vendibile`: nessun backfill, fail-closed,
--     approvazione solo dal rilascio, mai per una categoria chiusa alla preparazione;
--   - pubblicazione automatica senza approvazione preventiva, con tutti i requisiti
--     verificati dal database (proprietario, dichiarazione, foto, termini vietati,
--     quantita, categoria, venditore, anti-elusione);
--   - snapshot pubblico separato dalla Cantina; aggiornamento controllato;
--   - letture pubbliche e firme Storage solo per annunci visibili;
--   - segnalazioni e azioni dell'amministrazione sul sistema di moderazione
--     esistente; oscuramento immediato; nessuna ripubblicazione autonoma;
--   - nessun percorso d'acquisto.
-- La concorrenza su sessioni reali e in 12zk_vpm_015b3_concorrenza.sh.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zk: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zk (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zk (id, descrizione, passed, detail)
  values (p_id, p_descrizione, coalesce(p_passed, false), coalesce(p_detail, ''));
$f$;

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

create function pg_temp.diretto(p_sql text, out esito text, out hint text) returns record
language plpgsql as $f$
begin
  execute p_sql;
  esito := 'NESSUN_ERRORE';
  hint := '';
exception when others then
  get stacked diagnostics hint = pg_exception_hint;
  esito := sqlstate;
end;
$f$;

create function pg_temp.esito(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Per le funzioni che tornano void: l'espressione (non l'istruzione) e avvolta in un testo.
create function pg_temp.esito_v(p_expr text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama('select to_jsonb((' || p_expr || ')::text)', p_uid, p_ruolo);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

create function pg_temp.dato(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns jsonb language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.dati;
end;
$f$;

-- Un numero letto con i privilegi del ruolo (RLS compresa).
create function pg_temp.conta(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns integer language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format('select to_jsonb((%s))', p_sql), p_uid, p_ruolo);
  return coalesce((v_c.dati #>> '{}')::integer, -1);
end;
$f$;

create function pg_temp.atteso(p_prezzo bigint, p_m integer, p_pp integer default 209, p_f integer default 25)
returns bigint language sql immutable as $f$
  select ceil((p_prezzo::numeric * (10000 + p_m) + p_f::numeric * 10000) / (10000 - p_pp))::bigint;
$f$;

create function pg_temp.categoria(p_slug text) returns uuid language sql as $f$
  select id from private.accessori_categorie where slug = p_slug;
$f$;

create function pg_temp.accessorio(p_uid uuid, p_id uuid, p_slug text, p_nome text, p_quantita integer,
                                   p_note text default '')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object(
         'categoria_id', %L, 'nome', %L, 'quantita', %s, 'note', %L, 'condizione', 'usato'))$q$,
    p_id, pg_temp.categoria(p_slug), p_nome, p_quantita, p_note), p_uid);
  if v_c.esito <> 'NESSUN_ERRORE' then
    raise exception 'fixture 12zk: accessorio % fallito (% %)', p_nome, v_c.esito, v_c.hint;
  end if;
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Una foto: oggetto nel bucket (superutente) + porta B1; restituisce il percorso.
create function pg_temp.foto(p_uid uuid, p_id uuid, p_n integer) returns text language plpgsql as $f$
declare
  v_path text := p_uid::text || '/' || p_id::text || '/12f20000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0') || '.webp';
  v_attuali text[];
begin
  insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', v_path)
  on conflict do nothing;
  select immagini into v_attuali from private.cantina_accessori where id = p_id;
  perform pg_temp.chiama(format('select public.cantina_accessori_immagini_imposta(%L, %L::text[])',
    p_id, coalesce(v_attuali, '{}'::text[]) || v_path), p_uid);
  return v_path;
end;
$f$;

create function pg_temp.salva(p_uid uuid, p_id uuid, p_dati text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_salva(%L, %L::jsonb)', p_id, p_dati), p_uid);
$f$;

create function pg_temp.pubblica(p_uid uuid, p_id uuid) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_pubblica(%L)', p_id), p_uid);
$f$;

create function pg_temp.transizione(p_uid uuid, p_id uuid, p_a text) returns text language sql as $f$
  select pg_temp.esito(format('select public.annunci_accessori_transizione(%L, %L)', p_id, p_a), p_uid);
$f$;

-- L'annuncio com'e visto dal venditore (porta elenca).
create function pg_temp.mio(p_uid uuid, p_id uuid) returns jsonb language sql as $f$
  select e from jsonb_array_elements(
    coalesce(pg_temp.dato('select public.annunci_accessori_elenca(false)', p_uid), '[]'::jsonb)) e
  where e ->> 'id' = p_id::text;
$f$;

create function pg_temp.stato(p_id uuid) returns text language sql as $f$
  select stato from private.annunci_accessori where id = p_id;
$f$;

-- L'annuncio compare nell'elenco pubblico anonimo?
create function pg_temp.in_vetrina(p_id uuid) returns boolean language sql as $f$
  select exists (
    select 1 from jsonb_array_elements(
      coalesce(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon'), '[]'::jsonb)) e
    where e ->> 'id' = p_id::text);
$f$;

create function pg_temp.dettaglio_pubblico(p_id uuid) returns jsonb language sql as $f$
  select pg_temp.dato(format('select public.annunci_accessori_pubblico_dettaglio(%L)', p_id), null, 'anon');
$f$;

-- L'anonimo puo firmare la foto (policy di SELECT su Storage)?
create function pg_temp.foto_pubblica(p_path text) returns boolean language sql as $f$
  select pg_temp.conta(format(
    $q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, p_path),
    null, 'anon') = 1;
$f$;

\set adm '12f20000-0000-4000-8000-0000000000e0'
\set ua '12f20000-0000-4000-8000-0000000000e1'
\set ub '12f20000-0000-4000-8000-0000000000e2'
\set fnd '12f20000-0000-4000-8000-0000000000e3'
\set ur '12f20000-0000-4000-8000-0000000000e4'
\set us '12f20000-0000-4000-8000-0000000000e5'
\set rel '12f20000-0000-4000-8000-0000000000e6'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zk.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zk.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zk.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zk.test', now(), '{}'::jsonb),
  (:'ur', 'ur@grid-12zk.test', now(), '{}'::jsonb),
  (:'us', 'us@grid-12zk.test', now(), '{}'::jsonb),
  (:'rel', 'rel@grid-12zk.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zk', date '1980-01-01'),
  (:'ua', 'ua-12zk', date '1980-01-01'),
  (:'ub', 'ub-12zk', date '1980-01-01'),
  (:'fnd', 'fnd-12zk', date '1980-01-01'),
  (:'ur', 'ur-12zk', date '1980-01-01'),
  (:'us', 'us-12zk', date '1980-01-01'),
  (:'rel', 'rel-12zk', date '1980-01-01');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12f20000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12f20000-0000-4000-8000-0000000000e1';
  c_b constant uuid := '12f20000-0000-4000-8000-0000000000e2';
  c_fnd constant uuid := '12f20000-0000-4000-8000-0000000000e3';
  c_r constant uuid := '12f20000-0000-4000-8000-0000000000e4';
  c_s constant uuid := '12f20000-0000-4000-8000-0000000000e5';
  c_rel constant uuid := '12f20000-0000-4000-8000-0000000000e6';
  v_snap_prima text;
  v_conf_prima text;
  v_release_prima integer;
  v_vendibili_prima integer;
  v_c record;
  v_s text;
  v_t text;
  v_u text;
  v_w text;
  v_n integer;
  v_json jsonb;
  v_chiavi text[];
  v_nota constant text := 'nota riservata 12zk';
  v_ia uuid := gen_random_uuid();   -- calici, 6, di A (con foto)
  v_ic uuid := gen_random_uuid();   -- calici, 4, di A (con foto)
  v_id uuid := gen_random_uuid();   -- calici, 2, di A (anti-elusione)
  v_ie uuid := gen_random_uuid();   -- cavatappi, 3, di A (categoria non pubblicabile)
  v_if uuid := gen_random_uuid();   -- calici, 2, di A, senza foto
  v_ig uuid := gen_random_uuid();   -- calici "Calice di prova rimosso", 2, di A (stesso nome del rimosso)
  v_ih uuid := gen_random_uuid();   -- calici "Altro nome", 2, di A
  v_ii uuid := gen_random_uuid();   -- calici, 2, di A (termine vietato)
  v_ib uuid := gen_random_uuid();   -- accessorio di B
  v_is uuid := gen_random_uuid();   -- accessorio di S
  v_pul uuid := gen_random_uuid();
  v_alt uuid := gen_random_uuid();
  v_reg uuid := gen_random_uuid();
  v_a1 uuid := gen_random_uuid();
  v_a2 uuid := gen_random_uuid();
  v_a3 uuid := gen_random_uuid();
  v_a4 uuid := gen_random_uuid();
  v_a5 uuid := gen_random_uuid();
  v_a6 uuid := gen_random_uuid();
  v_a7 uuid := gen_random_uuid();
  v_a8 uuid := gen_random_uuid();
  v_ab uuid := gen_random_uuid();
  v_as uuid := gen_random_uuid();
  v_f1 text; v_f2 text; v_f3 text; v_fb text; v_fs text; v_f4 text;
  v_rep uuid; v_rep2 uuid; v_rep3 uuid;
  v_cat_calici uuid;
  v_cat_rosso uuid;
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.cellar_slots), (select count(*) from public.payments),
    (select count(*) from public.proposals));
  v_conf_prima := (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
                     riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
                     ',' order by id) from public.marketplace_config);
  v_release_prima := (select count(*) from public.user_roles where role = 'accessori_release');
  v_vendibili_prima := (select count(*) from private.annunci_accessori_categorie where vendibile);

  -- Ruoli della fixture (dopo aver contato quelli gia presenti).
  insert into public.user_roles (user_id, role) values
    (c_adm, 'admin'), (c_a, 'user'), (c_b, 'user'), (c_fnd, 'admin'), (c_fnd, 'accessori_release'),
    (c_r, 'user'), (c_s, 'user'), (c_rel, 'accessori_release');

  -- =========================================================================
  -- STATO INIZIALE, RILASCIO E CATEGORIE
  -- =========================================================================

  -- 1: tutto spento e chiuso di default.
  perform pg_temp.registra(1, 'stato iniziale: pubblicazione spenta, pubblicazione_aperta=false, nessuna categoria pubblicabile (nessun backfill da vendibile, che resta un filtro di preparazione con categorie vendibili presenti), nessun ruolo accessori_release assegnato dalla migrazione, nessun annuncio',
    (select not pubblicazione_attiva from private.annunci_accessori_impostazioni)
    and not private.annunci_accessori_pubblicazione_aperta()
    and (select count(*) from private.annunci_accessori_categorie_pubblicabili) = 0
    and v_vendibili_prima > 0
    and v_release_prima = 0
    and (select count(*) from private.annunci_accessori) = 0
    and not exists (select 1 from private.accessori_categorie c where private.annuncio_accessorio_categoria_pubblicabile(c.id))
    and (select count(*) from private.annunci_accessori_snapshot) = 0,
    v_release_prima::text || ' ' || v_vendibili_prima::text);

  -- Cantina Accessori e preparazione accese (B1, B2) dal rilascio: serve per le bozze.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zk')$q$, c_fnd);
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_imposta(true, 'collaudo 12zk')$q$, c_fnd);

  perform pg_temp.accessorio(c_a, v_ia, 'calici-da-rosso', 'Calice di prova 12zk', 6, v_nota);
  perform pg_temp.accessorio(c_a, v_ic, 'calici-da-rosso', 'Calice due di prova 12zk', 4);
  perform pg_temp.accessorio(c_a, v_id, 'calici-da-rosso', 'Calice rimosso 12zk', 2);
  perform pg_temp.accessorio(c_a, v_ie, 'cavatappi', 'Cavatappi di prova 12zk', 3);
  perform pg_temp.accessorio(c_a, v_if, 'calici-da-rosso', 'Calice senza foto 12zk', 2);
  perform pg_temp.accessorio(c_a, v_ig, 'calici-da-rosso', 'Calice rimosso 12zk', 2);
  perform pg_temp.accessorio(c_a, v_ih, 'calici-da-rosso', 'Calice altro nome 12zk', 2);
  perform pg_temp.accessorio(c_a, v_ii, 'calici-da-rosso', 'Calice sciabola 12zk', 2);
  perform pg_temp.accessorio(c_b, v_ib, 'calici-da-rosso', 'Calice di B 12zk', 3);
  perform pg_temp.accessorio(c_s, v_is, 'calici-da-rosso', 'Calice di S 12zk', 3);
  perform pg_temp.accessorio(c_a, v_pul, 'pulizia', 'Detergente 12zk', 5);
  perform pg_temp.accessorio(c_a, v_alt, 'altri-accessori', 'Oggetto vario 12zk', 5);
  perform pg_temp.accessorio(c_a, v_reg, 'set-regalo', 'Set regalo 12zk', 5);
  v_f1 := pg_temp.foto(c_a, v_ia, 1);
  v_f2 := pg_temp.foto(c_a, v_ic, 1);
  v_f4 := pg_temp.foto(c_a, v_id, 1);
  perform pg_temp.foto(c_a, v_ie, 1);
  perform pg_temp.foto(c_a, v_ig, 1);
  perform pg_temp.foto(c_a, v_ih, 1);
  perform pg_temp.foto(c_a, v_ii, 1);
  v_fb := pg_temp.foto(c_b, v_ib, 1);
  v_fs := pg_temp.foto(c_s, v_is, 1);

  -- 2: bozza pronta, ma con l'interruttore di pubblicazione spento nulla si pubblica.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 2000, 'descrizione', 'Due calici in ottimo stato.', 'condizione', 'come_nuovo',
       'conforme', true))$q$, v_a1, v_ia), c_a);
  v_s := pg_temp.pubblica(c_a, v_a1);
  v_t := pg_temp.pubblica(c_adm, v_a1);
  v_u := (pg_temp.diretto(format($q$update private.annunci_accessori set stato = 'pubblicato' where id = %L$q$, v_a1))).hint;
  perform pg_temp.registra(2, 'interruttore spento: pubblica risponde pubblicazione_chiusa a chiunque (proprietario o altro utente); un UPDATE privilegiato a pubblicato e rifiutato dalla guardia (pubblicazione_chiusa); l''annuncio resta bozza; la vetrina pubblica e vuota',
    v_s = '42501:pubblicazione_chiusa' and v_t = '42501:pubblicazione_chiusa'
    and v_u = 'pubblicazione_chiusa'
    and pg_temp.stato(v_a1) = 'bozza'
    and (select count(*) from private.annunci_accessori_snapshot) = 0
    and pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')::text = '[]'
    and pg_temp.dettaglio_pubblico(v_a1) is null
    and pg_temp.dato(format('select public.annunci_accessori_pubblico_dettaglio(%L)', v_a1), c_a) is null,
    v_s || ' ' || v_t || ' ' || v_u);

  -- Le porte di rilascio B1/B2 lasciano il marcatore nella transazione (qui e una sola per tutta
  -- la griglia): lo si azzera per provare i writer privilegiati.
  perform set_config('vinae.accessori_rilascio', '', true);
  update private.annunci_accessori_impostazioni set aggiornato_da = null;

  -- 3: accensione della pubblicazione riservata al rilascio; spegnimento a ogni admin.
  v_s := pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'prova')$q$, c_a);
  v_t := pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'prova')$q$, c_rel);
  v_w := pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, '  ')$q$, c_fnd);
  perform pg_temp.registra(3, 'accendere la pubblicazione: utente rifiutato (42501), admin senza rilascio rifiutato (rilascio_non_autorizzato), rilascio senza ruolo admin rifiutato, motivo obbligatorio, UPDATE privilegiato diretto rifiutato; resta spenta',
    v_s like '42501:%' and v_t = '42501:rilascio_non_autorizzato' and v_u like '42501:%'
    and v_w = '22023:motivo_obbligatorio'
    and (pg_temp.diretto($q$update private.annunci_accessori_impostazioni set pubblicazione_attiva = true$q$)).hint = 'rilascio_non_autorizzato'
    and (select pubblicazione_attiva from private.annunci_accessori_impostazioni) = false
    and pg_temp.esito($q$select public.annunci_accessori_admin_stato()$q$, c_a) like '42501:%'
    and pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(false, 'x')$q$, c_a) like '42501:%',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'collaudo 12zk')$q$, c_fnd);
  perform pg_temp.registra(4, 'il ruolo di rilascio accende la pubblicazione (registro con motivo); admin_stato la dichiara accesa e conta 0 categorie pubblicabili; pubblicazione_aperta=true, ma senza categorie approvate la vetrina resta vuota',
    v_s = 'NESSUN_ERRORE:'
    and (select pubblicazione_attiva from private.annunci_accessori_impostazioni)
    and (select count(*) from private.accessori_registro where oggetto = 'annunci_pubblicazione' and motivo is not null) = 1
    and (pg_temp.dato('select public.annunci_accessori_admin_stato()', c_adm)) ->> 'pubblicazione_attiva' = 'true'
    and (pg_temp.dato('select public.annunci_accessori_admin_stato()', c_adm)) ->> 'categorie_pubblicabili' = '0'
    and private.annunci_accessori_pubblicazione_aperta()
    and pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')::text = '[]',
    v_s);

  -- 5: categoria non approvata: nessuna pubblicazione (anche se vendibile alla preparazione).
  v_s := pg_temp.pubblica(c_a, v_a1);
  v_t := (pg_temp.diretto(format($q$update private.annunci_accessori set stato = 'pubblicato' where id = %L$q$, v_a1))).hint;
  perform pg_temp.registra(5, 'categoria vendibile alla preparazione ma non approvata alla pubblicazione: pubblica risponde categoria_non_pubblicabile, anche per UPDATE privilegiato; l''annuncio resta bozza',
    v_s = '22023:categoria_non_pubblicabile' and v_t = 'categoria_non_pubblicabile'
    and pg_temp.stato(v_a1) = 'bozza',
    v_s || ' ' || v_t);

  -- 6: approvazione delle categorie: solo dal rilascio, genitore prima, mai una categoria chiusa.
  v_cat_calici := pg_temp.categoria('calici');
  v_cat_rosso := pg_temp.categoria('calici-da-rosso');
  v_s := pg_temp.esito(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''prova'')', v_cat_calici), c_adm);
  v_t := pg_temp.esito(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''prova'')', v_cat_rosso), c_fnd);
  v_u := pg_temp.esito(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''prova'')', pg_temp.categoria('pulizia')), c_fnd);
  v_w := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori_categorie_pubblicabili (categoria_id, pubblicabile, approvata_da) values (%L, true, %L)$q$,
    v_cat_calici, c_fnd))).hint;
  perform pg_temp.registra(6, 'approvazione categorie: admin senza rilascio rifiutato (rilascio_non_autorizzato); figlia prima del genitore rifiutata (categoria_genitore_non_approvata); categoria chiusa alla preparazione (Pulizia) mai approvabile (categoria_non_approvabile); INSERT privilegiato senza porta di rilascio rifiutato; nessuna riga creata',
    v_s = '42501:rilascio_non_autorizzato' and v_t = '22023:categoria_genitore_non_approvata'
    and v_u = '22023:categoria_non_approvabile' and v_w = 'rilascio_non_autorizzato'
    and (select count(*) from private.annunci_accessori_categorie_pubblicabili) = 0
    and (select count(*) from private.accessori_registro where oggetto = 'categoria_pubblicabile') = 0,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  v_s := pg_temp.esito(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zk'')', v_cat_calici), c_fnd);
  v_t := pg_temp.esito(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''collaudo 12zk'')', v_cat_rosso), c_fnd);
  perform pg_temp.registra(7, 'il rilascio approva Calici e poi Calici da rosso (registro con motivo); Cavatappi, vendibile alla preparazione, NON diventa pubblicabile; Set regalo, Pulizia e Altri accessori restano chiuse; l''elenco admin riporta vendibile/pubblicabile',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and private.annuncio_accessorio_categoria_pubblicabile(v_cat_rosso)
    and not private.annuncio_accessorio_categoria_pubblicabile(pg_temp.categoria('cavatappi'))
    and private.annuncio_accessorio_categoria_vendibile(pg_temp.categoria('cavatappi'))
    and not private.annuncio_accessorio_categoria_pubblicabile(pg_temp.categoria('set-regalo'))
    and not private.annuncio_accessorio_categoria_pubblicabile(pg_temp.categoria('pulizia'))
    and not private.annuncio_accessorio_categoria_pubblicabile(pg_temp.categoria('altri-accessori'))
    and (select count(*) from private.accessori_registro where oggetto = 'categoria_pubblicabile' and motivo is not null) = 2
    and (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_admin_categorie_pubblicazione()', c_adm)) e
         where (e ->> 'pubblicabile')::boolean) = 2
    and pg_temp.esito('select public.annunci_accessori_admin_categorie_pubblicazione()', c_a) like '42501:%',
    v_s || ' ' || v_t);

  -- =========================================================================
  -- PUBBLICAZIONE AUTOMATICA E REQUISITI
  -- =========================================================================

  -- 8: requisiti: proprietario, dichiarazione, foto, termini, categoria, articoli regolamentati.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1500, 'conforme', true))$q$, v_a2, v_if), c_a);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1500, 'conforme', true))$q$, v_a3, v_ie), c_a);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1500, 'conforme', false))$q$, v_a4, v_ih), c_a);
  v_s := pg_temp.pubblica(c_b, v_a1);
  v_t := pg_temp.pubblica(c_a, v_a2);
  v_u := pg_temp.pubblica(c_a, v_a3);
  v_w := pg_temp.pubblica(c_a, v_a4);
  perform pg_temp.registra(8, 'requisiti: annuncio di un altro proprietario (non_trovato), senza foto (foto_obbligatoria), categoria vendibile ma non approvata (categoria_non_pubblicabile), senza dichiarazione di conformita (dichiarazione_mancante); nessuno diventa pubblico',
    v_s = 'P0001:non_trovato' and v_t = '22023:foto_obbligatoria'
    and v_u = '22023:categoria_non_pubblicabile' and v_w = '22023:dichiarazione_mancante'
    and pg_temp.stato(v_a2) = 'bozza' and pg_temp.stato(v_a3) = 'bozza' and pg_temp.stato(v_a4) = 'bozza',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 9: articoli regolamentati: categorie chiuse e termini vietati.
  v_s := pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":1500,"conforme":true}', v_pul));
  v_t := pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":1500,"conforme":true}', v_reg));
  v_u := pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":1500,"conforme":true}', v_alt));
  v_w := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
       values (%L, %L, 1, 1500, 'nuovo')$q$, c_a, v_pul))).hint;
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1500, 'conforme', true, 'descrizione', 'Elegante SCIABOLA da champagne'))$q$, v_a5, v_ii), c_a);
  perform pg_temp.registra(9, 'articoli regolamentati: Pulizia, Set regalo e Altri accessori non hanno nemmeno una bozza (categoria_non_vendibile, anche per INSERT privilegiato); una descrizione con "sciabola" non si pubblica (contenuto_non_ammesso) e resta bozza',
    v_s = '22023:categoria_non_vendibile' and v_t = '22023:categoria_non_vendibile'
    and v_u = '22023:categoria_non_vendibile' and v_w = 'categoria_non_vendibile'
    and pg_temp.pubblica(c_a, v_a5) = '22023:contenuto_non_ammesso'
    and pg_temp.stato(v_a5) = 'bozza'
    and private.annuncio_accessorio_testo_vietato('una Sciabola') = 'sciabol'
    and private.annuncio_accessorio_testo_vietato('Calice per rosso') is null,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);
  perform pg_temp.transizione(c_a, v_a5, 'ritirato');

  -- 10: pubblicazione automatica del caso conforme: nessuna approvazione, snapshot, vetrina.
  select * into v_c from pg_temp.chiama(format('select public.annunci_accessori_pubblica(%L)', v_a1), c_a);
  v_json := pg_temp.dettaglio_pubblico(v_a1);
  select array(select jsonb_object_keys(v_json) order by 1) into v_chiavi;
  perform pg_temp.registra(10, 'annuncio conforme, categoria approvata, interruttore acceso: pubblica lo rende pubblicato subito (nessun passaggio di revisione), con snapshot (versione 0) e data di pubblicazione; compare nella vetrina anonima; il dettaglio pubblico ha le sole 13 chiavi attese, acquistabile=false, prezzo per l''acquirente = 22,73 euro per pezzo (10%) spedizione esclusa',
    v_c.esito = 'NESSUN_ERRORE'
    and v_c.dati ->> 'stato' = 'pubblicato' and (v_c.dati ->> 'pubblico') = 'true'
    and pg_temp.stato(v_a1) = 'pubblicato'
    and (select pubblicato_at from private.annunci_accessori where id = v_a1) is not null
    and (select versione from private.annunci_accessori where id = v_a1) = 0
    and (select versione from private.annunci_accessori_snapshot where annuncio_id = v_a1) = 0
    and pg_temp.in_vetrina(v_a1)
    and v_chiavi = array['acquistabile', 'aggiornato_at', 'categoria', 'condizione', 'descrizione', 'foto', 'id', 'marchio',
                         'nome', 'prezzo_acquirente_cents', 'pubblicato_at', 'quantita', 'venditore']
    and v_json ->> 'acquistabile' = 'false'
    and (v_json ->> 'prezzo_acquirente_cents')::bigint = pg_temp.atteso(2000, 1000)
    and (v_json ->> 'quantita')::int = 2
    and v_json ->> 'nome' = 'Calice di prova 12zk'
    and v_json #>> '{venditore,username}' = 'ua-12zk'
    and (select array(select jsonb_object_keys(v_json -> 'venditore') order by 1)) = array['avatar_url', 'username'],
    v_c.esito || ':' || v_c.hint);

  -- 11: privacy: niente note, id di Cantina, id del venditore, prezzo del venditore.
  perform pg_temp.registra(11, 'separazione privato/pubblico: il dettaglio e l''elenco pubblici non contengono la nota privata, l''id della Cantina come campo, l''id del venditore come campo ne il prezzo richiesto dal venditore; le foto sono percorsi dello snapshot',
    position(v_nota in v_json::text) = 0
    and not (v_json ? 'prezzo_unitario_cents') and not (v_json ? 'cantina_id') and not (v_json ? 'note')
    and v_json -> 'foto' = to_jsonb(array[v_f1])
    and position(v_nota in coalesce(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')::text, '')) = 0,
    '');

  -- 12: quantita: nessuna sovra-allocazione, nessun doppio annuncio, vincoli per ogni writer.
  v_s := pg_temp.salva(c_a, gen_random_uuid(), format('{"cantina_id":"%s","quantita":1,"prezzo_unitario_cents":900}', v_ia));
  v_t := pg_temp.salva(c_a, v_a1, '{"quantita":7}');
  v_u := (pg_temp.diretto(format($q$update private.annunci_accessori set quantita = 7 where id = %L$q$, v_a1))).hint;
  v_w := (pg_temp.diretto(format(
    $q$insert into private.annunci_accessori (seller_id, cantina_accessorio_id, quantita, prezzo_unitario_cents, condizione)
       values (%L, %L, 1, 1000, 'nuovo')$q$, c_a, v_ia))).esito;
  perform pg_temp.registra(12, 'quantita: secondo annuncio sullo stesso accessorio (annuncio_gia_aperto, 23505 per INSERT privilegiato); 7 su 6 posseduti rifiutato (quantita_non_disponibile); UPDATE privilegiato dell''offerta pubblicata rifiutato (annuncio_non_modificabile); impegnati 2, disponibili 4',
    v_s = '22023:annuncio_gia_aperto' and v_t = '22023:quantita_non_disponibile'
    and v_u = 'annuncio_non_modificabile' and v_w = '23505'
    and private.annuncio_accessorio_impegnati(v_ia) = 2
    and (pg_temp.mio(c_a, v_a1) ->> 'disponibili')::int = 4,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 13: la Cantina non toglie la merce sotto un annuncio pubblicato.
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"quantita":1}'::jsonb)$q$, v_ia), c_a);
  v_t := pg_temp.esito(format('select public.cantina_accessori_archivia(%L, true)', v_ia), c_a);
  v_u := pg_temp.esito(format('select public.cantina_accessori_rimuovi(%L)', v_ia), c_a);
  v_w := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L))$q$, v_ia, pg_temp.categoria('cavatappi')), c_a);
  perform pg_temp.registra(13, 'accessorio con annuncio pubblicato: quantita sotto l''impegnata (quantita_sotto_impegnata), archiviazione e rimozione (annuncio_aperto), cambio di categoria (annuncio_pubblicato) rifiutati; anche DELETE privilegiato',
    v_s = '22023:quantita_sotto_impegnata' and v_t = '22023:annuncio_aperto'
    and v_u = '22023:annuncio_aperto' and v_w = '22023:annuncio_pubblicato'
    and (pg_temp.diretto(format($q$delete from private.cantina_accessori where id = %L$q$, v_ia))).hint = 'annuncio_aperto',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 14: snapshot: una modifica privata della Cantina non altera l'annuncio pubblicato.
  perform pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('nome', 'Nome cambiato in Cantina 12zk', 'note', 'altra nota privata'))$q$, v_ia), c_a);
  v_f3 := pg_temp.foto(c_a, v_ia, 2);
  perform pg_temp.registra(14, 'una modifica privata della Cantina (nome, note, nuova foto) non altera lo snapshot ne il dettaglio pubblico: nome e foto pubblicati restano quelli del momento della pubblicazione',
    pg_temp.dettaglio_pubblico(v_a1) ->> 'nome' = 'Calice di prova 12zk'
    and pg_temp.dettaglio_pubblico(v_a1) -> 'foto' = to_jsonb(array[v_f1])
    and (select nome from private.annunci_accessori_snapshot where annuncio_id = v_a1) = 'Calice di prova 12zk'
    and (select nome from private.cantina_accessori where id = v_ia) = 'Nome cambiato in Cantina 12zk'
    and not pg_temp.foto_pubblica(v_f3),
    '');

  -- 15: aggiornamento controllato: versione, nuovo snapshot, requisiti ricontrollati.
  v_s := pg_temp.salva(c_a, v_a1, '{"prezzo_unitario_cents":2500,"descrizione":"Due calici, prezzo aggiornato."}');
  perform pg_temp.registra(15, 'aggiornamento controllato dell''annuncio pubblicato (salva): versione 1, snapshot rifatto dalla Cantina (nuovo nome e due foto), prezzo pubblico ricalcolato dal database (25,00 euro -> formula unica 10%), data di pubblicazione invariata',
    v_s = 'NESSUN_ERRORE:'
    and (select versione from private.annunci_accessori where id = v_a1) = 1
    and (select versione from private.annunci_accessori_snapshot where annuncio_id = v_a1) = 1
    and pg_temp.dettaglio_pubblico(v_a1) ->> 'nome' = 'Nome cambiato in Cantina 12zk'
    and pg_temp.dettaglio_pubblico(v_a1) -> 'foto' = to_jsonb(array[v_f1, v_f3])
    and (pg_temp.dettaglio_pubblico(v_a1) ->> 'prezzo_acquirente_cents')::bigint = pg_temp.atteso(2500, 1000)
    and pg_temp.stato(v_a1) = 'pubblicato'
    and pg_temp.foto_pubblica(v_f3)
    and position(v_nota in pg_temp.dettaglio_pubblico(v_a1)::text) = 0
    and position('altra nota privata' in pg_temp.dettaglio_pubblico(v_a1)::text) = 0,
    v_s);

  -- 16: l'aggiornamento riverifica i requisiti.
  v_s := pg_temp.salva(c_a, v_a1, '{"descrizione":"Ora in vendita anche la sciabola"}');
  v_t := pg_temp.salva(c_a, v_a1, '{"conforme":false}');
  perform pg_temp.registra(16, 'un aggiornamento che violerebbe un requisito e rifiutato e l''annuncio pubblicato resta com''era: termine vietato (contenuto_non_ammesso), dichiarazione ritirata (dichiarazione_mancante); versione invariata',
    v_s = '22023:contenuto_non_ammesso' and v_t = '22023:dichiarazione_mancante'
    and (select versione from private.annunci_accessori where id = v_a1) = 1
    and (select descrizione from private.annunci_accessori where id = v_a1) = 'Due calici, prezzo aggiornato.'
    and (select dichiarazione_conforme from private.annunci_accessori where id = v_a1),
    v_s || ' ' || v_t);

  -- =========================================================================
  -- STORAGE
  -- =========================================================================

  -- 17: le foto pubbliche: solo quelle dello snapshot di un annuncio visibile.
  perform pg_temp.registra(17, 'Storage: l''anonimo firma le sole foto dello snapshot di un annuncio visibile (due); la foto di un altro annuncio in bozza e quella di B non sono leggibili; il bucket resta privato; l''owner non cancella un file citato dallo snapshot (non cancellabile)',
    pg_temp.foto_pubblica(v_f1) and pg_temp.foto_pubblica(v_f3)
    and not pg_temp.foto_pubblica(v_f2) and not pg_temp.foto_pubblica(v_fb) and not pg_temp.foto_pubblica(v_f4)
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_b) = 1
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f2), c_b) = 0
    and exists (select 1 from storage.buckets where id = 'cantina-accessori-foto' and public = false)
    and not private.cantina_accessorio_media_cancellabile(v_f1),
    '');

  -- =========================================================================
  -- SEGNALAZIONI
  -- =========================================================================

  -- 18: segnalazione dell'annuncio.
  v_s := pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'', ''Costa troppo'')', v_a1), null, 'anon');
  v_t := pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'')', v_a1), c_a);
  v_u := pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Motivo inventato'')', v_a1), c_r);
  v_w := pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'')', v_a2), c_r);
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.segnalazione_annuncio_accessorio_invia(%L, ''Articolo alcolico o regolamentato'', ''Sembra una sciabola.''))', v_a1), c_r);
  v_rep := (v_c.dati #>> '{}')::uuid;
  perform pg_temp.registra(18, 'segnalazione: l''anonimo non puo (42501, nessuna porta anonima); il venditore non segnala il proprio annuncio; motivo fuori elenco rifiutato; una bozza non e segnalabile (non trovata); un utente segnala un annuncio visibile e la pratica nasce nel dominio reports esistente con bersaglio, etichetta, priorita alta e storia visibile',
    v_s like '42501:%' and v_t = '22023:' and v_u = '22023:' and v_w = 'P0001:'
    and v_c.esito = 'NESSUN_ERRORE'
    and (select target_tipo::text from public.reports where id = v_rep) = 'annuncio_accessorio'
    and (select target_annuncio_accessorio_id from public.reports where id = v_rep) = v_a1
    and (select target_label from public.reports where id = v_rep) = 'Nome cambiato in Cantina 12zk'
    and (select priorita::text from public.reports where id = v_rep) = 'alta'
    and (select reporter_id from public.reports where id = v_rep) = c_r
    and (select count(*) from public.report_events where report_id = v_rep and visibile) = 1
    and (select count(*) from public.my_reports) is not null
    and pg_temp.conta('select count(*) from public.my_reports', c_r) = 1
    and pg_temp.conta('select count(*) from public.my_reports', c_b) = 0
    and pg_temp.conta(format('select count(*) from public.moderation_report_queue where id = %L and target_id = %L', v_rep, v_a1), c_adm) = 1
    and pg_temp.conta('select count(*) from public.moderation_report_queue', c_r) = 0,
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 19: doppione, generico, vincolo di bersaglio.
  v_s := pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'')', v_a1), c_r);
  v_t := pg_temp.esito(format(
    $q$select public.segnalazione_invia('annuncio_accessorio'::public.report_target_tipo, %L, 'x', 'Prezzo anomalo')$q$, v_a1), c_r);
  v_u := (pg_temp.diretto(format(
    $q$insert into public.reports (codice, target_tipo, target_label, target_annuncio_accessorio_id, target_profile_id, motivo, priorita, reporter_id)
       values ('SEG-X-1', 'annuncio_accessorio', 'x', %L, %L, 'Prezzo anomalo', 'bassa', %L)$q$, v_a1, c_b, c_r))).esito;
  perform pg_temp.registra(19, 'una sola segnalazione aperta per utente e annuncio (P0001); la porta generica segnalazione_invia non conosce il nuovo bersaglio (P0001); due bersagli sulla stessa riga violano il vincolo (23514)',
    v_s = 'P0001:' and v_t = 'P0001:' and v_u = '23514',
    v_s || ' ' || v_t || ' ' || v_u);

  -- =========================================================================
  -- MODERAZIONE
  -- =========================================================================

  -- 20: l'azione sulla pratica oscura subito, registra audit e avvisa il venditore.
  v_s := pg_temp.esito_v(format('public.moderazione_sospensione(%L, ''Motivazione di prova'')', v_rep), c_a);
  v_t := pg_temp.esito_v(format('public.moderazione_sospensione(%L, ''Motivazione di prova'')', v_rep), c_rel);
  v_u := pg_temp.esito_v(format('public.moderazione_sospensione(%L, ''  '')', v_rep), c_adm);
  v_w := pg_temp.esito_v(format('public.moderazione_sospensione(%L, ''Foto da verificare: sospetta un articolo vietato'')', v_rep), c_adm);
  perform pg_temp.registra(20, 'oscuramento da segnalazione: utente e rilascio-senza-admin rifiutati (42501); motivazione obbligatoria; l''admin oscura l''annuncio con provvedimento, motivo, stato precedente, pratica risolta, riga di audit (target annuncio_accessorio) e notifica al venditore',
    v_s like '42501:%' and v_t like '42501:%' and v_u like '22023:%' and v_w = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'oscurato'
    and (select provvedimento from private.annunci_accessori where id = v_a1) = 'sospensione'
    and (select stato_prima from private.annunci_accessori where id = v_a1) = 'pubblicato'
    and (select stato_motivo from private.annunci_accessori where id = v_a1) like 'Foto da verificare%'
    and (select stato_aggiornato_da from private.annunci_accessori where id = v_a1) = c_adm
    and (select stato::text from public.reports where id = v_rep) = 'risolta'
    and exists (select 1 from public.audit_log where target_tipo = 'annuncio_accessorio' and target_id = v_a1
                and azione = 'sospensione' and attore_id = c_adm and report_id = v_rep)
    and exists (select 1 from public.notifications where recipient_id = c_a and event_type = 'accessori_annuncio_moderato'),
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 21: effetto immediato sulle nuove letture e sulle firme.
  perform pg_temp.registra(21, 'rimozione immediatamente efficace: l''annuncio sparisce da vetrina e dettaglio pubblico, le foto non sono piu firmabili dall''anonimo ne da un altro utente, ma restano ispezionabili dall''admin (non dall''utente ordinario); non e piu segnalabile; il venditore vede stato, provvedimento e motivo',
    not pg_temp.in_vetrina(v_a1) and pg_temp.dettaglio_pubblico(v_a1) is null
    and not pg_temp.foto_pubblica(v_f1) and not pg_temp.foto_pubblica(v_f3)
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_b) = 0
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_adm) = 1
    and pg_temp.conta(format($q$select count(*) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$, v_f1), c_r) = 0
    and pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'')', v_a1), c_b) = 'P0001:'
    and (pg_temp.mio(c_a, v_a1) ->> 'stato') = 'oscurato'
    and (pg_temp.mio(c_a, v_a1) #>> '{moderazione,provvedimento}') = 'sospensione'
    and (pg_temp.mio(c_a, v_a1) #>> '{moderazione,motivo}') like 'Foto da verificare%'
    and (pg_temp.mio(c_a, v_a1) ->> 'pubblico') = 'false'
    and not ((pg_temp.mio(c_a, v_a1) -> 'moderazione') ? 'stato_aggiornato_da')
    and not private.cantina_accessorio_media_cancellabile(v_f1),
    '');

  -- 22: l'annuncio oscurato non torna pubblico da solo, comunque il venditore agisca.
  v_s := pg_temp.pubblica(c_a, v_a1);
  v_t := pg_temp.salva(c_a, v_a1, '{"descrizione":"Descrizione ritoccata dopo la rimozione"}');
  v_u := pg_temp.transizione(c_a, v_a1, 'bozza');
  perform pg_temp.chiama(format($q$select public.cantina_accessori_salva(%L, jsonb_build_object('nome', 'Cambio nome dopo oscuramento'))$q$, v_ia), c_a);
  perform pg_temp.foto(c_a, v_ia, 3);
  v_w := pg_temp.pubblica(c_a, v_a1);
  perform pg_temp.registra(22, 'annuncio oscurato: ripetere pubblica, modificare la descrizione, cambiare nome o foto in Cantina, tornare in bozza non lo riaprono (transizione_non_ammessa / annuncio_non_modificabile); UPDATE privilegiato a pubblicato o sui campi di moderazione rifiutato (moderazione_riservata); resta oscurato e invisibile',
    v_s = '22023:transizione_non_ammessa' and v_t = '22023:annuncio_non_modificabile'
    and v_u = '22023:transizione_non_ammessa' and v_w = '22023:transizione_non_ammessa'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set stato = 'pubblicato' where id = %L$q$, v_a1))).hint = 'moderazione_riservata'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set provvedimento = null, stato_motivo = 'ok' where id = %L$q$, v_a1))).hint = 'moderazione_riservata'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set stato = 'modifiche_richieste' where id = %L$q$, v_a1))).hint = 'moderazione_riservata'
    and pg_temp.stato(v_a1) = 'oscurato' and not pg_temp.in_vetrina(v_a1)
    and (select provvedimento from private.annunci_accessori where id = v_a1) = 'sospensione',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 23: ripristino dell'amministrazione: lo snapshot giudicato, non le modifiche successive.
  v_s := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Verificato: conforme'')', v_a1), c_a);
  v_t := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''  '')', v_a1), c_adm);
  v_u := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''ripristina'', ''Verificato: conforme'')', v_a1), c_adm);
  perform pg_temp.registra(23, 'ripristino: solo l''admin, con motivazione; l''annuncio torna pubblicato con lo snapshot che l''admin aveva giudicato (nome e foto pubblicati, non le modifiche fatte in Cantina mentre era oscurato); provvedimento azzerato, audit del ripristino, notifica',
    v_s like '42501:%' and v_t like '22023:%' and v_u = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'pubblicato'
    and (select provvedimento from private.annunci_accessori where id = v_a1) is null
    and pg_temp.in_vetrina(v_a1)
    and pg_temp.dettaglio_pubblico(v_a1) ->> 'nome' = 'Nome cambiato in Cantina 12zk'
    and pg_temp.dettaglio_pubblico(v_a1) -> 'foto' = to_jsonb(array[v_f1, v_f3])
    and exists (select 1 from public.audit_log where target_tipo = 'annuncio_accessorio' and target_id = v_a1 and azione = 'ripristino')
    and pg_temp.foto_pubblica(v_f1),
    v_s || ' ' || v_t || ' ' || v_u);

  -- 24: richiesta di modifiche: non pubblico, il venditore corregge; senza cambiare nulla non si ripubblica.
  -- La Cantina torna prima a combaciare con quanto l'admin ha giudicato (snapshot).
  perform pg_temp.chiama(format($q$select public.cantina_accessori_salva(%L, jsonb_build_object('nome', 'Nome cambiato in Cantina 12zk'))$q$, v_ia), c_a);
  perform pg_temp.chiama(format('select public.cantina_accessori_immagini_imposta(%L, %L::text[])', v_ia, array[v_f1, v_f3]), c_a);
  v_s := pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''Descrivi meglio le condizioni'')', v_a1), c_adm);
  perform pg_temp.registra(24, 'richiesta di modifiche: l''annuncio diventa modifiche_richieste, sparisce dalla vetrina, il venditore vede il motivo; ripubblicare senza cambiare nulla e rifiutato (modifiche_non_effettuate)',
    v_s = 'NESSUN_ERRORE:' and pg_temp.stato(v_a1) = 'modifiche_richieste'
    and not pg_temp.in_vetrina(v_a1) and pg_temp.dettaglio_pubblico(v_a1) is null
    and (pg_temp.mio(c_a, v_a1) #>> '{moderazione,motivo}') = 'Descrivi meglio le condizioni'
    and (select hash_richiesta from private.annunci_accessori where id = v_a1) is not null
    and pg_temp.pubblica(c_a, v_a1) = '22023:modifiche_non_effettuate'
    and pg_temp.transizione(c_a, v_a1, 'bozza') = '22023:transizione_non_ammessa',
    v_s);

  v_s := pg_temp.salva(c_a, v_a1, '{"descrizione":"Due calici in ottime condizioni, usati solo due volte."}');
  v_t := pg_temp.pubblica(c_a, v_a1);
  perform pg_temp.registra(25, 'correzione: il venditore modifica la descrizione (consentito in modifiche_richieste) e ripubblica; torna pubblicato con snapshot rifatto e dettaglio aggiornato',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and pg_temp.stato(v_a1) = 'pubblicato' and pg_temp.in_vetrina(v_a1)
    and pg_temp.dettaglio_pubblico(v_a1) ->> 'descrizione' = 'Due calici in ottime condizioni, usati solo due volte.'
    and pg_temp.dettaglio_pubblico(v_a1) ->> 'nome' = 'Nome cambiato in Cantina 12zk',
    v_s || ' ' || v_t);

  -- 26: rimozione + anti-elusione.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1800, 'conforme', true, 'descrizione', 'Calice da rimuovere.'))$q$, v_a6, v_id), c_a);
  perform pg_temp.pubblica(c_a, v_a6);
  select * into v_c from pg_temp.chiama(format(
    'select to_jsonb(public.segnalazione_annuncio_accessorio_invia(%L, ''Descrizione ingannevole''))', v_a6), c_r);
  v_rep2 := (v_c.dati #>> '{}')::uuid;
  v_s := pg_temp.esito_v(format('public.moderazione_rimozione(%L, ''Articolo non conforme alle regole'')', v_rep2), c_adm);
  v_t := pg_temp.transizione(c_a, v_a6, 'ritirato');
  -- stesso accessorio: nuova bozza ammessa, pubblicazione bloccata
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1800, 'conforme', true))$q$, v_a7, v_id), c_a);
  -- stesso nome e categoria in un altro accessorio dello stesso venditore
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 1,
       'prezzo_unitario_cents', 1800, 'conforme', true))$q$, v_a8, v_ig), c_a);
  v_u := pg_temp.pubblica(c_a, v_a7);
  v_w := pg_temp.pubblica(c_a, v_a8);
  perform pg_temp.registra(26, 'rimozione e anti-elusione: l''admin rimuove (provvedimento rimozione, audit); il venditore ritira (il provvedimento resta); ricreare un annuncio per lo stesso accessorio (ripubblicazione_bloccata) o per un accessorio con lo stesso nome e categoria entro 90 giorni (ripubblicazione_bloccata) non lo rende pubblico; un accessorio con un altro nome resta pubblicabile',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and (select provvedimento from private.annunci_accessori where id = v_a6) = 'rimozione'
    and pg_temp.stato(v_a6) = 'ritirato'
    and v_u = '42501:ripubblicazione_bloccata' and v_w = '42501:ripubblicazione_bloccata'
    and pg_temp.stato(v_a7) = 'bozza' and pg_temp.stato(v_a8) = 'bozza'
    and (select stato::text from public.reports where id = v_rep2) = 'risolta'
    and exists (select 1 from public.audit_log where target_tipo = 'annuncio_accessorio' and target_id = v_a6 and azione = 'rimozione')
    and pg_temp.salva(c_a, v_a4, '{"conforme":true}') = 'NESSUN_ERRORE:'
    and pg_temp.pubblica(c_a, v_a4) = 'NESSUN_ERRORE:',
    v_s || ' ' || v_t || ' ' || v_u || ' ' || v_w);

  -- 27: aggravamento sospensione -> rimozione.
  perform pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''Sospeso per verifica'')', v_a4), c_adm);
  v_s := (select provvedimento from private.annunci_accessori where id = v_a4);
  perform pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''rimuovi'', ''Violazione confermata'')', v_a4), c_adm);
  perform pg_temp.registra(27, 'una sospensione si aggrava in rimozione senza riaprire nulla; l''annuncio resta oscurato e invisibile',
    v_s = 'sospensione' and pg_temp.stato(v_a4) = 'oscurato'
    and (select provvedimento from private.annunci_accessori where id = v_a4) = 'rimozione'
    and not pg_temp.in_vetrina(v_a4)
    and pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''richiedi_modifiche'', ''x'')', v_a4), c_adm) = 'P0001:'
    and pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''azione_inventata'', ''x'')', v_a4), c_adm) = '22023:dati_non_validi'
    and pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''x'')', gen_random_uuid()), c_adm) = 'P0001:',
    '');

  -- =========================================================================
  -- INTERRUTTORI E VISIBILITA CONDIZIONATA
  -- =========================================================================

  -- 28: spegnere la pubblicazione, revocare la categoria o sospendere il venditore nasconde subito.
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 3000, 'conforme', true))$q$, v_ab, v_ib), c_b);
  perform pg_temp.chiama(format(
    $q$select public.annunci_accessori_salva(%L, jsonb_build_object('cantina_id', %L, 'quantita', 2,
       'prezzo_unitario_cents', 3000, 'conforme', true))$q$, v_as, v_is), c_s);
  v_s := pg_temp.pubblica(c_b, v_ab);
  v_t := pg_temp.pubblica(c_s, v_as);
  v_n := (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')));
  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(false, 'spegnimento di prova')$q$, c_adm);
  perform pg_temp.registra(28, 'spegnere la pubblicazione (qualunque admin) nasconde subito tutto: vetrina vuota, dettaglio nullo, foto non firmabili, nuove pubblicazioni e segnalazioni chiuse; il venditore vede ancora il proprio annuncio come non pubblico',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:' and v_n = 3
    and not (select pubblicazione_attiva from private.annunci_accessori_impostazioni)
    and pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')::text = '[]'
    and pg_temp.dettaglio_pubblico(v_ab) is null
    and not pg_temp.foto_pubblica(v_fb)
    and pg_temp.pubblica(c_a, v_a7) = '42501:pubblicazione_chiusa'
    and pg_temp.esito(format('select public.segnalazione_annuncio_accessorio_invia(%L, ''Prezzo anomalo'')', v_ab), c_r) = 'P0001:'
    and (select (e ->> 'pubblico')::boolean from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_elenca()', c_b)) e
         where e ->> 'id' = v_ab::text) = false
    and pg_temp.esito($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'x')$q$, c_adm) = '42501:rilascio_non_autorizzato',
    v_s || ' ' || v_t || ' ' || v_n::text);

  perform pg_temp.chiama($q$select public.annunci_accessori_admin_pubblicazione_imposta(true, 'riaccensione di prova')$q$, c_fnd);
  v_s := pg_temp.pubblica(c_a, v_a7);   -- ancora bloccata dall'anti-elusione
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, false, ''revoca di prova'')', v_cat_rosso), c_adm);
  v_n := (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon')));
  v_t := pg_temp.pubblica(c_a, v_a7);
  perform pg_temp.chiama(format('select public.annunci_accessori_admin_categoria_pubblicabile_imposta(%L, true, ''ripristino di prova'')', v_cat_rosso), c_fnd);
  perform pg_temp.registra(29, 'riaccesa la pubblicazione tornano visibili gli annunci pubblicati; revocare una categoria (qualunque admin) nasconde subito i suoi annunci e ne blocca la pubblicazione; riapprovarla (solo rilascio) li riporta',
    (select count(*) from jsonb_array_elements(pg_temp.dato('select public.annunci_accessori_pubblici_elenca()', null, 'anon'))) = 3
    and v_n = 0 and v_t = '22023:categoria_non_pubblicabile'
    and pg_temp.in_vetrina(v_a1) and pg_temp.in_vetrina(v_ab) and pg_temp.in_vetrina(v_as),
    v_s || ' ' || v_n::text || ' ' || v_t);

  -- 30: venditore sospeso o rimosso: nessuna vetrina.
  update public.profiles set stato_utente = 'sospeso', stato_utente_at = now(), stato_utente_motivo = 'prova 12zk' where id = c_s;
  v_s := pg_temp.pubblica(c_s, v_as);
  v_n := case when pg_temp.in_vetrina(v_as) then 1 else 0 end;
  update public.profiles set stato_utente = 'attivo', stato_utente_at = now(), stato_utente_motivo = null where id = c_s;
  perform pg_temp.registra(30, 'venditore sospeso: il suo annuncio sparisce dalla vetrina (nessun blocco amministrativo sul venditore) e torna visibile quando e di nuovo attivo',
    v_n = 0 and pg_temp.in_vetrina(v_as),
    v_s || ' ' || v_n::text);

  -- 31: vetrina filtrata per categoria; paginazione.
  perform pg_temp.registra(31, 'elenco pubblico: filtro per categoria (slug o genitore), slug malformato vuoto, limite massimo 60, offset; l''ordine e dal piu recente',
    jsonb_array_length(pg_temp.dato(format('select public.annunci_accessori_pubblici_elenca(%L)', 'calici'), null, 'anon')) = 3
    and jsonb_array_length(pg_temp.dato(format('select public.annunci_accessori_pubblici_elenca(%L)', 'calici-da-rosso'), null, 'anon')) = 3
    and jsonb_array_length(pg_temp.dato(format('select public.annunci_accessori_pubblici_elenca(%L)', 'cavatappi'), null, 'anon')) = 0
    and jsonb_array_length(pg_temp.dato(format('select public.annunci_accessori_pubblici_elenca(%L)', 'x; drop table y'), null, 'anon')) = 0
    and jsonb_array_length(pg_temp.dato('select public.annunci_accessori_pubblici_elenca(null, 2, 0)', null, 'anon')) = 2
    and jsonb_array_length(pg_temp.dato('select public.annunci_accessori_pubblici_elenca(null, 2, 2)', null, 'anon')) = 1
    and jsonb_array_length(pg_temp.dato('select public.annunci_accessori_pubblici_elenca(null, 5000, 0)', null, 'anon')) = 3
    and jsonb_array_length(pg_temp.dato('select public.annunci_accessori_pubblici_elenca(null, -4, -4)', null, 'anon')) = 1,
    '');

  -- =========================================================================
  -- AMMINISTRAZIONE
  -- =========================================================================

  -- 32: coda e dettaglio admin.
  v_json := pg_temp.dato(format('select public.annunci_accessori_admin_dettaglio(%L)', v_a1), c_adm);
  perform pg_temp.registra(32, 'porte admin: elenco con filtri (pubblicati, segnalati, oscurati, modifiche) e dettaglio con snapshot, segnalazioni e storico delle decisioni; mai note private; riservate agli admin (utente, rilascio-senza-admin e anonimo rifiutati)',
    jsonb_array_length(pg_temp.dato($q$select public.annunci_accessori_admin_elenca('pubblicati')$q$, c_adm)) = 3
    and jsonb_array_length(pg_temp.dato($q$select public.annunci_accessori_admin_elenca('oscurati')$q$, c_adm)) = 1
    and jsonb_array_length(pg_temp.dato($q$select public.annunci_accessori_admin_elenca('segnalati')$q$, c_adm)) = 0
    and jsonb_array_length(pg_temp.dato($q$select public.annunci_accessori_admin_elenca('tutti')$q$, c_adm)) = 4
    and pg_temp.esito($q$select public.annunci_accessori_admin_elenca('inventato')$q$, c_adm) = '22023:dati_non_validi'
    and v_json ->> 'stato' = 'pubblicato' and v_json ->> 'visibile' = 'true'
    and jsonb_array_length(v_json -> 'segnalazioni') = 1 and jsonb_array_length(v_json -> 'storico') >= 3
    and position(v_nota in v_json::text) = 0
    and pg_temp.esito(format('select public.annunci_accessori_admin_dettaglio(%L)', v_a1), c_a) like '42501:%'
    and pg_temp.esito(format('select public.annunci_accessori_admin_dettaglio(%L)', v_a1), c_rel) like '42501:%'
    and pg_temp.esito($q$select public.annunci_accessori_admin_elenca()$q$, null, 'anon') like '42501:%'
    and pg_temp.esito_v(format('public.annunci_accessori_admin_modera(%L, ''oscura'', ''x'')', v_a1), c_a) like '42501:%',
    '');

  -- =========================================================================
  -- ESCALATION, SCRITTURE PRIVILEGIATE, SEPARAZIONE DAL MERCATO
  -- =========================================================================

  -- 33: nessuna scrittura diretta su snapshot, categorie, moderazione; nessuna lettura delle tabelle private.
  perform pg_temp.registra(33, 'scritture dirette rifiutate anche a un writer privilegiato: snapshot (INSERT, UPDATE, DELETE: snapshot_protetto), categoria pubblicabile senza rilascio, campi di moderazione; nessuna lettura delle tabelle private da authenticated/anon; versione non modificabile',
    (pg_temp.diretto(format($q$update private.annunci_accessori_snapshot set nome = 'x' where annuncio_id = %L$q$, v_a1))).hint = 'snapshot_protetto'
    and (pg_temp.diretto(format($q$delete from private.annunci_accessori_snapshot where annuncio_id = %L$q$, v_a1))).hint = 'snapshot_protetto'
    and (pg_temp.diretto(format(
      $q$insert into private.annunci_accessori_snapshot (annuncio_id, versione, nome, categoria_id, immagini) values (%L, 0, 'xx', %L, array['a'])$q$,
      v_a7, v_cat_rosso))).hint = 'snapshot_protetto'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set versione = 9 where id = %L$q$, v_a1))).hint = 'annuncio_immutabile'
    and (pg_temp.diretto(format($q$update private.annunci_accessori set oscurato_at = now() where id = %L$q$, v_a1))).hint = 'moderazione_riservata'
    and (pg_temp.diretto(format($q$delete from private.annunci_accessori_categorie_pubblicabili where categoria_id = %L$q$, v_cat_rosso))).esito = '42501'
    and pg_temp.esito('select count(*) from private.annunci_accessori', c_a) like '42501:%'
    and pg_temp.esito('select count(*) from private.annunci_accessori_snapshot', c_a) like '42501:%'
    and pg_temp.esito('select count(*) from private.annunci_accessori_categorie_pubblicabili', c_adm) like '42501:%'
    and pg_temp.esito('select count(*) from private.annunci_accessori', null, 'anon') like '42501:%',
    '');

  -- 34: nessun percorso d'acquisto.
  perform pg_temp.registra(34, 'visibile non vuol dire acquistabile: nessuna FK da orders, payments, proposals, listings o bottle_units verso annunci e snapshot (solo reports); nessuna colonna o funzione d''ordine, pagamento, checkout, carrello, prenotazione; lo stato dichiara vendite_attive=false; nessun stato acquistabile; conteggi di listings, ordini, vino e pagamenti invariati',
    not exists (
      select 1 from pg_constraint c
      where c.confrelid in ('private.annunci_accessori'::regclass, 'private.annunci_accessori_snapshot'::regclass)
        and c.contype = 'f'
        and c.conrelid not in ('private.annunci_accessori_snapshot'::regclass, 'public.reports'::regclass))
    and not exists (
      select 1 from pg_attribute a
      where a.attrelid in ('private.annunci_accessori'::regclass, 'private.annunci_accessori_snapshot'::regclass)
        and a.attnum > 0 and not a.attisdropped
        and a.attname ~* '(order|payment|pagament|listing|proposal|stripe|checkout|carrello|cart|prenot|payout|trasferimento)')
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and (p.proname like 'annunci\_accessori\_%' or p.proname like 'annuncio\_accessorio\_%')
        and (p.proname ~* '(checkout|ordine|ordini|pagament|acquist|carrello|prenot|payout|spedizione_reale)'
             or p.prosrc ~* '(public\.|private\.)(orders|payments|payouts|proposals|bottle_units|wines|cellar_slots|balance_)'
             or (p.prosrc ~* 'public\.listings' and p.proname !~ '^annunci_accessori_admin')))
    and (pg_temp.dato('select public.annunci_accessori_stato()', c_a)) ->> 'vendite_attive' = 'false'
    and not exists (select 1 from private.annunci_accessori where stato not in ('bozza', 'pubblicato', 'modifiche_richieste', 'oscurato', 'ritirato'))
    and not exists (select 1 from pg_constraint c where c.conrelid = 'private.annunci_accessori'::regclass
                    and c.conname = 'annunci_accessori_stato_ammesso'
                    and (pg_get_constraintdef(c.oid) ~ 'attivo|acquist|venduto|riservato'))
    and (pg_temp.dettaglio_pubblico(v_a1) ->> 'acquistabile') = 'false'
    and concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.cellar_slots), (select count(*) from public.payments),
        (select count(*) from public.proposals)) = v_snap_prima,
    '');

  -- 35: inventario delle funzioni.
  select array_agg(p.proname::text order by p.proname) into v_chiavi
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and (p.proname like 'annunci\_accessori\_%' or p.proname = 'segnalazione_annuncio_accessorio_invia')
    and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.registra(35, 'anonimo esegue solo le due letture pubbliche; segnalazione e porte admin per authenticated; letture stable, scritture volatili; tutte security definer con search_path vuoto; nessuna esecuzione a service_role',
    v_chiavi = array['annunci_accessori_pubblici_elenca', 'annunci_accessori_pubblico_dettaglio']
    and has_function_privilege('authenticated', 'public.segnalazione_annuncio_accessorio_invia(uuid,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.segnalazione_annuncio_accessorio_invia(uuid,text,text)', 'execute')
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname like 'annunci\_accessori\_%' or p.proname = 'segnalazione_annuncio_accessorio_invia')
        and (p.prosecdef is not true or p.proconfig is null or not ('search_path=""' = any (p.proconfig))
             or has_function_privilege('service_role', p.oid, 'execute')))
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 's' and p.proname in (
           'annunci_accessori_pubblici_elenca', 'annunci_accessori_pubblico_dettaglio',
           'annunci_accessori_admin_elenca', 'annunci_accessori_admin_dettaglio',
           'annunci_accessori_admin_categorie_pubblicazione')) = 5
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 'v' and p.proname in (
           'annunci_accessori_admin_modera', 'annunci_accessori_admin_pubblicazione_imposta',
           'annunci_accessori_admin_categoria_pubblicabile_imposta', 'segnalazione_annuncio_accessorio_invia')) = 4,
    coalesce(array_to_string(v_chiavi, ','), ''));

  -- 36: nessun ruolo di rilascio assegnato, configurazione economica e interruttori propri.
  perform pg_temp.registra(36, 'nessun ruolo accessori_release assegnato dalla migrazione (solo quelli della fixture); marketplace_config identica (vino 8% / 15%), margini accessori 1000 / 1500; interruttori B1 e B2 distinti da quello di pubblicazione; il catalogo 015A resta spento e protetto',
    v_release_prima = 0
    and (select count(*) from public.user_roles where role = 'accessori_release') = 2
    and (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
        riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
        ',' order by id) from public.marketplace_config) = v_conf_prima
    and (select margine_obiettivo_bps from private.marketplace_margini_dominio
         where valida_fino is null and dominio = 'accessori_enologici' and classe_venditore = 'privato') = 1000
    and (select visibilita_pubblica from private.accessori_impostazioni) = false
    and pg_temp.dato('select public.accessori_elenca()', null, 'anon')::text = '[]'
    and pg_temp.esito($q$select public.accessori_admin_visibilita_imposta(true, 'x')$q$, c_adm) = '42501:rilascio_non_autorizzato',
    '');

  -- 37: cancellazione dell'account: annunci e snapshot spariscono, la segnalazione resta.
  perform pg_temp.chiama(format(
    $q$select to_jsonb(public.segnalazione_annuncio_accessorio_invia(%L, 'Prezzo anomalo'))$q$, v_as), c_r);
  v_n := (select count(*) from public.reports where target_annuncio_accessorio_id = v_as);
  v_s := (pg_temp.diretto(format('delete from public.profiles where id = %L', c_s))).esito;
  perform pg_temp.registra(37, 'cancellazione account: il profilo con un annuncio pubblicato si cancella (nessun blocco), annuncio e snapshot spariscono, la segnalazione resta con etichetta ma senza riferimento (on delete set null)',
    v_n = 1 and v_s = 'NESSUN_ERRORE'
    and not exists (select 1 from private.annunci_accessori where id = v_as)
    and not exists (select 1 from private.annunci_accessori_snapshot where annuncio_id = v_as)
    and (select count(*) from public.reports where target_tipo = 'annuncio_accessorio' and target_annuncio_accessorio_id is null
         and target_label = 'Calice di S 12zk') = 1
    and not pg_temp.foto_pubblica(v_fs),
    v_n::text || ' ' || v_s);

  -- 38: dopo il ritiro il file torna cancellabile (se non citato dalla Cantina).
  perform pg_temp.chiama(format('select public.cantina_accessori_immagini_imposta(%L, ''{}''::text[])', v_ib), c_b);
  v_t := case when private.cantina_accessorio_media_cancellabile(v_fb) then 'cancellabile' else 'protetto' end;
  v_s := pg_temp.transizione(c_b, v_ab, 'ritirato');
  perform pg_temp.registra(38, 'ritirare un annuncio pubblicato lo toglie subito dalla vetrina e rilascia i suoi file: finche e pubblicato il file citato dallo snapshot e protetto anche se l''utente lo toglie dalla Cantina, a ritiro avvenuto diventa cancellabile; quello ancora in Cantina no',
    v_s = 'NESSUN_ERRORE:' and v_t = 'protetto'
    and not pg_temp.in_vetrina(v_ab) and pg_temp.dettaglio_pubblico(v_ab) is null
    and not pg_temp.foto_pubblica(v_fb)
    and private.cantina_accessorio_media_cancellabile(v_fb)
    and not private.cantina_accessorio_media_cancellabile(v_f1)
    and (select ritirato_at from private.annunci_accessori where id = v_ab) is not null,
    v_s || ' ' || v_t);

  -- 39: stato finale.
  perform pg_temp.registra(39, 'a fine griglia: nessun ordine, listing o pagamento creato; marketplace_config invariata; snapshot di ogni annuncio pubblicato presente (rete di sicurezza)',
    concat_ws('/', (select count(*) from public.listings), (select count(*) from public.orders),
        (select count(*) from public.wines), (select count(*) from public.bottle_units),
        (select count(*) from public.cellar_slots), (select count(*) from public.payments),
        (select count(*) from public.proposals)) = v_snap_prima
    and (select string_agg(concat_ws(':', id, classe_venditore, margine_obiettivo_bps,
        riferimento_stripe_percentuale_bps, riferimento_stripe_fisso_cents, valida_fino is null),
        ',' order by id) from public.marketplace_config) = v_conf_prima
    and not exists (
      select 1 from private.annunci_accessori a
      where a.stato = 'pubblicato'
        and not exists (select 1 from private.annunci_accessori_snapshot s where s.annuncio_id = a.id)),
    '');
end $$;

select id, descrizione, passed, detail
from esiti_12zk
order by id;

rollback;
