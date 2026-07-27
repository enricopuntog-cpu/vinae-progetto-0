# Architettura di Vinea

## Obiettivo

La pre-release mantiene l’interfaccia React/TanStack già validata, ma separa le
responsabilità sensibili dal browser. Il backend applica autenticazione,
autorizzazione, limiti d’uso e regole di pagamento; il frontend non è una fonte
attendibile per identità, ruoli, prezzi o stato di un ordine.

## Componenti

```text
Browser
  └─ Frontend React/TanStack
       ├─ UI e routing
       ├─ store per dominio
       └─ client API
             │ HTTPS /api
             ▼
FastAPI
  ├─ autenticazione e ruoli
  ├─ rate limiting
  ├─ pagamenti e webhook
  ├─ servizi AI
  └─ repository asincroni
             │
             ├─ Database
             ├─ Stripe
             └─ Provider AI configurabile
```

## Confini di fiducia

- Il browser può richiedere operazioni, ma non assegnarsi ruoli o confermare un
  pagamento.
- L’identità viene risolta lato server tramite un’interfaccia indipendente dal
  provider di autenticazione.
- Gli endpoint verificano ruolo e proprietà della risorsa prima di leggere o
  modificare dati privati.
- Prezzo, valuta, ordine e proprietario usati dal pagamento devono provenire dal
  server.
- Il solo stato `complete` di una Checkout Session non prova l’incasso: lo stato
  affidabile deriva da `payment_status=paid` e da webhook Stripe firmati.

## Backend modulare

Il backend usa dipendenze esplicite tra questi livelli:

1. **Router HTTP** — valida input e traduce errori in risposte non sensibili.
2. **Servizi di dominio** — applicano regole di pagamento, AI e ownership.
3. **Adapter** — isolano provider di autenticazione, Stripe, AI e database.
4. **Repository asincroni** — evitano I/O bloccante nell’event loop.

Questo permette di sostituire provider e usare adapter in memoria nei test senza
rete o credenziali.

## Pagamenti

Il flusso previsto è:

1. l’utente autenticato richiede un checkout;
2. il server verifica identità, namespace del catalogo demo, prezzo una tantum e
   redirect ammesso;
3. crea la sessione con chiave di idempotenza;
4. registra lo stato iniziale;
5. Stripe invia un webhook firmato;
6. il server deduplica l’evento e aggiorna lo stato solo da segnali affidabili;
7. la lettura dello stato è consentita solo al proprietario o a un amministratore.

In questa pre-release Stripe addebita soltanto il prezzo una tantum del catalogo
server. Spedizione e protezione restano valori UX dimostrativi e sono marcati
come non addebitati. Il prodotto definitivo dovrà ottenere dal server un
preventivo completo e persistito prima di aprire il checkout.

La pre-release non implementa ancora l’intero flusso marketplace Stripe Connect.
Prima di ricevere denaro reale per conto di venditori servono progettazione
contabile, onboarding/KYC, rimborsi, contestazioni, controllo atomico di
annuncio/stock/ownership e verifica legale.

## Intelligenza artificiale

Gli endpoint AI dipendono da un contratto interno, non da un SDK di piattaforma.
Il provider e il modello sono configurabili. I test usano un provider finto.

Le risposte automatiche sono suggerimenti, non certificazioni di autenticità,
valore economico o sicurezza alimentare. Errori tecnici e dettagli del provider
non vengono inoltrati al client.

## Storico Sommelier

Ogni conversazione appartiene a un utente autenticato. Il repository applica:

- controllo di ownership;
- numero massimo di messaggi mantenuti;
- scadenza TTL;
- limite alla lunghezza dei contenuti;
- eliminazione esplicita da parte del proprietario.

## Frontend

Lo stato è suddiviso per dominio, con tipi espliciti per pagamenti, ordini e
amministrazione. Le API e gli adapter sono il punto di accesso alle operazioni
server-side.

La cantina 3D è un miglioramento progressivo: viene caricata solo quando richiesta,
solo nel browser, e mantiene un fallback non 3D per dispositivi incompatibili.

## Decisioni future

Prima del rilascio pubblico vanno ancora scelte e documentate:

- database e hosting di produzione;
- provider definitivo di autenticazione;
- provider AI e budget;
- osservabilità e gestione degli incidenti;
- strategia di backup e ripristino;
- Stripe Connect o alternativa compatibile con il modello legale;
- policy di conservazione dei dati e moderazione.
