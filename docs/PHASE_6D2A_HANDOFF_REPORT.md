# Fase 6d-2a — Rapporto di blocco delle precondizioni

Data e ora: 30 luglio 2026, 16:27:57 +02:00

Stato finale: **Non pronta per revisione SQL**

## Repository e stato Git

- Repository: `enricopuntog-cpu/vinae-progetto-0`
- Branch locale verificato: `hardening/phase-6d-1-security-invariants`
- HEAD locale: `82ae7fc9a6afbb8cc75b540f88941694cb5ecef6`
- Base remota verificata dopo `git fetch --prune origin`:
  `origin/main` = `a857f3b0215da955916ca298fcb6159e1954c776`
- Distanza locale da `origin/main`: 17 commit avanti, 0 indietro
- Distanza locale dal branch remoto 6d-1: 3 commit avanti, 0 indietro
- Branch richiesta `migration/phase-6d-2a-catalog-cellar-paths`: non creata

La working tree iniziale conteneva modifiche staged preesistenti della Fase
6d-1: regole agenti, handoff, report, migrazione repair rinominata alla versione
remota e query di verifica. Sono state preservate e non ripristinate,
sovrascritte o incluse in un nuovo commit.

## Precondizioni della Fase 6d-1

| Precondizione | Esito | Prova |
| --- | --- | --- |
| Merge conclusivo 6d-1 presente in `main` | FALLISCE | `origin/main` resta `a857f3b`, Fase 6c-2 |
| Repair `20260730140948` presente in `main` | FALLISCE | il path non esiste nell'albero di `origin/main` |
| Documentazione definitiva 6d-1 presente in `main` | FALLISCE | `docs/PHASE_6D1_SUPABASE_REVIEW.md` e `docs/PHASE_6D1_FINAL_EXECUTION_REPORT.md` non esistono in `origin/main` |
| Griglia principale finale 33/33 | NON VERIFICABILE | i documenti locali staged dichiarano ancora il retest pendente |
| Griglia follow-up finale 11/11 | NON VERIFICABILE | i documenti locali staged dichiarano ancora il retest pendente |
| Verifica repair completamente verde | SOLO LOCALE/HANDOFF | il verifier locale e i risultati non sono integrati in `main` |
| GitHub Actions verdi per la 6d-1 | FALLISCE | nessuna workflow run associata al commit locale `82ae7fc` |
| Pull request 6d-1 conclusa | FALLISCE | GitHub elenca come PR più recente la #13 della Fase 6c-2; nessuna PR 6d-1 |

Le precondizioni falliscono prima dell'avvio della fase. Non è quindi lecito
creare la branch 6d-2a, progettare o scrivere la migrazione, modificare servizi
o aprire una pull request.

## Fonti revisionate

Sono stati riletti `AGENTS.md`, `CLAUDE.md`, `CHANGES.log`,
`CONTESTO_IA/README.md` e i file di contesto indicati dal suo ordine di
lettura. Sono stati inoltre confrontati `docs/ROADMAP_V1.md`,
`docs/MIGRATION_PHASE_1_BACKLOG.md`, gli ADR 001 e 002,
`supabase/tests/README.md`, lo stato Git aggiornato e i metadati GitHub.

L'incoerenza operativa rilevata è che `CHANGES.log` e `CONTESTO_IA/`
descrivevano lavoro locale 6d-1 e una repair remota, mentre il nuovo incarico
assumeva che la fase fosse già integrata. Git e GitHub confermano che
l'integrazione non è avvenuta. `AGENTS.md` e `CLAUDE.md` non richiedono
correzioni: le loro regole permanenti restano valide.

La lettura analitica completa di schema, migrazioni 6a–6d-1, servizi e
implementazioni equivalenti non è stata trasformata in lavoro di fase: il gate
Git/GitHub è fallito prima dell'avvio della 6d-2a.

## Obiettivo e confini non avviati

L'obiettivo previsto era separare aggiunta privata, aggiunta pubblica e vendita
da bottiglia esistente; introdurre provenienza verificabile del catalogo;
rendere atomica la creazione ambiente/modulo; collegare alla home soltanto i
riepiloghi reali della Cantina.

