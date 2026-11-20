# WI-001C — handoff per il primo staging cloud reale

Stato: Rilascio A in `main` (merge `f579203`). Nessuna risorsa creata, nessun segreto, nessun import. Ogni voce sotto richiede l'autorizzazione specifica del founder. Il test iniziale usa solo WI-001B (già in Production): il runner non richiede le migration del catalogo canonico (Rilascio B).

> **Aggiornamento del 20 novembre 2026:** i passi di questo documento sono differiti, nessuna risorsa è stata creata. Stato e ripresa in `CLOSEOUT_WI_001C.md`.

1. **Environment GitHub `catalog-cloud-import`**: revisori obbligatori, deployment branch policy limitata a `main`, nessun bypass. Segreti solo qui: `CATALOG_DATABASE_URL`, `CATALOG_DB_CA_PEM`, `CATALOG_INPUT_URL`.
2. **Supabase temporaneo**: preferire un branch (non un progetto separato) salvo limite tecnico dimostrato; prima di crearlo `get_cost` e `confirm_cost`, tetto di costo e data di cancellazione approvati. Il branch parte con le migration di `main` fino a WI-001B. Nessuna migration WI-001C.
3. **Login dedicato**: login PostgreSQL membro del solo ruolo `catalog_loader`, nessun privilegio su `catalog.wines` né su `public`; il caricatore lo verifica e rifiuta altrimenti.
4. **TLS/CA e pooler**: `sslmode=verify-full`, CA pubblica del progetto in `CATALOG_DB_CA_PEM`; provare connessione diretta e Supavisor (sessione), perché il runner non è provato su Supavisor reale.
5. **Fonte LWIN privata**: URL firmato a breve scadenza; SHA-256 atteso `7669ceab4e815716aa6c90643c117f3da7c7daeaa202ecd3f7cfbc4db7fd488e` (workflow e `IMPORT_MANIFEST.json`).
6. **Prove reali prima dell'import**: SQLSTATE affidabile e `pg_cancel_backend` su una sessione di prova; comportamento del finish con connessione persa.
7. **Attivazione**: solo dopo i punti 1-6 impostare `CATALOG_CLOUD_IMPORT_ENABLED=true`, poi `workflow_dispatch` da `main` con `mode=dry-run` (sola lettura), esame del report.
8. **Import reale** dei 212.894 record (`mode=import`), verifiche V01-V09 dal runbook.
9. **Seconda esecuzione idempotente**: nessuna riga nuova, stessi conteggi e `state_digest`.
10. **Chiusura**: variabile riportata a non-true, branch eliminato, controllo dei costi, artefatto del report conservato (solo conteggi).

Riferimenti: `CLOUD_IMPORT_RUNBOOK.md`, `RELEASE_STRATEGY_WI_001C.md`, `HANDOFF_WI_001C_FIX03.md`.
