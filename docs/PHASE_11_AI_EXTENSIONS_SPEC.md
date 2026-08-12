# Fase 11 — Estensioni AI ammesse per eccezione

> **Documento organizzativo. Nessuna riga di codice, nessuna migrazione.**
> La Fase 11 **non è iniziata e non ha branch**. Il branch `migration/phase-11-*`
> si apre **dopo** che le decisioni della sezione 6 sono chiuse in sessione con
> Enrico, sul modello dei 9a/9b/9c della Fase 9 e dei 10a/10b/10c della Fase 10 —
> non prima.
>
> Le quattro funzionalità sono ammesse **per eccezione esplicita e per nome**
> dalle decisioni 7.3, 7.12 e 7.13 della Fase 10. «Niente funzionalità nuove
> durante la migrazione» **non è decaduta**: continua a valere per tutto ciò che
> una sessione non ha chiesto per nome.

---

## Su quale commit sono fissate le righe

**Hash di riferimento: `271c7dc`** — `docs: la Fase 10 è chiusa, e le fasi sono
rinumerate (Fase 11 estensioni AI, Fase 12 cutover)` (#36), mersa in squash il
**12 agosto 2026 alle 09:48:00 UTC** e ultimo commit su `main` al momento in cui
questo documento è stato ri-fissato. Come la spec della Fase 10 si era fissata su
`8dd56c0`, ogni `file:riga` di questo documento è letto lì.

**Perché non `442c98c`, e perché la cosa vale la pena di essere raccontata.** La
prima stesura era fissata sul merge della Fase 10 e portava un avvertimento in
testa: la numerazione stessa che il documento usa — cutover da Fase 11 a Fase 12,
e le quattro estensioni AI promosse a Fase 11 — viveva su una PR aperta e non
ancora mersa, non su `main`. Descriveva cioè una fase il cui numero esisteva su
un branch e non sul ramo principale. Quella PR è la **#36**, ed è ora mersa:
l'avvertimento è decaduto e le righe sono state **ri-fissate misurando lo scarto
file per file**, non ricalcolandolo a mente.

Lo scarto misurato fra `442c98c` e `271c7dc` — che serve a chiunque legga la
prima stesura, o una citazione presa in prestito da un documento più vecchio:

| File | Righe | Zona | Scarto |
| --- | --- | --- | --- |
| `docs/PHASE_10_AI_SERVICE_SPEC.md` | 1348 → 1369 | tabella di stato (§ iniziale) | **+9** |
| | | regole di esposizione (§4.3) | **+11** |
| | | decisioni §7.1 / §7.3 / §7.12 / §7.13 | **+20** |
| | | da §7.4 in poi (limiti, superficie, §7.11) | **+21** |
| `CONTESTO_IA/01_STATO_ATTUALE.md` | 1254 → 1361 | tutto il file, uniforme | **+107** |
| `CLAUDE.md` | 574 → 639 | sezione Fase 11 | **+44** |
| `CHANGES.log` | 84 → 74 | `CURRENT STATE` | **+6** |

Lo scarto **non è uniforme dentro un file**: nella spec della Fase 10 vale +9,
+11, +20 o +21 secondo la zona. È la ragione per cui è stato misurato riga per
riga anziché applicato in blocco — un solo offset avrebbe sbagliato tre zone su
quattro.

Le fonti che sono **codice, migrazione, workflow o frontend legacy** non si sono
mosse di una riga: la #36 è sola documentazione e non tocca `frontend/`,
`frontend-next/`, `backend/`, `supabase/` né `.github/`. Le loro citazioni
`file:riga` della prima stesura sono rimaste valide senza toccarle — 33 delle 37
citazioni assolute.

**Un'ultima avvertenza, che riguarda la PR che porta questo documento.** Essa
corregge sei righe di prosa non aggiornata nel `§7.12` della spec della Fase 10
(sezione 6.4b spiega quale e perché), sostituendole con diciassette. Le citazioni
qui sotto restano corrette **perché sono fissate su `271c7dc`**, che è il senso di
fissare un hash; ma su `main` dopo questa PR ogni riferimento a
`docs/PHASE_10_AI_SERVICE_SPEC.md` **oltre la riga 766** vale **+11**. Misurato:
1368 righe a `271c7dc`, 1379 dopo.

*Convenzione di notazione:* `271c7dc:NNN` senza altro nome indica sempre
`docs/PHASE_10_AI_SERVICE_SPEC.md`; un `:NNN` isolato continua l'ultimo file
nominato nella stessa frase, come nelle spec delle fasi precedenti. Le **38
citazioni assolute** di questo documento sono verificate a macchina: file
esistente su `271c7dc` e riga esistente in quel file. Le citazioni in forma di
continuazione sono state ri-mappate a mano una per una, perché nessuno script le
riconosce: sono quelle che un rinumero automatico avrebbe lasciato indietro.

Una correzione minore alla commissione che ha prodotto questo documento: la spec
della Fase 9 si chiama `docs/PHASE_9_MODERATION_SERVICE_SPEC.md`, non
`docs/PHASE_9_MODERATION_SPEC.md`. È quella la forma qui replicata — perimetro,
inventario, pattern riusabili, decisioni aperte, sotto-fasi, effort.

---

## 1. Perimetro

### 1.1 Le quattro funzionalità

| | Funzionalità | Origine | SQL? | Provider esterno |
| --- | --- | --- | --- | --- |
| **7.3a** | Autofill dei campi catalogo da foto dell'etichetta | Decisione 7.3 | No | Modello di visione (7.1) |
| **7.3b** | Spunta di completezza documentale sull'annuncio | Decisione 7.3 | **Sì** — una colonna su `listings` | Stesso della 7.3a |
| **7.12** | Triage di moderazione: classifica e ordina la coda | Decisione 7.12 | **Sì** — esito persistito | Livello più economico (7.1) |
| **7.13** | Ritaglio e sfondo reale al posto della demo | Decisione 7.13 | Probabile — policy di Storage | **PhotoRoom**, non un LLM |

Sono le stesse che la Fase 10 aveva numerato **10d** (7.3a + 7.3b), **10e**
(7.13) e **10f** (7.12) nella sua sezione 6, e che il suo unico checkpoint ha
lasciato fuori. La ragione registrata allora vale ancora, ed è la ragione per cui
questo documento esiste: sono **meno specificate**, e ciascuna merita la propria
sessione di spec prima del codice.

### 1.2 Fuori perimetro, dichiarato

- **L'autonomia parziale del moderatore AI.** Rinviata esplicitamente dalla 7.12,
  non decisa: richiede una revisione legale (AI Act, in vigore dal 2 agosto 2026,
  e DSA sulle decisioni automatizzate) che nessuna fase di migrazione fa.
- **Il cutover**, che è la Fase 12.
- **Qualunque quinta funzionalità.** L'eccezione della 7.3/7.12/7.13 è nominativa.
  Se durante l'implementazione emerge che ne servirebbe un'altra, quello è un
  segnale di fermarsi e segnalare, non di costruirla.
- **La revisione legale della spunta 7.3b.** Il vincolo di etichettatura è già
  deciso (sezione 2.1); una validazione legale di come è formulata non è compito
  di questa fase.

---

## 2. Stato ereditato — chiuso, non si riapre qui

### 2.1 Le quattro decisioni che ammettono la fase

Fonte primaria: `docs/PHASE_10_AI_SERVICE_SPEC.md`, sezione 7 (`§7.3` a
`271c7dc:704`, `§7.12` a `:745`, `§7.13` a `:768`, `§7.1` a `:661`). Fonte
gemella, con le stesse risposte in forma di verbale:
`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 10 — decisioni organizzative»
(`:998` e seguenti; 7.3 a `:1023-1032`, 7.12 a `:1033-1042`, 7.13 a `:1043-1049`).

**7.3 — dentro per eccezione, e sdoppiata.** Non una funzionalità, due. La 7.3a è
l'erede diretto del suggerimento di catalogazione del legacy con una foto al
posto dei campi testuali `ocr_text`/`hint`; resta un **suggerimento**, con i nove
campi tipizzati e il `confidence` in `[0,1]` già in produzione
(`supabase/functions/ai-catalogo/index.ts:31-33`, `:77-87`). La 7.3b verifica che
le foto coprano il prodotto — etichetta, livello, tappo — e **condivide la
chiamata di visione con la 7.3a**.

> **Il vincolo di onestà è parte della decisione, non una raccomandazione.** La
> spunta va etichettata **completezza documentale** e **mai** autenticità
> certificata. Nessuna AI può certificare l'autenticità di una bottiglia da una
> fotografia. Si aggancia a un invariante già in vigore — «le risposte non
> certificano autenticità o valore» (`docs/SECURITY.md:189-197`) — e lo rende più
> difficile da rispettare, perché stavolta l'affermazione non è in un testo
> generato ma in un elemento di interfaccia che il prodotto mostra come proprio.

**7.12 — solo triage, nessuna azione.** L'AI classifica e ordina dentro il
pannello di moderazione della Fase 9 già esistente; un moderatore umano preme
sempre il bottone finale. **Nessuna nuova RPC di esecuzione, nessuna identità
«attore AI» nell'`audit_log`**: non serve, perché l'AI non scrive niente di
moderazione.

**7.13 — dentro per eccezione, sfondi curati.** PhotoRoom come opzione tecnica
preferita, per il compositing su sfondo nativo e non il solo cutout. Il
**catalogo di sfondi è curato a mano da Enrico, non generato al volo**: un
piccolo insieme di immagini caricate una volta, e il venditore sceglie se usarne
una o tenere la propria foto. PhotoRoom **non passa dall'astrazione `AIProvider`**
e porta una chiave di natura diversa.

**7.1 — un provider per compito, non uno unico.** Per le funzionalità fotografiche
la tabella della decisione dice «Claude o Gemini», **da scegliere provandoli su
foto vere di etichette** — vetro, curvatura, luce non perfetta — e non su un
benchmark di documento pulito. Per il triage, il livello più economico
disponibile: qui il volume conta più della qualità. **La prova non è stata
fatta.**

### 2.2 I vincoli trasversali della Fase 10 che valgono anche qui

- **7.10 — il deploy è il merge.** Non esiste un passo di deploy separato da
  autorizzare: il merge su `main` distribuisce migrazioni **e ridistribuisce
  tutte le Edge Function, comprese quelle che la PR non ha toccato**. Misurato
  due volte, l'ultima l'11 agosto 2026: le tre function nuove della Fase 10
  create 38 secondi dopo il merge, e tutte e sei con lo stesso `updated_at` 43
  secondi dopo, con le tre preesistenti passate a versione 15/14/14 e hash di
  bundle nuovi. **Conseguenza operativa per questa fase: l'ambiente di una
  function si configura prima del merge, mai dopo.**
- **`_shared/cors.ts` ha diff vuoto e deve mantenerlo** (7.6). Le function AI
  leggono `AI_ALLOWED_ORIGINS` da `_shared/ai-cors.ts`, un modulo separato che
  replica il pattern invece di importarlo. Toccare il file condiviso rimetterebbe
  il percorso dei pagamenti in produzione a ogni merge successivo, chiunque lo
  faccia e per qualunque motivo.
- **`AI_ENABLED` fallisce chiuso** (7.5), e la mappatura degli errori è quella
  del legacy: provider giù → 503, forma di risposta inutilizzabile → 502, errore
  generico al client e **mai il messaggio del fornitore**
  (`supabase/functions/_shared/ai-gate.ts:109`,
  `docs/ENVIRONMENT.md:57`).
- **Una porta per operazione**, non un campo `action` nel corpo (7.6), sul
  precedente delle sette RPC distinte della Fase 9.
- **7.9 — l'accesso AI segue i due livelli di sospensione** di 9b/9c. Primo
  livello: non tocca l'AI. Secondo livello: la blocca, stessa superficie delle
  altre funzionalità sociali.
- **Le tre regole di esposizione Postgres** (`CLAUDE.md`, sezione «Postgres
  exposure rules»; ripetute in `docs/PHASE_10_AI_SERVICE_SPEC.md` `§4.3`,
  `271c7dc:477-496`) valgono integralmente per le due colonne nuove. Vale anche
  l'avvertenza della 9b: se si aggiunge una colonna a una tabella che ha un
  `GRANT UPDATE` di tabella intera, quel grant va ristretto **nello stesso
  momento**.
- **Una migrazione già pushata è congelata.** Ogni correzione è un file nuovo con
  timestamp più recente — anche in bozza, anche se nessun ambiente l'ha mai
  applicata.
- **Una griglia SQL scritta non è una prova finché non è stata eseguita almeno
  una volta**, e l'autorizzazione a eseguirla è **per griglia, non per progetto**.

### 2.3 Una decisione della 7.1 che il codice della 10a ha già chiuso

La 7.1 lasciava scoperti tre punti. **Uno dei tre non è più aperto**, e va tolto
dal tavolo prima della sessione: il `request_id` inoltrato al fornitore. Nel
legacy conteneva l'uuid dell'utente; la 10a lo ha reso **opaco per costruzione**
— `requestIdOpaco` genera `<compito>:<uuid casuale>`
(`supabase/functions/_shared/ai-provider.ts:59-60`) ed è usato da tutte e tre le
function (`supabase/functions/ai-catalogo/index.ts:110`,
`supabase/functions/ai-pairing/index.ts:131`,
`supabase/functions/ai-sommelier/index.ts:112`). Con un provider per compito lo stesso dato personale
sarebbe uscito verso tre o quattro terzi invece che verso uno: il debito è chiuso
prima che il numero di terzi crescesse. **Le funzionalità di questa fase devono
usare la stessa funzione**, non costruirsi un identificativo proprio.

Restano scoperti gli altri due, e sono di questa fase: **più provider significa
più chiavi** (7.11 va letta al plurale), e **PhotoRoom non è nella tabella dei
provider** perché non è un fornitore di modelli linguistici.

### 2.4 Le decisioni chiuse in sessione il 12 agosto 2026

Quattro decisioni che la prima stesura di questo documento elencava fra le aperte
sono state chiuse leggendolo. Sono registrate qui con la data e, dove Enrico ha
dato una motivazione, **con la sua**, perché il motivo di una decisione vale più
della decisione e sopravvive meglio a chi la rilegge fra tre mesi.

**11.A — Storage: bucket dedicato, non riuso di `annunci` o `cantina`.** Chiusa il
12 agosto 2026. Il motivo è quello scritto da Enrico ed è il fatto misurato al
3.2: **`annunci` è pubblico**, quindi una foto caricata solo per l'autofill e poi
abbandonata resterebbe **leggibile per sempre da chiunque ne conosca l'URL**. La
decisione chiude la domanda 6.1(a) e **lascia aperto tutto il resto di quella
sezione** — nome del bucket, pubblico o privato, ciclo di vita e pulizia degli
orfani, dimensione massima, tipi MIME accettati. Chiudere «dedicato» non decide
«privato»: sono due proprietà diverse, e il motivo che ha scartato `annunci` è un
argomento forte perché il nuovo bucket sia privato, ma non è la decisione.

**11.B — 7.3a e 7.3b sono due Edge Function distinte, non una condivisa.** Chiusa
il 12 agosto 2026. Segue il pattern «**una porta per operazione**» già applicato
dalle sette RPC della Fase 9 e dalle tre function della Fase 10. Chiude la 6.2
scegliendo la seconda riga della sua tabella, e con essa **accetta esplicitamente
il contro registrato lì**: se una sola chiamata di visione bastasse per entrambe,
due function significano due chiamate e costo doppio. Questa è la conseguenza che
la decisione compra in cambio di due bucket di frequenza separati e di una
superficie che non nasconde un `action` nel corpo — la forma che la 7.6 aveva
respinto. Ne segue anche che la tabella della 7.6 (`271c7dc:1010`), che metteva
entrambe dentro `ai-catalogo`, **è superata su questo punto**.

**11.C — questo documento vive in una PR propria**, separata dalla #36. Decisione
di processo, registrata perché chi legge dopo capisca perché la chiusura della
Fase 10 e la specifica della Fase 11 non sono nello stesso commit: «*la inserirei
in una PR apposta così da non fare confusione*». È la stessa forma della Fase 10,
dove la specifica (#34) precedette l'implementazione (#35) su un branch `docs/` e
non su un `migration/`.

**11.D — il via libera alla PR #36 è stato condizionato, non incondizionato.** La
formulazione esatta, che vale più di una parafrasi: «*se quella PR è completa sì,
se no la completiamo e mergiamo*». Non «approvata». La condizione è stata
verificata prima del merge — stato `CLEAN`, tre check verdi e `Supabase Preview`
in `skipping` come nelle #33 e #34, e diff vuoto su tutti i percorsi di codice,
SQL, configurazione e workflow — e **una incompletezza è stata trovata e sanata
prima del merge**: la #36 non registrava il proprio numero, che è ciò che
`CLAUDE.md` impone come ultimo commit di ogni PR. La PR è poi stata mersa come
squash `271c7dc`, il 12 agosto 2026 alle 09:48:00 UTC.

> Perché registrare la forma condizionale e non solo l'esito: un'approvazione
> condizionata che viene archiviata come «approvato» insegna, a chi legge il
> registro più tardi, che le PR di questo progetto si mergiano su richiesta. Non è
> così, ed è il genere di erosione che la regola del «via libera esplicito per PR»
> esiste per impedire.

---

## 3. Inventario verificato sul progetto reale

Letto su `pijnmcllmfgjmgsvtcej` il 12 agosto 2026 con strumenti di **sola
lettura** — `list_migrations`, `list_edge_functions`, e interrogazioni a
`pg_catalog`, `information_schema` e `storage.buckets`. **Nessuna scrittura,
nessuna fixture, nessuna griglia.** Le affermazioni della commissione che ha
prodotto questo documento sono state riverificate una per una, e tre risultano
incomplete: sono corrette qui sotto.

### 3.1 Ledger e Edge Function — coerenti con la chiusura della Fase 10

**Venticinque migrazioni**, l'ultima `20260811160000 phase_10b_sommelier_storico`.
**Sei Edge Function `ACTIVE`**, tutte `verify_jwt=true`: `payments-checkout`
(v15), `connect-onboarding` (v14), `payouts-release` (v14), `ai-catalogo` (v1),
`ai-pairing` (v1), `ai-sommelier` (v1).

**Nessuna settima function esiste.** In particolare **`ai-sfondo` non esiste**,
né distribuita né nel repository (`supabase/functions/` contiene `_shared/`,
`ai-catalogo/`, `ai-pairing/`, `ai-sommelier/`, `connect-onboarding/`,
`payments-checkout/`, `payouts-release/`). La tabella della 7.6
(`271c7dc:1006-1011`) ne proponeva **quattro** — `ai-sommelier`, `ai-pairing`,
`ai-catalogo`, `ai-sfondo` — e il primo checkpoint ne ha scritte tre: la quarta è
lavoro di questa fase.

### 3.2 Storage — due bucket esistono già, e uno è pubblico

| Bucket | `public` | `file_size_limit` | `allowed_mime_types` | Creato |
| --- | --- | --- | --- | --- |
| `annunci` | **`true`** | `5242880` (5 MB) | `image/jpeg, image/png, image/webp, image/avif` | 2026-07-28 |
| `cantina` | `false` | `5242880` (5 MB) | idem | 2026-07-31 |

Definiti rispettivamente in
`supabase/migrations/20260729112500_listings_write.sql:467-468` e
`supabase/migrations/20260731120340_catalog_cellar_paths.sql:145-146`.

Le policy su `storage.objects` sono **per cartella dell'utente**: la prima
componente del percorso deve essere `auth.uid()::text`. `annunci` ha
`INSERT`/`UPDATE`/`DELETE` così vincolate e **nessuna policy di `SELECT`**, perché
il bucket è pubblico e la lettura passa dalla CDN senza RLS. `cantina` ha anche
la `SELECT`, con lo stesso vincolo.

> **Il fatto che pesa su tutta la sezione 6.1: `annunci` è pubblico.** Qualunque
> oggetto vi finisca è leggibile da chiunque conosca l'URL, per sempre e senza
> sessione. Una foto caricata **solo** per far compilare un modulo — che è
> esattamente il caso della 7.3a — finirebbe lì in modo permanente e pubblico se
> nessuno decide diversamente.

### 3.3 Il percorso di upload esiste già, ed è fatto bene

Questa è la prima correzione all'inventario noto: non c'è da inventare un
caricamento di fotografie, **c'è già e funziona**.

- `frontend-next/src/app/vendi/actions.ts:43-79` — `firmaUploadFoto`, una Server
  Action che verifica la sessione (`:53-56`), valida il MIME contro quattro tipi
  (`:30-35`, `:58-61`) e la dimensione contro 5 MB (`:38`, `:62-64`), **costruisce
  il percorso lato server** come `<uid>/<uuid>.<estensione>` (`:66`) e restituisce
  un token di upload firmato (`:69-71`). Il commento spiega perché il percorso non
  lo sceglie il client (`:12-16`) e che i limiti sono doppi di proposito: qui per
  dare un messaggio sensato, sul bucket perché è lì che vengono applicati davvero,
  anche a chi salta l'interfaccia (`:20-23`).
- `frontend-next/src/hooks/useSellWizard.ts:192-216` — il caricamento vero, con
  `uploadToSignedUrl`; il bucket è scelto dalla modalità del wizard (`:195`).
  `MAX_FOTO = 6` (`:69`).
- `frontend-next/src/services/cellar-service.ts:461-462` — le letture dal bucket
  privato passano da `createSignedUrls` a 3600 secondi.
- Costanti dei nomi: `BUCKET_CANTINA`
  (`frontend-next/src/services/cellar-service.ts:42`), `BUCKET_ANNUNCI`
  (`frontend-next/src/services/listing-service.ts:100`).

**Conseguenza per la sessione:** «limite di dimensione file» e «tipo MIME» non
sono domande vergini. Hanno già una risposta replicata in **tre punti che devono
restare allineati** — la configurazione del bucket, le costanti della Server
Action, e il commento che lo dichiara. Un terzo bucket ne aggiunge un quarto.

Nel legacy, invece, **non esiste nessun caricamento**: `frontend/src/routes/vendi.tsx:206`
mostra un toast «Caricamento foto (demo)». Anche qui `frontend-next` è già avanti.

### 3.4 Il debito dei file orfani esiste già, e la 7.3a lo rende strutturale

`frontend-next/src/hooks/useSellWizard.ts:219-229`, sul togliere una foto dal
wizard:

> «L'oggetto resta nel bucket: cancellarlo richiederebbe una scrittura aggiuntiva
> a ogni ripensamento, e un file mai referenziato da nessun annuncio non è
> raggiungibile se non da chi ne conosce già l'URL. La pulizia dei file orfani è
> manutenzione, non parte di questa fase.»

È una decisione consapevole e registrata, presa quando un orfano era il
sottoprodotto di un ripensamento. **La 7.3a lo cambia di natura**: una foto
caricata per ottenere l'autofill e poi non usata nell'annuncio non è un
ripensamento occasionale, è il caso normale. Il ragionamento «non è raggiungibile
se non da chi ne conosce l'URL» va inoltre riletto alla luce del 3.2: su
`annunci`, che è pubblico, quell'URL non richiede sessione.

### 3.5 Le due colonne mancano davvero — confermato per interrogazione diretta

`public.listings` ha 23 colonne e **nessuna somiglia a una spunta di completezza**:
`id, slug, seller_id, bottle_unit_id, stato, prezzo_cents, prezzo_mercato_cents,
condizione, conservazione, storia, degustazione, immagini, tag, published_at,
expires_at, stato_motivo, stato_aggiornato_da, stato_aggiornato_at, created_at,
updated_at, reserved_by, reserved_until, imballaggio_codice`.

`public.reports` ha 18 colonne e **nessuna somiglia a un esito di triage**.

Gli array di immagini esistono e sono `text[] not null default '{}'`:
`listings.immagini`, `bottle_units.immagini`, `reports.foto`.

**Entrambe le migrazioni ipotizzate sono quindi necessarie, non solo una.**

Un fatto che semplifica il lavoro e che va conosciuto prima di scrivere lo
schema: **nessuna delle due tabelle ha un `GRANT` di tabella intera verso un ruolo
client.** L'ACL di `listings` e di `reports` contiene solo `postgres` e
`service_role`; `listings` ha grant **per colonna** verso `authenticated`
(`SELECT` su 17 colonne, `INSERT` su 10, `UPDATE` su 8 — e `stato` è fra quelle
di sola lettura, perché ha già la sua porta `SECURITY DEFINER` dalla 6a), mentre
`reports` **non ne ha nessuno**. Una
colonna aggiunta domani non eredita niente: nasce **chiusa al client per
costruzione**, e la terza regola di esposizione è soddisfatta senza dover
restringere nulla. È il contrario del caso `profiles` della 9b, dove un `UPDATE`
di tabella intera avrebbe permesso a un sospeso di togliersi la sospensione.

Attenzione però al **percorso di lettura**, che è dove sta il lavoro vero: il
pannello legge da `public.moderation_report_queue`, una vista
`security_invoker=off, security_barrier=true` a **elenco di colonne chiuso**
(15 colonne, `SELECT` ad `authenticated`). Una colonna nuova su `reports`
**resta invisibile al pannello** finché una migrazione successiva non la aggiunge
esplicitamente alla vista. Lo stesso vale per `public.my_reports`, la proiezione
che il **segnalante** legge sulla propria segnalazione: 12 colonne chiuse, e
`priorita` è fra queste.

### 3.6 Il fatto che cambia la forma della 7.12: `reports.priorita` esiste già

Questa è la seconda correzione, ed è la più importante del documento. La 7.12
dice che l'AI «classifica e ordina». **La coda è già classificata e già ordinata**,
da una regola deterministica scritta nella Fase 9.

- La colonna: `reports.priorita`, tipo `public.report_priorita`, enum
  `('bassa', 'media', 'alta')`, `not null` **senza default**
  (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:59`,
  `:167-168`).
