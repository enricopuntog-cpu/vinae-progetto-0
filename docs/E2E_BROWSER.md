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
| `frontend-next/e2e/support/target.ts` | guardia di isolamento (pura, con test in `bun test`) |
| `frontend-next/e2e/support/{stack,db,api,browser,test,pagina,immagine,esplora}.ts` | bersaglio, SQL nel container locale, porte reali, sessioni, diagnostica |
| `frontend-next/scripts/e2e-stack.mjs`, `e2e-serve.mjs` | stack locale e server dell'app |
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

## Isolamento (fail-closed)

Prima di aprire un browser, `risolviBersaglio()` + `globalSetup` richiedono:

1. API e app su loopback, nessun riferimento al progetto di produzione
   (`pijnmcllmfgjmgsvtcej`) né a `*.supabase.co`, chiave anonima senza `ref`;
2. container `supabase_db_*` su un daemon Docker locale (`DOCKER_HOST` assente o
   locale);
3. ledger delle migrazioni dello stack **uguale** ai file di `supabase/migrations/`;
4. nessun utente Auth estraneo alla fixture.

Se una condizione non è provata la corsa si ferma con `ISOLAMENTO NON PROVATO`:
il caso è `NON VERIFICATO`, non si forza. Fixture e pulizia sono quelle della
griglia 12zk (`supabase/tests/12zk_vpm_015b3_e2e_*.sql`, riusate senza copia);
la pulizia finale riporta residui e interruttori a zero e ne verifica il valore.
La visibilità pubblica della Cantina Accessori, che la pulizia 12zk non azzera, è
azzerata e verificata dal harness.

Segreti: la password degli utenti di fixture nasce a runtime, vive nella memoria
della corsa e non tocca il disco; l'accesso dei casi avviene in Node con
`@supabase/ssr` e i cookie sono iniettati nei contesti, quindi nessuna password
è mai digitata nel browser né compare in trace, video o screenshot. I report
oscurano `apikey` e JWT.

## Uso

Da `frontend-next/` (dettagli e problemi tipici nella skill):

```bash
bun run e2e:stack up      # stack isolato (Docker acceso)
bun run e2e:smoke         # Chromium desktop, @smoke
bun run e2e               # tre progetti
bun run e2e:report        # report HTML
bun run e2e:stack down --conferma    # distrugge lo stack
```

Gli artefatti stanno in `frontend-next/e2e/artifacts/` (ignorata da Git).

## Smoke automatico e suite estesa

| Livello | Quando | Cosa | Durata |
|---|---|---|---|
| Smoke | PR e push su `main` che toccano `frontend-next/`, `supabase/migrations/`, `supabase/config.toml`, la griglia 12zk o il workflow | `bun run e2e:smoke`, Chromium desktop, 17 casi `@smoke` | circa 3 min con build |
| Completa | `workflow_dispatch` con `suite=completa`; in locale `bun run e2e` prima di chiudere una modifica UI | tre progetti, 33 casi | circa 4 min con build |

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
