# Backlog — Traccia Migrazione (dopo Fase 1)

Un ticket = una fase futura. Ogni fase = una branch dedicata = una Pull
Request in draft. Nessuna fase parte senza approvazione esplicita della
fase precedente riportata nella zona organizzativa. Vedi
[`ROADMAP_V1.md`](ROADMAP_V1.md) per il contesto e le
[ADR](adr/001-target-architecture.md) per le decisioni architetturali.

## Fase 2 — Scaffold Next.js

**Branch**: `migration/phase-2-nextjs-scaffold`

Scaffold Next.js App Router + Tailwind v4 + shadcn/ui in una directory
nuova, separata da `frontend/` (nome esatto da confermare in fase, es.
`web-next/`). Copia invariata: `styles.css`, `components/ui/**`,
`components/vinea/**` (aggiungendo `"use client"` dove necessario),
`data/**`, `config/**`, `lib/wine-images.ts`, `lib/utils.ts`, `assets/**`.
Nessun dato reale, nessuna route ancora collegata a logica applicativa.
`frontend/` esistente non viene toccato né disattivato.

## Fase 3 — Porting pagine con mock esistenti + store come client provider

**Branch**: `migration/phase-3-static-pages`

> **Nota di correzione** (vedi [`ROADMAP_V1.md`](ROADMAP_V1.md#correzione-apportata-in-fase-3-fusione-con-la-ex-fase-4)
> per il dettaglio completo): questo ticket assorbe la ex "Fase 4 — Store
> come client provider" perché, in fase di esecuzione, è emerso che i
> componenti condivisi (`WineCard`, `FoodPairing`, `Layout`) e tutte le
> pagine di questa fase dipendono già da `useVinea()` per funzionalità
> reali esistenti in `frontend/`, rendendo impossibile un porting
> "solo mock, zero store" senza disabilitare funzionalità o forzare un
> collegamento provvisorio. Decisione approvata dalla zona organizzativa:
> montare lo store ora. La numerazione delle fasi successive (5+) non
> cambia; la Fase 4 originale non è più una fase a sé stante.

Portare le pagine senza stato server reale (home, home utente, dettaglio
annuncio, community index e dettaglio) su Next.js con gli stessi dati
mock già in `src/data/**`, mapping route secondo la tabella in
`frontend/docs/MIGRATION_TO_NEXTJS.md`. Montare `vinea-store.tsx` (le 8
slice di Sprint 1, invariate) come client provider in `app/providers.tsx`,
importato da `app/layout.tsx`. Demo iso-funzionale su Next.js: stesse
interazioni di oggi, dati ancora mock, zero servizi reali collegati
(nessun Supabase, nessuno Stripe, nessuna AI reale). Componenti/pagine
che dipendono dal layer servizi reale (l'assistente Sommelier) restano
fuori scope e sono documentati come tali nel rapporto di fase.

## Fase 5 — AuthService reale (Supabase)

**Branch**: `migration/phase-5-auth-service`

Implementare `AuthService` su Supabase Auth (email + magic link).
Tabelle `profiles` e `user_roles` (separata, anti-escalation) con RLS e
funzione `has_role()` SECURITY DEFINER. Route group `(auth)` con
middleware. Le altre interfacce di `src/services/types.ts` restano mock.
Primo dominio a scrivere su dati reali: da qui in poi FastAPI smette di
essere fonte di verità per l'identità.

## Fase 6a — Schema annunci e marketplace in lettura

**Branch**: `migration/phase-6a-listings-catalog`

Tabelle `wines` (catalogo condiviso), `bottle_units` (unità fisica, senza
UI) e `listings`, con RLS: `SELECT` pubblica solo per `stato = 'attivo'`,
`stato` mai scrivibile dal client (escluso dai `GRANT` di colonna), vincolo
`UNIQUE` parziale che impedisce due annunci attivi sulla stessa bottiglia.
Vista `public_listings` per esporre il venditore senza allargare la RLS di
`profiles`. Porting di `/esplora` da `frontend/`, e collegamento di
`/esplora`, `/annuncio/[id]`, `/` e `/home` ai dati reali in sola lettura.

Divergenza dichiarata dal contratto: `has_role('seller_enabled')` **non**
viene applicato. Nessuna interfaccia assegna quel ruolo (`user_roles` è
scrivibile solo da `service_role`) e la verifica venditore non è un dominio
migrato; applicarlo renderebbe impossibile creare annunci anche in 6b.
Da riprendere quando esisterà la verifica venditore.

## Fase 6b — Scritture annunci e wizard /vendi

**Branch**: `migration/phase-6b-listings-write`

Porting di `/vendi` da `frontend/`, metodi di scrittura di
`ListingService`, funzioni di transizione `SECURITY DEFINER`
(`bozza → attivo`, `attivo → sospeso`, `attivo → scaduto`; le transizioni
di moderazione e vendita restano alle Fasi 9 e 7). Caricamento foto:
bucket dedicato, upload firmato, limiti MIME e dimensione — necessario da
qui in poi, perché fino alla 6a le immagini sono asset statici locali.

`listing_crea` è una funzione e non un `INSERT` dal client perché la
creazione attraversa `wines`, che la 6a rende scrivibile solo da
admin/moderator: il wizard parte da testo digitato, non da un vino già in
catalogo. La modifica dei campi di contenuto resta invece un `UPDATE`
diretto, coperto dai `GRANT` di colonna e dalla policy
`listings_update_own` già definiti in 6a — quella lista non cambia.

Divergenze dichiarate rispetto a `frontend/`:

- **Nessun comando di modifica o sospensione nell'interfaccia.** In
  `frontend/` non esiste: `/vendi` crea soltanto, `/vendite` sono gli
  ordini, `toggleInVendita` in `/cantina` è un flag mock, `setListingStatus`
  è usata solo da `/admin` (moderazione, Fase 9) e `listingActionsFor()` in
  `data/moderation.ts` non è chiamata da nessuna parte. Le funzioni SQL e i
  metodi di `ListingService` esistono e sono provati a livello di database;
  aggiungere i comandi sarebbe una funzionalità nuova.
- **Gate di verifica venditore non portato**: `has_role('seller_enabled')`
  non è applicato (decisione di 6a) e `/verifica-venditore` non è migrata,
  quindi il blocco non avrebbe né una verifica da controllare né una
  destinazione dove mandare l'utente.
- **Pannello "Assistente AI"** del passo Identificazione non portato:
  chiama `/api/ai/listing-suggestion` sul backend FastAPI, dominio AI è
  Fase 10. Il pannello "Migliora lo sfondo con IA" è invece portato perché
  in `frontend/` è già interamente simulato e non chiama nessun servizio.
- **Accesso deciso dalla sessione Supabase reale** e non dal demo-switcher
  `ruolo`: il venditore di un annuncio è sempre `auth.uid()`.
- **Bucket `annunci` pubblico in lettura.** Le fotografie di un annuncio
  attivo sono visibili a chiunque, anche anonimo: è il prodotto. Conseguenza
  accettata: anche le foto di una bozza sono leggibili da chi ne indovina
  l'URL, che contiene due UUID.
- **Nessuna scadenza automatica.** `listing_scadi` materializza una scadenza
  già avvenuta e rifiuta se `expires_at` è nel futuro; la spazzata periodica
  su tutti i venditori richiede uno scheduler ed è lavoro di esercizio.

## Fase 6c-1 — Schema Cantina, RLS e posizionamento

**Branch**: `migration/phase-6c-cellar-schema`

Tabelle `cellar_environments`, `cellar_modules`, `cellar_slots`. Metadati di
bevuta e abbinamenti spostati da `data/cellar.ts` a colonne su `wines`
(catalogo condiviso: restano scrivibili solo dallo staff, con la policy della
6a). Su `bottle_units` arriva ciò che è personale della singola unità:
apertura pianificata, note, visibilità del prezzo, override della finestra.
Funzioni `cellar_posiziona` e `cellar_togli_posizione`. Nessuna interfaccia.

Scelte di schema che divergono dalla forma dei dati mock:

- **`cellar_slots` contiene solo posizioni occupate.** Nel mock `makeSlots()`
  materializza righe × colonne voci con `status: "libero"`, ma quelle righe
  sono derivabili dalla geometria del modulo: materializzarle significherebbe
  tenerle allineate a ogni modifica di `righe`/`colonne` e avere due fonti di
  verità sulla stessa geometria. `bottle_unit_id` è `NOT NULL` apposta, e il
  campo `status` non esiste per lo stesso motivo.
- **`cellar_slots` non è scrivibile dal client**: riga e colonna vanno
  verificate contro la geometria del modulo e la bottiglia contro il suo
  proprietario, cose che un `CHECK` non può fare. La scrittura passa dalle due
  funzioni.
- **`listings.quantita` sparisce come colonna** e diventa un conteggio dentro
  `public_listings`, attraverso la vista intermedia `listing_bottle_units`.
  Finché il legame annuncio → unità è uno a uno il conteggio vale 1, identico
  a prima; quando diventerà uno-a-molti cambierà solo quella vista.
- **Ambienti e moduli restano privati** anche quando contengono una bottiglia
  dichiarata `cantina_pubblica`: si rende pubblica la bottiglia, non i mobili.
  Se la 6c-2 mostrerà la cantina altrui in 3D servirà una policy in più.
- **Gli abbinamenti perdono la condivisione per stile.** Nel mock quattro
  elenchi sono riusati fra gli otto vini; come colonna su `wines` ogni vino
  porta la propria copia.

## Fase 6c-2 — Interfaccia Cantina

**Branch**: `migration/phase-6c-cellar-ui`

Porting di `/cantina` da `frontend/` (1065 righe): ambienti, moduli, viste
(mie / pronte / in vendita / 3D), finestra di bevuta con override,
preferenze, `Cellar3D`. Wizard di collegamento `bottle_unit` → slot.
`Cellar3D.tsx` e `DrinkWindow.tsx` sono già in `frontend-next/` dalla Fase 2:
vanno diffati contro la versione `frontend/`, non riscritti.

Da qui "metti in vendita questa bottiglia" parte da una `bottle_unit`
esistente, ed è il momento in cui il vincolo "una bottiglia, un solo annuncio
attivo" diventa raggiungibile dall'interfaccia: va verificato che arrivi il
messaggio leggibile di `listing_pubblica` e non il 23505.

### Scelte e divergenze emerse eseguendola

- **Una `bottle_unit` è una bottiglia; `quantita` è derivata dallo stato**
  (1 se chiusa, 0 se aperta o consumata). Nel mock una `CellarBottle` porta un
  campo `quantita` (2, 4, 3…) e un solo `storageLocationId`: una pila di
  quattro sta in un foro solo. Nessun percorso di codice ha mai creato una
  pila — `listing_crea` conia un'unità per volta — quindi il raggruppamento
  non è stato introdotto. La mappatura preserva tutti i comportamenti che
  dipendevano da quel numero: totale in cantina, valore stimato, decremento
  all'apertura, penalità nella ricerca per abbinamento.
- **Il prezzo di una bottiglia viene dal suo annuncio.** In `wines` un prezzo
  non esiste: appartiene a `listings`. Ogni bottiglia in cantina ne ha uno,
  perché `listing_crea` è l'unico scrittore di `bottle_units` e crea i due
  insieme.
- **`DEFAULT_META` resta come ripiego lato client.** `getWineMeta` non
  restituisce "niente" per un vino sconosciuto ma un profilo generico completo.
  Senza ripiego la scheda del vino creato in 6b avrebbe perso quattro
  abbinamenti e tre statistiche su quattro.
- **La cantina si carica dal browser**, non dal server: è privata, non c'è
  nulla da prerenderizzare, e le stesse bottiglie servono anche a
  `MyBottleActions` e alla ricerca per abbinamento. Stesso schema di
  `real-auth-domain.ts`.
- **Preferenze, sfondo e riduzione animazioni restano in memoria**: non
  persistono nemmeno in `frontend/`, e dar loro una tabella sarebbe un
  cambiamento di comportamento.
- **Elenco "Da collocare" nella vista 3D.** Unica deviazione: non è un comando
  nuovo ma lo stesso "Sposta" reso raggiungibile. Nei dati mock ogni bottiglia
  nasce collocata; su dati veri nessuna lo è, e senza quell'elenco
  `cellar_posiziona` resterebbe una funzione senza porta.
- **`p_bottle_unit_id` come parametro di `listing_crea`**, non una funzione
  gemella: le due vie condividono validazione, slug, inserimento della bozza e
  gestione della corsa sullo slug. Serve `DROP` e non `CREATE OR REPLACE`
  perché aggiungere un parametro crea una seconda firma, ambigua per PostgREST.
- **Ritorno in cantina dopo il wizard**, come in `frontend/`. La 6b mandava
  all'annuncio o restava nel wizard solo perché `/cantina` non esisteva:
  divergenza dichiarata allora, chiusa qui.
- **Il pannello "Nella tua cantina" sulla scheda annuncio** ora compare solo a
  chi possiede la bottiglia, e conta le proprie unità ancora chiuse. Prima,
  con la cantina mock, compariva a chiunque — anche a chi non aveva mai fatto
  accesso.

## Fase 6d-1 — Invarianti di sicurezza fra bottiglie e annunci

**Branch**: `hardening/phase-6d-1-security-invariants`

Non una migrazione di dati: le fonti restano quelle di 6a/6b/6c. Cambiano policy,
privilegi e percorsi di scrittura. Quattro migrazioni additive, nessuna modifica
retroattiva a un file già applicato:

- `20260729230000_security_invariants.sql`;
- `20260729234500_security_invariants_followup.sql`;
- `20260729235500_security_helper_invoker.sql`;
- `20260730140948_security_invariants_remote_drift_repair.sql`.

La verifica sul database reale, i problemi corretti e le eccezioni deliberate
degli advisor Supabase sono in
[`PHASE_6D1_SUPABASE_REVIEW.md`](PHASE_6D1_SUPABASE_REVIEW.md).

**Stato al 30 luglio 2026: integrata in `main`, prova comportamentale
post-repair ancora aperta.** La PR #14 è stata unita con merge commit
`61e3fde`; la CI finale `30554736346` è verde sull'HEAD `6bbe4dd`. La quarta
migrazione ha ripristinato lo stato finale senza modificare dati applicativi;
la query read-only post-deploy è 13/13 e `auth_rls_initplan` è scomparso.
Le griglie remote autorizzate separatamente restituiscono 33/33 e 11/11, con
residui fixture zero. La migrazione additiva
`20260730162046_fix_6d1_bottle_message_encoding.sql` corregge i due messaggi
UTF-8 emersi dal primo retest follow-up. Fino all'integrazione del rapporto
post-merge non si avvia la Fase 6d-2a né la Fase 7.

Sette confini chiusi: privacy di `bottle_units` e di `listings` (viste a elenco
chiuso di colonne al posto dei `GRANT` di tabella), `user_roles` non più
enumerabile e `has_role` non più anonima, controllo dell'età autoritativo in
database su `listing_crea` e `listing_pubblica`, invarianti bottiglia–annuncio
con lock di riga, annunci scaduti esclusi dalla proiezione pubblica, e la regola
«un annuncio, una bottiglia, un solo annuncio non terminale».

Le tre regole permanenti che ne derivano sono in `CLAUDE.md`, sezione
*Postgres exposure rules*.

### Scelte e divergenze emerse eseguendola

- **`ceduta_at` la valorizza un trigger, non la funzione di transizione.** Il
  buco era che l'indice della 6a copriva `('attivo','riservato')`: portando un
  annuncio a `'venduto'` la bottiglia tornava libera e si poteva ripubblicare una
  bottiglia già venduta. Serviva un marcatore di uscita dal possesso, e serviva
  che lo scrivesse chi conclude la vendita — ma quella funzione è Fase 7 e non
  esiste. Il trigger `listings_marca_bottiglia_ceduta` intercetta l'ingresso in
  `'venduto'` da qualunque origine, oggi `service_role` e domani la RPC di Fase 7.
- **L'invariante fra tabelle usa due trigger e non un indice.** Il perimetro di fase
  chiedeva che `ceduta_at` fosse «considerato dall'indice»: un indice unico vive
  su una tabella sola e non può leggere l'altra. Al suo posto
  `listings_bottiglia_idonea`, che rifiuta ogni annuncio non terminale su una
  bottiglia aperta, consumata, cancellata o ceduta — e vale anche per
  `service_role`, cosa che un controllo dentro le RPC non otterrebbe. Il
  follow-up aggiunge `bottle_units_preserva_annuncio_non_terminale`, così lo
  stesso vincolo vale anche quando cambia direttamente la bottiglia.
- **Le colonne di tracciamento moderazione escono anche per il proprietario.**
  `stato_motivo`, `stato_aggiornato_da` e `stato_aggiornato_at` non sono nel
  `GRANT` di colonna di `listings` per nessun ruolo client. Il perimetro chiedeva
  insieme che il venditore leggesse «integralmente» i propri annunci e che quelle
  colonne non fossero leggibili dai non proprietari: un privilegio di colonna non
  distingue le righe, e le due cose non stanno insieme. Oggi non costa nulla di
  visibile — la moderazione è Fase 9 e nessuna interfaccia le mostra.
- **`bottiglia_cancella` esiste senza avere un chiamante.** Nessun comando toglie
  una bottiglia dalla cantina, né in `frontend/` né in `frontend-next/`, e questa
  fase non lo aggiunge. La funzione nasce perché `deleted_at` esce dai `GRANT` di
  colonna insieme a `stato`: senza, quella colonna resterebbe senza porta.
- **`ceduta_at` toglie la bottiglia dalla cantina del venditore.** Il follow-up
  esclude le unità cedute dalla policy del proprietario e libera l'eventuale
  `cellar_slot`. Il trasferimento al compratore resta una responsabilità della
  Fase 7: questa fase rappresenta soltanto l'uscita dal possesso del venditore.

## Fase 6d-2a — Provenienza catalogo e percorsi Cantina

**Branch**: `migration/phase-6d-2a-catalog-cellar-paths`

**Stato**: integrata in `main` tramite PR #17 al merge squash `3037bf4`; CI #44
verde. La migrazione `20260731120340 catalog_cellar_paths` e la griglia 18/18
sono registrate, con residui database e Storage zero.

Precondizione obbligatoria: rapporto post-merge integrato con griglie 33/33 e
11/11, verifier repair 13/13, residui fixture zero e approvazione esplicita
della fase.

Perimetro:

- distinguere il catalogo curato dallo staff dai vini inseriti dagli utenti;
- separare aggiunta privata, aggiunta pubblica e vendita da `bottle_unit`
  esistente;
- rendere atomica la creazione dell'ambiente e del modulo iniziale;
- collegare alla home solo riepiloghi reali della Cantina;
- mantenere invarianti, RLS, privilegi e viste chiuse della 6d-1.

Decisioni implementate:

- `wines.provenienza` e `creato_da` separano autorità editoriale e inserimento
  utente senza duplicare la tripletta produttore/nome/annata;
- `cellar_bottiglia_aggiungi` crea una unità privata o pubblica senza annuncio;
- `listing_crea_da_bottiglia` vende soltanto un'unità già in Cantina e la
  vecchia via di creazione completa non è più eseguibile dai client;
- `cellar_ambiente_crea` rende atomici ambiente e modulo iniziale;
- le foto personali usano il bucket privato `cantina`;
- `/home` usa soltanto riepiloghi reali del `CellarService`.

Fuori perimetro: ordini, proposte, pagamenti, payout, KYC, trasferimento della
proprietà e qualsiasi lavoro della Fase 7. Ogni migrazione è additiva; SQL e
fixture sul progetto remoto richiedono autorizzazioni esplicite separate.

## Fase 7 — OrderService + ProposalService + PaymentService

**Branch**: `migration/phase-7-order-payment-service`

Ordini, proposte e pagamenti Stripe reali via Edge Function
(`payments-checkout`, webhook firmato su Route Handler). Feature flag per
attivazione controllata. Stessa disciplina di sicurezza pagamenti già
validata in Sprint 0 (stato solo da `payment_status=paid`, idempotenza,
protezione da eventi tardivi).

**Stato al 31 luglio 2026**: avvio autorizzato sul branch
`migration/phase-7-order-payment-service`. Il primo checkpoint è locale: schema,
limiter server-side, servizi, Edge Function, Route Handler e test. Nessuna
migrazione o funzione remota è autorizzata.

## Fase 8 — MessagingService + NotificationService

**Branch**: `migration/phase-8-messaging-notifications`

Messaggistica (`conversations`, `messages`) e notifiche (`notifications`)
via Supabase Realtime, con rate limit lato server.

## Fase 9 — ModerationService

**Branch**: `migration/phase-9-moderation-service`

Coda segnalazioni, audit log persistente (`audit_log`, scrittura solo via
funzione SECURITY DEFINER), azioni di moderazione reali al posto del
mock attuale.

## Fase 10 — AiService reale

**Branch**: `migration/phase-10-ai-service`

Provider AI reale via Edge Function proxy (`ai-identify-bottle` e
equivalenti), rate-limit lato server, chiave e budget configurati fuori
dal repository.

## Fase 11 — Cutover finale

**Branch**: `migration/phase-11-cutover`

Solo dopo parità funzionale verificata su tutti i domini precedenti e
approvazione esplicita separata: dismissione di `frontend/` (TanStack
Start) e `backend/` (FastAPI/MongoDB). Non è una conseguenza automatica
del completamento delle fasi 2–10.

## Debito dichiarato dalla Fase 6d-1

Lavoro che la 6d-1 ha reso necessario o ha lasciato scoperto, con un posto già
assegnato. Diverso dal "debito tecnico noto" più sotto, che invece non appartiene
a nessuna fase.

### Trasferimento di proprietà della bottiglia al compratore — Fase 7

`bottle_units.ceduta_at` dice che un'unità è uscita dal possesso di chi la
possedeva. Non dice a chi è andata: `owner_id` non si muove e il compratore non è
registrato da nessuna parte. Il trasferimento vero non si è implementato perché
**non esiste in `frontend/`** e sarebbe funzionalità nuova dentro una migrazione;
il campo però è già pronto ad accoglierlo.

**La Fase 7 deve sapere due cose.** La prima: il trigger
`listings_marca_bottiglia_ceduta` esiste già e valorizza `ceduta_at` all'ingresso
in `'venduto'` — la RPC che chiuderà una vendita **non deve** scriverla per conto
suo, o le due si sovrascriveranno a vicenda. La seconda: quando il passaggio di
proprietà sarà reale dovrà creare o trasferire l'unità del compratore senza
reintrodurre quella ceduta nella cantina del venditore. Le policy attuali la
escludono già e il trigger libera il suo slot.

### Il catalogo condiviso è scrivibile dagli utenti — domanda bloccante della 6d-2a

`wines` è dichiarato catalogo condiviso e la policy `wines_write_staff` (6a) lo
riserva a chi ha ruolo `admin` o `moderator`. **`listing_crea` lo scavalca**: è
`SECURITY DEFINER`, quindi gira con i privilegi del proprietario, e inserisce una
riga in `wines` ogni volta che un venditore descrive un vino non ancora in
catalogo. Chiunque sappia usare il wizard `/vendi` scrive nel catalogo condiviso.

Non è un difetto introdotto dalla 6d-1 ed è **fuori dal suo perimetro**: nasce
con la 6b, dove era una conseguenza voluta e dichiarata — il wizard parte da
testo digitato, non da un vino già catalogato, e senza quel varco non si potrebbe
creare nessun annuncio. Ciò che mancava era la conseguenza scritta da qualche
parte.

La conseguenza è che oggi non esiste differenza fra un vino curato dallo staff e
uno digitato da un utente: stessa tabella, stesso stato, stessa autorità
apparente. Servirà **distinguere il vino di catalogo dal vino inserito da
utente** — una colonna di provenienza, o due tabelle — e decidere che cosa
comporta la differenza per la ricerca, per la moderazione e per i metadati di
bevuta, che oggi solo lo staff può compilare.

È la domanda bloccante della 6d-2a e ha già risposta: la distinzione va
introdotta, non aggirata.

### Scheduler di scadenza degli annunci — lavoro schedulato

Dalla 6d-1 un annuncio oltre `expires_at` è escluso da `public_listings`, quindi
non è più né visibile né acquistabile. Lo **stato materializzato resta però
`'attivo'`** finché qualcuno non chiama `listing_scadi`, e nessuno la chiama: la
spazzata periodica su tutti i venditori richiede `pg_cron` o una Edge Function.
Fino ad allora il numero di righe in quella condizione cresce, ed è la prima
colonna della sezione [8] di `supabase/tests/6d-1_verifica.sql`.

La futura RPC di prenotazione (Fase 7) **deve ricontrollare la scadenza** dentro
la propria transazione: la difesa attuale è in lettura, e non impedisce a nessuno
di agire su un id già noto.

### CI che esegua le prove SQL — 6d-2 o successiva

`supabase/tests/*.sql` si eseguono a mano nel SQL Editor perché nell'ambiente in
cui la 6d-1 è stata scritta mancano CLI Supabase e Docker, quindi non c'è modo di
far ripartire un Postgres locale e ricostruire le migrazioni da zero. Serve un
job che avvii Supabase in locale, applichi le migrazioni in ordine ed esegua le
prove, possibilmente riscritte in pgTAP come previsto da ADR 002. Registrato,
non improvvisato.

### Infrastruttura di prova di `frontend-next/` — 6d-2

`frontend-next/` non ha uno script `test`: la CI vi esegue solo lint, typecheck e
build, mentre `frontend/` ha 73 test. Ogni fase da qui in avanti verifica il
proprio lavoro sul frontend a mano. Non è un difetto introdotto dalla 6d-1, ma è
la fase che lo rende evidente, perché sposta comportamento dal client al database
senza avere dove scrivere una prova del client.

### `public_bottle_units` non ha consumatori — da rimuovere se resta inutile

La vista conserva, in forma sicura, la capacità che le due policy pubbliche su
`bottle_units` davano prima della 6d-1: leggere le unità in un annuncio attivo e
quelle dichiarate `cantina_pubblica`. **Nessuna interfaccia la legge**, né oggi
né in `frontend/`: `cantina_pubblica` compare solo come etichetta derivata dai
dati del proprietario.

Toglierla nella 6d-1 avrebbe significato rimuovere in silenzio una capacità
mentre si chiudeva un buco — due decisioni diverse dentro lo stesso commit.
Tenerla è però superficie esposta senza chiamanti, che è esattamente il genere di
cosa che fra un anno nessuno osa più toccare.

**Da decidere entro la Fase 9**: se la 8 (messaggistica) o la 9 (moderazione) non
la usano, va rimossa insieme al concetto di cantina pubblica per singola
bottiglia, o va costruita l'interfaccia che lo rende visibile. Non un terzo anno
così.

### La nota di degustazione sovrascrive la nota personale

Il dialogo «Registra apertura» ha un campo etichettato *Nota di degustazione
(facoltativa)* che scrive dentro `note_personali` — due cose diverse nello stesso
posto. In `frontend/` (`cellar-domain.ts`, `personalNotes: nota ?? bottle.personalNotes`)
la nota di degustazione sostituisce la nota personale, e siccome il dialogo passa
sempre una stringa — vuota se non si scrive niente — **aprire una bottiglia senza
digitare nulla cancella la nota personale che c'era**.

`frontend-next` diverge già dalla 6c-2, a favore dei dati: una nota vuota non
tocca niente. La 6d-1 ha portato quella protezione dentro `bottiglia_apri`
insieme al resto della funzione. Resta però il caso in cui si scrive davvero
qualcosa: «Regalo di mio padre» diventa «Tannini setosi», e la prima frase non
torna più.

Stessa natura di `formatEUR`: difetto preesistente, visibile in entrambi gli
stack, la cui correzione — due campi separati, o una nota additiva — è un
cambiamento di comportamento che va deciso e verificato per conto suo. **Fuori
scope dalla 6d-1 e da qualunque fase di migrazione.**

### Rate limiting senza equivalente su Supabase

`backend/` limita checkout, stato pagamenti e AI con chiavi che combinano
identità autenticata e indirizzo client normalizzato (vedi `docs/SECURITY.md`).
Su Supabase **non esiste niente di equivalente**: PostgREST espone le RPC senza
alcun limite di frequenza, e le funzioni della 6d-1 — `listing_crea`,
`bottiglia_apri` — sono chiamabili in raffica da qualunque sessione autenticata.
Nessun invariante di dati ne viene violato, ma il costo e il rumore sì.

Va risolto prima che la Fase 7 esponga i pagamenti, ed è lavoro di infrastruttura
(Edge Function con storage condiviso, o limiti al bordo), non di questa traccia.

## Debito dichiarato dalla diagnosi della storia migrazioni — 2 agosto 2026

Trovato creando il branch Supabase `phase-7-migration-verify` e finito in
`MIGRATIONS_FAILED`. Precede la Fase 7 di giorni e non le appartiene: riguarda
la fedeltà di qualunque ambiente ricostruito dalle migrazioni. Diagnosi completa
in [`docs/PHASE_7_VERIFICATION.md`](PHASE_7_VERIFICATION.md).

### L'event trigger `ensure_rls` non è creato da nessun file — da decidere prima di fidarsi di un branch

`public.rls_auto_enable()` ritorna `event_trigger`, proprietario `postgres`,
`security definer`, `search_path=pg_catalog`. Il corpo scorre
`pg_event_trigger_ddl_commands()` e abilita RLS sulle tabelle nuove in `public`.
È agganciata all'event trigger `ensure_rls` su `ddl_command_end`, proprietario
`postgres` — gli altri sei event trigger del progetto sono di `supabase_admin`,
cioè di Supabase.

**Nessun file di `supabase/migrations/` la crea.** L'unica menzione in tutto il
repository è `20260729234500_security_invariants_followup.sql:86`, che le revoca
`execute`. È deriva vera, dello stesso genere riparato in parte dalla
`20260730140948`, che però non la copriva.

Va tenuta distinta dalla deriva del ledger — le sette versioni con `statements`
vuoto, riparate il 2 agosto 2026. Sono due difetti indipendenti: **riparato il
ledger, `ensure_rls` resta comunque assente** da ogni ambiente ricostruito,
perché non c'è alcun file da registrare.

### Aggiornamento 3 agosto 2026 — blocca il replay, non solo la fedeltà

Misurato dopo la riparazione del ledger, sul progetto reale e sul branch fallito
`ccnufawxtaykgjftvauc`:

| Misura | Progetto reale | Branch fresco |
| --- | --- | --- |
| Event trigger totali | 7 | 6 |
| `ensure_rls` | presente | assente |
| `public.rls_auto_enable()` | presente | assente |

I sei event trigger comuni sono di Supabase: **il settimo non arriva dalla
piattaforma**, quindi un branch nuovo nasce senza. Delle 21 funzioni in `public`
del progetto reale, 20 sono create da almeno un file tracciato e
`rls_auto_enable` da nessuno.

Conseguenza: `revoke execute on function public.rls_auto_enable()` alla riga 86
della `20260729234500` — presente anche nel testo registrato a ledger, verificato
— gira su un branch dove la funzione non esiste. In Postgres `revoke ... on
function` non ammette `if exists`: è un errore duro. **Il replay di un branch
pulito si ferma alla decima versione su quattordici** con
`function public.rls_auto_enable() does not exist`.

Il branch `phase-7-migration-verify` non lo aveva rivelato perché moriva prima,
alla riga 35 su `bottiglia_apri`, per effetto delle sette versioni vuote.

**Nessuna delle due strade sotto ripara il replay da sola.** La `revoke` sta
dentro una versione già registrata e gira prima di qualunque cosa una migrazione
nuova possa creare, perché il replay segue l'ordine delle versioni: una
migrazione con timestamp successivo arriva troppo tardi. Ripararlo richiede o una
riga di ledger antedatata rispetto alla `20260729234500`, o una modifica
chirurgica del testo registrato di quella versione. Entrambe sono scritture sul
bookkeeping, entrambe da autorizzare a parte.

**Non blocca la Fase 7 come schema.** La sua migrazione abilita RLS
esplicitamente su tutte e sei le tabelle che crea (righe 20 e 335–339), quindi
non dipende dall'auto-enable implicito. Blocca il metodo di verifica: finché la
decisione non è presa, **un branch Supabase non è né ricostruibile né un proxy
fedele della produzione** per qualunque migrazione che crei una tabella in
`public` senza `enable row level security` esplicito. Lì la tabella nascerebbe
con RLS attiva e sul branch no, e la differenza non comparirebbe in nessun
errore.

**Da decidere**, e registrare la scelta, prima di usare un branch come prova di
una migrazione futura. Due strade, nessuna delle due presa qui:

1. **Ricreare il trigger in una migrazione propria**, che lo renda parte della
   storia e quindi presente in ogni ambiente ricostruito. Mantiene la rete di
   sicurezza e chiude la deriva.
2. **Dichiarare deprecato l'auto-enable implicito** in favore di RLS sempre
   esplicita in ogni migrazione, e rimuovere trigger e funzione dal progetto
   reale con una migrazione che lo registri. Rende la storia autosufficiente al
   prezzo di togliere la rete: un `create table` che dimentichi
   `enable row level security` non verrebbe più corretto da nessuno.

Nessuna delle due va eseguita senza approvazione esplicita: entrambe toccano il
progetto reale, e la seconda cambia una protezione attiva. Entrambe vanno
accompagnate dalla riparazione del replay descritta sopra, altrimenti il branch
continua a fermarsi alla decima versione.

### Definizioni esatte degli oggetti derivati — estratte il 3 agosto 2026

Sola lettura sul progetto reale, prima di scrivere qualunque proposta.

`public.rls_auto_enable()` — `returns event_trigger`, `language plpgsql`,
`security definer`, `set search_path to 'pg_catalog'`, proprietario `postgres`.
Il corpo scorre `pg_event_trigger_ddl_commands()` filtrando i tag
`CREATE TABLE, CREATE TABLE AS, SELECT INTO` e gli `object_type`
`table, partitioned table`; per ogni oggetto in `public` esegue
`alter table if exists … enable row level security` dentro un blocco
`exception when others` che degrada a `raise log`, quindi non fa mai fallire il
`create table` che lo ha innescato.

Event trigger `ensure_rls` — evento `ddl_command_end`, tag
`CREATE TABLE, CREATE TABLE AS, SELECT INTO`, funzione `rls_auto_enable()`,
`evtenabled = 'O'` (abilitato), proprietario `postgres`.

**Non sono bootstrap di piattaforma.** La prova non è più solo il conteggio
7 contro 6: i sei event trigger presenti anche su un progetto appena creato
(`issue_graphql_placeholder`, `issue_pg_cron_access`, `issue_pg_graphql_access`,
`issue_pg_net_access`, `pgrst_ddl_watch`, `pgrst_drop_watch`) hanno tutti
proprietario `supabase_admin`, cioè il ruolo di Supabase. `ensure_rls` ha
proprietario `postgres`, il ruolo con cui si applicano le migrazioni e con cui
opera il SQL Editor. È stato creato da un'azione nostra fuori dalla storia, non
dalla piattaforma. Nessuna origine tracciabile nel repository: l'unica menzione
in tutti i file è la `revoke` alla riga 86 della `20260729234500`.

### Controllo preventivo sulle versioni 11-14 — 3 agosto 2026

Fatto prima di proporre la riparazione, per non scoprire un blocco alla volta un
branch alla volta. Metodo: il replay di un ambiente ricostruito può divergere
dall'applicazione originale solo sugli oggetti che esistono sul progetto reale
ma non sono creati da alcun file tracciato. Quindi si diffa l'inventario del
progetto reale contro quello di un progetto appena creato, e si verifica se le
versioni successive alla decima nominano qualcuno dei residui.

Oggetti presenti sul progetto reale e assenti da un progetto appena creato:

| Oggetto | Creato da file tracciato | Blocca il replay |
| --- | --- | --- |
| `public.rls_auto_enable()` | **no** | **sì, versione 10** |
| event trigger `ensure_rls` | **no** | no (nessuno lo nomina) |
| estensione `pg_trgm` | sì — `20260728193937:34` | no |
| schema `private` | sì — `20260731120340:201`, `20260731135455:4` | no |
| ruolo `cli_login_postgres` | no (ruolo di login della CLI) | no — mai nominato da alcuna migrazione |
| le altre 20 funzioni di `public` | sì | no |

`pg_trgm` e lo schema `private` risultavano assenti dal branch fallito, ma **non
erano deriva**: erano una conseguenza del ledger vuoto, perché le versioni che
li creano erano fra le sette che non registravano nulla. Riparato il ledger,
tornano.

Poi il controllo diretto: ognuno dei 62 `revoke execute on function` di tutte le
migrazioni è stato tracciato fino a chi crea il suo bersaglio. **Tutti hanno una
`create function` che li precede, tranne uno** — `public.rls_auto_enable()`.
Per le sole versioni 11-14 il dettaglio è:

- **11 `20260729235500`** — crea `has_role`, `cellar_ambiente_e_mio`,
  `cellar_modulo_e_mio` e revoca solo su quelle. Autosufficiente.
- **12 `20260730140948`** — crea `bottiglia_apri` (riga 30),
  `bottiglia_cancella` (107), `listings_bottiglia_idonea` (177),
  `listings_marca_bottiglia_ceduta` (244) prima di ogni `comment`/`revoke`/
  `grant` su di esse. `alter default privileges for role postgres`: il ruolo
  esiste ovunque. `drop trigger`/`drop policy` sono tutti `if exists`.
- **13 `20260730162046`** — crea `bottiglia_apri` e `bottiglia_cancella` e
  revoca solo su quelle. Le tabelle che il corpo nomina arrivano dalle versioni
  3 e 6, che il ledger riparato ora registra.
- **14 `20260731120340`** — crea `catalogo_risolvi_vino_utente` (204),
  `cellar_bottiglia_aggiungi` (307), `listing_crea_da_bottiglia` (401),
  `cellar_ambiente_crea` (447), la vista `public_listings` (541) prima di
  nominarle. `revoke execute on function public.listing_crea` alla 439 punta
  alla versione 5. `drop policy … on storage.objects`: schema di piattaforma,
  presente ovunque.

**Esito: dopo la versione 10 il replay non incontra altri blocchi.** Risolto
`rls_auto_enable`, un branch pulito dovrebbe arrivare a 14 su 14.

Resta **una sola incognita, e non riguarda le versioni a ledger**: la migrazione
di Fase 7, non ancora applicata da nessuna parte, esegue alla riga 140
`alter role authenticator set pgrst.db_pre_request = 'private.vinea_check_request'`.
Il ruolo `authenticator` esiste su un progetto appena creato — verificato — ma
che `postgres` possa fare `alter role … set` su di esso non è mai stato provato.
È una questione di privilegi, non di oggetti mancanti, e si scoprirà alla prima
applicazione autorizzata.

### Stato della riparazione — proposta scritta, non applicata

`supabase/repair/proposal_ledger_bootstrap_replay.sql` contiene il testo SQL
completo che la riga di ledger antedatata dovrebbe registrare: la
`create or replace function public.rls_auto_enable()` verbatim dal progetto
reale, più la `create event trigger ensure_rls` avvolta in un blocco `do` che
controlla `pg_event_trigger`, perché `create event trigger` non ammette
`if not exists`. Versione proposta `20260729220000`, libera fra la
`20260729210000` e la `20260729230000`. Sul progetto reale il DDL è un no-op.

**Non applicata.** Nessuna riga scritta sul ledger, nessun SQL eseguito, nessun
branch creato. L'`insert` è lasciato in commento dentro il file perché non possa
partire per errore. Attende approvazione esplicita in chat organizzativa.

Due cose che l'approvazione deve decidere, non date per scontate nel file:

1. **La collocazione.** A `20260729220000` il trigger esiste già quando girano
   le versioni successive, quindi ogni `create table` in `public` dalla
   `20260729230000` in poi riceve l'auto-enable. Non è dimostrabile che
   riproduca la storia vera — `pg_proc` non conserva la data di creazione, e
   quando `ensure_rls` sia nato sul progetto reale non è ricostruibile.
   L'effetto atteso è inerte perché ogni migrazione abilita RLS esplicitamente.
   L'alternativa che restringe al minimo la differenza è `20260729234000`,
   subito prima della versione che fa la `revoke`.
2. **Il file tracciato.** Registrare la sola riga di ledger ripeterebbe il
   difetto originario — una versione senza file. L'approvazione va accompagnata
   da `supabase/migrations/20260729220000_rls_auto_enable_bootstrap.sql` con lo
   stesso contenuto, perché repository e ledger tornino confrontabili per hash.

## Debito tecnico noto

Difetti reali, individuati durante la migrazione, che **non** appartengono a
nessuna fase della traccia: toccarli significherebbe cambiare il
comportamento di `frontend/` e `frontend-next/` insieme, cioè fare un
cambiamento di prodotto dentro una migrazione di dati.

### `formatEUR` tronca i centesimi (emerso in Fase 6b)

`src/lib/format.ts` — identico nei due frontend — formatta i prezzi con
`formatInteger`, quindi stampa euro interi: un annuncio da `145,90 €` viene
mostrato come `146 €`. Il dato è corretto e integro nel database
(`listings.prezzo_cents = 14590`); sbagliata è solo la resa.

Il difetto è preesistente, ma fino alla 6a era invisibile: tutti i prezzi
mock e le righe di prova erano cifre tonde. Diventa visibile dalla 6b, da
quando il wizard `/vendi` permette di digitare i centesimi.

Non si corregge in una fase di migrazione: cambiare `formatEUR` cambierebbe
la resa di ogni prezzo in entrambi i frontend — schede annuncio, carrello,
ordini, proposte, checkout — cioè un cambiamento di design trasversale, che
va deciso e verificato per conto suo. Esplicitamente **fuori scope dalla
Fase 6c** e da qualunque fase successiva della traccia.

---

Ogni ticket sopra è indicativo nella granularità di branch/nome; la fase
corrispondente potrà scinderlo ulteriormente in fasi più piccole se
risultasse troppo grande da verificare in un'unica PR.