- La regola: `private.report_priorita_da_motivo(text)`, `immutable`, che fa
  `like any` su quattro radici per `alta` — `truff`, `frod`, `pagament`,
  `molest` — e quattro per `media` — `offens`, `falsa`, `veritier`, `ingannev` —
  con `bassa` come caso restante (`:405-420`). È il porto letterale di
  `priorityFromReason` in `frontend/src/data/moderation.ts:108-120`.
- Chi la scrive: **solo il server**, dentro `segnalazione_invia` (`:582`, `:599`).
  Il commento di colonna lo dichiara una **regola di dominio**, «non un valore che
  il client invia» (`:222-225`).
- L'ordinamento: esiste già un indice
  `reports_stato_priorita_idx on public.reports (stato, priorita desc, created_at desc)`
  (`:231-232`).
- La UI: il pannello disegna già il badge di priorità
  (`frontend-next/src/components/vinea/moderation/ModerationPanelClient.tsx:256`,
  con la mappa dei toni a `:81`).

Quella regola è **una funzione pura del solo `motivo`**, che a sua volta è
vincolato a un elenco chiuso di **21 valori** — verificato: `report_reasons` ha 21
righe, ripartite in `annuncio` 6, `profilo` 5, `messaggio` 4, `conversazione` 3,
`recensione` 3. Sono le 28 voci di `frontend/src/data/moderation.ts:35-61` meno le
4 di `post` e le 3 di `commento`, che la decisione 7.6a tiene fuori finché i club
non hanno uno schema. In pratica la priorità odierna è **una tabella di
consultazione a 21 ingressi**: ignora la `descrizione` scritta dal segnalante, le
`foto` allegate, il bersaglio e la storia di chi segnala.

