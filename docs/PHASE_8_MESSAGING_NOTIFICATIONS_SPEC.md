# Fase 8 - Messaggistica privata e notifiche persistenti

Stato: specifica organizzativa approvata il 7 agosto 2026. Implementazione
autorizzata soltanto in locale sul branch
`migration/phase-8-messaging-notifications`.

## Confini

La fase porta in `frontend-next/` le rotte `/messaggi` e `/notifiche` senza
ridisegnare il prototipo. La sorgente canonica diventa PostgreSQL; Realtime
trasporta invalidazioni e non sostituisce letture o paginazione.

Sono inclusi:

- conversazioni private 1:1 nate da un annuncio o da un ordine condiviso;
- messaggi persistenti immutabili e notifiche persistenti;
- adapter mock e Supabase dietro contratti comuni;
- Broadcast privato autorizzato via RLS;
- badge, stati loading/empty/error/offline/sola lettura e retry idempotente;
- test SQL, TypeScript e di lifecycle Realtime.

Restano fuori:

- messaggi diretti arbitrari e chat di gruppo;
- allegati, modifica, cancellazione e retention applicativa dei messaggi;
- blocco, segnalazione e moderazione persistente, che appartengono alla Fase 9;
- AI e suggerimenti, che appartengono alla Fase 10;
- deploy, SQL remoto, fixture remote, impostazioni Dashboard, push, PR e merge.

## Invarianti di dominio

Ogni conversazione ha una coppia UUID canonica ordinata, esattamente due righe
partecipante e un annuncio obbligatorio. La coppia comprende sempre il venditore
dell'annuncio. Un eventuale ordine deve riferirsi allo stesso annuncio e alla
stessa coppia compratore/venditore. La chiave
`(listing_id, participant_low, participant_high)` impedisce duplicati.

Una nuova conversazione si apre soltanto da:

- un annuncio `attivo` e non scaduto, con chiamante diverso dal venditore; o
- un ordine non terminale condiviso dal chiamante.

Una conversazione gia esistente resta leggibile anche se l'annuncio o l'ordine
si chiudono. E scrivibile quando almeno una condizione e vera:

- annuncio `attivo` e non scaduto;
- ordine collegato non in `completato`, `rimborsato` o `annullato`.

I messaggi utente sono normalizzati con `btrim`, lunghi 1-2000 caratteri,
senza allegati e con mittente derivato esclusivamente da `auth.uid()`. Sono
immutabili. Una chiave UUID idempotente vale nella singola conversazione: un
retry identico restituisce la riga esistente prima di consumare rate limit;
riusare la chiave con mittente o testo diverso fallisce.

I limiti applicativi sono server-side:

- 30 nuovi messaggi per minuto per utente;
- 10 nuovi messaggi ogni 10 secondi per utente e conversazione.

Le notifiche hanno destinatario server-side, categoria
`marketplace | community | sistema`, chiave di deduplicazione e `read_at`.
La destinazione e una union persistita e validata tra
`none | conversation | listing | order | club`; non esistono URL arbitrari.
Ogni nuovo messaggio utente crea una notifica per la controparte nella stessa
transazione. Gli eventi sistema futuri passano dalla porta interna idempotente
`private.conversation_system_event`; nessun backfill e implicito.

## Schema e privilegi

La migrazione additiva
`supabase/migrations/20260806224517_phase_8_messaging_notifications.sql`
introduce:

- `public.conversations`;
- `public.conversation_participants`;
- `public.messages`;
- `public.notifications`;
- enum per tipo messaggio, categoria e destinazione notifica;
- vincoli differiti per coppia, partecipanti, annuncio e ordine;
- indici per chiavi esterne, keyset pagination, unread e deduplicazione;
- trigger per cursore ultimo messaggio, immutabilita e Broadcast;
- RPC di apertura, invio, lettura, paginazione e conteggio unread.

