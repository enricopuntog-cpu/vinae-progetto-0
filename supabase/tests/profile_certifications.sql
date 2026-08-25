-- Certificazioni di profilo - griglia COMPORTAMENTALE della fondazione fiducia.
-- Eseguire dopo la migrazione:
--   20260825120000_profile_certifications.sql
--
-- STATO DI ESECUZIONE. Dichiarato per primo, perche e la cosa piu importante
-- che questo file dice di se stesso:
--
--   ESEGUITA il 25 agosto 2026 su PostgreSQL 17.10 in un container usa e
--   getta, dal vuoto: bootstrap `9c` e poi tutte le 37 migrazioni del
--   repository, ciascuna nella propria transazione, infine questo file.
--   Risultato: **33 PASSA / 0 FALLISCE**, e i sette contatori di residuo
--   finali tutti a zero.
--
--   NON E MAI STATA ESEGUITA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej), e
--   farlo non e autorizzato. Questa griglia SCRIVE: crea utenti, vini,
--   bottiglie, annunci e CERTIFICAZIONI. Appartiene alla categoria "usa e
--   getta" della 12bc/12d, non alla "sola lettura" della 12a.
--
-- COME ESEGUIRLA. Dal vuoto, su un container PostgreSQL 17 usa e getta,
-- applicando supabase/tests/9c_bootstrap_postgres_locale.sql e poi TUTTE le
-- migrazioni del repository nell'ordine reale, ciascuna nella PROPRIA
-- TRANSAZIONE come fa Supabase. Poi questo file.
--
-- CHE COSA PROVA, IN UNA RIGA. Che il badge "Verificato" non si accende per
-- nessuna delle scorciatoie che sarebbero comode: non per l'email confermata,
-- non per il profilo completo, non per la data di nascita dichiarata, e
-- soprattutto non perche l'interessato l'ha chiesto. E che quando si accende,
-- si spegne da solo appena la certificazione che lo regge decade.
--
-- CHE COSA NON PROVA. Non tocca PostgREST: i casi qui misurano ruoli e
-- privilegi in SQL diretto, che e un percorso diverso da quello del browser.
-- Non prova la conferma email, che vive in `auth.users.email_confirmed_at` e
-- non in questo schema - quello che prova e' che questo schema NON la
-- duplica e NON la trasforma in una certificazione forte.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------
-- Stesso impianto della 1A e della 12d.

drop table if exists esiti_cert;
drop table if exists risultati_cert;