**Questo non toglie valore al triage — lo rende preciso.** Ma sposta la domanda:
non è «dove mettiamo l'esito», è «l'esito convive con `priorita`, la sostituisce,
o è un'altra cosa». Sono tre schemi diversi e tre comportamenti diversi del
pannello. Va risolto in sessione, ed è la 6.4.

### 3.7 Un solo provider è implementato, e non è né Claude né Gemini

Terza correzione. La 7.1 sceglie «Claude o Gemini» per le foto, ma nel codice
distribuito esiste **una sola implementazione di provider**, ed è OpenAI:
`creaOpenAiProvider` (`supabase/functions/_shared/ai-provider.ts:131`) contro
`https://api.openai.com/v1/chat/completions` (`:97`), con `OPENAI_API_KEY`
(`:207`). L'unica alternativa presente è il provider disabilitato che risponde
503 (`:68`), gemello del `DisabledAIProvider` del legacy
(`backend/ai_provider.py:19-27`).

Il modulo è progettato per essere il punto unico da cambiare — lo dichiara il suo
stesso commento (`:12-14`) — e l'interfaccia `AiProvider` è minima:
`completeText` e `streamText` (`:46-50`), sul modello del `Protocol` del legacy
(`backend/ai_provider.py:14-16`). Ma nessuna delle due firme prende un'immagine, e
`creaAiProvider` accetta oggi tre soli compiti: `"chat" | "pairing" | "catalogo"`
(`:206`).

