# Configurazione degli ambienti

## Regole generali

- Copiare gli esempi locali, senza modificarli con valori reali nel repository.
- Non versionare mai `.env`, token, chiavi private o segreti webhook.
- Usare ambienti e credenziali separati per sviluppo, staging e produzione.
- In produzione usare solo HTTPS e origini esplicite.
- Dopo l’aggiunta di una variabile aggiornare anche questo documento.

## Frontend

File di esempio: `frontend/.env.example`.

| Variabile | Obbligatoria | Descrizione |
|---|---:|---|
| `VITE_API_BASE_URL` | No | Base URL del backend. Vuota usa lo stesso origin; in locale può essere `http://localhost:8001`. |

Tutte le variabili `VITE_*` vengono incluse nel bundle client: non devono mai
contenere segreti.

Esempio locale:

```env
VITE_API_BASE_URL=http://localhost:8001
```

Se frontend e API sono esposti dallo stesso dominio o da un reverse proxy, lasciare
il valore vuoto è la scelta consigliata.

## Stack di destinazione (`frontend-next/` + Supabase)

File di esempio: `frontend-next/.env.example`. `PAYMENTS_ENABLED=false` è il
default obbligatorio finché migrazione, Edge Function, endpoint webhook e
configurazione Stripe di test non sono stati verificati nell'ambiente scelto.

| Variabile | Destinazione | Descrizione |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | client/server | URL progetto Supabase. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | client/server | Chiave publishable/anon soggetta a RLS. |
| `SUPABASE_SERVICE_ROLE_KEY` | solo server | Bypassa RLS; mai nel browser o nei log. |
| `PAYMENTS_ENABLED` | solo server | Kill switch del checkout e del webhook. |
| `NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED` | client | Visibilità UI soltanto; non autorizza operazioni. |
| `PAYMENT_ALLOWED_ORIGINS` | Edge Function | Allowlist CORS esatta, separata da virgole. |
| `PAYMENT_REDIRECT_ALLOWED_ORIGINS` | Edge Function | Allowlist server-side dei ritorni Stripe. |
| `PAYMENT_REDIRECT_ORIGIN` | Edge Function | Origin scelta dal server, appartenente all'allowlist. |
| `STRIPE_SECRET_KEY` | Edge Function | Chiave segreta Stripe dell'ambiente. |
| `STRIPE_WEBHOOK_SECRET` | Route Handler | Segreto firma dell'endpoint webhook. |
| `PAYMENTS_WEBHOOK_RATE_LIMIT` | Route Handler | Limite per bucket, default `600`. |
| `PAYMENTS_WEBHOOK_RATE_WINDOW_SECONDS` | Route Handler | Finestra del bucket, default `60`. |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | client | Chiave publishable del Payment Element. Solo `pk_test_…` fuori produzione. |
| `CONNECT_ACCOUNT_COUNTRY` | Edge Function | Paese degli account Connect Express aperti per i venditori. Default `IT`. |
| `PAYOUTS_JOB_TOKEN` | Edge Function | Secondo fattore di `payouts-release`. Indipendente dalla service role key e revocabile da solo. |
| `PAYOUTS_BATCH_LIMIT` | Edge Function | Ordini rilasciati per esecuzione, default `50`, massimo `500`. |
| `PACKAGING_ENABLED` | solo server | Gate della selezione imballaggio (Fase 7c). Indipendente da `PAYMENTS_ENABLED`. |
| `NEXT_PUBLIC_PACKAGING_ENABLED` | client | Visibilità UI dell'imballaggio soltanto; non autorizza operazioni. |

I segreti della Edge Function vanno impostati nell'ambiente Supabase; quelli del
Route Handler nell'ambiente server Next.js. Non copiare la `service_role` in un
file `.env` versionato.

`PACKAGING_ENABLED` è **scollegata** da `PAYMENTS_ENABLED`, ed è un requisito
della Fase 7c e non una svista: l'imballaggio deve poter restare visibile con i
pagamenti spenti, e i pagamenti devono poter essere accesi senza che
l'imballaggio compaia. In Fase 7c il fornitore di imballaggio è **finto** —
nessuna chiamata esterna, nessun endpoint, nessuna credenziale — quindi non
esiste alcuna variabile con un URL o un segreto di fornitore, e la sua comparsa
in futuro sarà il segnale che il provider ha smesso di essere finto.

