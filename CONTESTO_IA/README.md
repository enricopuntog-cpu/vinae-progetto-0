# Contesto completo Vinea per IA e nuove chat

Ultimo aggiornamento: **7 agosto 2026**

Questa cartella è il punto di ingresso rapido per chi deve lavorare su Vinea
senza conoscere le conversazioni precedenti. Riassume la cronologia delle fasi,
lo stato reale del repository, le decisioni architetturali e i vincoli che non
devono essere reinterpretati.

## Ordine di lettura

1. [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md) — fotografia verificata del
   repository e del lavoro ancora non integrato.
2. [`02_STORIA_FASI.md`](02_STORIA_FASI.md) — cosa è stato fatto, fase per
   fase, con collegamenti alle Pull Request.
3. [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md) —
   architettura, confini di sicurezza, regole di processo e debiti aperti.
4. [`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md) — checklist operativa
   prima di modificare codice, database o documentazione.
5. [`05_INDICE_PR_E_FONTI.md`](05_INDICE_PR_E_FONTI.md) — indice delle PR e
   gerarchia delle fonti.
6. [`06_PROMPT_CHAT_OPERATIVE.md`](06_PROMPT_CHAT_OPERATIVE.md) — prompt
   operativi storici delle fasi 6d-1 e 6d-2a, tenuti come modello di forma.
7. [`context-manifest.json`](context-manifest.json) — riepilogo
   machine-readable per strumenti automatici.

## Regola di interpretazione

Questa cartella è una **mappa**, non sostituisce le fonti vive. In caso di
contrasto:

1. prevalgono le istruzioni correnti dell'utente e l'eventuale
   [`../AGENTS.md`](../AGENTS.md);
2. prevalgono il codice e le migrazioni realmente presenti nel branch;
3. seguono [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md), le ADR e la
   documentazione di sicurezza;
4. questa cartella aiuta a orientarsi e va aggiornata quando una fase cambia
   stato.

## In una frase

Vinea sta migrando gradualmente dall'app servita `frontend/` + `backend/` verso
`frontend-next/` + Supabase. L'ultima fase integrata in `main` è la 7g, PR #26
al merge squash `f9c53e0`. La Fase 8 è nella draft PR #27 sul branch
`migration/phase-8-messaging-notifications`, nei commit `d4eb981`, `9a270f1`,
`059becc`, `4e97139` e `6ea0fe6`:
schema/RPC/RLS, UI messaggi e notifiche e Realtime privato sono implementati e
verificati localmente. `4e97139` rimuove soltanto l'abilitazione RLS ridondante
sulla tabella Supabase-managed `realtime.messages` e corregge a 23 casi
l'intestazione della griglia fixture. La Preview `jggjaqcdbcbxdxhnggio` ha
applicato la migrazione e superato 20/20 casi statici, 23/23 casi fixture e 5/5
prove concorrenti, con residui zero. Produzione non è stata modificata;
Dashboard Realtime, smoke autenticato, ready-for-review e merge restano aperti.
