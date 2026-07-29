-- ===========================================================================
-- Fase 6d-1 — Griglia di esiti degli invarianti di sicurezza.
--
-- COME SI ESEGUE. Incollare l'intero file nel SQL Editor del progetto Supabase
-- ed eseguire in una sola volta. Le ultime due istruzioni restituiscono la
-- tabella degli esiti e il totale: una riga per caso, colonna `esito` a PASSA o
-- FALLISCE. Nessun RAISE NOTICE — un esito che finisce nei log del server non è
-- un esito che si legge.
--
-- PERCHÉ NON pgTAP E NON UNA CI. La CLI Supabase e Docker non sono disponibili
-- nell'ambiente in cui questa fase è stata scritta, quindi non esiste un modo di
-- ricostruire le migrazioni da zero e lanciare i test in automatico. La CI che
-- lo farà è registrata nel backlog come lavoro successivo, non improvvisata qui.
--
-- NESSUN ACCOUNT REALE COME FIXTURE. Lo script crea tre utenti di prova e li
-- distrugge alla fine, insieme a vini, unità e annunci che ha generato.
--
-- COME SI IMPERSONA UN RUOLO, e perché è fatto così. Ogni caso passa il ruolo
-- alla funzione di asserzione, che cambia identità al proprio interno e la
-- restituisce prima di scrivere l'esito. La via più ovvia — cambiare ruolo nel
-- blocco principale e poi chiamare l'asserzione — non funziona: le funzioni
-- vivono nello schema temporaneo, su cui `anon` e `authenticated` non hanno
-- USAGE, e ogni caso fallirebbe sulla chiamata invece che sul merito.
--
-- ORDINE: eseguire DOPO 6d-1_preflight.sql e DOPO aver applicato la migrazione
-- 20260729230000_security_invariants.sql.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- [1] Tavolo degli esiti
-- ---------------------------------------------------------------------------

drop table if exists esiti_6d1;

create temporary table esiti_6d1 (
  n         integer primary key,
  caso      text not null,
  atteso    text not null,
  esito     text not null,
  dettaglio text not null default ''
);


-- ---------------------------------------------------------------------------
-- [2] Attrezzi
-- ---------------------------------------------------------------------------
-- `set_config(..., true)` è un SET LOCAL: vale fino alla fine della transazione
-- e non sporca la sessione. Si scrivono entrambe le forme delle claim perché
-- `auth.uid()` ha cambiato implementazione fra le versioni di Supabase e legge
-- l'una o l'altra. Tornare al ruolo iniziale è lecito perché SET ROLE guarda il
-- session_user, che resta quello di partenza.

create or replace function pg_temp.impersona(p_ruolo text, p_uid uuid)
returns void
language plpgsql
as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid::text, 'role', p_ruolo)::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
  end if;
  perform set_config('role', p_ruolo, true);
end;
$$;

-- Un caso che si misura su un numero: quante righe si vedono.
create or replace function pg_temp.att_numero(
  p_n integer, p_caso text, p_ruolo text, p_uid uuid, p_sql text, p_atteso bigint
)
returns void
language plpgsql
as $$
declare
  v_ottenuto bigint;
begin
  perform pg_temp.impersona(p_ruolo, p_uid);
  execute p_sql into v_ottenuto;
  perform set_config('role', 'postgres', true);

  insert into esiti_6d1 values (
    p_n, p_caso, 'valore = ' || p_atteso,
    case when v_ottenuto is not distinct from p_atteso then 'PASSA' else 'FALLISCE' end,
    'ottenuto ' || coalesce(v_ottenuto::text, 'NULL')
  );
exception when others then
  -- L'annullamento della sotto-transazione ha già riportato indietro il ruolo;
  -- si insiste perché l'esito va scritto comunque, e con privilegi pieni.
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1 values (
    p_n, p_caso, 'valore = ' || p_atteso, 'FALLISCE',
    'errore inatteso ' || sqlstate || ': ' || sqlerrm
  );
end;
$$;

-- Un caso che si misura su un rifiuto del database: il privilegio non c'è.
-- Si confronta lo SQLSTATE e non il messaggio, che dipende da lc_messages.
create or replace function pg_temp.att_sqlstate(
  p_n integer, p_caso text, p_ruolo text, p_uid uuid, p_sql text, p_stato text
)
returns void
language plpgsql
as $$
declare
  v_stato text;
  v_msg   text;
