# VPM-018 — Indice progressivo delle evidenze (E-001 …)

Ogni riga riporta: ID, cosa è stato verificato, metodo, esito, dove si trova il dettaglio, livello di evidenza.
Livelli: **FV** fatto verificato nella sessione indicata · **EP** evidenza precedente (sessione OmniRoute, non rieseguita in VPM-018-RECOVERY) · **IP** ipotesi · **NV** non verificato · **BE** blocco esterno. I file `/tmp/vpm018-*.txt` citati non sono conservati nel repository.

| ID | Evidenza | Metodo | Esito | Dettaglio | Livello |
|----|----------|--------|-------|-----------|---------|
| E-001 | Commit analizzato: `a008bbc` = `origin/main` (PR #264 squash, 3 nov 2026); baseline dichiarata `a008bbc` ancora attuale | `git rev-parse`, `git log`, `git merge-base` | Confermata | `CHANGES.log` § CURRENT STATE | FV (riverificato in VPM-018-RECOVERY) |
| E-002 | Branch di lavoro `audit/vpm-018-prelaunch-gap-report` da `origin/main`, worktree pulito | `git status --short --branch`, `git worktree list` | OK | — | EP |
| E-003 | Stack Supabase isolato `vpm018_audit`, porte 56321–56329, 108/108 migrazioni applicate, UP e healthy | `supabase start` (CLI 2.117.0), `docker ps`, `psql` sul container isolato | OK | `docs/audits/VPM-018-PRELAUNCH-GAP-REPORT.md` § 2 | EP (OmniRoute) |
| E-004 | App `frontend-next` buildata e servita su `127.0.0.1:3100` contro stack isolato; flag Accessori/logistica/ordini accesi SOLO nel processo di prova; pagamenti e IA spenti | `next build`, `next start`, `NEXT_PUBLIC_*`/`ACCESSORI_*` impostati in env di processo | OK | `scripts/e2e-serve.mjs`, `playwright.config.ts` | EP (OmniRoute) |
| E-005 | Stack condiviso `p_rogettto_vinae` **toccato** dal teardown E2E accidentale. Verifica `psql` successiva: ledger 101 migrazioni, 0 righe fixture `@e2e-12zk.test`, visibilità pubblica Accessori spenta, 9 bucket. Valori degli interruttori di sviluppo prima dell'evento non noti | `psql` sul container condiviso dopo il teardown accidentale | Nessun residuo rilevato; assenza di danno non dimostrata | `supabase_db_p_rogettto_vinae` | EP (OmniRoute) |
| E-006 | Lint `frontend-next`: 0 errori, 12 warning (`<img>` invece di `next/image`) | `bun run lint` | Passato | `/tmp/vpm018-lint.txt` | EP (OmniRoute) |
| E-007 | Typecheck `frontend-next`: OK dopo `bun install --frozen-lockfile` (mancanza `@stripe/stripe-js` era solo `node_modules` non allineato) | `bun run typecheck` | Passato | `/tmp/vpm018-tsc.txt` | EP (OmniRoute) |
| E-008 | Unit test `frontend-next`: 3324 passati / 0 falliti / 30779 assert = esattamente soglia CI `MIN_TESTS: 3324` (margine zero) | `bun run test` | Passato | `.github/workflows/ci.yml:114`, `/tmp/vpm018-test.txt` | EP (OmniRoute) |
| E-009 | Build `frontend-next`: OK (tutte le route elencate nel build output) | `bun run build` | Passato | `/tmp/vpm018-build.txt` | EP (OmniRoute) |
| E-010 | Audit dipendenze `frontend-next`: nessuna vulnerabilità | `node .github/scripts/frontend-next-audit.mjs` | Passato | `ci.yml` "Audit dependencies" | EP (OmniRoute) |
| E-011 | Audit sicurezza app (statico): 12 rischi plausibili A-01…A-12, massimo P2, nessuna P0, nessuna vulnerabilità confermata | Subagente `vinea-security-auditor` (sola lettura) | Completato | output subagente (chat precedente) | IP (subagente, OmniRoute) |
| E-012 | Audit sicurezza DB (statico): punti 1–4, 6, 8 coperti; punti 5, 7, 9 da completare; nessun exploit dimostrato | Subagente `vinea-security-auditor` (sola lettura) | Parziale | output subagente (chat precedente) | IP (subagente, OmniRoute) |
| E-013 | Inventario aree funzionali `frontend-next`: 16 aree mappate (route, componenti, RPC, flag, unit test, E2E, griglie SQL, stato) | Subagente `vinea-architecture-mapper` (sola lettura) | Completato | `docs/audits/VPM-018-TEST-COVERAGE.md` | EP (inventario del subagente) |
| E-014 | DB isolato: RLS attiva su tutte le 58 tabelle pubbliche; 490 funzioni SECURITY DEFINER, tutte con `search_path`; 0 grant tabella a `anon`; 11 viste pubbliche selezionabili da `anon` | `psql` interrogazioni su `pg_class`, `pg_proc`, `pg_policies`, `information_schema` | Confermato | report § 1 | EP (solo stack isolato) |
| E-015 | Buckets storage: limiti e MIME coerenti (es. `cantina-accessori-foto` 2 MiB solo webp, `annunci` 5 MiB pubblici) | `psql` su `storage.buckets` | Confermato | report § 1 | EP (solo stack isolato) |
| E-016 | `bun run e2e:smoke` bloccato da `globalSetup` per ledger mismatch (101 vs 108): il target era lo stack **condiviso** `p_rogettto_vinae` selezionato implicitamente, non lo stack isolato `vpm018_audit` (108/108). Nessun browser Playwright scaricato nell'ambiente di prova | `bun run e2e:smoke` | Bloccato (setup fail-closed) | report § 0.2, GAP-004; GAP-003 | EP; suite NV |
| E-017 | Teardown della suite E2E ha eseguito `puliziaFixture` sul container condiviso `p_rogettto_vinae`: nessun effetto residuo rilevato (0 righe fixture, visibilità spenta) | Verifica `psql` post-teardown | Nessun residuo rilevato; interruttori ante-evento non noti | `supabase_db_p_rogettto_vinae` | EP (OmniRoute) |
| E-018 | Worktree e documenti VPM-018 recuperati intatti (3 file non tracciati, branch = `origin/main` = `a008bbc`) | `git status`, `git worktree list` | OK | worktree `vinae-vpm-015qa` | FV |
| E-019 | Catena E2E: `project_id` = `p_rogettto_vinae` coincide con lo stack di sviluppo; guardia solo loopback; teardown senza condizione sul setup; pulizia con guardia sugli utenti ma reset incondizionato degli interruttori | Lettura statica di `stack.ts`, `target.ts`, `db.ts`, `global-*.ts`, `e2e-stack.mjs`, `12zk_*_cleanup.sql`, `supabase/config.toml:5` | Confermata | Report § 0.2 | FV (statico) |
| E-020 | 7 spec, 54 `test(` tutti `accessori-*`; nessun `error.tsx`/`not-found.tsx`/`sitemap.ts` in `src/app`; nessuna dipendenza di error tracking; solo 6 workflow, nessun gitleaks/CodeQL/dependabot | `grep`, `ls` | Confermato | Report § 0.1 | FV |
| E-021 | Spot-check GAP-016, 021, 022, 023 su codice | lettura | Confermati (016 parziale) | Report § 0.1 | FV |
| E-022 | E-006…E-011, E-013…E-015 non rieseguiti nella revisione | — | Riusati come precedenti | — | EP |
| E-023 | Playwright, UX/UI, accessibilità, prestazioni, ledger/Auth Production | non eseguiti | — | Report § 0.4 | NV / BE |

Indice non esaustivo: sono elencate solo le evidenze usate nel rapporto. Gli estratti di log non contengono segreti.
