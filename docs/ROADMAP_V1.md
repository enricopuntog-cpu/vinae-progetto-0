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
| 2 | Scaffold Next.js App Router + copia invariata di UI/dati/config; versione vincolata nel package manifest | No |
| 3 | Porting pagine statiche con mock esistenti **+** store (8 slice) montato come client provider Next.js — fasi fuse, vedi nota sotto | No — dati ancora mock |
| ~~4~~ | *(assorbita in Fase 3, vedi sotto — numerazione 5+ invariata)* | — |
| 5 | `AuthService` reale su Supabase (email + magic link) | Sì — primo dominio reale |
| 6a | Schema `wines`/`bottle_units`/`listings` + RLS, `/esplora` portata, marketplace in **sola lettura** su Supabase | Sì |
| 6b | Wizard `/vendi`, scritture di `ListingService`, transizioni di stato, upload foto | Sì |
| 6c-1 | **Cantina**, schema: ambienti/moduli/slot, metadati di bevuta su `wines`, funzioni di posizionamento. Nessuna interfaccia | Sì |
| 6c-2 | **Cantina**, interfaccia: `/cantina` portata, viste, visualizzazione 3D, collegamento bottiglia → posizione | Sì |
| 6d-1 | **Invarianti di sicurezza**: confini di autorizzazione fra bottiglie, annunci e ruoli; controllo età server-side; invarianti bottiglia–annuncio. Nessuna nuova fonte di dati | Sì |
| 6d-2a | **Provenienza catalogo e percorsi Cantina**: distinzione catalogo curato/utente, aggiunta privata/pubblica/vendita, inizializzazione atomica Cantina e home con dati reali | Sì |
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

## Correzioni apportate in Fase 6c-2

### Due difetti che solo i dati veri potevano mostrare

Il primo: **il comando "Sposta" era irraggiungibile**. In `frontend/` si apre
solo cliccando una bottiglia già presente nella scena 3D, e nei dati mock ogni
bottiglia nasce con uno `storageLocationId`. Su dati veri nessuna bottiglia
nasce collocata — `listing_crea` non assegna posizioni — quindi la scena parte
vuota e `cellar_posiziona` sarebbe rimasta una funzione senza porta. Risolto
aggiungendo un elenco "Da collocare" da cui si apre **lo stesso** dialogo: un
punto d'ingresso in più, non un comando nuovo.

Il secondo: **una bottiglia creata dal wizard non compariva in cantina** fino
al ricaricamento della pagina. Il wizard scrive tramite `ListingService`
mentre la cantina la tiene lo store, e nulla avvisava il secondo. In
`frontend/` il difetto non può esistere, perché lì la pubblicazione è un toast
che non scrive nulla e la cantina non cambia mai.

Nessuno dei due è emerso da lettura del codice: entrambi sono comparsi durante
la prova end-to-end su account reale.

### Divergenze chiuse

`/cantina` esiste, quindi si chiude la divergenza dichiarata in 6b: dopo
pubblicazione, catalogazione e salvataggio bozza il wizard torna in cantina,
come in `frontend/`, invece di mandare all'annuncio o restare fermo.

Si chiude anche la conseguenza collaterale registrata in 6b: il vincolo "una
bottiglia, un solo annuncio attivo" è ora **raggiungibile dall'interfaccia**,
e il messaggio leggibile di `listing_pubblica` arriva al posto del 23505.

## Fase 6d-1 — una sotto-fase fra la Cantina e gli ordini

### Perché sta qui e non dentro la Fase 7

La 6a, la 6b e la 6c hanno costruito, una alla volta, le tre tabelle su cui una
vendita si appoggia. Ognuna ha lasciato dietro di sé un confine ragionevole per
ciò che esisteva allora e insufficiente per ciò che è arrivato dopo: il `GRANT`
di tabella su `bottle_units` era innocuo finché l'unità aveva quattro colonne, e
lo ha smesso di essere quando la 6c-1 vi ha aggiunto note personali, date di
apertura pianificata e override della finestra di bevuta.

Metterci mano dentro la Fase 7 avrebbe significato aprire ordini e pagamenti
sopra fondamenta di cui si sapeva già che perdevano. La 6d-1 le chiude prima, e
non tocca né ordini né proposte né pagamenti.

### La decisione chiusa: un annuncio, una bottiglia, un solo annuncio non terminale

**Un annuncio vende una sola bottiglia fisica, e una bottiglia può avere un solo
annuncio non terminale.** Non terminali sono `bozza`, `in_revisione`,
`modifiche_richieste`, `attivo`, `riservato`; i quattro terminali (`sospeso`,
`scaduto`, `venduto`, `rifiutato`) restano come storico, in numero qualunque.