**Conseguenza per la sessione: scegliere Claude o Gemini per le foto non è
configurare una variabile, è scrivere un adapter** — più l'allargamento
dell'unione dei compiti e una firma che accetti un'immagine. È lavoro di
implementazione, non di configurazione, e va contato nell'effort.

I modelli sono già per compito (`AI_MODEL_CHAT`, `AI_MODEL_PAIRING`,
`AI_MODEL_CATALOGO`, con `AI_MODEL_DEFAULT` a `gpt-4.1-mini`, `:209-216`), quindi
lo schema delle variabili regge l'aggiunta senza cambiare forma.

### 3.8 PhotoRoom non esiste da nessuna parte

Verificato con `git grep` su tutto il repository a `271c7dc`: **PhotoRoom compare
soltanto in prosa** — `CLAUDE.md:389`, `CHANGES.log:13`,
`CONTESTO_IA/01_STATO_ATTUALE.md:1044`, `:1048`, e la spec della Fase 10. **Nessuna
variabile d'ambiente, nessun modulo, nessuna riga di codice, nessuna riga in
`docs/ENVIRONMENT.md`.** Nei tre `.env.example` non compare.

Per confronto, le variabili AI della Fase 10 sono già documentate e già negli
esempi: `docs/ENVIRONMENT.md:57-65` e `frontend-next/.env.example:41-60`.

### 3.9 Lo stato del limite di frequenza

`supabase/functions/_shared/ai-gate.ts` tiene i numeri **in un punto solo**:
`FINESTRA_SECONDI = 3600` (`:58`) e tre limiti (`:61-63`) — `ai:chat` **40**,
`ai:pairing` **15**, `ai:catalogo` **10**. Il tipo `AiScope` è un'unione chiusa di
tre stringhe (`:66`): **aggiungere uno scope è una modifica di tipo**, non un dato
di configurazione.

Il meccanismo sottostante non richiede migrazioni: `public.rate_limit_consume` è
in produzione dalla Fase 7 e concessa **al solo `service_role`**
(`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:157-160`),
quindi una Edge Function con client di servizio la consuma via `rpc()`.

La 7.4 aveva **proposto** due scope per questa fase — `ai:visione` e `ai:sfondo`,
entrambi a `10 / 3600 s` (`271c7dc:846-847`) — ma la riconferma numerica dell'11
agosto 2026 ha riguardato **solo i tre scope distribuiti**, e ha cambiato due
valori su tre (`:849-858`). I due scope delle foto portano quindi un numero
**ereditato da una proposta e mai verificato contro un uso reale**, per giunta
proprio il numero che la riconferma ha dovuto correggere altrove.

---

## 4. Pattern vincolanti da riusare, non da reinventare

| Cosa serve | Dove esiste già | Nota |
| --- | --- | --- |
| Porta di una Edge Function AI | `_shared/ai-gate.ts` (`apriPorta`) | Origine, metodo, `AI_ENABLED`, bearer, `auth.getUser`, bucket di frequenza |
| CORS delle sole function AI | `_shared/ai-cors.ts` | **Mai** `_shared/cors.ts` |
| Astrazione del fornitore | `_shared/ai-provider.ts` | Da estendere con la visione (3.7) |
| Identificativo opaco al fornitore | `requestIdOpaco` (`:59-60`) | Obbligatorio anche qui |
| Limite di frequenza server | `public.rate_limit_consume` | Nessuna migrazione necessaria |
| Upload firmato di una foto | `firmaUploadFoto` (`frontend-next/src/app/vendi/actions.ts:43`) | Percorso deciso dal server |
| Lettura privata di una foto | `createSignedUrls` (`frontend-next/src/services/cellar-service.ts:461`) | TTL 3600 s |
| Proiezione a colonne chiuse | `moderation_report_queue`, `my_reports` | `security_invoker=off` |
| Colonna con regola di dominio | `listings.stato`, `reports.priorita` | Fuori dal `GRANT`, porta `SECURITY DEFINER` |

`MIN_TESTS` in CI è a **255** (`.github/workflows/ci.yml:99`): va alzato
deliberatamente quando i test aumentano, come in ogni fase precedente.

---

## 5. Suddivisione proposta in sotto-fasi

**Proposta, non decisa.** La suddivisione non è una delle decisioni della sezione
6, ma non è nemmeno acquisita: la sessione può cambiarla. Fino al 12 agosto 2026
c'era un'ipotesi che la accorciava — se 7.3a e 7.3b fossero rimaste nella stessa
function e nello stesso momento, `11a` e `11b` sarebbero stati un checkpoint solo
— e **la 6.2 l'ha chiusa nel senso opposto**: due function distinte, quindi
`11a` e `11b` restano due.