Con `PACKAGING_ENABLED=true` e `PAYMENTS_ENABLED=false` un ordine nasce con
`addebito_totale_cents` più alto di `totale_cents` e nessun addebito reale
dietro. È coerente, perché nessun addebito reale esiste comunque, ma è uno stato
da conoscere in anticipo.

`PAYMENTS_ENABLED` è il kill switch di **tutta** la verticale pagamenti, non del
solo checkout: `payments-checkout`, `connect-onboarding`, `payouts-release` e il
Route Handler del webhook lo controllano ognuno per conto proprio e rispondono
`503` quando non è `true`. L'onboarding vi rientra perché apre account veri
presso il fornitore, anche in test mode.

`PAYOUTS_JOB_TOKEN` è separato dalla service role key di proposito: lo scheduler
ha bisogno di entrambe, ma comprometterne una sola non basta a far partire un
rilascio, e ruotare il token non costringe a ruotare la chiave che dà accesso
all'intero database.

## Backend

File di esempio: `backend/.env.example`.

### Runtime e database

| Variabile | Default esempio | Descrizione |
|---|---|---|
| `APP_ENV` | `development` | Ambiente: usare `production` per attivare le validazioni più rigide. |
| `MONGO_URL` | `mongodb://localhost:27017` | URI del database MongoDB. In produzione deve provenire dal secret manager. |
| `DB_NAME` | `vinea_demo` | Nome del database. Usare nomi separati per ambiente. |

Il backend usa Motor e repository asincroni. All’avvio crea gli indici necessari,
inclusi TTL per storico Sommelier e rate limiting.

### CORS

| Variabile | Esempio | Descrizione |
|---|---|---|
| `CORS_ALLOWED_ORIGINS` | `http://localhost:3000,http://localhost:5173` | Lista di origin complete, separate da virgola. |

`*` è rifiutato in produzione. Ogni valore deve contenere solo schema, host ed
eventuale porta, senza percorso. HTTP è ammesso soltanto per host locali quando
`ALLOW_HTTP_LOCAL_REDIRECTS=true`.

### Stripe e redirect

| Variabile | Obbligatoria in produzione | Descrizione |
|---|---:|---|
| `PAYMENT_REDIRECT_ALLOWED_ORIGINS` | Sì | Allowlist delle origin che possono ricevere il ritorno da Stripe. |
| `PAYMENT_REDIRECT_ORIGIN` | Sì | Origin scelta dal server; deve appartenere all’allowlist. |
| `ALLOW_HTTP_LOCAL_REDIRECTS` | No | `true` solo per sviluppo locale; impostare `false` negli ambienti condivisi. |
| `STRIPE_SECRET_KEY` | Sì | Chiave segreta Stripe. Usare `sk_test_…` fuori produzione. |
| `STRIPE_WEBHOOK_SECRET` | Sì | Segreto firma del webhook, specifico dell’endpoint e dell’ambiente. |
| `STRIPE_MODE` | Sì | Etichetta operativa (`test` o `live`) esposta dall’health check. |

Esempio locale:

```env
PAYMENT_REDIRECT_ALLOWED_ORIGINS=http://localhost:3000
PAYMENT_REDIRECT_ORIGIN=http://localhost:3000
ALLOW_HTTP_LOCAL_REDIRECTS=true
STRIPE_SECRET_KEY=sk_test_replace_me
STRIPE_WEBHOOK_SECRET=whsec_replace_me
STRIPE_MODE=test
```

Il client non sceglie l’origin finale. Non inserire URL di preview temporanee.

### Autenticazione

| Variabile | Obbligatoria | Descrizione |
|---|---:|---|
| `AUTH_JWT_ALGORITHM` | Sì | Algoritmo JWT consentito, per esempio `HS256` o `RS256`. |
| `AUTH_JWT_SIGNING_KEY` | Sì in produzione | Segreto HMAC o chiave pubblica PEM usata per verificare il token. |
| `AUTH_JWT_ISSUER` | Consigliata | Issuer atteso (`iss`). |
| `AUTH_JWT_AUDIENCE` | Consigliata | Audience attesa (`aud`). |
| `AUTH_ROLES_CLAIM` | Sì | Nome del claim contenente i ruoli, default `roles`. |

