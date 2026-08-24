-- Price Intelligence 1A - griglia COMPORTAMENTALE della fondazione prezzi.
-- Eseguire dopo la migrazione:
--   20260824120000_price_intelligence_1a_observations.sql
--
-- STATO DI ESECUZIONE. Dichiarato per primo, perche e la cosa piu importante
-- che questo file dice di se stesso:
--
--   ESEGUITA DAVVERO IL 2026-08-24 su PostgreSQL 17.10 (immagine Debian
--   `postgres:17.10`), container usa e getta `vinea-pi1a`, database creato
--   DAL VUOTO, bootstrap 9c e poi 36 migrazioni applicate nell'ordine reale,
--   ciascuna nella propria transazione.
--
--   Prima esecuzione pulita:  27 PASSA / 2 FALLISCE.
--   Dopo le correzioni:       30 PASSA / 0 FALLISCE.
--
--   RIESEGUITA IL 2026-08-24 in fase di VERIFY, di nuovo dal vuoto sullo
--   stesso impianto, dopo l'aggiunta dei casi 31 e 32: 32 PASSA / 0 FALLISCE,
--   sei contatori di residuo a zero. I casi 31-32 sono nati da un difetto
--   trovato nell'audit di VERIFY e non da un fallimento: un commento della
--   migrazione chiamava `completato` uno stato "terminale", mentre
--   `public.ordine_contesta` (7b riga 1204) lo accetta esplicitamente fra gli
--   stati contestabili. Il comportamento era gia corretto - l'indice parziale
--   regge - ma non era ne provato ne descritto con precisione.
--
--   I due fallimenti della prima esecuzione non erano equivalenti, e vale la
--   pena distinguerli:
--     * il caso 21 falliva per un difetto DELLA GRIGLIA: la stringa attesa
--       elencava le colonne come `annata,formato,fonte,...` mentre
--       `order by column_name` produce `annata,fonte,formato,...` ('n' < 'r').
--       La vista era gia corretta. Corretta l'attesa;
--     * il caso 27 falliva per un'affermazione FALSA NELLA MIGRAZIONE: un
--       commento sosteneva che `service_role` non avesse INSERT sulla tabella.
--       Ce l'ha, perche il bootstrap del progetto contiene un
--       `alter default privileges ... grant all on tables to ... service_role`
--       e la mia `revoke all` nominava solo `anon` e `authenticated`. La
--       verifica su `audit_log` - la tabella append-only canonica del
--       repository - ha mostrato che li `service_role` conserva l'intero
--       insieme di privilegi per la stessa ragione. Non e stato revocato:
--       togliere quel GRANT romperebbe la chiave di back-office senza chiudere
--       nessuna delle tre porte che contano, gia chiuse da trigger e vincolo.
--       E stato corretto il commento della migrazione, la sotto-asserzione (d)
--       del caso 27 e stata sostituita con una prova comportamentale, ed e
--       stato aggiunto il caso 30 che misura la posizione reale.
--
--   Residui dopo la pulizia: 0 osservazioni, 0 annunci, 0 ordini, 0 vini
--   `Azienda PI1A`, 0 utenti di prova. Gli 8 vini che restano nel conteggio
--   totale sono il seed di catalogo di `20260728193937_listings_catalog.sql`,
--   non fixture di questa griglia.
--
--   NON E MAI STATA ESEGUITA SUL PROGETTO REALE (pijnmcllmfgjmgsvtcej), e
--   farlo non e autorizzato. Questa griglia SCRIVE: crea utenti, vini,
--   bottiglie, annunci e ordini, e fa passare un ordine per `completato`.
--   Appartiene alla categoria "usa e getta" della 12bc/12d, non alla "sola
--   lettura" della 12a.
--
-- COME ESEGUIRLA. Dal vuoto, su un container PostgreSQL 17 usa e getta,
-- applicando supabase/tests/9c_bootstrap_postgres_locale.sql e poi TUTTE le
-- migrazioni del repository nell'ordine reale, ciascuna nella PROPRIA
-- TRANSAZIONE come fa Supabase. Poi questo file.
--
-- CHE COSA MISURA
--   [1] casi 01-06  ASKING: quando un prezzo chiesto diventa storia, e quando
--                   deliberatamente non lo diventa
--   [2] caso  07    l'unica esclusione: il ritorno da `riservato`
--   [3] casi 08-09  il formato, e perche e copiato invece che letto in join
--   [4] casi 10-14  SALE: la transizione, il prezzo congelato, l'istante
--       e 31-32     reale, e l'idempotenza - compresa quella contro il
--                   percorso reale completato -> contestato -> completato.
--                   Il 31 e il 32 stanno fisicamente qui ma sono numerati in
--                   coda: sono stati aggiunti in fase di VERIFY, e rinumerare
--                   trenta casi gia eseguiti avrebbe reso irriconoscibili i
--                   riferimenti scritti altrove
--   [5] casi 15-20  append-only: contro il client, contro `anon`, contro il
--                   proprietario della tabella e contro TRUNCATE
--   [6] casi 21-22  il modello di lettura, e cio che non lascia uscire
--   [7] casi 23-25  il backfill che non inventa storia, e il campo legacy che
--                   resta legacy
--   [8] casi 26-30  provenienza, fonti esterne OFF, ACL e back-office
--
-- MAPPA DEI 17 CASI RICHIESTI -> numero di caso qui
--   1->01  2->02  3->03  4->04  5->05  6->06  7->11  8->14  9->12
--   10->15 11->16 12->17 13->21 14->23 15->25 16->26 17->27
--   Controprove aggiunte: 07 (l'esclusione di `riservato`), 08-09 (il
--   formato), 10 (`pagato` non e ancora vendita), 13 (observed_at = paid_at),
--   18-20 (`anon`, il proprietario, TRUNCATE), 22 (base vs vista), 24 (il
--   backfill rieseguito), 28-29 (ACL della porta e della vista), 30 (la
--   posizione reale di `service_role`), 31-32 (l'uscita da `completato` e il
--   rientro dopo una contestazione).
--
-- CHE COSA NON MISURA
--   * niente su PostgREST: la traduzione dei 42501 in 403 e la lettura via
--     HTTP non passano di qui. Le griglie SQL non provano il percorso client;
--   * nessuna concorrenza: tutti i casi sono sequenziali. In particolare
--     l'idempotenza della vendita e provata contro una RIPETIZIONE, non
--     contro due completamenti simultanei dello stesso ordine; la rete di
--     sicurezza li e l'indice unico parziale, non questa griglia;
--   * niente sull'interfaccia: non esiste interfaccia. E la Fase 1B;
--   * niente su un fornitore esterno, perche non ne esiste nessuno. Il caso 27
--     misura l'ASSENZA di una via d'ingresso, che e cio che si puo misurare.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Registro e impersonazione
-- ---------------------------------------------------------------------------
-- Stesso impianto della 12d.

