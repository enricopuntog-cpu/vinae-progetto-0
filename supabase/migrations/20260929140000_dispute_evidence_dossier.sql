-- ===========================================================================
-- Fascicolo di contestazione: il read model del dossier per la moderazione
-- ===========================================================================
--
-- IL PROBLEMA CHE CHIUDE. Chi modera una contestazione oggi vede soltanto la
-- pratica: motivo, descrizione, fotografie del compratore, risposta del
-- venditore, timeline, note private. Tutto il resto del caso — che cosa era
-- l'annuncio, che confezione originale era stata dichiarata, che cosa il
-- venditore aveva fotografato PRIMA di spedire, dove il pacco e passato — vive
-- in tabelle che il pannello non legge. Il moderatore decide su meta caso, e la
-- meta che gli manca e proprio quella che distingue un danno da trasporto da un
-- imballaggio inadeguato da una merce mai conforme.
--
-- Questa migrazione non aggiunge dati. Aggiunge SOLO strade di lettura verso
-- dati che esistono gia, richiudendo ogni strada dietro lo stesso filtro admin
-- delle viste di moderazione esistenti.
--
-- ---------------------------------------------------------------------------
-- CHE COSA QUESTA MIGRAZIONE NON FA
-- ---------------------------------------------------------------------------
--
--   NESSUNA TABELLA NUOVA. Non nasce un secondo sistema di prove accanto a
--   `private.order_shipping_evidence` (28/09, cancello di spedizione) e a
--   `public.disputes.foto` / `venditore_foto`. Copiare le prove in una tabella
--   di fascicolo avrebbe creato due sorgenti di verita sullo stesso fatto
--   probatorio: la copia e l'originale sarebbero divergiti alla prima
--   sostituzione.
--
--   NESSUNA MODIFICA AL CICLO DI VITA. Le cinque porte di decisione
--   (`moderazione_contestazione_prendi_in_carico`, `..._inizia_revisione`,
--   `..._nota_privata`, `..._decidi`, `ordine_contestazione_risolvi`) non sono
--   toccate da una sola riga di questo file. Il fascicolo e materiale di
--   lettura: non muove stati, non muove denaro, non muove payout.
--
--   NESSUNA MODIFICA ALLE SORGENTI. `private.order_shipping_evidence`,
--   `public.tracking_events`, `public.listings`, `public.orders` restano come
--   sono: nessuna colonna aggiunta, nessuna policy riscritta, nessun grant
--   allargato.
--
--   NESSUN ALLARGAMENTO DELLO STORAGE. La policy di SELECT
--   `dispute_evidence_participants_select` (20260928210000, righe 269-291)
--   porta gia un ramo admin incondizionato sull'intero bucket
--   `dispute-evidence`, valutato PRIMA e FUORI dalla sottoquery sugli ordini.
--   Un admin puo percio firmare un oggetto di prova pre-spedizione senza che
--   qui si tocchi nulla. Verificato sul testo della policy distribuita; se un
--   domani quel ramo cambiasse, la risposta corretta non e aprire il bucket ma
--   una porta stretta dedicata.
--
--   NESSUNA PROVA DI CONSEGNA DEL VETTORE. Non esiste oggi un provider
--   logistico integrato, quindi non esiste un POD. `orders.consegnato_at` e
--   uno stato dell'ordine nel nostro dominio, NON la prova di consegna del
--   corriere, e questa migrazione non lo ribattezza e non lo espone come tale.
--   Nessuna colonna POD viene inventata: quando il provider arrivera, portera
--   il proprio dato.
--
-- ---------------------------------------------------------------------------
-- PERCHE LE PROVE SOSTITUITE RESTANO VISIBILI
-- ---------------------------------------------------------------------------
--
-- `private.order_shipping_evidence` conserva la storia delle sostituzioni:
-- CORRENTE e `superseded_at is null`, ed e unica per (ordine, tipo) grazie
-- all'indice parziale `order_shipping_evidence_corrente_uniq`. Fuori dalla
-- contestazione la sostituzione e innocua: conta l'ultima fotografia.
--
-- DENTRO una contestazione non lo e. Una prova sostituita poco prima o poco
-- dopo l'apertura della pratica e essa stessa materiale probatorio: dice che
-- cosa il venditore aveva documentato prima, e quando ha cambiato la
-- documentazione. Nascondere lo storico al moderatore significherebbe
-- consegnargli una versione ripulita del caso. La vista percio espone
-- CORRENTI e SOSTITUITE, distinte da `is_current`, e la UI mostra le
-- sostituite marcate, mai eliminate.
--
-- ---------------------------------------------------------------------------
-- PERCHE handoff_venditore RESTA FUORI
-- ---------------------------------------------------------------------------
--
-- `public.listings.handoff_venditore` (28/09) e una preferenza operativa del
-- venditore su come consegna il pacco alla rete logistica. Non e un dato della
-- merce, non e materiale probatorio, non serve a decidere una contestazione.
-- Non e esposto da `public_listings` e non viene esposto qui: una colonna
-- aggiunta a un read model e una colonna che qualcuno un giorno mostrera.
--
-- ---------------------------------------------------------------------------
-- IL MODELLO DI SICUREZZA
-- ---------------------------------------------------------------------------
--
-- Le tre viste sono `security_invoker = off` con `security_barrier = true` e
-- un predicato `public.has_role((select auth.uid()), 'admin')` esplicito nel
-- corpo: e il predicato, non la RLS della tabella sorgente, l'autorita che
-- filtra. E' lo stesso schema delle altre viste `moderation_*`, ed e la
-- ragione per cui il lint 0010 (`security_definer_view`) su queste viste e
-- un'eccezione accettata e documentata: passarle a `security_invoker = on`
-- romperebbe la lettura (il chiamante non ha privilegi su `private`) senza
-- aggiungere sicurezza.
--
-- I grant sono chiusi: `revoke all ... from public, anon, authenticated` e poi
-- il solo `select` a `authenticated`. Un `authenticated` non admin ha il
-- privilegio di interrogare la vista e riceve zero righe, perche il predicato
-- interno lo esclude. Compratore e venditore della pratica non fanno eccezione.
--
-- `storage_path` compare nella vista delle prove di spedizione perche e cio che
-- il servizio deve firmare: e un identificatore di oggetto dentro un bucket
-- privato, non un URL. Nessun URL firmato viene mai scritto in database, in
-- nessuna colonna e da nessuna porta.

