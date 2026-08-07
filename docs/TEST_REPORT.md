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
| Frontend | `bun install --frozen-lockfile` | Superato | Ambiente inizialmente privo di `node_modules`; Bun 1.3.14 e `bun.lock` rispettato |
| Frontend | `bun run lint` | Superato | Exit code 0; 14 warning Fast Refresh non bloccanti |
| Frontend | `bun run typecheck` | Superato | TypeScript strict, nessun errore |
| Frontend | `bun run test` | Superato | 13/13 test, 5 file, 23 asserzioni |
| Frontend | `bun run build` | Superato | Build produzione Vite 8.1.5 |
| Frontend SSR | smoke test route | Superato | 11 route selezionate HTTP 200; route inesistente HTTP 404 |
| Frontend browser | desktop e mobile | Superato | 12 route desktop, 9 route a 390×844 px, nessun nuovo errore console o overflow orizzontale |
| Backend | `python -m compileall -q .` | Superato | Sorgenti compilati sintatticamente |
| Backend | `python -m ruff check .` | Superato | Nessuna violazione bloccante |
| Backend | `python -m pytest -q` | Superato | 36/36 test in 0,54 s |
| Repository | scan residui runtime | Superato | Nessun Lovable, Emergent o `/__l5e` nel codice/lock runtime |
| Repository | package manager | Superato | Bun 1.3.14; `yarn.lock` assente |
| Repository | HTML | Superato | documento e pagina errore con `lang="it"` |
| CI | GitHub Actions run #1 | Superato | Run `30244669170`: job backend e frontend completati con successo |

## Frontend

### Test automatici

La suite Bun copre:

- contratti e parsing delle risposte API;
- client API e propagazione del token;
- dominio ordini e transizioni tipizzate;
- dominio cantina.
- formattazione numerica deterministica tra SSR Bun e browser.

I test sono in:

- `frontend/src/services/api-client.test.ts`;
- `frontend/src/services/api-contracts.test.ts`;
- `frontend/src/lib/store/order-domain.test.ts`;
- `frontend/src/lib/store/cellar-domain.test.ts`.
- `frontend/src/lib/format.test.ts`.

### Lint

Il lint termina con exit code 0. Rimangono 14 warning
`react-refresh/only-export-components` in componenti che esportano anche helper o
costanti. Non impediscono build o runtime; possono essere ridotti in un refactor
successivo separando tali export.

### Build e cantina 3D

La build di produzione è completata con Vite 8.1.5. Restano due avvisi non
bloccanti: `vite-tsconfig-paths` è ormai sostituibile dalla risoluzione nativa di
Vite e il chunk 3D supera la soglia generica di 500 kB.

Il chunk client della cantina 3D misura:

- 1.020,89 kB non compresso;
- 283,62 kB gzip.

È caricato lazy soltanto quando richiesto ed è completamente assente dal bundle
SSR. Il peso resta un elemento da monitorare sui dispositivi meno potenti.

### Smoke SSR

Undici route rappresentative sono state avviate dalla build SSR e hanno risposto
HTTP 200; una route inesistente ha restituito correttamente HTTP 404. Tutte
presentano `lang="it"`.

Il controllo in browser ha coperto homepage, ricerca, dettaglio annuncio, cantina,
vendita, club, profilo, checkout demo, pagine pagamento success/cancel, area
amministrativa e 404. Il profilo Admin demo apre correttamente il pannello e il
checkout mock crea un ordine locale.

È stato rilevato e corretto un mismatch di hydration sui prezzi oltre 999 €:
`Intl.NumberFormat` produceva raggruppamenti differenti nel runtime SSR Bun e nel
browser. La formattazione ora è deterministica e coperta da test. Dopo la
correzione non sono comparsi nuovi errori JavaScript o warning di hydration.

Le stesse schermate principali sono state verificate con viewport 390×844 px:
nessun overflow orizzontale e navigazione mobile presente. La cantina 3D viene
caricata soltanto dopo il clic su “Vista 3D”.

## Backend

I 36 test locali coprono, con adapter in memoria/fake:

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
- protezione dello stato `partially_refunded` da webhook tardivi di scadenza o
  fallimento;
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

**Stato:** run #1 completata con successo.

La run `30244669170` ha convalidato il commit
`55559b2d13ea8c60e17ea1c853660e0fcbbe1c8d`: job backend verde e job frontend
verde. Il workflow `.github/workflows/ci.yml` replica installazione, lint,
typecheck, test e build su runner puliti, con Bun 1.3.14, Python 3.12, cache e
permessi read-only.

Le verifiche locali descritte in questo rapporto includono inoltre le correzioni
successive rilevate durante la revisione finale. Il loro esito CI sarà riportato
nella Pull Request dopo il push; nessun esito locale sostituisce la nuova
esecuzione remota.

## Aggiornamento Fase 6d-1 — repair della deriva remota

Data: 30 luglio 2026.

Il progetto Supabase `pijnmcllmfgjmgsvtcej` è stato ispezionato, la deriva è
stata confermata e, dopo approvazione esplicita, è stata applicata la migrazione
additiva `20260730140948_security_invariants_remote_drift_repair.sql`. L'API
Supabase ha assegnato la versione `20260730140948`; il file locale è stato
allineato alla migration history.