Nessuno di questi percorsi è stato implementato. Ordini, Proposte, Pagamenti e
Fase 7 non sono stati iniziati. `frontend/` e `backend/` restano la versione
servita; `frontend-next/` e Supabase restano la destinazione. Il progetto non è
production-ready.

## Analisi, migrazione e modello di provenienza

- Analisi definitiva dello schema 6d-2a: non avviata per precondizione fallita.
- Modello di provenienza scelto: nessuno approvato o implementato.
- Stati del catalogo e transizioni: non definiti in una migrazione.
- Matrice dei privilegi 6d-2a: non prodotta.
- Gestione concorrenza e duplicati 6d-2a: non implementata.
- Migrazione proposta: nessuna.
- Percorso migrazione: non applicabile.
- SHA-256 migrazione: non applicabile.
- SQL remoto applicato: **no**.

## RPC, viste, servizi e home

- RPC aggiunta bottiglia: non creata.
- RPC ambiente + modulo iniziale: non creata.
- Viste pubbliche: non modificate.
- Servizi `frontend-next`: non modificati.
- Home: non modificata.
- Domini mock: invariati.
- Pull request 6d-2a: non aperta.

## Test e verifiche

Non sono stati eseguiti test SQL o frontend della 6d-2a, perché nessun codice
della fase è stato creato. Non sono stati eseguiti `lint`, `typecheck`, `test`
o `build` come qualificazione della fase. Non sono state create fixture e non è
stata eseguita alcuna query SQL remota in scrittura.

La verifica effettuata è limitata al gate:

- `git fetch --prune origin`: completato;
- `origin/main`: `a857f3b`;
- assenza dei path 6d-1 richiesti nell'albero di `origin/main`;
- assenza di PR 6d-1 su GitHub;
- assenza di workflow run per `82ae7fc`;
- presenza di 16 cambiamenti staged preesistenti della 6d-1, preservati.

## File modificati e commit

File modificati in questa verifica:

- `CHANGES.log`;
- `docs/PHASE_6D2A_HANDOFF_REPORT.md`.

Commit creati: nessuno.

La modifica a `CHANGES.log` si sovrappone a un file già staged dal lavoro
precedente; il contenuto staged preesistente non è stato azzerato. Nessun file
SQL, TypeScript, lockfile, `.env` o file estraneo è stato modificato.

## Rischi e rollback

Avviare la 6d-2a dalla base corrente produrrebbe una branch priva delle
invarianti, della repair e delle prove finali della 6d-1, rendendo non
revisionabili dipendenze e privilegi. Il rischio è evitato fermando il lavoro.

Non esiste rollback applicativo o database: nessuna modifica applicativa e
nessun SQL remoto sono stati eseguiti. Le sole aggiunte di handoff sono locali
e possono essere rimosse in un cambiamento esplicito successivo senza effetto
sul prodotto o sul database.

## Decisioni e istruzioni per la ripresa

Richiedono completamento o approvazione:

1. completare, committare e pubblicare le modifiche 6d-1 ancora locali;
2. ottenere e documentare 33/33, 11/11, verifier repair verde e CI verde;
3. approvare e completare il merge della PR 6d-1 in `main`.

Dopo il merge:

1. eseguire `git fetch --prune origin`;
2. verificare che `origin/main` contenga repair, rapporto finale e risultati;
3. verificare la CI dell'ultimo commit di `main`;
4. creare `migration/phase-6d-2a-catalog-cellar-paths` direttamente dal nuovo
   `origin/main`;
5. solo allora riprendere analisi, SQL locale e test della 6d-2a.

## Prossimi 3 passi atomici

1. Pubblicare il lavoro 6d-1 ancora locale sul branch remoto dedicato.
2. Completare prove, CI e merge approvato della Fase 6d-1 in `main`.
3. Rilanciare le precondizioni e creare la branch 6d-2a dal nuovo `origin/main`.

**Non pronta per revisione SQL**
