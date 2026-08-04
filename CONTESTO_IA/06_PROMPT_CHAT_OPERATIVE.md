# Prompt operativi per le prossime chat

**Stato al 4 agosto 2026:** i tre prompt qui sotto appartengono alle fasi 6d-1 e
6d-2a, entrambe chiuse e integrate. Restano come modello della forma da usare —
gate espliciti, autorizzazioni separate, fermata prima dell'SQL remoto — non
come lavoro da avviare. I gate ancora aperti sono elencati in
[`04_HANDOFF_NUOVA_IA.md`](04_HANDOFF_NUOVA_IA.md).

Questi prompt si usano **in ordine e mai in parallelo**.

Regola generale: le fasi già integrate e documentate si considerano concluse.
Non si ripetono audit, test o letture complete della cronologia senza una causa
concreta: modifica del relativo dominio, risultato contraddittorio, deriva
remota o prova mancante. Ogni chat legge sempre soltanto `AGENTS.md`,
`CLAUDE.md` e `CHANGES.log`, poi consulta le altre fonti necessarie al lavoro
corrente.

## Prompt 1 — chiusura del solo gate mancante della Fase 6d-1

```text
Lavora sul repository Vinea e chiudi esclusivamente il gate ancora mancante
della Fase 6d-1: le griglie remote post-repair 33/33 e 11/11.

Non rieseguire audit o test delle fasi 1–6c. Considera valido il verifier
read-only 13/13 già documentato, salvo che emerga una deriva concreta.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md e CHANGES.log;
2. esegui:
   git status --short --branch
   git fetch --prune origin
   git log -5 --oneline --decorate
   git rev-list --left-right --count origin/main...HEAD
3. verifica che la PR di riconciliazione dell'handoff sia integrata in main;
4. crea da origin/main aggiornato il branch
   hardening/phase-6d-1-post-merge-verification;
5. leggi soltanto:
   - supabase/tests/README.md;
   - supabase/tests/6d-1_invarianti_sicurezza.sql;
   - supabase/tests/6d-1_followup_invarianti.sql.

Autorizzazione obbligatoria:
- mostra i due script e spiega che creano e cancellano fixture remote;
- chiedi autorizzazione esplicita nella sessione corrente;
- FERMATI finché non arriva. Il merge della PR #14 non è autorizzazione.

Dopo l'autorizzazione:
- esegui soltanto le due griglie nell'ordine documentato;
- registra integralmente 33/33 e 11/11;
- verifica che i residui delle fixture siano zero;
- non rieseguire verifier 13/13, Advisor o vecchie prove, a meno che una griglia
  fallisca, emerga deriva o lo schema remoto risulti cambiato;
- in caso di fallimento non correggere dati o schema remoto senza una nuova
  proposta e autorizzazione;
- aggiorna il rapporto post-merge, CHANGES.log e lo stato sintetico in
  CONTESTO_IA;
- esegui solo i controlli documentali pertinenti, crea commit piccoli, push e
  draft PR;
- non iniziare la Fase 6d-2a e non eseguire merge autonomamente.

Concludi indicando soltanto: risultati 33/33 e 11/11, residui fixture, file
aggiornati, PR/CI e blocchi reali rimasti.
```

## Prompt 2 — implementazione della Fase 6d-2a

```text
Avvia e implementa la Fase 6d-2a soltanto se origin/main documenta 33/33,
11/11, verifier storico 13/13, residui fixture zero e approvazione esplicita
della fase. Se manca un gate, segnala esattamente quale e fermati senza
ripetere verifiche già concluse.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md e CHANGES.log;
2. esegui:
   git status --short --branch
   git fetch --prune origin
   git log -5 --oneline --decorate
   git rev-list --left-right --count origin/main...HEAD
3. crea da origin/main aggiornato
   migration/phase-6d-2a-catalog-cellar-paths;
4. leggi la sezione 6d-2a di ROADMAP_V1 e MIGRATION_PHASE_1_BACKLOG;
5. ispeziona soltanto schema, migrazioni, servizi e componenti direttamente
   coinvolti. Non rileggere o ritestare integralmente le vecchie fasi.

Obiettivo:
- distinguere in modo autoritativo il catalogo curato dallo staff dai vini
  inseriti dagli utenti;
- separare aggiunta privata, aggiunta pubblica e vendita da bottle_unit
  esistente;
- rendere atomica la creazione dell'ambiente e del modulo iniziale;
- collegare alla home soltanto riepiloghi reali della Cantina;
- preservare RLS, privilegi, viste chiuse, vincoli bottiglia-annuncio e
  ceduta_at già presenti;
- mantenere frontend/ e backend/ come versione servita;
- escludere ordini, proposte, pagamenti e qualsiasi lavoro della Fase 7.

Metodo:
- produci una specifica breve solo per le decisioni ancora aperte;
- implementa migrazioni additive, test della 6d-2a e adattamenti
  frontend-next dietro le interfacce esistenti;
- esegui soltanto lint, typecheck, build e test pertinenti ai file modificati;
- non ripetere test di Auth, OAuth, vecchia Cantina o 6d-1 se il relativo
  codice non è stato toccato;
- mostra l'SQL esatto e FERMATI prima di applicarlo al Supabase remoto;
- SQL remoto, fixture e merge richiedono autorizzazioni esplicite separate;
- aggiorna CHANGES.log e la documentazione direttamente interessata;
- crea commit piccoli, push e draft PR; nessun merge autonomo.

Concludi con ciò che è stato implementato, verifiche pertinenti, SQL ancora da
autorizzare, PR/CI e prossimo passo concreto.
```

## Prompt 3 — revisione e qualificazione finale della Fase 6d-2a

```text
Revisiona e qualifica esclusivamente il lavoro della Fase 6d-2a sul branch
migration/phase-6d-2a-catalog-cellar-paths. Non riesaminare le vecchie fasi e
non iniziare la Fase 7.

Prima di agire:
1. leggi integralmente AGENTS.md, CLAUDE.md e CHANGES.log;
2. verifica:
   git status --short --branch
   git fetch --prune origin
   git log -10 --oneline --decorate
   git diff --stat origin/main...HEAD
   git diff --check origin/main...HEAD
3. esamina il diff della 6d-2a e le sole dipendenze direttamente toccate.

Revisione richiesta:
- controlla provenienza catalogo, ownership, concorrenza e deduplicazione;
- prova i tre percorsi della fase: aggiunta privata, aggiunta pubblica e
  vendita da bottiglia esistente;
- verifica creazione atomica ambiente/modulo e home con soli dati reali;
- conferma che prezzo, ruolo, owner e stato autoritativo non provengano dal
  client;
- esegui test, lint, typecheck e build pertinenti al diff;
- non ripetere suite o audit di domini non modificati;
- controlla segreti, migrazioni additive, documentazione e residui prodotti
  dalla sola 6d-2a;
- per SQL o fixture remoti mostra l'azione esatta e chiedi autorizzazione
  separata;
- aggiorna CHANGES.log, roadmap, backlog e soltanto i file di contesto divenuti
  realmente obsoleti;
- aggiorna la draft PR e verifica la CI; non fare merge autonomamente.

Concludi con una decisione esplicita: BLOCCATA oppure PRONTA PER REVISIONE,
citando soltanto prove della 6d-2a e blocchi ancora effettivi.
```