begin
  perform pg_temp.impersona(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);

  insert into esiti_6d1 values (
    p_n, p_caso, 'errore SQLSTATE ' || p_stato, 'FALLISCE', 'nessun errore sollevato'
  );
exception when others then
  v_stato := sqlstate;
  v_msg   := sqlerrm;
  -- L'annullamento della sotto-transazione ha già riportato indietro il ruolo;
  -- si insiste perché l'esito va scritto comunque, e con privilegi pieni.
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1 values (
    p_n, p_caso, 'errore SQLSTATE ' || p_stato,
    case when v_stato = p_stato then 'PASSA' else 'FALLISCE' end,
    v_stato || ': ' || v_msg
  );
end;
$$;

-- Un caso che si misura su un messaggio scritto da noi: qui il testo È il
-- comportamento atteso, perché è ciò che l'utente legge.
create or replace function pg_temp.att_messaggio(
  p_n integer, p_caso text, p_ruolo text, p_uid uuid, p_sql text, p_frammento text
)
returns void
language plpgsql
as $$
declare
  v_stato text;
  v_msg   text;
begin
  perform pg_temp.impersona(p_ruolo, p_uid);
  execute p_sql;
  perform set_config('role', 'postgres', true);

  insert into esiti_6d1 values (
    p_n, p_caso, 'messaggio con «' || p_frammento || '»', 'FALLISCE', 'nessun errore sollevato'
  );
exception when others then
  v_stato := sqlstate;
  v_msg   := sqlerrm;
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1 values (
    p_n, p_caso, 'messaggio con «' || p_frammento || '»',
    case when position(lower(p_frammento) in lower(v_msg)) > 0 then 'PASSA' else 'FALLISCE' end,
    v_stato || ': ' || v_msg
  );
end;
$$;


-- ---------------------------------------------------------------------------
-- [3] Fixture e casi
-- ---------------------------------------------------------------------------

do $blocco$
declare
  -- Tre identità. Il venditore è maggiorenne e possiede tutto; il curioso è un
  -- secondo autenticato che non possiede niente ed è il metro di «non
  -- proprietario»; il social è il profilo OAuth senza data di nascita, quello
  -- che la 5b ha reso possibile togliendo il NOT NULL da profiles.dob.
  v_venditore uuid := gen_random_uuid();
  v_curioso   uuid := gen_random_uuid();
  v_social    uuid := gen_random_uuid();

  -- Cinque bottiglie, una per condizione da provare.
  v_l_attivo  uuid;   v_b_attiva   uuid;   -- Alfa    — annuncio pubblicato, unità privata
  v_l_aperta  uuid;   v_b_aperta   uuid;   -- Beta    — bottiglia aperta
  v_l_cancel  uuid;   v_b_cancel   uuid;   -- Gamma   — tolta dalla cantina
  v_l_bozza   uuid;   v_b_bozza    uuid;   -- Delta   — bozza viva, unità cantina_pubblica
  v_l_venduto uuid;   v_b_venduta  uuid;   -- Epsilon — vendita conclusa