-- ===========================================================================
-- 1. Coda di moderazione: le colonne del fascicolo, in coda
-- ===========================================================================
--
-- Ricreata dalla definizione EFFETTIVA piu recente
-- (20260921170806_complete_club_dispute_lifecycles.sql, righe 768-788). Le 33
-- colonne esistenti restano identiche, nello stesso ordine, con gli stessi
-- nomi: `create or replace view` lo impone e la UI distribuita ci conta. Le
-- dieci colonne del fascicolo sono aggiunte IN CODA.
--
-- Il join su `public.listings` e un LEFT JOIN benche `orders.listing_id` sia
-- `not null` con vincolo `on delete restrict`: una contestazione non deve
-- poter sparire dalla coda di moderazione a causa di una strada di lettura
-- aggiunta per comodita. Se un giorno quella garanzia cambiasse, la coda
-- perderebbe un caso invece di perdere una fotografia, ed e il contrario di
-- cio che serve.

create or replace view public.moderation_dispute_queue
with (security_invoker = off, security_barrier = true) as
select d.id, d.order_id, d.aperta_da, ap.username as aperta_da_username,
  o.seller_id, sp.username as seller_username, d.motivo, d.descrizione, d.foto,
  d.stato, d.esito_nota, d.risolta_da, d.apertura_at, d.chiusura_at,
  o.stato as ordine_stato, o.payout_stato as ordine_payout_stato,
  o.totale_cents, o.addebito_totale_cents, d.venditore_scadenza_at,
  d.venditore_risposta_tipo, d.venditore_risposta, d.venditore_foto,
  d.venditore_risposta_at, d.documentazione_completa_at,
  d.lifecycle_status, d.assigned_to, assignee.username as assigned_to_username,
  d.claimed_at, d.review_started_at, d.resolution_kind, d.resolution_note,
  d.resolved_at, d.resolution_version,
  -- Fascicolo: l'annuncio collegato alla vendita.
  o.listing_id,
  l.slug as listing_slug,
  coalesce(l.immagini, '{}'::text[]) as listing_immagini,
  l.confezione_originale_tipo,
  coalesce(l.confezione_originale_foto, '{}'::text[]) as confezione_originale_foto,
  -- Fascicolo: spedizione e consegna, come li conosce il nostro dominio.
  o.corriere,
  o.tracking_number,
  o.spedito_at,
  o.consegnato_at,
  o.ricezione_confermata_at
