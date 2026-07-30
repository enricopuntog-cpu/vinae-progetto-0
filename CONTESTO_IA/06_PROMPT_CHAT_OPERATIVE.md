# Prompt operativi per le prossime chat

Questi prompt si usano **in ordine e mai in parallelo**. Ogni chat deve
terminare aggiornando `CHANGES.log` secondo il protocollo di `AGENTS.md`.
Il passaggio al prompt successivo richiede che il gate del prompt precedente
sia documentato.

## Prompt 1 — audit post-merge della Fase 6d-1

```text
Lavora sul repository Vinea e svolgi esclusivamente l'audit post-merge della
Fase 6d-1.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md e CHANGES.log;
2. leggi CONTESTO_IA/README.md e tutti i file nell'ordine indicato;
3. verifica git status, branch, origin/main, PR #14, commit 6bbe4dd, merge
   61e3fde e GitHub Actions run 30554736346;
4. conserva qualsiasi modifica locale non tua.

Obiettivo:
- accertare quali autorizzazioni ed evidenze esistevano quando PR #14 è stata
  unita;
- distinguere CI verde, verifier read-only 13/13, baseline pre-repair 31/33 e
  7/11, e risultati finali post-repair eventualmente disponibili;
- non dedurre autorizzazioni o esiti dal solo merge;
- produrre un rapporto versionato PHASE_6D1_POST_MERGE_AUDIT.md con fonti,
  timestamp, commit e conclusione verificabile;
- aggiornare CHANGES.log e CONTESTO_IA senza riscrivere i rapporti storici.

Vincoli:
- parti da origin/main aggiornato e usa il branch dedicato
  hardening/phase-6d-1-post-merge-verification;
- nessun SQL remoto, nessuna fixture e nessuna modifica a migrazioni applicate;
- nessun lavoro della 6d-2a o della Fase 7;
- commit piccoli, push e draft PR; nessun merge autonomo.

Concludi indicando se le precondizioni per chiedere l'autorizzazione alle
griglie sono soddisfatte. Se lo sono, fermati e chiedi comunque autorizzazione
esplicita in sessione: nessuna prova storica sostituisce il consenso corrente.
```

## Prompt 2 — griglie remote post-repair 33/33 e 11/11

```text
Continua esclusivamente il lavoro della Fase 6d-1 post-merge sul branch
hardening/phase-6d-1-post-merge-verification e sulla sua draft PR. Non creare
un'altra branch e non lavorare in parallelo con altre chat.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md, CHANGES.log e CONTESTO_IA/;
2. leggi integralmente la skill Supabase disponibile;
3. verifica che l'audit post-merge sia presente e che la working tree sia
   pulita;
4. leggi supabase/tests/README.md e per intero:
   - supabase/tests/6d-1_invarianti_sicurezza.sql;
   - supabase/tests/6d-1_followup_invarianti.sql;
   - supabase/tests/6d-1_remote_drift_repair_verifica.sql;
   - supabase/tests/6d-1_verifica.sql.

Gate obbligatorio:
- mostra all'utente i percorsi e lo scopo esatto di
  supabase/tests/6d-1_invarianti_sicurezza.sql e
  supabase/tests/6d-1_followup_invarianti.sql;
- spiega che creano e cancellano fixture remote;
- chiedi autorizzazione esplicita separata;
- FERMATI senza eseguire SQL finché l'autorizzazione non compare nella
  sessione corrente. Il merge della PR #14 non vale come autorizzazione.

Dopo autorizzazione:
- esegui le due griglie nell'ordine documentato;
- riesegui il verifier repair read-only e le verifiche statiche previste;
- controlla residui fixture, Security Advisor e Performance Advisor;
- registra output completi: 33/33, 11/11, 13/13 e residui zero sono il gate;
- in caso di fallimento non bonificare o modificare il remoto senza una nuova
  proposta e autorizzazione;
- aggiorna rapporto post-merge, CHANGES.log e CONTESTO_IA;
- non modificare migrazioni già applicate e non avviare la 6d-2a;
- qualifica il diff, fai commit/push sulla draft PR e non eseguire merge.
```

## Prompt 3 — avvio della Fase 6d-2a

```text
Avvia la Fase 6d-2a solo se origin/main contiene il rapporto post-merge con
33/33, 11/11, 13/13, residui fixture zero e approvazione esplicita della fase.
Se anche una sola precondizione manca, produci un rapporto di blocco e fermati.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md, CHANGES.log e CONTESTO_IA/;
2. leggi la skill Supabase, ROADMAP_V1, MIGRATION_PHASE_1_BACKLOG, ADR 001/002,
   SECURITY.md e le migrazioni 6a-6d-1;
3. aggiorna origin/main e crea da quella base
   migration/phase-6d-2a-catalog-cellar-paths;
4. verifica che nessun'altra chat stia lavorando sullo stesso dominio.

Obiettivo della fase:
- distinguere in modo autoritativo il vino di catalogo curato dallo staff dal
  vino inserito da un utente;
- separare aggiunta privata, aggiunta pubblica e vendita da bottle_unit
  esistente;
- rendere atomica la creazione dell'ambiente e del modulo iniziale;
- collegare alla home soltanto riepiloghi reali della Cantina;
- preservare RLS, privilegi, viste chiuse, vincoli bottiglia-annuncio e
  ceduta_at introdotti dalla 6d-1;
- mantenere frontend/ e backend/ come versione servita;
- escludere ordini, proposte, pagamenti e qualsiasi lavoro della Fase 7.

Metodo:
- prima produci specifica e matrice accessi/stati/concorrenza;
- prepara solo migrazioni additive e test locali/versionati;
- aggiorna servizi frontend-next dietro le interfacce esistenti;
- verifica lint, typecheck, build e test pertinenti;
- mostra l'SQL esatto e FERMATI prima di applicarlo al Supabase remoto;
- applicazione, fixture e merge richiedono autorizzazioni esplicite separate;
- mantieni la PR draft e aggiorna CHANGES.log a ogni handoff.
```

## Prompt 4 — revisione e qualificazione finale della Fase 6d-2a

```text
Revisiona la Fase 6d-2a sul branch
migration/phase-6d-2a-catalog-cellar-paths. Non aggiungere funzionalità e non
iniziare la Fase 7.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md, CHANGES.log e CONTESTO_IA/;
2. verifica base, diff completo verso origin/main, commit, draft PR e lavoro
   concorrente;
3. leggi la skill Supabase e confronta schema, migrazioni, RLS, privilegi,
   viste, funzioni SECURITY DEFINER e test della fase.

Revisione richiesta:
- controlla provenienza catalogo, ownership, concorrenza e deduplicazione;
- prova i tre percorsi: aggiunta privata, aggiunta pubblica e vendita da
  bottiglia esistente;
- verifica creazione atomica ambiente/modulo e home con soli dati reali;
- conferma che nessun prezzo, ruolo, owner o stato autorevole venga dal client;
- esegui lint, typecheck, build, test e git diff --check;
- controlla segreti, lockfile, documentazione, advisor ed eventuali residui;
- per SQL o fixture remoti mostra prima l'azione esatta e chiedi autorizzazione
  separata nella sessione corrente;
- aggiorna ROADMAP, backlog, sicurezza/ambiente se necessario, CHANGES.log e
  tutti i file CONTESTO_IA;
- pubblica solo una draft PR qualificata; non fare merge autonomamente.

Concludi con una decisione esplicita: BLOCCATA oppure PRONTA PER REVISIONE,
elencando prove e blocchi residui.
```