drop table if exists esiti_pi1a;
drop table if exists risultati_pi1a;

create temporary table esiti_pi1a (
  n integer primary key,
  caso text not null,
  esito text not null,
  dettaglio text not null
);

create or replace function pg_temp.registra(
  p_n integer, p_caso text, p_ok boolean, p_dettaglio text default ''
) returns void language sql as $$
  insert into esiti_pi1a (n, caso, esito, dettaglio)
  values (p_n, p_caso, case when p_ok then 'PASSA' else 'FALLISCE' end, p_dettaglio);
$$;

create temporary table risultati_pi1a (
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
  insert into risultati_pi1a (chiave, esito) values (p_chiave, v_esito)
    on conflict (chiave) do update set esito = excluded.esito;
  return v_esito;
end;
$$;

create or replace function pg_temp.esito(p_chiave text)
returns text language sql stable as $$
  select esito from risultati_pi1a where chiave = p_chiave;
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

-- Quante osservazioni ha prodotto una certa origine, per tipo.
create or replace function pg_temp.conta(p_origine uuid, p_tipo text)
returns integer language sql stable as $$
  select count(*)::integer
  from public.wine_price_observations
  where origine_ref = p_origine and tipo::text = p_tipo;
$$;

-- La serie dei prezzi di un'origine, in ordine di tempo osservato.
create or replace function pg_temp.serie(p_origine uuid)
returns text language sql stable as $$
  select coalesce(string_agg(prezzo_cents::text, ',' order by observed_at, created_at), '')
  from public.wine_price_observations
  where origine_ref = p_origine;
$$;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
-- Identificatori fissi e riconoscibili: quando un caso fallisce si deve poter
-- dire QUALE riga, senza rileggere l'intero file.

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'venditore@pi1a.test'),
  ('22222222-2222-2222-2222-222222222222', 'compratore@pi1a.test');

-- `on conflict` e non `insert` secco: la creazione del profilo e un trigger su
-- auth.users (20260728000545), quindi le due righe ESISTONO GIA. Questo passo
-- non le crea - fissa username e data di nascita che i casi successivi usano.
insert into public.profiles (id, username, dob) values
  ('11111111-1111-1111-1111-111111111111', 'pi1a_venditore', '1980-01-01'),
  ('22222222-2222-2222-2222-222222222222', 'pi1a_compratore', '1980-01-01')
on conflict (id) do update
  set username = excluded.username, dob = excluded.dob;

-- Due vini in due formati diversi: e la ragione per cui `formato` esiste
-- sull'osservazione.
insert into public.wines (id, slug, produttore, nome, annata, regione, tipo, formato) values
  ('33333333-3333-3333-3333-333333333333', 'pi1a-vino-075',
   'Azienda PI1A', 'Rosso di Prova', 2018, 'Toscana', 'Rosso', '0,75 L'),
  ('34343434-3434-3434-3434-343434343434', 'pi1a-vino-magnum',
   'Azienda PI1A', 'Rosso di Prova Magnum', 2018, 'Toscana', 'Rosso', 'Magnum 1,5 L');

