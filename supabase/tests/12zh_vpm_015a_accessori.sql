-- VPM-015A — Accessori Vinea: fondazione Beta (griglia 12zh).
--
-- SOLO stack Supabase locale/effimero. Utenti `.test`, categorie, schede e
-- oggetti Storage di prova vivono nella transazione e spariscono con
-- ROLLBACK. Dati SINTETICI: nessun prodotto, marchio o prezzo reale.
--
-- Prova le migrazioni 20261020120000 e 20261020170000 (rilascio riservato al titolare, foto
-- private) con quattro identita (anonimo, utente A,
-- utente B, admin) più un admin con il ruolo di rilascio e un utente con il solo ruolo:
--   - tassonomia seminata, interruttore di visibilita spento di default;
--   - nessun accesso diretto alle tabelle; letture pubbliche vuote con
--     l'interruttore spento; anteprima e porte admin riservate all'admin reale;
--   - validazione delle schede (campi ammessi, slug, quantita, attributi) e
--     macchina a stati bozza -> pubblicato -> archiviato;
--   - bozze mai pubbliche, anche con l'interruttore acceso; elenco chiuso dei
--     campi pubblici (nessuna quantita, nessuno stato, nessun id);
--   - Storage: scrittura e lettura dell'elenco solo per l'admin;
--   - nessun legame con le entita del vino e con ordini/pagamenti, nessuna
--     colonna economica, nessuna porta di transazione;
--   - catalogo non cancellabile, registro append-only;
--   - volatilita delle funzioni (lettura stable, scrittura volatile).

begin;

\set ON_ERROR_STOP on

do $$
begin
  if exists (select 1 from auth.users where email not like '%.test') then
    raise exception 'Guard 12zh: il database contiene utenti reali, griglia rifiutata.';
  end if;
end $$;

create temp table esiti_12zh (
  id integer primary key,
  descrizione text not null,
  passed boolean not null,
  detail text not null
) on commit drop;

create function pg_temp.registra(
  p_id integer, p_descrizione text, p_passed boolean, p_detail text default ''
) returns void language sql as $f$
  insert into esiti_12zh (id, descrizione, passed, detail)
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

\set adm '12ee0000-0000-4000-8000-0000000000e0'
\set ua '12ee0000-0000-4000-8000-0000000000e1'
\set ub '12ee0000-0000-4000-8000-0000000000e2'
\set fnd '12ee0000-0000-4000-8000-0000000000e3'
\set rel '12ee0000-0000-4000-8000-0000000000e4'

set local session_replication_role = replica;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  (:'adm', 'adm@grid-12zh.test', now(), '{}'::jsonb),
  (:'ua', 'ua@grid-12zh.test', now(), '{}'::jsonb),
  (:'ub', 'ub@grid-12zh.test', now(), '{}'::jsonb),
  (:'fnd', 'fnd@grid-12zh.test', now(), '{}'::jsonb),
  (:'rel', 'rel@grid-12zh.test', now(), '{}'::jsonb);
insert into public.profiles (id, username, dob) values
  (:'adm', 'adm-12zh', date '1980-01-01'),
  (:'ua', 'ua-12zh', date '1980-01-01'),
  (:'ub', 'ub-12zh', date '1980-01-01'),
  (:'fnd', 'fnd-12zh', date '1980-01-01'),
  (:'rel', 'rel-12zh', date '1980-01-01');
insert into public.user_roles (user_id, role) values
  (:'adm', 'admin'), (:'ua', 'user'), (:'ub', 'user'),
  (:'fnd', 'admin'), (:'fnd', 'accessori_release'), (:'rel', 'accessori_release');
set local session_replication_role = origin;

do $$
declare
  c_adm constant uuid := '12ee0000-0000-4000-8000-0000000000e0';
  c_a constant uuid := '12ee0000-0000-4000-8000-0000000000e1';
  c_b constant uuid := '12ee0000-0000-4000-8000-0000000000e2';
  c_fnd constant uuid := '12ee0000-0000-4000-8000-0000000000e3';
  c_rel constant uuid := '12ee0000-0000-4000-8000-0000000000e4';
  v_snap_prima text;
  v_c record;
  v_s text;
  v_t text;
  v_sql text;
  v_n integer;
  v_cat uuid;
  v_sub uuid;
  v_acc uuid;
  v_acc2 uuid;
  v_path text;
  v_path_altro text;
  v_path_bozza text;
  v_media_cat text;
  v_media_sql constant text := $q$select coalesce(jsonb_agg(name order by name), '[]'::jsonb) from storage.objects where bucket_id = 'accessori-media'$q$;
  v_slug_pub constant text := 'accessorio-prova-12zh';
  v_slug_bozza constant text := 'accessorio-bozza-12zh';
  v_item jsonb;
  v_chiavi text[];
  v_attr13 jsonb;
  v_admin_sql text[] := array[
    'select public.accessori_admin_stato()',
    'select public.accessori_admin_categorie_elenca()',
    'select public.accessori_admin_elenca()',
    'select public.accessori_admin_dettaglio(gen_random_uuid())',
    'select public.accessori_admin_salva(null, ''{}''::jsonb)',
    'select public.accessori_admin_categoria_salva(null, ''{}''::jsonb)',
    'select public.accessori_admin_immagini_imposta(gen_random_uuid(), ''{}''::text[])',
    'select public.accessori_admin_stato_imposta(gen_random_uuid(), ''bozza'')',
    'select public.accessori_admin_visibilita_imposta(true, ''prova'')',
    'select public.accessori_elenca(null, true)',
    'select public.accessori_dettaglio(''x'', true)',
    'select public.accessori_categorie_elenca(true)'
  ];
