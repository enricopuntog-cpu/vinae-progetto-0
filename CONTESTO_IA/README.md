# Router del contesto durevole Vinea

Ultimo aggiornamento del router: **18 settembre 2026**.

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
  corrente. Le ultime voci sono del 18 settembre 2026: security hardening
  post-audit (PR #119, mersa; migrazione nel ledger di produzione) e step-up
  auth sui prelievi (PR in bozza, non mersa).
- La regola delle porte che fanno uscire denaro — riautenticazione recente
  dopo il ramo di replay — è in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
- L'eccezione accettata sulle viste `SECURITY DEFINER` (lint 0010) e i grant
  correnti di `public.profiles` sono in `03_ARCHITETTURA_REGOLE_DEBITI.md`.
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
- Vetrina a successo e aliquota per classe di venditore: ammesse per eccezione e
  per nome il 14 settembre 2026, **progettate e non implementate**. I documenti
  sono `docs/VETRINA_A_SUCCESSO_SPEC.md` e
  `docs/ALIQUOTA_PER_CLASSE_VENDITORE_SPEC.md`; l'elenco completo delle
  eccezioni è in `docs/ROADMAP_V1.md`.
- Fase 12: Club/Community; checkpoint 12a/12b/12c mersi e in produzione.
- `public.clubs` contiene `circolo-vinea` dal 19 agosto 2026; il seed dei sette
  club non è stato eseguito.
- Fase 13: cutover; non iniziata e soggetta a decisione separata.
- Dominio pubblico della beta: **`https://vineawineclub.com`**, di proprietà,
  dal 14 settembre 2026. L'host `timely-lokum-43a12e.netlify.app` non è più
  l'indirizzo pubblico: risponde `308` verso il dominio proprio conservando il
  percorso, ed è ancora una destinazione ammessa nei Redirect URLs di Supabase.
  Il nome del sito Netlify è invariato, quindi le Deploy Preview conservano la
  vecchia forma.
- Email di Auth: **SMTP proprio Resend**, mittente
  `Vinea Wine Club <noreply@vineawineclub.com>`, in uso dal 14 settembre 2026.
  Il mailer di prova incorporato in Supabase e il suo `over_email_send_rate_limit`
  non sono più la strada in uso. La chiave vive nel progetto Supabase, non nel
  repository.
- Ledger di produzione: **ultimo conteggio registrato 32**, al 20 agosto 2026,
  quando coincideva con i file su `main`. Su `origin/main` i file sono oggi
  **51**: **19 migrazioni** aggiunte dopo quella data non sono coperte da alcuna
  lettura del ledger. Non è una misura di quante manchino — è la misura di
  quanto non sappiamo. Rileggerlo è un prerequisito aperto dell'accensione dei
  pagamenti; l'elenco esatto è in [`01_STATO_ATTUALE.md`](01_STATO_ATTUALE.md).
  Un merge non prova che una nuova migrazione sia stata applicata, e un merge
  senza migrazioni può averne distribuite di altrui: rileggere sempre il ledger.
- Rilascio Netlify: il sito è collegato al repository e costruisce una Deploy
  Preview per ogni PR, ma **un merge su `main` non ha ricostruito la produzione**
  — misurato il 15 settembre 2026 sui merge `aca86ac` e `344ad45`. Il motivo è
  un dato della dashboard Netlify e resta una domanda aperta. Fino al 15
  settembre 2026 l'artefatto pubblicato conteneva codice assente da
  `origin/main`; la PR di recupero lo riporta in Git.
- L'integrazione `Supabase Preview` parte a **ogni** push su `main`, anche senza
  file sotto `supabase/migrations/`; sulle teste delle PR risulta `skipped`.

Per ogni fatto più volatile, rileggere `CHANGES.log` e misurare di nuovo.