begin

  -- =========================================================================
  -- Fixture
  -- =========================================================================
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values
    ('00000000-0000-0000-0000-000000000000', v_venditore, 'authenticated', 'authenticated',
     'vinea-test-venditore@example.invalid', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     json_build_object('username', 'vinea_test_venditore', 'dob', '1990-01-01')::jsonb),
    ('00000000-0000-0000-0000-000000000000', v_curioso, 'authenticated', 'authenticated',
     'vinea-test-curioso@example.invalid', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     json_build_object('username', 'vinea_test_curioso', 'dob', '1985-06-15')::jsonb),
    -- Nessun `dob`: è esattamente ciò che arriva da Google e Facebook.
    ('00000000-0000-0000-0000-000000000000', v_social, 'authenticated', 'authenticated',
     'vinea-test-social@example.invalid', '', now(), now(), now(),
     '{"provider":"google","providers":["google"]}'::jsonb,
     json_build_object('username', 'vinea_test_social')::jsonb);

  -- Un ruolo al venditore, per il caso sull'enumerazione.
  insert into public.user_roles (user_id, role) values (v_venditore, 'moderator');

  -- Le unità nascono tutte dalla via «da zero» di listing_crea, che è l'unico
  -- scrittore di bottle_units.
  perform pg_temp.impersona('authenticated', v_venditore);

  select annuncio_id into v_l_attivo from public.listing_crea(
    p_produttore := 'Test6D1', p_nome := 'Alfa', p_annata := 2000,
    p_regione := 'Piemonte', p_tipo := 'Rosso', p_prezzo_cents := 12345);
  select annuncio_id into v_l_aperta from public.listing_crea(
    p_produttore := 'Test6D1', p_nome := 'Beta', p_annata := 2001,
    p_regione := 'Toscana', p_tipo := 'Rosso', p_prezzo_cents := 2000);
  select annuncio_id into v_l_cancel from public.listing_crea(
    p_produttore := 'Test6D1', p_nome := 'Gamma', p_annata := 2002,
    p_regione := 'Veneto', p_tipo := 'Bianco', p_prezzo_cents := 3000);
  select annuncio_id into v_l_bozza from public.listing_crea(
    p_produttore := 'Test6D1', p_nome := 'Delta', p_annata := 2003,
    p_regione := 'Sicilia', p_tipo := 'Rosso', p_prezzo_cents := 4000);
  select annuncio_id into v_l_venduto from public.listing_crea(
    p_produttore := 'Test6D1', p_nome := 'Epsilon', p_annata := 2004,
    p_regione := 'Puglia', p_tipo := 'Rosato', p_prezzo_cents := 5000);

  -- Alfa ed Epsilon si pubblicano; le altre restano in bozza.
  perform public.listing_pubblica(v_l_attivo);
  perform public.listing_pubblica(v_l_venduto);

  perform set_config('role', 'postgres', true);

  select bottle_unit_id into v_b_attiva  from public.listings where id = v_l_attivo;
  select bottle_unit_id into v_b_aperta  from public.listings where id = v_l_aperta;
  select bottle_unit_id into v_b_cancel  from public.listings where id = v_l_cancel;
  select bottle_unit_id into v_b_bozza   from public.listings where id = v_l_bozza;
  select bottle_unit_id into v_b_venduta from public.listings where id = v_l_venduto;

  -- Beta e Gamma: le bozze diventano terminali, così la bottiglia resta libera
  -- di essere aperta o tolta senza incrociare altri invarianti.
  update public.listings set stato = 'sospeso' where id in (v_l_aperta, v_l_cancel);

  perform pg_temp.impersona('authenticated', v_venditore);

  -- Alfa resta `privata` e porta i dati personali: è la bottiglia su cui si
  -- misura sia che il proprietario li legge, sia che nessun altro li vede.
  update public.bottle_units
  set note_personali           = 'Regalo di mio padre',
      apertura_pianificata     = date '2027-12-24',
      override_finestra_inizio = 2028
  where id = v_b_attiva;

  -- Delta è l'altro ramo della proiezione pubblica: nessun annuncio attivo, ma
  -- il proprietario l'ha dichiarata di cantina pubblica.
  update public.bottle_units set visibilita = 'cantina_pubblica' where id = v_b_bozza;

  perform public.bottiglia_apri(v_b_aperta, 'aperta per la prova');
  perform public.bottiglia_cancella(v_b_cancel);

  -- Epsilon: vendita conclusa da service_role, come oggi avviene davvero — la
  -- funzione di transizione a 'venduto' è Fase 7 e non esiste.
  perform set_config('role', 'postgres', true);
  update public.listings set stato = 'venduto' where id = v_l_venduto;

  -- =========================================================================
  -- A — Privacy di bottle_units
  -- =========================================================================
  perform pg_temp.att_numero(1,
    'Il proprietario legge le proprie note personali',
    'authenticated', v_venditore,
    format('select count(*) from public.bottle_units where id = %L and note_personali = %L',
           v_b_attiva, 'Regalo di mio padre'), 1);

  perform pg_temp.att_numero(2,
    'Il proprietario legge la propria pianificazione e il proprio override',
    'authenticated', v_venditore,
    format('select count(*) from public.bottle_units where id = %L
              and apertura_pianificata = date ''2027-12-24'' and override_finestra_inizio = 2028',
           v_b_attiva), 1);

  perform pg_temp.att_sqlstate(3,
    'Un anonimo non raggiunge la tabella bottle_units',
    'anon', null,
    format('select count(*) from public.bottle_units where id = %L', v_b_attiva), '42501');

  perform pg_temp.att_numero(4,
    'Un anonimo vede la bottiglia in vendita solo dalla proiezione a colonne chiuse',
    'anon', null,
    format('select count(*) from public.public_bottle_units where id = %L', v_b_attiva), 1);

  perform pg_temp.att_numero(5,
    'La proiezione mostra anche la bottiglia dichiarata di cantina pubblica',
    'anon', null,
    format('select count(*) from public.public_bottle_units where id = %L', v_b_bozza), 1);

  perform pg_temp.att_numero(6,
    'La bottiglia tolta dalla cantina non compare in nessuna proiezione',
    'anon', null,
    format('select count(*) from public.public_bottle_units where id = %L', v_b_cancel), 0);

  perform pg_temp.att_numero(7,
    'La proiezione pubblica non espone nessuna colonna personale',
    'postgres', null,
    'select count(*) from information_schema.columns
       where table_schema = ''public'' and table_name = ''public_bottle_units''
         and column_name in (''note_personali'', ''apertura_pianificata'',
                             ''prezzo_visibilita'', ''override_finestra_inizio'',
                             ''override_finestra_fine'', ''override_apice_inizio'',
                             ''override_apice_fine'', ''override_preferenza'',
                             ''override_nota'', ''deleted_at'', ''ceduta_at'')', 0);

  perform pg_temp.att_numero(8,
    'Note e override non sono leggibili da un altro utente registrato',
    'authenticated', v_curioso,
    format('select count(*) from public.bottle_units where id = %L', v_b_attiva), 0);

  -- =========================================================================
  -- B — Privacy di listings
  -- =========================================================================
  perform pg_temp.att_sqlstate(9,
    'Un anonimo non raggiunge la tabella listings',
    'anon', null,
    format('select count(*) from public.listings where id = %L', v_l_attivo), '42501');

  perform pg_temp.att_numero(10,
    'Un non proprietario non legge gli annunci altrui dalla tabella',
    'authenticated', v_curioso,
    format('select count(*) from public.listings where id = %L', v_l_attivo), 0);

  perform pg_temp.att_sqlstate(11,
    'Le colonne di tracciamento moderazione non sono leggibili da nessun ruolo client',
    'authenticated', v_venditore,
    format('select stato_motivo from public.listings where id = %L', v_l_attivo), '42501');

  -- =========================================================================
  -- C — Ruoli
  -- =========================================================================
  perform pg_temp.att_numero(12,
    'Il proprietario legge i propri ruoli',
    'authenticated', v_venditore,
    format('select count(*) from public.user_roles where user_id = %L', v_venditore), 1);

  perform pg_temp.att_numero(13,
    'I ruoli altrui non sono enumerabili',
    'authenticated', v_curioso,
    'select count(*) from public.user_roles', 0);

  perform pg_temp.att_sqlstate(14,
    'Nessuna autoassegnazione di ruoli',
    'authenticated', v_curioso,
    format('insert into public.user_roles (user_id, role) values (%L, ''admin'')', v_curioso),
    '42501');

  perform pg_temp.att_sqlstate(15,
    'has_role non è più eseguibile da un anonimo',
    'anon', null,
    format('select public.has_role(%L, ''admin'')', v_venditore), '42501');

  -- =========================================================================
  -- D — Controllo età server-side
  -- =========================================================================
  perform pg_temp.att_messaggio(16,
    'Profilo OAuth senza data di nascita respinto in vendita',
    'authenticated', v_social,
    'select * from public.listing_crea(
       p_produttore := ''Test6D1'', p_nome := ''Zeta'', p_annata := 2005,
       p_regione := ''Lazio'', p_tipo := ''Rosso'', p_prezzo_cents := 9900)',
    'data di nascita');

  perform pg_temp.att_numero(17,
    'La navigazione pubblica resta disponibile senza data di nascita',
    'authenticated', v_social,
    format('select count(*) from public.public_listings where id = %L', v_l_attivo), 1);

  -- =========================================================================
  -- E — Invarianti bottiglia–annuncio
  -- =========================================================================
  perform pg_temp.att_messaggio(18,
    'Una bottiglia aperta non si può mettere in vendita',
    'authenticated', v_venditore,
    format('select * from public.listing_crea(p_prezzo_cents := 5000, p_bottle_unit_id := %L)',
           v_b_aperta), 'aperta');

  perform pg_temp.att_messaggio(19,
    'Una bottiglia tolta dalla cantina non si può mettere in vendita',
    'authenticated', v_venditore,
    format('select * from public.listing_crea(p_prezzo_cents := 5000, p_bottle_unit_id := %L)',
           v_b_cancel), 'non è nella tua cantina');

  perform pg_temp.att_messaggio(20,
    'Non si apre una bottiglia con annuncio attivo, e il messaggio dice cosa fare',
    'authenticated', v_venditore,
    format('select public.bottiglia_apri(%L)', v_b_attiva), 'sospendi il suo annuncio');

  perform pg_temp.att_messaggio(21,
    'Non si toglie dalla cantina una bottiglia con annuncio attivo',
    'authenticated', v_venditore,
    format('select public.bottiglia_cancella(%L)', v_b_attiva), 'sospendi il suo annuncio');

  perform pg_temp.att_sqlstate(22,
    'Lo stato fisico non è più scrivibile con un UPDATE diretto',
    'authenticated', v_venditore,
    format('update public.bottle_units set stato = ''aperta'' where id = %L', v_b_attiva),
    '42501');

  perform pg_temp.att_sqlstate(23,
    'La cancellazione logica non è più scrivibile con un UPDATE diretto',
    'authenticated', v_venditore,
    format('update public.bottle_units set deleted_at = now() where id = %L', v_b_attiva),
    '42501');

  -- =========================================================================
  -- F — Annunci scaduti
  -- =========================================================================
  perform set_config('role', 'postgres', true);
  update public.listings set expires_at = now() - interval '1 day' where id = v_l_attivo;

  perform pg_temp.att_numero(24,
    'Un annuncio oltre la scadenza sparisce dalla vista pubblica benché ancora attivo',
    'anon', null,
    format('select count(*) from public.public_listings where id = %L', v_l_attivo), 0);

  perform pg_temp.att_numero(25,
    'E con lui sparisce la sua bottiglia, che era pubblica solo grazie a quell''annuncio',
    'anon', null,
    format('select count(*) from public.public_bottle_units where id = %L', v_b_attiva), 0);

  perform set_config('role', 'postgres', true);
  update public.listings set expires_at = now() + interval '60 days' where id = v_l_attivo;

  -- =========================================================================
  -- G — Un annuncio, una bottiglia, un solo annuncio non terminale
  -- =========================================================================
  perform pg_temp.att_messaggio(26,
    'Una seconda bozza sulla stessa bottiglia è respinta con un messaggio leggibile',
    'authenticated', v_venditore,
    format('select * from public.listing_crea(p_prezzo_cents := 7000, p_bottle_unit_id := %L)',
           v_b_bozza), 'ha già un annuncio in corso');

  perform pg_temp.att_messaggio(27,
    'Ripubblicare una bottiglia già venduta è respinto',
    'authenticated', v_venditore,
    format('select * from public.listing_crea(p_prezzo_cents := 7000, p_bottle_unit_id := %L)',
           v_b_venduta), 'già stata venduta');

  perform pg_temp.att_numero(28,
    'Il trigger ha valorizzato ceduta_at all''ingresso dell''annuncio in venduto',
    'postgres', null,
    format('select count(*) from public.bottle_units where id = %L and ceduta_at is not null',
           v_b_venduta), 1);

  -- =========================================================================
  -- Nessuna regressione
  -- =========================================================================
  perform pg_temp.att_numero(29,
    'REGRESSIONE — un annuncio attivo resta visibile a un anonimo',
    'anon', null,
    format('select count(*) from public.public_listings where id = %L', v_l_attivo), 1);

  perform pg_temp.att_numero(30,
    'REGRESSIONE — la vista pubblica conserva vino, venditore e quantità',
    'anon', null,
    format('select count(*) from public.public_listings
              where id = %L and produttore = ''Test6D1'' and annata = 2000
                and seller_username = ''vinea_test_venditore'' and quantita = 1',
           v_l_attivo), 1);

  -- Alfa, Beta, Delta, Epsilon: Gamma è stata tolta dalla cantina e la policy
  -- del proprietario esclude le unità cancellate.
  perform pg_temp.att_numero(31,
    'REGRESSIONE — la cantina del proprietario legge le proprie unità',
    'authenticated', v_venditore,
    format('select count(*) from public.bottle_units where owner_id = %L and deleted_at is null',
           v_venditore), 4);

  -- L'innesto che alimenta prezzo, foto e stato di vendita in /cantina: è
  -- quello che si romperebbe se il grant di colonna su listings fosse sbagliato.
  perform pg_temp.att_numero(32,
    'REGRESSIONE — l''innesto annuncio→unità regge il grant di colonna',
    'authenticated', v_venditore,
    format('select count(*) from public.bottle_units bu
              join public.listings l on l.bottle_unit_id = bu.id
              where bu.owner_id = %L
                and l.prezzo_cents > 0 and l.stato is not null and l.immagini is not null',
           v_venditore), 4);

  -- Alfa ed Epsilon sono gli unici pubblicati, quindi gli unici con scadenza.
  perform pg_temp.att_numero(33,
    'REGRESSIONE — il venditore legge i propri annunci, scadenza compresa',
    'authenticated', v_venditore,
    format('select count(*) from public.listings where seller_id = %L and expires_at is not null',
           v_venditore), 2);

  -- =========================================================================
  -- [4] Pulizia — nessun residuo, nessun account reale toccato
  -- =========================================================================
  -- L'ordine non è negoziabile: bottle_units.wine_id e listings.bottle_unit_id
  -- sono `on delete restrict`, quindi cancellare l'utente per primo fallirebbe
  -- contro le proprie righe.
  perform set_config('role', 'postgres', true);

  delete from public.listings where seller_id in (v_venditore, v_curioso, v_social);
  delete from public.bottle_units where owner_id in (v_venditore, v_curioso, v_social);
  delete from public.wines where produttore = 'Test6D1';
  delete from auth.users where id in (v_venditore, v_curioso, v_social);

