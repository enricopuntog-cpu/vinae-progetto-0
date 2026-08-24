-- ===========================================================================
-- Price Intelligence 1A - fondazione dati: osservazioni di prezzo append-only
-- ===========================================================================
--
-- CHE COSA APRE, E CHE COSA NON APRE. Questa migrazione crea l'unico luogo in
-- cui Vinea conserva una storia dei prezzi. Da qui in avanti il prodotto
-- raccoglie due fatti reali, e nient'altro:
--
--   richiesta  il prezzo che un venditore chiede davvero nel marketplace,
--              nel momento in cui l'annuncio entra nella vetrina pubblica o
--              in cui quel prezzo cambia;
--   vendita    il prezzo congelato di un ordine realmente arrivato a
--              `completato`.
--
-- NON c'e' qui, e non e' una dimenticanza: nessun grafico, nessun trend,
-- nessun intervallo, nessun prezzo suggerito, nessun punteggio di affidabilita'
-- e nessuna interfaccia. Sono la Fase 1B, e nascono da questi dati. Una
-- fondazione che calcolasse gia' un indice avrebbe congelato in SQL una
-- formula che nessuno ha ancora deciso.
--
-- NON tocca il placeholder 260/300/120 di `/vendi`
-- (frontend-next/src/hooks/useSellWizard.ts): il collegamento fra la vetrina
-- di vendita e questi dati e' 1B, e farlo qui vorrebbe dire mostrare a un
-- venditore una storia che oggi ha una sola riga.
--
-- NON tocca payout, Stripe, rilascio, auto-rilascio, contestazioni ne' il
-- ciclo di vita dell'ordine. Price Intelligence OSSERVA il dominio ordini; non
-- lo governa. Per questo entrambe le registrazioni sono TRIGGER e non RPC: e'
-- la stessa scelta della 6d-1 e della 7c - cio' che deve valere anche per uno
-- scrittore privilegiato si mette in un trigger, non in una funzione che
-- qualcuno puo' non chiamare. Su `listings` gli stati sono scritti da almeno
-- sei punti diversi (listing_pubblica, la moderazione 9b, tre percorsi di
-- rilascio prenotazione della 7/7b/7c); su `orders`, `completato` e' scritto
-- da quattro. Elencarli in una RPC significherebbe dimenticarne uno oggi e
-- tutti quelli di domani.
--
-- ---------------------------------------------------------------------------
-- PROVIDER-AGNOSTIC, E OFF PER COSTRUZIONE
-- ---------------------------------------------------------------------------
--
-- La fonte interna Vinea funziona da sola e a costo zero: sono i dati del
-- prodotto. `public.price_observation_fonte` esiste perche' un domani si possa
-- distinguere un dato interno da uno di un fornitore esterno di market data
-- senza rifare il modello - ma oggi ha UNA sola label, `vinea_interno`, e
-- nessun nome di fornitore compare in questo file. Non e' stato scelto nessun
-- provider, e sceglierlo non e' una decisione tecnica.
--
-- Il confine e' fail-closed per COSTRUZIONE, non per configurazione, e sono
-- tre fatti misurabili invece di una promessa:
--
--   1. non esiste alcuna via d'ingresso esterna. `anon` e `authenticated` non
--      hanno alcun privilegio sulla tabella, e le sole funzioni che la
--      nominano sono la porta di scrittura interna e il guardiano
--      append-only. Nessuna Edge Function, nessun cron, nessun client HTTP,
--      nessuna chiave API;
--   2. il CHECK `..._solo_fonti_interne` rifiuta a livello di riga qualunque
--      `fonte` diversa da quella interna. Oggi l'enum ha una sola label,
--      quindi nessun chiamante puo' nemmeno nominare una fonte esterna; se un
--      domani l'enum ne acquistasse una, le righe di quella fonte
--      resterebbero rifiutate finche' una migrazione successiva non toglie
--      deliberatamente il vincolo. Questo vincolo lega anche `service_role`;
--   3. accendere un fornitore richiede quindi TRE atti espliciti in una
--      migrazione nuova - label, vincolo, via d'ingresso - e nessuno dei tre
--      puo' accadere per errore o per merge.
--
-- Nessun flag d'ambiente: un flag e' un interruttore che qualcuno puo' girare,
-- e non c'e' niente da accendere finche' non esiste il codice che consuma la
-- fonte. La Price Intelligence interna non dipende da nulla di tutto questo e
-- funziona comunque.
--
-- ---------------------------------------------------------------------------
-- IDENTITA' DEL VINO: wine_id NON BASTA DA SOLO
-- ---------------------------------------------------------------------------
--
-- `public.wines` e' gia' produttore + vino + annata (vincolo UNIQUE della 6a),
-- quindi il wine_id identifica l'annata e non serve una tassonomia nuova. Ma
-- `wines.formato` ha `default '0,75 L'` e NON e' nel vincolo di unicita': due
-- formati dello stesso vino sono oggi la stessa riga, e nulla impedisce a uno
-- staff di modificarlo. Confrontare il prezzo di una 0,75 L con quello di una
-- magnum non e' un errore di arrotondamento - e' un altro mercato.
--
-- Per questo `formato` e' COPIATO sull'osservazione al momento in cui nasce,
-- invece di essere letto da `wines` al momento della lettura. Un'osservazione
-- e' un fatto storico: deve restare vera anche se il catalogo cambia sotto.
-- La lettura raggruppa per (wine_id, formato), e la Fase 1B non puo' mescolare
-- formati incompatibili nemmeno volendo.
--
-- Il modello del catalogo NON viene modificato: nessuna colonna nuova su
-- `wines`, nessuna separazione wine/wine_vintage. Non serve a questo task.

