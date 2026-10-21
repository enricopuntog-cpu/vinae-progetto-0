-- VPM-015B1 — Cantina Accessori personale (griglia 12zi).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, accessori e oggetti
-- Storage di prova vivono nella transazione e spariscono con ROLLBACK. Dati
-- SINTETICI: nessun prodotto, marchio o prezzo reale.
--
-- Prova la migrazione 20261021090000 con cinque identita (anonimo, utente A,
-- utente B, admin senza rilascio, admin con ruolo di rilascio):
--   - due interruttori nel database spenti di default, accensione riservata al
--     ruolo di rilascio, spegnimento a ogni admin, registro;
--   - tassonomia leggibile per l'inserimento con il catalogo commerciale spento,
--     senza aprire bozze o visibilita del catalogo;
--   - inserimento: proprietario da auth.uid(), nasce privato, categoria della
--     tassonomia (foglia, attiva), nessuna categoria creabile dall'utente;
--   - isolamento fra utenti su tutte le porte; esposizione solo per scelta
--     esplicita; proiezione pubblica a campi chiusi; ritorno a privato,
--     archiviazione e interruttori fermano le nuove letture;
--   - Storage: bucket privato, cartella del proprietario, foto private
--     illeggibili ad altri e all'admin, firmabili da chiunque solo se esposte;
--   - nessun effetto su vino, bottiglie, annunci, ordini, pagamenti e sul
--     catalogo admin della 015A; nessun acquisto, ordine o pagamento.

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zi: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zi (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zi (id, descrizione, passed, detail)
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

-- Esito compatto "codice:hint" di una chiamata.
create function pg_temp.esito(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.esito || ':' || v_c.hint;
end;
$f$;

-- Il solo dato JSON di una chiamata riuscita (null se fallita).
create function pg_temp.dato(p_sql text, p_uid uuid, p_ruolo text default 'authenticated')
returns jsonb language plpgsql as $f$
declare v_c record;
begin
  select * into v_c from pg_temp.chiama(p_sql, p_uid, p_ruolo);
  return v_c.dati;
end;
$f$;

-- Righe visibili in storage.objects per il ruolo dato (RLS applicata).
create function pg_temp.vede_oggetto(p_percorso text, p_uid uuid, p_ruolo text default 'authenticated')
returns integer language plpgsql as $f$
begin
  return (pg_temp.dato(format(
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L$q$,
    p_percorso), p_uid, p_ruolo))::text::integer;
end;
$f$;

create function pg_temp.carica(p_percorso text, p_uid uuid, p_ruolo text default 'authenticated')
returns text language sql as $f$
  select pg_temp.esito(format(
    $q$with i as (insert into storage.objects (bucket_id, name) values ('cantina-accessori-foto', %L) returning 1) select to_jsonb(count(*)) from i$q$,
    p_percorso), p_uid, p_ruolo);
$f$;

create function pg_temp.cancella(p_percorso text, p_uid uuid, p_ruolo text default 'authenticated')
returns integer language plpgsql as $f$
begin
  -- Lo Storage API dichiara la cancellazione; qui lo si fa a mano per provare la sola policy.
  perform set_config('storage.allow_delete_query', 'true', true);
  return (pg_temp.dato(format(
    $q$with d as (delete from storage.objects where bucket_id = 'cantina-accessori-foto' and name = %L returning 1) select to_jsonb(count(*)) from d$q$,
    p_percorso), p_uid, p_ruolo))::text::integer;
end;
$f$;

\set adm '12ef0000-0000-4000-8000-0000000000e0'
\set ua '12ef0000-0000-4000-8000-0000000000e1'
\set ub '12ef0000-0000-4000-8000-0000000000e2'
\set fnd '12ef0000-0000-4000-8000-0000000000e3'
\set rel '12ef0000-0000-4000-8000-0000000000e4'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zi.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zi.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zi.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zi.test', now(), '{}'::jsonb),
  (:'rel', 'rel@grid-12zi.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zi', date '1980-01-01'),
  (:'ua', 'ua-12zi', date '1980-01-01'),
  (:'ub', 'ub-12zi', date '1980-01-01'),
  (:'fnd', 'fnd-12zi', date '1980-01-01'),
  (:'rel', 'rel-12zi', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'adm', 'admin'), (:'ua', 'user'), (:'ub', 'user'),
  (:'fnd', 'admin'), (:'fnd', 'accessori_release'), (:'rel', 'accessori_release');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12ef0000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12ef0000-0000-4000-8000-0000000000e1';
  c_b constant uuid := '12ef0000-0000-4000-8000-0000000000e2';
  c_fnd constant uuid := '12ef0000-0000-4000-8000-0000000000e3';
  c_rel constant uuid := '12ef0000-0000-4000-8000-0000000000e4';
  v_snap_prima text;
  v_cat_prima integer;
  v_c record;
  v_s text;
  v_t text;
  v_u text;
  v_n integer;
  v_i integer;
  v_sub_rosso uuid;
  v_sub_cavatappi uuid;
  v_sub_aeratori uuid;
  v_top_calici uuid;
  v_pulizia uuid;
  v_altri uuid;
  v_a1 uuid := gen_random_uuid();
  v_a2 uuid := gen_random_uuid();
  v_a3 uuid := gen_random_uuid();
  v_b1 uuid := gen_random_uuid();
  v_x uuid;
  v_item jsonb;
  v_chiavi text[];
  v_p_ok text;
  v_p_ok2 text;
  v_p_b text;
  v_p_ax text;
  v_cat_id uuid;
  v_cat_slug constant text := 'catalogo-prova-12zi';
  v_md5_prima text;
  v_pub_a constant text := 'select public.cantina_accessori_pubblica_profilo(%L::uuid)';
  v_w text;
  v_casi text[][];
  v_caso text[];
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.cellar_slots), (select count(*) from public.payments),
    (select count(*) from public.marketplace_config));
  v_cat_prima := (select count(*) from private.accessori_categorie);

  select id into v_sub_rosso from private.accessori_categorie where slug = 'calici-da-rosso';
  select id into v_sub_cavatappi from private.accessori_categorie where slug = 'cavatappi';
  select id into v_sub_aeratori from private.accessori_categorie where slug = 'aeratori';
  select id into v_top_calici from private.accessori_categorie where slug = 'calici';
  select id into v_pulizia from private.accessori_categorie where slug = 'pulizia';
  select id into v_altri from private.accessori_categorie where slug = 'altri-accessori';

  -- 1: stato iniziale: due interruttori spenti, nessun accessorio, bucket privato.
  perform pg_temp.registra(1, 'due interruttori spenti di default (una sola riga); nessun accessorio personale; bucket Storage privato solo WebP',
    (select count(*) from private.cantina_accessori_impostazioni) = 1
    and (select funzione_attiva or visibilita_pubblica from private.cantina_accessori_impostazioni) = false
    and (select count(*) from private.cantina_accessori) = 0
    and exists (select 1 from storage.buckets
                where id = 'cantina-accessori-foto' and public = false
                  and file_size_limit = 2097152 and allowed_mime_types = array['image/webp']),
    '');

  -- 2: nessun accesso diretto a tabelle e viste per i ruoli client.
  v_s := pg_temp.esito('select to_jsonb(count(*)) from private.cantina_accessori', null, 'anon');
  v_t := pg_temp.esito('select to_jsonb(count(*)) from private.cantina_accessori', c_a);
  v_u := pg_temp.esito('select to_jsonb(count(*)) from private.cantina_accessori_pubblica', c_a);
  perform pg_temp.registra(2, 'nessuna lettura diretta di tabella e vista (anonimo e utente); nessuna tabella o vista in public',
    v_s like '42501:%' and v_t like '42501:%' and v_u like '42501:%'
    and pg_temp.esito('select to_jsonb(count(*)) from private.cantina_accessori_impostazioni', c_a) like '42501:%'
    and to_regclass('public.cantina_accessori') is null
    and to_regclass('public.public_cantina_accessori') is null,
    v_s || ' ' || v_t || ' ' || v_u);

  -- 3: funzione spenta: nessun uso per i non admin; letture vuote; scritture rifiutate.
  perform pg_temp.registra(3, 'funzione spenta: stato abilitata=false, categorie ed elenco vuoti, salva rifiutata (funzione_non_attiva), porta pubblica vuota; anonimo non esegue le porte personali',
    (pg_temp.dato('select public.cantina_accessori_stato()', c_a)) ->> 'abilitata' = 'false'
    and pg_temp.dato('select public.cantina_accessori_categorie_elenca()', c_a)::text = '[]'
    and pg_temp.dato('select public.cantina_accessori_elenca()', c_a)::text = '[]'
    and pg_temp.esito(format(
      $q$select public.cantina_accessori_salva(%L, '{"categoria_id":"%s","nome":"Prova spenta"}'::jsonb)$q$, v_a1, v_sub_rosso), c_a)
        = '42501:funzione_non_attiva'
    and pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text = '[]'
    and pg_temp.esito('select public.cantina_accessori_stato()', null, 'anon') like '42501:%'
    and pg_temp.esito('select public.cantina_accessori_elenca()', null, 'anon') like '42501:%'
    and pg_temp.esito('select public.cantina_accessori_categorie_elenca()', null, 'anon') like '42501:%',
    '');

  -- 4: un admin reale puo verificare la funzione anche da spenta (collaudo in produzione).
  perform pg_temp.registra(4, 'admin reale: la funzione risulta usabile anche da spenta (collaudo); l''utente comune no',
    (pg_temp.dato('select public.cantina_accessori_stato()', c_adm)) ->> 'abilitata' = 'true'
    and (pg_temp.dato('select public.cantina_accessori_stato()', c_b)) ->> 'abilitata' = 'false'
    and (pg_temp.dato('select public.cantina_accessori_stato()', c_adm)) ->> 'esposti_visibili' = 'false',
    '');

  -- 5: accensione riservata al rilascio; spegnimento a ogni admin; registro.
  v_s := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', true, 'prova')$q$, c_a);
  v_t := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', true, 'prova')$q$, c_adm);
  v_u := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', true, 'prova')$q$, c_rel);
  perform pg_temp.registra(5, 'accendere: utente rifiutato, admin senza rilascio rifiutato (rilascio_non_autorizzato), ruolo di rilascio senza admin rifiutato',
    v_s like '42501:%' and v_t = '42501:rilascio_non_autorizzato' and v_u like '42501:%'
    and (select funzione_attiva from private.cantina_accessori_impostazioni) = false,
    v_s || ' ' || v_t || ' ' || v_u);

  v_s := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', true, '  ')$q$, c_fnd);
  v_t := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('altro', true, 'prova')$q$, c_fnd);
  v_u := (pg_temp.diretto($q$update private.cantina_accessori_impostazioni set funzione_attiva = true$q$)).esito || ':' ||
         (pg_temp.diretto($q$update private.cantina_accessori_impostazioni set funzione_attiva = true$q$)).hint;
  perform pg_temp.registra(6, 'motivo obbligatorio, interruttore ignoto rifiutato; UPDATE diretto (privilegiato) senza dichiarazione di rilascio rifiutato dal trigger',
    v_s = '22023:motivo_obbligatorio' and v_t = '22023:dati_non_validi'
    and v_u = '42501:rilascio_non_autorizzato'
    and (select funzione_attiva from private.cantina_accessori_impostazioni) = false,
    v_s || ' ' || v_t || ' ' || v_u);

  v_s := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', true, 'collaudo 12zi')$q$, c_fnd);
  v_t := pg_temp.esito($q$select public.cantina_accessori_admin_imposta('funzione', false, 'spegnimento 12zi')$q$, c_adm);
  v_n := (select count(*) from private.accessori_registro where oggetto = 'cantina_accessori');
  perform pg_temp.registra(7, 'ruolo di rilascio accende (registrato); qualunque admin spegne; il registro conta due azioni; il catalogo centrale resta spento',
    v_s = 'NESSUN_ERRORE:' and v_t = 'NESSUN_ERRORE:'
    and (select funzione_attiva from private.cantina_accessori_impostazioni) = false
    and v_n = 2
    and (select visibilita_pubblica from private.accessori_impostazioni) = false,
    v_s || ' ' || v_t || ' ' || v_n);

  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'riaccensione 12zi')$q$, c_fnd);

  -- 8: tassonomia per l'inserimento con il catalogo commerciale spento.
  v_item := pg_temp.dato('select public.cantina_accessori_categorie_elenca()', c_a);
  select array(select jsonb_object_keys(v_item -> 0) order by 1) into v_chiavi;
  perform pg_temp.registra(8, 'catalogo spento + funzione accesa: la tassonomia (10 categorie, 3 sottocategorie dei calici) e leggibile per inserire; il catalogo pubblico resta vuoto e chiuso',
    jsonb_array_length(v_item) = 10
    and (select jsonb_array_length(e -> 'sottocategorie') from jsonb_array_elements(v_item) e where e ->> 'slug' = 'calici') = 3
    and v_chiavi = array['id', 'nome', 'slug', 'sottocategorie']
    and pg_temp.dato('select public.accessori_categorie_elenca()', c_a)::text = '[]'
    and pg_temp.dato('select public.accessori_elenca()', null, 'anon')::text = '[]'
    and (select dati is null from pg_temp.chiama($q$select public.accessori_dettaglio('x')$q$, c_a))
    and (select visibilita_pubblica from private.accessori_impostazioni) = false,
    v_chiavi::text);

  -- 9: creazione: proprietario da auth.uid(), nasce privato, quantita predefinita.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object(
      'categoria_id', %L, 'nome', 'Calice di prova 12zi',
      'descrizione', 'Descrizione sintetica pubblicabile.', 'marchio', 'Marca Prova',
      'condizione', 'usato', 'quantita', 4, 'note', 'nota riservata 12zi'))$q$, v_a1, v_sub_rosso), c_a);
  perform pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L, 'nome', 'Detergente 12zi'))$q$, v_a2, v_pulizia), c_a);
  perform pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L, 'nome', 'Oggetto vario 12zi'))$q$, v_a3, v_altri), c_a);
  perform pg_temp.registra(9, 'A crea: proprietario = A (da auth.uid), nasce privato, quantita come inviata o 1, categoria foglia (sottocategoria, categoria senza figli, fallback "Altri accessori")',
    v_c.esito = 'NESSUN_ERRORE'
    and v_c.dati ->> 'visibilita' = 'privata' and (v_c.dati ->> 'quantita')::int = 4
    and v_c.dati #>> '{categoria,slug}' = 'calici-da-rosso' and v_c.dati #>> '{categoria,genitore_slug}' = 'calici'
    and (select owner_id from private.cantina_accessori where id = v_a1) = c_a
    and (select visibilita from private.cantina_accessori where id = v_a1) = 'privata'
    and (select quantita from private.cantina_accessori where id = v_a2) = 1
    and (select count(*) from private.cantina_accessori where owner_id = c_a) = 3,
    v_c.esito || ':' || v_c.hint);

  -- Ripetere la stessa richiesta (stesso id) non duplica.
  perform pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L, 'nome', 'Calice di prova 12zi'))$q$, v_a1, v_sub_rosso), c_a);
  perform pg_temp.registra(10, 'idempotenza: ripetere la creazione con lo stesso id aggiorna senza duplicare',
    (select count(*) from private.cantina_accessori where owner_id = c_a) = 3
    and (select quantita from private.cantina_accessori where id = v_a1) = 4,
    '');

  -- 11: regole di categoria.
  v_s := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Senza sotto'))$q$, v_top_calici), c_a);
  v_t := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Categoria ignota'))$q$, gen_random_uuid()), c_a);
  v_u := pg_temp.esito($q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('nome', 'Senza categoria'))$q$, c_a);
  perform pg_temp.registra(11, 'categoria: sottocategoria obbligatoria dove esiste; id ignoto rifiutato; categoria assente rifiutata',
    v_s = '22023:sottocategoria_obbligatoria' and v_t = '22023:categoria_non_valida'
    and v_u = '22023:categoria_obbligatoria',
    v_s || ' ' || v_t || ' ' || v_u);

  -- 12: categoria disattivata o con genitore disattivato non e scelta; la taxonomy la omette.
  update private.accessori_categorie set attiva = false where slug in ('cavatappi', 'decanter');
  v_s := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Disattiva'))$q$, v_sub_cavatappi), c_a);
  v_t := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Genitore disattivo'))$q$, v_sub_aeratori), c_a);
  v_item := pg_temp.dato('select public.cantina_accessori_categorie_elenca()', c_a);
  perform pg_temp.registra(12, 'categoria disattivata o con genitore disattivato non e selezionabile e non compare nella tassonomia',
    v_s = '22023:categoria_non_valida' and v_t = '22023:categoria_non_valida'
    and not (v_item::text like '%"cavatappi"%') and not (v_item::text like '%"decanter"%'),
    v_s || ' ' || v_t);
  update private.accessori_categorie set attiva = true where slug in ('cavatappi', 'decanter');

  -- 13: rinominare una categoria non rompe il legame (FK su id).
  update private.accessori_categorie set nome = 'Rosso rinominato 12zi' where id = v_sub_rosso;
  v_item := pg_temp.dato('select public.cantina_accessori_elenca()', c_a);
  perform pg_temp.registra(13, 'rinominare la categoria non rompe il legame: l''accessorio la mostra col nuovo nome, stesso id',
    exists (select 1 from jsonb_array_elements(v_item) e
            where e ->> 'id' = v_a1::text and e #>> '{categoria,nome}' = 'Rosso rinominato 12zi'
              and e #>> '{categoria,id}' = v_sub_rosso::text),
    '');
  update private.accessori_categorie set nome = 'Calici da rosso' where id = v_sub_rosso;

  -- 14: l'utente non crea categorie.
  v_s := pg_temp.esito(
    $q$insert into private.accessori_categorie (slug, nome) values ('mia-categoria-12zi', 'Mia categoria')$q$, c_a);
  v_t := pg_temp.esito(
    $q$select public.accessori_admin_categoria_salva(null, '{"slug":"mia-categoria-12zi","nome":"Mia categoria"}'::jsonb)$q$, c_a);
  v_u := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_nuova', 'Mia categoria', 'categoria_id', %L, 'nome', 'Prova'))$q$, v_sub_rosso), c_a);
  perform pg_temp.registra(14, 'nessun utente crea categorie: INSERT diretto, porta admin e campo "categoria_nuova" rifiutati; la tassonomia non cambia',
    v_s like '42501:%' and v_t like '42501:%' and v_u = '22023:campo_sconosciuto'
    and (select count(*) from private.accessori_categorie) = v_cat_prima
    and not has_table_privilege('authenticated', 'private.accessori_categorie', 'insert')
    and not has_table_privilege('anon', 'private.accessori_categorie', 'insert'),
    v_s || ' ' || v_t || ' ' || v_u);

  -- 15: validazione dei campi.
  v_casi := array[
    array['{"nome":"a"}', '22023:nome_non_valido'],
    array['{"nome":"Prova","quantita":0}', '22023:quantita_non_valida'],
    array['{"nome":"Prova","quantita":1000}', '22023:quantita_non_valida'],
    array['{"nome":"Prova","quantita":1.5}', '22023:quantita_non_valida'],
    array['{"nome":"Prova","quantita":"3"}', '22023:quantita_non_valida'],
    array['{"nome":"Prova","condizione":"rotto"}', '22023:condizione_non_valida'],
    array['{"nome":"Prova","prezzo":10}', '22023:campo_sconosciuto'],
    array['{"nome":"Prova","owner_id":"12ef0000-0000-4000-8000-0000000000e2"}', '22023:campo_sconosciuto'],
    array['{"nome":"Prova","visibilita":"cantina_pubblica"}', '22023:campo_sconosciuto'],
    array['{"nome":"Prova","immagini":["x"]}', '22023:campo_sconosciuto'],
    array['{"nome":"Prova\u0007"}', '22023:nome_non_valido'],
    array['{"nome":["Prova"]}', '22023:nome_non_valido'],
    array['[]', '22023:dati_non_validi']
  ];
  v_n := 0;
  foreach v_caso slice 1 in array v_casi loop
    v_s := pg_temp.esito(format(
      $q$select public.cantina_accessori_salva(gen_random_uuid(), (%L::jsonb) || jsonb_build_object('categoria_id', %L))$q$,
      v_caso[1], v_sub_rosso), c_a);
    if v_s = v_caso[2] then v_n := v_n + 1; else raise notice 'caso % -> % (atteso %)', v_caso[1], v_s, v_caso[2]; end if;
  end loop;
  v_s := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Prova', 'descrizione', repeat('x', 1001)))$q$, v_sub_rosso), c_a);
  if v_s = '22023:descrizione_non_valida' then v_n := v_n + 1; end if;
  v_s := pg_temp.esito(format(
    $q$select public.cantina_accessori_salva(null, jsonb_build_object('categoria_id', %L, 'nome', 'Prova'))$q$, v_sub_rosso), c_a);
  if v_s = '22023:dati_non_validi' then v_n := v_n + 1; end if;
  perform pg_temp.registra(15, 'validazione: nome, quantita (0, 1000, 1.5, testo), condizione, prezzo/owner_id/visibilita/immagini non ammessi alla creazione, caratteri di controllo, descrizione lunga, id nullo (15 prove)',
    v_n = 15 and (select count(*) from private.cantina_accessori where owner_id = c_a) = 3, v_n::text);

  -- 16: modifica.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, '{"quantita":6,"nome":"Calice di prova 12zi bis","condizione":"come_nuovo"}'::jsonb)$q$, v_a1), c_a);
  perform pg_temp.registra(16, 'A modifica il proprio accessorio (quantita, nome, condizione); i campi non inviati restano (note, categoria)',
    v_c.esito = 'NESSUN_ERRORE' and (v_c.dati ->> 'quantita')::int = 6
    and v_c.dati ->> 'nome' = 'Calice di prova 12zi bis' and v_c.dati ->> 'condizione' = 'come_nuovo'
    and v_c.dati ->> 'note' = 'nota riservata 12zi' and v_c.dati #>> '{categoria,slug}' = 'calici-da-rosso',
    v_c.esito || ':' || v_c.hint);

  -- 17: isolamento fra utenti.
  perform pg_temp.chiama(format(
    $q$select public.cantina_accessori_salva(%L, jsonb_build_object('categoria_id', %L, 'nome', 'Accessorio di B 12zi'))$q$, v_b1, v_pulizia), c_b);
  v_item := pg_temp.dato('select public.cantina_accessori_elenca()', c_b);
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"nome":"Rubato"}'::jsonb)$q$, v_a1), c_b);
  v_t := pg_temp.esito(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_b);
  v_u := pg_temp.esito(format($q$select public.cantina_accessori_archivia(%L, true)$q$, v_a1), c_b);
  perform pg_temp.registra(17, 'B non vede ne modifica gli accessori di A: elenco proprio, salva/visibilita/archivia/rimuovi/immagini su id altrui rispondono non_trovato; A invariato',
    jsonb_array_length(v_item) = 1 and v_item -> 0 ->> 'id' = v_b1::text
    and v_s = 'P0001:non_trovato' and v_t = 'P0001:non_trovato' and v_u = 'P0001:non_trovato'
    and pg_temp.esito(format($q$select public.cantina_accessori_rimuovi(%L)$q$, v_a1), c_b) = 'P0001:non_trovato'
    and pg_temp.esito(format($q$select public.cantina_accessori_immagini_imposta(%L, '{}'::text[])$q$, v_a1), c_b) = 'P0001:non_trovato'
    and (select nome from private.cantina_accessori where id = v_a1) = 'Calice di prova 12zi bis'
    and (select visibilita from private.cantina_accessori where id = v_a1) = 'privata'
    and (select archiviato_at from private.cantina_accessori where id = v_a1) is null
    and (select count(*) from private.cantina_accessori where owner_id = c_a) = 3,
    v_s || ' ' || v_t || ' ' || v_u);

  -- 18: nasce privato anche per i privilegiati; esposizione solo dalla porta.
  v_s := (pg_temp.diretto(format(
    $q$update private.cantina_accessori set visibilita = 'cantina_pubblica' where id = %L$q$, v_a1))).esito;
  v_t := (pg_temp.diretto(format(
    $q$update private.cantina_accessori set visibilita = 'cantina_pubblica' where id = %L$q$, v_a1))).hint;
  v_u := (pg_temp.diretto(format(
    $q$insert into private.cantina_accessori (owner_id, categoria_id, nome, visibilita) values (%L, %L, 'Nato pubblico', 'cantina_pubblica')$q$, c_a, v_pulizia))).hint;
  perform pg_temp.registra(18, 'esposizione richiede la scelta esplicita: UPDATE diretto e INSERT con visibilita pubblica rifiutati anche ai privilegiati (esposizione_non_autorizzata)',
    v_s = '42501' and v_t = 'esposizione_non_autorizzata' and v_u = 'esposizione_non_autorizzata'
    and (select count(*) from private.cantina_accessori where visibilita <> 'privata') = 0,
    v_s || ' ' || v_t || ' ' || v_u);

  -- 19: nessun effetto pubblico prima della scelta; scelta esplicita ma interruttore pubblico spento.
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'altro')$q$, v_a1), c_a);
  v_item := pg_temp.dato(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a);
  perform pg_temp.registra(19, 'A espone esplicitamente: valore ignoto rifiutato; esposto ma con visibilita pubblica spenta la porta pubblica resta vuota (anonimo e altro utente)',
    v_s = '22023:visibilita_non_valida' and v_item ->> 'visibilita' = 'cantina_pubblica'
    and pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text = '[]'
    and pg_temp.dato(format(v_pub_a, c_a), c_b)::text = '[]',
    v_s);

  -- 20: accensione della visibilita: solo gli esposti, a campi chiusi.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'collaudo visibilita 12zi')$q$, c_fnd);
  v_item := pg_temp.dato(format(v_pub_a, c_a), null, 'anon');
  select array(select jsonb_object_keys(v_item -> 0) order by 1) into v_chiavi;
  perform pg_temp.registra(20, 'visibilita accesa: l''anonimo vede SOLO l''accessorio esposto di A (non gli altri due privati), con campi chiusi; niente note, proprietario o legame col catalogo',
    jsonb_array_length(v_item) = 1 and v_item -> 0 ->> 'id' = v_a1::text
    and v_chiavi = array['categoria_nome', 'categoria_slug', 'condizione', 'descrizione', 'genitore_nome',
                         'id', 'immagini', 'marchio', 'nome', 'quantita']
    and v_item::text not like '%nota riservata%' and v_item::text not like '%' || c_a::text || '%'
    and v_item::text not like '%catalogo%'
    and jsonb_array_length(pg_temp.dato(format(v_pub_a, c_a), c_b)) = 1
    and pg_temp.dato(format(v_pub_a, c_b), null, 'anon')::text = '[]',
    v_chiavi::text);

  -- 21: ritorno a privato, archiviazione, ripristino.
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'privata')$q$, v_a1), c_a);
  v_s := pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text;
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a);
  v_t := (pg_temp.dato(format(v_pub_a, c_a), null, 'anon') -> 0 ->> 'id');
  perform pg_temp.chiama(format($q$select public.cantina_accessori_archivia(%L, true)$q$, v_a1), c_a);
  v_u := pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text;
  perform pg_temp.registra(21, 'tornare privato o archiviare ferma le nuove letture pubbliche; un archiviato e privato; archiviato non si modifica ne si espone',
    v_s = '[]' and v_t = v_a1::text and v_u = '[]'
    and (select visibilita from private.cantina_accessori where id = v_a1) = 'privata'
    and pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"quantita":2}'::jsonb)$q$, v_a1), c_a) = '22023:archiviato'
    and pg_temp.esito(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a) = '22023:archiviato'
    and exists (select 1 from jsonb_array_elements(pg_temp.dato('select public.cantina_accessori_elenca(true)', c_a)) e
                where e ->> 'id' = v_a1::text and (e ->> 'archiviato')::boolean)
    and not exists (select 1 from jsonb_array_elements(pg_temp.dato('select public.cantina_accessori_elenca()', c_a)) e
                    where e ->> 'id' = v_a1::text),
    v_s || ' ' || v_u);

  perform pg_temp.chiama(format($q$select public.cantina_accessori_archivia(%L, false)$q$, v_a1), c_a);
  perform pg_temp.registra(22, 'il ripristino da archivio non riespone: resta privato finche il proprietario non sceglie di nuovo',
    (select visibilita from private.cantina_accessori where id = v_a1) = 'privata'
    and (select archiviato_at from private.cantina_accessori where id = v_a1) is null
    and pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text = '[]'
    and (select count(*) from private.cantina_accessori where archiviato_at is not null and visibilita <> 'privata') = 0,
    '');

  -- 23: interruttori che fermano le letture; il proprietario puo sempre rientrare in privato.
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', false, 'stop 12zi')$q$, c_adm);
  v_s := pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text;
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'riprendi 12zi')$q$, c_fnd);
  v_t := (pg_temp.dato(format(v_pub_a, c_a), null, 'anon') -> 0 ->> 'id');
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', false, 'stop funzione 12zi')$q$, c_adm);
  v_u := pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text;
  perform pg_temp.registra(23, 'visibilita pubblica spenta o funzione spenta (da un admin qualsiasi): porta pubblica vuota; con funzione spenta A non elenca ne salva, ma puo riportare un accessorio a privato; l''admin collauda ancora',
    v_s = '[]' and v_t = v_a1::text and v_u = '[]'
    and pg_temp.dato('select public.cantina_accessori_elenca()', c_a)::text = '[]'
    and pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"quantita":2}'::jsonb)$q$, v_a1), c_a) = '42501:funzione_non_attiva'
    and pg_temp.esito(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a2), c_a) = '42501:funzione_non_attiva'
    and pg_temp.esito(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'privata')$q$, v_a1), c_a) = 'NESSUN_ERRORE:'
    and jsonb_array_length(pg_temp.dato('select public.cantina_accessori_elenca()', c_adm)) = 0,
    v_s || ' ' || v_u);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('funzione', true, 'riaccendi 12zi')$q$, c_fnd);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a);

  -- 24: anteprima admin della proiezione pubblica.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', false, 'anteprima 12zi')$q$, c_adm);
  v_s := pg_temp.esito(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 12, 0, true)', c_a), null, 'anon');
  v_t := pg_temp.esito(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 12, 0, true)', c_a), c_b);
  v_item := pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 12, 0, true)', c_a), c_adm);
  perform pg_temp.registra(24, 'anteprima della proiezione pubblica: anonimo e utente rifiutati (42501); l''admin la vede anche con la visibilita spenta, a campi chiusi',
    v_s like '42501:%' and v_t like '42501:%' and jsonb_array_length(v_item) = 1
    and pg_temp.dato(format(v_pub_a, c_a), null, 'anon')::text = '[]',
    v_s || ' ' || v_t);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'riprendi 12zi')$q$, c_fnd);

  -- 25: legame facoltativo col catalogo: solo lettura, nessuna creazione o modifica.
  select (dati ->> 'id')::uuid into v_cat_id from pg_temp.chiama(format(
    $q$select public.accessori_admin_salva(null, jsonb_build_object('categoria_id', %L, 'slug', %L, 'nome', 'Scheda catalogo 12zi'))$q$,
    v_sub_cavatappi, v_cat_slug), c_adm);
  v_s := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"catalogo_slug":"%s"}'::jsonb)$q$, v_a3, v_cat_slug), c_a);
  -- Pubblicazione di fixture (scrittore privilegiato): descrizione e una foto di catalogo.
  update private.accessori
  set descrizione = 'Descrizione sintetica della scheda di catalogo.',
      immagini = array[v_cat_id::text || '/' || gen_random_uuid()::text || '.webp'],
      stato = 'pubblicato'
  where id = v_cat_id;
  v_t := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"catalogo_slug":"%s"}'::jsonb)$q$, v_a3, v_cat_slug), c_a);
  v_md5_prima := (select md5(a::text) from private.accessori a where a.id = v_cat_id);
  perform pg_temp.chiama($q$select public.accessori_admin_visibilita_imposta(true, 'prova 12zi')$q$, c_fnd);
  v_u := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"catalogo_slug":"%s"}'::jsonb)$q$, v_a3, v_cat_slug), c_a);
  v_item := pg_temp.dato(format($q$select public.cantina_accessori_elenca()$q$), c_a);
  perform pg_temp.chiama($q$select public.accessori_admin_visibilita_imposta(false, 'chiusura 12zi')$q$, c_adm);
  v_w := pg_temp.esito(format($q$select public.cantina_accessori_salva(%L, '{"catalogo_slug":null}'::jsonb)$q$, v_a3), c_a);
  perform pg_temp.registra(25, 'legame col catalogo: scheda in bozza o catalogo chiuso -> catalogo_non_valido; scheda pubblicata e visibile -> legame; il catalogo non cambia di un byte e nessuna scheda viene creata; scollegabile con null',
    v_s = '22023:catalogo_non_valido' and v_t = '22023:catalogo_non_valido' and v_u = 'NESSUN_ERRORE:'
    and exists (select 1 from jsonb_array_elements(v_item) e
                where e ->> 'id' = v_a3::text and e ->> 'catalogo_slug' = v_cat_slug)
    and (select md5(a::text) from private.accessori a where a.id = v_cat_id) = v_md5_prima
    and (select count(*) from private.accessori) = 1
    and v_w = 'NESSUN_ERRORE:'
    and (select catalogo_id from private.cantina_accessori where id = v_a3) is null
    and (select visibilita_pubblica from private.accessori_impostazioni) = false,
    v_s || ' ' || v_t || ' ' || v_u);

  -- 26: limite di 48 e di 300.
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'limite 12zi')$q$, c_fnd);
  for v_i in 1..50 loop
    v_x := gen_random_uuid();
    insert into private.cantina_accessori (id, owner_id, categoria_id, nome)
    values (v_x, c_b, v_pulizia, 'Massivo ' || lpad(v_i::text, 3, '0'));
    perform set_config('vinae.cantina_accessori_espone', 'espone:' || c_b::text || ':' || v_x::text, true);
    update private.cantina_accessori set visibilita = 'cantina_pubblica' where id = v_x;
  end loop;
  perform set_config('vinae.cantina_accessori_espone', '', true);
  perform pg_temp.registra(26, 'la porta pubblica taglia a 48 anche se se ne chiedono mille, a 12 di default, rispetta l''offset (50 esposti)',
    jsonb_array_length(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 1000, 0)', c_b), null, 'anon')) = 48
    and jsonb_array_length(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid)', c_b), null, 'anon')) = 12
    and jsonb_array_length(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 48, 40)', c_b), null, 'anon')) = 10
    and jsonb_array_length(pg_temp.dato(format('select public.cantina_accessori_pubblica_profilo(%L::uuid, 5, -9)', c_b), null, 'anon')) = 5,
    '');

  insert into private.cantina_accessori (owner_id, categoria_id, nome)
  select c_b, v_pulizia, 'Riempitivo ' || g from generate_series(1, 300 - 51) g;
  perform pg_temp.registra(27, 'tetto di 300 accessori per utente: oltre, limite_raggiunto',
    (select count(*) from private.cantina_accessori where owner_id = c_b) = 300
    and pg_temp.esito(format(
      $q$select public.cantina_accessori_salva(gen_random_uuid(), jsonb_build_object('categoria_id', %L, 'nome', 'Troppi'))$q$, v_pulizia), c_b)
        = '22023:limite_raggiunto',
    '');
  delete from private.cantina_accessori where owner_id = c_b and (nome like 'Massivo %' or nome like 'Riempitivo %');

  -- 28: Storage.
  v_p_ok := c_a::text || '/' || v_a1::text || '/' || gen_random_uuid()::text || '.webp';
  v_p_ok2 := c_a::text || '/' || v_a1::text || '/' || gen_random_uuid()::text || '.webp';
  v_p_b := c_b::text || '/' || v_b1::text || '/' || gen_random_uuid()::text || '.webp';
  v_p_ax := c_a::text || '/' || v_b1::text || '/' || gen_random_uuid()::text || '.webp';
  perform pg_temp.registra(28, 'Storage, scrittura: A carica solo nella propria cartella per un proprio accessorio; cartella altrui, accessorio altrui, accessorio inesistente, forma errata e anonimo sono rifiutati',
    pg_temp.carica(v_p_ok, c_a) = 'NESSUN_ERRORE:'
    and pg_temp.carica(v_p_b, c_a) like '42501:%'
    and pg_temp.carica(v_p_ax, c_a) like '42501:%'
    and pg_temp.carica(c_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.webp', c_a) like '42501:%'
    and pg_temp.carica(c_a::text || '/' || v_a1::text || '/foto.webp', c_a) like '42501:%'
    and pg_temp.carica(c_a::text || '/' || v_a1::text || '/' || gen_random_uuid()::text || '.webp', null, 'anon') like '42501:%'
    and pg_temp.carica(v_p_b, c_b) = 'NESSUN_ERRORE:',
    '');

  -- 29: lettura privata: solo il proprietario, nemmeno l'admin.
  perform pg_temp.registra(29, 'foto private con percorso noto: solo il proprietario la legge; altro utente, anonimo e admin no',
    pg_temp.vede_oggetto(v_p_ok, c_a) = 1
    and pg_temp.vede_oggetto(v_p_ok, c_b) = 0
    and pg_temp.vede_oggetto(v_p_ok, null, 'anon') = 0
    and pg_temp.vede_oggetto(v_p_ok, c_adm) = 0
    and pg_temp.vede_oggetto(v_p_ok, c_fnd) = 0,
    '');

  -- 30: collegamento delle foto all'accessorio e rifiuti.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.cantina_accessori_immagini_imposta(%L, array[%L])$q$, v_a1, v_p_ok), c_a);
  perform pg_temp.registra(30, 'immagini_imposta: foto propria collegata; foto altrui, inesistente, forma errata e oltre 4 rifiutate',
    v_c.esito = 'NESSUN_ERRORE' and v_c.dati -> 'immagini' ->> 0 = v_p_ok
    and pg_temp.esito(format($q$select public.cantina_accessori_immagini_imposta(%L, array[%L])$q$, v_a1, v_p_b), c_a) = '22023:immagini_non_valide'
    and pg_temp.esito(format($q$select public.cantina_accessori_immagini_imposta(%L, array[%L])$q$, v_a1, c_a::text || '/' || v_a1::text || '/' || gen_random_uuid()::text || '.webp'), c_a) = '22023:immagine_assente'
    and pg_temp.esito(format($q$select public.cantina_accessori_immagini_imposta(%L, array[%L,%L,%L,%L,%L])$q$, v_a1, v_p_ok, v_p_ok, v_p_ok, v_p_ok, v_p_ok), c_a) = '22023:immagini_non_valide'
    and pg_temp.esito(format($q$select public.cantina_accessori_immagini_imposta(%L, array[%L,%L])$q$, v_a1, v_p_ok, v_p_ok), c_a) = '22023:immagini_non_valide'
    and (select immagini from private.cantina_accessori where id = v_a1) = array[v_p_ok],
    v_c.esito || ':' || v_c.hint);

  -- 31: la firma pubblica segue lo stato (esposto + interruttori), non il percorso noto.
  v_s := pg_temp.vede_oggetto(v_p_ok, null, 'anon') || '/' || pg_temp.vede_oggetto(v_p_ok, c_b);   -- esposto, tutto acceso
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'privata')$q$, v_a1), c_a);
  v_t := pg_temp.vede_oggetto(v_p_ok, null, 'anon') || '/' || pg_temp.vede_oggetto(v_p_ok, c_b) || '/' || pg_temp.vede_oggetto(v_p_ok, c_a);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_visibilita_imposta(%L, 'cantina_pubblica')$q$, v_a1), c_a);
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', false, 'foto 12zi')$q$, c_adm);
  v_u := pg_temp.vede_oggetto(v_p_ok, null, 'anon')::text;
  perform pg_temp.chiama($q$select public.cantina_accessori_admin_imposta('visibilita_pubblica', true, 'foto 12zi')$q$, c_fnd);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_archivia(%L, true)$q$, v_a1), c_a);
  perform pg_temp.registra(31, 'foto firmabili da chiunque solo se l''accessorio e esposto, non archiviato e gli interruttori sono accesi; privato, archiviato o visibilita spenta -> nessuna nuova firma (anonimo 0, altro utente 0, proprietario 1)',
    v_s = '1/1' and v_t = '0/0/1' and v_u = '0'
    and pg_temp.vede_oggetto(v_p_ok, null, 'anon') = 0 and pg_temp.vede_oggetto(v_p_ok, c_a) = 1,
    v_s || ' ' || v_t || ' ' || v_u);
  perform pg_temp.chiama(format($q$select public.cantina_accessori_archivia(%L, false)$q$, v_a1), c_a);

  -- 32: cancellazione dei file: solo propri e non in uso.
  perform pg_temp.carica(v_p_ok2, c_a);
  perform pg_temp.registra(32, 'Storage, cancellazione: A non cancella una foto in uso ne un file altrui; cancella un proprio file non in uso; nessuna policy di UPDATE (non si sovrascrive)',
    pg_temp.cancella(v_p_ok, c_a) = 0
    and pg_temp.cancella(v_p_b, c_a) = 0
    and pg_temp.cancella(v_p_ok2, c_b) = 0
    and pg_temp.cancella(v_p_ok2, c_a) = 1
    and not exists (select 1 from pg_policies
                    where schemaname = 'storage' and tablename = 'objects'
                      and (qual like '%cantina-accessori-foto%' or with_check like '%cantina-accessori-foto%')
                      and cmd in ('UPDATE', 'ALL')),
    '');

  -- 33: superficie di Storage per anon.
  perform pg_temp.registra(33, 'per anon due sole policy sul bucket, entrambe SELECT (foto esposte 015B1 e foto di annunci visibili 015B3), nessuna di scrittura; gli helper di interruttore non sono eseguibili dai ruoli client',
    (select count(*) from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and (qual like '%cantina-accessori-foto%' or with_check like '%cantina-accessori-foto%')
       and 'anon' = any (roles)) = 2
    and not exists (select 1 from pg_policies
                    where schemaname = 'storage' and tablename = 'objects'
                      and (qual like '%cantina-accessori-foto%' or with_check like '%cantina-accessori-foto%')
                      and 'anon' = any (roles) and cmd <> 'SELECT')
    and exists (select 1 from pg_policies
                where schemaname = 'storage' and tablename = 'objects'
                  and policyname = 'cantina_accessori_media_select_esposte' and cmd = 'SELECT' and 'anon' = any (roles))
    and exists (select 1 from pg_policies
                where schemaname = 'storage' and tablename = 'objects'
                  and policyname = 'cantina_accessori_media_select_annunci_pubblicati' and cmd = 'SELECT' and 'anon' = any (roles))
    and not has_function_privilege('anon', 'private.cantina_accessori_consentita()', 'execute')
    and not has_function_privilege('authenticated', 'private.cantina_accessori_consentita()', 'execute')
    and not has_function_privilege('authenticated', 'private.cantina_accessori_utente()', 'execute')
    and not has_function_privilege('authenticated', 'private.cantina_accessori_impostazioni_guard()', 'execute'),
    '');

  -- 34: rimozione definitiva: restituisce i percorsi, che A puo poi cancellare.
  select * into v_c from pg_temp.chiama(format($q$select public.cantina_accessori_rimuovi(%L)$q$, v_a1), c_a);
  perform pg_temp.registra(34, 'rimuovi: l''accessorio sparisce, i percorsi delle foto tornano al proprietario che ora puo cancellarle; B non cancella quelle di A',
    v_c.esito = 'NESSUN_ERRORE' and (v_c.dati ->> 'rimosso')::boolean
    and v_c.dati -> 'percorsi' ->> 0 = v_p_ok
    and not exists (select 1 from private.cantina_accessori where id = v_a1)
    and pg_temp.cancella(v_p_ok, c_b) = 0
    and pg_temp.cancella(v_p_ok, c_a) = 1,
    v_c.esito || ':' || v_c.hint);

  -- 35: nessun legame con vino, bottiglie, ordini, pagamenti; nessuna colonna economica.
  perform pg_temp.registra(35, 'nessun accessorio in wines/bottle_units/cellar_slots: conteggi invariati; nessuna FK verso vino/annunci/ordini; nessuna colonna di prezzo; nessuna funzione cantina_accessori cita ordini, pagamenti, annunci o bottiglie',
    concat_ws('/',
      (select count(*) from public.listings), (select count(*) from public.orders),
      (select count(*) from public.wines), (select count(*) from public.bottle_units),
      (select count(*) from public.cellar_slots), (select count(*) from public.payments),
      (select count(*) from public.marketplace_config)) = v_snap_prima
    and not exists (
      select 1 from pg_constraint c
      where c.conrelid = 'private.cantina_accessori'::regclass and c.contype = 'f'
        and c.confrelid not in ('public.profiles'::regclass, 'private.accessori_categorie'::regclass,
                                'private.accessori'::regclass))
    and not exists (
      select 1 from pg_attribute a
      where a.attrelid = 'private.cantina_accessori'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attname ~* '(^|_)(prezzo|valuta|price|currency|iva|vat|commission|spedizion|serial|matricola)(_|$)')
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private') and p.proname like '%cantina\_accessor%'
        and p.prosrc ~* '(public\.|private\.)?(orders|payments|payouts|listings|proposals|bottle_units|cellar_slots|wines|marketplace_config|balance_)'),
    v_snap_prima);

  -- 36: catalogo admin 015A invariato e separato dagli interruttori della Cantina.
  perform pg_temp.registra(36, 'catalogo admin 015A invariato: porte admin ancora riservate (utente 42501), interruttore del catalogo ancora spento e indipendente, tassonomia intatta, una sola scheda (quella creata dall''admin)',
    pg_temp.esito('select public.accessori_admin_stato()', c_a) like '42501:%'
    and pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''x'')', c_adm) = '42501:rilascio_non_autorizzato'
    and (select visibilita_pubblica from private.accessori_impostazioni) = false
    and (select funzione_attiva and visibilita_pubblica from private.cantina_accessori_impostazioni)
    and pg_temp.dato('select public.accessori_elenca()', null, 'anon')::text = '[]'
    and (select count(*) from private.accessori_categorie) = v_cat_prima
    and (select count(*) from private.accessori) = 1,
    '');

  -- 37: volatilita e privilegi.
  select array(select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname like 'cantina\_accessori\_%'
                 and has_function_privilege('anon', p.oid, 'execute') order by 1) into v_chiavi;
  perform pg_temp.registra(37, 'anonimo esegue solo la porta pubblica; i dieci altri comandi sono per authenticated; cinque letture stable, sei scritture volatili (modo transazione PostgREST)',
    v_chiavi = array['cantina_accessori_pubblica_profilo']
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'cantina\_accessori\_%'
           and has_function_privilege('authenticated', p.oid, 'execute')) = 11
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 's' and p.proname in (
           'cantina_accessori_stato', 'cantina_accessori_categorie_elenca', 'cantina_accessori_elenca',
           'cantina_accessori_pubblica_profilo', 'cantina_accessori_admin_stato')) = 5
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 'v' and p.proname in (
           'cantina_accessori_salva', 'cantina_accessori_immagini_imposta',
           'cantina_accessori_visibilita_imposta', 'cantina_accessori_archivia',
           'cantina_accessori_rimuovi', 'cantina_accessori_admin_imposta')) = 6
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname like 'cantina\_accessori\_%' and p.prosecdef is not true),
    array_to_string(v_chiavi, ','));

  -- 38: registro append-only e impostazioni non cancellabili.
  perform pg_temp.registra(38, 'registro append-only e impostazioni non cancellabili ne troncabili anche per i privilegiati; ogni accensione/spegnimento e registrato con motivo',
    (pg_temp.diretto($q$delete from private.cantina_accessori_impostazioni$q$)).esito = '42501'
    and (pg_temp.diretto($q$truncate private.cantina_accessori_impostazioni$q$)).esito = '42501'
    and (pg_temp.diretto($q$update private.accessori_registro set motivo = 'x' where oggetto = 'cantina_accessori'$q$)).esito = '42501'
    and (select count(*) from private.accessori_registro where oggetto = 'cantina_accessori' and motivo is not null) >= 8,
    (select count(*)::text from private.accessori_registro where oggetto = 'cantina_accessori'));

  -- 39: nessun ruolo ammin/commerciale acquisibile dal client; la griglia lascia gli utenti senza nuovi ruoli.
  perform pg_temp.registra(39, 'nessun ruolo acquisibile dal client: nessuna scrittura su user_roles per authenticated, gli utenti A e B non hanno ruoli oltre "user"',
    not has_table_privilege('authenticated', 'public.user_roles', 'insert')
    and not has_table_privilege('authenticated', 'public.user_roles', 'update')
    and (select count(*) from public.user_roles where user_id in (c_a, c_b) and role <> 'user') = 0,
    '');
end $$;

select id, descrizione, passed, detail
from esiti_12zi
order by id;

rollback;