| | Contenuto | SQL? | Che cosa serve prima |
| --- | --- | --- | --- |
| **11a** | Visione: una function propria che accetta un'immagine, autofill 7.3a. Nessuna colonna nuova | No | Adapter del provider di visione (3.7), prova 7.1, decisioni 6.1 residue e 6.5 |
| **11b** | Spunta 7.3b: **function propria** (6.2), colonna su `listings`, `SECURITY DEFINER`, esposizione | **Sì** | 11a, decisione 6.4 |
| **11c** | Sfondo 7.13: `ai-sfondo`, relay PhotoRoom, bucket degli sfondi curati, sostituzione del `setTimeout` | Probabile | Decisione 6.3, chiave PhotoRoom configurata |
| **11d** | Triage 7.12: classificatore, esito persistito, colonna nella vista di coda | **Sì** | Decisione 6.4, e il pannello della Fase 9 esercitato almeno una volta |

**Perché il triage è ultimo, e non per comodità.** Il pannello di moderazione
della Fase 9 esiste in produzione ma **nessun suo comportamento vi è mai stato
esercitato**: schema, grant e conteggi sono stati letti, non una transizione
eseguita. Aggiungere un classificatore che ordina una coda che nessuno ha ancora
visto funzionare è costruire sul non verificato. La stessa ragione che rendeva
`10f` ultima nella Fase 10 vale invariata.

**Perché la 7.3a viene prima della 7.3b.** Condividono la chiamata di visione per
decisione, ma la 7.3a non scrive niente e la 7.3b è una colonna con una regola di
dominio dietro. Fare prima quella reversibile è lo stesso criterio con cui la 10a
precedeva la 10b.

---

## 6. Decisioni — che cosa è chiuso e che cosa serve prima di qualunque codice

**Niente è risolto per default in questo documento.** Ciò che è chiuso porta la
data della sessione che l'ha chiuso; ciò che è aperto è marcato aperto anche
quando la risposta sembra ovvia. Dove è indicata una preferenza, è segnalata come
tale e resta una proposta.

**Nessun valore numerico è proposto.** Limiti, dimensioni, budget e finestre si
fissano in sessione: sotto sono elencati come domande, non come tabelle da
approvare.

| | Area | Stato |
| --- | --- | --- |
| **6.1** | Storage: bucket, ciclo di vita, dimensione, MIME | **Parzialmente chiusa** — bucket dedicato deciso il 12 agosto 2026; nome, pubblico/privato, ciclo di vita, dimensione e MIME **aperti** |
| **6.2** | Una Edge Function o due per 7.3a e 7.3b | **Chiusa** il 12 agosto 2026 — **due**, una porta per operazione |
| **6.3** | PhotoRoom: chiave, budget, modalità | **Aperta** — cinque punti, nessuno risolto |
| **6.4** | Le due migrazioni: forma, RLS, grant | **Aperta** — e la 6.4(b) è cambiata di natura dopo il 3.6 |
| **6.5** | Limite di frequenza e valori numerici | **Aperta** — elencata come domande, senza numeri proposti |
| **6.6** | La prova del provider fotografico | **Aperta** — chi, con quali foto, quando |

Due domande **nuove** sono nate dalle decisioni del 12 agosto e sono aperte anche
loro: se il bucket dedicato sia privato e come si chiami (6.1 a-bis). Una
decisione che ne apre altre non è una decisione mal presa — è il motivo per cui
questa sezione ha una tabella di stato invece di un elenco.

### 6.1 Storage: dove vivono le foto, e per quanto

**Parzialmente chiusa.** La prima delle quattro domande ha risposta dal 12 agosto
2026; le altre tre restano aperte, e con esse due domande **nuove** che la
risposta apre.

**(a) Bucket dedicato o riuso — CHIUSA (12 agosto 2026): bucket dedicato.**
Registrata al 2.4 con la motivazione originale. La tabella di ciò che è stato
pesato resta qui, perché sapere che cosa è stato scartato e perché vale più della
sola risposta — è la stessa convenzione della sezione 7 della spec Fase 10:

| Opzione | Implicazione | Esito |
| --- | --- | --- |
| **Riuso di `cantina`** (privato) | Zero migrazioni di bucket, policy già scritte, `firmaUploadFoto` già lo sa fare. Ma `cantina` significa oggi «la mia cantina»: metterci foto usa-e-getta ne cambia il significato, e le letture del wizard non le filtrano | Scartata |
| **Riuso di `annunci`** (pubblico) | Naturale se la foto diventa comunque quella dell'annuncio. **Ma è pubblico**: una foto caricata solo per l'autofill e poi scartata resta leggibile per sempre da chi ne conosce l'URL (3.2) | **Scartata, ed è questo il motivo registrato della decisione** |
| **Terzo bucket dedicato**, privato, es. `ai-input` | Semantica pulita, ciclo di vita proprio, e un unico posto da svuotare. Costa una migrazione con le sue policy, e **un quarto punto** in cui tenere allineati MIME e dimensione (3.3) | **SCELTA** |

**(a-bis) Due domande nuove, aperte, che la decisione apre e non chiude.**

- **Come si chiama.** Il nome è pubblico: compare negli URL e nei percorsi, e
  cambiarlo dopo significa migrare oggetti. `ai-input` è un segnaposto usato qui
  per parlarne, non una proposta.
- **Pubblico o privato.** Sono proprietà diverse da «dedicato», e la decisione ha
  chiuso solo la seconda. Il motivo che ha scartato `annunci` è un argomento
  forte perché il nuovo bucket sia **privato** — se il problema era la leggibilità
  perpetua da URL, un bucket dedicato ma pubblico la riproduce identica — ma
  resta da dire in sessione. Se privato, ogni lettura passa da un URL firmato con
  scadenza, e va deciso **chi lo firma e per quanto**: la function che inoltra a
  PhotoRoom ha bisogno di leggere l'oggetto, e con un bucket privato non basta
  passargli l'URL pubblico.

**(a-ter) Una conseguenza da mettere a bilancio.** Il bucket dedicato è la terza
riga della tabella, quindi ne eredita il costo: **un quarto punto in cui tenere
allineati MIME e dimensione** (3.3), oltre ai tre di oggi. Non è un argomento
contro la decisione — è la manutenzione che la decisione compra, e va scritta
adesso perché al momento del codice si vede solo se qualcuno l'ha scritta.

**(b) Ciclo di vita.** Che ne è di una foto caricata **solo** per compilare un
modulo? Il debito degli orfani è già accettato per il caso del ripensamento
(3.4), ma la 7.3a lo rende il caso normale. Opzioni: nessuna pulizia (coerente con
oggi, e con la 7.2 che ha scelto la stessa strada per le righe scadute dello
storico Sommelier); cancellazione esplicita quando il wizard si chiude senza
pubblicare; oppure un bucket dedicato che si possa svuotare in blocco. **Va
osservato che `pg_cron` resta escluso dalla decisione 1a della Fase 7d**, e che un
secondo job GitHub Actions è già stato scartato una volta nella 7.2 perché
aggiungerebbe uno scheduler a uno che è a 18 run falliti su 18.

**(c) Limite di dimensione.** Oggi 5 MB in tre punti allineati (3.3). Domande: 5
MB è giusto anche per un'immagine che viene **inoltrata a un terzo** e pagata a
chiamata? Serve un limite più basso lato client **prima** della compressione, e in
quel caso chi comprime — il browser o la function?

**(d) Tipi MIME.** In ingresso i quattro dei bucket. Ma **che cosa restituisce
PhotoRoom**, e in quale formato viene ripubblicato il risultato? Se restituisse un
formato fuori dai quattro, o l'`allowed_mime_types` cambia o la function converte.
**Da verificare sulla documentazione del fornitore prima di decidere**, non da
assumere.

### 6.2 Una Edge Function o due per 7.3a e 7.3b — CHIUSA (12 agosto 2026): due

**Chiusa: due Edge Function distinte**, sul pattern «una porta per operazione»
delle sette RPC della Fase 9 e delle tre function della Fase 10. Registrata al
2.4. La tensione che la rendeva una decisione resta utile da conoscere: la 7.3
dice che le due **condividono la chiamata di visione** e la tabella della 7.6
(`271c7dc:1010`) le metteva entrambe dentro `ai-catalogo`, mentre il principio
«una porta per operazione» della **stessa** 7.6 tirava dall'altra parte. La
decisione ha sciolto il conflitto a favore del principio.