-- ---------------------------------------------------------------------------
-- Tipi
-- ---------------------------------------------------------------------------

create type public.price_observation_tipo as enum ('richiesta', 'vendita');

comment on type public.price_observation_tipo is
  'Che cosa dice il prezzo osservato. `richiesta`: un venditore lo chiede '
  'davvero nella vetrina pubblica di Vinea. `vendita`: un ordine reale si e'' '
  'chiuso a quel prezzo. Non sono la stessa informazione e non vanno mediate '
  'insieme senza deciderlo: un chiesto non e'' un pagato.';

create type public.price_observation_fonte as enum ('vinea_interno');

comment on type public.price_observation_fonte is
  'Provenienza del dato. Una sola label oggi: il marketplace Vinea. Esiste '
  'per rendere estensibile la provenienza senza rifare il modello, NON per '
  'annunciare un fornitore - nessuno e'' stato scelto. Aggiungere una label '
  'non basta ad accendere nulla: vedi il CHECK ..._solo_fonti_interne.';

-- ---------------------------------------------------------------------------
-- wine_price_observations - il registro append-only
-- ---------------------------------------------------------------------------
-- Una tabella interna piu' una vista pubblica, e non una tabella sola con RLS
-- selettiva. La ragione e' la regola di esposizione della 6d-1: la RLS filtra
-- righe e non colonne, e qui la colonna da non far uscire - `origine_ref`, che
-- e' un id di annuncio o di ordine - sta sulla stessa riga del prezzo, che
-- invece deve uscire. Una vista `security_invoker = off` con elenco chiuso e'
-- l'unica forma in cui una colonna aggiunta domani resta privata finche'
-- qualcuno non la espone di proposito.

create table public.wine_price_observations (
  id uuid primary key default gen_random_uuid(),

  wine_id uuid not null references public.wines (id) on delete restrict,

  -- Copiato da wines.formato alla nascita dell'osservazione, non letto in
  -- join alla lettura. Vedi il cappello: un fatto storico non cambia quando
  -- cambia il catalogo.
  formato text not null check (length(trim(formato)) > 0),

  tipo public.price_observation_tipo not null,
  fonte public.price_observation_fonte not null,

  -- Interi in centesimi, come listings.prezzo_cents e orders.prezzo_cents. Il
  -- dominio e' discreto e il tipo deve esserlo.
  prezzo_cents integer not null check (prezzo_cents > 0),
  valuta text not null default 'eur' check (valuta = 'eur'),

  -- QUANDO IL FATTO E' ACCADUTO. Per una richiesta: l'istante in cui
  -- l'annuncio e'' entrato in vetrina o in cui il prezzo e' cambiato. Per una
  -- vendita: `orders.paid_at`, l'istante in cui il denaro si e' mosso davvero.
  observed_at timestamptz not null,

  -- QUANDO VINEA L'HA SAPUTO. Distinto da observed_at di proposito: una
  -- vendita si REGISTRA al passaggio a `completato`, ma e' ACCADUTA al
  -- pagamento. Tenerli separati e' cio' che permette al backfill di dire la
  -- verita' invece di inventare una storia.
  created_at timestamptz not null default now(),

  -- Id dell'annuncio (richiesta) o dell'ordine (vendita). Serve a due cose
  -- sole: deduplicare e poter risalire al fatto in un'indagine. NON esce mai
  -- dalla vista pubblica, e per questo la vista ha un elenco chiuso.
  --
  -- Nessuna FOREIGN KEY, e non e' una svista. Un vincolo referenziale
  -- imporrebbe una scelta fra tre mali: `cascade` cancellerebbe storia
  -- quando una riga di dominio sparisce, `set null` sarebbe un UPDATE su una
  -- tabella append-only e verrebbe rifiutato dal suo stesso trigger,
  -- `restrict` legherebbe la cancellabilita' di ordini e annunci a una
  -- tabella di osservazione. Un'osservazione e' un fatto avvenuto, non una
  -- proiezione della riga che l'ha causata.
  origine_ref uuid not null
);

