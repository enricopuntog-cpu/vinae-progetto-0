-- Fase 12d - griglia COMPORTAMENTALE dei club creati dagli utenti.
-- Eseguire dopo la migrazione:
--   20260822000000_club_user_creation.sql
--
-- STATO DI ESECUZIONE. Dichiarato per primo, perche e la cosa piu importante
-- che questo file dice di se stesso:
--
--   ESEGUITA il 2026-08-24 su PostgreSQL 17.10 (Debian) in un container usa e
--   getta, dal vuoto, con il bootstrap 9c e tutte e trentacinque le migrazioni
--   del repository applicate nell'ordine reale, ciascuna nella propria
--   transazione.
--
--     prima esecuzione:      47 PASSA / 1 FALLISCE
--     seconda e definitiva:  48 PASSA / 0 FALLISCE
--
--   L'unico fallimento era della GRIGLIA, non della migrazione: il caso 43
--   passava a `segnalazione_invia` il motivo «Fuori tema», che non esiste in
--   public.report_reasons per il bersaglio `post`. La funzione rispondeva
--   22023 «Motivo non ammesso per questo tipo di bersaglio», e il caso
--   sembrava dire che un club OWNER_ONLY blocca la moderazione, mentre la
--   moderazione non era mai stata toccata. Il motivo corretto e «Off-topic per
--   il club». E l'avvertimento della 12bc che si ripete: il fallimento era
--   invisibile a chi leggeva il file.
--
--   Una correzione della MIGRAZIONE e emersa prima della griglia, applicando
--   le migrazioni in ordine: `create or replace view` non puo inserire colonne
--   in mezzo a un elenco esistente («cannot change name of view column
--   "membri" to "owner_id"»). La vista public_clubs si ricrea con drop + create.
--
--   I due caveat dichiarati come ipotesi si sono risolti da soli e NON hanno
--   prodotto rossi: l'ordine alfabetico dei trigger su club_posts non cambia
--   l'esito dei casi 32-36, e la verifica di esistenza su storage.objects nel
--   corpo di club_crea funziona perche la funzione e SECURITY DEFINER e il suo
--   proprietario e superuser in questo ambiente.
--
--   NON e verificato dalla griglia il caso 47 (rename `Circolo Vinea` ->
--   `Club Vinea`): il club storico `circolo-vinea` non e creato da nessuna
--   migrazione, e in un database vuoto quella riga non esiste. Il caso passa
--   in modo vacuo. Il rename si verifica soltanto in produzione.
--
--   NON E MAI STATA ESEGUITA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej), e
--   farlo resta un'autorizzazione esplicita separata, PER GRIGLIA e non per
--   progetto. Questa SCRIVE - crea utenti, club, post, risposte, like,
--   segnalazioni e oggetti nello Storage - quindi non e della categoria "sola
--   lettura" della 12a.
--
-- COME ESEGUIRLA. Come la 12bc: dal vuoto, applicando tutte le migrazioni del
-- repository nell'ordine reale, ciascuna nella PROPRIA TRANSAZIONE come fa
-- Supabase, sopra supabase/tests/9c_bootstrap_postgres_locale.sql.
--
-- CHE COSA MISURA
--   [1] casi 01-08  club_crea: il percorso felice, e chi decide che cosa
--   [2] casi 09-12  chi non puo creare un club
--   [3] casi 13-18  la validazione dell'input
--   [4] casi 19-22  lo slug: generato dal server, e le collisioni
--   [5] casi 23-30  la cover: percorso e non URL, e legata al proprietario
--   [6] casi 31-37  OPEN e OWNER_ONLY, che vivono nei trigger
--   [7] casi 38-43  cio che OWNER_ONLY NON tocca: lettura, follow, like,
--                   moderazione
--   [8] casi 44-48  controprove strutturali, e il rate limit
--
-- CHE COSA NON MISURA
--   * niente sull'interfaccia: nessuna schermata e stata aperta contro questo
--     database. Che il composer sia nascosto a un non proprietario e provato
--     altrove, in frontend-next/src/lib/phase12/club-view.test.ts, e comunque
--     non e una barriera: la barriera sono i casi 32 e 35;
--   * niente sulla preparazione dell'immagine: il ridisegno in WebP e la
--     rimozione dei metadati avvengono nel browser, e qui gli oggetti dello
--     Storage sono fixture inserite a mano;
--   * niente su PostgREST: la traduzione del rate limit in 429 e la lettura
--     via HTTP non passano di qui;
--   * nessuna concorrenza: tutti i casi sono sequenziali. In particolare il
--     loop di risoluzione delle collisioni di slug NON e provato contro due
--     creazioni simultanee dello stesso nome; la rete di sicurezza li e il
--     vincolo di chiave primaria su clubs.slug, non questa griglia.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------
-- Stesso impianto della 12bc, con una sola aggiunta: `risultati` porta anche
-- uno `slug`, perche club_crea non restituisce un uuid ma una riga di clubs, e
-- cio che i casi successivi devono nominare e lo slug che il SERVER ha scelto.
-- Rileggerlo dal database invece di ricostruirlo qui e il punto: se la griglia
-- calcolasse lo slug atteso, proverebbe soltanto che due generatori sono
-- d'accordo.

