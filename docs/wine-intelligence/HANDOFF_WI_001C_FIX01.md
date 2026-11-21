# Handoff — WI-001C-FIX-01 (per la QA indipendente Opus HIGH)

> **STORICO (21 novembre 2026).** Il ramo `feature/wi-001c-canonical-catalog` citato qui è stato superato: il riferimento operativo corrente è la **PR #310** (`feature/wi-001c-unified-completion`, 4 migration congelate integrate su `origin/main`). Il vecchio ramo resta solo come archivio; non è la prossima strada operativa. Stato aggiornato in `CLOSEOUT_WI_001C.md`.

Stato al 19 novembre 2026. Branch `feature/wi-001c-canonical-catalog`, base della correzione `9254c93` (BUILD-01), `origin/main` `d66a01e`.
Questo documento è autosufficiente: la QA verifica il codice direttamente da GitHub senza la cronologia della conversazione.
**Nulla è stato eseguito su Supabase Production o su altri ambienti cloud**: nessun import, nessuna promozione, nessuna migration applicata, nessun branch/progetto creato, nessuna PR aperta.

## Regola sulle migration

`20261119100000_wi_001c_canonical_catalog.sql` è **congelata** (già sul remoto) e NON è stata toccata (`git diff 9254c93 -- supabase/migrations/20261119100000*` è vuoto).
Le correzioni stanno in una nuova migration additiva: **`supabase/migrations/20261119120000_wi_001c_fix01_canonical_hardening.sql`**.

## Correzioni — importatore cloud (I-1, I-2, I-3)

| ID | Difetto QA | Correzione | Dove | Prova |
|---|---|---|---|---|
| I-1 | CA/TLS/runner non provati | CA obbligatoria da `CATALOG_DB_CA_PEM` (o `--ca-file`, mai entrambe; PEM solo certificati, no chiavi private); URL con un solo `sslmode=verify-full`; `rejectUnauthorized: true` sempre; errori TLS normalizzati (Bun dà messaggio vuoto per hostname errato); segreto del workflow solo allo step del caricatore | `lib/cloud-tls.mjs`, `lib/db-bun.mjs`, `lwin-load.mjs`, workflow | `test/tls-bun.test.mjs` (Bun, server PG **finto** con TLS su loopback, certificati generati con openssl): CA giusta+hostname giusto OK; **CA errata, hostname errato, `sslmode` disable/allow/prefer/require/verify-ca, server che non offre TLS: rifiutati**; `cloud-fix01.test.mjs` (Node) |
| I-2 | login con privilegi/membership indiretta | `LOGIN_AUDIT_SQL`: grafo ricorsivo `pg_auth_members` (raggiungibile solo `catalog_loader`), ruoli con poteri, ADMIN OPTION, grant diretti (rel/func/schema/colonne/db), oggetti posseduti, CREATE su db/public/catalog; valutato da `evaluateLoginAudit` | `lib/cloud-guards.mjs` | griglia **12zz** su **ruoli reali** (A01–A12) + `cloud-fix01.test.mjs` (membership indiretta, ruolo privilegiato, grant aggiuntivi, ADMIN OPTION, escalation) + test di deriva testo SQL ↔ griglia |
| I-3 | WAL solo dopo il finish; riconnessioni | stima preventiva `planFinishWal` (rifiuta il finish se WAL usato + stima > budget); monitor su seconda connessione con `pg_cancel_backend` oltre il budget (e se perde visibilità); hook `afterFinish`; **connessione riservata** (Bun.SQL altrimenti si ricollega in silenzio perdendo ruolo/timeout: verificato) + `assertIntact()` a ogni lotto; filtri su `RESET ROLE`/`SET ROLE`/`set_config('role')`/transazioni/multi-statement | `lib/cloud-guards.mjs`, `lib/db-bun.mjs`, `lib/load.mjs` | `cloud-fix01.test.mjs` (stima, monitor, fail-closed), `tls-bun.test.mjs` (caduta ⇒ un solo startup sul server, richieste rifiutate; filtri) |
| dry-run | si connetteva col ruolo di scrittura | sessione `default_transaction_read_only = on` + solo `SELECT/SHOW/WITH/VALUES` lato client | `lib/db-bun.mjs`, `lwin-load.mjs` | `tls-bun.test.mjs` |