Con algoritmi HMAC, la chiave di produzione deve avere almeno 32 byte. Per un
provider esterno è preferibile verificare firme asimmetriche e impostare sempre
issuer e audience. Il token deve includere almeno `sub` ed `exp`.

L’interfaccia `TokenVerifier` è indipendente dal provider. Il verifier JWT incluso
è una base sostituibile: prima della produzione deve essere configurato e provato
con il provider di identità scelto.

### Provider AI

| Variabile | Default | Descrizione |
|---|---|---|
| `AI_PROVIDER` | `disabled` | `disabled` oppure `openai`. |
| `OPENAI_API_KEY` | vuota | Richiesta solo con `AI_PROVIDER=openai`. |
| `OPENAI_MODEL` | `gpt-4.1-mini` | Modello configurabile senza cambiare il dominio. |
| `AI_TIMEOUT_SECONDS` | `30` | Timeout massimo per una richiesta al provider. |
| `AI_MAX_OUTPUT_TOKENS` | `800` | Limite massimo dell’output richiesto al provider. |

Con `AI_PROVIDER=disabled` gli endpoint restano protetti e restituiscono un errore
controllato; la suite automatica usa un provider fake iniettato.

### Storico Sommelier

| Variabile | Default | Descrizione |
|---|---:|---|
| `SOMMELIER_HISTORY_TTL_DAYS` | `30` | Giorni prima della scadenza automatica. |
| `SOMMELIER_MAX_MESSAGES` | `100` | Numero massimo di messaggi conservati per conversazione. |
| `SOMMELIER_CONTEXT_MESSAGES` | `12` | Messaggi recenti inviati al provider AI. |
| `SOMMELIER_MAX_RESPONSE_CHARS` | `8000` | Limite massimo dei caratteri trasmessi e salvati per risposta. |

Il valore del contesto non può superare il limite massimo. Tutti i valori devono
essere maggiori di zero.

### Rate limiting

| Variabile | Default | Descrizione |
|---|---:|---|
| `PAYMENTS_RATE_LIMIT` | `20` | Richieste pagamento per finestra. |
| `PAYMENTS_RATE_WINDOW_SECONDS` | `60` | Durata finestra pagamenti. |
| `WEBHOOK_RATE_LIMIT` | `600` | Richieste webhook per finestra. |
| `WEBHOOK_RATE_WINDOW_SECONDS` | `60` | Durata finestra webhook. |
| `AI_RATE_LIMIT` | `20` | Richieste AI per finestra. |
| `AI_RATE_WINDOW_SECONDS` | `60` | Durata finestra AI. |

In esecuzione normale il limiter MongoDB è condiviso tra istanze e usa bucket con
TTL. Nei test viene iniettato un limiter in memoria.

## Configurazione minima di produzione

Esempio illustrativo; i valori reali devono provenire da un secret manager:

```env
APP_ENV=production
MONGO_URL=mongodb+srv://REDACTED
DB_NAME=vinea_production

CORS_ALLOWED_ORIGINS=https://app.example.it
PAYMENT_REDIRECT_ALLOWED_ORIGINS=https://app.example.it
PAYMENT_REDIRECT_ORIGIN=https://app.example.it
ALLOW_HTTP_LOCAL_REDIRECTS=false

STRIPE_SECRET_KEY=REDACTED
STRIPE_WEBHOOK_SECRET=REDACTED
STRIPE_MODE=live

AUTH_JWT_ALGORITHM=RS256
AUTH_JWT_SIGNING_KEY=REDACTED_PUBLIC_KEY
AUTH_JWT_ISSUER=https://identity.example.it/
AUTH_JWT_AUDIENCE=vinea-api
AUTH_ROLES_CLAIM=roles

AI_PROVIDER=disabled
```

Questo esempio non rende l’applicazione production-ready: restano necessarie le
verifiche elencate in `PRE_RELEASE_AUDIT_RESOLVED.md`.
