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
quel numero perché segue direttamente la Fase 11 nell'ordine di dipendenza. È
strutturata in tre checkpoint 12a/12b/12c, dettagliati nel documento
organizzativo della fase, non ancora scritto in questo repo. Vale per essa la
stessa osservazione fatta qui sotto per la Fase 11: **non è un dominio migrato**,
quindi resta fuori dal punto 2 e non allarga il perimetro «un dominio alla volta
collegato a Supabase», che si è chiuso con la Fase 10. Questa ADR ne registra il
numero e non ne apre la fase.

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
- Nessuna fase introduce funzionalità non richiesta dal prompt della fase
  stessa; l'obiettivo è parità, non miglioramento del prodotto.
- Ogni fase che tocca dati reali richiede: migrazioni pulite, policy RLS
  verificate, test pgTAP dove applicabile.
- Ogni fase termina con un rapporto strutturato riportato nella zona
  organizzativa; nessuna fase successiva parte senza approvazione
  esplicita.

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
