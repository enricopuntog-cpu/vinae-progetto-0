-- Fase 12b + 12c - griglia COMPORTAMENTALE dei contenuti dei club.
-- Eseguire dopo le tre migrazioni:
--   20260817120000_phase_12b_club_content.sql
--   20260817120500_phase_12c_report_target_enum.sql
--   20260817121000_phase_12c_club_moderation.sql
--
-- STATO DI ESECUZIONE. Dichiarato per primo, perche e la cosa piu importante
-- che questo file dice di se stesso, e perche qui e diverso dalla 12a:
--
--   QUESTA GRIGLIA E STATA ESEGUITA, e l'esito e 47 PASSA / 0 FALLISCE. Su
--   PostgreSQL 15.19 in container usa-e-getta, il 17 agosto 2026, dopo aver
--   applicato DAL VUOTO tutte e ventinove le migrazioni del repository
--   nell'ordine reale, ciascuna nella PROPRIA TRANSAZIONE come fa Supabase,
--   sopra supabase/tests/9c_bootstrap_postgres_locale.sql.
--
--   Nella stessa sessione e stato misurato, e non dedotto, il vincolo che
--   impone tre file di migrazione invece di uno: `alter type ... add value`
--   seguito dall'uso del valore nella STESSA transazione risponde
--   «ERROR: unsafe use of new value "..." of enum type report_target_tipo -
--   HINT: New enum values must be committed before they can be used.».
--
--   NON E MAI STATA ESEGUITA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej), e
--   farlo resta un'autorizzazione esplicita separata, PER GRIGLIA e non per
--   progetto: l'approvazione del merge delle migrazioni non la comprende.
--   Questa in particolare SCRIVE - crea utenti, club, bottiglie, annunci,
--   post, segnalazioni - quindi non e della categoria "sola lettura" della
--   12a, e sul progetto reale andrebbe trattata come le fixture di Fase 7 e 9.
--
-- LA 7E AVEVA RAGIONE, E L'HA AVUTA ANCHE QUI. La regola del repository e che
-- una griglia versionata e mai eseguita NON e una prova. Le esecuzioni di
-- questa sono state quattro - 25/42, poi 45/47, poi 46/47, poi 47/47 - e
-- NESSUNO dei fallimenti era un difetto delle migrazioni: erano tutti difetti
-- della griglia, e nessuno di essi era visibile leggendola. Chi la rilegge
-- tenga presente che il valore di queste cinque note non e storico: sono le
-- cinque cose che una griglia scritta e mai eseguita avrebbe dichiarato verdi.
--
--   [1] Dieci casi assegnavano un `id` esplicito nell'INSERT. `id` non e nel
--       grant di colonna, quindi Postgres rispondeva 42501 prima di arrivare
--       al trigger: il grant funzionava, era il test a chiedere un privilegio
--       che nessun client ha. Da qui `esegui_id`: gli id si leggono da
--       `returning`, non si decidono.
--   [2] I confronti erano sul solo SQLSTATE, e 42501 e insieme «permission
--       denied» e «Account sospeso»: un errore di privilegi si sarebbe
--       travestito da controllo di dominio superato. Ora ogni caso negativo
--       confronta ANCHE un frammento del messaggio.
--   [3] Il piu insidioso: i casi in piu passi mettevano "scrivi" e "poi
--       verifica" dentro la stessa espressione, unite da `and`. SQL NON
--       GARANTISCE l'ordine di valutazione degli operandi di `and`, e il
--       pianificatore puo riordinarli. Passavano per fortuna, finche il
--       ripristino - che ha bisogno della propria segnalazione creata prima -
--       e stato valutato al contrario. Da qui `esegui` + `esito`: ogni passo
--       che scrive e una ISTRUZIONE a se, e le istruzioni sono ordinate.
--   [4] Un caso inseriva in `reports` come `authenticated`, che su quella
--       tabella non ha alcun grant (9a): misurava un permesso negato invece
--       del CHECK che voleva provare.
--   [5] Un caso scriveva un apostrofo con quattro virgolette dentro un blocco
--       dollar-quoted destinato a EXECUTE, dove il raddoppio avviene una volta
--       sola: il titolo finiva con due apostrofi e il confronto falliva. Vale
--       la pena averlo lasciato: il corpo di un post italiano e pieno di
--       apostrofi, ed e la sola cosa che qui li esercita.
--
-- Cio che resta testo, e non risultato, sono le differenze fra questo Postgres
-- e Supabase: GoTrue, PostgREST (e quindi la traduzione in 429 del rate
-- limit), Realtime e i ruoli reali del progetto qui non ci sono.
--
-- CHE COSA MISURA
--   [1] casi 01-10  gli allegati di un post, e cosa il client non puo nominare
--   [2] casi 11-14  cosa e immutabile dopo la pubblicazione
--   [3] casi 15-18  decisione 7.6b: sospeso non scrive, rimosso non legge
--   [4] casi 19-24  risposte, like, conteggi e cio che la vista non pubblica
--   [5] casi 25-30  la segnalazione dei due bersagli nuovi
--   [6] casi 31-39  la rimozione: chi puo, cosa produce, e il ripristino
--   [7] casi 40-42  i vincoli che l'estensione dell'enum avrebbe potuto aprire
--   [8] casi 43-46  controprove: privilegi, viste, macchina di pagamento
--   [9] caso  47    il rate limit esiste davvero e si esaurisce
--
-- CHE COSA NON MISURA
--   * niente sull'interfaccia: nessuna schermata e stata aperta contro questo
--     database;
--   * nessuna concorrenza: tutti i casi sono sequenziali.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------

