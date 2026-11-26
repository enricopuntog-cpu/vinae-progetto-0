# WI-015 — delta per l'audit indipendente di attivazione

Passaggio di consegne scritto dalla sessione di build: **non è un audit** e non certifica nulla. L'audit lo esegue una
sessione indipendente. Non ripetere WI-001→WI-008, l'import LWIN né le prove già verdi sullo stesso SHA senza un motivo
concreto. Findings di partenza: [`WI-009-014-RELEASE-AUDIT.md`](WI-009-014-RELEASE-AUDIT.md).

## 1. Delta

| | |
|---|---|
| Base | `7cbc79b9844e6807c6dbf2cc4fbaccae8b209fa4` (ledger 136) |
| Codice da rivalidare | `7cbc79b..6602fbb18ba959f8629eca777e315cf1b1d07dc0`: 65 file, +5522 −198 |
| Commit | `ac3012c` (#325, WI-015A, testa provata `a25d859`), `6602fbb` (#326, WI-015B, testa provata `1368c23`, stesso albero di `6602fbb`) |
| Migration | `20261129100000_wi_015a_finding_audit.sql`, `20261129110000_wi_015b_operazioni_autonome.sql` (congelate) |
| Fuori dalle migration | `tools/company-brain/`, `tools/wine-catalog/promozione/` (`00`, `02`, `03`), `supabase/functions/` (`_shared/ai-gate.ts`, `_shared/ai-provider.ts`, le tre function AI), `.github/` (ambito del gate DB, heartbeat, `offsite-backup-freshness`, soglia test), `frontend-next/` |

La PR di chiusura successiva cambia solo documentazione.

Production dopo #326 (sola lettura, 26/11/2026 23:06 UTC): ledger 138; corpo di **56 funzioni su 56** definite dalle due
migration identico al sorgente di `main` (`md5(prosrc)`); impronta `64e038526a78f44070a54498fd0ff607` e digest
`b352be426a3a32762fb7fa5140b7ee88` invariati; RLS attiva e nessun privilegio di `anon`, `authenticated`,
`service_role` e dei ruoli brain sulle 14 tabelle controllate (nuove e collegate); `ai_budget_*` eseguibili dal solo
`service_role`; ruoli `brain_*` e `catalog_import_login` `NOLOGIN`.

## 2. Aree da verificare

| Area | Domanda per l'auditor | Dove guardare | Evidenza esistente | Non provato / da attaccare |
|---|---|---|---|---|
| Identità reale degli agenti | la sola credenziale determina l'identità? un login con più appartenenze o attributi passa? | `brain.current_agent`, `role_is_least_privilege`, `agents_identity_guard`, `agente/registra.sql` | `wi015_identita_concorrenza.sh` (due login veri) | login dietro il pooler Supabase; membership `ADMIN` di `postgres` sui ruoli `brain_*` (documentata) |
| Accessi incrociati e lease | un agente può leggere, scrivere, rinnovare o chiudere un task altrui conoscendo id e token? | `lease_task`, `*_core`, `agent_context`, `renew_lease`, `disable_agent` | stessa prova + `wi015b_operazioni.sql`, `wi015_operazioni.sh` | revoca con connessioni aperte dal pooler |
| Approvazione ≠ esecuzione | `approvato` può eseguire qualcosa o saltare la conferma? | `azienda_admin_task_decidi`, vincolo `requires_approval`, `close_if_allowed` | `wi015a_finding_audit.sql` | ADM-01 (nessuna MFA admin) |
| Conflitti nativi/LWIN | un nativo può nascere o restare duplicato durante un lotto? | `catalog.add_manual_wine`, `lwin_native_conflicts`, `catalogo_admin_distingui_lwin`, `02`/`03` | griglia A + banco `concorrenza.sh` (T15) | catalogo popolato; delta su una versione LWIN nuova |
| Concorrenza delle proposte | ritiro, decisione, invio e cancellazione account mantengono contatore e stato? | ordine di lock, trigger `contribution_submissions_removed` | `wi015_identita_concorrenza.sh`, `wi011_concorrenza.sh` | carico oltre le sessioni provate |
| Privacy e revoca | campi in più, dati personali nei payload, legami utente dopo revoca o cancellazione | `catalogo_proponi`, `payload_ammesso`, `agent_context_core`, `minimize_decided_submissions`, `lib/cantina/proposta-catalogo.ts` | griglie WI-011, A e B | periodo di conservazione non scelto; nessun TTL per eventi, task, segnali, `ai_chiamate` |
| Acquisizione affidabile | che cosa si perde, e quando? | `useSellWizard`, `harvest_listings`, `intake_failures` | test client e griglia B | **limite aperto**: nessun recupero persistente ([`WI_011` §12](../wine-intelligence/WI_011_LIVING_CATALOG.md)) |
| Scheduler | sovrapposizione, arretrato, ritentativi, sospensione, falso «pianificato» | `scheduler_tick`, `run_job`, `scheduler_status`, `sentinel_status`, `scheduler/*.sql` | griglia B; `wi015_operazioni.sh` con `pg_cron` vero | Supabase ospitato; osservatore indipendente non scelto |
| Autenticazione dei mittenti | chi può inviare segnali? replay, ordine, volume | `ingest_signal`, `ingest_signal_core`, `segnale.mjs`, `lib/connessione.mjs` | griglia B; login vero in `wi015_operazioni.sh` | nessuna fonte collegata; login di sola lettura del monitor mai usato con una connessione vera |
| Escalation Sentinel | un P0/P1 può restare soppresso? doppio task? il verde chiude? | `report_anomaly`, `sentinel_run`, `sentinel_checks`, `technical-heartbeat.mjs` | griglie A e B, test dell'heartbeat | notifiche esterne assenti |
| Prenotazione e consuntivo AI | un tetto si supera? chi apre l'interruttore? | `ai_budget_prenota`/`consuntivo`/`stato`, `ai-gate.ts`, `ai-provider.ts` | griglia B, `sommelier-edge.test.ts`, `wi004_sommelier_postgrest.sh` | rischi residui in [`COMPANY_BRAIN` §7.1](../COMPANY_BRAIN.md); nessun fornitore vero |
| Privilegi e feature flag | nuove porte eseguibili da chi non deve; interruttori fail-closed | ACL delle due migration, `catalog.surface_audit`, `12zs`, `12zy`, flag delle Edge Function | gate DB; Production: 0 violazioni; 503 dalle tre function AI, da checkout e onboarding con chiave pubblica | flag di `payouts-release` e del `backend/` legacy non rilevati in WI-015 |

## 3. Prove eseguite sul codice rilasciato

Sulla testa `1368c23` (verificate nei log anche dalla cabina di regia): frontend 4059/4059; smoke browser 114/114;
WI-015A 32/32; identità e concorrenza 37/37; WI-015B 37/37; operazioni end-to-end 22/22; concorrenza WI-011 9/9;
PostgREST WI-004 13/13 e WI-008D 22/22. Run: CI `45904368974`, gate DB `45904368870`, E2E `45904369073`,
Security scan `45904368969`. Dopo il merge, su `6602fbb`, **tutti verdi**: CI `45908736603` (frontend-next 4059/4059),
gate DB `45908736589` (WI-015A 32/32, identità e concorrenza 37/37, WI-015B 37/37, operazioni 22/22, WI-011 concorrenza
9/9, WI-004 13/13, WI-008D 22/22), E2E `45908736626` (114 passati, pulizia verificata), Security scan `45908736661`.

Il banco sintetico di promozione è stato eseguito sulla PR #325. Le prove con `pg_cron` e con i processi dei worker usano
uno stack locale usa e getta, non un progetto Supabase ospitato.

## 4. Stato dei gate

Spenti o assenti: regola di promozione (`draft`), promozione, proiezione, proposte, acquisizione annunci, chiusura
automatica, agenti (0), lavori dello scheduler (6 su 6 spenti), `pg_cron`, fonti di monitoraggio (7 su 7 spente, 0
collegate), tariffe e tetti AI, `AI_ENABLED`, `PAYMENTS_ENABLED` (dal comportamento di checkout e onboarding), ambiente
dei worker ([`COMPANY_BRAIN` §3.1](../COMPANY_BRAIN.md)). Procedura unica di attivazione e revoca:
[`COMPANY_BRAIN` §8](../COMPANY_BRAIN.md).
