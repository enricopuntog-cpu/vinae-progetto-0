# WI-001C-FIX-03 — handoff (19 novembre 2026)

> **STORICO (21 novembre 2026).** Il ramo `feature/wi-001c-canonical-catalog` citato qui è stato superato: il riferimento operativo corrente è la **PR #310** (`feature/wi-001c-unified-completion`, 4 migration congelate integrate su `origin/main`). Il vecchio ramo resta solo come archivio; non è la prossima strada operativa. Stato aggiornato in `CLOSEOUT_WI_001C.md`.

Documento autosufficiente. Nessun segreto. Nessun import LWIN reale, nessuna PR, nessun merge, nessun progetto/branch Supabase creato, nessuna migration (nessun file in `supabase/` nel runner), nessuna scrittura in Production, nessuna spesa. Il runner **non è verificato su Supavisor reale**: quelle prove sono successive e richiedono lo staging autorizzato.

## 1. Stato

FIX-03 chiude i cinque P2 e il P3 emersi da WI-001C-QA-FIX-02 sul runner (`tools/wine-catalog/`). Rami: `release/wi-001c-runner-a` (Rilascio A) e `feature/wi-001c-canonical-catalog` (Rilascio B, stessi file del runner byte-per-byte). SHA nel `CHANGES.log` e nel messaggio di consegna.

## 2. Correzioni

| ID | Problema | Correzione | Dove |
|---|---|---|---|
| R1 | errore o `finish_unknown` perdevano gli identificativi per riconciliare | `run_id`, `source_code`, `file_sha256`, `file_name`, `backend_pid` propagati (hook `onIdentity`, `error.runIdentity`), in `cloud.run_identity` del report (anche `mode: error`) e in `finish_outcome.reconcile`; valori solo nella forma attesa (`sanitizeRunIdentity`), nessuna credenziale; disponibili anche dopo `begin_import_run` e prima del finish; senza `run_id` (begin senza risposta) il blocco indica come cercare il tentativo. Il rimando del runbook ora punta a una sezione che esiste («Esito incerto del finish») | `load.mjs`, `cloud-guards.mjs`, `cloud-outcome.mjs`, runbook |
| R2 | un errore client poteva valere «rollback già avvenuto» | `lib/finish-error.mjs`: «fallito» solo con errore del server con SQLSTATE affidabile (Bun: `errno` con `code = ERR_POSTGRES_SERVER_ERROR`; `sqlState`) su sessione integra; classi `08`, `57P01-05`, `58`, `XX`, errori senza SQLSTATE, errori driver/decodifica/rete, scadenze → **unknown**: niente `fail_import_run` (la funzione WI-001B cancella i finding a prescindere dallo stato terminale), niente cancellazioni, niente rollback dichiarato, niente ripetizione; la sessione cloud con esito incerto è marcata non riutilizzabile. `57014` = interruzione riportata dal server (statement_timeout **o** `pg_cancel_backend` di chiunque): rollback noto se la sessione è integra, «annullato dal monitor» solo se il monitor ha una richiesta riuscita | `finish-error.mjs`, `load.mjs` |
| R3 | nessuna scadenza lato client | finish: `--finish-timeout-min` + 60 s; verifica 120 s; conclusione 90 s (stop monitor, sonde, misura WAL); lettura finale del WAL 10 s; controlli di sessione 15 s. `withDeadline` ferma l'**attesa**, non la query: scadenza ⇒ esito `finish_unknown` (`deadline_expired`), nessun secondo finish, nessun annullamento dichiarato, sessione non riusata (misura via monitor). I limiti dei lotti si ripristinano solo se la sessione è integra | `cloud-guards.mjs`, `cloud-outcome.mjs` |
| R4 | `monitor.stop()` che lancia faceva sparire lo stato del monitor | `safeStopMonitor`: stato `lost` + `stop_failed`, `monitor_lost`, exit 1, report sempre scritto (nel `finally` e in `concludeFinish`/`settleCloudRun`) | `cloud-guards.mjs`, `cloud-outcome.mjs`, `lwin-load.mjs` |
| R5 | verifica post-commit non eseguita poteva lasciare `ok:true` | verifica obbligatoria dopo il commit: `verification_not_run` / `verification_failed` (lanciata, scaduta, risultato non valido); `finish_outcome.states` separa `database` / `verification` / `monitor` / `overall`; exit ≠ 0 | `cloud-guards.mjs`, `cloud-outcome.mjs` |
| R6 | `x$q$; reset role;` apriva una stringa a dollaro | `$` dopo un carattere d'identificativo (lettere, cifre, `_`, `$`, non ASCII) non apre una stringa; `assertCallerSql` estratta ed esportata per le prove; whitelist del monitor e protezioni server-side invariate (il parser client è difesa in profondità) | `sql-scan.mjs`, `db-bun.mjs` |

