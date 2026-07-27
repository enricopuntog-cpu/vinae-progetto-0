# Audit pre-release — Vinea Emergent

Data audit: 26 luglio 2026.

## Verifiche superate

- Frontend sorgente completo: 117 file in `src`, 16.233 righe TypeScript/TSX.
- Backend: 956 righe Python; compilazione sintattica Python superata.
- Parsing sintattico di 104 file TypeScript/TSX superato senza errori.
- Build Emergent compilata avviata come worker SSR: 23/23 route principali rispondono HTTP 200; route inesistente risponde 404.
- Contract test backend con servizi esterni simulati: 13/13 controlli superati per health, checkout, stato pagamento, webhook, pairing, listing AI, Sommelier SSE, storico e reset.
- Nessun `.env`, chiave Stripe o chiave AI reale incluso nel repository assemblato.

## Bloccanti prima della versione ufficiale

### 1. Pagamenti: stato `complete` trattato come pagamento riuscito

In `backend/server.py`, `get_status()` marca la transazione come pagata quando:

```python
s.payment_status == "paid" or s.status == "complete"
```

Una Checkout Session può essere `complete` mentre un metodo di pagamento asincrono non è ancora `paid`. La condizione deve basarsi sul pagamento effettivo e sugli eventi webhook affidabili.

### 2. Nessuna autenticazione o autorizzazione reale

Ruoli, admin, profilo, ordini, messaggi e moderazione sono controllati lato client. Gli endpoint di pagamento e AI non verificano identità o ownership. Prima del rilascio servono autenticazione server-side, RBAC e policy sui dati.

### 3. CORS completamente aperto

`allow_origins=["*"]` deve essere sostituito con un elenco di domini consentiti configurato da ambiente.

### 4. `origin_url` controllato dal client

Il backend usa `origin_url` ricevuto dal browser per costruire `success_url` e `cancel_url` Stripe. Va validato contro una allowlist per evitare redirect verso domini arbitrari.

### 5. Dipendenza non portabile da Emergent

Il backend dipende da `emergentintegrations` e dal modello configurato come `openai/gpt-5.4`. Per una piattaforma ufficiale va definito un adapter AI portabile, con provider e modello configurabili, retry, timeout, rate limit e monitoraggio costi.

## Priorità alta

- Rendere obbligatorio e non vuoto `STRIPE_WEBHOOK_SECRET` in produzione.
- Non restituire al client le eccezioni interne del provider AI nello stream SSE.
- Aggiungere rate limiting e quote agli endpoint AI e checkout.
- Limitare e archiviare lo storico chat: attualmente il documento Mongo cresce senza limite.
- Rendere asincrono l'accesso Mongo oppure usare un driver async; `pymongo` sincrono blocca l'event loop FastAPI.
- Validare `session_id` anche sugli endpoint GET/DELETE dello storico.
- Imporre esattamente tre risultati validi nella risposta pairing oppure gestire esplicitamente meno risultati nel frontend.
- Correggere `<html lang="en">` in `frontend/src/routes/__root.tsx` a `it`.
- Rimuovere il preload hardcoded `/__l5e/.../vinea-cellar.jpg`, specifico dell'ambiente Lovable/Emergent, e includere l'immagine nel repository o in uno storage ufficiale.
- Rimuovere `LOVABLE_PREVIEW_HOST` hardcoded dallo script `start`.
- Configurare proxy locale `/api` oppure una variabile `VITE_API_BASE_URL`.

## Debito tecnico

- `src/lib/vinea-store.tsx` è monolitico e gestisce molti domini differenti.
- Diverse pagine superano 400–600 righe e contengono business logic.
- Sono presenti numerosi `any`/`as any` nei flussi checkout, ordine, moderazione e navigazione.
- Le pagine importano direttamente dati mock, nonostante la documentazione indichi lo store come livello di accesso.
- Mancano test frontend versionati e una pipeline CI ripetibile.
- Sono presenti due lockfile (`bun.lock` e `yarn.lock`) senza un `packageManager` dichiarato.
- Il README interno del frontend è precedente alle integrazioni Emergent e descrive ancora pagamenti/AI come totalmente simulati.
- La build predefinita è orientata a Cloudflare tramite configurazione Lovable: va scelta esplicitamente la piattaforma di deploy ufficiale.

## Sequenza consigliata

1. Correzioni sicurezza pagamenti e configurazione ambiente.
2. Autenticazione, ruoli e ownership server-side.
3. Refactor backend in router/service/repository e Mongo async.
4. Adapter AI indipendente da Emergent con rate limit.
5. Refactor store frontend e rimozione `any` critici.
6. Test unitari + integrazione + Playwright e GitHub Actions.
7. Decisione infrastrutturale: deployment, database, storage, email, logging e monitoring.
8. Solo dopo: sviluppo della versione ufficiale e dati reali.
