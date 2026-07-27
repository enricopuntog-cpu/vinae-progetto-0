# Risoluzione dell’audit pre-release

Data revisione: 27 luglio 2026.

Documento di origine: [`PRE_RELEASE_AUDIT.md`](PRE_RELEASE_AUDIT.md).

## Valutazione

I 16 interventi richiesti hanno una risoluzione applicativa locale oppure un
limite residuo dichiarato e verificabile. Dove il controllo definitivo richiede
servizi esterni, lo stato è esplicitamente “verifica esterna richiesta”: non è
stato simulato come superato.

La base è pronta per essere revisionata e pubblicata su una branch GitHub, ma non
è ancora production-ready. Gli esiti completi sono in
[`TEST_REPORT.md`](TEST_REPORT.md).

## Stato sintetico

| # | Area | Stato | Evidenza |
|---|---|---|---|
| 1 | Stripe, webhook e stato reale | Risolto localmente; sandbox richiesta | `backend/stripe_service.py`, `backend/server.py`, test Stripe |
| 2 | Allowlist redirect | Risolto | `backend/config.py`, `backend/stripe_service.py`, test redirect |
| 3 | CORS da ambiente | Risolto | `backend/config.py`, `backend/server.py` |
| 4 | Auth, ruoli e autorizzazioni | Risolto localmente; provider reale richiesto | `backend/auth.py`, test auth/ownership |
| 5 | Rate limiting Stripe e AI | Risolto localmente; Mongo distribuito da validare | `backend/rate_limit.py`, middleware applicativo, test |
| 6 | Provider AI astratto | Risolto nello scope; provider/costi reali da validare | `backend/ai_provider.py`, provider fake nei test |
| 7 | Database non bloccante | Risolto | `backend/database.py`, `backend/repositories.py` |
| 8 | Storico Sommelier limitato, TTL e ownership | Risolto localmente; TTL Mongo da validare | repository, route AI e test |
| 9 | Residui Lovable/Emergent | Risolto | scan runtime e lockfile |
| 10 | HTML `lang="it"` | Risolto | root HTML e pagina errore |
| 11 | Bun unico package manager | Risolto | `packageManager`, `bun.lock`, assenza `yarn.lock` |
| 12 | Store e `any` critici | Risolto per lo scope prioritario | moduli dominio e tipi API |
| 13 | Lazy loading cantina 3D | Risolto | import dinamico browser-only e bundle SSR |
| 14 | Documentazione | Risolto | README e documenti `docs/` |
| 15 | Test frontend e backend | Risolto localmente; integrazioni reali richieste | 11 frontend + 35 backend |
| 16 | GitHub Actions | Workflow risolto; prima esecuzione richiesta | `.github/workflows/ci.yml` |

## 1. Stripe, webhook e stato reale del pagamento

Il backend non tratta più `session.status=complete` come prova di incasso.
L’avvenuto pagamento dipende da `payment_status=paid` e dagli eventi Stripe
firmati.

Sono presenti:

- verifica firma sul corpo raw;
- `STRIPE_WEBHOOK_SECRET` obbligatorio in produzione;
- deduplicazione degli eventi;
- lease recuperabile per eventi rimasti in elaborazione dopo un arresto;
- idempotenza nella creazione del checkout;
- errori provider convertiti in risposte non sensibili;
- ownership sulla lettura dello stato;
- distinzione tra rimborsi parziali e totali;
- chiamate SDK sincrone isolate con `asyncio.to_thread`.

Il checkout Stripe della pre-release addebita soltanto il prezzo una tantum
configurato nel catalogo server. La UI non presenta più spedizione o protezione
simulate come parte dell’importo Stripe: il totale effettivo è mostrato dal
provider prima della conferma.

I test locali coprono sessione completa ma non pagata, sessione pagata, firma
invalida, webhook duplicato e recupero di un evento rimasto in elaborazione oltre
la sua lease.

**Resta:** prova Stripe sandbox/CLI, preventivo server-side di spedizione e
protezione, metodi asincroni reali, rimborsi, riconciliazione e progettazione
Stripe Connect.

## 2. Allowlist dei redirect

Il client non fornisce più liberamente l’origin finale. Il server usa
`PAYMENT_REDIRECT_ORIGIN`, che deve appartenere a
`PAYMENT_REDIRECT_ALLOWED_ORIGINS`.

La validazione confronta origin normalizzate e rifiuta schema, host, porta,
credenziali URL o percorso non ammessi. HTTP è consentito solo per host locali
esplicitamente abilitati.

## 3. CORS configurabile

`CORS_ALLOWED_ORIGINS` definisce una lista esplicita. In produzione il wildcard è
rifiutato dalla validazione della configurazione. Metodi e header ammessi sono
limitati alle necessità dell’API.

## 4. Autenticazione, ruoli e autorizzazioni

`TokenVerifier` separa le regole di dominio dal provider. `JwtTokenVerifier`
verifica firma, algoritmo, `sub`, scadenza e, se configurati, issuer e audience.

Le route private ricevono un `AuthenticatedUser` verificato e applicano ownership
o ruolo `admin`; `user_id` e ruoli inviati dal browser non sono considerati fonte
attendibile.

**Resta:** collegare e provare il provider reale, inclusi chiavi/JWKS, rotazione,
revoca e mapping dei ruoli.

## 5. Rate limiting

Checkout, stato pagamenti, webhook e AI hanno limiti e finestre separati,
configurabili da ambiente.