| Opzione | A favore | Contro | Esito |
| --- | --- | --- | --- |
| **Entrambe in `ai-catalogo`** | È la lettera della tabella della 7.6; una sola chiamata al fornitore può produrre i due esiti insieme, e la visione è cara; un'unità di deploy e un cold start in meno | Un solo bucket di frequenza per due funzionalità con costi e cadenze diverse — **esattamente il difetto del bucket unico `ai:user:{id}` del legacy** che la 7.4 ha corretto. La funzione accumula tre input diversi (`ocr_text`, `hint`, immagine) e due forme di uscita | Scartata |
| **Due function distinte** | Un bucket per funzionalità senza forzature; una porta per operazione alla lettera; la 7.3b può avere un modello più economico della 7.3a | Se una sola chiamata di visione basta per entrambe, due function significano **due chiamate e doppio costo**, contro la lettera della 7.3 | **SCELTA** |
| **Una function, due bucket di frequenza** | Compromesso: un'unità di deploy, ma il costo resta separato per funzionalità | Un `action` implicito nel corpo — la forma che la 7.6 ha respinto | Scartata |

**Che cosa la decisione comporta, detto adesso.** Il contro della riga scelta è
accettato, non eliminato: **la tabella della 7.6 è superata su questo punto**, e
`ai-catalogo` non ospiterà la 7.3b. Restano due conseguenze da tenere in conto
quando si scriverà il codice, e nessuna delle due riapre la decisione.

- **Il costo doppio è possibile ma non certo, e dipende da una domanda ancora
  aperta:** la spunta 7.3b si calcola **alla pubblicazione** (7.3 dice «alla
  pubblicazione») o **durante il wizard**, insieme all'autofill? Se i due momenti
  sono diversi, non c'è nessuna chiamata da condividere e il contro sparisce da
  sé. Se sono lo stesso momento, il costo doppio è reale e va messo a bilancio
  nella 6.5. **Prima questa domanda decideva l'architettura; adesso ne misura il
  prezzo** — ed è per questo che resta aperta invece di chiudersi con la 6.2.
- **Due function significano due nomi, due `AI_ALLOWED_ORIGINS` da leggere con lo
  stesso modulo, due scope di frequenza e due voci in `docs/ENVIRONMENT.md`.**
  Non è nuovo lavoro di progetto: è il costo per funzionalità che la Fase 10 ha
  già pagato tre volte.

### 6.3 PhotoRoom: chiave, budget, e quale delle due modalità

**Aperta.** Il fornitore non è integrato in nessuna forma (3.8).

**(a) Dove vive la chiave, e dietro quale modulo.** Una parte è già vincolata e
non è in discussione: la chiave sta **nell'ambiente della Edge Function** — mai
nel repository, mai nel browser — con il vincolo di piattaforma che le variabili
non possono iniziare per `SUPABASE_`, e va aggiunta a `docs/ENVIRONMENT.md` e al
`.env.example` pertinente **nello stesso cambiamento che la introduce**. Quello
che è aperto è **la forma del modulo**, e la commissione proponeva «lo stesso
pattern di `ai-provider.ts`». È il punto da correggere prima di decidere:

| Opzione | Implicazione |
| --- | --- |
| **Dentro `_shared/ai-provider.ts`** | Nessun file nuovo. Ma PhotoRoom **non fa completamento di testo** e non entra nell'interfaccia `AiProvider`, che ha due sole firme, `completeText` e `streamText` (`supabase/functions/_shared/ai-provider.ts:46-50`). Entrarci significa allargare un'interfaccia per un fornitore che non ne condivide la semantica — e quel file è il punto unico di cambio per i modelli linguistici, non per i servizi di immagine |
| **Modulo proprio, sul pattern di `payment-provider.ts`** | È il precedente esistente per «un fornitore esterno che non è un LLM»: un modulo con la propria interfaccia e i propri tipi (`supabase/functions/_shared/payment-provider.ts:82`, `:139`, `:172` — tre interfacce distinte per tre capacità dello stesso fornitore). Un file nuovo, ma la separazione è quella che la 7.13 già dichiara quando dice che PhotoRoom **non passa dall'astrazione `AIProvider`** |
| **Nessuna astrazione: chiamata diretta dentro la function** | La più corta. Ma nessun punto unico da cambiare se il fornitore cambia, e il fallimento non ha una forma tipizzata — cioè il contrario di quello che le due astrazioni esistenti hanno comprato |

**La ragione per cui questa non è una scelta di stile.** La 7.13 dice già che
PhotoRoom non passa da `AIProvider`; la domanda vera è se meriti un'astrazione
**sua** o nessuna. Il precedente utile è che entrambe le astrazioni esistenti sono
nate quando un fornitore era **uno solo** — e sono servite quando è diventato più
d'uno.

**(b) L'impegno della 7.11 copre PhotoRoom?** La commissione chiedeva di
verificarlo. **La risposta letterale è sì, e va comunque riconfermata.** La 7.11
enumera fra le variabili necessarie «la chiave PhotoRoom (7.13)»
(`271c7dc:1293-1296`) e apre osservando che «i provider sono almeno tre, più
PhotoRoom (7.13). Non è una chiave, sono quattro» (`:1249`). Ma quella scadenza —
lunedì 18 agosto 2026 — era stata costruita come **precondizione di merge della
Fase 10**, e la Fase 10 è mersa **spenta** senza PhotoRoom. La funzionalità che
usa quella chiave non ha branch. **Domanda per la sessione:** la chiave PhotoRoom
resta agganciata al 18 agosto insieme alle altre, oppure prende una data propria
legata all'apertura di `11c`? Lasciarla implicitamente al 18 agosto significa
farla scadere senza che serva a niente — e «una scadenza che non scade non è una
scadenza» è la lezione che la 7.11 stessa trae dal caso 7g.

**(c) Cutout puro o compositing, e con quale criterio si sceglie.** La 7.13 ha
deciso **che il catalogo di sfondi è curato a mano** e che il compositing su
sfondo nativo è l'opzione tecnica preferita; non ha deciso **come si sceglie fra
le due modalità in ogni singola chiamata**. Tre criteri possibili, che sono tre
prodotti diversi:

| Criterio | Che cosa significa in interfaccia | Costo |
| --- | --- | --- |
| **Sceglie il venditore** | Vede il catalogo di sfondi, ne prende uno, oppure sceglie «solo ritaglio» (cutout su trasparenza o su fondo pieno) | Un passo in più nel wizard; il venditore deve capire una distinzione tecnica |
| **Sempre compositing, con uno sfondo di default** | Nessuna scelta da fare: la foto esce già impaginata | Un default che decide l'estetica del catalogo al posto del venditore, e nessuna via d'uscita se lo sfondo non gli piace |
| **Cutout sempre, sfondo solo se lo chiede** | Il ritaglio è il servizio; lo sfondo è un extra | Se il compositing è la parte che vale, la si nasconde dietro un'azione che pochi troveranno |

Restano due domande che nessuno dei tre criteri risolve da solo, e vanno risposte
insieme a esso:

- **Esiste un default**, e se sì quale? Un catalogo curato a mano ha un primo
  elemento, e il primo elemento diventa il default per omissione se nessuno lo
  decide.
- **Se il ritaglio riesce male, che cosa vede l'utente** — la foto originale
  intatta, un errore, o il risultato brutto con la possibilità di annullare? È la
  stessa domanda che la 7.5 ha già risposto per i fallimenti del provider AI
  (errore generico, mai il messaggio del fornitore), ma qui il fallimento è
  **silenzioso**: PhotoRoom risponde `200` con un'immagine sbagliata, non un 503.

**(d) Il budget.** PhotoRoom si paga a immagine. Vale il principio della 7.11 —
il tetto sta **sul conto del fornitore**, perché è l'unico che ferma anche una
chiave uscita — e vale il rifiuto della 7.4 a un secondo tetto nostro. Da
confermare che valga anche per un fornitore a consumo per immagine.

**(e) Un dato di un utente esce verso un terzo nuovo.** Non è un modello
linguistico e non è coperto da quanto già scritto sui fornitori AI. Da verificare
se serve una riga in `docs/SECURITY.md`.

### 6.4 Le due migrazioni: forma delle colonne, RLS e grant

**Aperta**, ed è la decisione con più conseguenze.

**(a) La spunta di completezza su `listings` — APERTA, tre forme possibili.**
Nessuna è preferita qui. La colonna non esiste: verificato per interrogazione
diretta al catalogo di produzione (3.5), `listings` non ha nulla che assomigli a
una spunta di completezza, quindi il disegno è interamente da fare e nessun
vincolo storico lo restringe.

