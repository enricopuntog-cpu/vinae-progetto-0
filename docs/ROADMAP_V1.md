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
| 7b | **Stripe Connect, commissione e trattenuta fondi**: account di incasso del venditore, rincaro a netto garantito congelato sull'ordine, fondi sul balance della piattaforma e Transfer separato al rilascio | Sì |
| 8 | `MessagingService` + `NotificationService` (Realtime) | Sì |
| 9 | `ModerationService` + audit persistente | Sì |
| 10 | `AiService` reale via Edge Function | Sì |
| 11 | Estensioni AI ammesse per eccezione: autofill da foto, spunta di completezza documentale, triage di moderazione, ritaglio e sfondo reale | Sì |
| 12 | Club/Community: tre checkpoint 12a/12b/12c. 12a merso (PR #48); 12b+12c aperti insieme e non separabili in merge (PR #49) | Sì |
| 13 | Cutover finale: dismissione `frontend/` + `backend/` | — |

**Rinumerazione del 16 agosto 2026.** Il cutover era la Fase 12 e diventa la
**Fase 13**. La nuova **Fase 12** è Club/Community, e prende quel numero perché
segue direttamente la Fase 11 — estensioni AI — nell'ordine di dipendenza. È
strutturata in tre checkpoint **12a/12b/12c**, dettagliati nel documento
organizzativo della fase, che **non è ancora scritto in questo repo**. Questa
rinumerazione è il prerequisito da mergiare **prima** di aprire il branch della
fase: non è la Fase 12, è ciò che le libera il numero. A differenza dell'11
agosto 2026, **nessun file congelato conserva il numero vecchio**: la ricerca di
«Fase 12»/«Phase 12» in `supabase/migrations/*.sql` e in
`docs/superpowers/plans/` dà **zero risultati**, verificato e non presunto dalla
regola.

**Rinumerazione dell'11 agosto 2026.** Il cutover era la Fase 11 e diventa la
**Fase 12**. La nuova **Fase 11** raccoglie le quattro funzionalità che le
decisioni 7.3, 7.12 e 7.13 hanno ammesso per eccezione durante la Fase 10 e che
il suo unico checkpoint ha lasciato fuori: non sono Fase 10 e non avevano una
fase propria, quindi finivano in nessun posto. Dove il vecchio numero sopravvive
è perché il file è congelato per regola — i due file di `supabase/migrations/`
che lo citano in un commento (uno dei quali è un `comment on column`, quindi
«Fase 11» resta testo vivo nel catalogo di produzione) e il verbale di sessione
`docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md`, che è il
resoconto di una giornata e non un piano vigente.

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

Il trasferimento di proprietà della bottiglia al compratore non è implementato
**dalla 6d-1** — non esiste in `frontend/` e qui sarebbe stata funzionalità
nuova. Era debito dichiarato in
[`MIGRATION_PHASE_1_BACKLOG.md`](MIGRATION_PHASE_1_BACKLOG.md), con il campo già
pronto ad accoglierlo; lo ha chiuso la Fase 7, che alla conferma del pagamento
conia una `bottle_unit` nuova per il compratore e la registra in
`orders.buyer_bottle_unit_id`.

### Stato di integrazione e gate successivo

La Fase 6d-1 è stata integrata in `main` il 30 luglio 2026 tramite PR #14,
merge commit `61e3fde`. La CI finale `30554736346` è verde sull'HEAD
`6bbe4dd`. La verifica post-merge autorizzata separatamente registra 33/33,
11/11, verifier storico 13/13 e residui fixture zero. La correzione additiva
dei messaggi UTF-8 è registrata come migrazione `20260730162046`.

## Fase 6d-2a — provenienza catalogo e percorsi Cantina

**Stato: integrata in `main` tramite PR #17, merge squash
`3037bf4f8fa5269895bb01a998d85bb5f629cd34`.** L'ultimo HEAD della PR è
`c54939213686ea5ca02e26434a3079cfd474be89`; la CI #44, run `30635023614`, è
verde. La migrazione remota è registrata come
`20260731120340 catalog_cellar_paths`; la griglia è 18/18 `PASSA` e i residui
fixture database e Storage documentati sono zero.

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

## Fase 7 — proposte, ordini e pagamenti

**Stato: integrata in `main` con la PR #18 al merge squash `2a47952`.** Include
schema versionato, prenotazione atomica, RLS/grant, limiter condiviso, Edge
Function di checkout, webhook firmato, adapter e test. La migrazione
`20260731135455 phase_7_order_payment_service` **è applicata al progetto reale**:
la distribuisce l'integrazione GitHub di Supabase al merge su `main`, non un
`supabase db push` manuale. Le tabelle di ordine e pagamento esistono e sono a
zero righe.

Il pagamento confermato crea una nuova unità privata per il buyer e conserva
l'unità storica del seller, che il trigger esistente marca come ceduta.
Specifica, gate e limiti di verifica sono in `docs/superpowers/` e
`docs/PHASE_7_VERIFICATION.md`.

## Fase 7b — Stripe Connect, commissione e trattenuta fondi

**Stato: integrata in `main` con la PR #19 al merge squash `5e6b8e4`, il 4 agosto
2026; CI verde sulla run `30900108638`; feature flag spenta.** Estende
lo schema della Fase 7 — non lo sostituisce — con account Connect Express del
venditore, rincaro di piattaforma a percentuale variabile congelato sull'ordine,
trattenuta dei fondi sul balance della piattaforma, rilascio su conferma del
compratore o auto-rilascio a scadenza, e stato `contestato` che blocca entrambi.

Il rincaro non è una percentuale scelta: è il numero che lascia alla piattaforma
un margine netto costante **dopo** la fee del fornitore, arrotondato per eccesso
perché per difetto il margine scenderebbe sotto l'obiettivo di un centesimo. Con
i parametri iniziali — 5% netto, fee di riferimento 1,5% più 0,25 € — la
percentuale effettiva vale 9,20% su 10 €, 6,86% su 100 € e converge a 6,60% sui
prezzi alti. I **tre parametri** sono congelati sull'ordine insieme al risultato:
senza di essi un ordine vecchio resta addebitabile ma non più spiegabile. La fee
davvero trattenuta è misurata a parte e non entra in nessuna decisione.

Il checkout passa dalla Checkout Session ospitata a un PaymentIntent con un solo
Payment Element. **Non porta `transfer_data` né `on_behalf_of`**: è quell'assenza
a far restare i fondi alla piattaforma, e il denaro raggiunge il venditore solo
con un Transfer separato creato al rilascio.

Chiude la sorgente del debito `seller_enabled` aperto dalla 6a: il ruolo diventa
vero solo quando un evento firmato dichiara `charges_enabled` e
`payouts_enabled` insieme. Il gate sulla creazione di annunci resta però spento
— accenderlo prima che i pagamenti siano raggiungibili impedirebbe di vendere a
chiunque.

Restano fuori: interfaccia di gestione delle contestazioni (Fase 9), KYC oltre
l'onboarding ospitato, schedulazione reale del job di rilascio, e qualunque
pagamento reale. Perimetro e debiti in `docs/MIGRATION_PHASE_1_BACKLOG.md`.

### Distribuita non vuol dire percorsa

Verificato sul progetto reale il 5 agosto 2026, in sola lettura: il registro ha
diciannove voci e termina con
`20260805160250 phase_7f_fix_contestazione_enum_cast`; le tre Edge Function
`payments-checkout`,
`connect-onboarding` e `payouts-release` risultano `ACTIVE`. **Non c'è nessun
`apply_migration` in attesa di autorizzazione**: l'integrazione GitHub di
Supabase distribuisce migrazioni e function al merge su `main`, quindi lo schema
di 7, 7b, 7c e la correzione 7f è già live.

Il contenuto applicato è quello a netto garantito, non la prima bozza a
percentuale piatta: `orders` porta `margine_obiettivo_bps`,
`riferimento_stripe_percentuale_bps`, `riferimento_stripe_fisso_cents` e
`commissione_cents`, e `marketplace_config` è versionata.

Ciò che resta vero è più stretto, e va detto così: `orders`, `payments`,
`payouts` e `seller_payout_accounts` sono a **zero righe**, `marketplace_config`
ha la sola riga di configurazione iniziale, nessun percorso dell'interfaccia
raggiunge onboarding o checkout, mentre i percorsi dell'ordine coprono conferma e
contestazione; la feature flag resta spenta. Il checkpoint 7g implementa la
schedulazione dell'auto-rilascio con uno scheduler esterno GitHub Actions, come
prescrive la decisione vincolante 1a, non con `pg_cron`/`pg_net`; la PR #26 è
integrata in `main` con squash `f9c53e0`. Restano aperte configurazione remota e
prima invocazione. Le decisioni sono
chiuse: 1c assegna notifiche
native e rotazione del token a Enrico / `enricopuntog-cpu`, ogni 90 giorni o
subito dopo sospetta esposizione; 1d conferma `0 */6 * * *` e batch 50.
Resta separato anche lo schema 2c per la fee reale: tetto futuro di 5 tentativi,
marcatore derivato da `fee_tentativi >= 5` e nessun nuovo valore di
`public.payment_stato`. Il codice è raggiungibile; nessun denaro lo ha mai percorso.

Fino all'11 agosto 2026 questo punto diceva che la Fase 8 era «nella draft
PR #27»: era vero quando è stato scritto e da allora sono passate tre fasi. Lo
stato aggiornato è nelle sezioni qui sotto.

## Fase 8, Fase 9 e Fase 10 — integrate

- **Fase 8**, messaggi e notifiche: PR #27 al merge squash `4f96864`, 7 agosto
  2026. La migrazione `20260806224517` è la ventesima riga del ledger di
  produzione.
- **Fase 9**, moderazione e audit persistente: PR #32 al merge squash `cd81df6`,
  11 agosto 2026, quattro migrazioni alle righe 21-24 del ledger. La verifica
  successiva al merge è la PR #33, squash `8dd56c0`.
- **Fase 10**, `AiService` reale via Edge Function: PR #35 al merge squash
  `442c98c`, 11 agosto 2026 alle 18:53:14 UTC. Vedi la sezione dedicata.

## Fase 10 — AiService reale via Edge Function

**Stato: chiusa e distribuita, e distribuita spenta.**

Un checkpoint solo, 10a + 10b + 10c dentro la PR #35, sul modello dei 9a/9b/9c
dentro la #32. Il perimetro chiuso è **le tre funzionalità migrate**: chat
Sommelier con storico su Postgres, abbinamento cibo-vino, suggerimento di
catalogazione da testo. Tre Edge Function nuove — `ai-pairing`, `ai-catalogo`,
`ai-sommelier` — dietro un'unica porta (`_shared/ai-gate.ts`) che applica in
ordine origine, metodo, flag, bearer, identità, stato utente e bucket orario;
una migrazione, `20260811160000_phase_10b_sommelier_storico`, venticinquesima
riga del ledger.

**`AI_ENABLED` resta spento** finché Enrico non configura chiave e budget del
provider — decisione 7.11, scadenza impegnata **lunedì 18 agosto 2026**. Non è
una dimenticanza da correggere prima di considerare la fase chiusa: il flag
fallisce chiuso per costruzione, ed è ciò che ha reso sicuro distribuire la fase
prima che le chiavi esistessero. Fino ad allora ogni chiamata risponde
«funzionalità non disponibile» senza guardare un token.

Restano fuori le quattro funzionalità ammesse per eccezione: sono la Fase 11.

## Fase 11 — estensioni AI ammesse per eccezione

**Stato: non iniziata. Nessun branch.**

Le quattro funzionalità che le decisioni 7.3, 7.12 e 7.13 hanno ammesso per
eccezione esplicita durante la Fase 10 — autofill da foto (7.3a), spunta di
completezza documentale (7.3b), triage di moderazione (7.12), ritaglio e sfondo
reale (7.13). Sono le prime funzionalità nuove autorizzate dall'inizio della
migrazione, e sono state autorizzate per nome: la regola «nessuna funzionalità
nuova» continua a valere per tutto il resto.

Le quattro decisioni che le descrivono sono **già chiuse** e stanno nella
sezione 7 di [`PHASE_10_AI_SERVICE_SPEC.md`](PHASE_10_AI_SERVICE_SPEC.md).
Manca però tutto il resto, e non è poco: Storage (bucket, privacy, ciclo di
vita), limiti di dimensione dei file, tipi MIME ammessi per le foto,
l'integrazione PhotoRoom per la 7.13. Sull'esito del triage la decisione c'è già
— **colonna persistita**, non ricalcolo a ogni apertura del pannello — e implica
una migrazione. Due delle quattro portano una migrazione ciascuna.

Ciascuna funzionalità **ha la propria sessione di spec prima del codice**, sul
modello dei 9a/9b/9c separati, e non è chiaro che debbano stare tutte nella
stessa PR.

## Fase 12 — Club/Community

**Stato: checkpoint 12a merso. 12b + 12c in corso, in una PR sola.**

Prende il numero 12 perché segue direttamente la Fase 11 — estensioni AI —
nell'ordine di dipendenza, e per questo il cutover si è spostato alla 13. È
strutturata in **tre checkpoint, 12a/12b/12c**, dettagliati nel **documento
organizzativo della fase**, che **non è ancora scritto in questo repo**: finché
non lo è, il contenuto di 12b e 12c non si deduce da qui.

### Checkpoint 12a — club in sola lettura, con follow reale

**Merso** come squash `e2132ee`, [PR #48](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/48),
aperto il 17 agosto 2026 sul branch `migration/phase-12a-club-readonly`.

Perimetro: `/community` e `/community/[slug]` tornano raggiungibili su righe
reali, un utente autenticato segue e smette di seguire un club, e **nessun
contenuto è scrivibile dagli utenti** — niente post, niente risposte, niente
reazioni. Quelli sono il 12b, e il 12a non crea nemmeno una tabella vuota che
li aspetti: la superficie esiste da quando esiste la tabella, non da quando la
si popola. I due tab che li conterrebbero restano visibili e lo dichiarano.

Contiene: la migrazione additiva `20260817090000_phase_12a_club_readonly.sql`
(`clubs`, `club_memberships`, la vista `public_clubs`), `ClubService` reale con
firma `Result<T,E>`, le due pagine ricostruite — la #44 le aveva cancellate — e
il ritorno della voce **Club** nell'header.

**Non contiene, ed è un cancello separato ciascuno:** l'applicazione dell'SQL
al progetto Supabase reale; il fixture dei sette club iniziali, che è una
*proposta* in `supabase/queries/` e non un file che qualcosa esegue da solo;
l'esecuzione della griglia `supabase/tests/12a_club_readonly_statica.sql`, che
**non è mai stata eseguita da nessuna parte**.

Questa PR porta file sotto `supabase/migrations/`, quindi **non rientra
nell'eccezione di merge autonomo** registrata dalla PR #47: il merge resta
esplicito.

### Checkpoint 12b + 12c — contenuti dei club e loro moderazione

Aperti **insieme** il 17 agosto 2026 sul branch `migration/phase-12bc-club-content`,
draft [PR #49](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/49).

**Non si separano in merge, in nessuna circostanza.** La 12b introduce testo
pubblico scrivibile dagli utenti; la 12c introduce il modo di segnalarlo e
rimuoverlo. Mergiare la 12b da sola aprirebbe una finestra — di durata decisa da
quando la 12c viene approvata — in cui chiunque pubblica su una superficie
pubblica e nessuno può segnalare ciò che legge. È la stessa regola che la
decisione **7.6a** aveva già applicato al contrario, escludendo `post` e
`commento` dai bersagli finché i club non avessero schema.

#### Fase 12b+12c — scrittura di contenuti nei club, ammessa per eccezione

La scrittura di contenuti pubblici nei club (`club_posts`, `club_post_risposte`,
`club_post_like`) è ammessa per eccezione esplicita e per nome da Enrico, in
sessione di coordinamento della Fase 12. È la seconda funzionalità nuova
autorizzata durante la migrazione dopo le quattro della Fase 11 — «niente
funzionalità nuove durante la migrazione» non è decaduta: continua a valere per
tutto ciò che una sessione non ha chiesto per nome. L'ammissione è condizionata e
inseparabile dalla 12c: nessun contenuto pubblico scrivibile va in produzione
senza un modo per segnalarlo, la stessa regola già valida per la 7.6a.

**La decisione 7.6a è adempiuta, non riaperta.** Rinviava `post` e `commento`
«finché i club non hanno schema Supabase»: la 12a ha dato schema ai club ma non
ai post, quindi la condizione reggeva ancora. La 12b dà schema a post e risposte,
e con questo i due valori hanno finalmente una tabella in cui risolversi. La 12c
li aggiunge a `report_target_tipo`.

Contiene **tre** migrazioni additive, e il numero non è una preferenza:
`report_target_tipo` è un **enum**, e in PostgreSQL un valore aggiunto a un enum
non è utilizzabile nella transazione che lo aggiunge — Supabase applica ogni file
nella propria. Il file di mezzo esiste solo per essere quella transazione.

- `20260817120000_phase_12b_club_content.sql` — le tre tabelle, RLS a grant di
  colonna, i guard, le viste `public_club_posts` e `public_club_post_risposte`
- `20260817120500_phase_12c_report_target_enum.sql` — **solo** i due `add value`
- `20260817121000_phase_12c_club_moderation.sql` — i motivi ammessi, le due
  colonne di bersaglio, i vincoli ridefiniti, `segnalazione_invia` estesa, il
  motore di rimozione logica e i due rami nuovi di `moderazione_rimozione` e
  `moderazione_ripristino`

Più il frontend: `ClubService` con sei metodi nuovi, il componente
`ClubDiscussioni` condiviso dalle due pagine, e `ReportDialog` cablato su post e
risposte con i due bersagli nuovi.

**La griglia `supabase/tests/12bc_club_content_moderazione.sql` è stata
eseguita** — 47 PASSA / 0 FALLISCE su PostgreSQL 15.19 locale, dopo aver
applicato dal vuoto tutte e 29 le migrazioni ciascuna nella propria transazione.
È la prima griglia di questo repository che non sia solo versionata. **Non è mai
stata eseguita sul progetto reale**, e farlo resta un'autorizzazione separata per
griglia: questa **scrive**.

**Non contiene, ed è un cancello separato ciascuno:** l'applicazione dell'SQL al
progetto Supabase reale; il fixture dei club, ancora una proposta in
`supabase/queries/`; l'esecuzione della griglia sul progetto reale. Porta file
sotto `supabase/migrations/`, quindi **non rientra nell'eccezione di merge
autonomo** della PR #47: il merge resta esplicito di Enrico.

## Fase 13 — cutover finale

**Stato: non iniziato.** Era la Fase 11 fino all'11 agosto 2026 e la Fase 12
fino al 16 agosto 2026.

Dismissione di `frontend/` (TanStack Start) e `backend/` (FastAPI/MongoDB) solo
dopo parità funzionale verificata e approvazione esplicita separata.

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