from public.disputes d
join public.orders o on o.id = d.order_id
join public.profiles ap on ap.id = d.aperta_da
join public.profiles sp on sp.id = o.seller_id
left join public.profiles assignee on assignee.id = d.assigned_to
left join public.listings l on l.id = o.listing_id
where public.has_role((select auth.uid()), 'admin');

comment on view public.moderation_dispute_queue is
  'Coda contestazioni per la moderazione. Dal fascicolo (29/09) porta anche '
  'l''annuncio collegato alla vendita (id, slug, immagini, confezione '
  'originale dichiarata e sue fotografie) e i campi di spedizione e consegna '
  'dell''ordine. `handoff_venditore` resta fuori: preferenza operativa del '
  'venditore, non materiale probatorio. `consegnato_at` e lo stato di consegna '
  'del NOSTRO dominio, non la prova di consegna del vettore, che oggi non '
  'esiste. `confezione_originale_tipo` NULL significa "non dichiarata", mai '
  '"nessuna confezione": quest''ultima e un valore esplicito. Il filtro admin '
  'e nel corpo della vista.';

revoke all on public.moderation_dispute_queue from public, anon, authenticated;
grant select on public.moderation_dispute_queue to authenticated;

-- ===========================================================================
-- 2. Prove pre-spedizione del venditore, correnti e sostituite
-- ===========================================================================
--
-- Lista di colonne CHIUSA: la vista non fa `select e.*`. `uploader_id` resta
-- fuori — il caricatore e sempre il venditore dell'ordine e la colonna non
-- aggiunge nulla al giudizio — e una colonna aggiunta domani a
-- `private.order_shipping_evidence` resta privata finche qualcuno non decide
-- di esporla qui, deliberatamente.

create view public.moderation_dispute_shipping_evidence
with (security_invoker = off, security_barrier = true) as
select
  d.id as dispute_id,
  e.order_id,
  e.id as evidence_id,
  e.evidence_kind,
  e.storage_path,
  e.created_at,
  e.superseded_at,
  (e.superseded_at is null) as is_current
from public.disputes d
join private.order_shipping_evidence e on e.order_id = d.order_id
where public.has_role((select auth.uid()), 'admin');

comment on view public.moderation_dispute_shipping_evidence is
  'Prove pre-spedizione del venditore leggibili dal fascicolo di una '
  'contestazione. Espone CORRENTI e SOSTITUITE: dentro una pratica lo storico '
  'delle sostituzioni e esso stesso materiale probatorio, e `is_current` le '
  'distingue. Lista di colonne chiusa; `uploader_id` non e esposto. '
  '`storage_path` e un identificatore di oggetto nel bucket privato '
  '`dispute-evidence`, da firmare al momento della lettura: nessun URL firmato '
  'viene mai persistito. Solo admin, per predicato interno.';

revoke all on public.moderation_dispute_shipping_evidence from public, anon, authenticated;
grant select on public.moderation_dispute_shipping_evidence to authenticated;

-- ===========================================================================
-- 3. Eventi di tracking dell'ordine contestato
-- ===========================================================================
--
-- `public.tracking_events` ha gia una sua RLS per i partecipanti all'ordine.
-- Questa vista non la tocca e non la sostituisce: apre una seconda strada,
-- richiusa dal filtro admin, perche il moderatore non e un partecipante
-- all'ordine e la policy esistente — correttamente — lo escluderebbe.
--
-- Gli eventi sono cio che il nostro dominio ha registrato sul viaggio del
-- pacco. Non sono un tracciamento del vettore e non vanno letti come tale.

create view public.moderation_dispute_tracking
with (security_invoker = off, security_barrier = true) as
select
  d.id as dispute_id,
  t.order_id,
  t.id as tracking_event_id,
  t.tipo,
  t.titolo,
  t.descrizione,
  t.luogo,
  t.created_at
from public.disputes d
join public.tracking_events t on t.order_id = d.order_id
where public.has_role((select auth.uid()), 'admin');

comment on view public.moderation_dispute_tracking is
  'Eventi di tracking degli ordini contestati, per il fascicolo di '
  'moderazione. Seconda strada di lettura accanto alla RLS per partecipanti di '
  '`public.tracking_events`, che non viene modificata: il moderatore non e '
  'parte dell''ordine. Sono eventi del nostro dominio, non un tracciamento del '
  'vettore. Solo admin, per predicato interno.';

revoke all on public.moderation_dispute_tracking from public, anon, authenticated;
grant select on public.moderation_dispute_tracking to authenticated;

notify pgrst, 'reload schema';