exception when others then
  -- Qualunque cosa sia esplosa fuori da un caso (una fixture, la pulizia) deve
  -- comparire nella griglia invece di far sparire l'intero risultato.
  perform set_config('role', 'postgres', true);
  insert into esiti_6d1 values (
    99, 'ESECUZIONE DELLO SCRIPT', 'nessun errore fuori dai casi', 'FALLISCE',
    sqlstate || ': ' || sqlerrm
  );
  delete from public.listings where seller_id in (v_venditore, v_curioso, v_social);
  delete from public.bottle_units where owner_id in (v_venditore, v_curioso, v_social);
  delete from public.wines where produttore = 'Test6D1';
  delete from auth.users where id in (v_venditore, v_curioso, v_social);
end;
$blocco$;


-- ---------------------------------------------------------------------------
-- [5] La griglia
-- ---------------------------------------------------------------------------
-- Atteso: 33 righe, tutte PASSA, e nessuna riga 99.

select n, esito, caso, atteso, dettaglio
from esiti_6d1
order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti_6d1;


-- ---------------------------------------------------------------------------
-- [6] Rete di sicurezza
-- ---------------------------------------------------------------------------
-- Se l'esecuzione si è interrotta lasciando residui, questo blocco si rilancia
-- da solo. Non tocca nulla che non porti il marchio della prova.

/*
delete from public.listings l
  using public.profiles p
  where p.id = l.seller_id and p.username like 'vinea_test_%';
delete from public.bottle_units bu
  using public.profiles p
  where p.id = bu.owner_id and p.username like 'vinea_test_%';
delete from public.wines where produttore = 'Test6D1';
delete from auth.users where email like 'vinea-test-%@example.invalid';
*/