La 6a aveva applicato solo la metà pubblica della regola — l'indice copriva
`('attivo','riservato')` — e la 6b lo aveva dichiarato di proposito: «una bozza in
più non fa danno». Con la Cantina il danno è comparso: dalla 6c-2 «metti in
vendita questa bottiglia» parte da un'unità esistente, quindi due clic
producevano due schede della stessa bottiglia, e chi ne pubblicava una scopriva
solo al momento di pubblicare la seconda che non poteva.

Alla regola si aggiunge il caso che l'indice non poteva vedere: **una bottiglia
venduta non torna in vendita.** Prima della 6d-1 il passaggio a `'venduto'` faceva
uscire l'annuncio dall'indice e liberava la bottiglia — comportamento voluto per
un annuncio scaduto o ritirato, dove la bottiglia è ancora del venditore, ma non
per una vendita conclusa, dove non lo è più. Lo chiude `bottle_units.ceduta_at`.

Decisione chiusa: non è più una scelta aperta per le fasi successive.

### Cosa è cambiato di proposito, ed è visibile

Il design non è stato toccato. Cambia però ciò che il database accetta, e in tre
punti un utente può incontrare un errore dove prima non c'era:

- aprire o togliere dalla cantina una bottiglia con un annuncio attivo o
  riservato viene rifiutato, con un messaggio che dice di sospendere l'annuncio;
- creare un secondo annuncio su una bottiglia che ne ha già uno in corso viene
  rifiutato;
- mettere in vendita richiede una data di nascita dichiarata e la maggiore età.
  La navigazione pubblica resta disponibile senza.

Tutti e tre erano già impossibili *nell'intenzione*; solo che il database li
permetteva.

### Cosa NON contiene, e va detto

Nessuno Stripe Connect e nessun KYC. Il controllo dell'età è una dichiarazione
auto-riferita verificata lato server, non un accertamento d'identità:
**l'abilitazione venditore e l'onboarding del conto di pagamento andranno
richiesti prima di qualunque payout reale.** Resta valida la voce «verifica
legale su vendita di alcolici, età, privacy, marketplace» qui sotto.

Il trasferimento di proprietà della bottiglia al compratore non è implementato —
non esiste in `frontend/` e sarebbe funzionalità nuova. È debito dichiarato in
[`MIGRATION_PHASE_1_BACKLOG.md`](MIGRATION_PHASE_1_BACKLOG.md), con il campo già
pronto ad accoglierlo.

### Stato di integrazione e gate successivo

La Fase 6d-1 è stata integrata in `main` il 30 luglio 2026 tramite PR #14,
merge commit `61e3fde`. La CI finale `30554736346` è verde sull'HEAD
`6bbe4dd`. La verifica post-merge autorizzata separatamente registra 33/33,
11/11, verifier storico 13/13 e residui fixture zero. La correzione additiva
dei messaggi UTF-8 è registrata come migrazione `20260730162046`.

## Fase 6d-2a — provenienza catalogo e percorsi Cantina

**Stato sul branch `migration/phase-6d-2a-catalog-cellar-paths`: implementazione
locale in corso; SQL remoto non applicato.**

Questa sotto-fase viene prima degli ordini perché `listing_crea` può oggi
inserire un vino tramite `SECURITY DEFINER` senza distinguere una scheda curata
dallo staff da una descrizione immessa da un utente.

Deve:

- introdurre una provenienza autoritativa del catalogo;
- separare aggiunta privata, aggiunta pubblica e vendita da bottiglia esistente;
- rendere atomica l'inizializzazione ambiente/modulo della Cantina;
- collegare alla home solo riepiloghi reali;
- preservare RLS, privilegi, viste chiuse e invarianti della 6d-1.

La soluzione sul branch introduce provenienza `staff`/`utente`, una RPC di
catalogazione senza annuncio, una RPC di vendita che accetta soltanto una
`bottle_unit` esistente, un bucket privato per le foto della Cantina e una RPC
transazionale per ambiente più modulo iniziale. La home legge i riepiloghi
Cantina dal servizio reale.

Non contiene ordini, proposte, pagamenti o trasferimento di proprietà. Le prove
33/33, 11/11, 13/13 e residui fixture zero sono documentate nel rapporto
post-merge; la fase non può iniziare finché quel rapporto non è integrato e la
fase non è autorizzata esplicitamente.

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
