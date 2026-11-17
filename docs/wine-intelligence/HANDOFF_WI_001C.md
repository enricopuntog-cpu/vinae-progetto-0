# Handoff — da WI-001B a WI-001C

Stato al 17 novembre 2026. Branch `feature/wi-001b-catalog-staging` (base `origin/main` `127cec2`), **non pubblicato, non mergiato**.

## Cosa esiste (solo nel repository e su database LOCALE effimero)

- Migration `supabase/migrations/20261117120000_wi_001b_catalog_staging.sql`: schema privato `catalog` (fonti, snapshot, tentativi, record importati, storico, rilievi, accorpamenti, territori, alias), ruolo `catalog_loader`, nove funzioni invoker. Modello e scostamenti dalla bozza: `docs/WINE_CATALOG_ARCHITECTURE.md` §11.
- Caricatore `tools/wine-catalog/lwin-load.mjs` (Bun; client PostgreSQL integrato; solo database loopback; dry-run con anteprima del delta; `--takeover`, `--allow-mass-removal`). Il parser e i normalizzatori di WI-001A sono riusati; chiuso il limite G1 (i Combined sono confrontati con lo snapshot precedente: `merged_new/updated/unchanged`).
- Griglia SQL `supabase/tests/12zs_wi_001b_catalog_staging.sql` (81 casi), agganciata a `supabase/tests/12g_ci_run.sh` (gate «Supabase DB regression», stack locale effimero). 15 nuovi test Node in `tools/wine-catalog/test/load.test.mjs` (57 totali).

## Cosa NON esiste / non è stato distribuito

- La migration **non è applicata a nessun database remoto** (Production, Preview, staging): migration applicate = 0. Il ledger resta a 104+ migration senza questa.
- **Nessun import del file reale**: `LWINdatabase.xlsx` non è stato indicato né letto in questa sessione. Conteggi 212.894 / 206.167 / 6.221 / 506 sul database: NON VERIFICATI. Resta da eseguire, in locale: `bun tools/wine-catalog/lwin-load.mjs --input <percorso> --database-url postgresql://…127.0.0.1… --report <fuori dal repo>`.
- Nessuna scheda canonica, nessun `wine_links`, nessuna immagine, nessuna UI, nessun agente AI, nessun job schedulato.
- Docker/Supabase CLI non erano disponibili sulla macchina: la migration e la griglia sono state provate su PGlite (PostgreSQL in WASM, ruoli `anon/authenticated/service_role` creati a mano, senza PostgREST né Auth). La griglia **non è ancora stata eseguita su uno stack Supabase reale**: lo farà il gate CI al primo push consentito.

## Blocco alla pubblicazione

Un push dei file sotto `supabase/` fa creare all'integrazione GitHub di Supabase un branch Preview che applica le migration (`CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`, check «Supabase Preview»). L'incarico vieta ogni applicazione remota, quindi **nessun push è stato fatto**. Per pubblicare serve un incarico che decida come gestire la Preview (per esempio PR con la migration dopo la verifica degli effetti di distribuzione).

## Prima del merge (incarico successivo)

1. Esecuzione della griglia 12zs su stack Supabase locale reale (CLI 2.117.0 come in CI); verifica che `postgres` possa fare `SET ROLE catalog_loader` (la migration prova `grant catalog_loader to current_user`).
2. Import locale del file reale con dry-run e confronto con `IMPORT_MANIFEST.json`.
3. Decidere come gestire la Supabase Preview e verificare, dopo il merge, ledger e oggetti (`catalog.*`) su Production.
4. Rivedere i residui: tabella `import_findings` che cresce a ogni tentativo; contratto «leggere solo se l'ultimo tentativo è succeeded».

## Proposta WI-001C — schede canoniche

Definire e approvare (founder) le regole di promozione e deduplicazione (LWIN-7 ↔ `catalog.wines`, LWIN-11 ↔ annata, formato), poi creare `catalog.producers/wines/wine_vintages/wine_formats` con provenienza verso `source_records`, `catalog.wine_links` verso `public.wines` solo `manual`/`exact_id`, alias territoriali con mappatura attendibile, viste pubbliche a colonne chiuse. Criteri in `docs/WINE_CATALOG_ARCHITECTURE.md` §11.

## Vietato senza nuova autorizzazione

Applicare migration o importare su ambienti remoti; mergiare la PR; scaricare immagini; creare UI, agenti AI o job; estendere la licenza LWIN a immagini/prezzi/API; fondere duplicati automaticamente; cancellare record; WI-003, nuove ricerche di cataloghi, Vinea Sentinel.
