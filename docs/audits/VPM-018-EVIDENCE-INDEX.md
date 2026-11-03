# VPM-018 — Indice progressivo delle evidenze (E-001 …)

Ogni riga riporta: ID, cosa è stato verificato, metodo, esito, dove si trova il dettaglio, livello di evidenza.
Livelli: FATTO VERIFICATO / DICHIARAZIONE PRECEDENTE / IPOTESI / NON VERIFICATO / BLOCCO ESTERNO.

| ID | Evidenza | Metodo | Esito | Dettaglio | Livello |
|----|----------|--------|-------|-----------|---------|
| E-001 | Commit analizzato: `a008bbc` = `origin/main` (PR #264 squash, 3 nov 2026); baseline dichiarata `a008bbc` ancora attuale | `git rev-parse`, `git log`, `git merge-base` | Confermata | `CHANGES.log` § CURRENT STATE | FATTO VERIFICATO |
| E-002 | Branch di lavoro `audit/vpm-018-prelaunch-gap-report` da `origin/main`, worktree pulito | `git status --short --branch`, `git worktree list` | OK | — | FATTO VERIFICATO |
| E-003 | Stack Supabase isolato `vpm018_audit`, porte 56321–56329, 108/108 migrazioni applicate, UP e healthy | `supabase start` (CLI 2.117.0), `docker ps`, `psql` sul container isolato | OK | `docs/audits/VPM-018-PRELAUNCH-GAP-REPORT.md` § 2 | FATTO VERIFICATO |
| E-004 | App `frontend-next` buildata e servita su `127.0.0.1:3100` contro stack isolato; flag Accessori/logistica/ordini accesi SOLO nel processo di prova; pagamenti e IA spenti | `next build`, `next start`, `NEXT_PUBLIC_*`/`ACCESSORI_*` impostati in env di processo | OK | `scripts/e2e-serve.mjs`, `playwright.config.ts` | FATTO VERIFICATO |
| E-005 | Stack condiviso `p_rogettto_vinae` NON toccato: ledger 101 migrazioni (stato dichiarato in CHANGES.log), 0 righe fixture `@e2e-12zk.test`, visibilità pubblica Accessori spenta, 9 bucket | `psql` sul container condiviso dopo il teardown accidentale | Confermato intatto | `supabase_db_p_rogettto_vinae` | FATTO VERIFICATO |
| E-006 | Lint `frontend-next`: 0 errori, 12 warning (`<img>` invece di `next/image`) | `bun run lint` | Passato | `/tmp/vpm018-lint.txt` | FATTO VERIFICATO |
| E-007 | Typecheck `frontend-next`: OK dopo `bun install --frozen-lockfile` (mancanza `@stripe/stripe-js` era solo `node_modules` non allineato) | `bun run typecheck` | Passato | `/tmp/vpm018-tsc.txt` | FATTO VERIFICATO |
| E-008 | Unit test `frontend-next`: 3324 passati / 0 falliti / 30779 assert = esattamente soglia CI `MIN_TESTS: 3324` (margine zero) | `bun run test` | Passato | `.github/workflows/ci.yml:114`, `/tmp/vpm018-test.txt` | FATTO VERIFICATO |
| E-009 | Build `frontend-next`: OK (tutte le route elencate nel build output) | `bun run build` | Passato | `/tmp/vpm018-build.txt` | FATTO VERIFICATO |
| E-010 | Audit dipendenze `frontend-next`: nessuna vulnerabilità | `node .github/scripts/frontend-next-audit.mjs` | Passato | `ci.yml` "Audit dependencies" | FATTO VERIFICATO |
| E-011 | Audit sicurezza app (statico): 12 rischi plausibili A-01…A-12, massimo P2, nessuna P0, nessuna vulnerabilità confermata | Subagente `vinea-security-auditor` (sola lettura) | Completato | output subagente (chat precedente) | RISCHIO PLAUSIBILE DA ISPEZIONE STATICA |
| E-012 | Audit sicurezza DB (statico): punti 1–4, 6, 8 coperti; punti 5, 7, 9 da completare; nessun exploit dimostrato | Subagente `vinea-security-auditor` (sola lettura) | Parziale | output subagente (chat precedente) | RISCHIO PLAUSIBILE / NON VERIFICABILE |
| E-013 | Inventario aree funzionali `frontend-next`: 16 aree mappate (route, componenti, RPC, flag, unit test, E2E, griglie SQL, stato) | Subagente `vinea-architecture-mapper` (sola lettura) | Completato | `docs/audits/VPM-018-TEST-COVERAGE.md` | FATTO VERIFICATO (inventario) |
| E-014 | DB isolato: RLS attiva su tutte le 58 tabelle pubbliche; 490 funzioni SECURITY DEFINER, tutte con `search_path`; 0 grant tabella a `anon`; 11 viste pubbliche selezionabili da `anon` | `psql` interrogazioni su `pg_class`, `pg_proc`, `pg_policies`, `information_schema` | Confermato | report § 1 | FATTO VERIFICATO (su stack isolato) |
| E-015 | Buckets storage: limiti e MIME coerenti (es. `cantina-accessori-foto` 2 MiB solo webp, `annunci` 5 MiB pubblici) | `psql` su `storage.buckets` | Confermato | report § 1 | FATTO VERIFICATO (su stack isolato) |
| E-016 | Suite E2E Playwright NON eseguibile sullo stack isolato: `globalSetup` blocca per ledger mismatch (7 migrazioni mancanti vs file checkout) e nessun browser Playwright scaricato | `bun run e2e:smoke` | Bloccato | report § 3, VPM-018-GAP-003 | NON VERIFICATO / BLOCCO ESTERNO (browser, ledger) |
| E-017 | Teardown della suite E2E ha eseguito `puliziaFixture` sul container condiviso `p_rogettto_vinae`: nessun effetto residuo rilevato (0 righe fixture, visibilità spenta) | Verifica `psql` post-teardown | OK | `supabase_db_p_rogettto_vinae` | FATTO VERIFICATO |
| E-018 | Worktree e documenti VPM-018 recuperati intatti (3 file non tracciati, branch = `origin/main` = `a008bbc`) | `git status`, `git worktree list` | OK | worktree `vinae-vpm-015qa` | FATTO VERIFICATO |
| E-019 | Catena E2E: `project_id` = `p_rogettto_vinae` coincide con lo stack di sviluppo; guardia solo loopback; teardown senza condizione sul setup; pulizia con guardia sugli utenti ma reset incondizionato degli interruttori | Lettura statica di `stack.ts`, `target.ts`, `db.ts`, `global-*.ts`, `e2e-stack.mjs`, `12zk_*_cleanup.sql`, `supabase/config.toml:5` | Confermata | Report § 0.2 | FATTO VERIFICATO (statico) |
| E-020 | 7 spec, 54 `test(` tutti `accessori-*`; nessun `error.tsx`/`not-found.tsx`/`sitemap.ts` in `src/app`; nessuna dipendenza di error tracking; solo 6 workflow, nessun gitleaks/CodeQL/dependabot | `grep`, `ls` | Confermato | Report § 0.1 | FATTO VERIFICATO |
| E-021 | Spot-check GAP-016, 021, 022, 023 su codice | lettura | Confermati (016 parziale) | Report § 0.1 | FATTO VERIFICATO |
| E-022 | E-006…E-011, E-013…E-015 non rieseguiti nella revisione | — | Riusati come precedenti | — | EVIDENZA PRECEDENTE |
| E-023 | Playwright, UX/UI, accessibilità, prestazioni, ledger/Auth Production | non eseguiti | — | Report § 0.4 | NON VERIFICATO / BLOCCO ESTERNO |

Indice non esaustivo: sono elencate solo le evidenze usate nel rapporto. Gli estratti di log non contengono segreti.
