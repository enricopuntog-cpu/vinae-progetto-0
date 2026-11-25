# WI-001C — chiusura della fase di sviluppo (20 novembre 2026)

Documento nato il 20 novembre 2026 come chiusura senza costi: in quel momento nessun branch Supabase, environment GitHub, segreto o variabile erano stati creati, nessun import LWIN eseguito, nessuna migration applicata, Production invariata. **Il 21 novembre 2026 è stato poi eseguito e distrutto un unico staging** (vedi la sezione seguente, che prevale sulle frasi dello stato iniziale); Production è rimasta invariata. Le sezioni «Stato effettivo» e «Come riprendere» descrivono lo stato del 20 novembre, aggiornato dove indicato.

## Aggiornamento del 21 novembre 2026 (staging reale e prova locale)

Un'unica Preview (`qhdvnkqwqggnkwhvczeo`, ≈12 minuti, ≈$0,003, **eliminata e verificata**; Production invariata a `20261120120000`).

- **Provato sul cloud reale, via Session Pooler**: migration applicate in ordine dall'integrazione; login dedicato con audit conforme; TLS `verify-full` con CA; dry-run del file reale (212.894 record, 0 scartati); `pg_cancel_backend` dal pooler con SQLSTATE `57014`; RLS 25/25, nessun grant né EXECUTE ai ruoli API, 15 SECURITY DEFINER con `search_path` vuoto, regola in `draft`, 0 vini canonici.
- **Difetti reali trovati e corretti nella PR #310**: (1) `assertCloudSession` leggeva `pg_stat_ssl` che dietro Supavisor descrive il tratto pooler→PostgreSQL: ora la diretta è invariata e il pooler richiede il TLS verificato attestato dal driver più il login effettivo, con il tratto interno `not_proven` quando non provato; (2) la sonda `pg_stat_activity` filtrava per `application_name`, che Supavisor riscrive in `Supavisor`: ora pid + login. Il cluster del pooler cambia per progetto (`aws-0` o `aws-1`): provare entrambi prima dell'import.
- **Import cloud NON completato nella Preview** (poi ESEGUITO in Production il 25 novembre 2026, vedi `CLOUD_IMPORT_RUNBOOK.md`): nel finish il disco della Preview si è esaurito (`No space left on device` su `pg_wal`), con crash recovery e rollback completo; nulla è stato promosso, il run è rimasto `running` e la Preview è stata eliminata. Il runner non controlla la capienza del disco: prima di Production verificare lo spazio libero (peso osservato: `source_records` 640 MB, WAL ≈1 GB, più lo staging).
- **Prova sostitutiva locale** (stesse migration, stesso runner, file reale): 212.894 record in 517 s, V01–V09 tutte OK, seconda esecuzione `skipped`, `catalog.wines` 0, `public.wines` invariata, regola `draft`, 130 rilievi aperti e nessuna fusione.
- **Non provato**: import completo sul cloud, workflow GitHub (gira solo da `main`), cifratura interna Supavisor→PostgreSQL (SSL enforcement non impostabile da qui), fabbisogno di disco in Production.

## Stato effettivo

