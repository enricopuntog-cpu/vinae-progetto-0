# Strategia di rilascio WI-001C in due tempi (Rilascio A runner, Rilascio B migration)

> **STORICO (21 novembre 2026).** Il ramo `feature/wi-001c-canonical-catalog` citato qui è stato superato: il riferimento operativo corrente è la **PR #310** (`feature/wi-001c-unified-completion`, 4 migration congelate integrate su `origin/main`). Il vecchio ramo resta solo come archivio; non è la prossima strada operativa. Stato aggiornato in `CLOSEOUT_WI_001C.md`.

Stato al 19 novembre 2026. **Nulla di quanto segue è stato eseguito su GitHub o su Supabase**: nessuna PR aperta, nessun merge,
nessuna migration applicata, nessun ambiente creato. Il documento dice cosa separare, perché e quale approvazione serve.

## Il problema

1. Un `workflow_dispatch` compare in Actions (e si può avviare) solo se il file del workflow è sul **branch predefinito** (`main`).
   `.github/workflows/wine-catalog-cloud-import.yml` oggi esiste solo su `feature/wi-001c-canonical-catalog`; inoltre il suo job
   gira solo da `refs/heads/main` (per scelta: i segreti dell'environment non devono vedere codice di un ramo qualsiasi).
2. Il merge dell'intero branch WI-001C porterebbe su `main` anche le migration `20261119100000` e `20261119120000`: l'integrazione
   Supabase le applicherebbe a **Production** al merge. Non è ciò che serve per provare l'import su uno staging, e non è autorizzato.

## Dipendenze reali (verificate sul codice, non assunte)

| Componente del runner | Dipende da | Dalla migration canonica? |
|---|---|---|
| `lwin-load.mjs`, `lib/load.mjs`, `lib/cloud-*.mjs`, `lib/db-bun.mjs`, `lib/safe-log.mjs` | funzioni e tabelle di **WI-001B** (`catalog.begin_import_run`, `stage_source_records`, `finish_import_run`, `state_digest`, `import_stage` UNLOGGED, `source_records`) | **No** |
| `assertCloudSession` / `assertLoaderPrivileges` / audit del login | `pg_roles`, `pg_auth_members`, catalogo di sistema; ruolo `catalog_loader` di WI-001B | **No** (l'audit è una query inline, non una funzione di database: per questo il Rilascio A non richiede la migration FIX-01) |
| Workflow `wine-catalog-cloud-import.yml` | solo il runner e i segreti dell'environment | **No** |
| Test Node (`cloud*.test.mjs`) e Bun (`tls-bun.test.mjs`) | niente database; un solo test legge `supabase/tests/12zz_…login_audit.sql` per la deriva del testo SQL | No (il test si **salta** se la griglia non c'è: arriva col Rilascio B) |
| Verifica post-finish (`verifyFinish`) | `catalog.state_digest`, `import_runs`, `import_stage` (WI-001B) | No |

Conclusione: **il runner è indipendente dal catalogo canonico**. WI-001B è già in Production (PR #300), quindi uno staging costruito
dalle migration di `main` ha già tutto ciò che serve all'import.

## Rilascio A — runner cloud-ready (nessuna migration)

Contenuto, tutto fuori da `supabase/`:

- `tools/wine-catalog/**` (importatore, moduli cloud, test, helper dei test TLS);
- `.github/workflows/wine-catalog-cloud-import.yml` e, in `.github/workflows/ci.yml`, il solo passo Bun dei test TLS;
- documentazione: questo file, `CLOUD_IMPORT_RUNBOOK.md`, `docs/ENVIRONMENT.md` (`CATALOG_DB_CA_PEM`), `CHANGES.log`.

**Controllo della Preview automatica.** Il check `Supabase Preview` si valuta sul diff: senza modifiche a `supabase/migrations/**` o
`supabase/config.toml` esce `skipped` (esito atteso, già osservato nello storico: `CONTESTO_IA/01_STATO_ATTUALE.md`, PR senza migration). Il Rilascio A
**non tocca `supabase/`** (verificabile con `git diff --stat origin/main...<ramo>`), quindi non crea alcun branch di Preview a pagamento e,
al merge, l'integrazione non ha nulla da applicare a Production. Il gate «Supabase DB regression» non è pertinente (nessuna migration o griglia) e si salta.

**Un push del ramo senza PR non crea Preview** (la Preview nasce dalla PR). Il ramo `release/wi-001c-runner-a` è pronto sul remoto; la PR **non** è aperta.

**Gate di approvazione per aprire la PR di A e mergerla**: decisione del founder/CTO (non è un merge tecnico di routine: porta su `main` un workflow
che, una volta configurati environment e segreti, può scrivere in un database cloud). Prima di aprire la PR verificare: `git diff --name-only origin/main...release/wi-001c-runner-a`
non contiene `supabase/`; CI verde. Dopo il merge il workflow resta **spento**: serve la variabile di repository `CATALOG_CLOUD_IMPORT_ENABLED=true` (non esiste) e l'environment `catalog-cloud-import`.

**Import reale impossibile per default** (tutte le condizioni insieme, fail-closed): `--cloud` + `CATALOG_CLOUD_IMPORT=enabled` + `--target-ref` uguale al ref dell'URL + host Supabase ammesso + `sslmode=verify-full` + CA fornita +
login dedicato (audit) + ruolo `catalog_loader`; Production rifiutata senza `--allow-production` e `CATALOG_PRODUCTION_APPROVAL` (il workflow non li imposta mai).

### Prova su staging (futura, non attivata)

1. Autorizzazione di costo e di progetto di staging **separato** (nuovo progetto Supabase = spesa: decisione del founder). Applicare a quel progetto le migration di `main` (WI-001B c'è già).
2. Login dedicato (vedi runbook), CA del progetto nel segreto `CATALOG_DB_CA_PEM`, segreti `CATALOG_DATABASE_URL` e `CATALOG_INPUT_URL`, environment protetto.
3. `mode = dry-run` (sola lettura), poi `mode = import`, poi verifica (runbook). Il workflow gira da `main`.

## Rilascio B — migration canoniche (solo dopo autorizzazione)

Contenuto: `supabase/migrations/20261119100000_…sql` (congelata) e `20261119120000_…sql`, griglie `12zy`, `12zz` (SQL e concorrenza), aggiornamento di `12zs`
(allowlist delle porte definer), `12g_ci_run.sh`, riga `bash -n` della concorrenza in `ci.yml`, handoff e documentazione del catalogo.
**Effetti**: la PR crea una Preview Supabase (costo) e il merge applica le migration a Production (catalogo canonico VUOTO, promozione spenta).
Gate: QA indipendente Opus HIGH sul codice, decisione del founder su Preview/costi, verifica del ledger di Production prima e dopo (CLAUDE.md, *Supabase workflow*:
il merge non prova l'applicazione; rileggere il ledger e le funzioni). **Non** approvare né accendere la promozione: restano decisioni separate.

## Ordine e indipendenza

A e B sono indipendenti: A può andare prima, B dopo (o mai insieme). Se B dovesse andare prima, A resta valido. Il ramo di lavoro
`feature/wi-001c-canonical-catalog` contiene **entrambi** (è la fonte di verità per la QA); il ramo `release/wi-001c-runner-a` è la proiezione di sola A su `origin/main`.
