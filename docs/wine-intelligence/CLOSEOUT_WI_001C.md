# WI-001C — chiusura della fase di sviluppo (20 novembre 2026)

Documento di chiusura senza costi. Nessun branch Supabase, environment GitHub, segreto o variabile creati; nessun import LWIN; nessuna migration; Production invariata. Il lavoro è sospeso, non abbandonato: tutto ciò che serve per riprendere è conservato.

## Stato effettivo

| Componente | Stato |
|---|---|
| WI-001A, importatore locale LWIN | **Completato** (PR #298) |
| WI-001B, schema `catalog` di staging | **Distribuito** in Production (PR #300, ledger `20261117120000`), nessun dato |
| WI-001C Rilascio A, runner cloud | **Mergiato** (PR #301, `f579203`), CI verde; handoff PR #302 (`2d92790`), CI verde |
| WI-001C Rilascio B, catalogo canonico | **Integrato su `origin/main` `2ad23f7` nel branch `feature/wi-001c-unified-completion`** (4 migration invariate, griglie `12zy`/`12zz`, allow-list `12zs`); non ancora mergiato né distribuito. Applicazione fuori ordine verificata in locale: vedi `CLOUD_IMPORT_RUNBOOK.md` |
| Importazione LWIN reale | **Rinviata** |
| Validazione Supavisor/TLS reale | **Rinviata** (il runner non è provato su un pooler né su una CA reali) |
| Risorse a pagamento | **Nessuna autorizzata** |
| Workflow `wine-catalog-cloud-import.yml` | **Disabilitato** (variabile `CATALOG_CLOUD_IMPORT_ENABLED` assente, environment assente, nessuna esecuzione) |

Verifiche in sola lettura del 20 novembre 2026: `origin/main` `2d92790`, check verdi; Supabase `pijnmcllmfgjmgsvtcej` con il solo branch `main`, ledger fino a `20261117120000`; environment GitHub solo `production-backup` e `production-payouts`; nessuna variabile `CATALOG_*`.

## Cosa è conservato

- Rami remoti, da non eliminare: `release/wi-001c-runner-a` (`84f444c`, già in `main`) e `feature/wi-001c-canonical-catalog` (`7ff54be`, 11 commit sopra la base `d66a01e`).
- Migration del Rilascio B, **solo sul ramo**: `20261119100000_wi_001c_canonical_catalog`, `20261119120000_wi_001c_fix01_canonical_hardening`, `20261119140000_wi_001c_fix02_audit_hardening`, `20261119150000_wi_001c_fix02_fingerprint_guards`, con le griglie `supabase/tests/12zs`, `12zy`, `12zz`.
- Documenti in `main`: `CLOUD_IMPORT_RUNBOOK.md`, `RELEASE_STRATEGY_WI_001C.md`, `STAGING_HANDOFF_WI_001C.md`, `IMPORT_MANIFEST.json`, `SOURCE_REGISTRY.md`. Handoff FIX-02 e FIX-03 sono sul ramo del Rilascio B.
- File LWIN originale (SHA-256 `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`, 212.894 record): **non è nel repository**; il founder deve conservarlo.

## Come riprendere

1. **Staging (Rilascio A).** Il founder autorizza per iscritto un branch Supabase temporaneo con tetto di costo e data di cancellazione. Quotazione del 20 novembre 2026: $0,01344/ora, da riverificare con `get_cost`. Poi eseguire `STAGING_HANDOFF_WI_001C.md`: environment `catalog-cloud-import` con revisore e policy solo `main`, login dedicato, CA e URL `verify-full`, prove Supavisor e `pg_cancel_backend`, dry-run, import, V01-V09, seconda esecuzione, chiusura e controllo del costo.
2. **Rilascio B.** Solo dopo un import verificato e con approvazione del founder: rebase di `feature/wi-001c-canonical-catalog` su `origin/main`, nuova CI e DB regression, merge in una PR dedicata, poi rilettura del ledger Production. Le regole canoniche non sono approvate.
3. Il workflow resta disabilitato finché i punti dell'handoff non sono tutti soddisfatti.

## Verifica post-applicazione (Production, dopo il merge)

In sola lettura. Attesi: le 4 versioni `20261119100000`, `20261119120000`, `20261119140000`, `20261119150000` nel ledger con il nome del file; nessun grant su schema `catalog` ai ruoli `anon`/`authenticated`/`service_role`; RLS attiva su ogni tabella `catalog`; le 15 funzioni `SECURITY DEFINER` del catalogo senza `EXECUTE` per i ruoli API e con `search_path` vuoto; regola `lwin-conservative-v1` ancora in stato `draft` (nessuna promozione); `catalog.promotion_logic_fingerprint('lwin-conservative-v1')` valorizzata.
