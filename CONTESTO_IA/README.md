# Contesto completo Vinea per IA e nuove chat

Ultimo aggiornamento: **6 agosto 2026**

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
`frontend-next/` + Supabase. L'ultima fase integrata in `main` è la 7f, PR #25
al merge squash `491e10d`. Il checkpoint 7g è nella PR draft #26 dal branch
`hardening/phase-7g-operational-closeout`: workflow GitHub Actions di
auto-rilascio implementato, pubblicato e verificato localmente senza invocazioni reali. La verticale
pagamenti resta mai percorsa, `PAYMENTS_ENABLED=false` e nessuna chiamata Stripe
è stata fatta. Le fasi 8–11 non sono iniziate.