drop table if exists esiti_12d;
drop table if exists risultati;

create temporary table esiti_12d (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_caso text, p_ok boolean, p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_12d (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create temporary table risultati (
  chiave text primary key,
  esito text not null,
  id uuid,
  slug text
);

-- Esegue p_sql impersonando p_uid e conserva 'SQLSTATE|messaggio' oppure
-- 'NESSUN_ERRORE'. Il BEGIN...EXCEPTION interno e una sottotransazione: quando
-- il passo fallisce come previsto la sua scrittura viene annullata e non lascia
-- residui.
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

-- Come `esegui`, per un'istruzione con `returning id`.
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

-- Per club_crea: conserva lo slug assegnato dal server.
create or replace function pg_temp.esegui_slug(
  p_chiave text, p_sql text, p_uid uuid
) returns text language plpgsql as $$
declare v_esito text; v_slug text;
begin
  perform set_config('vinea.uid', p_uid::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into v_slug;
    v_esito := 'NESSUN_ERRORE';
  exception when others then
    v_esito := sqlstate || '|' || sqlerrm;
  end;
  reset role;
  insert into risultati (chiave, esito, slug) values (p_chiave, v_esito, v_slug)
    on conflict (chiave) do update set esito = excluded.esito, slug = excluded.slug;
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

create or replace function pg_temp.slug(p_chiave text)
returns text language sql stable as $$
  select slug from risultati where chiave = p_chiave;
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

-- Raffica per il rate limit di club:crea. Il ciclo sta dentro plpgsql, dove
-- l'ordine e garantito. Restituisce 'indice|SQLSTATE|messaggio' del primo passo
-- fallito, oppure 'tutte ok'.
create or replace function pg_temp.raffica_crea(p_uid uuid, p_quante integer)
returns text language plpgsql as $$
declare i integer; v text;
begin
  for i in 1..p_quante loop
    v := pg_temp.esegui('raffica_' || i, format($f$
      select public.club_crea('Raffica %s', 'Un club creato in raffica, per misurare il limite.')
    $f$, i), p_uid);
    if v <> 'NESSUN_ERRORE' then return i || '|' || v; end if;
  end loop;
  return 'tutte ok';
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
-- Sei utenti, un club storico senza proprietario, due oggetti nel bucket delle
-- cover. Creati come `postgres`, cioe fuori dalla RLS: e cio che fa un fixture,
-- e non e la cosa in prova.
--
-- Due proprietari e non uno: il club OWNER_ONLY appartiene a `proprietario2`,
-- cosi il non proprietario che si vede rifiutare la pubblicazione (casi 32 e
-- 35) e a sua volta uno che i club li crea. Se fosse un utente qualunque, il
-- rifiuto si potrebbe leggere come «non ha i privilegi»; cosi si legge solo
-- come «non e il proprietario di QUESTO club», che e la regola vera.
--
-- `proprietario` crea al massimo quattro club: il bucket club:crea e 5/ora, e
-- la raffica del caso 48 gira su un utente dedicato per non renderla dipendente
-- dall'ordine degli altri casi.

do $fix$
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    ('77777777-7777-7777-7777-777777777777', 'proprietario@vinea.test',
     '{"username":"proprietario"}'::jsonb),
    ('88888888-8888-8888-8888-888888888888', 'estraneo@vinea.test',
     '{"username":"estraneo"}'::jsonb),
    ('99999999-9999-9999-9999-999999999999', 'sospesoclub@vinea.test',
     '{"username":"sospesoclub"}'::jsonb),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'proprietario2@vinea.test',
     '{"username":"proprietario2"}'::jsonb),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'rimossoclub@vinea.test',
     '{"username":"rimossoclub"}'::jsonb),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'rafficaclub@vinea.test',
     '{"username":"rafficaclub"}'::jsonb);

  update public.profiles set stato_utente = 'sospeso'
    where id = '99999999-9999-9999-9999-999999999999';
  update public.profiles set stato_utente = 'rimosso'
    where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

  -- Il club storico: nessun owner_id, come i club di sistema gia in produzione.
  -- Serve a provare che la 12d non li ha cambiati (casi 37 e 44).
  insert into public.clubs (slug, nome, descrizione, territorio, tipologia)
    values ('legacy-senza-proprietario', 'Club senza proprietario',
            'Un club di sistema, come quelli che esistevano prima della 12d.',
            'Piemonte', 'Rosso');

  -- Due oggetti nel bucket. Il primo e la cover che `proprietario` usera
  -- davvero; il secondo sta nella cartella di `estraneo` e serve al caso 26.
  -- Si inseriscono le sole colonne che esistono anche nel bootstrap locale.
  insert into storage.objects (bucket_id, name, owner, metadata) values
    ('club-covers',
     '77777777-7777-7777-7777-777777777777/0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9.webp',
     '77777777-7777-7777-7777-777777777777', '{"mimetype":"image/webp"}'::jsonb),
    ('club-covers',
     '88888888-8888-8888-8888-888888888888/1b2c3d4e-5f60-4172-9384-95a6b7c8d9e0.webp',
     '88888888-8888-8888-8888-888888888888', '{"mimetype":"image/webp"}'::jsonb);