`anon` non riceve privilegi. `authenticated` ha SELECT a elenco di colonne e
EXECUTE soltanto sulle RPC pubbliche. Non ha INSERT, UPDATE o DELETE sulle
quattro tabelle. `source_event_key` e `dedupe_key` non sono leggibili dal
browser. Le funzioni di scrittura sono `SECURITY DEFINER`, hanno
`search_path = ''`, qualificano tutti gli oggetti, verificano `auth.uid()` e
revocano l'esecuzione a `PUBLIC` e `anon`. La porta per eventi sistema e
eseguibile soltanto da `service_role`.

Le letture dirette sono isolate con RLS:

- una conversazione e i suoi messaggi sono visibili solo ai due partecipanti;
- le righe partecipante sono visibili soltanto ai membri della conversazione;
- una notifica e visibile soltanto al destinatario;
- nessuna policy client consente scritture dirette.

## Contratti applicativi

I contratti TypeScript non accettano `userId`. L'identita proviene dalla
sessione Supabase o dal profilo demo dell'adapter mock.

- `PageCursor`: tupla ISO `createdAt` + UUID `id`;
- `ConversationSummary`: controparte, annuncio, ordine, ultimo messaggio,
  conteggio unread e stato scrivibile;
- `Message` e `MessagePage`: pagina keyset, ordinamento canonico e cursore;
- `OpenConversationInput`: union esclusiva annuncio/ordine;
- `SendMessageInput`: conversazione, testo e chiave idempotente UUID;
- `NotificationDestination`: union tipizzata senza URL;
- `Notification` e `NotificationPage`: destinazione, categoria, lettura e
  cursore;
- `RealtimeState`: `idle | connecting | connected | reconnecting | offline |
  error`.

Gli adapter condividono gli stessi risultati e lo stesso mapping. Il mock non
finge moderazione, allegati o funzionalita persistenti escluse dalla fase.

## Realtime

La fase usa Database Broadcast privato, non Postgres Changes. I topic sono:

- `conversation:<uuid>`;
- `user:<uuid>:notifications`.

Il client chiama `supabase.realtime.setAuth()` prima della subscribe e crea
canali con `config.private = true`. La policy SELECT su `realtime.messages`
richiede `extension = 'broadcast'` e confronta il topic esatto con una
membership o con `auth.uid()`. Non esiste policy INSERT: il browser non
pubblica eventi.

I payload sono invalidazioni a elenco chiuso:

```text
{ schemaVersion, entity: "message", id, conversationId, createdAt }
{ schemaVersion, entity: "notification", id, createdAt }
```

Dopo subscribe, reconnect o evento, il client rilegge il database e unisce per
UUID. Broadcast Replay non e una garanzia di consegna e non viene usato come
recupero. Logout e cambio utente rimuovono tutti i canali, svuotano cache e
cursori e rendono innocui i callback della sessione precedente.

## Verifiche e gate

Checkpoint 8a:

- migrazione ricostruibile da zero;
- verificatore statico di schema, privilegi, RLS, trigger e indici;
- griglia sequenziale per isolamento, idempotenza, rate limit, pagination,
  notifiche e cleanup;
- prove concorrenti separate per apertura, invio, cursore e deduplicazione.

Checkpoint 8b:

- test dei contratti e dei mapping mock/Supabase;
- test delle rotte, stati UI, badge e retry con la stessa chiave;
- lint, typecheck, test e build di `frontend-next/`.

Checkpoint 8c:

- isolamento topic conversazione e notifiche;
- payload chiusi e canali sempre privati;
- deduplicazione, catch-up e teardown su reconnect/logout/cambio utente;
- verifica completa locale e soglia CI alzata al numero reale di test passati.

SQL remoto, anche senza fixture, richiede revisione del testo esatto e una
nuova approvazione nella sessione di esecuzione. Una griglia che crea o cancella
fixture richiede una seconda approvazione distinta. Dashboard Realtime, deploy,
push, PR, ready-for-review e merge sono gate separati.