**Garantito / non garantito sul WAL**: vedi `CLOUD_IMPORT_RUNBOOK.md` §9 (nessun limite rigido; il rollback non restituisce il WAL scritto; stima euristica).

## Correzioni — catalogo canonico (D-1 … D-6)

| ID | Difetto | Correzione nella migration FIX-01 | Prova (12zy) |
|---|---|---|---|
| D-1 | regola approvata ≠ logica | `promotion_rules.approved_fingerprint/approved_view_digest`: l'approvazione (UPDATE del proprietario) registra l'impronta md5 delle funzioni di promozione e della vista candidati; regola **immutabile** (descrizione, approvatore, impronta; solo → `retired`; non cancellabile; non nasce approvata); `promote_wine_candidates` accetta **solo** `lwin-conservative-v1` e verifica impronta e vista; `promotion_authorized()` nel trigger di INSERT. Cambiare una riga di una funzione invalida l'approvazione. **`lwin-conservative-v1` resta `draft`** | L01–L11, Z01–Z06 (manomissione), C05b/C05c (interruttore acceso + bozza) |
| D-2 | `origin='manual'` come scorciatoia | vincoli: manual ⇒ niente LWIN, niente `source_id/source_record_id`/`natural_key`, `provenance_note` obbligatoria; promozione ⇒ record di fonte Live/wine/autorizzato/non rimosso con `external_id = lwin7` e chiave naturale coerente | M01–M10 |
| D-3 | fusioni | `merge_id` su produttori/vini; `merge_authorized` verifica coppia **e direzione** (kept_side); `revert_authorized` vale solo per la fusione che ha fuso l'entità; nessun riuso di fusioni annullate; stati active→merged→active, active→retired (non se ci sono fusioni verso l'entità), retired definitivo, nessun re-puntamento; cicli rilevati; **advisory lock per tipo** nelle funzioni e nel guard; vini di produttori diversi non si fondono; nessuna cancellazione | N01–N15, K01/K11–K15, concorrenza reale `12zz_…_concorrenza.sh` |
| D-4 | starvation lotti | `promotion_candidates` marca i record con produttore non attivo (anche via fusione); il lotto li salta; `promotion_exceptions` (append-only) li traccia; nessuna fusione/scarto automatico; l'anteprima li conta (`blocked_producer_retired`) | O01–O09 |
| D-5 | LWIN-16/18 | `format_guard` secondo Liv-ex: LWIN-16 = LWIN-11 + volume (5 cifre, ml, `units_per_pack = 1`); LWIN-18 = LWIN-11 + confezione (2 cifre) + volume (5 cifre); **nessun prefisso LWIN-16 richiesto**; coerenza con `volume_ml`/`units_per_pack`; volume ≤ 99999, confezione ≤ 99; richiedono LWIN-11 dell'annata. Esempi ufficiali: 1234567 2012 00750 (LWIN-16), 1234567 2012 12 00750 (LWIN-18). Non verificata la cifra di controllo del LWIN-7 né il codice del non-millesimato (non descritti dalla pagina ufficiale) | D12/D16, P01–P14 |
| D-6 | audit e privilegi | il curatore **non ha più INSERT/UPDATE/DELETE** (né a colonna) su alcuna tabella canonica; scrive solo con 16 porte `SECURITY DEFINER` (`search_path` vuoto, `EXECUTE` solo a `catalog_curator`), ognuna con esecutore obbligatorio (1–200 caratteri, senza caratteri di controllo) ed **evento append-only** con `db_user` (login) e `acting_role` (SET ROLE); `record_canonical_event` non eseguibile dal curatore (nessun audit falso); RLS del curatore solo `SELECT` | A03, A10b, Q01–Q11, K05a |