## 3. Prove

Vedi `CHANGES.log`. `test/fix03.test.mjs` (26 test): R1 connessione persa con identificativi, errore prima del begin, sanificazione, sezione del runbook; R2 errore senza SQLSTATE → unknown e nessuna chiamata a `fail_import_run`, matrice SQLSTATE, 23505 → failed; R3 scadenza del finish senza falsa garanzia di annullamento, margine, conclusione con scadenza, limiti ripristinati solo a sessione integra; R4 commit + WAL entro budget + `stop()` che lancia → `monitor_lost`, exit 1, report salvato su file; R5 verifica non eseguita/lanciata/scaduta/non valida; R6 positivi e negativi del filtro SQL.

## 4. Limiti noti (non risolti qui)

- `errno` come SQLSTATE di Bun.SQL è dedotto dalla documentazione/prove locali, **non misurato su un errore reale del pooler Supavisor**; `pg_cancel_backend` e `pg_stat_activity.application_name` dal pooler idem.
- Una scadenza JavaScript non annulla la query: se scade, il backend può ancora confermare. Per questo l'esito è sconosciuto e va riconciliato (runbook).
- Locale (senza `db.state`): errore del finish = «fallito» (regola storica, database di prova).
- Il filtro lessicale non è un parser SQL completo: la barriera vera resta il database.

## 5. Da fare dopo (richiede approvazione)

1. Aprire la PR del Rilascio A (`release/wi-001c-runner-a` → `main`), CI completa `ci.yml` sulla testa esatta, merge squash (admin solo a check verdi).
2. Prove sul Supabase branch reale autorizzato (TLS/CA verso il pooler, SQLSTATE reali, `pg_cancel_backend`, WAL del finish).
3. Solo dopo, decisione sul Rilascio B e sull'import dei 212.894 record.

## 6. Revisione interna (subagenti in sola lettura) e rilievi applicati

`vinea-security-auditor` e `vinea-code-reviewer` hanno letto il diff; nessun P0/P1. Rilievi applicati: tag `$…$` non ASCII e senza limite di lunghezza; commento `--` chiuso anche da `\r`; `$` non riconosciuto rifiutato (fail-closed); `E'…'` coerente con gli identificativi; SQLSTATE `40003`, `25P03`, severità FATAL/PANIC e codici Node come `E2BIG` non provano più un rollback; testo persistito da `fail_import_run` = testo fisso + SQLSTATE (non il messaggio del driver) e `failMarked` dichiara se la chiamata è riuscita; `walGuard.report()` segnala `unavailable`/`stale`; la scadenza del ripristino dei limiti rende la sessione incerta e salta la verifica; identità annunciata prima del controllo sha256; runbook allineato. Non applicato: elenco chiuso di testi per le query del caricatore (il filtro resta difesa in profondità, la barriera è il ruolo) e un test del flusso CLI end-to-end con `db` finto (il cablaggio è coperto dalle funzioni di `cloud-outcome.mjs` e da asserzioni sul sorgente).