| Forma | Implicazione |
| --- | --- |
| `boolean` | Semplice. Ma non distingue «verificata e incompleta» da «mai verificata», e il default `false` mente su entrambe |
| **`enum`** a tre valori (es. `non_verificata`, `incompleta`, `completa`) | Distingue i tre stati veri. Un tipo nuovo, e il vincolo della 7f: **castare esplicitamente ogni ramo di un `case`**, mai un letterale nudo |
| Punteggio `smallint` + soglia | Più informativo, ma espone all'utente un numero che l'AI non sa produrre in modo stabile, e la soglia diventa una regola di prodotto nascosta |

Domande che la forma non risolve da sola: la spunta **scade** quando il venditore
cambia le foto? Se sì, il ricalcolo è automatico (un trigger, e quindi una
chiamata AI dentro una transazione — da evitare) o esplicito? E che cosa mostra
`public_listings`, la vista pubblica a colonne chiuse: la spunta è visibile a un
compratore anonimo? Se sì è **una promessa del prodotto verso un estraneo**, ed è
lì che il vincolo di etichettatura della 7.3 conta davvero.

**(b) L'esito del triage.** La parte **decisa** è che l'esito è **persistito e non
ricalcolato a ogni apertura del pannello**
(`CONTESTO_IA/01_STATO_ATTUALE.md:1132-1135`, e la tabella riassuntiva della spec
Fase 10 a `271c7dc:50`). Restano aperte due cose, e la prima è quella scoperta
al 3.6.

*Nota per chi legge le fonti, e una correzione fatta.* Su `271c7dc` il **corpo**
di `§7.12` (`:761-766`) era rimasto alla formulazione precedente e diceva ancora
«va risolto prima della 10e», mentre la tabella di stato dello stesso documento
(`:50`) e il verbale (`CONTESTO_IA/01_STATO_ATTUALE.md:1132-1135`) lo registravano
già chiuso. Non era una decisione da riaprire, era una riga di prosa non
aggiornata — e **la stessa PR che porta questo documento la aggiorna**, perché una
frase falsa in una spec vigente non si segnala e si lascia: si corregge. È la sola
modifica che questa PR fa a un file diverso da questo.

**Prima domanda aperta — il rapporto con `priorita`, e non più «dove lo metto».**
Il verbale dice «colonna persistita su `reports` **(o su una tabella collegata)**»:
la persistenza è decisa, il posto no. Ma il 3.6 ha cambiato la domanda, e vale la
pena dire come, perché la formulazione che arriva dalla Fase 10 non è più quella
giusta.

Quando la 7.12 è stata decisa, «l'AI classifica e ordina la coda» suonava come una
capacità nuova su una coda che non ne aveva. **Non è così:** `reports.priorita`
esiste già, è un `enum` a tre valori scritto **solo dal server** dentro
`segnalazione_invia`, deriva da una **regola di dominio deterministica** — una
funzione `immutable` del solo `motivo`, su un elenco chiuso di 21 voci — e la coda
del moderatore è **già ordinata** su di essa, con il suo indice dedicato e il suo
badge nel pannello (3.6). Il triage AI quindi non arriva su un terreno vuoto:
arriva accanto a una classificazione che c'è, funziona ed è verificabile.

Da qui la domanda vera, che è **a tre vie e non a quattro opzioni**: l'esito del
triage **convive** con `priorita`, la **sostituisce**, o **non è la stessa cosa**?
Le quattro forme concrete sotto sono i modi di realizzare quelle tre risposte.

| Risposta | Forma concreta | Implicazione |
| --- | --- | --- |
| **Convive** | **Colonna nuova accanto a `priorita`** | Le due classificazioni si possono confrontare — utile per misurare se l'AI batte la regola a 21 ingressi. Ma il pannello deve decidere **su quale delle due ordinare**, e una coda non può avere due ordinamenti insieme. Serve un secondo indice. Il confronto è il vero guadagno, e va voluto: se nessuno lo guarderà mai, questa è la colonna in più che non serve |
| **Convive** | **Tabella collegata** (es. `report_triage`) | `reports` resta intatta; ci stanno anche punteggio, categoria, modello usato e data — cioè la tracciabilità di *quale* modello ha detto *cosa* e *quando*, che una colonna sola non porta. Costa una `JOIN` nella vista di coda e una tabella nuova con le sue policy |
| **Sostituisce** | **L'AI scrive `priorita`** | Nessuna colonna nuova, ordinamento e indice già pronti, pannello invariato: la più economica di tutte. **Ma `priorita` è una colonna con una regola di dominio dietro** (`:222-225`), e sovrascriverla rende la regola deterministica non più verificabile — non si distingue più una priorità dedotta dal motivo da una dedotta dal modello. E assomiglia molto a «l'AI decide», che la 7.12 vieta per nome |
| **Non è la stessa cosa** | **L'esito non è una priorità** | L'AI produce categoria, sintesi e segnali che la regola non può vedere — per esempio «più segnalazioni sullo stesso bersaglio», che nessuna funzione del solo `motivo` potrà mai dedurre. **Non compete con `priorita`**: elimina il conflitto alla radice e sfrutta l'unica cosa che l'AI sa fare e la regola no. Ma cambia che cosa la 7.12 promette al moderatore, e la promessa era «classifica e ordina» |

**Come conviene affrontarla in sessione.** Non partendo dallo schema, ma da una
domanda sola: *che cosa il moderatore non riesce a fare oggi con la coda ordinata
per `priorita`?* Se la risposta è «distinguere le segnalazioni gravi fra quelle
`alta`», la risposta giusta è probabilmente la convivenza. Se è «vedere che tre
segnalazioni diverse puntano allo stesso venditore», è la quarta riga. Se è
«niente, funziona», allora la 7.12 va ridimensionata prima di scrivere una
migrazione — ed è una conclusione legittima che questo documento non ha
l'autorità per trarre.

**Seconda domanda aperta — chi lo vede.** Una colonna su `reports` è invisibile
finché non entra in `moderation_report_queue` (3.5). E poiché `my_reports` è la
proiezione del **segnalante**, va deciso esplicitamente se l'esito del triage vi
compare. La proposta ovvia è **no** — la valutazione automatica di una
segnalazione è materiale di lavoro del moderatore — ma non è mai stata scritta, e
la 9a aveva già cura di tenere fuori dalle proiezioni raggiungibili dal segnalato
ciò che non le riguardava (`:218-221`).

