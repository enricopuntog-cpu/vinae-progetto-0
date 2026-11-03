# Suite browser E2E (VPM-LAB-003)

31 ottobre 2026. Collaudo di Vinea in un browser reale con Playwright Test,
sulla sola pila isolata: Supabase locale effimero e un'app costruita per la
prova. È il livello «E2E browser» che mancava fra i test unitari, le griglie SQL
e le prove REST. La costituzione operativa resta `CLAUDE.md`; la skill che guida
l'uso è `.claude/skills/vinea-browser-qa/`.

## Che cosa è e che cosa non è

- Prova **ciò che vede l'utente**: sessioni di utenti distinti, form, dialoghi,
  upload di foto, gate delle flag, moderazione, pagine servite da `next start`.
- **Non** tocca produzione, non crea ordini né pagamenti, non usa credenziali
  reali, non sostituisce le griglie SQL del gate `Supabase DB regression`.
- Il primo banco di prova è Accessori (VPM-015): vetrina, Cantina, vendita
  parziale, segnalazione, oscuramento. Gli Accessori restano una vetrina:
  «pubblicato» non significa «acquistabile».

## Componenti

| File | Ruolo |
|---|---|
| `frontend-next/playwright.config.ts` | tre progetti, trace, report, `webServer` |
| `frontend-next/e2e/*.e2e.ts` | i casi (`.e2e.ts`: `bun test` non li raccoglie) |
| `frontend-next/e2e/support/target.ts` | guardie di isolamento e di possesso (pure, con test in `bun test`) |
| `frontend-next/e2e/global-setup.ts` | verifiche, presa di possesso e pulizia finale restituita (test in `global-setup.test.ts`) |
| `frontend-next/e2e/support/{stack,db,api,browser,test,pagina,immagine,esplora}.ts` | bersaglio, SQL protetto nel container dedicato, porte reali, sessioni, diagnostica |
| `frontend-next/scripts/e2e-stack.ts` (Bun), `e2e-serve.mjs` | stack E2E dedicato e server dell'app |
| `.github/workflows/e2e-browser.yml` | smoke su PR pertinenti, suite completa a richiesta |

Versioni fissate: `@playwright/test` **1.64.1** (esatta nel `package.json` e nel
`bun.lock`; browser Chromium 1248 e WebKit 27.2 della stessa versione), Supabase
CLI **2.117.0** (`npx --yes supabase@2.117.0`, come il gate), Bun 1.3.14, Node
22 in CI. Nessuna installazione globale e nessun `latest`.

## Progetti

| Progetto | Esegue |
|---|---|
| `chromium-desktop` | tutti i casi |
| `chromium-mobile-375` | solo `@cross`, viewport 375×812 |
| `webkit-desktop` | solo `@cross` |

`@smoke` = corsa veloce (CI su ogni PR pertinente). `@cross` = sola lettura o
stato preparato per progetto. I casi che accendono interruttori e creano dati
(`accessori-vendita-parziale`) girano solo su Chromium desktop.

## Casi di Accessori

