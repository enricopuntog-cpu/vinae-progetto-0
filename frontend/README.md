# Vinea — Wine Club

Frontend responsive del marketplace sociale Vinea. L'applicazione usa TanStack
Start, React 19, TypeScript e Tailwind CSS. Il backend FastAPI vive nella
cartella `backend/` del repository principale.

## Requisiti

- Bun 1.3.14
- backend Vinea avviato, oppure un reverse proxy che esponga `/api` sullo
  stesso dominio del frontend

Il progetto usa esclusivamente Bun. `bun.lock` è il lockfile ufficiale e non
devono essere aggiunti lockfile di altri package manager.

## Configurazione

Copia `.env.example` in `.env.local` e imposta, solo se frontend e backend
usano origini diverse:

```dotenv
VITE_API_BASE_URL=http://localhost:8001
```

Lasciando la variabile vuota, tutte le chiamate usano `/api` sulla stessa
origine. Non inserire token o segreti nelle variabili `VITE_*`: sono pubbliche
nel bundle browser.

Il client HTTP in `src/services/api-client.ts` supporta un provider di access
token iniettabile tramite `configureAccessTokenProvider`. L'integrazione con il
provider di identità deve fornire il token in memoria; non sono previsti token
hardcoded o letti da variabili pubbliche.

## Comandi

```bash
bun install --frozen-lockfile
bun run dev
bun run lint
bun run typecheck
bun run test
bun run build
bun run start
```

La build SSR viene prodotta in `.output/`.

## Struttura

```text
src/
  components/          componenti UI e di dominio
  config/              brand, rotte, navigazione e label
  data/                tipi e seed dimostrativi
  lib/
    store/             moduli di dominio cantina e ordini/proposte
    vinea-store.tsx    provider compatibile che compone i moduli
    wine-images.ts     asset locali versionati
  routes/              route TanStack Start
  services/
    api-client.ts      client HTTP, base URL e bearer token provider
    api-contracts.ts   validazione Zod delle risposte backend
  test/                configurazione test
```

## Pagamenti e API

- Il browser non decide mai se un pagamento è riuscito.
- La pagina di conferma accetta soltanto lo stato restituito dal backend.
- `order_id` deve provenire dal server ed è obbligatorio nei contratti Zod.
- Il checkout usa un header `Idempotency-Key`.
- L'URL di ritorno non viene inviato dal browser: il backend lo sceglie da una
  allowlist configurata.
- Le richieste private includono credenziali e, quando configurato, un bearer
  token ottenuto dal provider di identità.

## Cantina 3D

La vista 3D è browser-only e il chunk Three.js viene caricato tramite
`React.lazy` soltanto dopo che l'utente seleziona esplicitamente la modalità
3D. Griglia ed elenco rimangono disponibili come fallback.

## Test

Il test runner nativo di Bun, Testing Library e happy-dom coprono:

- composizione URL, credenziali e bearer token del client API;
- idempotency header e serializzazione JSON;
- contratti checkout, stato pagamento e storico Sommelier;
- regole principali del dominio cantina;
- creazione ordini e prevenzione di proposte duplicate.

Le prove che richiedono credenziali reali Stripe o un provider AI vengono
eseguite nel backend con servizi simulati; non devono usare segreti nel
frontend.

## Stato della migrazione

La UI mantiene ancora alcuni dati dimostrativi per consentire la navigazione
completa. Pagamenti e funzioni AI comunicano invece con le API configurate e
validano le risposte a runtime. La persistenza completa di catalogo, cantina,
club e moderazione resta responsabilità dei servizi backend.
