# Handoff — da WI-001B a WI-001C

Stato al 18 novembre 2026. Branch `feature/wi-001b-catalog-staging` (base `origin/main` `127cec2`).

## Cosa consegna WI-001B (infrastruttura, NON il catalogo)

- Migration `supabase/migrations/20261117120000_wi_001b_catalog_staging.sql`: schema privato `catalog` (fonti, snapshot, tentativi, `source_records`, storico eventi, rilievi, accorpamenti Combined, territori, alias, staging UNLOGGED), ruolo `catalog_loader`, 19 funzioni invoker con `search_path` vuoto, nessuna SECURITY DEFINER, RLS ovunque, nessun grant a PUBLIC/anon/authenticated/service_role. Additiva: nessun oggetto di `public` toccato. Modello: `docs/WINE_CATALOG_ARCHITECTURE.md` §11.
- Caricatore `tools/wine-catalog/lwin-load.mjs` (Bun, solo loopback, dry-run, ripresa con `--takeover`, rimozioni solo marcate).
- Prove: Node 73, griglia `supabase/tests/12zs_wi_001b_catalog_staging.sql` 152/152 (agganciata a `12g_ci_run.sh`), concorrenza reale `test/pg-integration.mjs` 18/18, crash reale `test/pg-crash.mjs` 13/13. Revisione indipendente Opus 5.5 HIGH: nessun P0/P1.

## Stato dei dati (leggere prima di fare qualsiasi cosa)

- **Il catalogo è vuoto.** Nessun import del file reale `LWINdatabase.xlsx` (non fornito al task; SHA-256 atteso `7669ceab…fd488e`, 212.894 righe). I conteggi in `IMPORT_MANIFEST.json` sono quelli del dry-run WI-001A.
- Decisione del founder: **cloud-first**. L'import completo gira solo in cloud, dopo verifica di destinazione, costi, autorizzazioni e sicurezza; mai sul PC (log e WAL hanno già riempito il disco una volta). Nessun benchmark massivo locale.
- Misure su dati sintetici (PostgreSQL 17.6 locale, poi eliminate): import completo 189–199 s, ~1 GB di WAL; ripetizione `skipped`; modificato a caldo 31–39 s. Il file reale non è mai stato misurato.

## Limiti e debiti aperti

1. **`finish_import_run` a 212.894 record non rimisurato dopo la correzione** (`enable_nestloop = off`, causa: Nested Loop quadratico senza statistiche). Verificato a 5.000 (< 1 s, prima 14–21 s) e 40.000 record (1,8 s). Da confermare nell'import cloud autorizzato, con `statement_timeout` e monitoraggio.
2. P14 è uno smoke di scala, non una guardia di regressione (passa anche senza la correzione su DB vuoto); la guardia è il caso 12zs A12b.
3. Al primo import ogni record è scritto due volte (INSERT con `territory_id` null, poi UPDATE in `sync_territories`): creare i territori prima e valorizzare `territory_id` nell'INSERT (WAL ≈ 2×).
4. Trigger `territory_edges_no_cycle` O(E²): trascurabile a ~2.000 archi (LWIN reale), da rivedere se i territori crescono.
5. Le funzioni create in WI-001C nascono eseguibili da PUBLIC: aggiungere `alter default privileges in schema catalog revoke execute on functions from public` o revocare esplicitamente.
6. `expected_rows` di uno snapshot non è correggibile; `p_stale_after` è validato solo dalla CLI; l'allowlist loopback è un guard-rail, non un confine di sicurezza (un tunnel su localhost la supera); `grant catalog_loader to current_user` in migration ignora l'errore con una notice.
7. Un test Node è fallito una volta su sei esecuzioni (non identificato, non riprodotto in cinque successive).
8. Rilievi `import_findings` che non si ripresentano restano `open`; la tabella va potata.

## Vietato senza nuova autorizzazione

Import completo su Production o su qualunque DB cloud; benchmark massivi locali; scaricare immagini; UI, agenti AI, job schedulati; estendere la licenza LWIN (CC BY 4.0, `SOURCE_REGISTRY.md`) a immagini/prezzi/API; fondere duplicati automaticamente; cancellare record; mettere il file xlsx in un repository.

## Proposta WI-001C — catalogo canonico

Con approvazione del founder delle regole di promozione/deduplicazione: `catalog.producers`, `wines` (LWIN-7), `wine_vintages` (LWIN-11), `wine_formats` con provenienza verso `source_records`; `wine_links` verso `public.wines` solo `manual`/`exact_id`; gerarchie e denominazioni; alias multilingua senza traduzione automatica; schede enologiche e attributi con provenienza; viste pubbliche a colonne chiuse; predisposizione a ricerca e uso AI (solo contratto, nessun agente). Criteri in `docs/WINE_CATALOG_ARCHITECTURE.md` §11. Prerequisito: import cloud autorizzato e verificato del file reale (o decisione di partire da un sottoinsieme).