| File | Casi |
|---|---|
| `accessori-spenti` | con gli interruttori del database spenti: vetrina e catalogo vuoti, 404 su un annuncio inesistente, Cantina senza sezione Accessori, admin senza rilascio non può accendere, utente ordinario non entra in `/admin/accessori` (404) |
| `accessori-vendita-parziale` | Cantina con 6 calici privati e foto; privato → esposto ma invisibile (interruttore pubblico spento) → visibile → di nuovo privato; annuncio di **2 pezzi su 6** a 20,00 € con preventivo mostrato uguale a quello del database (22,73 € per l'acquirente); pubblicazione automatica; vetrina e dettaglio da un altro account senza controlli di acquisto né note private; segnalazione; oscuramento dall'admin; contenuto non più raggiungibile (404, fuori vetrina, firma Storage negata); nessuna richiesta di checkout e `public.orders` vuota |
| `accessori-vetrina` | vetrina e dettaglio in Chromium, Chromium 375 px e WebKit: nessuno scorrimento orizzontale, accessibilità di base, sessione riconosciuta dal client |

## Isolamento (fail-closed, VPM-018-FIX-E2E-01)

La suite non lavora mai sullo stack di sviluppo (`project_id` di
`supabase/config.toml`, condiviso da ogni worktree), ma solo su uno **stack E2E
dedicato**: progetto riservato `vinea_e2e`, porte 55321 (API) e 55322
(database), creato da `bun run e2e:stack up` nella stessa copia di lavoro.
L'identità si dimostra, non si dichiara: nessuna variabile di consenso.

| Invariante | Come è garantito |
|---|---|
| Bersaglio esplicito | senza il file `frontend-next/e2e/.stack-e2e.json` (scritto da `up`, ignorato da Git) la configurazione rifiuta prima di eseguire qualsiasi comando; il container è sempre `supabase_db_vinea_e2e` (`E2E_DB_CONTAINER` diverso è rifiutato) e l'API deve stare sulla porta 55321, pubblicata dal gateway `supabase_kong_vinea_e2e` |
| Identità verificabile | `up` scrive nel database un marcatore (`vinea_e2e.identita`, schema senza privilegi per `anon`/`authenticated`) con un nonce casuale che solo il file di identità conosce; `create schema` senza `if not exists` fallisce su uno stack non nuovo |
| Verifica all'uso | ogni SQL della suite (`eseguiSql`) antepone, nella stessa sessione psql con `ON_ERROR_STOP`, un blocco che verifica marcatore e nonce: su un altro database nessuna istruzione parte |
| Possesso della corsa | il setup scrive un token di corsa nel marcatore; da lì ogni SQL (worker e pulizia) lo verifica, quindi una corsa più nuova toglie il possesso alla vecchia. Un token ereditato dalla shell viene scartato |
| Setup fallito | nessun `globalTeardown` (Playwright lo esegue anche a setup fallito: task registrato prima del setup). La pulizia è la funzione restituita da `globalSetup`, che Playwright esegue solo a setup completato, nello stesso processo |
| Interruttori | la pulizia 12zk li azzera, ma solo sullo stack dedicato: la guardia del marcatore la precede |
| Distruzione | `down --conferma` esegue `stop --no-backup --project-id vinea_e2e` solo se il container porta l'etichetta del progetto e il nonce nel database coincide con il file; `up` rifiuta se esiste già una risorsa Docker di `vinea_e2e` |
| Server dell'app | mai riusato (`reuseExistingServer: false`): un server già in ascolto può puntare a un altro stack |

Restano anche le condizioni precedenti: loopback, nessun riferimento al progetto
di produzione (`pijnmcllmfgjmgsvtcej`) né a `*.supabase.co`, chiave anonima senza
`ref`, daemon Docker locale, ledger **uguale** ai file di `supabase/migrations/`,
nessun utente Auth estraneo alla fixture (comprese le righe senza email).

Se una condizione non è provata la corsa si ferma con `ISOLAMENTO NON PROVATO`:
il caso è `NON VERIFICATO`, non si forza. Fixture e pulizia sono quelle della
griglia 12zk (`supabase/tests/12zk_vpm_015b3_e2e_*.sql`, riusate senza copia né
modifiche: il gate `Supabase DB regression` le usa sul proprio stack effimero);
la pulizia finale riporta residui e interruttori a zero e ne verifica il valore.
La visibilità pubblica della Cantina Accessori, che la pulizia 12zk non azzera, è
azzerata e verificata dal harness.

Uno stack dedicato per macchina alla volta (porte fisse). Se il database dello
stack dedicato non risponde, `down` non può leggere il marcatore e rifiuta: la
rimozione manuale e consapevole è
`npx --yes supabase@2.117.0 stop --no-backup --project-id vinea_e2e`, **solo dopo
aver verificato che nessun altro worktree abbia `frontend-next/e2e/.stack-e2e.json`**
(quel comando non controlla il proprietario: è la via d'uscita, non l'uso normale).
`E2E_SKIP_BUILD=1` riusa `.next` solo se l'ha costruita `e2e-serve.mjs` per lo
stesso `BUILD_ID` e lo stesso URL Supabase (impronta `.next/e2e-bersaglio.json`),
altrimenti ricostruisce: una build per un altro stack non viene mai servita. Un
`supabase db reset` sullo stack dedicato cancella il marcatore: serve un nuovo
`down`/`up`.

Segreti: la password degli utenti di fixture nasce a runtime, vive nella memoria
della corsa e non tocca il disco; l'accesso dei casi avviene in Node con
`@supabase/ssr` e i cookie sono iniettati nei contesti, quindi nessuna password
è mai digitata nel browser né compare in trace, video o screenshot. I report
oscurano `apikey` e JWT.

## Uso

Da `frontend-next/` (dettagli e problemi tipici nella skill):

```bash
bun run e2e:stack up      # stack E2E dedicato vinea_e2e (Docker acceso)
bun run e2e:smoke         # Chromium desktop, @smoke
bun run e2e               # tre progetti
bun run e2e:report        # report HTML
bun run e2e:stack down --conferma    # distrugge SOLO lo stack dedicato di questa copia di lavoro
```

La CI (`e2e-browser.yml`) usa gli stessi comandi `up`/`down` e fallisce se la
riga `[e2e] pulizia completata` non compare nella corsa.

Gli artefatti stanno in `frontend-next/e2e/artifacts/` (ignorata da Git).

## Smoke automatico e suite estesa

| Livello | Quando | Cosa | Durata |
|---|---|---|---|
| Smoke | PR e push su `main` che toccano `frontend-next/`, `supabase/migrations/`, `supabase/config.toml`, la griglia 12zk o il workflow | `bun run e2e:smoke`, Chromium desktop, casi `@smoke` (54 al 3 novembre 2026) | 3 min 31 s misurati in CI con 17 casi (PR #248); 2,4 min in locale con 54 casi (VPM-018-FIX-E2E-01) |
| Completa | `workflow_dispatch` con `suite=completa`; in locale `bun run e2e` prima di chiudere una modifica UI | tre progetti, 33 casi | circa 4-5 min (33 casi misurati in locale: 1,0-1,3 min più build e installazione di WebKit) |

Il workflow `E2E browser` **non** è un check richiesto dal ruleset
`main-protection`: non cambia le condizioni di merge. Se se ne vuole fare un
check richiesto, è una decisione del titolare sul ruleset.

## Qualità della suite: prova mutazionale

Un caso vale se diventa rosso quando la funzione si rompe. Il 31 ottobre 2026,
in ambiente isolato, è stato aggiunto di proposito un pulsante «Acquista ora»
nel dettaglio dell'annuncio (`AnnunciPubblici.tsx`): build nuova, il caso 5 di
`accessori-vendita-parziale` è diventato rosso (`getByRole('button', /acquista…/)`:
atteso 0, trovato 1) e i quattro casi dipendenti non sono partiti; ripristinato il
sorgente con `git checkout`, build nuova, **33/33 verdi** e residui a zero.

## Limiti dichiarati

- Lo stack non avvia Realtime (come il gate): il WebSocket Realtime fallisce ed è
  ammesso come rumore noto, con altre due voci documentate in
  `support/test.ts` (`RUMORE_INFRASTRUTTURA`).
- Il fallback CSP statico (`security-headers.ts`, solo Report-Only) nomina l'origine
  Supabase di produzione: su stack locale WebKit lo scrive in console. Una
  violazione della CSP effettiva (enforcing) fa fallire il caso.
- Nessun modulo di login via interfaccia: l'accesso con password non si digita nel
  browser (per non lasciarla in trace). Il form `/accedi` non è coperto da questa
  suite.
- Nessun test di carico, nessun test visivo a confronto di pixel: gli screenshot
  si leggono, non si confrontano in automatico.
- La prova da un'altra sessione Claude Code nel profilo OmniRoute `vinea-coding` è
  `NON VERIFICATO` (OAuth del profilo scaduto in quella sessione); vedi
  `.claude/skills/vinea-browser-qa/references/strumenti-browser.md`.
- Playwright CLI non è installato: auditato e rinviato nel registro delle skill.