begin
  v_snap_prima := concat_ws('/',
    (select count(*) from public.listings), (select count(*) from public.orders),
    (select count(*) from public.wines), (select count(*) from public.bottle_units),
    (select count(*) from public.payments), (select count(*) from public.marketplace_config));

  -- 1: stato iniziale: interruttore spento, tassonomia seminata, nessun prodotto.
  perform pg_temp.registra(1, 'interruttore pubblico spento di default (una sola riga); nessuna scheda seminata',
    (select count(*) from private.accessori_impostazioni) = 1
    and (select visibilita_pubblica from private.accessori_impostazioni) = false
    and (select count(*) from private.accessori) = 0,
    (select visibilita_pubblica::text from private.accessori_impostazioni));

  select count(*) into v_n from private.accessori_categorie
  where parent_id is null and slug in ('apertura', 'calici', 'degustazione', 'decanter',
    'raffreddamento', 'conservazione', 'espositori', 'pulizia', 'set-regalo', 'altri-accessori');
  perform pg_temp.registra(2, 'tassonomia: le dieci categorie richieste e almeno una sottocategoria; due livelli',
    v_n = 10
    and (select count(*) from private.accessori_categorie where parent_id is not null) >= 8
    and not exists (
      select 1 from private.accessori_categorie k
      join private.accessori_categorie p on p.id = k.parent_id
      where p.parent_id is not null),
    v_n::text);

  -- 3: nessun accesso diretto alle tabelle per i ruoli client.
  v_s := pg_temp.esito('select to_jsonb(count(*)) from private.accessori', null, 'anon');
  v_t := pg_temp.esito('select to_jsonb(count(*)) from private.accessori', c_a);
  perform pg_temp.registra(3, 'nessuna lettura diretta di private.accessori (anonimo e utente); nessuna tabella o vista in public',
    v_s like '42501:%' and v_t like '42501:%'
    and to_regclass('public.accessori') is null and to_regclass('public.accessori_categorie') is null
    and to_regclass('public.public_accessori') is null,
    v_s || ' ' || v_t);

  -- 4: letture pubbliche vuote con l'interruttore spento.
  v_s := (select dati::text from pg_temp.chiama('select public.accessori_categorie_elenca()', null, 'anon'))
      || (select dati::text from pg_temp.chiama('select public.accessori_elenca()', null, 'anon'));
  perform pg_temp.registra(4, 'interruttore spento: categorie ed elenco pubblici vuoti per anonimo, utente A e utente B; dettaglio null',
    v_s = '[][]'
    and (select dati::text from pg_temp.chiama('select public.accessori_elenca()', c_a)) = '[]'
    and (select dati::text from pg_temp.chiama('select public.accessori_categorie_elenca()', c_b)) = '[]'
    and (select dati is null and esito = 'NESSUN_ERRORE'
         from pg_temp.chiama('select public.accessori_dettaglio(''qualunque'')', null, 'anon')),
    v_s);

  -- 5: anteprima e porte admin: anonimo, A e B rifiutati.
  v_n := 0;
  foreach v_sql in array v_admin_sql loop
    if pg_temp.esito(v_sql, null, 'anon') like '42501:%' then v_n := v_n + 1; end if;
    if pg_temp.esito(v_sql, c_a) like '42501:%' then v_n := v_n + 1; end if;
    if pg_temp.esito(v_sql, c_b) like '42501:%' then v_n := v_n + 1; end if;
  end loop;
  perform pg_temp.registra(5, 'dodici porte (anteprima + admin) rifiutate con 42501 a anonimo, utente A e utente B (36 prove)',
    v_n = 36, v_n::text);

  -- 6: categorie dell'admin: crea, sottocategoria, terzo livello rifiutato, slug in uso.
  select * into v_c from pg_temp.chiama(
    $q$select public.accessori_admin_categoria_salva(null, '{"slug":"prova-12zh","nome":"Prova 12zh","descrizione":"Categoria sintetica"}'::jsonb)$q$, c_adm);
  v_cat := (v_c.dati ->> 'id')::uuid;
  select * into v_c from pg_temp.chiama(format(
    $q$select public.accessori_admin_categoria_salva(null, '{"slug":"prova-sotto-12zh","nome":"Sotto 12zh","genitore_id":"%s"}'::jsonb)$q$, v_cat), c_adm);
  v_sub := (v_c.dati ->> 'id')::uuid;
  v_s := pg_temp.esito(format(
    $q$select public.accessori_admin_categoria_salva(null, '{"slug":"terzo-livello-12zh","nome":"Terzo","genitore_id":"%s"}'::jsonb)$q$, v_sub), c_adm);
  v_t := pg_temp.esito(
    $q$select public.accessori_admin_categoria_salva(null, '{"slug":"apertura","nome":"Doppione"}'::jsonb)$q$, c_adm);
  perform pg_temp.registra(6, 'admin: categoria e sottocategoria create; terzo livello rifiutato (livello_non_ammesso); slug in uso (slug_in_uso)',
    v_cat is not null and v_sub is not null
    and v_s = '22023:livello_non_ammesso' and v_t = '23505:slug_in_uso',
    v_s || ' ' || v_t);

  -- 7: la scheda in bozza e i rifiuti di validazione.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.accessori_admin_salva(null, jsonb_build_object(
      'categoria_id', %L, 'slug', %L, 'nome', 'Accessorio di prova 12zh',
      'descrizione', 'Descrizione sintetica di una scheda di prova.',
      'marchio', 'Marchio Prova', 'condizione', 'nuovo', 'quantita', 5,
      'attributi', '{"materiale":"cristallo"}'::jsonb))$q$, v_sub, v_slug_pub), c_adm);
  v_acc := (v_c.dati ->> 'id')::uuid;
  perform pg_temp.registra(7, 'admin: scheda creata in bozza con categoria, marchio, condizione, quantita e attributi',
    v_acc is not null and v_c.dati ->> 'stato' = 'bozza' and (v_c.dati ->> 'quantita')::int = 5
    and v_c.dati #>> '{categoria,slug}' = 'prova-sotto-12zh',
    coalesce(v_c.esito || ':' || v_c.hint, ''));

  v_attr13 := (select jsonb_object_agg('k' || g, 'v') from generate_series(1, 13) g);
  v_sql := 'select public.accessori_admin_salva(%L, %L::jsonb)';
  perform pg_temp.registra(8, 'validazione: slug riservato/maiuscolo, campo non ammesso (prezzo), nome corto, quantita negativa o testuale, condizione ignota, attributi invalidi o oltre 12',
    pg_temp.esito(format(v_sql, v_acc, '{"slug":"categoria"}'), c_adm) = '22023:slug_non_valido'
    and pg_temp.esito(format(v_sql, v_acc, '{"slug":"Maiuscolo"}'), c_adm) = '22023:slug_non_valido'
    and pg_temp.esito(format(v_sql, v_acc, '{"prezzo":10}'), c_adm) = '22023:campo_sconosciuto'
    and pg_temp.esito(format(v_sql, v_acc, '{"valuta":"EUR"}'), c_adm) = '22023:campo_sconosciuto'
    and pg_temp.esito(format(v_sql, v_acc, '{"nome":"a"}'), c_adm) = '22023:nome_non_valido'
    and pg_temp.esito(format(v_sql, v_acc, '{"quantita":-1}'), c_adm) = '22023:quantita_non_valida'
    and pg_temp.esito(format(v_sql, v_acc, '{"quantita":"5"}'), c_adm) = '22023:quantita_non_valida'
    and pg_temp.esito(format(v_sql, v_acc, '{"condizione":"rotto"}'), c_adm) = '22023:condizione_non_valida'
    and pg_temp.esito(format(v_sql, v_acc, '{"attributi":{"Materiale":"x"}}'), c_adm) = '22023:attributi_non_validi'
    and pg_temp.esito(format(v_sql, v_acc, '{"attributi":{"materiale":3}}'), c_adm) = '22023:attributi_non_validi'
    and pg_temp.esito(format(v_sql, v_acc, jsonb_build_object('attributi', v_attr13)::text), c_adm) = '22023:attributi_non_validi'
    and pg_temp.esito(format(v_sql, gen_random_uuid(), '{"nome":"Nuovo nome"}'), c_adm) = 'P0001:non_trovato',
    '');

  -- 9: macchina a stati: senza immagini non si pubblica; bozza -> archiviato no.
  v_s := pg_temp.esito(format('select public.accessori_admin_stato_imposta(%L, ''pubblicato'')', v_acc), c_adm);
  v_t := pg_temp.esito(format('select public.accessori_admin_stato_imposta(%L, ''archiviato'')', v_acc), c_adm);
  perform pg_temp.registra(9, 'pubblicazione senza immagine rifiutata (pubblicazione_incompleta); bozza -> archiviato non ammesso',
    v_s = '22023:pubblicazione_incompleta' and v_t = '22023:transizione_non_ammessa',
    v_s || ' ' || v_t);

  -- 10: Storage: solo l'admin carica e vede; il bucket e WebP 2 MB.
  v_path := v_acc::text || '/' || gen_random_uuid()::text || '.webp';
  v_sql := format($q$with i as (insert into storage.objects (bucket_id, name) values ('accessori-media', %L) returning 1) select to_jsonb(count(*)) from i$q$, v_path);
  v_s := pg_temp.esito(v_sql, null, 'anon');
  v_t := pg_temp.esito(v_sql, c_a);
  select * into v_c from pg_temp.chiama(v_sql, c_adm);
  perform pg_temp.registra(10, 'Storage accessori-media: bucket PRIVATO WebP 2 MB; caricamento negato ad anonimo e utente, ammesso all''admin; percorso fuori forma e scheda inesistente rifiutati',
    (select not public and file_size_limit = 2097152 and allowed_mime_types = array['image/webp']
     from storage.buckets where id = 'accessori-media')
    and v_s like '42501:%' and v_t like '42501:%' and v_c.esito = 'NESSUN_ERRORE'
    and pg_temp.esito(format($q$with i as (insert into storage.objects (bucket_id, name) values ('accessori-media', %L) returning 1) select to_jsonb(count(*)) from i$q$, v_acc::text || '/foto.webp'), c_adm) like '42501:%'
    and pg_temp.esito(format($q$with i as (insert into storage.objects (bucket_id, name) values ('accessori-media', %L) returning 1) select to_jsonb(count(*)) from i$q$, gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.webp'), c_adm) like '42501:%',
    v_s || ' ' || v_t || ' ' || v_c.esito);

  perform pg_temp.registra(11, 'elenco degli oggetti del bucket: invisibile ad anonimo, utente A e utente B; visibile all''admin',
    (select dati::text from pg_temp.chiama($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media'$q$, null, 'anon')) = '0'
    and (select dati::text from pg_temp.chiama($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media'$q$, c_a)) = '0'
    and (select dati::text from pg_temp.chiama($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media'$q$, c_b)) = '0'
    and (select dati::text from pg_temp.chiama($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media'$q$, c_adm)) = '1',
    '');

  -- 12: immagini: percorso inesistente rifiutato; poi collegata e pubblicazione.
  v_s := pg_temp.esito(format('select public.accessori_admin_immagini_imposta(%L, array[%L])',
    v_acc, v_acc::text || '/' || gen_random_uuid()::text || '.webp'), c_adm);
  -- Un oggetto reale ma nella cartella di un'altra scheda non si collega.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.accessori_admin_salva(null, jsonb_build_object(
      'categoria_id', %L, 'slug', 'altra-scheda-12zh', 'nome', 'Altra scheda 12zh'))$q$, v_cat), c_adm);

  v_path_altro := (v_c.dati ->> 'id') || '/' || gen_random_uuid()::text || '.webp';
  perform pg_temp.chiama(format($q$with i as (insert into storage.objects (bucket_id, name) values ('accessori-media', %L) returning 1) select to_jsonb(count(*)) from i$q$, v_path_altro), c_adm);
  v_t := pg_temp.esito(format('select public.accessori_admin_immagini_imposta(%L, array[%L])', v_acc, v_path_altro), c_adm);
  select * into v_c from pg_temp.chiama(format('select public.accessori_admin_immagini_imposta(%L, array[%L])', v_acc, v_path), c_adm);
  perform pg_temp.registra(12, 'immagini: oggetto assente o di un''altra scheda rifiutato; oggetto reale collegato alla scheda',
    v_s = '22023:immagine_assente' and v_t = '22023:immagini_non_valide'
    and v_c.esito = 'NESSUN_ERRORE' and v_c.dati -> 'immagini' ->> 0 = v_path,
    v_s || ' ' || v_t || ' ' || v_c.esito);

  -- 13: pubblicazione, indirizzo bloccato dopo la pubblicazione.
  select * into v_c from pg_temp.chiama(format('select public.accessori_admin_stato_imposta(%L, ''pubblicato'')', v_acc), c_adm);
  v_s := pg_temp.esito(format('select public.accessori_admin_salva(%L, ''{"slug":"altro-indirizzo-12zh"}''::jsonb)', v_acc), c_adm);
  perform pg_temp.registra(13, 'pubblicazione riuscita con data; l''indirizzo di una scheda pubblicata non cambia (slug_bloccato); nome ancora modificabile',
    v_c.dati ->> 'stato' = 'pubblicato' and v_c.dati ->> 'pubblicato_il' is not null
    and v_s = '22023:slug_bloccato'
    and pg_temp.esito(format('select public.accessori_admin_salva(%L, ''{"nome":"Accessorio di prova 12zh bis"}''::jsonb)', v_acc), c_adm) = 'NESSUN_ERRORE:',
    v_s);

  -- Seconda scheda: resta bozza.
  select * into v_c from pg_temp.chiama(format(
    $q$select public.accessori_admin_salva(null, jsonb_build_object(
      'categoria_id', %L, 'slug', %L, 'nome', 'Bozza di prova 12zh',
      'descrizione', 'Una bozza che non deve mai uscire.'))$q$, v_sub, v_slug_bozza), c_adm);
  v_acc2 := (v_c.dati ->> 'id')::uuid;

  -- 14: anteprima admin con interruttore spento; pubblico ancora vuoto.
  perform pg_temp.registra(14, 'interruttore spento: l''admin vede in anteprima pubblicata + bozza (2) con lo stato; anonimo, A e B non vedono nulla',
    (select array(select e ->> 'stato' from jsonb_array_elements(dati) e order by 1) from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'', true)', c_adm)) = array['bozza', 'pubblicato']
    and
    (select jsonb_array_length(dati) from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'', true)', c_adm)) = 2
    and (select dati::text from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', null, 'anon')) = '[]'
    and (select dati::text from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', c_a)) = '[]'
    and (select dati is not null from pg_temp.chiama(format('select public.accessori_dettaglio(%L, true)', v_slug_bozza), c_adm))
    and (select dati is null from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_pub), null, 'anon')),
    '');

  -- 15: accendere la visibilita PUBBLICA e riservato al titolare: un admin
  -- ordinario non puo, nemmeno con un motivo valido.
  v_s := pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''Prova 12zh'')', c_adm);
  v_t := pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''Prova 12zh'')', c_rel);
  perform pg_temp.registra(15, 'admin ordinario: accensione rifiutata (rilascio_non_autorizzato) anche con motivo; il solo ruolo di rilascio senza essere admin e rifiutato; l''interruttore resta spento',
    v_s = '42501:rilascio_non_autorizzato' and v_t like '42501:%'
    and pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''Prova 12zh'')', c_a) like '42501:%'
    and pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''Prova 12zh'')', null, 'anon') like '42501:%'
    and not (select visibilita_pubblica from private.accessori_impostazioni)
    and not exists (select 1 from private.accessori_registro where azione = 'visibilita_accendi'),
    v_s || ' ' || v_t);

  -- 30: il database vincola anche i writer privilegiati: UPDATE diretto
  -- che accende, con o senza un autore, e rifiutato dal trigger.
  v_s := (pg_temp.diretto('update private.accessori_impostazioni set visibilita_pubblica = true')).hint;
  v_t := (pg_temp.diretto(format(
    'update private.accessori_impostazioni set visibilita_pubblica = true, aggiornato_da = %L', c_fnd))).hint;
  perform pg_temp.registra(30, 'UPDATE diretto che accende la visibilita (anche con un autore) rifiutato dal trigger: serve la porta di rilascio',
    v_s = 'rilascio_non_autorizzato' and v_t = 'rilascio_non_autorizzato'
    and not (select visibilita_pubblica from private.accessori_impostazioni),
    coalesce(v_s, '') || ' ' || coalesce(v_t, ''));

  -- 31: il titolare (admin con ruolo di rilascio) richiede il motivo, poi accende.
  v_s := pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, '''')', c_fnd);
  v_t := pg_temp.esito('select public.accessori_admin_visibilita_imposta(true, ''Prova 12zh'')', c_fnd);
  perform pg_temp.registra(31, 'titolare: accensione senza motivo rifiutata (motivo_obbligatorio); con motivo riuscita e registrata a suo nome; l''admin ordinario non e il titolare',
    v_s = '22023:motivo_obbligatorio' and v_t = 'NESSUN_ERRORE:'
    and (select visibilita_pubblica from private.accessori_impostazioni)
    and exists (select 1 from private.accessori_registro where azione = 'visibilita_accendi' and motivo = 'Prova 12zh' and admin_id = c_fnd)
    and not exists (select 1 from private.accessori_registro where azione = 'visibilita_accendi' and admin_id = c_adm)
    and (select (dati ->> 'puo_rilasciare')::boolean from pg_temp.chiama('select public.accessori_admin_stato()', c_fnd))
    and not (select (dati ->> 'puo_rilasciare')::boolean from pg_temp.chiama('select public.accessori_admin_stato()', c_adm)),
    v_s || ' ' || v_t);

  -- 16: interruttore acceso: A, B e anonimo vedono solo la pubblicata; la bozza no.
  select dati into v_item from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', null, 'anon');
  perform pg_temp.registra(16, 'interruttore acceso: anonimo, utente A e utente B vedono solo la scheda pubblicata; la bozza non appare in elenco, dettaglio, categoria padre',
    jsonb_array_length(v_item) = 1 and v_item -> 0 ->> 'slug' = v_slug_pub
    and (select jsonb_array_length(dati) from pg_temp.chiama('select public.accessori_elenca()', c_a)) = 1
    and (select jsonb_array_length(dati) from pg_temp.chiama('select public.accessori_elenca(''prova-12zh'')', c_b)) = 1
    and (select dati is null from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_bozza), null, 'anon'))
    and (select dati is null from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_bozza), c_a))
    and (select dati is not null from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_pub), c_b))
    and pg_temp.esito(format('select public.accessori_dettaglio(%L, true)', v_slug_bozza), null, 'anon') like '42501:%'
    and pg_temp.esito(format('select public.accessori_dettaglio(%L, true)', v_slug_bozza), c_a) like '42501:%',
    coalesce(v_item::text, ''));

  -- 32: Storage con la visibilita accesa: le foto della sola scheda PUBBLICATA
  -- sono leggibili (e quindi firmabili) da tutti; quelle di una bozza e quelle
  -- non collegate a nessuna scheda restano dell'admin.
  v_path_bozza := v_acc2::text || '/' || gen_random_uuid()::text || '.webp';
  perform pg_temp.chiama(format($q$with i as (insert into storage.objects (bucket_id, name) values ('accessori-media', %L) returning 1) select to_jsonb(count(*)) from i$q$, v_path_bozza), c_adm);
  perform pg_temp.chiama(format('select public.accessori_admin_immagini_imposta(%L, array[%L])', v_acc2, v_path_bozza), c_adm);
  perform pg_temp.registra(32, 'visibilita accesa: anonimo, A e B leggono (firmano) solo la foto della scheda pubblicata; foto di bozza e foto non collegata no; l''admin le vede tutte',
    (select dati from pg_temp.chiama(v_media_sql, null, 'anon')) = jsonb_build_array(v_path)
    and (select dati from pg_temp.chiama(v_media_sql, c_a)) = jsonb_build_array(v_path)
    and (select dati from pg_temp.chiama(v_media_sql, c_b)) = jsonb_build_array(v_path)
    and (select jsonb_array_length(dati) from pg_temp.chiama(v_media_sql, c_adm)) = 3
    and (select dati::text from pg_temp.chiama(format($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media' and name = %L$q$, v_path_bozza), null, 'anon')) = '0'
    and (select dati::text from pg_temp.chiama(format($q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'accessori-media' and name = %L$q$, v_path_altro), c_a)) = '0',
    '');

  -- 17: elenco chiuso dei campi pubblici.
  select array(select jsonb_object_keys(v_item -> 0) order by 1) into v_chiavi;
  perform pg_temp.registra(17, 'campi pubblici a elenco chiuso: nessuna quantita, stato, id, creatore o data; categoria con slug e nome',
    v_chiavi = array['attributi', 'categoria', 'condizione', 'descrizione', 'immagini', 'marchio', 'nome', 'slug']
    and array(select jsonb_object_keys(v_item -> 0 -> 'categoria') order by 1)
        = array['genitore_nome', 'genitore_slug', 'nome', 'slug'],
    array_to_string(v_chiavi, ','));

  -- 18: conteggi di categoria: pubblico solo pubblicate; anteprima anche bozze.
  perform pg_temp.registra(18, 'conteggio per sottocategoria: 1 pubblico, 2 in anteprima admin; il genitore include la sottocategoria',
    (select (e ->> 'conteggio')::int from pg_temp.chiama('select public.accessori_categorie_elenca()', null, 'anon') c,
       jsonb_array_elements(c.dati) e where e ->> 'slug' = 'prova-sotto-12zh') = 1
    and (select (e ->> 'conteggio')::int from pg_temp.chiama('select public.accessori_categorie_elenca(true)', c_adm) c,
       jsonb_array_elements(c.dati) e where e ->> 'slug' = 'prova-sotto-12zh') = 2
    and (select (e ->> 'conteggio')::int from pg_temp.chiama('select public.accessori_categorie_elenca()', c_a) c,
       jsonb_array_elements(c.dati) e where e ->> 'slug' = 'prova-12zh') = 1,
    '');

  -- 19: archiviazione e riapertura; archiviato non torna direttamente pubblicato.
  select * into v_c from pg_temp.chiama(format('select public.accessori_admin_stato_imposta(%L, ''archiviato'')', v_acc), c_adm);
  v_s := pg_temp.esito(format('select public.accessori_admin_stato_imposta(%L, ''pubblicato'')', v_acc), c_adm);
  perform pg_temp.registra(19, 'scheda archiviata sparisce dal pubblico; archiviato -> pubblicato non ammesso; archiviato -> bozza -> pubblicato ammessi',
    v_c.dati ->> 'stato' = 'archiviato'
    and (select dati::text from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', null, 'anon')) = '[]'
    and v_s = '22023:transizione_non_ammessa'
    and pg_temp.esito(format('select public.accessori_admin_stato_imposta(%L, ''bozza'')', v_acc), c_adm) = 'NESSUN_ERRORE:'
    and pg_temp.esito(format('select public.accessori_admin_stato_imposta(%L, ''pubblicato'')', v_acc), c_adm) = 'NESSUN_ERRORE:',
    v_s);

  -- 20: categoria disattivata nasconde le schede; riattivata le restituisce.
  perform pg_temp.chiama(format('select public.accessori_admin_categoria_salva(%L, ''{"attiva":false}''::jsonb)', v_sub), c_adm);
  v_s := (select dati::text from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', null, 'anon'));
  v_t := (select dati::text from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_pub), null, 'anon'));
  v_media_cat := (select dati::text from pg_temp.chiama(v_media_sql, null, 'anon'));
  perform pg_temp.chiama(format('select public.accessori_admin_categoria_salva(%L, ''{"attiva":true}''::jsonb)', v_sub), c_adm);
  perform pg_temp.registra(20, 'categoria disattivata: schede nascoste in elenco e dettaglio; riattivata: tornano visibili',
    v_s = '[]' and v_t is null
    and (select jsonb_array_length(dati) from pg_temp.chiama('select public.accessori_elenca(''prova-sotto-12zh'')', null, 'anon')) = 1,
    coalesce(v_s, '') || ' ' || coalesce(v_t, ''));
  perform pg_temp.registra(33, 'categoria disattivata: anche la foto della scheda diventa illeggibile all''anonimo',
    v_media_cat = '[]', coalesce(v_media_cat, ''));

  -- 21: spegnimento: torna tutto vuoto.
  perform pg_temp.chiama('select public.accessori_admin_visibilita_imposta(false, ''Chiusura 12zh'')', c_adm);
  perform pg_temp.registra(21, 'interruttore rispento: elenco, categorie e dettaglio pubblici di nuovo vuoti',
    (select dati::text from pg_temp.chiama('select public.accessori_elenca()', null, 'anon')) = '[]'
    and (select dati::text from pg_temp.chiama('select public.accessori_categorie_elenca()', c_a)) = '[]'
    and (select dati is null from pg_temp.chiama(format('select public.accessori_dettaglio(%L)', v_slug_pub), c_b))
    and not (select visibilita_pubblica from private.accessori_impostazioni),
    '');

  -- 34: spegnere e consentito a un admin ordinario (il verso sicuro non richiede
  -- approvazione, ed e stato appena fatto da c_adm); da spenta nessuna foto e
  -- leggibile ai ruoli client, nemmeno quella gia pubblicata. L'admin si'.
  perform pg_temp.registra(34, 'visibilita spenta da un admin ordinario: nessuna foto leggibile da anonimo, A e B; l''admin le vede ancora',
    exists (select 1 from private.accessori_registro where azione = 'visibilita_spegni' and admin_id = c_adm)
    and (select dati::text from pg_temp.chiama(v_media_sql, null, 'anon')) = '[]'
    and (select dati::text from pg_temp.chiama(v_media_sql, c_a)) = '[]'
    and (select dati::text from pg_temp.chiama(v_media_sql, c_b)) = '[]'
    and (select jsonb_array_length(dati) from pg_temp.chiama(v_media_sql, c_adm)) = 3,
    '');

  -- 22: scrittori privilegiati vincolati dal database (trigger).
  v_s := (pg_temp.diretto(format(
    'insert into private.accessori (categoria_id, slug, nome, stato, creato_da) values (%L, ''diretto-12zh'', ''Diretto'', ''pubblicato'', %L)', v_sub, c_adm))).hint;
  v_t := (pg_temp.diretto(format(
    'update private.accessori set immagini = array[''percorso/non-valido.webp''] where id = %L', v_acc2))).hint;
  perform pg_temp.registra(22, 'anche un writer privilegiato e vincolato: nascita non in bozza e immagini fuori forma rifiutate dal trigger',
    v_s = 'stato_iniziale' and v_t = 'immagini_non_valide', v_s || ' ' || v_t);

  -- 23: catalogo non cancellabile, registro append-only, interruttore unico.
  perform pg_temp.registra(23, 'nessuna cancellazione o svuotamento di categorie, schede, impostazioni e registro; registro non modificabile; seconda riga impostazioni rifiutata',
    (pg_temp.diretto('delete from private.accessori')).esito = '42501'
    and (pg_temp.diretto('delete from private.accessori_categorie')).esito = '42501'
    and (pg_temp.diretto('truncate private.accessori cascade')).esito = '42501'
    and (pg_temp.diretto('truncate private.accessori_categorie cascade')).esito = '42501'
    and (pg_temp.diretto('delete from private.accessori_impostazioni')).esito = '42501'
    and (pg_temp.diretto('update private.accessori_registro set azione = ''x''')).esito = '42501'
    and (pg_temp.diretto('delete from private.accessori_registro')).esito = '42501'
    and (pg_temp.diretto('insert into private.accessori_impostazioni (singleton, visibilita_pubblica) values (false, true)')).esito in ('23514', '23505'),
    '');

  -- 24: il registro ha tracciato le scritture admin.
  select count(*) into v_n from private.accessori_registro where admin_id = c_adm;
  perform pg_temp.registra(24, 'registro: creazioni, modifiche, immagini, stati e interruttore tracciati con l''admin',
    v_n >= 12
    and exists (select 1 from private.accessori_registro where azione = 'accessorio_crea')
    and exists (select 1 from private.accessori_registro where azione = 'accessorio_immagini')
    and exists (select 1 from private.accessori_registro where azione = 'accessorio_stato_archiviato')
    and exists (select 1 from private.accessori_registro where azione = 'visibilita_spegni'),
    v_n::text);

  -- 25: separazione dal vino e dal denaro: nessun legame, nessuna colonna economica.
  perform pg_temp.registra(25, 'separazione: nessuna FK verso o da listings, orders, payments, wines, bottle_units; riferimenti solo a profiles e fra tabelle accessori (uniche eccezioni: la Cantina Accessori personale 015B1, che punta a tassonomia e schede, e le regole di vendita per categoria 015B2, che puntano alla tassonomia)',
    not exists (
      select 1 from pg_constraint k
      join pg_class cr on cr.oid = k.conrelid join pg_namespace nr on nr.oid = cr.relnamespace
      join pg_class cf on cf.oid = k.confrelid join pg_namespace nf on nf.oid = cf.relnamespace
      where k.contype = 'f'
        and ((nr.nspname = 'private' and cr.relname like 'accessori%'
              and not (nf.nspname = 'private' and cf.relname like 'accessori%')
              and not (nf.nspname = 'public' and cf.relname = 'profiles'))
          or (nf.nspname = 'private' and cf.relname like 'accessori%'
              and not (nr.nspname = 'private' and cr.relname in ('cantina_accessori', 'annunci_accessori_categorie'))
              and not (nr.nspname = 'private' and cr.relname like 'accessori%')))),
    '');

  perform pg_temp.registra(26, 'nessuna colonna di prezzo, valuta, importo, IVA, commissione, peso, dimensioni, fornitore o pagamento nelle tabelle accessori',
    not exists (
      select 1 from information_schema.columns
      where table_schema = 'private' and table_name like 'accessori%'
        and column_name ~* '(prezzo|price|valuta|currency|cents|importo|amount|(^|_)iva(_|$)|(^|_)vat(_|$)|commission|peso|weight|dimension|fornitor|supplier|payment|pagamento|checkout|spedizion|shipping)'),
    (select string_agg(table_name || '.' || column_name, ',') from information_schema.columns
     where table_schema = 'private' and table_name like 'accessori%'));

  -- 27: nessuna porta di transazione: le sole funzioni accessori eseguibili da
  -- anonimo sono le tre letture; nessuna porta accessori scrive su ordini.
  select array_agg(p.proname::text order by p.proname) into v_chiavi
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'accessori%'
    and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.registra(27, 'anonimo esegue solo le tre letture pubbliche; le nove porte admin non sono eseguibili da anon; nessuna funzione accessori cita ordini, pagamenti o annunci',
    v_chiavi = array['accessori_categorie_elenca', 'accessori_dettaglio', 'accessori_elenca']
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'accessori_admin_%'
           and has_function_privilege('authenticated', p.oid, 'execute')
           and not has_function_privilege('anon', p.oid, 'execute')) = 9
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private') and p.proname like 'accessori%'
        and p.prosrc ~* '(public\.|private\.)?(orders|payments|payouts|listings|proposals|bottle_units|wines|marketplace_config|balance_)'),
    array_to_string(v_chiavi, ','));

  -- 28: volatilita: letture stable, scritture volatili (modo transazione PostgREST).
  perform pg_temp.registra(28, 'volatilita: sei letture stable, sei scritture volatili (PostgREST sceglie il modo transazione dalla volatilita)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.provolatile = 's' and p.proname in (
       'accessori_categorie_elenca', 'accessori_elenca', 'accessori_dettaglio',
       'accessori_admin_stato', 'accessori_admin_categorie_elenca', 'accessori_admin_elenca',
       'accessori_admin_dettaglio')) = 7
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.provolatile = 'v' and p.proname in (
           'accessori_admin_salva', 'accessori_admin_categoria_salva',
           'accessori_admin_immagini_imposta', 'accessori_admin_stato_imposta',
           'accessori_admin_visibilita_imposta')) = 5,
    '');

  -- 35: bucket privato e superficie di Storage: per anon esiste una sola policy
  -- sul bucket (SELECT delle foto pubblicate), nessuna di scrittura; gli helper
  -- del rilascio non sono eseguibili dai ruoli client.
  perform pg_temp.registra(35, 'bucket privato; per anon una sola policy sul bucket (SELECT delle foto pubblicate), nessuna di scrittura; helper di rilascio non eseguibili da anon e authenticated',
    not (select public from storage.buckets where id = 'accessori-media')
    and (select count(*) from pg_policies
         where schemaname = 'storage' and tablename = 'objects'
           and (qual like '%accessori-media%' or with_check like '%accessori-media%')
           and 'anon' = any (roles)) = 1
    and exists (select 1 from pg_policies
                where schemaname = 'storage' and tablename = 'objects'
                  and policyname = 'accessori_media_select_pubblicate'
                  and cmd = 'SELECT' and 'anon' = any (roles))
    and not has_function_privilege('anon', 'private.accessori_puo_rilasciare()', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_puo_rilasciare()', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_rilascio_richiesto()', 'execute')
    and not has_function_privilege('authenticated', 'private.accessori_impostazioni_guard()', 'execute'),
    '');

  -- 29: nessun effetto sul resto del marketplace.
  perform pg_temp.registra(29, 'annunci, ordini, vini, bottiglie, pagamenti e configurazione commerciale invariati dopo tutta la griglia',
    concat_ws('/',
      (select count(*) from public.listings), (select count(*) from public.orders),
      (select count(*) from public.wines), (select count(*) from public.bottle_units),
      (select count(*) from public.payments), (select count(*) from public.marketplace_config)) = v_snap_prima,
    v_snap_prima);

end $$;

select id, descrizione, passed, detail
from esiti_12zh
order by id;

rollback;
