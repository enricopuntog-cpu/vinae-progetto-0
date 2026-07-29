# Roadmap v1 — Migrazione Next.js + Supabase

Questo documento fotografa lo stato reale del progetto dopo Sprint 0 e
Sprint 1 e definisce la sequenza di fasi della traccia "Migrazione",
separata dalla numerazione "Sprint". Una fase alla volta, una branch,
una PR — mai tutte insieme.

## Stato reale verificato

- **Sprint 0** (PR #1, merged in `main` al commit `836d8d8`): hardening
  pre-release. Pagamenti Stripe con stato reale solo da
  `payment_status=paid` + webhook firmato/idempotente, allowlist redirect,
  CORS configurabile, autenticazione e ruoli server-side, rate limiting,
  `AIProvider` astratto, Mongo asincrono, storico Sommelier con
  ownership/TTL, rimozione config Lovable/Emergent. Test automatici
  introdotti: 13 frontend, 36 backend. CI verde.
- **Sprint 1** (PR #2, merged in `main` al commit `67dd4dd`): lo store
  frontend monolitico (`vinea-store.tsx`, ~700 righe) è stato suddiviso in
  8 slice di dominio testabili (`auth`, `profile`, `cellar`, `listings`,
  `order`, `messaging`, `moderation`, `clubs`) e la business logic mescolata
  in 4 pagine route è stata estratta in hook dedicati (`useSellWizard`,
  `useCellar`, `useOrderActions`, `useModerationActions`). Test frontend
  passati da 13 a 73. Nessuna modifica comportamentale visibile.
- **Stato attuale**: `frontend/` (TanStack Start) e `backend/`
  (FastAPI/MongoDB) sono l'unica versione funzionante e servita. Il
  backend FastAPI/MongoDB è dichiaratamente transitorio: valida i
  contratti di dominio con adapter sostituibili, non è l'architettura di
  produzione scelta.

## Perché questa è una migrazione, non un altro refactor

La destinazione (Next.js App Router + Supabase) era già pianificata prima
di Sprint 0/1, in `frontend/docs/MIGRATION_TO_NEXTJS.md` e
`frontend/docs/BACKEND_CONTRACTS.md` — non è una decisione improvvisata in
questa fase. Le 8 slice dello store create in Sprint 1 corrispondono quasi
1:1 alle interfacce di servizio già previste in quei documenti
(`AuthService`, `ProfileService`, `CellarService`, `ListingService`,
`ProposalService`+`OrderService`, `MessagingService`, `ClubService`,
`NotificationService`, `ModerationService`): la base di dominio è già
pronta per essere collegata a implementazioni reali, senza un secondo
refactor dello stato.

Dettagli architetturali completi nelle ADR:

- [ADR 001 — Architettura target](adr/001-target-architecture.md)
- [ADR 002 — Strategia di migrazione](adr/002-migration-strategy.md)

## Principi vincolanti per tutta la traccia

- **Migrazione progressiva**: `frontend/` + `backend/` restano l'unica
  versione autoritativa e servita finché la versione Next.js/Supabase non
  raggiunge parità funzionale verificata. Non deve esistere un momento in
  cui il sito è rotto o offline.
- **Mai due backend autoritativi per lo stesso dominio nello stesso
  momento**: quando un dominio (es. Auth) viene migrato a Supabase, il
  vecchio percorso FastAPI/MongoDB smette di essere la fonte di verità
  scrivibile per quel dominio specifico.
- **Una fase = una branch = una PR draft**, mai più fasi in parallelo
  sulla stessa area. Nessuna fase successiva parte senza approvazione
  esplicita riportata nella zona organizzativa.
- **Nessuna funzionalità nuova durante la migrazione**: l'obiettivo è
  parità comportamentale con l'app attuale, non un miglioramento del
  prodotto.

## Sequenza delle fasi

Il dettaglio di ogni ticket è in
[`MIGRATION_PHASE_1_BACKLOG.md`](MIGRATION_PHASE_1_BACKLOG.md).

| Fase | Contenuto | Tocca dati reali? |
| --- | --- | --- |
| 1 | Piano, ADR, pulizia backlog | No — solo documentazione |
| 2 | Scaffold Next.js 15 App Router + copia invariata di UI/dati/config | No |
| 3 | Porting pagine statiche con mock esistenti **+** store (8 slice) montato come client provider Next.js — fasi fuse, vedi nota sotto | No — dati ancora mock |
| ~~4~~ | *(assorbita in Fase 3, vedi sotto — numerazione 5+ invariata)* | — |
| 5 | `AuthService` reale su Supabase (email + magic link) | Sì — primo dominio reale |
| 6a | Schema `wines`/`bottle_units`/`listings` + RLS, `/esplora` portata, marketplace in **sola lettura** su Supabase | Sì |
| 6b | Wizard `/vendi`, scritture di `ListingService`, transizioni di stato, upload foto | Sì |
| 6c-1 | **Cantina**, schema: ambienti/moduli/slot, metadati di bevuta su `wines`, funzioni di posizionamento. Nessuna interfaccia | Sì |
| 6c-2 | **Cantina**, interfaccia: `/cantina` portata, viste, visualizzazione 3D, collegamento bottiglia → posizione | Sì |
| 7 | `OrderService` + `ProposalService` + `PaymentService` (Stripe) | Sì |
| 8 | `MessagingService` + `NotificationService` (Realtime) | Sì |
| 9 | `ModerationService` + audit persistente | Sì |
| 10 | `AiService` reale via Edge Function | Sì |
| 11 | Cutover finale: dismissione `frontend/` + `backend/` | — |

## Correzioni apportate in Fase 1

- `frontend/docs/TODO.md`: rimossi due riferimenti ormai falsi ("nessun
  test automatico", "store monolitico da ~750 righe") e corretta la voce
  su `Cellar3D` per non implicare che l'attuale lazy-loading non esista
  già.
- `frontend/docs/STATE_MACHINES.md`: il riferimento a "tutte le
  transizioni vivono in `vinea-store.tsx`" è stato aggiornato per
  riflettere la suddivisione in 8 slice + 4 hook di Sprint 1.

## Correzione apportata in Fase 3: fusione con la ex Fase 4

Il piano originale assumeva che le pagine assegnate a Fase 3 (home,
community, dettaglio annuncio) e i componenti condivisi da adattare al
routing Next.js (`WineCard`, `FoodPairing`, `Layout`, `States`) fossero
"router-only" — dipendenti cioè solo dall'API di routing, non dallo
store applicativo — rimandando il montaggio dello store a una Fase 4
separata.

Durante l'esecuzione di Fase 3, l'ispezione diretta del codice sorgente
ha mostrato che questa assunzione era falsa: `WineCard`, `FoodPairing` e
`Layout` (3 dei 4 componenti "router-only" previsti) chiamano `useVinea()`
per funzionalità reali (preferiti, follow, notifiche, stato annunci), e
tutte le pagine candidate a Fase 3 chiamano `useVinea()` direttamente per
funzionalità interattive già esistenti in `frontend/` (preferiti,
proposte d'acquisto, follow community, apertura bottiglie, ecc.). Non
esisteva quindi una versione "solo mock, zero store" di queste pagine che
non richiedesse o disabilitare funzionalità già esistenti, o forzare un
collegamento provvisorio non richiesto — entrambe le opzioni vietate dai
vincoli della traccia.

Individuato il blocco, l'esecuzione si è fermata prima di improvvisare
una soluzione (come da regola esplicita della traccia) e la decisione è
stata riportata alla zona organizzativa con le tre opzioni possibili
(montare lo store subito, restringere Fase 3 alle sole pagine
realmente statiche, oppure portare le pagine con le funzionalità
store-dipendenti visibilmente disattivate). La zona organizzativa ha
scelto di montare lo store ora, assorbendo di fatto la ex Fase 4
dentro Fase 3, con questi vincoli confermati fermi:

- zero servizi reali collegati (nessun Supabase, nessuno Stripe, nessuna
  AI reale);
- tutti i dati restano mock (`src/data/**`, invariati);
- nessuna funzionalità nuova rispetto a quelle già esistenti in
  `frontend/`;
- nessun cambiamento di design o di comportamento visibile rispetto a
  `frontend/` (l'unica eccezione nota e documentata è l'assistente
  Sommelier, escluso perché dipende dal layer servizi reale — vedi
  rapporto di Fase 3).

Questa è una correzione di pianificazione dichiarata, non una deviazione
silenziosa: la numerazione delle fasi successive (5 in poi) resta
invariata, e la Fase 4 originale non esiste più come fase separata — il
suo contenuto (`vinea-store.tsx` montato come client provider) è stato
consegnato dentro la Pull Request di Fase 3.

## Correzioni apportate in Fase 6a

### La Fase 6 si divide in tre

Il piano originale trattava la Fase 6 come un blocco unico
(`ListingService` + `WineCatalogService`). L'esecuzione ha mostrato che
conteneva tre lavori distinti, con rischi diversi.

Il primo problema è che **le pagine da collegare non esistevano tutte**.
La traccia assumeva di trovare in `frontend-next/` le pagine Annunci e
Catalogo già portate; in realtà la Fase 3 aveva portato solo
`/annuncio/[id]`, mentre `/esplora` (ricerca, 17,6 KB) e `/vendi`
(wizard di creazione, 24,4 KB) non erano mai state migrate — e `/home`
già puntava a entrambe con link che rispondevano 404. Collegare la
scrittura a un wizard inesistente significava portare in Fase 6 un lavoro
di porting di dimensioni paragonabili alla Fase 3.

Il secondo è che **lettura e scrittura hanno superfici di rischio
diverse**: la lettura pubblica si verifica guardando una pagina, la
scrittura richiede transizioni di stato, upload di immagini e una prova
RLS incrociata fra account. Il backlog di Fase 1 lo aveva già intuito
("Letture pubbliche prima, scritture dopo") senza però separarne le fasi.

Divisione adottata, approvata prima dell'esecuzione:

- **6a** — schema (`wines`, `bottle_units`, `listings`), RLS, vista
  pubblica, porting di `/esplora`, marketplace in sola lettura su dati
  reali. Nessuna via di scrittura esposta.
- **6b** — wizard `/vendi`, metodi di scrittura di `ListingService`,
  funzioni di transizione (`bozza → attivo`, `attivo → sospeso`,
  `attivo → scaduto`) e caricamento foto.
- **6c** — Cantina.

### La Cantina non era nella sequenza, e serviva

`bottle_units` nasce in 6a per una ragione precisa: un annuncio deve
vendere una bottiglia identificabile, non un vino generico, altrimenti il
vincolo "una bottiglia, un solo annuncio attivo" non è applicabile dal
database. Ma la Cantina — posizione fisica, ambienti, moduli, slot,
visualizzazione 3D (`Cellar3D`) — **non compariva in nessuna fase** di
questo documento, pur essendo una funzionalità già presente e visibile in
`frontend/src/routes/cantina.tsx`. Senza una fase dedicata sarebbe rimasta
l'unico dominio migrabile mai pianificato.

Diventa quindi la **Fase 6c**, subito dopo il marketplace e prima degli
ordini: dipende da `bottle_units` (creata in 6a) e la Fase 7 ha bisogno di
sapere quale unità fisica cambia proprietario quando un ordine si chiude.

Conseguenza dichiarata sullo schema: `listings.quantita` resta fissa a 1
per tutta la 6a/6b. La colonna esiste perché l'interfaccia mostra
"N bottiglie disponibili", ma diventerà un conteggio reale solo quando la
6c permetterà di collegare più unità allo stesso annuncio. Il commento SQL
sulla colonna lo dice, così non sembra un residuo dimenticato.

## Correzione apportata in Fase 6b: la gestione annunci non esisteva

Il perimetro della 6b prevedeva le scritture "creazione, modifica,
sospensione". L'esecuzione ha mostrato che **in `frontend/` esiste solo la
creazione**: non c'è nessuna interfaccia con cui un venditore modifichi o
sospenda un proprio annuncio. `/vendi` crea e basta, `/vendite` elenca gli
ordini ricevuti, `toggleInVendita` in `/cantina` è un flag mock sulla
cantina e non un annuncio, `setListingStatus` è usata soltanto da `/admin`
(moderazione, Fase 9). La funzione `listingActionsFor()` in
`data/moderation.ts` elenca "Modifica, Metti in pausa, Ritira" ma non è
chiamata da nessuna parte: sono dati di riferimento per la galleria degli
stati, non comandi.

Costruire quei comandi sarebbe stata una funzionalità nuova, che questa
traccia vieta. La 6b si è quindi fermata dove finisce la parità:

- le funzioni SQL di transizione e i metodi di `ListingService` esistono e
  sono verificati a livello di database (griglia RLS di fase);
- nessun comando nuovo compare nell'interfaccia.

Decisione confermata dalla zona organizzativa prima della chiusura di fase.
Quando la gestione annunci diventerà un requisito di prodotto sarà una fase
sua, non un'aggiunta silenziosa dentro una migrazione.

Conseguenza collaterale sul vincolo "una bottiglia, un solo annuncio
attivo": **non è raggiungibile dal wizard**, perché ogni creazione conia una
`bottle_unit` nuova — `/vendi` non ha nessun selettore di cantina, si
descrive una bottiglia e non se ne sceglie una. Il messaggio leggibile vive
in `listing_pubblica`, che è dove il vincolo scatta (l'indice è parziale e
non copre le bozze), e diventerà raggiungibile dall'interfaccia con la 6c,
quando "metti in vendita questa bottiglia" partirà da un'unità già esistente.

## Cosa NON è ancora deciso

- Hosting di produzione per il frontend Next.js (Vercel o altro).
- Piano Supabase (tier, regione dati, residenza dati per requisiti
  legali su vendita di alcolici).
- Provider email transazionali definitivo (Resend è l'ipotesi in
  `BACKEND_CONTRACTS.md`, non confermato).
- Strategia concreta di feature flag per il rollout progressivo per
  dominio.
- Verifica legale su vendita di alcolici, età, privacy, marketplace —
  esplicitamente fuori scope tecnico, richiede validazione dedicata prima
  di qualunque fase che tocchi dati reali di pagamento o identità.
