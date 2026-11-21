# WI-001C-FIX-02 — handoff (19 novembre 2026)

> **STORICO (21 novembre 2026).** Il ramo `feature/wi-001c-canonical-catalog` citato qui è stato superato: il riferimento operativo corrente è la **PR #310** (`feature/wi-001c-unified-completion`, 4 migration congelate integrate su `origin/main`). Il vecchio ramo resta solo come archivio; non è la prossima strada operativa. Stato aggiornato in `CLOSEOUT_WI_001C.md`.

Documento autosufficiente. Non contiene segreti. Nessun import LWIN reale, nessuna PR, nessun merge, nessun progetto/branch Supabase creato, nessuna migration in Production, nessuna spesa.

## 1. Stato

FIX-02 **completato** su due rami remoti (nessun force push, PR NON aperta):

| Ramo | Contenuto | SHA |
|---|---|---|
| `release/wi-001c-runner-a` (Rilascio A, nessun file in `supabase/`) | fix P1 WAL + confini SQL del runner | vedi `git log` (commit «WI-001C-FIX-02 P1 WAL»: `cbbcada` + commit docs) |
| `feature/wi-001c-canonical-catalog` (Rilascio B) | stessi file del runner (byte-per-byte identici) + migration `20261119140000` + griglia 12zy sezione R | vedi `git log` |

I moduli cloud condivisi (`tools/wine-catalog/lib/{cloud-guards,db-bun,load,sql-scan,cloud-tls,cloud-target}.mjs`, `lwin-load.mjs`) sono identici nei due rami (verificato con sha1 sul commit di cherry-pick).

## 2. Blocco A — runner

**P1 originale**: `finish_import_run` poteva concludersi tra due campioni del monitor; con 400 MB di WAL su un budget di 100 MB il programma usciva con codice 0.

Correzione (`lib/cloud-guards.mjs`, `lib/load.mjs`, `lwin-load.mjs`):

- `concludeFinish`: ferma il monitor (attende un campione in volo, con scadenza), riconcilia se la connessione principale è caduta e **misura il WAL a fine finish** (connessione principale, poi monitor). La misura è monotona: vale più di qualunque campione.
- `finalizeWal` (funzione pura) e `buildFinishOutcome` (conclusione assente = fail-closed): esiti `within_budget`, `cancelled_before_commit`, `over_budget_after_commit`, `monitor_lost`, `finish_unknown` (+ `failed_before_commit` per un finish fallito per altra causa). **Solo `within_budget` senza altre anomalie vale successo (exit 0)**. Il report contiene `finish_outcome` (outcome, failure_reasons, byte misurati, budget, stato DB noto, incertezza residua, prossima azione). Nessun «Caricamento completato» quando l'esito è anomalo.
- Commit già avvenuto: nessun `fail_import_run`, nessun rollback dichiarato, nessuna cancellazione. Esito sconosciuto (connessione persa): nessun `fail_import_run`.
- Monitor: scadenza per query, `stop()` asincrono, campione tardivo registrato ma senza annullamenti, tetto ai tentativi di annullamento (5), `cancelRequested` solo se `pg_cancel_backend` risponde true, `start()` rifiutato senza misura iniziale, riconnessione della sola connessione monitor, sonda `pg_stat_activity` (≤ 4) per la connessione principale persa.
- Confini SQL: il monitor accetta solo 4 testi esatti (`MONITOR_SQL_ALLOWED`); `setLimits` accetta solo il testo costante dei timeout; la sessione del caricatore ammette solo SELECT/WITH/VALUES senza DML diretto né `set_config`; il filtro legge i letterali (`lib/sql-scan.mjs`: stringhe, `E''`, `$$`, commenti annidati; testo non chiuso = rifiuto). La barriera vera resta il database (login dedicato, audit transitivo, ruolo `catalog_loader`).
- Preservati: TLS verify-full con CA, identificazione destinazione, Production rifiutata, login dedicato, audit transitivo, sessione principale riservata e mai riconnessa, dry-run di sola lettura, segreti mascherati (messaggi di errore del driver non finiscono nel report).

Prove (deterministiche, timer finti, fixture di due righe): `test/wal-fix02.test.mjs` (21 test) — scenario 400/100 MB (esito `over_budget_after_commit`, `samples = 1`, exit 1), finish rapido entro budget, annullamento prima del commit, annullamento dopo il commit, monitor bloccato, connessione persa, `pg_cancel_backend` = false, campione in volo durante `stop()`, verifica conclusiva fallita, secondo tentativo idempotente (`skipped`), conclusione assente, `beforeFinish` che lancia.

## 3. Blocco B — catalogo (migration `20261119140000_wi_001c_fix02_audit_hardening.sql`, additiva)