| Componente | Stato |
|---|---|
| WI-001A, importatore locale LWIN | **Completato** (PR #298) |
| WI-001B, schema `catalog` di staging | **Distribuito** in Production (PR #300, ledger `20261117120000`), nessun dato |
| WI-001C Rilascio A, runner cloud | **Mergiato** (PR #301, `f579203`), CI verde; handoff PR #302 (`2d92790`), CI verde |
| WI-001C Rilascio B, catalogo canonico | **Integrato su `origin/main` `2ad23f7` nel branch `feature/wi-001c-unified-completion`** (4 migration invariate, griglie `12zy`/`12zz`, allow-list `12zs`); non ancora mergiato né distribuito. Applicazione fuori ordine verificata in locale: vedi `CLOUD_IMPORT_RUNBOOK.md` |
| Importazione LWIN reale | **Provata in locale** (212.894 record, V01–V09 OK, idempotente); sul cloud **non completata** (disco); Production **non eseguita** |
| Validazione Supavisor/TLS reale | **Eseguita** il 21 novembre 2026 su Preview (pooler, CA, dry-run, annullamento); import completo non riuscito per disco esaurito (vedi sopra) |
| Risorse a pagamento | **Nessuna autorizzata** |
| Workflow `wine-catalog-cloud-import.yml` | **Disabilitato** (variabile `CATALOG_CLOUD_IMPORT_ENABLED` assente, environment assente, nessuna esecuzione) |

Verifiche in sola lettura del 20 novembre 2026: `origin/main` `2d92790`, check verdi; Supabase `pijnmcllmfgjmgsvtcej` con il solo branch `main`, ledger fino a `20261117120000`; environment GitHub solo `production-backup` e `production-payouts`; nessuna variabile `CATALOG_*`.

## Cosa è conservato

- *Storico:* rami remoti, da non eliminare (il riferimento operativo corrente è la PR #310): `release/wi-001c-runner-a` (`84f444c`, già in `main`) e `feature/wi-001c-canonical-catalog` (`7ff54be`, 11 commit sopra la base `d66a01e`).
- Migration del Rilascio B, **solo sul ramo**: `20261119100000_wi_001c_canonical_catalog`, `20261119120000_wi_001c_fix01_canonical_hardening`, `20261119140000_wi_001c_fix02_audit_hardening`, `20261119150000_wi_001c_fix02_fingerprint_guards`, con le griglie `supabase/tests/12zs`, `12zy`, `12zz`.
- Documenti in `main`: `CLOUD_IMPORT_RUNBOOK.md`, `RELEASE_STRATEGY_WI_001C.md`, `STAGING_HANDOFF_WI_001C.md`, `IMPORT_MANIFEST.json`, `SOURCE_REGISTRY.md`. Handoff FIX-02 e FIX-03 sono sul ramo del Rilascio B.
- File LWIN originale (SHA-256 `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e`, 212.894 record): **non è nel repository**; il founder deve conservarlo.

## Come riprendere

1. **Staging (Rilascio A).** *Eseguito il 21 novembre 2026 (vedi sopra); non ripetere una Preview identica: serve prima il gate disco del runbook.* Procedura originale: il founder autorizza per iscritto un branch Supabase temporaneo con tetto di costo e data di cancellazione. Quotazione del 20 novembre 2026: $0,01344/ora, da riverificare con `get_cost`. Poi eseguire `STAGING_HANDOFF_WI_001C.md`: environment `catalog-cloud-import` con revisore e policy solo `main`, login dedicato, CA e URL `verify-full`, prove Supavisor e `pg_cancel_backend`, dry-run, import, V01-V09, seconda esecuzione, chiusura e controllo del costo.
2. **Rilascio B.** *(Storico: superato dalla PR #310, che integra le 4 migration su `origin/main`; restano il gate di merge e quello di import.)* Procedura originale: solo dopo un import verificato e con approvazione del founder: rebase di `feature/wi-001c-canonical-catalog` su `origin/main`, nuova CI e DB regression, merge in una PR dedicata, poi rilettura del ledger Production. Le regole canoniche non sono approvate.
3. Il workflow resta disabilitato finché i punti dell'handoff non sono tutti soddisfatti.

## Verifica post-applicazione (Production, dopo il merge)

In sola lettura. Attesi: le 4 versioni `20261119100000`, `20261119120000`, `20261119140000`, `20261119150000` nel ledger con il nome del file; nessun grant su schema `catalog` ai ruoli `anon`/`authenticated`/`service_role`; RLS attiva su ogni tabella `catalog`; le 15 funzioni `SECURITY DEFINER` del catalogo senza `EXECUTE` per i ruoli API e con `search_path` vuoto; regola `lwin-conservative-v1` ancora in stato `draft` (nessuna promozione); `catalog.promotion_logic_fingerprint('lwin-conservative-v1')` valorizzata.