drop table if exists esiti_12bc;
drop table if exists risultati;

create temporary table esiti_12bc (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_caso text, p_ok boolean, p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_12bc (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create temporary table risultati (
  chiave text primary key,
  esito text not null,
  id uuid
);

-- Esegue p_sql impersonando p_uid e conserva 'SQLSTATE|messaggio' oppure
-- 'NESSUN_ERRORE'. Il BEGIN...EXCEPTION interno e una sottotransazione: quando
-- il passo fallisce come previsto la sua scrittura viene annullata e non lascia
-- residui - che e come la pulizia resta garantita anche sul percorso d'errore.
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
  insert into risultati (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

-- Come `esegui`, per un'istruzione con `returning id` o una RPC che restituisce
-- un uuid: conserva anche l'identificativo generato dal database.
create or replace function pg_temp.esegui_id(
  p_chiave text, p_sql text, p_uid uuid
) returns text language plpgsql as $$
declare v_esito text; v_id uuid;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into v_id;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati (chiave, esito, id) values (p_chiave, v_esito, v_id)
    on conflict (chiave) do update set esito = excluded.esito, id = excluded.id;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati where chiave = p_chiave;
$$;

create or replace function pg_temp.rif(p_chiave text)
returns uuid language sql stable as $$
  select id from risultati where chiave = p_chiave;
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
end;
$$;

-- Raffica per il rate limit: il ciclo sta dentro plpgsql, dove l'ordine e
-- garantito. Restituisce 'indice|SQLSTATE|messaggio' del primo passo fallito,
-- oppure 'tutte ok'.
create or replace function pg_temp.raffica(p_uid uuid, p_quante integer)
returns text language plpgsql as $$
declare i integer; v text;
begin
  for i in 1..p_quante loop
    v := pg_temp.esegui('raffica_' || i, format($f$
      insert into public.club_posts (club_slug, tipo, titolo, corpo)
      values ('barolo', 'discussione', 'Raffica %s', 'Corpo di prova.')
    $f$, i), p_uid);
    if v <> 'NESSUN_ERRORE' then return i || '|' || v; end if;
  end loop;
  return 'tutte ok';
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
-- Sei utenti, un club, tre bottiglie, tre annunci. Creati come `postgres`,
-- cioe fuori dalla RLS: e cio che fa un fixture, e non e la cosa in prova.

do $fix$
declare v_wine uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    ('11111111-1111-1111-1111-111111111111', 'autore@vinea.test',  '{"username":"autore"}'::jsonb),
    ('22222222-2222-2222-2222-222222222222', 'altro@vinea.test',   '{"username":"altro"}'::jsonb),
    ('33333333-3333-3333-3333-333333333333', 'admin@vinea.test',   '{"username":"moderatore"}'::jsonb),
    ('44444444-4444-4444-4444-444444444444', 'sospeso@vinea.test', '{"username":"sospeso"}'::jsonb),
    ('55555555-5555-5555-5555-555555555555', 'rimosso@vinea.test', '{"username":"rimossoutente"}'::jsonb),
    ('66666666-6666-6666-6666-666666666666', 'bucket@vinea.test',  '{"username":"bucket"}'::jsonb);

  insert into public.user_roles (user_id, role)
    values ('33333333-3333-3333-3333-333333333333', 'admin');

  update public.profiles set stato_utente = 'sospeso'
    where id = '44444444-4444-4444-4444-444444444444';
  update public.profiles set stato_utente = 'rimosso'
    where id = '55555555-5555-5555-5555-555555555555';

  insert into public.clubs (slug, nome, descrizione, territorio, tipologia)
    values ('barolo', 'Barolo e Barbaresco',
            'Il re dei vini, discusso da chi lo beve.', 'Piemonte', 'Rosso');

  select id into v_wine from public.wines order by created_at limit 1;

  insert into public.bottle_units (id, owner_id, wine_id) values
    ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', v_wine),
    ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', v_wine),
    ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', v_wine);

  insert into public.listings
    (id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, published_at)
  values
    ('bbbbbbbb-0000-0000-0000-000000000001', 'annuncio-mio-attivo',
     '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001',
     'attivo', 9900, now()),
    ('bbbbbbbb-0000-0000-0000-000000000002', 'annuncio-altrui-attivo',
     '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000002',
     'attivo', 12900, now()),
    ('bbbbbbbb-0000-0000-0000-000000000003', 'annuncio-mio-bozza',
     '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000003',
     'bozza', 5000, null);
end
$fix$;

-- ===========================================================================
-- [1] Gli allegati di un post, e cosa il client non puo nominare
-- ===========================================================================

select pg_temp.esegui_id('post1', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values ('barolo', 'discussione', 'Biondi-Santi 2016 fra 20 anni?',
          'L''annata e mitica. Come pensate evolvera?')
  returning id
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(1,
  'Un post senza allegati si pubblica',
  pg_temp.esito('post1') = 'NESSUN_ERRORE',
  'il caso normale, senza il quale gli altri non dicono niente');

select pg_temp.esegui('id_scelto', $$
  insert into public.club_posts (id, club_slug, tipo, titolo, corpo)
  values (gen_random_uuid(), 'barolo', 'discussione', 'Con id mio', 'Corpo.')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(2,
  'Il client non puo scegliere l''id di un post',
  pg_temp.esito('id_scelto') like '42501|permission denied%',
  'il grant di colonna non comprende `id`: e cio che ha rotto la prima esecuzione');

select pg_temp.esegui('autore_finto', $$
  insert into public.club_posts (club_slug, autore_id, tipo, titolo, corpo)
  values ('barolo', '22222222-2222-2222-2222-222222222222', 'discussione',
          'Firmato da un altro', 'Corpo.')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(3,
  'Il client non puo dichiarare di essere un altro autore',
  pg_temp.esito('autore_finto') like '42501|permission denied%',
  '`autore_id` fuori dal grant: arriva dal DEFAULT auth.uid(), mai dal client');

select pg_temp.esegui_id('post_bottiglia', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, bottle_unit_id)
  values ('barolo', 'degustazione', 'Aperta ieri sera', 'Note di sottobosco.',
          'aaaaaaaa-0000-0000-0000-000000000001')
  returning id
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(4,
  'Una bottiglia PROPRIA si puo collegare',
  pg_temp.esito('post_bottiglia') = 'NESSUN_ERRORE', '');

select pg_temp.esegui('bottiglia_altrui', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, bottle_unit_id)
  values ('barolo', 'degustazione', 'Non e mia', 'Provo a collegarla.',
          'aaaaaaaa-0000-0000-0000-000000000002')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(5,
  'Una bottiglia ALTRUI e rifiutata',
  pg_temp.esito('bottiglia_altrui') like '42501|Puoi collegare soltanto%',
  'club_post_riferimenti_guard, che legge bottle_units e mai cellar_environments');

select pg_temp.esegui_id('post_annuncio', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, listing_id)
  values ('barolo', 'annuncio', 'Vendo Barolo Brunate 2018',
          'Bottiglia allocata direttamente in cantina. Doppio pezzo.',
          'bbbbbbbb-0000-0000-0000-000000000001')
  returning id
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(6,
  'Un post `annuncio` con un annuncio PROPRIO e pubblico si pubblica',
  pg_temp.esito('post_annuncio') = 'NESSUN_ERRORE',
  'la lettura del mock: si annuncia la PROPRIA vendita');

select pg_temp.esegui('annuncio_altrui', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, listing_id)
  values ('barolo', 'annuncio', 'Vendo roba di un altro', 'Non e mia.',
          'bbbbbbbb-0000-0000-0000-000000000002')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(7,
  'Un post `annuncio` con un annuncio ALTRUI e rifiutato',
  pg_temp.esito('annuncio_altrui') like '42501|Un post di tipo annuncio%',
  'seconda condizione: pubblicita non richiesta, o dirottamento di traffico');

select pg_temp.esegui('annuncio_bozza', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, listing_id)
  values ('barolo', 'discussione', 'Che ne pensate?', 'Guardate qui.',
          'bbbbbbbb-0000-0000-0000-000000000003')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(8,
  'Un annuncio NON PUBBLICO e rifiutato anche su una discussione',
  pg_temp.esito('annuncio_bozza') like 'P0001|L''annuncio collegato non e pubblico%',
  'prima condizione: una bozza manderebbe il club su qualcosa che non si apre');

select pg_temp.esegui_id('post_citazione', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo, listing_id)
  values ('barolo', 'consiglio', 'Vale il prezzo?', 'Ho visto questo.',
          'bbbbbbbb-0000-0000-0000-000000000002')
  returning id
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(9,
  'Un annuncio altrui ma pubblico si cita in una discussione',
  pg_temp.esito('post_citazione') = 'NESSUN_ERRORE',
  'la condizione 2 vale SOLO per tipo = annuncio: qui e un riferimento');

select pg_temp.esegui('annuncio_senza_listing', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values ('barolo', 'annuncio', 'Vendo qualcosa', 'Ma non dico cosa.')
$$, '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(10,
  'Un post `annuncio` SENZA annuncio collegato e rifiutato',
  pg_temp.esito('annuncio_senza_listing') like '23514|%club_posts_annuncio_ha_listing%',
  'un titolo "Vendo…" che non porta da nessuna parte');

-- ===========================================================================
-- [2] Cosa e immutabile dopo la pubblicazione
-- ===========================================================================

-- L'apostrofo non e vezzo: il corpo di un post italiano ne e pieno, e dentro un
-- blocco dollar-quoted che finisce in EXECUTE le virgolette si raddoppiano una
-- volta sola. La prima stesura ne metteva quattro e il titolo finiva con due
-- apostrofi: il caso falliva sul confronto, e la migrazione non c'entrava.
select pg_temp.esegui('correggi_titolo', format($$
  update public.club_posts set titolo = 'Biondi-Santi 2016 fra vent''anni?'
  where id = %L
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(11,
  'Il titolo si corregge',
  pg_temp.esito('correggi_titolo') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select titolo from public.club_posts where id = %L
  $$, pg_temp.rif('post1'))) = 'Biondi-Santi 2016 fra vent''anni?', '');

select pg_temp.esegui('cambia_autore', format($$
  update public.club_posts set autore_id = '22222222-2222-2222-2222-222222222222'
  where id = %L
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.esegui('cambia_club', format($$
  update public.club_posts set club_slug = 'altro-club' where id = %L
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(12,
  'L''autore NON e riassegnabile e il club NON e cambiabile',
  pg_temp.esito('cambia_autore') like '42501|permission denied%'
  and pg_temp.esito('cambia_club') like '42501|permission denied%',
  'fuori dal grant di UPDATE: negato prima ancora di arrivare al trigger');

select pg_temp.esegui('service_role_sposta', format($$
  update public.club_posts set tipo = 'sondaggio' where id = %L
$$, pg_temp.rif('post1')), null, 'service_role');

select pg_temp.registra(13,
  'Nemmeno service_role sposta un post: il trigger vale anche per chi scavalca i grant',
  pg_temp.esito('service_role_sposta') like '42501|Di un post pubblicato%',
  'private.club_post_immutabile_guard: il grant lo scavalca, il trigger no');

select pg_temp.esegui('dirotta_altrui', format($$
  update public.club_posts set titolo = 'Dirottato' where id = %L
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(14,
  'Il post di un ALTRO non si modifica',
  pg_temp.esito('dirotta_altrui') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select titolo from public.club_posts where id = %L
  $$, pg_temp.rif('post1'))) <> 'Dirottato',
  'la RLS non solleva: filtra a zero righe, e la UPDATE non tocca nulla');

-- ===========================================================================
-- [3] Decisione 7.6b
-- ===========================================================================

select pg_temp.esegui('sospeso_post', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values ('barolo', 'discussione', 'Sono sospeso', 'Ma scrivo lo stesso.')
$$, '44444444-4444-4444-4444-444444444444');

select pg_temp.registra(15,
  'Un utente SOSPESO non pubblica',
  pg_temp.esito('sospeso_post') like '42501|Account sospeso%',
  'private.scrittura_social_guard della 9b, invariata e riusata');

select pg_temp.esegui('sospeso_risposta', format($$
  insert into public.club_post_risposte (post_id, corpo)
  values (%L, 'Rispondo lo stesso.')
$$, pg_temp.rif('post1')), '44444444-4444-4444-4444-444444444444');

select pg_temp.esegui('sospeso_like', format($$
  insert into public.club_post_like (post_id) values (%L)
$$, pg_temp.rif('post1')), '44444444-4444-4444-4444-444444444444');

select pg_temp.registra(16,
  'Un utente SOSPESO non risponde e non mette like',
  pg_temp.esito('sospeso_risposta') like '42501|Account sospeso%'
  and pg_temp.esito('sospeso_like') like '42501|Account sospeso%',
  'tutte e tre le tabelle prendono il guard');

select pg_temp.registra(17,
  'Un utente RIMOSSO non legge le discussioni',
  pg_temp.leggi('select count(*)::text from public.public_club_posts',
                '55555555-5555-5555-5555-555555555555', 'authenticated') = '0',
  'secondo livello: toglie anche l''accesso in visione');

select pg_temp.registra(18,
  'Un ANONIMO legge le discussioni e non e toccato dal filtro',
  pg_temp.leggi('select count(*)::text from public.public_club_posts',
                null, 'anon')::integer = 4,
  'per anon auth.uid() e nullo, il not exists e vero: vede i quattro post');

-- ===========================================================================
-- [4] Risposte, like e conteggi
-- ===========================================================================

select pg_temp.esegui_id('risposta1', format($$
  insert into public.club_post_risposte (post_id, corpo)
  values (%L, 'Secondo me evolvera benissimo.') returning id
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(19,
  'Si risponde a una discussione',
  pg_temp.esito('risposta1') = 'NESSUN_ERRORE', '');

select pg_temp.esegui('like1', format($$
  insert into public.club_post_like (post_id) values (%L)
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.esegui('like2', format($$
  insert into public.club_post_like (post_id) values (%L)
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(20,
  'Il like si mette; il secondo e lo stesso stato, non un errore nuovo',
  pg_temp.esito('like1') = 'NESSUN_ERRORE'
  and pg_temp.esito('like2') like '23505|%',
  'l''adapter tratta 23505 come stato voluto, come fa gia con il follow');

select pg_temp.registra(21,
  'I conteggi della vista sono quelli veri, e `piaciuto` e del solo chiamante',
  pg_temp.leggi(format($$
    select risposte || '/' || mi_piace || '/' || piaciuto || '/' || mio
    from public.public_club_posts where id = %L
  $$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222', 'authenticated')
    = '1/1/true/false'
  and pg_temp.leggi(format($$
    select piaciuto || '/' || mio from public.public_club_posts where id = %L
  $$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111', 'authenticated')
    = 'false/true',
  'chi non ha messo like vede lo stesso conteggio e piaciuto = false');

select pg_temp.registra(22,
  'Nessuno legge i like altrui',
  pg_temp.leggi('select count(*)::text from public.club_post_like',
                '11111111-1111-1111-1111-111111111111', 'authenticated') = '0',
  'la RLS confina alle righe proprie: l''autore del post non sa CHI ha messo like');

select pg_temp.registra(23,
  'La vista NON pubblica l''identificativo della bottiglia, ma pubblica il vino',
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'public_club_posts'
      and column_name = 'bottle_unit_id')
  and pg_temp.leggi(format($$
    select (vino_produttore is not null)::text
    from public.public_club_posts where id = %L
  $$, pg_temp.rif('post_bottiglia')), null, 'anon') = 'true',
  'pubblica il vino di cui si parla, mai la chiave con cui la cantina lo nomina');

select pg_temp.registra(24,
  'L''annuncio collegato e risolto attraverso public_listings',
  pg_temp.leggi(format($$
    select listing_slug || '/' || listing_prezzo_cents
    from public.public_club_posts where id = %L
  $$, pg_temp.rif('post_annuncio')), null, 'anon') = 'annuncio-mio-attivo/9900', '');

-- ===========================================================================
-- [5] Segnalazione dei due bersagli nuovi
-- ===========================================================================

select pg_temp.esegui_id('report_post', format($$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo, %L,
    'Biondi-Santi 2016 fra vent''anni?',
    'Off-topic per il club', '', '{}', 'barolo')
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(25,
  'Un post si segnala',
  pg_temp.esito('report_post') = 'NESSUN_ERRORE',
  'decisione 7.6a adempiuta: il bersaglio ora si risolve in una riga');

select pg_temp.esegui_id('report_commento', format($$
  select public.segnalazione_invia(
    'commento'::public.report_target_tipo, %L,
    'Secondo me evolvera benissimo.', 'Spam', '', '{}', 'barolo')
$$, pg_temp.rif('risposta1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(26,
  'Una risposta si segnala',
  pg_temp.esito('report_commento') = 'NESSUN_ERRORE', '');

select pg_temp.esegui('motivo_inventato', format($$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo, %L,
    'Aperta ieri sera', 'Motivo inventato', '', '{}', 'barolo')
$$, pg_temp.rif('post_bottiglia')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(27,
  'Un motivo fuori elenco e rifiutato anche per i bersagli nuovi',
  pg_temp.esito('motivo_inventato') like '22023|Motivo non ammesso%',
  'report_reasons e un vincolo referenziale, non un menu del client');

select pg_temp.esegui('bersaglio_fantasma', $$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo,
    '99999999-9999-9999-9999-999999999999',
    'Non esiste', 'Disinformazione', '', '{}', 'barolo')
$$, '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(28,
  'Un post inesistente non entra in coda',
  pg_temp.esito('bersaglio_fantasma') like 'P0001|Bersaglio non trovato%',
  'il ramo `case` nuovo di v_esiste');

select pg_temp.esegui('doppione', format($$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo, %L, 'Di nuovo',
    'Disinformazione', '', '{}', 'barolo')
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(29,
  'Il doppione sullo stesso post e riconosciuto',
  pg_temp.esito('doppione') like 'P0001|Hai gia una segnalazione aperta%',
  'il coalesce del controllo comprende le due colonne nuove');

select pg_temp.registra(30,
  'La colonna di bersaglio giusta e valorizzata, e la coda risolve il target_id',
  pg_temp.leggi(format($$
    select (target_post_id = %L)::text || '/' || (target_listing_id is null)::text
    from public.reports where id = %L
  $$, pg_temp.rif('post1'), pg_temp.rif('report_post'))) = 'true/true'
  and pg_temp.leggi(format($$
    select (target_id = %L)::text from public.moderation_report_queue where id = %L
  $$, pg_temp.rif('post1'), pg_temp.rif('report_post')),
    '33333333-3333-3333-3333-333333333333', 'authenticated') = 'true',
  'senza il coalesce esteso la coda mostrerebbe un bersaglio che non sa aprire');

-- ===========================================================================
-- [6] La rimozione
-- ===========================================================================

select pg_temp.esegui('rimozione_non_moderatore', format($$
  select public.moderazione_rimozione(%L, 'Ci provo.')
$$, pg_temp.rif('report_post')), '22222222-2222-2222-2222-222222222222');

select pg_temp.registra(31,
  'Un utente qualunque NON rimuove un contenuto',
  pg_temp.esito('rimozione_non_moderatore')
    like '42501|Azione riservata alla moderazione%',
  'private.moderazione_attore(), che scrive il predicato admin per esteso');

select pg_temp.esegui('rimozione', format($$
  select public.moderazione_rimozione(%L, 'Fuori tema, come segnalato.')
$$, pg_temp.rif('report_post')), '33333333-3333-3333-3333-333333333333');

select pg_temp.registra(32,
  'Il moderatore rimuove il post, che sparisce dalla lettura pubblica',
  pg_temp.esito('rimozione') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select count(*)::text from public.public_club_posts where id = %L
  $$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222', 'authenticated')
    = '0',
  'rimozione LOGICA: la vista non lo mostra piu');

select pg_temp.registra(33,
  'La riga esiste ancora, con chi l''ha rimossa e perche',
  pg_temp.leggi(format($$
    select (rimosso_at is not null)::text || '/' ||
           (rimosso_da = '33333333-3333-3333-3333-333333333333')::text || '/' ||
           (rimosso_motivo = 'Fuori tema, come segnalato.')::text
    from public.club_posts where id = %L
  $$, pg_temp.rif('post1'))) = 'true/true/true',
  'una segnalazione deve sopravvivere alla rimozione di cio che segnala');

select pg_temp.registra(34,
  'Rimuovere un post nasconde anche le sue risposte, senza toccarle',
  pg_temp.leggi(format($$
    select count(*)::text from public.public_club_post_risposte where post_id = %L
  $$, pg_temp.rif('post1')), null, 'anon') = '0'
  and pg_temp.leggi(format($$
    select (rimosso_at is null)::text from public.club_post_risposte where id = %L
  $$, pg_temp.rif('risposta1'))) = 'true',
  'il doppio filtro della vista: le risposte restano intatte per il ripristino');

select pg_temp.esegui('risposta_a_rimosso', format($$
  insert into public.club_post_risposte (post_id, corpo)
  values (%L, 'Ci siete ancora?')
$$, pg_temp.rif('post1')), '22222222-2222-2222-2222-222222222222');

select pg_temp.esegui('like_a_rimosso', format($$
  insert into public.club_post_like (post_id) values (%L)
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(35,
  'Non si risponde piu, e non si mette piu like, a un post rimosso',
  pg_temp.esito('risposta_a_rimosso') like 'P0001|Questa discussione non e piu%'
  and pg_temp.esito('like_a_rimosso') like 'P0001|Questa discussione non e piu%',
  'private.club_post_figlio_guard');

select pg_temp.esegui('modifica_rimosso', format($$
  update public.club_posts set corpo = 'Riscrivo tutto.' where id = %L
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(36,
  'L''autore non modifica piu un post rimosso',
  pg_temp.esito('modifica_rimosso') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select corpo from public.club_posts where id = %L
  $$, pg_temp.rif('post1'))) <> 'Riscrivo tutto.',
  'la policy filtra su rimosso_at is null: zero righe, nessuna modifica');

select pg_temp.registra(37,
  'L''audit registra l''azione con scope `club` e lo slug del club',
  pg_temp.leggi($$
    select scope::text || '/' || coalesce(club_slug, '-') || '/' || azione::text
    from public.audit_log where target_tipo = 'post' order by ts desc limit 1
  $$) = 'club/barolo/rimozione',
  'prima riga con scope club: la 9a creo il valore e nessuno poteva ancora usarlo');

-- Il ripristino ha bisogno di una pratica APERTA: moderazione_pratica della 9b
-- rifiuta una pratica gia `risolta`, e la rimozione ha chiuso la precedente.
-- Che l'autore possa segnalare il PROPRIO post e la scelta registrata nella
-- 12c: per lui e l'unica richiesta di revisione disponibile, perche non ha una
-- porta per cancellare cio che ha scritto.
select pg_temp.esegui_id('report_ripristino', format($$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo, %L, 'Il mio post rimosso',
    'Contenuto inappropriato', 'Chiedo revisione.', '{}', 'barolo')
$$, pg_temp.rif('post1')), '11111111-1111-1111-1111-111111111111');

select pg_temp.esegui('ripristino', format($$
  select public.moderazione_ripristino(%L, 'Revisione accolta.')
$$, pg_temp.rif('report_ripristino')), '33333333-3333-3333-3333-333333333333');

select pg_temp.registra(38,
  'Con una nuova pratica il moderatore ripristina, e il post torna leggibile',
  pg_temp.esito('report_ripristino') = 'NESSUN_ERRORE'
  and pg_temp.esito('ripristino') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select count(*)::text from public.public_club_posts where id = %L
  $$, pg_temp.rif('post1')), null, 'anon') = '1',
  'l''autore puo segnalare il proprio post: e la sua unica richiesta di revisione');

select pg_temp.esegui('ripristino_inutile', format($$
  select public.moderazione_ripristino(%L, 'Non era rimosso.')
$$, pg_temp.rif('report_commento')), '33333333-3333-3333-3333-333333333333');

select pg_temp.registra(39,
  'Ripristinare cio che non e rimosso e un errore, non un successo silenzioso',
  pg_temp.esito('ripristino_inutile')
    like 'P0001|Questo contenuto e gia nello stato richiesto%',
  'la condizione di transizione del motore, come l''array di stati della 9b');

-- ===========================================================================
-- [7] I vincoli che l'estensione dell'enum avrebbe potuto aprire
-- ===========================================================================
-- Come `postgres`: `reports` non ha alcun grant client (9a), quindi provare
-- questo INSERT come `authenticated` misurerebbe un permesso negato invece del
-- CHECK. E' l'errore che la seconda esecuzione ha trovato qui.

select pg_temp.esegui('due_bersagli', format($$
  insert into public.reports
    (codice, target_tipo, target_label, target_post_id, target_listing_id,
     motivo, priorita, reporter_id)
  values ('SEG-TEST-0001', 'post', 'due bersagli', %L,
          'bbbbbbbb-0000-0000-0000-000000000001',
          'Disinformazione', 'bassa', '22222222-2222-2222-2222-222222222222')
$$, pg_temp.rif('post_bottiglia')), null, 'postgres');

select pg_temp.registra(40,
  'Una segnalazione `post` non puo portare anche un bersaglio di annuncio',
  pg_temp.esito('due_bersagli') like '23514|%reports_target_%',
  'senza la ridefinizione, il case senza else tornava NULL e il CHECK passava');

select pg_temp.registra(41,
  'Il vincolo di coerenza ha il ramo `else`: un ottavo valore fallirebbe chiuso',
  (select pg_get_constraintdef(oid) ilike '%else false%'
   from pg_constraint where conname = 'reports_target_coerente'),
  'la correzione che rende la classe di difetto irripetibile, non risolta una volta');

select pg_temp.registra(42,
  'L''enum ha sette valori, e i sette motivi dei due nuovi ci sono',
  (select count(*) = 7 from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'report_target_tipo')
  and (select count(*) = 7 from public.report_reasons
       where target_tipo in ('post', 'commento')),
  'quattro motivi per post e tre per commento, copiati da data/moderation.ts');

-- ===========================================================================
-- [8] Controprove
-- ===========================================================================

select pg_temp.registra(43,
  'Nessuna funzione della macchina di pagamento e stata toccata dalla 12b/12c',
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in ('payout_prepara', 'payout_coda', 'payout_registra_esito',
                        'ordine_auto_rilascio_esegui', 'conferma_ricezione',
                        'ordine_contestazione_risolvi')
      and pg_get_functiondef(p.oid) ilike '%club_post%'),
  'vincolo della 9c: il pagamento non reagisce a nulla di sociale, club compresi');

select pg_temp.registra(44,
  'Nessun DELETE su post e risposte, nessun UPDATE sui like',
  not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('club_posts', 'club_post_risposte')
      and grantee in ('anon', 'authenticated') and privilege_type = 'DELETE')
  and not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'club_post_like'
      and grantee in ('anon', 'authenticated') and privilege_type = 'UPDATE'),
  'la rimozione e logica e appartiene alla moderazione; togliere un like e una DELETE');

select pg_temp.registra(45,
  'Le colonne di rimozione non sono scrivibili da nessun ruolo client',
  not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public'
      and table_name in ('club_posts', 'club_post_risposte')
      and column_name in ('rimosso_at', 'rimosso_da', 'rimosso_motivo')
      and grantee in ('anon', 'authenticated')
      and privilege_type in ('UPDATE', 'INSERT')),
  'terza regola di esposizione: unica porta la SECURITY DEFINER della 12c');

select pg_temp.registra(46,
  'Le due viste pubbliche sono security_invoker = off',
  (select count(*) = 2 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('public_club_posts', 'public_club_post_risposte')
     and not coalesce(
       (select option_value = 'true' from pg_options_to_table(c.reloptions)
        where option_name = 'security_invoker'), false)),
  'seconda regola di esposizione');

-- ===========================================================================
-- [9] Il rate limit
-- ===========================================================================
-- Su un utente dedicato, cosi la saturazione non dipende dall'ordine degli
-- altri casi ne li rende irripetibili nella stessa ora.

select pg_temp.registra(47,
  'Il bucket club:post e 10/ora, e l''undicesimo post lo trova esaurito',
  pg_temp.raffica('66666666-6666-6666-6666-666666666666', 11)
    like '11|%Troppe richieste%',
  'private.rate_limit_consume dentro il trigger: vincola ogni percorso');

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_12bc order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti_12bc;
