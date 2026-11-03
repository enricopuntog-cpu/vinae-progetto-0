# Comandi e ambiente

Tutto si lancia da `frontend-next/`. Versioni fissate: Playwright Test 1.64.1
(lockfile Bun), Supabase CLI 2.117.0 (`npx --yes supabase@2.117.0`), Bun 1.3.14.

## Prerequisiti

| Cosa | Verifica | Se manca |
|---|---|---|
| Docker (motore attivo) | `docker info` | avviare Docker Desktop; senza, `NON VERIFICATO` |
| Dipendenze | `bun install --frozen-lockfile` | — |
| Browser Playwright | `bun x playwright install chromium webkit` | scarica i binari della versione fissata nella cache utente |
| Stack locale | `bun run e2e:stack status` | `bun run e2e:stack up` |

`bun run e2e:stack up` avvia il progetto riservato `vinea_e2e` (porte 55321
API, 55322 database) con solo database, Auth, PostgREST, Storage e gateway
(stessa esclusione del gate CI `supabase-db-regression.yml`) e le migrazioni del
checkout, scrive il marcatore di possesso nel database e il file
`e2e/.stack-e2e.json`, e non stampa le chiavi. Rifiuta se esiste già una
risorsa Docker di `vinea_e2e` (di un'altra copia di lavoro o non chiusa): non la
tocca. Uno stack dedicato per macchina alla volta.

`down --conferma` distrugge (`stop --no-backup --project-id vinea_e2e`) solo lo
stack dedicato e solo se etichetta del container e marcatore coincidono con il
file di identità; senza `--conferma`, senza file o con marcatore diverso rifiuta.
Lo stack di sviluppo (`project_id` di `supabase/config.toml`) non è mai toccato.
Se lo stack dedicato è rotto (database che non risponde) e il marcatore non si
legge, `down` rifiuta: rimozione manuale e consapevole con
`npx --yes supabase@2.117.0 stop --no-backup --project-id vinea_e2e`, solo dopo
aver verificato che nessun altro worktree abbia `frontend-next/e2e/.stack-e2e.json`
(il comando non controlla il proprietario).

## Comandi

| Scopo | Comando |
|---|---|
| Smoke (Chromium desktop, casi `@smoke`) | `bun run e2e:smoke` |
| Tutto: Chromium desktop, Chromium 375 px, WebKit | `bun run e2e` |
| Un solo progetto | `bun run e2e --project=webkit-desktop` |
| Un solo caso | `bun run e2e --project=chromium-desktop -g "vendita parziale"` |
| Un solo file | `bun run e2e accessori-spenti` |
| Report HTML | `bun run e2e:report` |
| Trace di un caso | `bun x playwright show-trace e2e/artifacts/test-results/<caso>/trace.zip` |
| Guardia e utilità pure | `bun test e2e/support/target.test.ts` |

Ogni corsa costruisce l'app (`next build`, circa 45 s) con l'ambiente di prova e
la serve su `127.0.0.1:3100` (`E2E_APP_PORT` la cambia). Le variabili
`NEXT_PUBLIC_*` sono incorporate in build: cambiare un sorgente richiede una
build nuova.

Iterare senza ricostruire, **solo se i sorgenti non sono cambiati** dall'ultima
build: `E2E_SKIP_BUILD=1 bun run e2e ...` (mai in CI; riusa `.next` solo se
costruita da `e2e-serve.mjs` per lo stesso BUILD_ID e URL Supabase, altrimenti
ricostruisce). Un server già in ascolto
non si riusa mai (può avere flag o bersaglio diversi): `E2E_REUSE_SERVER` è stato
rimosso.

## Variabili di prova

Solo del processo di test, mai dell'app in produzione. Elenco in
`docs/ENVIRONMENT.md`.

| Variabile | Uso |
|---|---|
| `E2E_SUPABASE_URL`, `E2E_ANON_KEY` | stack dedicato; altrimenti da `supabase status` di `vinea_e2e`. Solo porta 55321 |
| `E2E_DB_CONTAINER` | ammesso solo `supabase_db_vinea_e2e` |
| `E2E_APP_PORT` | porta dell'app (predefinita 3100) |
| `E2E_SKIP_BUILD` | solo per iterare, vedi sopra |

`E2E_PASSWORD` ed `E2E_CORSA` sono generate dalla corsa: non impostarle, non stamparle.

## Artefatti

`frontend-next/e2e/artifacts/` (ignorata da Git): `report/` (HTML),
`results.json`, `test-results/<caso>/` con `trace.zip` e screenshot dei casi
falliti, più gli screenshot allegati ai casi che li producono sempre. Le trace non
contengono password (l'accesso avviene in Node, non nel browser); contengono
cookie di sessione di utenti fittizi di uno stack che poi si distrugge. Non
pubblicarle fuori dagli artefatti del workflow.

## Problemi tipici

- `ISOLAMENTO NON PROVATO: ...`: la guardia ha rifiutato il bersaglio. Non è un
  difetto dell'app: correggi l'ambiente (stack dedicato non avviato da questa
  copia di lavoro, ledger, utenti estranei, URL). `questa corsa non possiede più
  lo stack`: un'altra corsa è partita sullo stesso stack.
- `Stack E2E dedicato non raggiungibile`: Docker spento o `e2e:stack up` non eseguito.
- Porta 3100 occupata: un server precedente è rimasto vivo; fermalo (su Windows
  `Get-NetTCPConnection -LocalPort 3100`).
- `next dev` riscrive `frontend-next/AGENTS.md`: la suite non lo usa; se lo avvii
  a mano, ripristina il file con `git checkout -- frontend-next/AGENTS.md`.
  `next dev` inoltre non idrata le pagine da `127.0.0.1`: usare la build.
