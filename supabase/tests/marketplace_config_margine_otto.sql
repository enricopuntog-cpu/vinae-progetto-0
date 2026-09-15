-- Configurazione economica del marketplace, margine 8% — griglia di esiti.
--
-- Eseguire DOPO la migrazione
-- supabase/migrations/20260915120000_marketplace_config_margine_otto_percento.sql.
-- Prima di quella, undici casi su sedici falliscono: è il loro modo di dire che
-- la nuova riga di configurazione non è ancora in vigore.
--
-- STATO DI ESECUZIONE. Dichiarato per primo perché la regola di questo
-- repository è che UNA GRIGLIA VERSIONATA E MAI ESEGUITA NON È UNA PROVA.
-- Questa è stata ESEGUITA:
--
--   DOVE: PostgreSQL 17.6 in un contenitore isolato, nato dal bootstrap
--   `9c_bootstrap_postgres_locale.sql` e dalle 51 migrazioni di `origin/main`
--   applicate in ordine — la stessa famiglia del progetto reale, che gira
--   17.6.1.147. Il contenitore è stato rimosso a fine corsa.
--   QUANDO: 15 settembre 2026, prima del merge e quindi prima di qualunque
--   applicazione in produzione, perché in questo repository il merge è il gate
--   di deploy.
--
--   DUE ESECUZIONI, e la prima conta quanto la seconda:
--     PRIMA della migrazione   ->   5 PASSA / 11 FALLISCE
--     DOPO  la migrazione      ->  16 PASSA /  0 FALLISCE
--
--   La corsa di controllo serve a escludere una griglia verde in entrambi i
--   casi, che non misurerebbe nulla. I cinque casi verdi anche prima sono
--   [01], [03], [07], [08] e [14]. Tre valgono già per costruzione: l'unicità
--   della riga corrente e le colonne e la riga sola della vista. [14] è verde
--   in entrambe le corse ed è il punto: dice che la formula non si è mossa.
--   [03] è il caso da leggere con attenzione — prima della migrazione passa
--   perché la riga `id = 1` è ancora quella corrente e porta ovviamente i
--   propri valori; dopo, passa perché quei valori sono stati conservati nella
--   riga chiusa. Da solo non distinguerebbe i due mondi: a distinguerli è [04],
--   che legge `valida_fino`.
--
--   SUL PROGETTO REALE NON È ANCORA GIRATA. Può girarci: questa griglia NON
--   SCRIVE — nessuna fixture, nessun utente, nessun ordine, solo letture e
--   chiamate a funzioni `immutable`/`stable`. Il `begin`/`rollback` serve
--   soltanto alla tabella temporanea degli esiti.
--
--   CIÒ CHE QUESTA GRIGLIA NON PUÒ VEDERE: una sessione Postgres diretta non
--   passa da PostgREST. Che la vista `public_marketplace_config` sia davvero
--   leggibile da un client `anon` attraverso l'API va provato dal client.
--
-- COSA VERIFICA, IN UNA RIGA: che esista una sola configurazione corrente, che
-- sia la nuova, che la vecchia sia conservata chiusa, che la vista pubblica
-- esponga quella e nient'altro, e che la formula — invariata — produca sui
-- nuovi parametri i totali attesi, margine netto compreso.

\set ON_ERROR_STOP off

begin;

create temporary table esiti (
  caso   text,
  atteso text,
  visto  text,
  passa  boolean
) on commit drop;

create or replace function pg_temp.registra(
  p_caso text, p_atteso text, p_visto text
) returns void language plpgsql as $$
begin
  insert into esiti values (p_caso, p_atteso, p_visto, p_atteso is not distinct from p_visto);
end;
$$;

-- ---------------------------------------------------------------------------
-- La riga corrente
-- ---------------------------------------------------------------------------

-- [1] L'invariante dell'indice `marketplace_config_una_corrente`: al più una
--     riga aperta. Vale già prima della migrazione — qui serve a dimostrare che
--     la migrazione non l'ha rotto passando per uno stato a due righe aperte.
select pg_temp.registra(
  '[01] esiste esattamente una riga corrente',
  '1',
  (select count(*)::text from public.marketplace_config where valida_fino is null));