insert into public.bottle_units (id, owner_id, wine_id) values
  ('44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('45454545-4545-4545-4545-454545454545',
   '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('46464646-4646-4646-4646-464646464646',
   '11111111-1111-1111-1111-111111111111', '34343434-3434-3434-3434-343434343434'),
  ('47474747-4747-4747-4747-474747474747',
   '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333');

-- ---------------------------------------------------------------------------
-- [1] ASKING - quando un prezzo chiesto diventa storia
-- ---------------------------------------------------------------------------

-- L1 nasce in bozza a 100,00 EUR.
insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents)
values ('55555555-5555-5555-5555-555555555555', 'pi1a-annuncio-uno',
        '11111111-1111-1111-1111-111111111111',
        '44444444-4444-4444-4444-444444444444', 10000);

select pg_temp.registra(1,
  'Un annuncio in bozza non e un prezzo chiesto al mercato',
  pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 0,
  'il numero esiste ma nessuno lo sta chiedendo: e in un modulo, non in vetrina');

-- La pubblicazione passa dalla RPC reale del venditore, non da un UPDATE
-- diretto: cio che si vuole provare e che il percorso VERO produce la riga.
select pg_temp.esegui('pubblica',
  $$ select public.listing_pubblica('55555555-5555-5555-5555-555555555555') $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(2,
  'L''ingresso in vetrina produce esattamente una osservazione `richiesta`',
  pg_temp.esito('pubblica') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 1
  and pg_temp.leggi($$
    select prezzo_cents::text from public.wine_price_observations
    where origine_ref = '55555555-5555-5555-5555-555555555555'
  $$) = '10000',
  'una, non zero e non due: la storia comincia quando il prezzo diventa pubblico');

-- Descrizione, fotografie, tag: tutto cio che non e il prezzo.
select pg_temp.esegui('metadati',
  $$ update public.listings
       set storia = 'Riscritta.', degustazione = 'Riscritta.',
           immagini = array['a.webp'], tag = array['prova'],
           condizione = 'Buono', conservazione = 'Cantina'
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(3,
  'Riscrivere descrizione, foto e tag non e un dato di mercato',
  pg_temp.esito('metadati') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 1,
  'se ogni UPDATE producesse una riga, la storia misurerebbe la logorrea del venditore');

select pg_temp.esegui('stesso_prezzo',
  $$ update public.listings set prezzo_cents = 10000
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(4,
  'Riscrivere lo STESSO prezzo non produce nulla',
  pg_temp.esito('stesso_prezzo') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 1,
  'il confronto e `is distinct from`, non la presenza della colonna nell''UPDATE');

select pg_temp.esegui('prezzo_su',
  $$ update public.listings set prezzo_cents = 12000
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(5,
  'Un cambio di prezzo REALE su un annuncio attivo produce una nuova riga',
  pg_temp.esito('prezzo_su') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 2,
  'e la modifica che dal 19 agosto il venditore puo fare, e che fino a oggi non lasciava traccia');

select pg_temp.esegui('prezzo_su_2',
  $$ update public.listings set prezzo_cents = 13000
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.esegui('prezzo_giu',
  $$ update public.listings set prezzo_cents = 9000
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(6,
  'Piu cambi di prezzo danno una storia ordinabile, non un totale',
  pg_temp.serie('55555555-5555-5555-5555-555555555555') = '10000,12000,13000,9000'
  and pg_temp.leggi($$
    select count(distinct observed_at)::text
    from public.wine_price_observations
    where origine_ref = '55555555-5555-5555-5555-555555555555'
  $$) = '4',
  'quattro istanti distinti: se `now()` fosse costante fra i passi, la serie non sarebbe ordinabile');

-- ---------------------------------------------------------------------------
-- [2] L'unica esclusione deliberata
-- ---------------------------------------------------------------------------
-- `riservato` -> `attivo` lo scrivono i percorsi di rilascio prenotazione
-- quando un checkout scade o un ordine si annulla. Non e un prezzo nuovo.

select pg_temp.esegui('riserva',
  $$ update public.listings set stato = 'riservato'
     where id = '55555555-5555-5555-5555-555555555555' $$,
  null, 'postgres');

select pg_temp.esegui('rilascia',
  $$ update public.listings set stato = 'attivo'
     where id = '55555555-5555-5555-5555-555555555555' $$,
  null, 'postgres');

select pg_temp.registra(7,
  'Il ritorno da `riservato` NON e una nuova richiesta',
  pg_temp.esito('riserva') = 'NESSUN_ERRORE'
  and pg_temp.esito('rilascia') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 4,
  'un checkout abbandonato riporta l''annuncio in vetrina allo stesso prezzo: registrarlo sarebbe rumore proporzionale ai carrelli lasciati');

-- ---------------------------------------------------------------------------
-- [3] Il formato
-- ---------------------------------------------------------------------------

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents)
values ('56565656-5656-5656-5656-565656565656', 'pi1a-annuncio-magnum',
        '11111111-1111-1111-1111-111111111111',
        '46464646-4646-4646-4646-464646464646', 30000);

select pg_temp.esegui('pubblica_magnum',
  $$ select public.listing_pubblica('56565656-5656-5656-5656-565656565656') $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(8,
  'Una magnum non entra nella serie della 0,75 L',
  pg_temp.esito('pubblica_magnum') = 'NESSUN_ERRORE'
  and pg_temp.leggi($$
    select formato from public.wine_price_observations
    where origine_ref = '56565656-5656-5656-5656-565656565656'
  $$) = 'Magnum 1,5 L'
  and pg_temp.leggi($$
    select count(distinct formato)::text from public.wine_price_history
    where produttore = 'Azienda PI1A'
  $$) = '2',
  'sono due mercati, non due arrotondamenti: la 1B raggruppa per (wine_id, formato)');

-- Il catalogo cambia sotto. L'osservazione e un fatto storico e non deve
-- cambiare con lui.
update public.wines set formato = 'Doppia Magnum 3 L'
where id = '34343434-3434-3434-3434-343434343434';

select pg_temp.registra(9,
  'Il formato dell''osservazione non si riscrive quando cambia il catalogo',
  pg_temp.leggi($$
    select formato from public.wine_price_history
    where wine_slug = 'pi1a-vino-magnum'
  $$) = 'Magnum 1,5 L',
  'copiato alla nascita, non letto in join: un fatto avvenuto non si aggiorna');

-- ---------------------------------------------------------------------------
-- [4] SALE
-- ---------------------------------------------------------------------------

insert into public.listings (id, slug, seller_id, bottle_unit_id, prezzo_cents)
values ('57575757-5757-5757-5757-575757575757', 'pi1a-annuncio-venduto',
        '11111111-1111-1111-1111-111111111111',
        '47474747-4747-4747-4747-474747474747', 20000);

select pg_temp.esegui('pubblica_venduto',
  $$ select public.listing_pubblica('57575757-5757-5757-5757-575757575757') $$,
  '11111111-1111-1111-1111-111111111111');

-- L'ordine nasce a 200,00 EUR e viene pagato dieci giorni fa.
insert into public.orders (
  id, listing_id, buyer_id, seller_id, seller_bottle_unit_id,
  stato, delivery_mode, prezzo_cents, idempotency_key,
  reservation_expires_at, paid_at
) values (
  '66666666-6666-6666-6666-666666666666',
  '57575757-5757-5757-5757-575757575757',
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  '47474747-4747-4747-4747-474747474747',
  'pagato', 'spedizione', 20000, 'pi1a-ordine-uno',
  now() + interval '1 day', now() - interval '10 days'
);

select pg_temp.registra(10,
  'Un ordine `pagato` non e ancora una vendita',
  pg_temp.conta('66666666-6666-6666-6666-666666666666', 'vendita') = 0,
  'da `pagato` si puo ancora finire in `rimborsato` o `annullato`: registrare qui vorrebbe dire chiamare vendita cio che si puo disfare');

-- Il venditore alza il prezzo dell'annuncio DOPO che l'ordine e nato. E il
-- caso che separa il prezzo congelato da quello corrente.
select pg_temp.esegui('prezzo_dopo_ordine',
  $$ update public.listings set prezzo_cents = 25000
     where id = '57575757-5757-5757-5757-575757575757' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.esegui('completa',
  $$ update public.orders set stato = 'completato'
     where id = '66666666-6666-6666-6666-666666666666' $$,
  null, 'postgres');

select pg_temp.registra(11,
  'Il passaggio a `completato` produce UNA osservazione `vendita`',
  pg_temp.esito('completa') = 'NESSUN_ERRORE'
  and pg_temp.conta('66666666-6666-6666-6666-666666666666', 'vendita') = 1,
  '`completato` sblocca il payout e permette la recensione: e li che il dominio dichiara avvenuta la compravendita. Non e uno stato assorbente - vedi i casi 31 e 32');

select pg_temp.registra(12,
  'Il prezzo della vendita e quello CONGELATO sull''ordine, non quello corrente',
  pg_temp.leggi($$
    select prezzo_cents::text from public.wine_price_observations
    where origine_ref = '66666666-6666-6666-6666-666666666666'
      and tipo = 'vendita'
  $$) = '20000'
  and pg_temp.leggi($$
    select prezzo_cents::text from public.listings
    where id = '57575757-5757-5757-5757-575757575757'
  $$) = '25000',
  'l''annuncio dice 250,00 ma la compravendita e avvenuta a 200,00: registrare il prezzo corrente falsificherebbe il mercato');

select pg_temp.registra(13,
  'L''istante osservato della vendita e `paid_at`, non quello del completamento',
  pg_temp.leggi($$
    select (o.observed_at = ord.paid_at)::text
    from public.wine_price_observations o
      join public.orders ord on ord.id = o.origine_ref
    where o.tipo = 'vendita'
      and o.origine_ref = '66666666-6666-6666-6666-666666666666'
  $$) = 'true'
  and pg_temp.leggi($$
    select (created_at > observed_at)::text
    from public.wine_price_observations
    where origine_ref = '66666666-6666-6666-6666-666666666666'
      and tipo = 'vendita'
  $$) = 'true',
  'lo scambio e avvenuto quando il denaro si e mosso; il completamento certifica soltanto che non e stato disfatto. `created_at` conserva quando Vinea l''ha saputo');

-- Ripetizione: l'ordine esce e rientra in `completato`.
select pg_temp.esegui('completa_ripeti_a',
  $$ update public.orders set stato = 'consegnato'
     where id = '66666666-6666-6666-6666-666666666666' $$,
  null, 'postgres');

select pg_temp.esegui('completa_ripeti_b',
  $$ update public.orders set stato = 'completato'
     where id = '66666666-6666-6666-6666-666666666666' $$,
  null, 'postgres');

select pg_temp.registra(14,
  'Un ordine completato due volte resta UNA sola vendita',
  pg_temp.esito('completa_ripeti_b') = 'NESSUN_ERRORE'
  and pg_temp.conta('66666666-6666-6666-6666-666666666666', 'vendita') = 1,
  'l''unicita la garantisce l''indice parziale, e `on conflict do nothing` fa si che una seconda registrazione non rompa l''ordine');

-- Il caso 14 prova la ripetizione meccanica. Questo prova il percorso REALE che
-- la produce: `public.ordine_contesta` (7b riga 1204) accetta esplicitamente
-- `completato` fra gli stati contestabili finche il payout non e stato
-- trasferito, quindi completato -> contestato -> completato non e un'ipotesi di
-- laboratorio ma la risoluzione di una contestazione (7c/7f riga 1125).
--
-- L'UPDATE e diretto e non passa dalla RPC perche cio che si misura qui e il
-- trigger, non la contestazione: la RPC chiede un compratore autenticato, una
-- riga in `disputes`, un rate limit e uno stato di payout, e nessuna di quelle
-- condizioni cambia cio che il trigger vede.

select pg_temp.esegui('contesta_dopo_completato',
  $$ update public.orders set stato = 'contestato'
     where id = '66666666-6666-6666-6666-666666666666' $$,
  null, 'postgres');

select pg_temp.registra(31,
  'Uscire da `completato` verso `contestato` non tocca la vendita gia scritta',
  pg_temp.esito('contesta_dopo_completato') = 'NESSUN_ERRORE'
  and pg_temp.conta('66666666-6666-6666-6666-666666666666', 'vendita') = 1
  and pg_temp.leggi($$
    select prezzo_cents::text from public.wine_price_observations
    where origine_ref = '66666666-6666-6666-6666-666666666666' and tipo = 'vendita'
  $$) = '20000',
  'la riga non si cancella e non si riscrive: la tabella e append-only, e una osservazione dice che l''ordine RAGGIUNSE `completato` a quel prezzo, non che quel denaro non tornera mai indietro');

select pg_temp.esegui('risolvi_verso_completato',
  $$ update public.orders set stato = 'completato'
     where id = '66666666-6666-6666-6666-666666666666' $$,
  null, 'postgres');

select pg_temp.registra(32,
  'La contestazione risolta riporta in `completato` senza creare una seconda vendita',
  pg_temp.esito('risolvi_verso_completato') = 'NESSUN_ERRORE'
  and pg_temp.conta('66666666-6666-6666-6666-666666666666', 'vendita') = 1
  and pg_temp.leggi($$
    select count(*)::text from public.wine_price_observations
    where origine_ref = '66666666-6666-6666-6666-666666666666'
  $$) = '1',
  'e il percorso di 7c/7f riga 1125: il trigger riscatta perche `old.stato is distinct from completato`, e a fermarlo e l''indice parziale - il conteggio totale, non solo quello per tipo, resta uno');

-- ---------------------------------------------------------------------------
-- [5] Append-only, contro chiunque
-- ---------------------------------------------------------------------------

select pg_temp.esegui('client_insert',
  $$ insert into public.wine_price_observations
       (wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref)
     values ('33333333-3333-3333-3333-333333333333', '0,75 L', 'vendita',
             'vinea_interno', 1, now(),
             '99999999-9999-9999-9999-999999999999') $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(15,
  'Un browser autenticato non puo INSERIRE una osservazione',
  pg_temp.esito('client_insert') like '42501|%',
  'se potesse, chiunque potrebbe scriversi il mercato che preferisce');

select pg_temp.esegui('client_update',
  $$ update public.wine_price_observations set prezzo_cents = 1 $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(16,
  'Un browser autenticato non puo MODIFICARE una osservazione',
  pg_temp.esito('client_update') like '42501|%',
  'una storia riscrivibile non e una storia');

select pg_temp.esegui('client_delete',
  $$ delete from public.wine_price_observations $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(17,
  'Un browser autenticato non puo CANCELLARE una osservazione',
  pg_temp.esito('client_delete') like '42501|%',
  'poter cancellare il proprio prezzo alto e poter truccare la media');

select pg_temp.registra(18,
  '`anon` non ha alcun privilegio sulla tabella',
  not pg_temp.leggi($$
    select (has_table_privilege('anon', 'public.wine_price_observations', 'select')
         or has_table_privilege('anon', 'public.wine_price_observations', 'insert')
         or has_table_privilege('anon', 'public.wine_price_observations', 'update')
         or has_table_privilege('anon', 'public.wine_price_observations', 'delete'))::text
  $$)::boolean,
  'la revoca iniziale serve proprio a questo: senza, gli ALTER DEFAULT PRIVILEGES del progetto darebbero tutto');

-- Il proprietario della tabella. E il caso che distingue un trigger da un
-- GRANT: i GRANT non lo vincolano.
select pg_temp.esegui('owner_update',
  $$ update public.wine_price_observations set prezzo_cents = 1 $$,
  null, 'postgres');

select pg_temp.esegui('owner_delete',
  $$ delete from public.wine_price_observations $$,
  null, 'postgres');

select pg_temp.registra(19,
  'L''append-only vincola anche il proprietario della tabella',
  pg_temp.esito('owner_update') like '42501|%append-only%'
  and pg_temp.esito('owner_delete') like '42501|%append-only%',
  'e per questo e un trigger e non un GRANT: un GRANT non si applica a chi possiede la tabella');

select pg_temp.esegui('owner_truncate',
  $$ truncate public.wine_price_observations $$,
  null, 'postgres');

select pg_temp.registra(20,
  'Anche TRUNCATE viene rifiutato',
  pg_temp.esito('owner_truncate') like '42501|%append-only%',
  'TRUNCATE non passa dai trigger di riga: senza il terzo trigger la tabella si svuoterebbe in un colpo');

-- ---------------------------------------------------------------------------
-- [6] Il modello di lettura
-- ---------------------------------------------------------------------------

select pg_temp.registra(21,
  'La vista non espone venditore, compratore, ordine ne annuncio',
  pg_temp.leggi($$
    select string_agg(column_name, ',' order by column_name)
    from information_schema.columns
    where table_schema = 'public' and table_name = 'wine_price_history'
  $$) = 'annata,fonte,formato,nome,observed_at,prezzo_cents,produttore,tipo,valuta,wine_id,wine_slug',
  'elenco chiuso e verificato per intero: `origine_ref` non c''e, e una colonna aggiunta domani alla tabella base resta privata finche non la si aggiunge QUI');

select pg_temp.esegui('client_legge_base',
  $$ select count(*) from public.wine_price_observations $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(22,
  'Il client legge la vista, non la tabella base',
  pg_temp.esito('client_legge_base') like '42501|%'
  and pg_temp.leggi($$ select count(*)::text from public.wine_price_history $$,
                    '11111111-1111-1111-1111-111111111111', 'authenticated')
      not like '42501|%',
  'la RLS filtra righe e non colonne: la colonna da non far uscire sta sulla stessa riga del prezzo, quindi la barriera e la vista');

-- ---------------------------------------------------------------------------
-- [7] Backfill e campo legacy
-- ---------------------------------------------------------------------------
-- Il backfill della migrazione ha girato su un database vuoto, quindi non ha
-- prodotto nulla: provarlo cosi sarebbe vacuo. Qui si ricostruisce la
-- situazione reale - un annuncio ATTIVO nato PRIMA della migrazione, quindi
-- senza osservazione - disattivando il trigger, e si riesegue lo STESSO
-- INSERT del backfill.

alter table public.listings disable trigger listings_price_observation_sync;

insert into public.listings (
  id, slug, seller_id, bottle_unit_id, prezzo_cents, stato,
  published_at, created_at
) values (
  '58585858-5858-5858-5858-585858585858', 'pi1a-annuncio-preesistente',
  '11111111-1111-1111-1111-111111111111',
  '45454545-4545-4545-4545-454545454545', 15000, 'attivo',
  now() - interval '200 days', now() - interval '210 days'
);

alter table public.listings enable trigger listings_price_observation_sync;

insert into public.wine_price_observations (
  wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref
)
select
  w.id,
  coalesce(nullif(btrim(w.formato), ''), '0,75 L'),
  'richiesta',
  'vinea_interno',
  l.prezzo_cents,
  now(),
  l.id
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
where l.stato = 'attivo'
  and not exists (
    select 1 from public.wine_price_observations o
    where o.origine_ref = l.id and o.tipo = 'richiesta'
  );

select pg_temp.registra(23,
  'Il backfill data al momento reale dell''acquisizione, non alla pubblicazione',
  pg_temp.conta('58585858-5858-5858-5858-585858585858', 'richiesta') = 1
  and pg_temp.leggi($$
    select (o.observed_at > l.published_at + interval '199 days')::text
    from public.wine_price_observations o
      join public.listings l on l.id = o.origine_ref
    where o.origine_ref = '58585858-5858-5858-5858-585858585858'
  $$) = 'true'
  and pg_temp.leggi($$
    select (o.observed_at > l.created_at + interval '209 days')::text
    from public.wine_price_observations o
      join public.listings l on l.id = o.origine_ref
    where o.origine_ref = '58585858-5858-5858-5858-585858585858'
  $$) = 'true',
  'nessuno puo dimostrare che il prezzo di oggi fosse quello duecento giorni fa: datare all''indietro trasformerebbe una congettura in storia');

-- La sezione e rieseguibile a vuoto: `not exists` invece di `on conflict`,
-- perche nessun indice unico copre le richieste e non deve coprirle.
insert into public.wine_price_observations (
  wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref
)
select w.id, w.formato, 'richiesta', 'vinea_interno', l.prezzo_cents, now(), l.id
from public.listings l
  join public.bottle_units bu on bu.id = l.bottle_unit_id
  join public.wines w on w.id = bu.wine_id
where l.stato = 'attivo'
  and not exists (
    select 1 from public.wine_price_observations o
    where o.origine_ref = l.id and o.tipo = 'richiesta'
  );

select pg_temp.registra(24,
  'Rieseguire il backfill non duplica nulla',
  pg_temp.conta('58585858-5858-5858-5858-585858585858', 'richiesta') = 1
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 4,
  'una migrazione riapplicata su un database gia migrato non deve raddoppiare la storia');

select pg_temp.esegui('legacy',
  $$ update public.listings set prezzo_mercato_cents = 99999
     where id = '55555555-5555-5555-5555-555555555555' $$,
  '11111111-1111-1111-1111-111111111111');

select pg_temp.registra(25,
  '`prezzo_mercato_cents` non diventa una osservazione autorevole',
  pg_temp.esito('legacy') = 'NESSUN_ERRORE'
  and pg_temp.conta('55555555-5555-5555-5555-555555555555', 'richiesta') = 4
  and pg_temp.leggi($$
    select count(*)::text from public.wine_price_observations
    where prezzo_cents = 99999
  $$) = '0',
  'sei righe di provenienza ignota in produzione non diventano market data per il fatto di esistere');

-- ---------------------------------------------------------------------------
-- [8] Provenienza, fonti esterne, ACL
-- ---------------------------------------------------------------------------

select pg_temp.registra(26,
  'La provenienza distingue la richiesta Vinea dalla vendita Vinea',
  pg_temp.leggi($$
    select string_agg(distinct tipo::text || ':' || fonte::text, ',' order by tipo::text || ':' || fonte::text)
    from public.wine_price_history
  $$) = 'richiesta:vinea_interno,vendita:vinea_interno',
  'due tipi, una sola fonte: un chiesto e un pagato non sono la stessa informazione e non vanno mediati senza deciderlo');

-- Il tentativo piu vicino a un fornitore esterno che si possa costruire oggi:
-- inserire una riga dichiarandola di un'altra provenienza. Lo fa il ruolo di
-- servizio, cioe il piu privilegiato che il prodotto usi.
select pg_temp.esegui('fonte_inventata',
  $$ insert into public.wine_price_observations
       (wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref)
     values ('33333333-3333-3333-3333-333333333333', '0,75 L', 'vendita',
             'fornitore_esterno', 50000, now(),
             '98989898-9898-9898-9898-989898989898') $$,
  null, 'service_role');

select pg_temp.registra(27,
  'Le fonti esterne sono OFF per costruzione, non per configurazione',
  -- (a) l'enum ha una sola label, e nessun nome di fornitore
  pg_temp.leggi($$
    select string_agg(enumlabel, ',' order by enumsortorder)
    from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'price_observation_fonte'
  $$) = 'vinea_interno'
  -- (b) il vincolo di riga che rifiuterebbe una fonte futura
  and pg_temp.leggi($$
    select count(*)::text from pg_constraint
    where conname = 'wine_price_observations_solo_fonti_interne'
  $$) = '1'
  -- (c) nessuna via d'ingresso: le sole funzioni che nominano la tabella sono
  --     la porta di scrittura interna e il guardiano append-only
  and pg_temp.leggi($$
    select string_agg(p.proname, ',' order by p.proname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosrc like '%wine_price_observations%'
  $$) = 'price_observation_registra,wine_price_observations_append_only'
  -- (d) e nessun chiamante puo nemmeno NOMINARE una fonte che non esiste
  and pg_temp.esito('fonte_inventata') like '22P02|%',
  'accendere un fornitore richiede tre atti espliciti in una migrazione nuova - label, vincolo, via d''ingresso - e nessuno dei tre puo accadere per errore');

select pg_temp.registra(28,
  'L''unica porta di scrittura e chiusa ai ruoli client',
  not pg_temp.leggi($$
    select (has_function_privilege('authenticated',
              'private.price_observation_registra(uuid,text,public.price_observation_tipo,integer,timestamptz,uuid)', 'execute')
         or has_function_privilege('anon',
              'private.price_observation_registra(uuid,text,public.price_observation_tipo,integer,timestamptz,uuid)', 'execute'))::text
  $$)::boolean,
  'una SECURITY DEFINER eseguibile da chiunque sarebbe la stessa falla del GRANT, con un nome piu lungo');

select pg_temp.registra(29,
  'La vista resta security_invoker = off e concede solo SELECT',
  (select not coalesce(
     (select option_value = 'true' from pg_options_to_table(c.reloptions)
      where option_name = 'security_invoker'), false)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'wine_price_history')
  and not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'wine_price_history'
      and grantee in ('anon', 'authenticated')
      and privilege_type <> 'SELECT'),
  'e il pattern di public_listings e public_clubs: il linter Supabase lo segnala come `security_definer_view`, ed e la segnalazione attesa');

-- La posizione REALE di `service_role`, misurata invece che dichiarata. In
-- questo repository la chiave di back-office conserva i privilegi di tabella
-- ovunque - `audit_log`, l'altra tabella append-only, si comporta uguale - e
-- cio che deve vincolarla sta nei trigger e nei vincoli, non nei GRANT.

select pg_temp.esegui('sr_insert',
  $$ insert into public.wine_price_observations
       (wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref)
     values ('33333333-3333-3333-3333-333333333333', '0,75 L', 'vendita',
             'vinea_interno', 50000, now(),
             '97979797-9797-9797-9797-979797979797') $$,
  null, 'service_role');

select pg_temp.esegui('sr_update',
  $$ update public.wine_price_observations set prezzo_cents = 1
     where origine_ref = '97979797-9797-9797-9797-979797979797' $$,
  null, 'service_role');

select pg_temp.esegui('sr_delete',
  $$ delete from public.wine_price_observations
     where origine_ref = '97979797-9797-9797-9797-979797979797' $$,
  null, 'service_role');

select pg_temp.registra(30,
  'Il back-office puo aggiungere, non riscrivere ne cancellare',
  pg_temp.esito('sr_insert') = 'NESSUN_ERRORE'
  and pg_temp.esito('sr_update') like '42501|%append-only%'
  and pg_temp.esito('sr_delete') like '42501|%append-only%',
  'togliere il GRANT a service_role romperebbe il back-office senza chiudere nulla: le tre porte che contano - riscrittura, cancellazione, fonte esterna - sono gia chiuse da trigger e vincoli');

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select n, caso, esito, dettaglio from esiti_pi1a order by n;

select
  count(*) filter (where esito = 'PASSA')    as passa,
  count(*) filter (where esito = 'FALLISCE') as fallisce,
  count(*)                                   as totale
from esiti_pi1a;

-- ---------------------------------------------------------------------------
-- Pulizia
-- ---------------------------------------------------------------------------
-- Il database e usa e getta e viene distrutto con il container: la pulizia
-- non serve a liberare spazio, serve a rendere la griglia rieseguibile sullo
-- stesso database senza collisioni di chiave. Le osservazioni NON si possono
-- cancellare - e il caso 19 - quindi i trigger si disattivano qui e solo qui.

alter table public.wine_price_observations disable trigger wine_price_observations_no_delete;
delete from public.wine_price_observations
where origine_ref in (
  '55555555-5555-5555-5555-555555555555',
  '56565656-5656-5656-5656-565656565656',
  '57575757-5757-5757-5757-575757575757',
  '58585858-5858-5858-5858-585858585858',
  '66666666-6666-6666-6666-666666666666',
  '97979797-9797-9797-9797-979797979797'
);
alter table public.wine_price_observations enable trigger wine_price_observations_no_delete;

delete from public.orders where id = '66666666-6666-6666-6666-666666666666';
delete from public.listings where seller_id = '11111111-1111-1111-1111-111111111111';
delete from public.bottle_units where owner_id = '11111111-1111-1111-1111-111111111111';
delete from public.wines where produttore = 'Azienda PI1A';
delete from auth.users where id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222'
);

-- I conteggi sono ristretti alle fixture di QUESTA griglia. Un `count(*)` nudo
-- su `public.wines` restituirebbe 8 anche dopo una pulizia perfetta, perche
-- quel numero e il seed di catalogo di 20260728193937_listings_catalog.sql:
-- un residuo apparente che non e un residuo.
select
  (select count(*) from public.wine_price_observations)                        as osservazioni_residue,
  (select count(*) from public.listings
     where seller_id = '11111111-1111-1111-1111-111111111111')                 as annunci_residui,
  (select count(*) from public.orders
     where id = '66666666-6666-6666-6666-666666666666')                        as ordini_residui,
  (select count(*) from public.wines where produttore = 'Azienda PI1A')        as vini_residui,
  (select count(*) from public.bottle_units
     where owner_id = '11111111-1111-1111-1111-111111111111')                  as bottiglie_residue,
  (select count(*) from auth.users where id in (
     '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222'))                                  as utenti_residui;