| Area | Comando o verifica | Esito | Dettaglio |
|---|---|---|---|
| Supabase remoto | `pg_get_functiondef`, `pg_trigger`, `pg_policies` e privilegi | Deriva confermata | definizioni base riemerse per apertura, cancellazione, idoneità annuncio, cessione e policy ruoli |
| Supabase remoto | deploy repair | Superato | DDL applicato e registrato come `20260730140948 security_invariants_remote_drift_repair` |
| Supabase remoto | migration history | Superato | base, follow-up, helper, repair e correzione messaggi `20260730162046` risultano registrati |
| Supabase remoto | preflight read-only | Superato | 0 duplicati, 0 bottiglie non idonee/mismatch, 0 slot invalidi |
| Supabase remoto | fixture residue | Superato | 0 utenti `vinea-test-*` |
| Supabase remoto | griglia principale | Superato | 33/33 post-repair |
| Supabase remoto | griglia follow-up | Superato | 11/11 dopo la correzione UTF-8 dei due messaggi |
| Supabase remoto | query unica della repair | Superato | 13/13 `PASSA` dopo il deploy |
| Supabase advisor | Security e Performance | Riesaminati dopo la repair | `auth_rls_initplan` eliminato; restano eccezioni deliberate, indici senza traffico e Leaked Password Protection disabilitata |
| Repository | `git diff --check` | Eccezione documentata | diff staged/unstaged puliti dopo la rimozione della riga vuota in `CONTESTO_IA/05_INDICE_PR_E_FONTI.md`; il diff completo verso `main` segnala una riga vuota EOF nella migrazione già applicata `20260729234500_security_invariants_followup.sql`, non modificata retroattivamente |
| Repository | scansione file modificati | Superato | nessun `.env`, chiave privata, token o credenziale rilevato |
| Frontend Next.js | `bun install --frozen-lockfile` | Superato | Bun 1.3.14; lockfile invariato |
| Frontend Next.js | `bun run lint` | Superato | exit code 0; 23 warning preesistenti, 0 errori |
| Frontend Next.js | `bun run typecheck` | Superato | TypeScript, nessun errore |
| Frontend Next.js | `bun run build` | Superato | Next.js 16.2.12; build di produzione e 13 route completate |
| Supabase locale | CLI, replay e test SQL locali | Non eseguiti | Supabase CLI, `psql` e Docker non sono disponibili |

La query read-only
`supabase/tests/6d-1_remote_drift_repair_verifica.sql` raccoglie in una sola
griglia i controlli di definizione, privilegi, trigger, policy, preflight e
fixture ed è interamente verde. Le due griglie comportamentali sono state
autorizzate separatamente e concluse con 33/33 e 11/11; il controllo finale dei
residui è zero.

Nella verifica post-merge del 30 luglio 2026 il SQL remoto e le fixture sono
stati eseguiti soltanto dopo autorizzazioni esplicite separate. Il dettaglio
della migrazione `20260730162046`, delle griglie e dei residui è in
`docs/PHASE_6D1_POST_MERGE_VERIFICATION.md`.

## Conclusione

Lo stato remoto statico della Fase 6d-1 è nuovamente coerente con il repository.
Le due griglie comportamentali sono verdi. Restano le verifiche di staging e
compliance indicate sopra; il progetto non deve essere presentato come
production-ready.

## Checkpoint Fase 8 e Supabase Preview — 7 agosto 2026

| Area | Comando o verifica | Esito | Dettaglio |
|---|---|---|---|
| Frontend Next.js | `bun run test` | Superato | 166/166 test, 13 file, 13.782 asserzioni |
| Frontend Next.js | `bun run typecheck` | Superato | nessun errore TypeScript |
| Frontend Next.js | `bun run lint` | Superato | exit code 0; 25 warning non bloccanti, 0 errori |
| Frontend Next.js | `bun run build` | Superato | Next.js 16.2.12; 18 pagine generate, incluse `/messaggi` e `/notifiche` |
| Browser locale | messaggi e notifiche mock | Superato | apertura, unread, invio, segna tutte; nessun errore console |
| SQL statico | `8_messaging_notifications_static.sql` sulla Preview | Superato | 20 PASSA, 0 FALLISCE |
| SQL fixture | `8_messaging_notifications.sql` sulla Preview | Superato | 23 PASSA, 0 FALLISCE, cleanup incluso |
| Concorrenza | C1-C5 sulla Preview | Superato | 5 PASSA; idempotenza, dedupe, cursore e rate limit verificati con sessioni indipendenti |
| Cleanup | controllo esteso post-fixture | Superato | zero residui in 9 classi |
| Supabase Preview | PR #27, progetto `jggjaqcdbcbxdxhnggio` | Superato | migrazione `20260806224517` applicata; check GitHub verde |
| Supabase Advisor | Security e Performance sulla Preview | Riesaminati | nessun errore Fase 8; warning sulle RPC `SECURITY DEFINER` autenticate e info su FK composite/indice senza traffico, coerenti con il disegno e non bloccanti |
| Supabase produzione | migrazione Fase 8 | Non eseguito | ledger invariato a 19 migrazioni prima del merge; nessun SQL manuale |
| Realtime Dashboard | `Allow public access to channels=false` sulla Preview | Superato | Realtime attivo; valore riletto dopo reload |
| Realtime autenticato | topic conversazione e notifiche sulla Preview | Superato | partecipante e destinatario iscritti; outsider respinto su entrambi; canale pubblico respinto `PrivateOnly` |
| Payload e riconnessione | eventi `message.changed` e `notification.changed` | Superato | un evento per tipo, zero duplicati, sole chiavi chiuse previste |
| Cleanup smoke | controllo esteso post-Realtime | Superato | zero residui in 10 classi |

La Preview ha eseguito realmente la migrazione, la griglia statica da 20 casi,
la griglia fixture da 23 casi e le cinque prove concorrenti. Il cleanup finale
ha verificato zero residui. Questi risultati appartengono alla Preview della PR
#27 e non dimostrano un'applicazione su produzione.