-- [2] I quattro parametri in vigore, letti insieme: separarli lascerebbe
--     passare una riga mezza aggiornata.
select pg_temp.registra(
  '[02] la riga corrente vale 800/209/25/14',
  '800|209|25|14',
  (select margine_obiettivo_bps || '|' || riferimento_stripe_percentuale_bps
          || '|' || riferimento_stripe_fisso_cents || '|' || auto_rilascio_giorni
   from public.marketplace_config where valida_fino is null));

-- [3] La riga chiusa non è stata riscritta: lo storico è la tabella, e un
--     ordine nato sotto i vecchi parametri deve restare spiegabile.
select pg_temp.registra(
  '[03] la riga chiusa conserva 500/150/25/14',
  '500|150|25|14',
  (select margine_obiettivo_bps || '|' || riferimento_stripe_percentuale_bps
          || '|' || riferimento_stripe_fisso_cents || '|' || auto_rilascio_giorni
   from public.marketplace_config where id = 1));

-- [4] Chiusa vuol dire con `valida_fino` valorizzata, non cancellata.
select pg_temp.registra(
  '[04] la riga vecchia è chiusa, non rimossa',
  'true',
  (select (valida_fino is not null)::text
   from public.marketplace_config where id = 1));

-- [5] Nessuno scoperto e nessuna sovrapposizione: `now()` è l'istante della
--     transazione, quindi la chiusura della vecchia e l'apertura della nuova
--     cadono sullo stesso punto. Se le due istruzioni finissero in transazioni
--     diverse, qui si vedrebbe.
select pg_temp.registra(
  '[05] la nuova si apre esattamente quando la vecchia si chiude',
  'true',
  (select (c.valida_fino = n.valida_da)::text
   from public.marketplace_config c,
        public.marketplace_config n
   where c.id = 1 and n.valida_fino is null));

-- [6] Il lettore unico restituisce la nuova riga. È la funzione da cui passa
--     `ordine_prenota`: se leggesse la vecchia, la migrazione non servirebbe.
select pg_temp.registra(
  '[06] private.marketplace_config_corrente() restituisce la nuova riga',
  '800|209|25|14',
  (select (c).margine_obiettivo_bps || '|' || (c).riferimento_stripe_percentuale_bps
          || '|' || (c).riferimento_stripe_fisso_cents || '|' || (c).auto_rilascio_giorni
   from private.marketplace_config_corrente() as c));

-- ---------------------------------------------------------------------------
-- La vista pubblica: i nuovi valori, e nient'altro
-- ---------------------------------------------------------------------------

-- [7] «Nient'altro», primo senso: le colonne. L'elenco è chiuso apposta, perché
--     una colonna aggiunta domani alla tabella base resti privata.
select pg_temp.registra(
  '[07] la vista espone esattamente le quattro colonne dichiarate',
  'auto_rilascio_giorni,margine_obiettivo_bps,riferimento_stripe_fisso_cents,riferimento_stripe_percentuale_bps',
  (select string_agg(column_name, ',' order by column_name)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'public_marketplace_config'));

-- [8] «Nient'altro», secondo senso: le righe. Lo storico non deve affacciarsi.
select pg_temp.registra(
  '[08] la vista espone una sola riga',
  '1',
  (select count(*)::text from public.public_marketplace_config));

-- [9] E quella riga porta i nuovi valori.
select pg_temp.registra(
  '[09] la vista espone i nuovi valori',
  '800|209|25|14',
  (select margine_obiettivo_bps || '|' || riferimento_stripe_percentuale_bps
          || '|' || riferimento_stripe_fisso_cents || '|' || auto_rilascio_giorni
   from public.public_marketplace_config));

-- ---------------------------------------------------------------------------
-- La formula, che non è cambiata
-- ---------------------------------------------------------------------------

-- [10] Il caso della decisione: 45,00 € al venditore, 49,90 € al compratore.
select pg_temp.registra(
  '[10] totale su 4500 centesimi',
  '4990',
  (select private.marketplace_totale_cents(4500, c.margine_obiettivo_bps,
            c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents)::text
   from public.marketplace_config c where c.valida_fino is null));