**(c) Le categorie del triage.** La commissione chiedeva se valga il meccanismo di
`report_reasons` — fonte unica in `frontend/src/data/moderation.ts` più vincolo
referenziale in database, come dichiara il commento di tabella verificato in
produzione. Sono due casi diversi e vanno decisi separatamente: quell'elenco è il
**menu di un utente**, e deve coincidere con ciò che il database accetta; le
categorie del triage sarebbero **l'uscita di un modello**, che nessun menu mostra.
Opzioni: enum chiuso (il modello non può inventare, ma ogni categoria nuova è una
migrazione); tabella di riferimento con vincolo (elenco modificabile senza
migrazione, ma un'uscita fuori elenco va gestita); testo libero con validazione
solo applicativa (flessibile, e la coda si riempie di varianti). **Se si sceglie
un elenco chiuso, va deciso chi è la fonte** — il repository o il database.

**(d) Entrambe le colonne** vanno scritte da una `SECURITY DEFINER` come unica
porta, restano fuori dal `GRANT` e non sono mai scrivibili dal client. Questo è
già vincolato dalle tre regole di esposizione e **non è una decisione aperta**:
è un requisito. Aperta è solo la forma.

### 6.5 Limite di frequenza e valori numerici

**Aperta nei numeri, chiusa nella forma.** La forma la fissa la 7.4 e non si
riapre: **un bucket per funzionalità**, **finestra oraria**, **nessuna esenzione
per `admin`**, **nessun secondo tetto nostro** oltre al limite di frequenza per il
v0.

Con la 6.2 chiusa a **due function distinte**, il conto degli scope non è più
condizionale: **7.3a e 7.3b ne hanno uno ciascuna**. Le domande, in forma diretta
e senza numeri proposti:

1. **Quante chiamate all'ora per l'autofill 7.3a?**
2. **Quante per la spunta 7.3b?** Ha un bucket suo per costruzione, ora che è una
   function sua. E la cadenza d'uso è diversa: l'autofill si invoca mentre si
   compila, la spunta una volta per annuncio (o a ogni cambio di foto, se la 6.4a
   decide che scade).
3. **Quante per lo sfondo 7.13**, che è l'unica pagata **a immagine** a un
   fornitore esterno e quindi l'unica in cui un limite troppo alto si traduce
   direttamente in fattura?
4. **Quante per il triage 7.12 — e ne serve uno?** Il triage **non è chiamato da
   un browser**: se gira sul flusso di invio di una segnalazione, il limite che
   conta è già `report:submit` a `10 / 3600 s`
   (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524`), e un
   secondo bucket sullo stesso percorso sarebbe il «secondo tetto» che la 7.4 ha
   respinto. Se invece gira **su richiesta del moderatore**, allora è un percorso
   diverso e la domanda si riapre per intero.
5. **Come si chiamano gli scope.** La 7.4 proponeva `ai:visione` e `ai:sfondo`,
   ma `ai:visione` è nato quando 7.3a e 7.3b erano una cosa sola: con due
   function serve una risposta esplicita — due nomi per funzionalità (`ai:autofill`,
   `ai:completezza`) oppure uno condiviso, che però rifarebbe per la porta di
   servizio il bucket unico che la 6.2 ha appena separato.
6. **Dimensione massima del file per il nuovo bucket.** Oggi sono 5 MB in tre
   punti allineati (3.3), ma quel numero è nato per una foto che resta in
   piattaforma. Qui l'immagine viene **inoltrata a un terzo e pagata a chiamata**:
   il numero va confermato o cambiato per questo caso, non ereditato.
7. **Tetto mensile di spesa sul conto di ciascun fornitore: quale, e chi lo
   configura?** Vale il principio della 7.11 — il tetto sta sul conto del
   fornitore, non nel nostro codice — ma il valore e il responsabile non sono
   stati fissati per nessuno dei fornitori nuovi, PhotoRoom compreso.

Da tenere presente quando si scelgono i numeri: quelli della proposta 7.4 sono
`10 / 3600 s` per entrambi, mai verificati contro un uso reale (3.9), e il
precedente più recente è che la riconferma numerica **ha dovuto correggere due
valori su tre** perché `10 / 3600` si esauriva dentro una sola conversazione.
Un venditore che cataloga tre bottiglie in una sera scatta più di dieci foto.

### 6.6 La prova del provider fotografico

**Aperta.** La 7.1 la impone e non è stata fatta.

- **Chi la conduce.** Enrico è l'unica persona con accesso al progetto, e ha già
  la 7.11 sulle spalle. Il confronto fra due uscite su una foto vera non richiede
  però accesso al progetto: può essere fatto da chiunque, fuori da qualunque
  migrazione, e portato in sessione come risultato.
- **Con quali foto.** La 7.1 lo dice: vetro, curvatura, luce non perfetta, **non
  documenti puliti**. Da fissare quante e quali — proposta: sei foto reali di
  bottiglie della cantina di Enrico, comprese due volutamente difficili
  (riflesso, etichetta parzialmente coperta).
- **Con quale criterio.** Aperto, e serve prima di guardare le uscite. Proposta:
  quanti dei nove campi di `ai-catalogo`
  (`supabase/functions/ai-catalogo/index.ts:31-33`) sono corretti, e
  quante volte il modello **inventa** un campo che non poteva dedurre — che è
  l'errore peggiore, perché il `confidence` non lo cattura.
- **Prima o dopo la chiusura di questo documento.** Proposta: **prima di aprire
  `11a`, ma può avvenire dopo la sessione che chiude le altre decisioni.** È
  l'unica delle sei che non blocca le altre, perché nessuna dipende da quale
  fornitore vince — ma blocca il codice, esattamente come la 7.1 dichiara.

**Quello che la prova compra davvero, e che va detto prima di condurla.** La 7.1
per le foto non è una decisione di configurazione: è la scelta di **quale adapter
verrà scritto**. Nel codice distribuito esiste **una sola implementazione di
provider, ed è OpenAI** (3.7); l'interfaccia `AiProvider` ha due sole firme,
`completeText` e `streamText`, e **nessuna delle due prende un'immagine**
(`supabase/functions/_shared/ai-provider.ts:46-50`), mentre `creaAiProvider`
accetta oggi tre soli compiti (`:206`). Qualunque sia l'esito della prova, la fase
paga:

1. un **adapter nuovo** per il fornitore che vince — Claude o Gemini, entrambi da
   zero, nessuno dei due presente;
2. l'**allargamento dell'unione dei compiti**, che è tipizzata e chiusa;
3. una **firma che accetti un'immagine**, che oggi non esiste in nessuna delle due
   funzioni dell'interfaccia.

Nessuno dei tre è opzionale e nessuno dipende da chi vince: **è il costo fisso
della 7.1 applicata alle foto**, e va contato nell'effort prima della sessione, non
scoperto durante `11a`. È anche la ragione per cui la prova ha senso farla presto:
non cambia *se* si scrive un adapter, ma cambia *quale*, e riscriverne uno dopo
averlo scritto costa più che aspettare sei fotografie.

Ciò che invece **non** va rifatto: i modelli sono già per compito
(`AI_MODEL_CHAT`, `AI_MODEL_PAIRING`, `AI_MODEL_CATALOGO`, con
`AI_MODEL_DEFAULT`, `:209-216`), quindi lo schema delle variabili regge l'aggiunta
senza cambiare forma.

---

## 7. Effort e dipendenze

**Dipendenze esterne alla fase, che nessuna quantità di codice chiude:**

1. La configurazione di chiave e budget dei fornitori (7.11, 18 agosto 2026), e la
   risposta al 6.3(b) su PhotoRoom.
2. La prova su foto reali (6.6).
3. Il pannello di moderazione della Fase 9 **esercitato almeno una volta** su una
   sessione reale, prima di `11d`.

**Ordine di grandezza**, sapendo che l'adapter di visione è lavoro vero (3.7) e
non configurazione:

| Voce | Stima |
| --- | --- |
| Migrazioni | **Due** — spunta 7.3b su `listings`, esito del triage — **più una terza** per il bucket dedicato deciso al 2.4 e le sue policy, che prima era condizionale e adesso non lo è |
| Edge Function | **Tre nuove** dopo la 6.2: una per l'autofill 7.3a, **una per la spunta 7.3b** (che prima si sperava di ospitare in `ai-catalogo`), una per lo sfondo 7.13 — più il percorso del triage 7.12, la cui forma dipende dalla 6.5(4). Da tre distribuite si passa a sei o sette |
| Adapter di provider | **Almeno uno nuovo** (visione), **più uno** per PhotoRoom, che non passa da `AiProvider` |
| Superfici UI | Wizard `/vendi` (foto → autofill), badge di completezza sull'annuncio, `SfondoIAPanel` reale, pannello di moderazione |
| Griglie SQL | Una per migrazione, **da eseguire almeno una volta** prima di chiamarle prove |

**Il debito che questa fase eredita e deve chiudere.** La 7.13 ha tolto
`SfondoIAPanel` dalla lista di cutover per chiuderlo «in questa fase», ma la 7.13
è restata fuori dal checkpoint unico della Fase 10. Quella fase è ora la **11**:
fino ad allora `frontend/src/routes/vendi.tsx:569-579` continua a promettere uno
sfondo che è un `setTimeout` di 1100 ms e un toast «Sfondo applicato (demo)».
**Se la Fase 11 non lo chiude, il debito torna sulla lista di cutover della Fase
12** e non sparisce da solo.

---

## 8. Che cosa deve succedere prima che si apra un branch

1. Una sessione organizzativa che chiude **ciò che della sezione 6 resta aperto**,
   con la stessa disciplina della Fase 9 e della Fase 10: risposta registrata,
   proposta conservata dove le due divergono. Al 12 agosto 2026 restano aperte la
   **6.1 meno il punto (a)** — incluse le due domande nuove che la decisione sul
   bucket ha aperto — e per intero **6.3, 6.4, 6.5 e 6.6**. La 6.2 è chiusa.
2. Le risposte trascritte in `CONTESTO_IA/01_STATO_ATTUALE.md` e in questo
   documento, con data — come è stato fatto per le quattro del 12 agosto (2.4).
3. La prova della 6.6, se la sessione la mette prima del codice.
4. Solo allora `migration/phase-11-…`, un checkpoint per volta.

Applicare qualunque cosa al progetto reale — migrazione, function, configurazione
— resta **una conferma esplicita e distinta per perimetro**, data in sessione, e
non è coperta da un'autorizzazione precedente che nominava un perimetro diverso.
