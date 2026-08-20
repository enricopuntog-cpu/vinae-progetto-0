# ADR 002: Strategia di migrazione incrementale

## Stato

Accettata.

## Contesto

Vinea è in uso come demo durante tutta la transizione verso l'architettura
target descritta in [ADR 001](001-target-architecture.md). Non deve
esistere un momento in cui il sito è rotto o offline, e non devono mai
esistere due backend entrambi scrivibili come fonte di verità per lo
stesso dominio nello stesso momento.

## Decisione

La migrazione procede per fasi piccole, una alla volta, ciascuna con
branch e Pull Request dedicate (draft finché non diversamente indicato):

1. **Scaffold e porting statico** (Fasi 2–4): il nuovo frontend Next.js
   viene costruito e reso iso-funzionale con dati mock. Non è ancora la
   versione servita agli utenti; convive con `frontend/` attuale senza
   sostituirlo.
2. **Un dominio alla volta collegato a Supabase** (Fasi 5–10), partendo da
   Auth — prerequisito di tutti gli altri domini — e proseguendo in
   ordine di dipendenza: catalogo/annunci prima di ordini, ordini prima
   di pagamenti reali, messaggistica e moderazione dopo che il nucleo
   marketplace è stabile.
3. **Un solo scrittore per dominio**: quando un dominio viene migrato a
   Supabase, il percorso FastAPI/MongoDB corrispondente smette di essere
   scritto per quel dominio. Le letture legacy possono restare per
   compatibilità solo se esplicitamente pianificato nella fase, mai le
   scritture.
4. **Il frontend TanStack Start attuale resta la versione servita** agli
   utenti finché la versione Next.js non raggiunge parità funzionale
   verificata end-to-end per tutti i domini migrati fino a quel punto.
5. **Cutover finale** (Fase 13): dismissione di `frontend/` (TanStack
   Start) e `backend/` (FastAPI/MongoDB) solo dopo parità verificata e
   approvazione esplicita separata — non è una conseguenza automatica
   del completamento delle fasi precedenti.

Il cutover era la **Fase 12** in questa ADR fino al 16 agosto 2026, quando è
stata inserita prima di esso una **Fase 12 nuova**: Club/Community, che prende
quel numero perché segue direttamente la Fase 11 nell'ordine di dipendenza. I
checkpoint 12a/12b/12c sono ora mersi e in produzione. Vale per essi la stessa
osservazione fatta qui sotto per la Fase 11: **non costituiscono un dominio
migrato**, quindi restano fuori dal punto 2 e non allargano il perimetro «un
dominio alla volta collegato a Supabase», che si è chiuso con la Fase 10. Questa
ADR registra l'assegnazione corrente; il cutover resta la Fase 13 e non segue
automaticamente dalla chiusura della Fase 12.

Il cutover era la **Fase 11** in questa ADR fino all'11 agosto 2026, quando la
chiusura della Fase 10 ha inserito prima di esso una **Fase 11 nuova**: le
quattro funzionalità AI ammesse per eccezione esplicita dalle decisioni 7.3,
7.12 e 7.13. Non sono un dominio migrato — sono funzionalità che il legacy non
ha — quindi restano fuori dal punto 2 e non allargano il perimetro «un dominio
alla volta collegato a Supabase», che si chiude con la Fase 10.

## Regole operative per ogni fase

- Una fase = una branch = una Pull Request. Mai più fasi in lavorazione
  in parallelo sulla stessa area.
- Pull Request in draft (non ready for review) per tutta questa traccia,
  finché non diversamente indicato — è pianificazione/fondazione, non
  lavoro pronto per merge immediato.
- Nessuna fase introduce funzionalità non ammessa nel proprio perimetro;
  l'obiettivo ordinario è parità, non miglioramento del prodotto.
- Ogni fase che tocca dati reali richiede migrazioni pulite, policy RLS
  verificate e prove database dove applicabili.
- L'ammissione di una nuova fase o funzionalità è una decisione organizzativa
  sullo scope e viene registrata nella zona organizzativa. Non è una richiesta
  di conferma per ogni comando Git o Supabase.

### Autonomia tecnica e gate di scope — decisione corrente

Un agente dotato degli strumenti necessari è autorizzato autonomamente a
completare il ciclo `branch → implementazione → test → commit → push → PR → CI
→ fix CI → merge → verifica post-merge`. Questo vale anche per PR con file sotto
`supabase/migrations/` e per il lavoro Supabase richiesto dal task: migrazioni,
schema, RPC, trigger, RLS, Storage, Edge Function, fixture tecniche necessarie e
verifiche remote.

L'autonomia non modifica i gate di integrità: si lavora fuori da `main`, i
controlli pertinenti devono essere verdi e GitHub deve riportare l'head esatto
come `MERGEABLE`/`CLEAN`. Restano vietati force push o riscritture di `main`,
bypass deliberato della CI, distruzione di lavoro altrui e merge sapendo che un
controllo rilevante fallisce.

Per Supabase si verificano project ref, ambiente e stato remoto prima di ogni
scrittura; si evolve migration-first; un file già pushato o distribuito è
congelato; non si disabilita RLS globalmente, non si committano segreti e non si
cancellano arbitrariamente dati reali. Fixture e griglie scriventi devono essere
richieste dal task, minime, ripulite anche sull'errore e seguite dalla verifica
dei residui.

Il merge non dimostra che una migrazione sia stata applicata. L'integrazione
Supabase può non partire e una corsa successiva può distribuire il backlog; dopo
il merge si confrontano ledger remoto e file su `origin/main` e si verificano
gli oggetti effettivi. L'ammissione di una fase e il cutover di Fase 13 restano
invece decisioni di prodotto/organizzative separate.

La deroga del 16 agosto 2026 che limitava il merge autonomo alle PR senza
migrazioni è conservata nell'indice storico della PR #47, ma non è più la policy
operativa.

## Conseguenze

- Il ritmo è più lento di una riscrittura "big bang", ma ogni fase è
  revisionabile e — in caso di problemi — reversibile singolarmente senza
  bloccare l'intero progetto.
- Serve una sequenza di ticket piccoli per non perdere la continuità tra
  una fase e l'altra: vedi
  [`docs/MIGRATION_PHASE_1_BACKLOG.md`](../MIGRATION_PHASE_1_BACKLOG.md).
- Durante le Fasi 5–10 esiste temporaneamente doppia UI (TanStack Start
  in produzione, Next.js in costruzione) ma mai doppia scrittura
  autoritativa sugli stessi dati.