comment on table public.wine_price_observations is
  'Registro append-only dei prezzi osservati da Price Intelligence. Nessun '
  'UPDATE e nessun DELETE, per nessun ruolo, service_role e proprietario '
  'compresi: sono trigger e non solo GRANT, perche'' un GRANT non vincola il '
  'proprietario della tabella. Il client non ha alcun privilegio di scrittura '
  'e la lettura passa dalla vista public.wine_price_history.';

comment on column public.wine_price_observations.observed_at is
  'Istante reale del fatto osservato. Per una vendita e'' orders.paid_at, non '
  'l''istante della registrazione: quello e'' created_at.';

comment on column public.wine_price_observations.origine_ref is
  'Annuncio (richiesta) o ordine (vendita). Identificativo tecnico interno: '
  'non esce dalla vista pubblica e non e'' un dato personale.';

-- IL VINCOLO CHE TIENE OFF LE FONTI ESTERNE. Non ridondante rispetto
-- all'enum: l'enum dice quali label esistono, questo dice quali sono ammesse
-- IN SCRITTURA oggi. Aggiungere una label domani non accende niente finche'
-- una migrazione nuova non toglie deliberatamente questo vincolo.
alter table public.wine_price_observations
  add constraint wine_price_observations_solo_fonti_interne
  check (fonte = 'vinea_interno');

-- IDEMPOTENZA DELLA VENDITA, espressa dal database e non sperata dal codice:
-- un ordine completato produce AL PIU' una osservazione di vendita. Parziale,
-- perche' su `richiesta` lo stesso annuncio deve poter avere piu' righe - e'
-- esattamente la storia che serve.
create unique index wine_price_observations_una_vendita_per_ordine
  on public.wine_price_observations (origine_ref)
  where tipo = 'vendita';

-- Indice di lettura della 1B: la serie di un vino in un formato, in ordine di
-- tempo. E' la sola forma di interrogazione che la vista espone.
create index wine_price_observations_serie_idx
  on public.wine_price_observations (wine_id, formato, observed_at desc);

create index wine_price_observations_origine_idx
  on public.wine_price_observations (origine_ref, tipo);