Risposta alla domanda «i privilegi diretti sono necessari alle funzioni invoker?»: sì, finché le funzioni erano invoker; per questo il modello è passato a definer + revoca (CLAUDE.md: colonne di dominio solo tramite funzione `SECURITY DEFINER` verificata). Nessun superuser, RLS non disattivata. L'attore resta dichiarato dal chiamante (testo): l'identità **autorevole** è `db_user`/`acting_role`; la separazione proponente/revisore non è imposta (limite noto).

## Test K05 / C05

- **K05** ora crea un candidato aperto reale e prova che l'INSERT diretto in `entity_merges` è respinto per **autorizzazione** (curatore: 42501 «permission denied»; proprietario: 55000 «richiede un candidato rivisto "same"»), con asserzione sul **messaggio**, non su un `not_null_violation` generico.
- **C05b/C05c**: interruttore acceso + regola ancora in bozza ⇒ promozione rifiutata (42501, «non approvata»), nulla creato, nemmeno INSERT diretto `origin=promotion`.

## Prove eseguite (questa sessione)

Vedi il report finale in conversazione e `CHANGES.log`. Riepilogo: 12zy **221/221**, 12zs **153/153** (con la migration FIX-01 applicata), 12zz **12/12** su PGlite (PostgreSQL reale in WASM) con controlli di mutazione; Node `tools/wine-catalog` 114 passati + 10 saltati sotto Node (i 10 test Bun passano con `bun test`); CI GitHub «Supabase DB regression» sul ramo: vedi `CHANGES.log`/report.
**Non provato**: stack Supabase reale oltre alla CI; Bun contro un server PostgreSQL vero (solo il server finto); il pooler Supavisor; l'esecuzione del monitor WAL e di `pg_cancel_backend` su un server vero (solo con query finte); la concorrenza reale (script bash) solo in CI.

## Cose che la QA dovrebbe guardare per prime

1. La migration FIX-01 per intero: porte definer (A03/Q01), trigger `merge_state_check`, `canonical_insert_guard`, impronta (`promotion_logic_fingerprint` hasha anche `prosecdef/proconfig`).
2. Se un proprietario può approvare una regola e poi cambiare una funzione **non** inclusa nell'impronta (elenco in `promotion_logic_fingerprint`): per progetto l'impronta copre le funzioni di promozione e le loro guardie, non l'intero schema.
3. `merge_canonical_entity` con più lock (promozione prende `catalog.promote`+`catalog.import`; fusione `catalog.merge:<tipo>`): ordine coerente, nessun ciclo di attese noto.
4. `connectCloud`: `reserve()` di Bun e `SET ROLE` col pooler Supavisor in modalità sessione — non provato col pooler reale.
5. Il monitor WAL usa la connessione senza `SET ROLE` perché `pg_cancel_backend` richiede i privilegi del ruolo di sessione del backend bersaglio: da confermare su Supabase.

## Debiti e limiti noti

- Le funzioni `search_wines`/`wine_sheet` e la vista `wine_resolution` (ricorsiva su tutti i vini) non sono state ottimizzate né misurate a 212.894 record.
- `promotion_preview`/`promotion_candidates` calcolano `producer_final` per riga su ~200k record: costo non misurato (nessun benchmark massivo).
- `approved_view_digest` dipende da `pg_get_viewdef` (stabile entro una versione maggiore di PostgreSQL): un upgrade maggiore invalida l'approvazione (fail-closed, serve riapprovare).
- Doppia scrittura al primo import (WAL ≈ 2×) e `finish_import_run` a 212.894 record mai misurati (invariati).

## Vietato senza nuova autorizzazione

Import LWIN (cloud o locale massivo); attivare o approvare la promozione; impostare `CATALOG_PRODUCTION_APPROVAL`; creare ambienti/branch/progetti Supabase; distribuire le migration in Production; aprire PR o fare merge (Preview a pagamento / migration su Production); fusioni automatiche; cancellare dati. Vedi `RELEASE_STRATEGY_WI_001C.md`.
