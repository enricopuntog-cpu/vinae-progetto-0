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

`bun run e2e:stack up` avvia solo database, Auth, PostgREST, Storage e gateway
(stessa esclusione del gate CI `supabase-db-regression.yml`) con le migrazioni
del checkout, e non stampa le chiavi. `down` ferma e **distrugge** lo stack.

Il database restaurato da un backup precedente è accettato solo se il ledger
coincide con i file di `supabase/migrations/` e non ci sono utenti estranei: la
guardia lo controlla prima di ogni corsa.

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
build: `E2E_SKIP_BUILD=1 bun run e2e ...` (mai in CI). `E2E_REUSE_SERVER=1`
riusa un server già in ascolto: evitarlo, può avere flag o bersaglio diversi.

## Variabili di prova

Solo del processo di test, mai dell'app in produzione. Elenco in
`docs/ENVIRONMENT.md`.

| Variabile | Uso |
|---|---|
| `E2E_SUPABASE_URL`, `E2E_ANON_KEY` | bersaglio esplicito (come la CI); altrimenti da `supabase status` |
| `E2E_DB_CONTAINER` | container del database (predefinito `supabase_db_<project_id>`) |
| `E2E_APP_PORT` | porta dell'app (predefinita 3100) |
| `E2E_SKIP_BUILD`, `E2E_REUSE_SERVER` | solo per iterare, vedi sopra |

`E2E_PASSWORD` è generata dalla corsa: non impostarla, non stamparla.

## Artefatti

`frontend-next/e2e/artifacts/` (ignorata da Git): `report/` (HTML),
`results.json`, `test-results/<caso>/` con `trace.zip` e screenshot dei casi
falliti, più gli screenshot allegati ai casi che li producono sempre. Le trace non
contengono password (l'accesso avviene in Node, non nel browser); contengono
cookie di sessione di utenti fittizi di uno stack che poi si distrugge. Non
pubblicarle fuori dagli artefatti del workflow.

## Problemi tipici

- `ISOLAMENTO NON PROVATO: ...`: la guardia ha rifiutato il bersaglio. Non è un
  difetto dell'app: correggi l'ambiente (ledger, utenti estranei, URL).
- `Stack Supabase locale non raggiungibile`: Docker spento o stack non avviato.
- Porta 3100 occupata: un server precedente è rimasto vivo; fermalo (su Windows
  `Get-NetTCPConnection -LocalPort 3100`), non usare `E2E_REUSE_SERVER`.
- `next dev` riscrive `frontend-next/AGENTS.md`: la suite non lo usa; se lo avvii
  a mano, ripristina il file con `git checkout -- frontend-next/AGENTS.md`.
  `next dev` inoltre non idrata le pagine da `127.0.0.1`: usare la build.