-- I privilegi si azzerano prima di non concederne nessuno. Senza questa
-- revoca gli ALTER DEFAULT PRIVILEGES del progetto darebbero ad anon e
-- authenticated tutti i permessi sulla tabella nuova, e l'append-only sarebbe
-- decorativo. Nessun GRANT segue: i due ruoli del browser non hanno qui
-- nemmeno la lettura, che passa dalla vista.
--
-- `service_role` NON viene revocato, ed e' deliberato: e' la chiave di
-- back-office, e in questo repository conserva i privilegi di tabella
-- ovunque - `audit_log`, che e' l'altra tabella append-only, si comporta
-- esattamente cosi'. La regola del repository e' che cio' che deve valere
-- anche per un ruolo privilegiato si mette in un trigger o in un vincolo, non
-- in un GRANT: qui `service_role` puo' inserire una osservazione interna, ma
-- NON puo' riscriverla ne' cancellarla (i tre trigger append-only) e NON puo'
-- dichiararla di fonte esterna (il CHECK piu' sopra). Toglierle il GRANT
-- romperebbe il back-office senza chiudere nessuna di queste tre porte, che
-- sono gia' chiuse altrove.
revoke all on public.wine_price_observations from anon, authenticated;

-- RLS accesa (l'event trigger `ensure_rls` della 20260729234000 lo farebbe
-- comunque; scriverlo rende l'invariante leggibile qui). Nessuna policy: senza
-- policy e senza GRANT la tabella e' chiusa a ogni ruolo client in lettura e
-- in scrittura. I trigger sono SECURITY DEFINER e non passano dalla RLS.
alter table public.wine_price_observations enable row level security;

-- ---------------------------------------------------------------------------
-- Append-only, contro chiunque
-- ---------------------------------------------------------------------------
-- Stessa forma di private.audit_log_append_only() della 9a. Tre trigger e non
-- uno: TRUNCATE non passa dai trigger di riga.

create or replace function private.wine_price_observations_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception
    'wine_price_observations e append-only: % non e ammesso.', tg_op
    using errcode = '42501';
end;
$$;

comment on function private.wine_price_observations_append_only() is
  'Rifiuta UPDATE, DELETE e TRUNCATE su public.wine_price_observations per '
  'ogni ruolo. Un trigger e'' l''unico modo di esprimere questo invariante: i '
  'GRANT non vincolano il proprietario della tabella.';

create trigger wine_price_observations_no_update
  before update on public.wine_price_observations
  for each row execute function private.wine_price_observations_append_only();

create trigger wine_price_observations_no_delete
  before delete on public.wine_price_observations
  for each row execute function private.wine_price_observations_append_only();

create trigger wine_price_observations_no_truncate
  before truncate on public.wine_price_observations
  for each statement
  execute function private.wine_price_observations_append_only();

-- ---------------------------------------------------------------------------
-- private.price_observation_registra - l'unico scrittore
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER perche' i due trigger che la chiamano girano nel contesto
-- di un venditore o di un compratore, che sulla tabella non hanno alcun
-- privilegio - ed e' giusto che non l'abbiano. Non e' un aggiramento comodo di
-- un permesso: e' l'unica porta, ed e' chiusa a tutti tranne che ai trigger.
--
-- Non riceve mai un id dal client: i due chiamanti passano `new.id` di una
-- riga gia' scritta e verificata dal proprio dominio.

create or replace function private.price_observation_registra(
  p_wine_id      uuid,
  p_formato      text,
  p_tipo         public.price_observation_tipo,
  p_prezzo_cents integer,
  p_observed_at  timestamptz,
  p_origine_ref  uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Un dato incompleto non diventa una riga di storia sbagliata: si tace. Un
  -- prezzo non positivo o un vino sconosciuto qui vorrebbero dire che il
  -- dominio a monte ha gia' un difetto, e non e' questo il posto in cui
  -- fermare un ordine o una pubblicazione per segnalarlo.
  if p_wine_id is null or p_prezzo_cents is null or p_prezzo_cents <= 0 then
    return;
  end if;

  insert into public.wine_price_observations (
    wine_id, formato, tipo, fonte, prezzo_cents, observed_at, origine_ref
  )
  values (
    p_wine_id,
    coalesce(nullif(btrim(p_formato), ''), '0,75 L'),
    p_tipo,
    'vinea_interno',
    p_prezzo_cents,
    coalesce(p_observed_at, now()),
    p_origine_ref
  )
  -- Rete di idempotenza sulla vendita: se l'indice parziale trova gia' la riga
  -- di questo ordine, non solleva - non registra. Una seconda esecuzione di un
  -- percorso di completamento non deve rompere l'ordine per colpa di una
  -- osservazione.
  on conflict do nothing;
end;
$$;

comment on function private.price_observation_registra(
  uuid, text, public.price_observation_tipo, integer, timestamptz, uuid
) is
  'Unica porta di scrittura di wine_price_observations. Chiamata soltanto dai '
  'due trigger di dominio. `on conflict do nothing` rende idempotente la '
  'registrazione di vendita senza far fallire il completamento dell''ordine.';

revoke execute on function private.price_observation_registra(
  uuid, text, public.price_observation_tipo, integer, timestamptz, uuid
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- ASKING - il prezzo chiesto davvero nella vetrina pubblica
-- ---------------------------------------------------------------------------
-- Le quattro decisioni di questo trigger, esplicite perche' sono decisioni di
-- dominio e non dettagli:
--
--   [a] SOLO `attivo`. Una bozza, un annuncio in revisione, sospeso, scaduto,
--       rifiutato o riservato non e' un prezzo chiesto al mercato: e' un
--       numero in un modulo. Il caso `riservato` merita una riga a parte piu'
--       sotto.
--
--   [b] ENTRARE in vetrina registra. bozza | modifiche_richieste |
--       in_revisione | sospeso | scaduto | rifiutato -> attivo e' il momento
--       in cui quel prezzo diventa un'offerta reale. Vale anche per la
--       riattivazione decisa dalla moderazione (9b): l'annuncio torna
--       davvero in vetrina.
--
--   [c] GIA' in vetrina: conta solo il prezzo. Un UPDATE che cambia
--       descrizione, fotografie, tag, condizione o conservazione non produce
--       nulla, e nemmeno un UPDATE che riscrive lo stesso prezzo. Il confronto
--       e' `new.prezzo_cents is distinct from old.prezzo_cents`, quindi ogni
--       variazione REALE - e ogni variazione successiva - produce una riga
--       nuova e la storia diventa ordinabile.
--
--   [d] `riservato` -> `attivo` NON registra. E' l'unica esclusione, e non e'
--       una svista. Quel passaggio non lo decide un venditore: lo scrivono i
--       tre percorsi di rilascio della prenotazione (7 riga 603, 7b riga 561,
--       7c riga 723) quando un checkout scade o un ordine si annulla. Il
--       prezzo non e' cambiato e nessuno ha chiesto niente di nuovo:
--       registrarlo riempirebbe la storia di rumore proporzionale ai checkout
--       abbandonati, cioe' esattamente il contrario di un dato di mercato. Se
--       il prezzo E' cambiato mentre l'annuncio era riservato, il ramo [c] non
--       lo copre - ma nemmeno il client puo' averlo cambiato, perche'
--       `listings_update_own` (20260819090000) non ammette l'UPDATE da
--       `riservato`.
--
-- `prezzo_mercato_cents` NON viene letto qui, ne' altrove in questa
-- migrazione. E' un campo legacy la cui provenienza non e' abbastanza forte
-- per farne un'osservazione di mercato autorevole: sei righe in produzione, e
-- nessuno sa da dove vengano i numeri. Resta dov'e', e come deprecarlo o
-- sostituirlo e' una decisione di una fase successiva.

create or replace function private.listings_price_observation_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registra boolean := false;
  v_wine_id  uuid;
  v_formato  text;
begin
  -- [a]
  if new.stato <> 'attivo' then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- Nasce gia' attivo. Dal client e' impossibile - `stato` non e' fra i
    -- GRANT di colonna della 6a e il DEFAULT e' 'bozza' - ma uno scrittore
    -- privilegiato puo' farlo, ed e' proprio per coprirlo che questo e' un
    -- trigger.
    v_registra := true;
  elsif old.stato = 'attivo' then
    -- [c]
    v_registra := new.prezzo_cents is distinct from old.prezzo_cents;
  elsif old.stato = 'riservato' then
    -- [d]
    v_registra := false;
  else
    -- [b]
    v_registra := true;
  end if;

  if not v_registra then
    return null;
  end if;

  select w.id, w.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
    join public.wines w on w.id = bu.wine_id
  where bu.id = new.bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'richiesta', new.prezzo_cents, now(), new.id
  );

  return null;
end;
$$;

comment on function private.listings_price_observation_sync() is
  'Registra una osservazione `richiesta` quando un annuncio entra nella '
  'vetrina pubblica o quando il prezzo di un annuncio gia'' attivo cambia '
  'davvero. Il ritorno da `riservato` e'' escluso di proposito: lo scrivono i '
  'percorsi di rilascio prenotazione, non un venditore.';

revoke execute on function private.listings_price_observation_sync()
  from public, anon, authenticated;

-- AFTER e non BEFORE: si osserva un fatto gia' avvenuto, e un difetto di
-- Price Intelligence non deve poter impedire una pubblicazione.
create trigger listings_price_observation_sync
  after insert or update on public.listings
  for each row
  when (new.stato = 'attivo')
  execute function private.listings_price_observation_sync();

-- ---------------------------------------------------------------------------
-- SALE - il prezzo congelato di una vendita realmente conclusa
-- ---------------------------------------------------------------------------
-- QUALE TRANSIZIONE, E PERCHE' NON UN'ALTRA. `public.order_stato` ha dieci
-- label; la vendita conclusa e' `completato`, e non e' stata inventata qui:
--
--   `pagato`     il denaro e' incassato ma la compravendita puo' ancora
--                finire in `rimborsato` o `annullato`. Registrare qui
--                vorrebbe dire chiamare vendita cio' che puo' essere
--                disfatto;
--   `consegnato` la bottiglia e' arrivata ma la finestra di verifica e'
--                aperta: da li' si passa a `contestato` e si puo' rimborsare;
--   `completato` e' lo stato in cui il dominio DICHIARA avvenuta la
--                compravendita: sblocca il payout al venditore, permette la
--                recensione (7c riga 1202) e chiude la conversazione (8 riga
--                800, che lo raggruppa con `rimborsato` e `annullato` fra gli
--                ordini "conclusi").
--
-- `completato` NON E' PERO' UNO STATO ASSORBENTE, e chiamarlo "terminale"
-- sarebbe impreciso: `public.ordine_contesta` (7b riga 1204) accetta
-- esplicitamente `completato` fra gli stati contestabili, finche' il payout non
-- e' stato trasferito. Un ordine puo' quindi fare completato -> contestato ->
-- completato (contestazione risolta, 7c/7f) oppure completato -> contestato ->
-- rimborsato.
--
-- La conseguenza e' deliberata e va detta per intero: una osservazione
-- `vendita` significa "questo ordine ha RAGGIUNTO `completato` a questo
-- prezzo", non "questo denaro non tornera' mai indietro". Il rientro in
-- `completato` non produce una seconda riga (indice parziale + `on conflict do
-- nothing`), e un rimborso successivo non cancella ne' modifica la riga gia'
-- scritta - non potrebbe, la tabella e' append-only. Come pesare i rimborsi in
-- una statistica di mercato e' una decisione della Fase 1B, che avra' i dati
-- per prenderla: `origine_ref` conserva l'ordine, e lo stato attuale
-- dell'ordine e' leggibile.
--
-- Ci arrivano quattro percorsi diversi (auto-rilascio 7b righe 1165 e 1269,
-- risoluzione di contestazione 7c/7f, la 9c riga 318). Per questo il trigger
-- e' `after update of stato` sulla tabella e non una riga aggiunta a
-- ciascuno: nessun percorso puo' dimenticarsene, presente o futuro.
--
-- IL PREZZO E' `orders.prezzo_cents`, la colonna materializzata congelata alla
-- creazione dell'ordine, non il prezzo corrente dell'annuncio - che il
-- venditore puo' avere cambiato dopo (20260819090000, punto 4a). E' il prezzo
-- del vino: NON `totale_cents` e NON `addebito_totale_cents`, che includono
-- imballaggio e spedizione e non sono un prezzo di mercato del vino.
--
-- `observed_at` E' `paid_at`, non l'istante del completamento. Lo scambio e'
-- avvenuto quando il denaro si e' mosso; il completamento certifica soltanto
-- che non e' stato disfatto. Quando Vinea l'ha saputo resta scritto, in
-- `created_at`.

create or replace function private.orders_price_observation_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wine_id uuid;
  v_formato text;
begin
  select w.id, w.formato
    into v_wine_id, v_formato
  from public.bottle_units bu
    join public.wines w on w.id = bu.wine_id
  where bu.id = new.seller_bottle_unit_id;

  perform private.price_observation_registra(
    v_wine_id, v_formato, 'vendita', new.prezzo_cents,
    coalesce(new.paid_at, now()), new.id
  );

  return null;
end;
$$;

comment on function private.orders_price_observation_sync() is
  'Registra UNA osservazione `vendita` quando un ordine entra in `completato`. '
  'Il prezzo e'' quello congelato sull''ordine, non quello corrente '
  'dell''annuncio. L''unicita'' e'' garantita dall''indice parziale '
  'wine_price_observations_una_vendita_per_ordine, non da questo codice: '
  '`completato` non e'' assorbente (ordine_contesta lo accetta), quindi un '
  'rientro dopo una contestazione NON produce una seconda riga.';

revoke execute on function private.orders_price_observation_sync()
  from public, anon, authenticated;

create trigger orders_price_observation_sync
  after update of stato on public.orders
  for each row
  when (new.stato = 'completato' and old.stato is distinct from 'completato')
  execute function private.orders_price_observation_sync();

-- ---------------------------------------------------------------------------
-- public.wine_price_history - il modello di lettura
-- ---------------------------------------------------------------------------
-- `security_invoker = off` con elenco chiuso di colonne, come public_listings
-- e public_clubs. Il linter Supabase la segnalera' come
-- `security_definer_view`: e' la segnalazione attesa per questo pattern.
--
-- COSA NON ESCE, ed e' il motivo per cui questa vista esiste: `origine_ref`,
-- e con esso ogni riferimento ad annuncio, ordine, venditore, compratore o
-- persona. Una colonna aggiunta domani alla tabella base resta privata finche'
-- qualcuno non la aggiunge QUI di proposito.
--
-- COSA NON CALCOLA, ed e' deliberato: nessuna media, nessun intervallo,
-- nessun minimo o massimo, nessun conteggio, nessun punteggio. Sono la 1B, e
-- una vista che gia' aggregasse imporrebbe la formula prima che qualcuno
-- l'abbia scelta. Qui ci sono i fatti, uno per riga, ordinabili.

create view public.wine_price_history
with (security_invoker = off)
as
select
  o.wine_id,
  w.slug        as wine_slug,
  w.produttore,
  w.nome,
  w.annata,
  o.formato,
  o.tipo,
  o.fonte,
  o.prezzo_cents,
  o.valuta,
  o.observed_at
from public.wine_price_observations o
  join public.wines w on w.id = o.wine_id;

comment on view public.wine_price_history is
  'Serie storica dei prezzi osservati, per vino e formato. Elenco chiuso di '
  'colonne: nessun identificativo di annuncio, ordine, venditore o '
  'compratore, e nessun dato personale. Non aggrega nulla - media, intervallo '
  'e affidabilita'' sono decisioni della Fase 1B.';

revoke all on public.wine_price_history from anon, authenticated;
grant select on public.wine_price_history to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Backfill UNA TANTUM degli annunci oggi in vetrina
-- ---------------------------------------------------------------------------
-- SENZA FALSIFICARE LA STORIA, ed e' il punto piu' facile da sbagliare.
-- `observed_at` e' `now()`, cioe' il momento reale in cui Vinea ACQUISISCE
-- questo dato. Non `published_at` e non `created_at`: nessuno puo' dimostrare
-- che il prezzo di oggi fosse quello anche il giorno della pubblicazione,
-- perche' fino a questa migrazione le modifiche di prezzo non lasciavano
-- traccia (20260819090000, punto 4b). Datare all'indietro trasformerebbe una
-- congettura in una riga di storia.
--
-- Solo `attivo`, solo `prezzo_cents`. `prezzo_mercato_cents` NON viene
-- importato: sei righe in produzione di provenienza ignota non diventano
-- market data autorevole per il fatto di esistere.
--
-- `not exists` invece di `on conflict`: nessun indice unico copre le
-- osservazioni di richiesta - non deve, servono piu' righe per annuncio - e
-- questo rende la sezione rieseguibile a vuoto senza duplicare.

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
    select 1
    from public.wine_price_observations o
    where o.origine_ref = l.id
      and o.tipo = 'richiesta'
  );

-- ---------------------------------------------------------------------------
-- Come si verifica dopo l'applicazione
-- ---------------------------------------------------------------------------
-- Sola lettura, nessuna scrittura:
--
--   select grantee, privilege_type from information_schema.table_privileges
--   where table_schema='public' and table_name='wine_price_observations';
--   -- atteso: zero righe per anon e authenticated.
--
--   select count(*) from public.wine_price_history;
--   -- atteso: il numero di annunci `attivo` al momento del backfill.
--
--   select distinct fonte from public.wine_price_observations;
--   -- atteso: solo `vinea_interno`.
--
-- La griglia comportamentale e' supabase/tests/price_intelligence_1a.sql. Va
-- eseguita su un database usa e getta: crea utenti, vini, bottiglie, annunci e
-- ordini. NON sul progetto reale.