end
$fix$;

-- ===========================================================================
-- [1] club_crea: il percorso felice, e chi decide che cosa
-- ===========================================================================

select pg_temp.esegui_slug('club_open', $$
  select slug from public.club_crea(
    '  Barolo Club  ',
    '  Un club per chi beve Barolo e vuole parlarne.  ',
    array['Niente annunci mascherati', 'Si cita l''annata'],
    'OPEN')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(1,
  'Un utente autenticato crea un club',
  pg_temp.esito('club_open') = 'NESSUN_ERRORE',
  'il caso normale, senza il quale gli altri non dicono niente');

select pg_temp.registra(2,
  'Lo slug lo genera il server dal nome',
  pg_temp.slug('club_open') = 'barolo-club',
  'public.slugifica, la stessa di listing_crea: abbassa e toglie gli accenti insieme');

select pg_temp.registra(3,
  'owner_id e auth.uid(), e non e mai stato un parametro',
  pg_temp.leggi(format($$
    select owner_id::text from public.clubs where slug = %L
  $$, pg_temp.slug('club_open'))) = '77777777-7777-7777-7777-777777777777'
  and not exists (
    select 1 from information_schema.parameters
    where specific_schema = 'public'
      and specific_name like 'club_crea%'
      and parameter_name in ('p_owner_id', 'p_slug', 'p_membri')),
  'la firma non ha una porta per dichiararsi proprietario: non c''e nulla da non fidarsi');

select pg_temp.registra(4,
  'Nome e descrizione arrivano senza gli spazi ai bordi',
  pg_temp.leggi(format($$
    select nome || '|' || descrizione from public.clubs where slug = %L
  $$, pg_temp.slug('club_open')))
    = 'Barolo Club|Un club per chi beve Barolo e vuole parlarne.',
  'il trim e del server: un nome fatto di spazi non deve diventare un club');

select pg_temp.registra(5,
  'Le regole si conservano nell''ordine dato',
  pg_temp.leggi(format($$
    select array_to_string(regole, '~') from public.clubs where slug = %L
  $$, pg_temp.slug('club_open')))
    = 'Niente annunci mascherati~Si cita l''annata', '');

select pg_temp.registra(6,
  'Il creatore e gia membro: il follow e automatico',
  pg_temp.leggi(format($$
    select count(*)::text from public.club_memberships
    where club_slug = %L and user_id = '77777777-7777-7777-7777-777777777777'
  $$, pg_temp.slug('club_open'))) = '1',
  'nella stessa transazione dell''INSERT: non esiste un istante in cui il club e senza il suo autore');

select pg_temp.registra(7,
  'Per il creatore la vista dice membri = 1, seguito e mio',
  pg_temp.leggi(format($$
    select membri || '/' || seguito || '/' || mio
    from public.public_clubs where slug = %L
  $$, pg_temp.slug('club_open')),
    '77777777-7777-7777-7777-777777777777', 'authenticated') = '1/true/true',
  'i tre valori che la UI usa per decidere il redirect e il composer');

select pg_temp.registra(8,
  'Per un estraneo lo stesso club e visibile, non seguito e non suo',
  pg_temp.leggi(format($$
    select membri || '/' || seguito || '/' || mio
    from public.public_clubs where slug = %L
  $$, pg_temp.slug('club_open')),
    '88888888-8888-8888-8888-888888888888', 'authenticated') = '1/false/false',
  '`seguito` e `mio` sono del chiamante; `membri` e del club');

-- ===========================================================================
-- [2] Chi non puo creare un club
-- ===========================================================================

select pg_temp.esegui('crea_anonimo', $$
  select public.club_crea('Club anonimo', 'Provo a crearlo senza sessione.')
$$, null, 'anon');

select pg_temp.registra(9,
  'Un ANONIMO non crea club',
  pg_temp.esito('crea_anonimo') like '42501|%',
  'anon non ha execute sulla funzione: si ferma prima ancora del controllo su auth.uid()');

select pg_temp.esegui('crea_senza_uid', $$
  select public.club_crea('Club senza uid', 'Ruolo giusto, ma nessun auth.uid().')
$$, null, 'authenticated');

select pg_temp.registra(10,
  'Con il ruolo giusto ma senza auth.uid() il rifiuto e del dominio',
  pg_temp.esito('crea_senza_uid') like '42501|Devi accedere%',
  'primo controllo della RPC: il messaggio dice all''utente cosa fare');

select pg_temp.esegui('crea_sospeso', $$
  select public.club_crea('Club del sospeso', 'Un account sospeso prova a creare un club.')
$$, '99999999-9999-9999-9999-999999999999');

select pg_temp.registra(11,
  'Un utente SOSPESO non crea club',
  pg_temp.esito('crea_sospeso') like '42501|Account sospeso%',
  'decisione 7.6b primo livello, rifiutata PRIMA di aver creato il club');

select pg_temp.esegui('crea_rimosso', $$
  select public.club_crea('Club del rimosso', 'Un account rimosso prova a creare un club.')
$$, 'dddddddd-dddd-dddd-dddd-dddddddddddd');

select pg_temp.registra(12,
  'Un utente RIMOSSO non crea club',
  pg_temp.esito('crea_rimosso') like '42501|Account rimosso%',
  'secondo livello: non scrive, e la vista non gli restituisce nemmeno righe');

-- ===========================================================================
-- [3] La validazione dell'input
-- ===========================================================================
-- Ogni caso qui fallisce in una sottotransazione, quindi non consuma il bucket
-- club:crea del proprietario: il rate limit e stato consumato ma il rollback lo
-- annulla insieme al resto. E la ragione per cui i quattro club di
-- `proprietario` restano quattro.

select pg_temp.esegui('nome_spazi', $$
  select public.club_crea('   ', 'Una descrizione lunga a sufficienza per passare.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(13,
  'Un nome fatto di soli spazi non e un nome',
  pg_temp.esito('nome_spazi') like 'P0001|Il nome del club e obbligatorio%',
  'il trim precede la misura: altrimenti "   " supererebbe il minimo');

select pg_temp.esegui('nome_corto', $$
  select public.club_crea('B', 'Una descrizione lunga a sufficienza per passare.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(14,
  'Un nome di un solo carattere e rifiutato',
  pg_temp.esito('nome_corto') like 'P0001|Il nome deve essere compreso%', '');

select pg_temp.esegui('nome_lungo', format($$
  select public.club_crea(%L, 'Una descrizione lunga a sufficienza per passare.')
$$, repeat('x', 121)), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(15,
  'Un nome oltre i 120 caratteri e rifiutato',
  pg_temp.esito('nome_lungo') like 'P0001|Il nome deve essere compreso%', '');

select pg_temp.esegui('descrizione_corta', $$
  select public.club_crea('Club valido', 'Corta.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(16,
  'Una descrizione sotto i 10 caratteri e rifiutata',
  pg_temp.esito('descrizione_corta') like 'P0001|La descrizione deve essere compresa%', '');

select pg_temp.esegui('regole_troppe', format($$
  select public.club_crea('Club regolato', 'Una descrizione lunga a sufficienza per passare.', %L)
$$, (select array_agg('regola ' || i) from generate_series(1, 21) i)),
  '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(17,
  'Ventuno regole sono troppe',
  pg_temp.esito('regole_troppe') like 'P0001|Massimo 20 regole%', '');

select pg_temp.esegui('modalita_inventata', $$
  select public.club_crea('Club privato', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'PRIVATO')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(18,
  'Una modalita inventata e rifiutata: esistono solo OPEN e OWNER_ONLY',
  pg_temp.esito('modalita_inventata') like 'P0001|Modalita di pubblicazione non valida%',
  'in particolare non esiste un club privato: la 12d non ne ha introdotti');

-- ===========================================================================
-- [4] Lo slug: generato dal server, e le collisioni
-- ===========================================================================

select pg_temp.esegui_slug('collisione1', $$
  select slug from public.club_crea(
    'Barolo Club', 'Un secondo club con lo stesso identico nome del primo.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(19,
  'Un secondo club con lo stesso nome prende il suffisso -1',
  pg_temp.esito('collisione1') = 'NESSUN_ERRORE'
  and pg_temp.slug('collisione1') = 'barolo-club-1',
  'il nome duplicato NON e un errore: due persone possono voler parlare della stessa cosa');

select pg_temp.esegui_slug('collisione2', $$
  select slug from public.club_crea(
    'BAROLO CLUB', 'Un terzo club, scritto tutto in maiuscolo.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(20,
  'Le maiuscole non aggirano la collisione: il terzo e -2',
  pg_temp.slug('collisione2') = 'barolo-club-2',
  'slugifica abbassa PRIMA di confrontare, quindi la collisione la vede');

select pg_temp.registra(21,
  'I tre club esistono davvero e sono tre righe distinte',
  pg_temp.leggi($$
    select count(*)::text from public.clubs where slug like 'barolo-club%'
  $$) = '3',
  'il suffisso non ha sovrascritto niente');

select pg_temp.registra(22,
  'Il client non ha modo di proporre uno slug',
  not exists (
    select 1 from information_schema.parameters
    where specific_schema = 'public' and specific_name like 'club_crea%'
      and parameter_name = 'p_slug')
  and pg_temp.leggi($$
    select has_column_privilege('authenticated', 'public.clubs', 'slug', 'insert')::text
  $$) = 'false',
  'due sorgenti per lo slug sarebbero una di troppo, e quella sbagliata sarebbe il client');

-- ===========================================================================
-- [5] La cover: un percorso, e legato al proprietario
-- ===========================================================================
-- Il caso 28 dipende da un fatto dell'ambiente e non del dominio: club_crea e
-- SECURITY DEFINER di proprieta di `postgres`, e la verifica di esistenza legge
-- storage.objects, che ha la RLS attiva. Se il proprietario della funzione non
-- avesse BYPASSRLS, la select non troverebbe MAI l'oggetto e il caso 29
-- fallirebbe con «Cover non trovata» - cioe la griglia direbbe rosso su un
-- difetto di installazione, non di codice. Su Supabase `postgres` ha bypassrls;
-- chi esegue questa griglia altrove lo verifichi prima di dare la colpa alla
-- migrazione.

select pg_temp.esegui('cover_url_esterno', $$
  select public.club_crea('Club con URL', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN', 'https://esempio.invalid/cover.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(23,
  'Un URL esterno non e una cover',
  pg_temp.esito('cover_url_esterno') like 'P0001|Cover non valida%',
  'nel database va un percorso, mai un URL: e il requisito, e qui e un rifiuto');

select pg_temp.esegui('cover_url_storage', $$
  select public.club_crea('Club con URL storage', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN',
    'https://progetto.supabase.co/storage/v1/object/public/club-covers/77777777-7777-7777-7777-777777777777/0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(24,
  'Nemmeno l''URL COMPLETO dell''oggetto giusto passa',
  pg_temp.esito('cover_url_storage') like 'P0001|Cover non valida%',
  'il caso insidioso: la stringa contiene davvero il percorso valido. L''ancoraggio ^...$ e la ragione per cui non passa');

select pg_temp.esegui('cover_preset', $$
  select public.club_crea('Club con preset', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN', '/club-covers/vigna.svg')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(25,
  'Il percorso di un preset Vinea non finisce in questo campo',
  pg_temp.esito('cover_preset') like 'P0001|Cover non valida%',
  'i preset sono asset di public/: il client li ricodifica e li CARICA, cosi nel DB esiste un solo formato');

select pg_temp.esegui('cover_altrui', $$
  select public.club_crea('Club con cover altrui', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN',
    '88888888-8888-8888-8888-888888888888/1b2c3d4e-5f60-4172-9384-95a6b7c8d9e0.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(26,
  'La cover nella cartella di un ALTRO utente e rifiutata, benche esista',
  pg_temp.esito('cover_altrui') like 'P0001|Cover non valida%',
  'l''oggetto c''e davvero: il rifiuto e sull''appartenenza, non sull''esistenza');

select pg_temp.esegui('cover_traversal', $$
  select public.club_crea('Club con traversal', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN',
    '../88888888-8888-8888-8888-888888888888/1b2c3d4e-5f60-4172-9384-95a6b7c8d9e0.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(27,
  'Un percorso con `..` davanti e rifiutato',
  pg_temp.esito('cover_traversal') like 'P0001|Cover non valida%',
  'ancora l''ancoraggio iniziale: il percorso deve COMINCIARE con l''uid del chiamante');

select pg_temp.esegui('cover_fantasma', $$
  select public.club_crea('Club con fantasma', 'Una descrizione lunga a sufficienza per passare.',
                          '{}', 'OPEN',
    '77777777-7777-7777-7777-777777777777/ffffffff-ffff-4fff-8fff-ffffffffffff.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(28,
  'Un percorso ben formato ma senza oggetto nel bucket e rifiutato',
  pg_temp.esito('cover_fantasma') like 'P0001|Cover non trovata nel bucket%',
  'la forma non basta: la RPC guarda storage.objects. E il solo caso in cui il messaggio dice all''utente di ricaricare');

select pg_temp.esegui_slug('club_cover', $$
  select slug from public.club_crea(
    'Club con cover', 'Una descrizione lunga a sufficienza per passare.',
    '{}', 'OPEN',
    '77777777-7777-7777-7777-777777777777/0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9.webp')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(29,
  'Una cover propria e realmente caricata viene accettata, e nel DB c''e il PERCORSO',
  pg_temp.esito('club_cover') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select cover_image from public.clubs where slug = %L
  $$, pg_temp.slug('club_cover')))
    = '77777777-7777-7777-7777-777777777777/0a1b2c3d-4e5f-4061-8273-8495a6b7c8d9.webp',
  'nessun http, nessun /storage/: l''indirizzo lo ricompone il client dalla configurazione');

select pg_temp.esegui('cover_forzata', format($$
  update public.clubs set cover_image = 'https://esempio.invalid/cover.webp'
  where slug = %L
$$, pg_temp.slug('club_cover')), null, 'postgres');

select pg_temp.registra(30,
  'Nemmeno un writer privilegiato puo mettere un URL in cover_image',
  pg_temp.esito('cover_forzata') like '23514|%clubs_cover_image_vinea_check%',
  'il CHECK vincola la TABELLA: vale per ogni percorso presente e futuro, service_role compreso');

-- ===========================================================================
-- [6] OPEN e OWNER_ONLY
-- ===========================================================================
-- Il club OWNER_ONLY e di `proprietario2`. Chi si vede rifiutare la
-- pubblicazione e `proprietario`, che di club ne ha creati quattro: cosi il
-- rifiuto non si puo leggere come mancanza di privilegi.
--
-- ORDINE DEI TRIGGER. I BEFORE INSERT su club_posts scattano in ordine
-- alfabetico di nome: immutabile, owner_only, riferimenti, scrittura_social.
-- `owner_only` precede quindi il guard sociale della 9b, e questo si vede in un
-- caso solo: un utente SOSPESO che scrive in un club OWNER_ONLY non suo riceve
-- «Solo il proprietario...» invece di «Account sospeso». Sono due rifiuti
-- entrambi corretti e entrambi 42501, e la griglia non li mescola apposta - i
-- casi 11 e 32 misurano un utente attivo e un utente sospeso separatamente.

select pg_temp.esegui_slug('club_chiuso', $$
  select slug from public.club_crea(
    'Le mie note', 'Un club in cui scrivo soltanto io, ma che chiunque puo leggere.',
    array['Si legge, non si scrive'], 'OWNER_ONLY')
$$, 'cccccccc-cccc-cccc-cccc-cccccccccccc');

select pg_temp.registra(31,
  'Un club OWNER_ONLY si crea, e la modalita e memorizzata',
  pg_temp.esito('club_chiuso') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select posting_mode from public.clubs where slug = %L
  $$, pg_temp.slug('club_chiuso'))) = 'OWNER_ONLY', '');

select pg_temp.esegui('chiuso_post_estraneo', format($$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values (%L, 'discussione', 'Posso scrivere qui?', 'Provo a pubblicare in un club non mio.')
$$, pg_temp.slug('club_chiuso')), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(32,
  'In un club OWNER_ONLY un NON proprietario non pubblica',
  pg_temp.esito('chiuso_post_estraneo') like '42501|Solo il proprietario di questo club puo pubblicare%',
  'la regola vive nel trigger, non nella UI: vale anche a interfaccia aggirata');

select pg_temp.esegui_id('chiuso_post_owner', format($$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values (%L, 'discussione', 'Le note di questa settimana',
          'Apro io la discussione, come previsto dalla modalita.')
  returning id
$$, pg_temp.slug('club_chiuso')), 'cccccccc-cccc-cccc-cccc-cccccccccccc');

select pg_temp.registra(33,
  'In un club OWNER_ONLY il proprietario pubblica',
  pg_temp.esito('chiuso_post_owner') = 'NESSUN_ERRORE',
  'senza questo, il caso 32 proverebbe soltanto che nessuno scrive');

select pg_temp.esegui('chiuso_risposta_owner', format($$
  insert into public.club_post_risposte (post_id, corpo)
  values (%L, 'Aggiungo una nota mia.')
$$, pg_temp.rif('chiuso_post_owner')), 'cccccccc-cccc-cccc-cccc-cccccccccccc');

select pg_temp.registra(34,
  'In un club OWNER_ONLY il proprietario risponde',
  pg_temp.esito('chiuso_risposta_owner') = 'NESSUN_ERRORE', '');

select pg_temp.esegui('chiuso_risposta_estraneo', format($$
  insert into public.club_post_risposte (post_id, corpo)
  values (%L, 'Vorrei commentare.')
$$, pg_temp.rif('chiuso_post_owner')), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(35,
  'In un club OWNER_ONLY un NON proprietario non risponde',
  pg_temp.esito('chiuso_risposta_estraneo') like '42501|Solo il proprietario di questo club puo rispondere%',
  'il club del post lo risale il trigger dal padre: il client non lo dichiara');

select pg_temp.esegui('aperto_post_estraneo', format($$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values (%L, 'discussione', 'Il 2016 in Langa', 'Che ne pensate dell''annata?')
$$, pg_temp.slug('club_open')), '88888888-8888-8888-8888-888888888888');

select pg_temp.registra(36,
  'In un club OPEN chiunque pubblica, come prima della 12d',
  pg_temp.esito('aperto_post_estraneo') = 'NESSUN_ERRORE',
  'OPEN e esattamente il comportamento esistente: il trigger restituisce new e si fa da parte');

select pg_temp.esegui('legacy_post_estraneo', $$
  insert into public.club_posts (club_slug, tipo, titolo, corpo)
  values ('legacy-senza-proprietario', 'discussione', 'Nel club storico',
          'I club di sistema non hanno proprietario e restano aperti.')
$$, '88888888-8888-8888-8888-888888888888');

select pg_temp.registra(37,
  'Un club STORICO senza owner_id continua a funzionare',
  pg_temp.esito('legacy_post_estraneo') = 'NESSUN_ERRORE',
  'la migrazione e additiva: owner_id nullable, e il trigger esce subito quando e nullo');

-- ===========================================================================
-- [7] Cio che OWNER_ONLY NON tocca
-- ===========================================================================
-- OWNER_ONLY non e un club privato. Questi sei casi sono la ragione per cui
-- quella frase e vera invece di essere un'intenzione.

select pg_temp.registra(38,
  'Un ANONIMO legge un club OWNER_ONLY: descrizione e regole comprese',
  pg_temp.leggi(format($$
    select (descrizione is not null and array_length(regole, 1) = 1)::text
    from public.public_clubs where slug = %L
  $$, pg_temp.slug('club_chiuso')), null, 'anon') = 'true',
  'la modalita riguarda la scrittura: la scheda non chiede il permesso di mostrarsi');

select pg_temp.registra(39,
  'Un estraneo legge le discussioni di un club OWNER_ONLY',
  pg_temp.leggi(format($$
    select count(*)::text from public.public_club_posts where club_slug = %L
  $$, pg_temp.slug('club_chiuso')),
    '77777777-7777-7777-7777-777777777777', 'authenticated') = '1',
  'il post del proprietario si legge da chiunque: e un club leggibile, non un diario');

select pg_temp.esegui('chiuso_follow', format($$
  insert into public.club_memberships (club_slug) values (%L)
$$, pg_temp.slug('club_chiuso')), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(40,
  'Un estraneo SEGUE un club OWNER_ONLY',
  pg_temp.esito('chiuso_follow') = 'NESSUN_ERRORE',
  'il follow e invariato: la 12d non ha toccato club_memberships');

select pg_temp.esegui('chiuso_unfollow', format($$
  delete from public.club_memberships where club_slug = %L
$$, pg_temp.slug('club_chiuso')), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(41,
  'E smette di seguirlo quando vuole',
  pg_temp.esito('chiuso_unfollow') = 'NESSUN_ERRORE'
  and pg_temp.leggi(format($$
    select count(*)::text from public.club_memberships
    where club_slug = %L and user_id = '77777777-7777-7777-7777-777777777777'
  $$, pg_temp.slug('club_chiuso'))) = '0', '');

select pg_temp.esegui('chiuso_like', format($$
  insert into public.club_post_like (post_id) values (%L)
$$, pg_temp.rif('chiuso_post_owner')), '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(42,
  'Un estraneo mette LIKE a un post in un club OWNER_ONLY',
  pg_temp.esito('chiuso_like') = 'NESSUN_ERRORE',
  'il like e invariato: non e una pubblicazione');

-- Il motivo non e testo libero: `segnalazione_invia` lo confronta con
-- public.report_reasons per quel bersaglio. Per `post` l'elenco chiuso della
-- 12c e Contenuto inappropriato / Disinformazione / Off-topic per il club /
-- Spam commerciale. La prima stesura passava «Fuori tema», che non c'e: il
-- caso falliva con 22023 e sembrava un blocco della moderazione, mentre era
-- la griglia a inventare un motivo.
select pg_temp.esegui('chiuso_segnalazione', format($$
  select public.segnalazione_invia(
    'post'::public.report_target_tipo, %L,
    'Le note di questa settimana', 'Off-topic per il club', '', '{}', %L)
$$, pg_temp.rif('chiuso_post_owner'), pg_temp.slug('club_chiuso')),
  '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(43,
  'Un estraneo SEGNALA un post in un club OWNER_ONLY',
  pg_temp.esito('chiuso_segnalazione') = 'NESSUN_ERRORE',
  'la moderazione e invariata: un club chiuso in scrittura non e un club fuori dalle regole');

-- ===========================================================================
-- [8] Controprove strutturali, e il rate limit
-- ===========================================================================

select pg_temp.esegui('insert_diretto', $$
  insert into public.clubs (slug, nome, descrizione)
  values ('club-fatto-a-mano', 'Club fatto a mano', 'Provo a inserirlo direttamente.')
$$, '77777777-7777-7777-7777-777777777777');

select pg_temp.registra(44,
  'Nessun INSERT diretto su clubs: la RPC e l''unica porta',
  pg_temp.esito('insert_diretto') like '42501|permission denied%'
  and not pg_temp.leggi($$
    select (has_table_privilege('authenticated', 'public.clubs', 'insert')
         or has_table_privilege('anon', 'public.clubs', 'insert'))::text
  $$)::boolean,
  'se il grant esistesse, ogni controllo della RPC sarebbe aggirabile con una riga');

select pg_temp.registra(45,
  'club_crea si chiama cosi, e la esegue solo `authenticated`',
  pg_temp.leggi($$
    select has_function_privilege('authenticated',
      'public.club_crea(text,text,text[],text,text)', 'execute')::text
  $$) = 'true'
  and pg_temp.leggi($$
    select has_function_privilege('anon',
      'public.club_crea(text,text,text[],text,text)', 'execute')::text
  $$) = 'false',
  'il nome e parte del contratto: il client chiama esattamente club_crea');

select pg_temp.registra(46,
  'La vista public_clubs resta security_invoker = off',
  (select not coalesce(
     (select option_value = 'true' from pg_options_to_table(c.reloptions)
      where option_name = 'security_invoker'), false)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'public_clubs')
  and not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'public_clubs'
      and grantee in ('anon', 'authenticated')
      and privilege_type <> 'SELECT'),
  'la vista ha aggiunto tre colonne in LETTURA: clubs resta senza grant di scrittura');

select pg_temp.registra(47,
  'Il club storico si chiama `Club Vinea` e il suo slug e invariato',
  pg_temp.leggi($$
    select coalesce((select nome from public.clubs where slug = 'circolo-vinea'), 'ASSENTE')
  $$) in ('Club Vinea', 'ASSENTE'),
  'lo slug e chiave primaria e referenziata da notifications e reports: si rinomina solo cio che si vede. ASSENTE e legittimo se il club storico non e in questo database');

select pg_temp.registra(48,
  'Il bucket club:crea e 5/ora, e il sesto club lo trova esaurito',
  pg_temp.raffica_crea('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 6)
    like '6|%Troppe richieste%',
  'su un utente dedicato, cosi la saturazione non dipende dall''ordine degli altri casi');

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_12d order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti_12d;