create temporary table esiti_cert (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_caso text, p_ok boolean, p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_cert (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create temporary table risultati_cert (
  chiave text primary key,
  esito text not null
);

-- Esegue p_sql impersonando p_uid e conserva 'SQLSTATE|messaggio' oppure
-- 'NESSUN_ERRORE'. Il BEGIN...EXCEPTION interno e una sottotransazione:
-- quando il passo fallisce come previsto la sua scrittura viene annullata e
-- non lascia residui.
create or replace function pg_temp.esegui(
  p_chiave text, p_sql text, p_uid uuid default null,
  p_ruolo text default 'authenticated'
) returns text language plpgsql as $$
declare v_esito text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  begin
    execute p_sql;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati_cert (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_cert where chiave = p_chiave;
$$;

-- Sola lettura: nessun effetto, quindi e sicura anche dentro un `and`.
create or replace function pg_temp.leggi(
  p_sql text, p_uid uuid default null, p_ruolo text default 'postgres'
) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('vinea.uid', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_ruolo);
  execute p_sql into v;
  reset role;
  return v;
exception when others then
  reset role;
  return sqlstate || '|' || sqlerrm;
end;
$$;

-- `seller_verificato` di un annuncio, letto come lo legge davvero il catalogo:
-- da `anon`, attraverso la vista pubblica.
create or replace function pg_temp.badge(p_slug text)
returns text language sql as $$
  select pg_temp.leggi(
    format(
      'select coalesce(seller_verificato::text, ''NULL'') from public.public_listings where slug = %L',
      p_slug
    ),
    null, 'anon'
  );
$$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
-- Tre venditori che differiscono per UNA cosa sola, cosi quando un caso
-- fallisce si sa quale:
--   CERT1  email confermata, profilo completo, nessuna certificazione forte;
--   CERT2  identita certificata, venditore no;
--   CERT3  identita e venditore certificati.

insert into auth.users (id, email) values
  ('c1c1c1c1-1111-4111-8111-111111111111', 'nudo@cert.test'),
  ('c2c2c2c2-2222-4222-8222-222222222222', 'identita@cert.test'),
  ('c3c3c3c3-3333-4333-8333-333333333333', 'venditore@cert.test'),
  ('c4c4c4c4-4444-4444-8444-444444444444', 'operatore@cert.test');

-- `on conflict` e non `insert` secco: la creazione del profilo e un trigger su
-- auth.users (20260728000545), quindi le quattro righe ESISTONO GIA. Questo
-- passo non le crea - fissa username e data di nascita.
insert into public.profiles (id, username, dob) values
  ('c1c1c1c1-1111-4111-8111-111111111111', 'cert_nudo', '1980-01-01'),
  ('c2c2c2c2-2222-4222-8222-222222222222', 'cert_identita', '1980-01-01'),
  ('c3c3c3c3-3333-4333-8333-333333333333', 'cert_venditore', '1980-01-01'),
  ('c4c4c4c4-4444-4444-8444-444444444444', 'cert_operatore', '1980-01-01')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob;

insert into public.wines (id, slug, produttore, nome, annata, regione, tipo, formato) values
  ('cececece-1111-4111-8111-111111111111', 'cert-vino',
   'Azienda CERT', 'Rosso di Prova', 2018, 'Toscana', 'Rosso', '0,75 L');

insert into public.bottle_units (id, owner_id, wine_id) values
  ('cbcbcbcb-1111-4111-8111-111111111111',
   'c1c1c1c1-1111-4111-8111-111111111111', 'cececece-1111-4111-8111-111111111111'),
  ('cbcbcbcb-2222-4222-8222-222222222222',
   'c2c2c2c2-2222-4222-8222-222222222222', 'cececece-1111-4111-8111-111111111111'),
  ('cbcbcbcb-3333-4333-8333-333333333333',
   'c3c3c3c3-3333-4333-8333-333333333333', 'cececece-1111-4111-8111-111111111111');

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents) values
  ('cacacaca-1111-4111-8111-111111111111', 'cert-annuncio-nudo',
   'c1c1c1c1-1111-4111-8111-111111111111', 'cbcbcbcb-1111-4111-8111-111111111111', 10000),
  ('cacacaca-2222-4222-8222-222222222222', 'cert-annuncio-identita',
   'c2c2c2c2-2222-4222-8222-222222222222', 'cbcbcbcb-2222-4222-8222-222222222222', 10000),
  ('cacacaca-3333-4333-8333-333333333333', 'cert-annuncio-venditore',
   'c3c3c3c3-3333-4333-8333-333333333333', 'cbcbcbcb-3333-4333-8333-333333333333', 10000);

-- La pubblicazione passa dalla RPC reale del venditore, non da un UPDATE
-- diretto: i tre annunci devono stare nel catalogo per la stessa via degli altri.
select pg_temp.esegui('pubblica_nudo',
  $$ select public.listing_pubblica('cacacaca-1111-4111-8111-111111111111') $$,
  'c1c1c1c1-1111-4111-8111-111111111111');
select pg_temp.esegui('pubblica_identita',
  $$ select public.listing_pubblica('cacacaca-2222-4222-8222-222222222222') $$,
  'c2c2c2c2-2222-4222-8222-222222222222');
select pg_temp.esegui('pubblica_venditore',
  $$ select public.listing_pubblica('cacacaca-3333-4333-8333-333333333333') $$,
  'c3c3c3c3-3333-4333-8333-333333333333');

select pg_temp.registra(0,
  'I tre annunci di prova sono davvero nel catalogo pubblico',
  pg_temp.leggi($$
    select count(*)::text from public.public_listings where slug like 'cert-annuncio-%'
  $$, null, 'anon') = '3',
  'senza questo nessun caso sul badge significherebbe niente');

-- ---------------------------------------------------------------------------
-- [1] Nessuno si certifica da solo
-- ---------------------------------------------------------------------------

-- Prima porta: il privilegio. `authenticated` non ha alcun GRANT.
select pg_temp.esegui('auto_insert',
  $$ insert into public.profile_certifications (user_id, tipo, fonte)
     values ('c1c1c1c1-1111-4111-8111-111111111111', 'identita', 'verifica_interna_vinea') $$,
  'c1c1c1c1-1111-4111-8111-111111111111');

select pg_temp.registra(1,
  'Un utente autenticato non puo certificare se stesso',
  pg_temp.esito('auto_insert') like '42501|%',
  'e la prima porta: nessun GRANT di scrittura, quindi non arriva nemmeno al trigger');

-- Seconda porta: il trigger, che vale anche per chi ha i privilegi. Simula la
-- futura RPC di back office chiamata da una sessione autenticata che tenta di
-- emettere la certificazione a proprio nome.
select pg_temp.esegui('auto_insert_privilegiato',
  $$ insert into public.profile_certifications (user_id, tipo, fonte)
     values ('c4c4c4c4-4444-4444-8444-444444444444', 'identita', 'verifica_interna_vinea') $$,
  'c4c4c4c4-4444-4444-8444-444444444444', 'postgres');

select pg_temp.registra(2,
  'Nemmeno una sessione privilegiata emette una certificazione a proprio nome',
  pg_temp.esito('auto_insert_privilegiato') like '42501|%',
  'il vincolo sta in un trigger, quindi lega anche chi non passa dai GRANT');

-- Terza: forgiare la certificazione di un ALTRO, che e il caso interessante -
-- un utente qualunque che tenta di verificare un complice.
select pg_temp.esegui('forgia_altrui',
  $$ insert into public.profile_certifications (user_id, tipo, fonte)
     values ('c2c2c2c2-2222-4222-8222-222222222222', 'identita', 'verifica_interna_vinea') $$,
  'c1c1c1c1-1111-4111-8111-111111111111');

select pg_temp.registra(3,
  'Un utente autenticato non puo forgiare la verifica identita di un altro',
  pg_temp.esito('forgia_altrui') like '42501|%',
  'il trigger non basterebbe qui: la barriera e il GRANT assente');

-- ---------------------------------------------------------------------------
-- [2] La tabella base non e raggiungibile dal client
-- ---------------------------------------------------------------------------

select pg_temp.registra(4,
  'Un utente autenticato non legge la tabella delle certificazioni',
  pg_temp.leggi($$ select count(*)::text from public.profile_certifications $$,
    'c1c1c1c1-1111-4111-8111-111111111111', 'authenticated') like '42501|%',
  'nemmeno le proprie: la lettura personale passa da my_certifications');

select pg_temp.registra(5,
  'Un visitatore anonimo non legge la tabella delle certificazioni',
  pg_temp.leggi($$ select count(*)::text from public.profile_certifications $$,
    null, 'anon') like '42501|%');

select pg_temp.registra(6,
  'Nessuno dei due ruoli client legge la vista privata di validita',
  pg_temp.leggi($$ select count(*)::text from private.certificazioni_valide $$,
    'c1c1c1c1-1111-4111-8111-111111111111', 'authenticated') like '42501|%'
  and pg_temp.leggi($$ select count(*)::text from private.certificazioni_valide $$,
    null, 'anon') like '42501|%',
  'hanno USAGE sullo schema private dalla Fase 7: il privilegio va tolto sull''oggetto');

select pg_temp.registra(7,
  'RLS attiva e zero policy sulla tabella',
  pg_temp.leggi($$
    select (
      (select relrowsecurity::text from pg_class
        where oid = 'public.profile_certifications'::regclass)
      || '/' ||
      (select count(*)::text from pg_policies
        where schemaname = 'public' and tablename = 'profile_certifications')
    )
  $$) = 'true/0',
  'stessa forma di wine_price_observations: la barriera e l''assenza di porte');

-- ---------------------------------------------------------------------------
-- [3] L'email confermata non e una certificazione forte
-- ---------------------------------------------------------------------------

select pg_temp.registra(8,
  'Lo schema delle certificazioni non conosce l''email',
  pg_temp.leggi($$
    select coalesce(string_agg(enumlabel, ',' order by enumsortorder), '')
    from pg_enum where enumtypid = 'public.certificazione_tipo'::regtype
  $$) = 'identita,venditore',
  'la conferma email resta un fatto di auth.users e non diventa un tipo qui');

select pg_temp.registra(9,
  'La tabella non contiene email, data di nascita ne dati di documento',
  pg_temp.leggi($$
    select coalesce(string_agg(column_name, ',' order by column_name), '')
    from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_certifications'
  $$) = 'fonte,rilasciata_at,scade_at,tipo,user_id',
  'contiene esiti, mai prove: cinque colonne e nessuna di testo libero');

-- CERT1 ha email, profilo completo e data di nascita dichiarata, e nient'altro.
select pg_temp.registra(10,
  'Email confermata e profilo completo non fanno identita verificata',
  pg_temp.leggi($$
    select identita_verificata::text from public.my_certifications
  $$, 'c1c1c1c1-1111-4111-8111-111111111111', 'authenticated') = 'false');

select pg_temp.registra(11,
  'Email confermata e profilo completo non fanno venditore verificato',
  pg_temp.badge('cert-annuncio-nudo') = 'false',
  'e il caso che il prodotto vedra piu spesso: nessun badge, e va bene cosi');

-- ---------------------------------------------------------------------------
-- [4] L'identita non implica il venditore
-- ---------------------------------------------------------------------------

-- Da qui in avanti si certifica davvero, e lo fa l'operatore: `postgres` senza
-- `vinea.uid`, cioe la chiave di back office con auth.uid() nullo.
insert into public.profile_certifications (user_id, tipo, fonte) values
  ('c2c2c2c2-2222-4222-8222-222222222222', 'identita', 'verifica_interna_vinea'),
  ('c3c3c3c3-3333-4333-8333-333333333333', 'identita', 'verifica_interna_vinea');

select pg_temp.registra(12,
  'Identita certificata da sola non accende il badge del venditore',
  pg_temp.badge('cert-annuncio-identita') = 'false'
  and pg_temp.leggi($$ select identita_verificata::text from public.my_certifications $$,
    'c2c2c2c2-2222-4222-8222-222222222222', 'authenticated') = 'true',
  'l''interessato vede la propria identita verificata, il catalogo non vede un venditore');

select pg_temp.esegui('venditore_senza_identita',
  $$ insert into public.profile_certifications (user_id, tipo, fonte)
     values ('c1c1c1c1-1111-4111-8111-111111111111', 'venditore', 'verifica_interna_vinea') $$,
  null, 'postgres');

select pg_temp.registra(13,
  'Venditore verificato senza identita viene rifiutato in scrittura',
  pg_temp.esito('venditore_senza_identita') like '23514|%',
  'e un trigger e non un CHECK perche il vincolo attraversa due righe');

-- ---------------------------------------------------------------------------
-- [5] Quando il badge si accende davvero
-- ---------------------------------------------------------------------------

insert into public.profile_certifications (user_id, tipo, fonte) values
  ('c3c3c3c3-3333-4333-8333-333333333333', 'venditore', 'verifica_interna_vinea');

select pg_temp.registra(14,
  'Identita e venditore insieme accendono il badge, e lo vede anche un anonimo',
  pg_temp.badge('cert-annuncio-venditore') = 'true',
  'la vista annidata private.certificazioni_valide e leggibile dalla proiezione '
  'pubblica pur non essendolo dal chiamante');

select pg_temp.registra(15,
  'Il badge acceso non contagia gli altri due venditori',
  pg_temp.badge('cert-annuncio-nudo') = 'false'
  and pg_temp.badge('cert-annuncio-identita') = 'false');

-- ---------------------------------------------------------------------------
-- [6] Il badge si spegne da solo
-- ---------------------------------------------------------------------------

update public.profile_certifications
set rilasciata_at = now() - interval '2 days', scade_at = now() - interval '1 day'
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'identita';

select pg_temp.registra(16,
  'Identita scaduta spegne il badge anche se la certificazione venditore resta',
  pg_temp.badge('cert-annuncio-venditore') = 'false',
  'e la ragione per cui la proiezione ripete il controllo invece di fidarsi della scrittura');

update public.profile_certifications
set rilasciata_at = now(), scade_at = null
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'identita';

update public.profile_certifications
set rilasciata_at = now() - interval '2 days', scade_at = now() - interval '1 day'
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'venditore';

select pg_temp.registra(17,
  'Venditore scaduto spegne il badge anche con identita valida',
  pg_temp.badge('cert-annuncio-venditore') = 'false');

update public.profile_certifications
set rilasciata_at = now(), scade_at = null
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'venditore';

delete from public.profile_certifications
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'identita';

select pg_temp.registra(18,
  'Revocare l''identita spegne il badge senza toccare la riga venditore',
  pg_temp.badge('cert-annuncio-venditore') = 'false'
  and pg_temp.leggi($$
    select count(*)::text from public.profile_certifications
    where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'venditore'
  $$) = '1',
  'nessun trigger di cancellazione: la lettura fail-closed rende superfluo il vincolo');

insert into public.profile_certifications (user_id, tipo, fonte) values
  ('c3c3c3c3-3333-4333-8333-333333333333', 'identita', 'verifica_interna_vinea');

select pg_temp.registra(19,
  'Ripristinata l''identita, il badge torna acceso',
  pg_temp.badge('cert-annuncio-venditore') = 'true');

-- ---------------------------------------------------------------------------
-- [7] La proiezione personale non e una finestra sugli altri
-- ---------------------------------------------------------------------------

select pg_temp.registra(20,
  'my_certifications restituisce una sola riga, la propria',
  pg_temp.leggi($$
    select coalesce(string_agg(user_id::text, ','), 'VUOTO') from public.my_certifications
  $$, 'c3c3c3c3-3333-4333-8333-333333333333', 'authenticated')
    = 'c3c3c3c3-3333-4333-8333-333333333333');

select pg_temp.registra(21,
  'my_certifications e vuota per un visitatore anonimo',
  pg_temp.leggi($$ select count(*)::text from public.my_certifications $$, null, 'anon')
    in ('0', '42501|permission denied for view my_certifications'),
  'anon non ha il GRANT; se lo avesse, auth.uid() nullo darebbe comunque zero righe');

select pg_temp.registra(22,
  'my_certifications espone tre colonne, tutte derivate',
  pg_temp.leggi($$
    select coalesce(string_agg(column_name, ',' order by column_name), '')
    from information_schema.columns
    where table_schema = 'public' and table_name = 'my_certifications'
  $$) = 'identita_verificata,user_id,venditore_verificato',
  'nessuna fonte, nessuna data, nessuna email: solo a che punto sono');

-- ---------------------------------------------------------------------------
-- [8] La proiezione pubblica non ha allargato niente
-- ---------------------------------------------------------------------------

select pg_temp.registra(23,
  'public_listings ha una sola colonna in piu, ed e in coda',
  pg_temp.leggi($$
    select (
      (select count(*)::text from information_schema.columns
        where table_schema = 'public' and table_name = 'public_listings')
      || '/' ||
      (select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
        from information_schema.columns
        where table_schema = 'public' and table_name = 'public_listings'
          and ordinal_position >= 29)
    )
  $$) = '31/wine_provenienza,imballaggio_codice,seller_verificato',
  'create or replace view esige l''ordine: le trenta colonne della 9b sono ferme');

select pg_temp.registra(24,
  'public_listings non espone email, data di nascita ne fonte della verifica',
  pg_temp.leggi($$
    select count(*)::text
    from information_schema.columns
    where table_schema = 'public' and table_name = 'public_listings'
      and (column_name ilike '%email%' or column_name ilike '%dob%'
        or column_name ilike '%nascita%' or column_name ilike '%fonte%'
        or column_name ilike '%rilasciat%' or column_name ilike '%scade%')
  $$) = '0');

select pg_temp.registra(25,
  'I quattro predicati della 9b sopravvivono alla ridefinizione',
  pg_temp.leggi($$
    select (
      (case when pg_get_viewdef('public.public_listings'::regclass) like '%stato_utente <> ''rimosso''%'
        then 'R' else '-' end) ||
      (case when pg_get_viewdef('public.public_listings'::regclass) like '%bu.stato = ''chiusa''%'
        then 'C' else '-' end) ||
      (case when pg_get_viewdef('public.public_listings'::regclass) like '%l.stato = ''attivo''%'
        then 'A' else '-' end) ||
      (case when pg_get_viewdef('public.public_listings'::regclass) like '%ceduta_at IS NULL%'
        then 'D' else '-' end)
    )
  $$) = 'RCAD',
  'la rimozione 9b e i filtri 6a non sono stati persi riscrivendo la vista');

-- ---------------------------------------------------------------------------
-- [9] Fail-closed sulla fonte, e nessun backfill
-- ---------------------------------------------------------------------------

select pg_temp.registra(26,
  'La fonte ammette una sola specie, e nessun nome di fornitore',
  pg_temp.leggi($$
    select coalesce(string_agg(enumlabel, ',' order by enumsortorder), '')
    from pg_enum where enumtypid = 'public.certificazione_fonte'::regtype
  $$) = 'verifica_interna_vinea',
  'accendere un fornitore richiede label, vincolo e via d''ingresso in una migrazione nuova');

select pg_temp.registra(27,
  'Il vincolo sulla fonte esiste e lega anche service_role',
  pg_temp.leggi($$
    select count(*)::text from pg_constraint
    where conrelid = 'public.profile_certifications'::regclass
      and conname = 'profile_certifications_solo_fonti_interne'
  $$) = '1');

-- L'unica certificazione esistente nel database e quella che questa griglia ha
-- scritto: la migrazione non ne ha inventata nessuna.
select pg_temp.registra(28,
  'La migrazione non ha creato nessuna certificazione',
  pg_temp.leggi($$
    select count(*)::text from public.profile_certifications
    where user_id not in (
      'c1c1c1c1-1111-4111-8111-111111111111',
      'c2c2c2c2-2222-4222-8222-222222222222',
      'c3c3c3c3-3333-4333-8333-333333333333',
      'c4c4c4c4-4444-4444-8444-444444444444'
    )
  $$) = '0',
  'nessun backfill da email confermata, profilo completo o anzianita account');

-- ---------------------------------------------------------------------------
-- [10] Il client non modifica ne cancella
-- ---------------------------------------------------------------------------

select pg_temp.esegui('update_client',
  $$ update public.profile_certifications set scade_at = null
     where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' $$,
  'c3c3c3c3-3333-4333-8333-333333333333');

select pg_temp.esegui('delete_client',
  $$ delete from public.profile_certifications
     where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' $$,
  'c3c3c3c3-3333-4333-8333-333333333333');

select pg_temp.registra(29,
  'Il proprietario non modifica ne cancella le proprie certificazioni',
  pg_temp.esito('update_client') like '42501|%'
  and pg_temp.esito('delete_client') like '42501|%',
  'una certificazione che l''interessato puo cancellare o prorogare non certifica niente');

-- ---------------------------------------------------------------------------
-- [11] Il tempo scorre in una direzione sola
-- ---------------------------------------------------------------------------
-- La sezione [6] prova la fine dell'intervallo; questa prova l'inizio. Il
-- CHECK impedisce che la scadenza preceda il rilascio, ma non impedisce di
-- collocare TUTTO l'intervallo nel futuro: senza il predicato sull'inizio una
-- certificazione emessa con decorrenza a domani accenderebbe il badge oggi.

update public.profile_certifications
set rilasciata_at = now() + interval '10 days',
    scade_at      = now() + interval '20 days'
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'identita';

select pg_temp.registra(30,
  'Una certificazione con decorrenza futura non vale oggi',
  pg_temp.badge('cert-annuncio-venditore') = 'false',
  'l''intervallo e coerente e non scaduto, ma non e ancora cominciato');

-- Il guardiano deve leggere la stessa definizione delle viste: se l'identita
-- non e ancora in vigore, non regge una certificazione venditore nemmeno in
-- scrittura. La riga venditore esce prima, altrimenti l'INSERT fallirebbe
-- sulla chiave primaria e proverebbe un'altra cosa.
delete from public.profile_certifications
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'venditore';

select pg_temp.esegui('venditore_su_identita_futura',
  $$ insert into public.profile_certifications (user_id, tipo, fonte)
     values ('c3c3c3c3-3333-4333-8333-333333333333', 'venditore', 'verifica_interna_vinea') $$,
  null, 'postgres');

select pg_temp.registra(31,
  'Il guardiano rifiuta venditore se l''identita non e ancora in vigore',
  pg_temp.esito('venditore_su_identita_futura') like '23514|%',
  'trigger e proiezioni condividono private.certificazioni_valide, quindi non possono divergere');

update public.profile_certifications
set rilasciata_at = now() - interval '1 day', scade_at = null
where user_id = 'c3c3c3c3-3333-4333-8333-333333333333' and tipo = 'identita';

insert into public.profile_certifications (user_id, tipo, fonte) values
  ('c3c3c3c3-3333-4333-8333-333333333333', 'venditore', 'verifica_interna_vinea');

select pg_temp.registra(32,
  'Arrivata la decorrenza, la stessa identita torna a reggere il badge',
  pg_temp.badge('cert-annuncio-venditore') = 'true',
  'la data futura sospende la certificazione, non la avvelena');

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_cert order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce
from esiti_cert;

-- ---------------------------------------------------------------------------
-- Pulizia e verifica dei residui
-- ---------------------------------------------------------------------------
-- L'ordine conta: gli annunci prima delle bottiglie, le bottiglie prima dei
-- vini, e gli utenti per ultimi - profiles e profile_certifications escono in
-- cascata da auth.users.
--
-- Le tre pubblicazioni hanno prodotto altrettante osservazioni ASKING, perche
-- il trigger della 1A e vivo e ha fatto il suo mestiere. Quelle righe sono
-- append-only e rifiutano il DELETE anche a service_role: il trigger si
-- disattiva qui e solo qui, come fa la pulizia della griglia 1A, altrimenti la
-- chiave esterna su `wines` impedirebbe di togliere il vino di prova.

alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where wine_id = 'cececece-1111-4111-8111-111111111111';
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;

delete from public.listings where slug like 'cert-annuncio-%';
delete from public.bottle_units where wine_id = 'cececece-1111-4111-8111-111111111111';
delete from public.wines where slug = 'cert-vino';
delete from auth.users where email like '%@cert.test';

select
  (select count(*) from public.profile_certifications) as certificazioni_residue,
  (select count(*) from public.profiles where username like 'cert\_%') as profili_residui,
  (select count(*) from public.listings where slug like 'cert-annuncio-%') as annunci_residui,
  (select count(*) from public.bottle_units
     where wine_id = 'cececece-1111-4111-8111-111111111111') as bottiglie_residue,
  (select count(*) from public.wines where produttore = 'Azienda CERT') as vini_residui,
  (select count(*) from auth.users where email like '%@cert.test') as utenti_residui,
  (select count(*) from public.wine_price_observations
     where wine_id = 'cececece-1111-4111-8111-111111111111') as osservazioni_residue;
