# Fase 9 - ModerationService e audit persistente

Stato: **specifica organizzativa, non approvata.** Nessuna riga di SQL, nessuna
migrazione, nessun codice applicativo. Il branch previsto dal backlog è
`migration/phase-9-moderation-service`
(`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService»).

Ogni affermazione di questo documento porta la fonte `file:riga` da cui viene.
Ciò che non ha una fonte è marcato **decisione aperta** e va risposto in chat
organizzativa prima di qualunque SQL.

**I numeri di riga sono presi su `4f96864`**, cioè `origin/main` al merge della
Fase 8. I file di `CONTESTO_IA/` sono citati per **sezione** e non per riga,
perché sono aggiornati a ogni fase e una riga vi resta valida per poco.

## 1. Perimetro

Il perimetro della Fase 9 non è mai stato scritto in un solo posto: è la somma
dei rinvii lasciati dalle fasi 6a, 6b, 6d-1, 7b, 7c e 8. Questo è l'inventario
completo di quei rinvii.

### 1.1 Enunciato di fase

| Requisito | Fonte |
| --- | --- |
| Branch `migration/phase-9-moderation-service` | `docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService» |
| Coda segnalazioni, `audit_log` persistente con **scrittura solo via funzione SECURITY DEFINER**, azioni di moderazione reali al posto del mock attuale | `docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService» |
| `ModerationService`, audit persistente e **proiezioni dedicate** per i motivi di moderazione, senza riaprire le colonne private delle tabelle | `CONTESTO_IA/02_STORIA_FASI.md`, sezione «Fase 9 — moderazione» |
| Dominio «Moderazione e audit persistente» non migrato | `CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Domini già migrati» |
| L'interfaccia `ModerationService` esiste già in TypeScript e non ha implementazione reale | `frontend-next/src/services/types.ts:970-981` |

### 1.2 Debiti che la Fase 9 eredita da annunci e catalogo (6a/6b/6d-1)

| Requisito | Fonte |
| --- | --- |
| Coda di moderazione e `audit_log` dichiarati fuori perimetro dalla 6a e assegnati alla Fase 9 | `supabase/migrations/20260728193937_listings_catalog.sql:13` |
| I valori `in_revisione`, `modifiche_richieste` e `rifiutato` **esistono già** in `public.listing_stato` e le loro transizioni sono assegnate alla Fase 9 | `supabase/migrations/20260728193937_listings_catalog.sql:229-230`; enum a `:212-216` |
| Le tre colonne di traccia su `listings` (`stato_motivo`, `stato_aggiornato_da`, `stato_aggiornato_at`) **non sostituiscono** l'`audit_log` persistente della Fase 9 | `supabase/migrations/20260728193937_listings_catalog.sql:272-277` |
| Le transizioni di moderazione restano fuori dalla 6b e sono Fase 9 | `supabase/migrations/20260729112500_listings_write.sql:10-11` |
| La sospensione decisa da un **moderatore** è cosa diversa da `listing_sospendi` e passerà da **una funzione separata che verifica `has_role()`** | `supabase/migrations/20260729112500_listings_write.sql:333-334` e `:378-380` |
| `listing_sospendi` oggi accetta solo il proprietario dell'annuncio e solo dallo stato `attivo` | `supabase/migrations/20260729112500_listings_write.sql:356-366` |
| Le tre colonne di traccia non sono nel `GRANT` di colonna di `listings` per **nessun** ruolo client, proprietario compreso | `supabase/migrations/20260729230000_security_invariants.sql:1015-1026`; `docs/SECURITY.md:62-64`; `docs/MIGRATION_PHASE_1_BACKLOG.md:281-287` |
| Quando la Fase 9 mostrerà al venditore il motivo di un rifiuto lo farà con **una proiezione dedicata alle righe proprie, non riaprendo la tabella** | `supabase/migrations/20260729230000_security_invariants.sql:1024-1026`; `docs/superpowers/plans/2026-07-29-fase-6d-1-invarianti-sicurezza.md:132-133` |
| La coda di moderazione è citata dalla 6d-1 come futura policy che espone righe altrui, e l'elenco di colonne è già il limite previsto | `supabase/migrations/20260729230000_security_invariants.sql:1002-1004` |
| `setListingStatus` è usata **solo** da `/admin`; `listingActionsFor()` non è chiamata da nessuna parte; costruire quei comandi per il venditore sarebbe funzionalità nuova | `docs/MIGRATION_PHASE_1_BACKLOG.md:113-117`; `docs/ROADMAP_V1.md:207-211` |
| `richiediFoto` è un'azione di moderazione (Fase 9) e resta fuori da `ListingService` | `frontend-next/src/services/types.ts:259-260` |

### 1.3 Debiti che la Fase 9 eredita da ordini e contestazioni (7b/7c/7f)

| Requisito | Fonte |
| --- | --- |
| Della contestazione esistono lo stato e il blocco, **non l'interfaccia di gestione**, che appartiene alla Fase 9 | `docs/MIGRATION_PHASE_1_BACKLOG.md:444-446`; `docs/superpowers/plans/2026-08-03-phase-7b-stripe-connect-marketplace.md:198` |
| Interfaccia di gestione delle contestazioni fuori dal perimetro 7b, assegnata alla Fase 9 | `docs/ROADMAP_V1.md:415` |
| **Coda, assegnazione e audit** delle contestazioni sono Fase 9; la 7c consegna la sola RPC riservata ad `admin` | `docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md:1048-1050` |
| `ordine_contestazione_risolvi` è riservata a `service_role` e al ruolo `admin`, senza alcun `grant execute` verso `authenticated` | `docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md:557-563`; `supabase/migrations/20260805160250_phase_7f_fix_contestazione_enum_cast.sql:97` e il controllo `has_role(v_uid, 'admin')` nel corpo |
| Il `DisputePanel` di `frontend-next/` è dichiaratamente in sola lettura, e l'interfaccia di gestione appartiene alla Fase 9 | `frontend-next/src/components/vinea/orders/DisputePanel.tsx:18-25` |

### 1.4 Debiti che la Fase 9 eredita dalla messaggistica (8)

| Requisito | Fonte |
| --- | --- |
| **Blocco, segnalazione e moderazione persistente** sono esplicitamente fuori dalla Fase 8 e appartengono alla Fase 9 | `docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:26` |
| Il pulsante «altre azioni» dell'intestazione conversazione è **disabilitato** con il titolo «Segnalazione e blocco arrivano con la Fase 9» | `frontend-next/src/components/vinea/messaging/ConversationHeader.tsx:36-42` |

### 1.5 Decisione che il backlog impone di chiudere *entro* la Fase 9

| Requisito | Fonte |
| --- | --- |
| `public_bottle_units` non ha consumatori: **se la 8 o la 9 non la usano va rimossa** insieme al concetto di cantina pubblica per singola bottiglia, oppure va costruita l'interfaccia che la rende visibile | `docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «`public_bottle_units` non ha consumatori» |

La Fase 8 è chiusa e non l'ha usata: le sue quattro tabelle sono
`conversations`, `conversation_participants`, `messages` e `notifications`
(`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 8»). La decisione ricade quindi
interamente sulla Fase 9 — vedi §7.7.

### 1.6 Fuori perimetro, dichiarato

- **Nessuna funzionalità nuova.** L'obiettivo è la parità con `frontend/`, non il
  miglioramento di prodotto (`CLAUDE.md`, sezione «Migration architecture»). Ogni
  voce della §2 che in `frontend/` non ha un chiamante resta senza chiamante
  anche qui.
- Comandi di modifica/sospensione **del venditore** sul proprio annuncio: in
  `frontend/` non esistono e costruirli sarebbe funzionalità nuova
  (`docs/ROADMAP_V1.md:207-213`).
- Ricorsi (`ricorso` in `AuditEntry`): il campo esiste nei dati mock
  (`frontend/src/data/moderation.ts:224`) ma **nessuna interfaccia di
  `frontend/` lo scrive** — è sempre `"nessuno"` tranne in un seed statico
  (`frontend/src/data/moderation.ts:400`). Vedi §7.8.
- Retention e policy di conservazione dei dati: elencate fra le decisioni non
  ancora prese del progetto (`docs/ARCHITECTURE.md:152`). Vedi §7.3.
- SQL remoto, migrazioni, fixture remote, deploy, push, merge: tutti gate
  separati e nessuno chiesto da questo documento.

## 2. Inventario del mock legacy da sostituire

Tre file, un dominio dello store e quattro percorsi UI. Sono l'unica definizione
esistente del comportamento da portare.

### 2.1 `frontend/src/data/moderation.ts` — tipi e dati di riferimento

| Cosa | Righe | Contenuto |
| --- | --- | --- |
| `TrustSource` + etichette | 4-18 | `piattaforma \| venditore \| ia`; è la legenda dei badge di fiducia, non moderazione |
| `ReportTargetType` | 22-33 | **7 tipi di bersaglio**: `annuncio`, `profilo`, `messaggio`, `conversazione`, `post`, `commento`, `recensione` |
| `reportReasons` | 35-61 | Elenco chiuso di motivi **per tipo di bersaglio**: 6 per annuncio, 5 per profilo, 4 per messaggio, 3 per conversazione, 4 per post, 3 per commento, 3 per recensione |
| `ReportStatus` | 63-71 | **5 stati**: `inviata`, `in_revisione`, `info_richieste`, `risolta`, `respinta` |
| `Priorita` | 81 | `bassa \| media \| alta` |
| `Report` | 89-106 | id, bersaglio (tipo/id/etichetta), motivo, descrizione, foto, stato, priorità, `reporter`, `assignee?`, `clubSlug?`, `createdAt`, `updatedAt`, `storia[]`, `noteInterne[]` |
| `priorityFromReason` | 108-120 | Priorità **derivata dal testo del motivo**: `truff/frod/pagament/molest` → alta; `offens/falsa/veritier/ingannev` → media; altrimenti bassa |
| `ListingStatus` | 124-133 | I 9 stati d'annuncio, identici ai valori di `public.listing_stato` (`supabase/migrations/20260728193937_listings_catalog.sql:212-216`) |
| `listingActionsFor` | 160-181 | Azioni ammesse per stato. **Non è chiamata da nessuna parte** (`docs/ROADMAP_V1.md:209-211`) |
| `ModAction` | 185-192 | **7 azioni**: `richiesta_modifiche`, `ammonizione`, `sospensione`, `rimozione`, `ripristino`, `chiusura`, `info_richieste` |
| `AuditEntry` | 214-225 | id, `ts`, `attore`, `scope` (`piattaforma \| club`), `clubSlug?`, `azione`, `target`, `motivazione`, `durata?`, `ricorso?` |
| Seed | 231-403 | 6 segnalazioni, 8 stati d'annuncio, 3 voci di audit |
| `MY_REPORTER` | 406 | Costante `"Elena Rossi"`: nel mock l'identità del segnalante è una stringa, non un utente |

### 2.2 `frontend/src/lib/store/moderation-domain.ts` — lo stato

`useModerationDomain` (25-223) tiene quattro pezzi di stato React —
`reports`, `listingStatus`, `auditLog`, `modScope` — inizializzati dai seed
(26-30) e montati nello store globale da
`frontend/src/lib/vinea-store.tsx:202` e `:214`. Espone sette comandi:

| Comando | Righe | Cosa fa oggi |
| --- | --- | --- |
| `submitReport` | 32-69 | Crea una segnalazione con **id casuale** (44), stato `inviata`, priorità derivata dal motivo, `reporter` fisso a `MY_REPORTER`, una voce di storia «Segnalazione ricevuta»; spinge una notifica di categoria `sistema` |
| `updateReportStatus` | 71-96 | Cambia stato e aggiunge una voce di storia con autore `"Moderazione"`; notifica il segnalante |
| `assignReport` | 98-115 | Scrive `assignee` (stringa libera) e una voce di storia |
| `addReportNote` | 117-130 | Aggiunge una **nota interna**, separata dalla storia visibile |
| `setListingStatus` | 132-135 | Cambia lo stato di un annuncio in una mappa `wineId → ListingStatus`. Usata **solo** da `/admin` (`docs/ROADMAP_V1.md:208`) |
| `applyModAction` | 137-193 | Scrive una voce di `auditLog` e, se c'è un `reportId`, chiude la segnalazione. La mappatura azione→stato è: `info_richieste`→`info_richieste`, `chiusura`→`risolta`, `ripristino`→`respinta`, **tutto il resto**→`risolta` (162-169). L'attore è derivato dallo `scope`: `"Mod. Club"` o `"Mod. Vinea"` (151) |
| `richiediAltreFoto` | 195-207 | Notifica il venditore. È l'azione che `frontend-next/src/services/types.ts:259-260` chiama `richiediFoto` e dichiara di moderazione |

### 2.3 `frontend/src/hooks/useModerationActions.ts` — la lettura della coda

| Hook | Righe | Cosa fa |
| --- | --- | --- |
| `useReportQueue` | 11-26 | Filtra la coda per **ambito** (`piattaforma` o `{club}`), priorità e stato. In ambito club vede solo le segnalazioni con quel `clubSlug` (19) |
| `useModAction` | 43-81 | Tiene motivazione e durata; `actionsFor` (47-59) offre **solo `ripristino`** su una segnalazione già `risolta`/`respinta`, altrimenti le altre sei; `eseguiAzione` **rifiuta senza motivazione** (63) e passa `durata` solo per `sospensione` (69) |
| `useScopedAuditLog` | 88-97 | In ambito club filtra l'audit a `scope === "club"` con quel `clubSlug`; in ambito piattaforma restituisce tutto (94) |

Entrambi i file hanno test: `frontend/src/hooks/useModerationActions.test.ts`
(159 righe) e `frontend/src/lib/store/moderation-domain.test.ts` (104 righe).

### 2.4 I percorsi UI che li consumano

| Percorso | Ruolo | Cosa mostra |
| --- | --- | --- |
| `frontend/src/routes/admin.tsx` | Pannello moderazione. Gate: `ruolo !== "admin"` → schermata di rifiuto (73-84). Selettore di **ambito** piattaforma/club (106-125). Tre schede: **coda** (158-160), **controversie ordini** (161-165, solo in ambito piattaforma), **audit log** (166-168) | `CodaSegnalazioni` (192), `ReportDetail` (314), `ConfirmAction` (502), `Controversie` (566), `AuditLog` (659) |
| `frontend/src/routes/segnalazioni.tsx` | Lato utente: «Le mie segnalazioni», filtrate per `reporter === MY_REPORTER` (44), con la storia di ogni pratica (109-126) | 170 righe |
| `frontend/src/routes/admin.stati.tsx` | Galleria dimostrativa degli stati; usa solo `listingStatusLabel`/`listingStatusTone` (24) | 203 righe |
| `frontend/src/components/vinea/ReportDialog.tsx` | Il dialogo di segnalazione, unico punto d'ingresso di `submitReport` (35, 59); i motivi vengono da `reportReasons[targetType]` (38) | usato da `annuncio.$id.tsx:38` e da `messaggi.tsx:161-170` |
| `frontend/src/routes/messaggi.tsx` | Menu conversazione con «Segnala conversazione» (161-170) e **«Blocca» che è un solo `toast`** (172-174): nel mock il blocco non esiste come dato | — |

Consumatori di sola presentazione, non di moderazione:
`TrustBadge.tsx:2`, `WineCard.tsx:6`, `annuncio.$id.tsx:39`.

### 2.5 Cosa è già stato deciso di **non** portare alla lettera

`frontend/` mostra tre bottoni di risoluzione controversia a **entrambe** le
parti sotto la scritta «Azioni demo»
(`frontend/src/routes/admin.tsx:627-649` per il pannello admin;
`docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md:551-563`
per la divergenza approvata). La 7c ha già deciso che è impalcatura da demo e
non un modello di permessi. La Fase 9 **non** riapre quella decisione.

## 3. Coda contestazioni: cosa esiste già e cosa la Fase 9 aggiunge

Le contestazioni non sono un dominio nuovo. Lo schema, la logica di risoluzione
e i suoi effetti sul denaro sono in produzione dalla Fase 7c, corretti dalla 7f.

### 3.1 Quello che esiste

- `public.disputes`: una riga per ordine (`order_id ... unique`), con `motivo`,
  `descrizione`, fino a 8 foto, `stato`, `esito_nota`, `risolta_da`,
  `apertura_at`, `chiusura_at`
  (`supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql:135-150`).
- `public.dispute_stato`: `aperta`, `in_valutazione`, `rimborsata`, `risolta`,
  `respinta` (stesso file, `:131-133`).
- Il `GRANT` su `disputes` è **a colonne chiuse** e `risolta_da` ne è
  deliberatamente fuori: chi ha deciso la pratica è dato di moderazione e il
  venditore, che pure raggiunge la riga, non deve leggerlo (stesso file,
  `:155-160`).
- `public.ordine_contestazione_apri(uuid, text, text, text[])`: la apre **il solo
  compratore** (`buyer_id <> v_uid` → `42501`), una pratica per ordine, e compone
  `public.ordine_contesta` della 7b senza riaprirla (stesso file, `:999-1051`).
- `public.ordine_contestazione_risolvi(uuid, public.dispute_stato, text)`:
  riservata ad `admin` e `service_role`, tre esiti ammessi, idempotente su una
  pratica già chiusa
  (`supabase/migrations/20260805160250_phase_7f_fix_contestazione_enum_cast.sql:97`
  e seguenti).
- Il vincolo differito `orders_contestazione_ha_pratica` lega il flag
  sull'ordine all'esistenza del fascicolo
  (`supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql:309-314`).

### 3.2 Quello che la Fase 9 aggiunge — e quello che non tocca

**La Fase 9 non scrive logica di risoluzione nuova.** `ordine_contestazione_apri`
e `ordine_contestazione_risolvi` restano le uniche porte, con la firma e la
semantica che hanno oggi. Quelle funzioni muovono `orders.stato`,
`orders.payout_stato` e `contestato_at`, cioè i tre valori su cui filtrano
`ordine_auto_rilascio_esegui`, `payout_coda` e `payout_prepara`: è il codice che
la 7f ha dovuto correggere perché un difetto lì congelava i fondi del venditore
(`CONTESTO_IA/02_STORIA_FASI.md`, sezione «Fase 7f»). Riscriverlo non è nel perimetro di
questa fase.

Quello che manca, e che la Fase 9 porta, è **admin-facing e non transazionale**:

1. **Coda.** Una lettura elencabile delle pratiche aperte, oggi impossibile: le
   policy di `disputes` mostrano a ciascun cliente le proprie righe, e non
   esiste una proiezione che un moderatore possa scorrere. `frontend/` la
   costruisce filtrando in memoria gli ordini che hanno un `dispute`
   (`frontend/src/routes/admin.tsx:566-569`) — un percorso che con RLS reali
   non restituisce nulla.
2. **Assegnazione.** Nel mock è una stringa libera su `Report`
   (`frontend/src/lib/store/moderation-domain.ts:98-115`); su `disputes` non
   esiste alcuna colonna equivalente. Assegnare una pratica a un moderatore è
   quindi **dato nuovo**, e la sua forma è una decisione aperta (§7.5).
3. **Audit.** Oggi l'unica traccia di chi ha deciso è `disputes.risolta_da` e la
   riga in `public.order_events` che `ordine_contestazione_risolvi` scrive con
   `tipo = 'contestazione_risolta'`. Non c'è un registro append-only unico per
   tutte le azioni di moderazione: è esattamente ciò che il backlog chiama
   `audit_log` (`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService»).

La coda contestazioni e la coda segnalazioni restano **due code distinte con due
tabelle distinte**, unite solo dall'audit e dalla schermata: in `frontend/` sono
già due schede separate del pannello (`frontend/src/routes/admin.tsx:158-168`), e
fonderle sarebbe un ridisegno, non una migrazione.

## 4. Schema, in linguaggio naturale

Nessuna riga di SQL. Questa sezione descrive **cosa** deve esistere; il **come**
si scrive dopo che le decisioni della §7 hanno una risposta.

### 4.1 `audit_log` — il registro append-only

- **Una riga per azione di moderazione compiuta**, mai modificata e mai
  cancellata dai percorsi applicativi. È il requisito testuale del backlog
  (`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService») e la ragione per cui le tre
  colonne di traccia su `listings` non bastano: quelle conservano solo
  *l'ultima* transizione e vengono sovrascritte
  (`supabase/migrations/20260728193937_listings_catalog.sql:272-274`).
- **Scrittura solo via funzione `SECURITY DEFINER`**, mai `INSERT` dal client.
  È il pattern che il progetto applica già a ogni colonna con una regola di
  dominio dietro (`CLAUDE.md`, «Postgres exposure rules», terza regola).
- **Nessun `UPDATE` né `DELETE` per nessun ruolo client**, e un trigger che
  rifiuti entrambi anche a `service_role`: append-only che dipende solo dai
  `GRANT` è append-only finché qualcuno non aggiunge un `GRANT`. Il progetto usa
  già i trigger per gli invarianti che un indice o un `CHECK` non esprimono
  (`CLAUDE.md`, «Postgres exposure rules», terza regola).
- **Campi minimi, derivati dal mock `AuditEntry`**
  (`frontend/src/data/moderation.ts:214-225`): quando, chi ha agito (identità
  reale, non la stringa `"Mod. Vinea"`), ambito piattaforma o club, azione fra le
  sette esistenti, bersaglio, motivazione obbligatoria, durata quando l'azione è
  una sospensione.
- **Il bersaglio è polimorfico** — annuncio, profilo, messaggio, conversazione,
  post di club, commento, recensione (`frontend/src/data/moderation.ts:22-33`) —
  e quindi non può essere una singola foreign key. La forma esatta (colonna tipo
  + id senza vincolo referenziale, oppure una colonna nullable per ciascun
  bersaglio con vincolo di esclusività) è una scelta di modellazione da fare
  dopo aver risposto alla §7.6: due dei sette bersagli, `post` e `commento`, non
  hanno alcuna tabella in Supabase oggi.
- **La motivazione è obbligatoria.** Il mock lo impone già lato client
  (`frontend/src/hooks/useModerationActions.ts:63`) e in questa fase diventa un
  vincolo di database.

### 4.2 Tabella segnalazioni

Il modello di riferimento è il tipo `Report`
(`frontend/src/data/moderation.ts:89-106`), con tre differenze imposte dal
passaggio a un database reale:

- **Il segnalante è un utente, non una stringa.** Nel mock è la costante
  `MY_REPORTER` (`frontend/src/data/moderation.ts:406`); qui è un riferimento a
  `public.profiles` derivato da `auth.uid()` server-side, come ogni altra
  identità di questo progetto (`CLAUDE.md`, invarianti trasversali: il frontend
  non è un confine di fiducia). Se sia **leggibile** dal moderatore è la
  decisione aperta §7.4.
- **L'id non è casuale.** Il mock genera `SEG-2026-####` con `Math.random()`
  (`frontend/src/lib/store/moderation-domain.ts:44`); qui è una chiave del
  database. Un eventuale codice leggibile resta un'etichetta derivata, non la
  chiave.
- **La priorità è derivata sul server.** `priorityFromReason`
  (`frontend/src/data/moderation.ts:108-120`) è una regola di dominio e come
  tale non è un valore che il client invia.

Restano dal mock, senza aggiunte: i 7 tipi di bersaglio, l'elenco chiuso di
motivi per tipo (`:35-61`), i 5 stati (`:63-71`), la storia visibile e le note
interne come due sequenze separate (`:104-105`), e l'ambito club opzionale
(`:101`).

**Le note interne non sono leggibili dal segnalante.** Nel mock la separazione è
solo strutturale; qui è un confine di privilegio, ed è lo stesso motivo per cui
`disputes.risolta_da` è fuori dal `GRANT`
(`supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql:155-158`).

### 4.3 Relazioni con ciò che esiste

| Relazione | Con che cosa | Nota |
| --- | --- | --- |
| Bersaglio `annuncio` | `public.listings` | Le tre colonne di traccia esistono già e restano fuori dal `GRANT` client (`supabase/migrations/20260729230000_security_invariants.sql:1015-1026`) |
| Bersaglio `profilo` | `public.profiles` | Nessuna colonna di stato utente esiste oggi: sospensione e ban sono dato nuovo, vedi §7.4 |
| Bersaglio `messaggio` / `conversazione` | `public.messages`, `public.conversations` (Fase 8, `docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 8») | I messaggi sono immutabili (`docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:50-51`): la moderazione di un messaggio non può essere una modifica del testo |
| Bersaglio `recensione` | `public.order_reviews` (7c) | — |
| Bersaglio `post` / `commento` | **niente** | I club non hanno schema Supabase. Vedi §7.6 |
| Contestazioni | `public.disputes` | Coda e audit si agganciano; la risoluzione resta la RPC esistente, §3.2 |
| Attore della moderazione | `public.user_roles` + `public.has_role()` | Un utente vede solo i propri ruoli (`supabase/migrations/20260729230000_security_invariants.sql:1081-1082`, riscritta in `20260730140948:283-285`); nessuno se li autoassegna (`docs/SECURITY.md:65-66`) |
| Transizioni di stato annuncio | `public.listing_stato` | I tre valori di moderazione **esistono già** e non serve alterare l'enum (`supabase/migrations/20260728193937_listings_catalog.sql:212-216`, `:229-230`) |
| Notifica al segnalante | `public.notifications` (Fase 8) | Il mock notifica a ogni cambio di stato (`frontend/src/lib/store/moderation-domain.ts:61-65`, `:89-93`); la categoria `sistema` esiste già (`docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:60-63`) |

## 5. Pattern di sicurezza da riusare

Questa fase è la prima che introduce **un ruolo che legge righe di altri**. È
esattamente lo scenario che la 6d-1 aveva previsto quando ha chiuso i privilegi
(`supabase/migrations/20260729230000_security_invariants.sql:1002-1004`), e le
tre regole di `CLAUDE.md` («Postgres exposure rules», vincolanti dalla 6d-1) si
applicano tutte:

1. **Nessun `GRANT SELECT` di tabella intera a un ruolo che raggiunge righe non
   sue.** Se una policy lascia al moderatore le righe altrui, quella tabella ha
   un `GRANT` a colonne chiuse o nessuno. Vale per `reports`, per `audit_log` e
   per qualunque proiezione della coda.
2. **Le letture allargate passano da una vista `security_invoker = off` a elenco
   di colonne chiuso**, non da una policy sulla tabella base. `public_listings` e
   `public_bottle_units` sono il modello: il filtro sta dentro la vista dove
   nessun client può allargarlo, e una colonna aggiunta domani alla tabella base
   resta privata finché qualcuno non la elenca.
3. **Una colonna con una regola di dominio dietro non è scrivibile dal client**:
   esce dal `GRANT` e ha una funzione `SECURITY DEFINER` come unica porta. Vale
   per lo stato della segnalazione, per lo stato di moderazione dell'annuncio e
   per ogni riga di `audit_log`.

Conseguenze concrete per questa fase:

- **La proiezione «il venditore legge il motivo del rifiuto» è una vista o una
  RPC a righe proprie, non un allargamento del `GRANT` su `listings`.** È
  scritto due volte, in migrazione e nel piano
  (`supabase/migrations/20260729230000_security_invariants.sql:1024-1026`;
  `docs/superpowers/plans/2026-07-29-fase-6d-1-invarianti-sicurezza.md:132-133`).
- **La sospensione di moderazione è una funzione separata con `has_role()`**, non
  un allargamento di `listing_sospendi`, che oggi accetta il solo proprietario
  (`supabase/migrations/20260729112500_listings_write.sql:333-334`, `:378-380`).
- **Le funzioni di scrittura seguono la forma già usata dalla Fase 8**:
  `SECURITY DEFINER`, `search_path = ''`, ogni oggetto qualificato, `auth.uid()`
  verificato dentro, `execute` revocato a `PUBLIC` e `anon`
  (`docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:87-90`).
- **Rate limit lato server sulla segnalazione**, con l'infrastruttura condivisa
  che esiste dalla Fase 7 (`private.rate_limit_buckets`,
  `private.vinea_check_request`, `CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 7 — proposte, ordini, pagamenti»).
  Senza, la segnalazione è una porta di scrittura anonima al ritmo che il client
  decide.
- **Le prove sono una griglia SQL versionata in `supabase/tests/`**, e vanno
  **eseguite**: una griglia mai eseguita non è una prova, e la 7e ha misurato
  quanto costa crederlo (`CLAUDE.md`, sezione sulle griglie;
  `CONTESTO_IA/04_HANDOFF_NUOVA_IA.md`, sezione «Stato da non reinterpretare»).

## 6. Suddivisione proposta in sotto-fasi

**Proposta: 9a lettura e coda, 9b scrittura e azioni.** Due branch? No: una sola
fase, `migration/phase-9-moderation-service`
(`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 9 — ModerationService»), due checkpoint con verifica e commit
atomico ciascuno — la stessa forma dei checkpoint 8a/8b/8c
(`docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:146-165`).

### 9a — schema, privilegi, coda in lettura

Tabelle, enum, RLS, `GRANT` a colonne chiuse, viste/proiezioni della coda,
`audit_log` con la sua funzione di scrittura, griglia SQL statica e griglia
fixture. Lato client: solo lettura — coda segnalazioni, coda contestazioni,
elenco audit, «Le mie segnalazioni».

### 9b — azioni e scritture

Le RPC che eseguono le sette azioni di moderazione, la sospensione di
moderazione sugli annunci, la transizione `in_revisione`/`modifiche_richieste`/
`rifiutato`, l'assegnazione, le note interne, la proiezione del motivo di rifiuto
per il venditore. Lato client: i comandi del pannello.

### Perché in quest'ordine

- **È il modello già usato due volte in questo progetto**: 6a legge il catalogo e
  6b lo scrive (`docs/MIGRATION_PHASE_1_BACKLOG.md:58` e `:91`); 6c-1 fa lo
  schema Cantina e 6c-2 l'interfaccia (`:136` e `:170`). La Fase 5 è divisa per
  provider (5a email, 5b OAuth) e non per lettura/scrittura, quindi il
  precedente utile è la 6.
- **La 9a è la parte che decide la sicurezza**, e la 9b quella che la usa. Se il
  perimetro dei privilegi è sbagliato, si scopre mentre si scrivono le
  proiezioni, non dopo aver costruito sette comandi sopra.
- **La 9a è reversibile, la 9b no.** Una tabella in più senza chiamanti è
  superficie; una sospensione applicata a un annuncio reale è un effetto sul
  prodotto. La 7c ha già registrato quanto costa scoprire tardi che una funzione
  di scrittura non compilava
  (`CONTESTO_IA/02_STORIA_FASI.md`, sezione «Fase 7f»).
- **`audit_log` deve esistere prima della prima azione**, non insieme. Un
  registro append-only che nasce dopo le azioni che dovrebbe registrare nasce
  già incompleto.

## 7. Decisioni aperte — servono una risposta esplicita prima di qualunque SQL

Nessuna di queste ha una fonte nel repository. Tutte vanno chiuse in chat
organizzativa e registrate, come è stato fatto per le decisioni economiche della
7d (`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 7d — decisioni economiche»).

### 7.1 Chi può moderare: ruolo dedicato o riuso di `admin`?

Oggi esiste `admin`, ed è il ruolo che `ordine_contestazione_risolvi` controlla
(`docs/superpowers/plans/2026-08-04-phase-7c-delivery-packaging-design.md:557-563`).
`frontend/` ha però **due ambiti distinti**: moderatore di piattaforma e
moderatore di club, con l'audit filtrato per ambito
(`frontend/src/hooks/useModerationActions.ts:88-97`;
`frontend/src/routes/admin.tsx:106-125`). `user_roles` è una tabella
`(user_id, role)` senza colonna d'ambito
(`supabase/migrations/20260728000545_auth_profiles_roles.sql:72-77`), quindi
«moderatore del club X» non è esprimibile con la forma attuale.

Da decidere: (a) riusare `admin` per tutto e rinviare l'ambito club; (b) un ruolo
`moderator` distinto da `admin`; (c) un ruolo per ambito, che richiede di
estendere `user_roles`. Nessuna delle tre è deducibile da ciò che è scritto.

### 7.2 Chi assegna i ruoli, e come

Nessuna interfaccia scrive `user_roles`: solo `service_role` e le funzioni
`SECURITY DEFINER` dedicate
(`supabase/migrations/20260728000545_auth_profiles_roles.sql:79-86`). L'unico
scrittore reale oggi è il trigger `seller_enabled` della 7b, che agisce su un
evento firmato (`supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql:223`
e `:235`). Serve dire se la Fase 9 aggiunge una porta di assegnazione o se i
moderatori si creano fuori banda.

### 7.3 Retention dell'audit log

`docs/ARCHITECTURE.md:152` elenca «policy di conservazione dei dati e
moderazione» fra le decisioni **non prese**. Un registro append-only senza
retention cresce senza fine; una retention che cancella righe contraddice
l'append-only. Le due risposte compatibili sono «nessuna cancellazione, mai» e
«archiviazione fredda dopo N mesi con la cancellazione fuori dai percorsi
applicativi». Va scelta prima, perché cambia la forma della tabella.

### 7.4 Segnalazioni anonime o tracciate

Nel mock il segnalante è una stringa costante
(`frontend/src/data/moderation.ts:406`) e la schermata «Le mie segnalazioni»
filtra su di essa (`frontend/src/routes/segnalazioni.tsx:44`): l'identità serve
al segnalante per rivedere le proprie pratiche. Non è però scritto da nessuna
parte se il **moderatore** debba vederla. Le due opzioni hanno conseguenze
opposte: tracciata permette di riconoscere l'abuso della segnalazione, anonima
protegge chi segnala una controparte con cui ha un ordine aperto. Da decidere,
insieme al fatto che sia il segnalato a non doverla vedere in nessun caso.

### 7.5 Assegnazione delle pratiche

Nel mock è una stringa libera (`frontend/src/lib/store/moderation-domain.ts:98-115`)
e su `disputes` non esiste. Da decidere se esiste come dato (riferimento a un
moderatore reale), se è opzionale, e se una pratica assegnata è ancora
lavorabile da un altro moderatore.

### 7.6 Cosa vede l'utente sospeso o bannato

Il mock ha `sospensione` e `rimozione` fra le azioni
(`frontend/src/data/moderation.ts:185-192`) e una `durata` sull'audit (`:223`),
ma **`public.profiles` non ha alcuna colonna di stato utente**
(`supabase/migrations/20260728000545_auth_profiles_roles.sql:13-27`) e nessun
percorso di `frontend/` mostra cosa succede a un utente sospeso. Da decidere:
se la sospensione blocca il login, o solo le scritture; se l'utente vede un
messaggio e quale; se i suoi annunci attivi restano visibili; se le sue
conversazioni della Fase 8 restano leggibili. Senza risposta, «sospendi» è un
bottone che scrive una riga di audit e non fa nulla.

Nello stesso blocco: **`post` e `commento` sono due dei sette tipi di bersaglio
segnalabili** (`frontend/src/data/moderation.ts:22-23`) e i club non hanno
schema Supabase. Da decidere se la Fase 9 li accetta come bersagli senza
riferimento, o se li esclude fino alla fase che porterà i club.

### 7.7 `public_bottle_units` e la cantina pubblica

Il backlog impone di chiudere questa decisione **entro la Fase 9**
(`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «`public_bottle_units` non ha consumatori»): la vista non ha consumatori, né
in `frontend-next/` né in `frontend/`, e va rimossa insieme al concetto di
cantina pubblica per singola bottiglia oppure va costruita l'interfaccia che la
rende visibile. La Fase 8 è chiusa e non l'ha usata. **Rimuoverla è però
funzionalità in meno, non parità**: la decisione è del committente e non
dell'esecutore.

### 7.8 SLA e ricorsi

Nessuna fonte nel repository fissa un tempo di presa in carico o di risoluzione.
Il mock ha una priorità derivata dal motivo
(`frontend/src/data/moderation.ts:108-120`) che oggi serve solo a ordinare la
coda. Da decidere se la priorità ha un SLA associato, e se lo sforamento è
misurato — nel qual caso serve un controllo di sanità come quello che la 7g ha
scritto per lo scheduler
(`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 7g»).

Sui **ricorsi**: `AuditEntry.ricorso` esiste nel tipo
(`frontend/src/data/moderation.ts:224`) ma nessuna interfaccia di `frontend/` lo
scrive. Portarlo sarebbe funzionalità nuova; non portarlo lascia un campo morto.
Da decidere quale delle due.

### 7.9 Dove sta il gate di autorizzazione

Non è una decisione della Fase 9 ma la precede: la regola scritta presidia
`supabase db push`, mentre il percorso reale di distribuzione è il merge su
`main`. È registrata come **non decisa** e riguarda ogni fase successiva
(`CONTESTO_IA/01_STATO_ATTUALE.md`, «Gate aperti»;
`CONTESTO_IA/04_HANDOFF_NUOVA_IA.md`, gate 2).

## 8. Effort e dipendenze

### 8.1 Dipendenze da fasi ancora aperte

| Dipendenza | Stato | Effetto sulla Fase 9 |
| --- | --- | --- |
| Fase 8 — messaggistica | **Integrata**, PR #27 (`docs/MIGRATION_PHASE_1_BACKLOG.md`, sezione «Fase 8») | Nessun blocco: `messages` e `conversations` esistono come bersagli, `notifications` come canale verso il segnalante |
| Club (post, commenti) | **Nessuno schema Supabase** | Blocca 2 dei 7 tipi di bersaglio, §7.6 |
| Stato utente su `profiles` | **Non esiste** | Blocca sospensione e ban finché §7.6 non è chiusa |
| Ambito club nei ruoli | `user_roles` è `(user_id, role)` (`supabase/migrations/20260728000545_auth_profiles_roles.sql:72-77`) | Blocca il moderatore di club finché §7.1 non è chiusa |
| Griglie 7 (16 casi), 7b (23), 6d-2a (18) | **Senza esito** (`CLAUDE.md`, sezione griglie) | Non blocca la Fase 9, ma la sua griglia non va ad aggiungersi a quel debito senza essere eseguita |
| Scheduler auto-rilascio 7g | Attivo su `main` e **fallito a ogni esecuzione**: `gh run list --workflow "Phase 7 - auto-release payouts"` dà 11 run su 11 in `failure` dal 7 al 9 agosto 2026, tutte con `Configurazione mancante: SUPABASE_URL` | Non blocca la Fase 9; è però il gate operativo aperto con priorità più alta |
| Decisione 3e (spedizione) e 2c (tetto tentativi fee) | Aperte (`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 7d») | Nessun effetto: dominio disgiunto |

### 8.2 Ordine di grandezza

Stima per confronto con le fasi già chiuse, non misura:

- La Fase 8 ha prodotto una migrazione da 1307 righe
  (`supabase/migrations/20260806224517_phase_8_messaging_notifications.sql`), due
  griglie SQL (`supabase/tests/8_messaging_notifications_static.sql` a 20 casi e
  `supabase/tests/8_messaging_notifications.sql` a 23) e 43 test in più:
  `.github/workflows/ci.yml:99` passa da `MIN_TESTS: "123"` a `"166"` fra
  `f9c53e0` e `4f96864`.
- La Fase 9 ha **meno tabelle** (segnalazioni + audit contro le quattro della 8),
  **nessun Realtime**, ma **più superficie di privilegio**: è la prima fase in cui
  un ruolo legge righe altrui, e ogni proiezione va provata contro un chiamante
  che non è il proprietario.
- Le sette azioni di moderazione (`frontend/src/data/moderation.ts:185-192`) sono
  sette RPC distinte, non una con un parametro: è la stessa ragione per cui
  `ListingService` ha un metodo per transizione e non un `aggiornaStato(id, stato)`
  (`frontend-next/src/services/types.ts:255-258`).

**Il costo dominante non è il codice, sono le nove decisioni della §7.** Sette di
esse cambiano la forma dello schema. Scrivere SQL prima che siano chiuse
significa scommettere, che è esattamente ciò che la 7d ha rifiutato di fare sulla
decisione 3e (`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 7d»).
