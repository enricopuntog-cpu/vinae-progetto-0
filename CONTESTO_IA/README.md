# Contesto completo Vinea per IA e nuove chat

Ultimo aggiornamento: **9 agosto 2026**

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
`frontend-next/` + Supabase. L'ultima fase integrata in `main` è la **8**, PR #27
al merge squash `4f96864` del 7 agosto 2026, con i quattro check `SUCCESS`
sull'HEAD finale `b32ff9d` del branch `migration/phase-8-messaging-notifications`:
schema/RPC/RLS di messaggistica e notifiche, UI `/messaggi` e `/notifiche` e
Realtime privato sono in `main`, e il merge ha distribuito
`20260806224517 phase_8_messaging_notifications` come ventesima riga del ledger
di produzione. Le prove della fase — 20/20 statici, 23/23 fixture, 5/5 concorrenti,
smoke Realtime autenticato, residui zero — erano state eseguite sulla Preview
`jggjaqcdbcbxdxhnggio`, che era legata alla PR e non esiste più. Le fasi 9, 10 e
11 non sono iniziate.
