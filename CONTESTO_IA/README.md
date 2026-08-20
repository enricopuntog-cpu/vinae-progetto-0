# Router del contesto durevole Vinea

Ultimo aggiornamento del router: **20 agosto 2026**.

Questa cartella conserva memoria strutturale e storia datata. Non è il bootstrap
obbligatorio e non sostituisce le fonti vive.

## Lettura obbligatoria a inizio sessione

Fuori da questa cartella:

1. [`../CLAUDE.md`](../CLAUDE.md) — costituzione operativa corrente;
2. [`../CHANGES.log`](../CHANGES.log) — stato e handoff corrente;
3. stato Git del branch/worktree.

[`../AGENTS.md`](../AGENTS.md) è solo il router minimo che porta a quei file.
Non contiene una seconda costituzione.

## Lettura su richiesta

Aprire soltanto ciò che serve al task:

- [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md) — dossier cronologico di misure e
  stati verificati; l'apertura è una fotografia del 9 agosto 2026, non lo stato
  corrente.
- [`02_STORIA_FASI.md`](02_STORIA_FASI.md) — cronologia delle fasi e delle PR.
- [`03_ARCHITETTURA_REGOLE_DEBITI.md`](03_ARCHITETTURA_REGOLE_DEBITI.md) —
  architettura durevole, invarianti e debiti. Le regole operative correnti sono
  comunque in `CLAUDE.md`.
- [`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md) — procedure non ovvie per
  ricerca, Supabase e fixture tecniche.
- [`05_INDICE_PR_E_FONTI.md`](05_INDICE_PR_E_FONTI.md) — indice PR e fonti
  storiche.
- [`06_PROMPT_CHAT_OPERATIVE.md`](06_PROMPT_CHAT_OPERATIVE.md) — prompt storici,
  conservati come record e non come policy corrente.
- [`context-manifest.json`](context-manifest.json) — snapshot machine-readable
  ricostruito il 13 agosto 2026; è datato e non autorevole.

## Gerarchia delle fonti

In caso di contrasto:

1. istruzioni correnti dell'utente e perimetro del task;
2. `CLAUDE.md`;
3. `CHANGES.log`;
4. codice, migrazioni, Git/CI e fatti runtime misurati;
5. ADR, roadmap e documenti correnti di sicurezza/ambiente;
6. questa cartella, specifiche datate, verbali, report e prompt archiviati.

Un verbale storico resta vero come record della sua data, ma non può imporre
oggi un vecchio gate di conferma contraddetto dalla costituzione corrente. Non
va riscritto come se la decisione precedente non fosse mai esistita.

## Coordinate correnti essenziali

- `frontend/` + `backend/` restano la versione servita.
- La beta pubblica `frontend-next` è separata e non è il cutover.
- Fase 11: estensioni AI ammesse per eccezione; implementazione non aperta finché
  non sono soddisfatti i prerequisiti della specifica.
- Fase 12: Club/Community; checkpoint 12a/12b/12c mersi e in produzione.
- `public.clubs` contiene `circolo-vinea` dal 19 agosto 2026; il seed dei sette
  club non è stato eseguito.
- Fase 13: cutover; non iniziata e soggetta a decisione separata.
- Ultimo ledger di produzione registrato: 32 migrazioni. Un merge non prova che
  una nuova migrazione sia stata applicata: rileggere sempre il ledger.

Per ogni fatto più volatile, rileggere `CHANGES.log` e misurare di nuovo.