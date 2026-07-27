# Rapporto dei test

Data: 27 luglio 2026.

## Esito complessivo

I controlli locali disponibili sono stati completati con esito positivo. La suite
automatica non usa rete, database esterno, Stripe reale o credenziali AI.

Questo risultato qualifica il codice per revisione e pubblicazione su una branch
GitHub; non certifica l’idoneità alla produzione o a transazioni reali.

## Matrice

| Area | Comando o verifica | Esito | Dettaglio |
|---|---|---|---|
| Frontend | `bun install --frozen-lockfile` | Superato | 496 installazioni, 608 pacchetti; `bun.lock` rispettato |
| Frontend | `bun run lint` | Superato | Exit code 0; 14 warning Fast Refresh non bloccanti |
| Frontend | `bun run typecheck` | Superato | TypeScript strict, nessun errore |
| Frontend | `bun run test` | Superato | 11/11 test, 4 file |
| Frontend | `bun run build` | Superato | Build produzione Vite 8.1.5 |
| Frontend SSR | smoke test route | Superato | 8 route selezionate hanno risposto HTTP 200 |
| Backend | `python -m compileall -q .` | Superato | Sorgenti compilati sintatticamente |
| Backend | `python -m ruff check .` | Superato | Nessuna violazione bloccante |
| Backend | `python -m pytest -q` | Superato | 35/35 test in 0,59 s |
| Repository | scan residui runtime | Superato | Nessun Lovable, Emergent o `/__l5e` nel codice/lock runtime |
| Repository | package manager | Superato | Bun 1.3.14; `yarn.lock` assente |
| Repository | HTML | Superato | documento e pagina errore con `lang="it"` |
| CI | esecuzione GitHub Actions | Non eseguito | Disponibile solo dopo il push della branch |

## Frontend

### Test automatici

La suite Bun copre:

- contratti e parsing delle risposte API;
- client API e propagazione del token;
- dominio ordini e transizioni tipizzate;
- dominio cantina.

I test sono in:

- `frontend/src/services/api-client.test.ts`;
- `frontend/src/services/api-contracts.test.ts`;
- `frontend/src/lib/store/order-domain.test.ts`;
- `frontend/src/lib/store/cellar-domain.test.ts`.

### Lint

Il lint termina con exit code 0. Rimangono 14 warning
`react-refresh/only-export-components` in componenti che esportano anche helper o
costanti. Non impediscono build o runtime; possono essere ridotti in un refactor
successivo separando tali export.

### Build e cantina 3D

La build di produzione è completata con Vite 8.1.5.

Il chunk client della cantina 3D misura:

- 1.020,89 kB non compresso;
- 283,62 kB gzip.

È caricato lazy soltanto quando richiesto ed è completamente assente dal bundle
SSR. Il peso resta un elemento da monitorare sui dispositivi meno potenti.

### Smoke SSR

Otto route rappresentative sono state avviate dalla build SSR e hanno risposto
HTTP 200. Questo controllo verifica bootstrap e rendering; non sostituisce una
suite end-to-end completa in browser.

## Backend

I 35 test locali coprono, con adapter in memoria/fake:

- health check;
- token JWT valido, mancante o non valido;
- ruoli e ownership;
- CORS e validazione configurazione;
- redirect consentito o rifiutato;
- creazione checkout e idempotenza;
- stato `complete` non equivalente a pagamento;
- stato realmente `paid`;
- webhook firmato, non valido, duplicato e recupero dopo lease scaduta;
- distinzione tra rimborso parziale e totale;
- rate limiting;
- provider AI fake ed errori sanitizzati;
- pairing con numero esatto di risultati validi e suggerimento annuncio;
- Sommelier, ownership, limiti di input/output e cancellazione dello storico;
- validazione degli identificatori sulle route di cronologia;
- CORS esplicito e rifiuto delle eccezioni HTTP locali in produzione;
- namespace catalogo Stripe e rifiuto dei prezzi ricorrenti.

Non vengono usati URL di preview temporanei.

## Scan di portabilità

La ricerca runtime ha verificato:

- nessuna dipendenza o integrazione Lovable;
- nessuna dipendenza o integrazione Emergent;
- nessun asset `/__l5e`;
- lockfile Bun rigenerato dal registry npm pubblico;
- assenza di `yarn.lock`;
- `packageManager` impostato a `bun@1.3.14`.

I riferimenti a Lovable/Emergent nei documenti storici di audit o migrazione sono
contesto documentale, non dipendenze runtime.

## Verifiche non eseguite senza servizi reali

### Stripe sandbox e Stripe CLI

**Stato:** non eseguito; richiede credenziali e webhook sandbox.

Da verificare prima dell’attivazione:

- creazione reale di una Checkout Session;
- firma e inoltro webhook tramite Stripe CLI;
- pagamento con carta test;
- metodo di pagamento asincrono;
- eventi duplicati e fuori ordine;
- rimborso e riconciliazione;
- progettazione Stripe Connect per pagare venditori.

### Provider AI reale

**Stato:** non eseguito; nessuna chiave reale è stata usata.

La suite usa un provider fake. Prima di abilitarne uno reale servono chiave,
modello, quota di spesa, timeout, logging minimizzato e test di qualità/sicurezza.

### MongoDB reale

**Stato:** non eseguito; i test automatici usano repository in memoria.

Su staging vanno verificati:

- connessione Motor;
- creazione degli indici;
- eliminazione TTL dello storico;
- limite distribuito su più istanze;
- concorrenza e idempotenza;
- backup e ripristino.

### Provider di autenticazione reale

**Stato:** non eseguito; il contratto e il verifier JWT sono testati localmente.

Vanno validati token reali, chiave pubblica/JWKS, rotazione, issuer, audience,
revoca e mapping ruoli del provider scelto.

### GitHub Actions

**Stato:** workflow creato ma non ancora eseguito.

`.github/workflows/ci.yml` replica installazione, lint, typecheck, test e build su
runner puliti, con Bun 1.3.14, Python 3.12, cache e permessi read-only. Il suo primo
esito sarà disponibile dopo il push della branch.

## Conclusione

La base è coerente e riproducibile localmente. Restano obbligatorie le verifiche di
staging e compliance indicate sopra; il progetto non deve essere presentato come
production-ready.