- `InMemoryRateLimiter` rende deterministici i test.
- `MongoRateLimiter` offre bucket condivisi e TTL per più istanze.
- Le risposte limitate includono HTTP 429 e `Retry-After`.

**Resta:** validare concorrenza e comportamento distribuito su MongoDB di staging.

## 6. Provider AI indipendente

Il backend dipende dal contratto `AIProvider`. Sono disponibili:

- adapter OpenAI asincrono;
- provider disabilitato per ambienti senza AI;
- provider fake iniettato nei test;
- provider e modello configurabili;
- timeout, retry e limite massimo dell’output configurati;
- errori sanitizzati.

Non è presente alcuna dipendenza da SDK Emergent.

**Resta:** prova controllata con provider reale, budget, raccolta dell’utilizzo e
dei costi, monitoraggio e valutazione delle risposte.

## 7. Database non bloccante

MongoDB usa Motor e repository asincroni. Le route non eseguono più chiamate
`pymongo` sincrone nell’event loop. I test iniettano repository in memoria e non
richiedono un database.

## 8. Storico Sommelier

Lo storico:

- appartiene all’utente autenticato;
- limita messaggi conservati e contesto;
- assegna una scadenza TTL;
- impedisce lettura o cancellazione da parte di altri utenti;
- consente eliminazione esplicita;
- non inoltra eccezioni interne nello stream SSE.

**Resta:** verificare creazione indice e scadenza TTL su MongoDB di staging.

## 9. Rimozione delle dipendenze precedenti

Sono stati rimossi:

- pacchetti e configurazione Lovable;
- host preview hardcoded;
- telemetria Lovable;
- asset `/__l5e`;
- SDK e configurazione Emergent;
- riferimenti runtime e metadata Stripe Emergent.

La scansione del codice e del lockfile runtime non trova `Lovable`, `Emergent` o
`/__l5e`. I riferimenti presenti nei documenti storici descrivono soltanto la
provenienza dell’audit.

## 10. Lingua HTML

Il documento principale e la pagina di errore dichiarano `lang="it"`.

## 11. Bun unico package manager

- `frontend/package.json` dichiara `bun@1.3.14`;
- `bun.lock` è stato rigenerato dal registry npm pubblico;
- `yarn.lock` è stato eliminato;
- installazione locale e CI usano `--frozen-lockfile`.

## 12. Refactoring prioritario dello store e tipi

I domini più critici sono estratti in:

- `frontend/src/lib/store/order-domain.ts`;
- `frontend/src/lib/store/cellar-domain.ts`;
- `frontend/src/services/api-contracts.ts`;
- `frontend/src/services/api-client.ts`.

Pagamento, ordine e amministrazione non contengono `any`/`as any` manuali. I cast
residui appartengono esclusivamente al file route tree generato automaticamente.

Il vecchio store mantiene ancora responsabilità demo non critiche: la sua
ulteriore divisione resta debito tecnico, non un blocco di questo hardening.

## 13. Cantina 3D lazy

La cantina 3D usa import dinamico, `Suspense` e guard SSR. Il chunk viene scaricato
solo all’apertura della vista 3D ed è assente dal bundle SSR.

Dimensione misurata del chunk client:

- 1.020,89 kB;
- 283,62 kB gzip.

Il lazy loading risolve l’impatto sul caricamento iniziale; il peso del chunk resta
da ottimizzare per dispositivi meno potenti.

## 14. Documentazione

Sono stati aggiornati o creati:

- `README.md`;
- `docs/ARCHITECTURE.md`;
- `docs/DEVELOPMENT.md`;
- `docs/ENVIRONMENT.md`;
- `docs/SECURITY.md`;
- `docs/PRE_RELEASE_AUDIT_RESOLVED.md`;
- `docs/TEST_REPORT.md`;
- esempi ambiente frontend e backend.

## 15. Test automatici

Esiti locali:

- installazione Bun congelata: superata;
- lint frontend: superato con 14 warning non bloccanti;
- typecheck: superato;
- test frontend: 11/11;
- build produzione: superata;
- smoke SSR: 8 route HTTP 200;
- compileall backend: superato;
- Ruff backend: superato;
- test backend: 35/35 in 0,59 s.

Stripe reale, provider AI reale e MongoDB reale non sono stati usati; le relative
prove sono elencate in `TEST_REPORT.md`.

## 16. GitHub Actions

`.github/workflows/ci.yml` esegue su pull request e push a `main`:

- Bun 1.3.14 con cache;
- installazione frozen;
- lint, typecheck, test e build frontend;
- Python 3.12 con cache pip;
- compileall, Ruff e pytest backend;
- nessun segreto;
- permessi `contents: read`;
- cancellazione delle esecuzioni CI superate.

**Resta:** la prima esecuzione effettiva sarà disponibile solo dopo il push della
branch su GitHub.

## Rischi residui prima della produzione

1. Provider di autenticazione reale e ciclo di vita delle chiavi.
2. MongoDB di produzione: indici TTL, limiter distribuito, backup e restore.
3. Stripe sandbox completo e architettura Stripe Connect.
4. Provider AI reale, costi, qualità e monitoraggio.
5. Osservabilità, alert, audit log e gestione centralizzata dei segreti.
6. Test end-to-end browser più ampi.
7. Revisione legale su marketplace, alcolici, età, privacy, pagamenti e logistica.

Questi rischi impediscono di definire la versione “production-ready”, ma non
impediscono la pubblicazione del codice hardenizzato su una branch di sviluppo.