- **B1 (D-6 residuo)**: `detect_duplicate_candidates(integer)` era una porta SECURITY DEFINER eseguibile dal curatore che scriveva candidati senza esecutore né evento. Eliminata; al suo posto `detect_duplicate_candidates_internal(integer, text)` **senza EXECUTE a nessun ruolo**, chiamata solo da `promote_wine_candidates`, il cui evento ora include `duplicates`; i candidati riportano `detected_by = promotion:<esecutore>`. Nessuna fusione automatica. L'impronta della logica (`promotion_logic_fingerprint`) segue la nuova firma: **una regola approvata prima di questa migration non abiliterebbe più nulla** (oggi nessuna regola è approvata).
- **B2**: `catalog.surface_audit()` deriva dal catalogo di sistema la classe di OGNI funzione (porta del curatore / lettura / porta del caricatore / interna) e ne verifica le regole (definer + search_path vuoto + esecutore + evento nel corpo per le porte; letture invoker non volatili; interne non eseguibili; nessun accesso PUBLIC/anon/authenticated/service_role; elenco di eccezioni motivate, oggi vuoto). La griglia (A03, Q01, Q08) non usa più elenchi fissi; Q08 verifica un evento proprio **per ogni porta ricavata dal catalogo**. R05 crea una porta difettosa e prova che il controllo la rifiuta (il difetto originale).
- **B3**: produttori già fusi — rilevamento dei candidati e validazione della fusione dei vini usano il produttore effettivo (`producer_final`); i produttori originali restano nel dettaglio del candidato (`via_merged_producer`, `producer_a/b`); `wines.producer_id` non viene riscritto. Controllo negativo: due produttori distinti non fusi non rendono fondibili i loro vini.
- **B4**: nuove annate/formati/rivendicazioni/collegamenti solo su bersagli attivi (trigger `zz_fix02_target_active`); alias `combined_lwin` solo se verificati da un collegamento Combined attivo di fonte (la promozione resta ammessa); TRUNCATE rifiutato su `canonical_events` e `promotion_exceptions` (il trigger non impedisce DROP TRIGGER né un superuser: nessuna garanzia oltre questo). NON coperti da trigger TRUNCATE: `entity_aliases`, `attribute_claims`, `wine_links` e i registri di staging WI-001B (`source_record_events`, `import_findings`): i ruoli applicativi non hanno comunque TRUNCATE (R25), il proprietario sì. Provenienza: `detected_by` + dettaglio dei candidati + `duplicates` nell'evento di promozione.

### Seconda migration `20261119150000_wi_001c_fix02_fingerprint_guards.sql`

La prima migration era già pubblicata (congelata): la revisione interna ha chiesto che l'impronta della logica di promozione copra anche `fix02_combined_alias_guard`, `fix02_target_active_guard` ed `entity_merges_insert_guard`; la correzione è in questa migration successiva (cambia di nuovo l'impronta; nessuna regola è approvata). Limite noto di `surface_audit`: il controllo dell'esecutore/evento è testuale sul corpo della funzione (`LIKE`), quindi un commento che contiene `record_canonical_event(` lo soddisferebbe; lo compensa Q08 (evento reale per ogni porta esercitata dalla griglia: una porta nuova non provata fa fallire Q08).

## 4. Gate documentati (NON sviluppati ora)

- **Separazione proponente/revisore** e **login per operatore**: richiesti prima della **curazione reale**, non per l'import WI-001B/C. Oggi `p_actor`/`p_reviewer` sono testo; l'identità effettiva è in `db_user`/`acting_role`.

## 5. Verifiche eseguite

Vedi il report finale nel `CHANGES.log` e nel messaggio di consegna: Node (importatore), Bun TLS (10/10, nessun salto), workflow security (nelle regole `cloud.test`), CI «Supabase DB regression» sul ramo catalogo (URL/SHA/conteggi nel `CHANGES.log`).

## 6. Da fare ancora (non eseguibile qui)

- CI completa `ci.yml` (richiede PR o push su `main`): non aperta; resta da verificare nel Rilascio A.
- Prove sul Supabase branch reale: TLS/CA verso il pooler reale, `pg_cancel_backend` e `pg_stat_activity.application_name` dal pooler (Supavisor), comportamento di Bun.SQL su errori reali (`errno`/SQLSTATE `57014`), misura del WAL reale del finish (la stima 8 KiB/riga è euristica), `track_functions`/privilegi del login dedicato.
- QA Opus HIGH limitata al nuovo diff: `git diff 2f1377f..cbbcada -- tools docs` (runner) e `git diff f24b31c..HEAD -- supabase` (catalogo).