-- [11]-[13] I bordi. Sui prezzi bassi la quota fissa pesa e la percentuale
--     effettiva sale; sui prezzi alti converge. Il margine netto resta l'8%.
select pg_temp.registra(
  '[11] totale su 1000 centesimi',
  '1129',
  (select private.marketplace_totale_cents(1000, c.margine_obiettivo_bps,
            c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents)::text
   from public.marketplace_config c where c.valida_fino is null));

select pg_temp.registra(
  '[12] totale su 10000 centesimi',
  '11057',
  (select private.marketplace_totale_cents(10000, c.margine_obiettivo_bps,
            c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents)::text
   from public.marketplace_config c where c.valida_fino is null));

select pg_temp.registra(
  '[13] totale su 50000 centesimi',
  '55179',
  (select private.marketplace_totale_cents(50000, c.margine_obiettivo_bps,
            c.riferimento_stripe_percentuale_bps, c.riferimento_stripe_fisso_cents)::text
   from public.marketplace_config c where c.valida_fino is null));

-- [14] La formula non si è mossa. Con i VECCHI parametri deve restituire i
--     VECCHI totali: se qualcuno avesse ritoccato
--     `private.marketplace_totale_cents` invece dei parametri, questo caso
--     fallirebbe mentre da [10] a [13] potrebbero restare verdi.
select pg_temp.registra(
  '[14] con i vecchi parametri la formula dà i vecchi totali',
  '1092|4823|10686|53325',
  (select private.marketplace_totale_cents(1000, 500, 150, 25) || '|'
       || private.marketplace_totale_cents(4500, 500, 150, 25) || '|'
       || private.marketplace_totale_cents(10000, 500, 150, 25) || '|'
       || private.marketplace_totale_cents(50000, 500, 150, 25)));

-- [15] Il margine netto proiettato è davvero l'8% del prezzo del venditore, ai
--     quattro prezzi, con l'arrotondamento per eccesso che non lo fa mai
--     scendere sotto l'obiettivo. È la ragione stessa del cambio: il parametro
--     deve significare ciò che dichiara. La fee proiettata è calcolata come
--     nella vista di riconciliazione della 7b, `round(totale*bps/10000) + fisso`.
select pg_temp.registra(
  '[15] margine netto proiettato >= 8,00% del prezzo ai quattro prezzi',
  'true',
  (select bool_and(
            (f.t - round(f.t::numeric * c.riferimento_stripe_percentuale_bps / 10000)
                 - c.riferimento_stripe_fisso_cents - p.prezzo)::numeric
            >= p.prezzo * 0.08)::text
   from public.marketplace_config c
   cross join (values (1000), (4500), (10000), (50000)) as p(prezzo)
   cross join lateral (select private.marketplace_totale_cents(p.prezzo,
                   c.margine_obiettivo_bps, c.riferimento_stripe_percentuale_bps,
                   c.riferimento_stripe_fisso_cents) as t) as f
   where c.valida_fino is null));

-- [16] Il commento della colonna non descrive più la tariffa di una carta.
--     Un commento fuorviante su un parametro pubblicato è un difetto quanto un
--     valore sbagliato, e questo è il solo posto in cui si può correggere: il
--     testo sorgente della 7b è congelato.
select pg_temp.registra(
  '[16] il commento della colonna nomina il costo ponderato e Connect',
  'true',
  (select (col_description(a.attrelid, a.attnum) like '%ponderato%'
           and col_description(a.attrelid, a.attnum) like '%Connect%')::text
   from pg_attribute a
   where a.attrelid = 'public.marketplace_config'::regclass
     and a.attname = 'riferimento_stripe_percentuale_bps'));

-- ---------------------------------------------------------------------------
-- Esito
-- ---------------------------------------------------------------------------

select caso, atteso, visto, case when passa then 'PASSA' else 'FALLISCE' end as esito
from esiti order by caso;

select count(*) filter (where passa)     as passa,
       count(*) filter (where not passa) as fallisce
from esiti;

rollback;
