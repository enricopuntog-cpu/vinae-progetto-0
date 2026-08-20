# Fase 11 — Estensioni AI ammesse per eccezione

> **Documento organizzativo. Nessuna riga di codice, nessuna migrazione.**
> La Fase 11 **non è iniziata e non ha branch**. Il branch `migration/phase-11-*`
> si apre **dopo** che le decisioni della sezione 6 sono chiuse in sessione con
> Enrico, sul modello dei 9a/9b/9c della Fase 9 e dei 10a/10b/10c della Fase 10 —
> non prima.
>
> **Aggiornamento del 12 agosto 2026, secondo tempo: la sezione 6 è chiusa per
> intero.** Tutte e sei le aree hanno una risposta registrata con data e
> motivazione (§2.5 per il verbale, §6 per il dettaglio). **Il branch resta
> comunque non aperto**, e non per prudenza: tutti e quattro i checkpoint della
> §5 sono bloccati da dipendenze esterne che nessuna quantità di codice chiude, e
> una di esse — la prova 6.6 **prima** di `11a` — è stata decisa in questa stessa
> sessione. Aprire `11a` adesso contraddirebbe una decisione presa un'ora prima.
>
> Le quattro funzionalità sono ammesse **per eccezione esplicita e per nome**
> dalle decisioni 7.3, 7.12 e 7.13 della Fase 10. «Niente funzionalità nuove
> durante la migrazione» **non è decaduta**: continua a valere per tutto ciò che
> una sessione non ha chiesto per nome.
>
> **Aggiornamento del 13 agosto 2026.** Due sezioni nuove, nessuna delle quali
> apre la fase: la **§9.5** registra le etichette di trasparenza IA aggiunte ai
> tre pannelli della **Fase 10** — codice vero, ma su superfici già mersate e
> fuori da questa fase — e la **§10** registra il copy e il flusso pronti per
> `11a` e `11c`, che restano bloccati. La §6 non è stata toccata.
>
> **Secondo passaggio dello stesso giorno: la §10.3 è chiusa.** I tre punti che
> il flusso dello sfondo lasciava aperti sono ora **decisioni di sessione** — il
> rullino si ferma a metà invece di rifiutare in partenza, `ai:sfondo` resta a
> **15/ora** finché non ci sono costi reali da guardare, e la conferma è
> **cumulativa con eccezioni**. Nessuna riapre la §6: la seconda **conferma** un
> valore della 6.5 e registra a quale condizione tornerà in sessione. La fase
> resta ferma dov'era.

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

**Rinumerazione del 16 agosto 2026 — la Fase 11 non si muove, il cutover sì.** Il
cutover **non è più la Fase 12: è la Fase 13**, perché la **Fase 12** è ora
Club/Community, che segue direttamente la Fase 11 nell'ordine di dipendenza. Le
due frasi qui sopra che dicono «Fase 12 cutover» **restano com'erano di
proposito**: la prima è il **titolo letterale del commit `271c7dc`**, che è un
record Git e non si riscrive, la seconda è il racconto di com'era fissata la
prima stesura. Sono resoconti, non l'indicazione del numero corrente. **Questa
rinumerazione non tocca il numero di questa fase, il suo perimetro né alcuna
delle sue decisioni**, e non sposta l'hash di riferimento: le righe restano
fissate su `271c7dc`, quindi ogni `file:riga` di questo documento va letto lì e
resta valido anche se i file citati cambiano su `main` dopo quella data.

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
| **7.3a** | Autofill dei campi catalogo da foto dell'etichetta | Decisione 7.3 | **Sì** — il bucket `foto-ai` e le sue policy (6.1) | Modello di visione (7.1) |
| **7.3b** | Spunta di completezza documentale sull'annuncio | Decisione 7.3 | **Sì** — un `enum` e una colonna su `listings` (6.4a) | Stesso della 7.3a |
| **7.12** | Triage di moderazione: classifica e ordina la coda | Decisione 7.12 | **Sì** — tabella `report_triage` (6.4b) | Livello più economico (7.1) |
| **7.13** | Ritaglio e sfondo reale al posto della demo | Decisione 7.13 | **Sì** — il bucket `sfondi` e le sue policy (6.3c) | **PhotoRoom**, non un LLM |

La colonna «SQL?» era a due `Sì` e due incerte nella prima stesura. Dopo le
decisioni del 12 agosto (secondo tempo) **sono quattro `Sì`**: ogni funzionalità
di questa fase porta una migrazione, e il conto della §7 si aggiorna di
conseguenza.

Sono le stesse che la Fase 10 aveva numerato **10d** (7.3a + 7.3b), **10e**
(7.13) e **10f** (7.12) nella sua sezione 6, e che il suo unico checkpoint ha
lasciato fuori. La ragione registrata allora vale ancora, ed è la ragione per cui
questo documento esiste: sono **meno specificate**, e ciascuna merita la propria
sessione di spec prima del codice.

### 1.2 Fuori perimetro, dichiarato

- **L'autonomia parziale del moderatore AI.** Rinviata esplicitamente dalla 7.12,
  non decisa: richiede una revisione legale (AI Act, in vigore dal 2 agosto 2026,
  e DSA sulle decisioni automatizzate) che nessuna fase di migrazione fa.
- **Il cutover**, che è la Fase 13.
- **Club/Community, che è la Fase 12** — non iniziata, senza branch, e con il
  proprio documento organizzativo non ancora scritto in questo repo.
- **Qualunque quinta funzionalità.** L'eccezione della 7.3/7.12/7.13 è nominativa.
  Se durante l'implementazione emerge che ne servirebbe un'altra, quello è un
  segnale di fermarsi e segnalare, non di costruirla.
- **La revisione legale della spunta 7.3b.** Il vincolo di etichettatura è già
  deciso (sezione 2.1); una validazione legale di come è formulata non è compito
  di questa fase.

> **La revisione legale resta fuori, ma non resta senza materiale.** La §9
> registra la **prima proposta** che questa fase le consegna — un'informativa su
> privacy e uso dell'IA alla registrazione — come proposta e non come chiusura.
> Il blocco che ne dipende non si sposta.

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

- **7.10 — il merge può innescare il deploy.** Non c'è un gate di autorizzazione
  separato per il deploy tecnico richiesto dal task. Le corse misurate
  **tre volte**, l'ultima il 12 agosto 2026 (§2.5), distribuirono migrazioni e
  ridistribuirono **tutte** le Edge Function, comprese quelle non toccate dalla
  PR: le tre function nuove della Fase 10 furono create 38 secondi dopo il merge,
  e tutte e sei ebbero lo stesso `updated_at` 43 secondi dopo; accadde di nuovo
  dopo la #37, di sola documentazione. Non è una garanzia per ogni merge: corsa
  e stato remoto vanno verificati. **Conseguenza operativa per questa fase:
  l'ambiente di una function si configura e si verifica prima del merge che può
  attivarla, mai dopo.**
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
  una volta.** La regola allora vigente richiedeva un'autorizzazione per ogni
  griglia; resta un fatto storico di questa specifica datata ed è sostituita
  dalla policy autonoma corrente di `CLAUDE.md`, con verifica obbligatoria di
  progetto/ref/ambiente, idoneità dell'ambiente, cleanup e residui.

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

### 2.5 Il secondo tempo del 12 agosto 2026 — la sezione 6 è chiusa per intero

La stessa giornata ha avuto due sessioni, come l'11 agosto ne aveva avute due per
la Fase 10. La prima ha chiuso le quattro decisioni del 2.4 leggendo la prima
stesura di questo documento; la seconda ha preso **tutte e sei le aree della
sezione 6**, una per una, nell'ordine in cui il documento le pone. Il dettaglio,
le tabelle di ciò che è stato pesato e le motivazioni stanno nella sezione 6; qui
c'è il verbale in forma breve, perché un elenco che si legge in un minuto è ciò
che serve fra tre mesi.

| | Area | Risposta |
| --- | --- | --- |
| **6.1** | Storage | Bucket **`foto-ai`**, **privato**, **nessuna pulizia**, **5 MB**, MIME **`image/jpeg`, `image/png`, `image/webp`** — senza `image/avif` |
| **6.2** | Function per 7.3a/7.3b | *(già chiusa al 2.4)* — due distinte |
| **6.3** | PhotoRoom | Modulo proprio sul pattern di `payment-provider.ts`; chiave con **data propria** legata all'apertura di `11c`; **sceglie il venditore** con «solo ritaglio» preselezionato; sfondi in un quarto bucket **pubblico `sfondi`**; anteprima con conferma esplicita; **riga in `docs/SECURITY.md`, punto EXIF compreso** |
| **6.4a** | Spunta di completezza | **`enum` a tre valori**; **scade** al cambio foto con **ricalcolo esplicito**; **visibile anche all'anonimo**; calcolata **alla pubblicazione** |
| **6.4b** | Esito del triage | **Convive** con `priorita`, in una **tabella collegata `report_triage`**; ordinamento `priorita` primario e triage **dentro il gruppo**; contenuto **punteggio + motivazione breve**; **non** esposto in `my_reports` |
| **6.5** | Numeri | `ai:autofill` **30/ora**, `ai:completezza` **10/ora**, `ai:sfondo` **15/ora**; triage **senza scope nuovo**; **5 MB invariato**; tetto mensile **fissato alla configurazione della chiave** |
| **6.6** | Prova del provider | **Enrico**, **sei foto** della sua cantina con due volutamente difficili, criterio **campi corretti su nove + campi inventati**, **prima di aprire `11a`** |
| **7.11** | Perimetro della scadenza | PhotoRoom **esce** dal 18 agosto 2026 |

**Tre motivazioni valgono più delle risposte, e sono riportate con le parole di
chi le ha date.** Sul tetto mensile: *«nessun consumo reale è mai stato osservato
per nessun fornitore AI in questo progetto, e un numero scelto senza dati sarebbe
esattamente il tipo di valore inventato che il resto della fase ha sempre
evitato»*. Sul criterio della prova: contare i campi corretti **e** i campi
inventati, perché il solo conteggio dei corretti *«premia un modello che riempie
tutti e nove i campi tirando a indovinare rispetto a uno che ne lascia quattro
onestamente vuoti»*. Sul percorso del triage, che è la ragione per cui
`segnalazione_invia` non viene toccata: *«l'opzione 2 lega l'invio di una
segnalazione — un'azione critica già esistente — alla riuscita di una chiamata a
un fornitore esterno. È il contrario del principio che regge tutta questa fase:
`AI_ENABLED` fallisce chiuso proprio perché una funzionalità AI non deve mai
diventare un blocco per qualcosa che già funziona»*.

**Due domande che la sezione 6 non poneva sono state poste e chiuse lo stesso**,
perché sono emerse dalle risposte e lasciarle implicite sarebbe stato inventarle
dopo: **dove vivono gli sfondi curati a mano** della 7.13 (§6.3c), che la sezione
5 nominava di sfuggita e la sezione 6 non chiedeva; e **da dove parte la
chiamata al triage** ora che è un percorso proprio (§6.4b).

#### La 7.10 misurata una terza volta, sulla #37

`list_edge_functions` su `pijnmcllmfgjmgsvtcej`, letto il 12 agosto 2026 dopo il
merge della **#37** — che è **sola documentazione**, quattro file di prosa e
nessuna riga di function:

| | Versione all'11 agosto | Versione dopo la #37 |
| --- | --- | --- |
| `payments-checkout` | 15 | **17** |
| `connect-onboarding` | 14 | **16** |
| `payouts-release` | 14 | **16** |
| `ai-catalogo`, `ai-pairing`, `ai-sommelier` | 1 | **3** |

Tutte e sei condividono un `updated_at` di `2026-08-12T13:28:54Z`, **43 secondi
dopo** il merge della #37 (13:28:11 UTC) — lo stesso scarto misurato la volta
precedente. Non è una curiosità: è la 7.10 confermata per la terza volta su una
PR che non tocca nemmeno un file di function, e con essa il vincolo operativo di
questa fase. **L'ambiente di una Edge Function si configura prima del merge**, e
una chiave che manca al momento del merge non è un ritardo recuperabile dopo: è
una function che comincia a rispondere entro un minuto con l'ambiente che trova.

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

> **Le versioni sono quelle lette prima del merge della #37 e non lo sono più.**
> Dopo quel merge sono 17 / 16 / 16 e 3 / 3 / 3, misurate lo stesso giorno: il
> dettaglio e ciò che dimostra stanno al §2.5. Il ledger e l'elenco delle
> function, invece, non sono cambiati — le migrazioni restano venticinque e le
> function restano sei.

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

Con la sezione 6 chiusa, la colonna «SQL?» non ha più incertezze e la colonna
«che cosa serve prima» non contiene più decisioni da prendere, **solo dipendenze
esterne**:

| | Contenuto | SQL? | Che cosa serve prima |
| --- | --- | --- | --- |
| **11a** | Visione: `ai-autofill`, una function propria che accetta un'immagine, autofill 7.3a. Bucket **`foto-ai`** e le sue policy | **Sì** — bucket e policy | **Prova 6.6 eseguita** (che a sua volta richiede le chiavi della 7.11), e l'adapter di visione da scrivere (3.7) |
| **11b** | Spunta 7.3b: `ai-completezza` (6.2), `enum` e colonna su `listings`, `SECURITY DEFINER`, esposizione in `public_listings` | **Sì** | `11a` |
| **11c** | Sfondo 7.13: `ai-sfondo`, relay PhotoRoom, bucket **`sfondi`**, sostituzione del `setTimeout` di `SfondoIAPanel` | **Sì** — bucket e policy | **Chiave PhotoRoom configurata** — che per la 6.3(b) ha una data legata all'apertura di questo stesso checkpoint |
| **11d** | Triage 7.12: `ai-triage`, tabella `report_triage`, `JOIN` e ordinamento nella vista di coda | **Sì** | Il pannello della Fase 9 **esercitato almeno una volta** su una sessione reale |

> **Nessuno dei quattro è apribile al 12 agosto 2026, e non per prudenza.**
> `11a` è bloccato dalla prova 6.6, che questa stessa sessione ha messo **prima**
> del codice e che non è eseguibile finché non esistono le chiavi (7.11, scadenza
> 18 agosto 2026); `11b` da `11a`; `11c` da una chiave la cui data è per
> definizione l'apertura di `11c`; `11d` dal pannello della Fase 9, di cui su
> `pijnmcllmfgjmgsvtcej` sono stati letti schema, grant e conteggi ma **nessun
> comportamento è mai stato esercitato**. Aprire un branch adesso significherebbe
> contraddire una decisione presa lo stesso giorno.

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
data della sessione che l'ha chiuso; ciò che era aperto era marcato aperto anche
quando la risposta sembrava ovvia. Dove era indicata una preferenza, era segnalata
come tale e restava una proposta.

**Nessun valore numerico era proposto** nella prima stesura: limiti, dimensioni,
budget e finestre erano elencati come domande, non come tabelle da approvare, e
sono stati fissati in sessione. Le domande restano scritte sotto le risposte,
perché una risposta senza la domanda che l'ha prodotta non si può rileggere.

**Stato al 12 agosto 2026, secondo tempo: tutte le aree sono chiuse.**

| | Area | Stato |
| --- | --- | --- |
| **6.1** | Storage: bucket, ciclo di vita, dimensione, MIME | **Chiusa** — dedicato (primo tempo) + `foto-ai`, privato, nessuna pulizia, 5 MB, tre MIME (secondo tempo) |
| **6.2** | Una Edge Function o due per 7.3a e 7.3b | **Chiusa** — **due**, una porta per operazione |
| **6.3** | PhotoRoom: chiave, budget, modalità | **Chiusa** — cinque punti più due che la sezione non poneva |
| **6.4** | Le due migrazioni: forma, RLS, grant | **Chiusa** — `enum` a tre valori; convivenza in `report_triage` |
| **6.5** | Limite di frequenza e valori numerici | **Chiusa** — tre scope con tre numeri, nessuno ereditato |
| **6.6** | La prova del provider fotografico | **Chiusa** — Enrico, sei foto, criterio a due conteggi, prima di `11a` |
| **6.7** | *(nuova)* Il guardiano di `ai-triage` | **Chiusa** — derivata dalla 6.4b, con enforcement esplicito |

Le due domande **nuove** che le decisioni del primo tempo avevano aperto — nome
e visibilità del bucket (6.1 a-bis) — sono chiuse dal secondo tempo. Il secondo
tempo ne ha aperte altre due, e le ha chiuse nella stessa sessione: dove vivono
gli sfondi curati (6.3c) e da dove parte la chiamata al triage (6.4b). **Una
decisione che ne apre altre non è una decisione mal presa** — è il motivo per cui
questa sezione ha una tabella di stato invece di un elenco.

### 6.1 Storage: dove vivono le foto, e per quanto — CHIUSA (12 agosto 2026)

**Chiusa in due tempi nella stessa giornata.** Il primo tempo ha risposto alla
domanda (a) — bucket dedicato — e ne ha aperte due nuove; il secondo tempo ha
chiuso quelle due e le restanti (b), (c), (d).

**Il risultato, in una riga:** bucket **`foto-ai`**, **privato**, **nessuna
pulizia**, **5 MB**, MIME `image/jpeg`, `image/png`, `image/webp`.

**(a) Bucket dedicato o riuso — CHIUSA (12 agosto 2026): bucket dedicato.**
Registrata al 2.4 con la motivazione originale. La tabella di ciò che è stato
pesato resta qui, perché sapere che cosa è stato scartato e perché vale più della
sola risposta — è la stessa convenzione della sezione 7 della spec Fase 10:

| Opzione | Implicazione | Esito |
| --- | --- | --- |
| **Riuso di `cantina`** (privato) | Zero migrazioni di bucket, policy già scritte, `firmaUploadFoto` già lo sa fare. Ma `cantina` significa oggi «la mia cantina»: metterci foto usa-e-getta ne cambia il significato, e le letture del wizard non le filtrano | Scartata |
| **Riuso di `annunci`** (pubblico) | Naturale se la foto diventa comunque quella dell'annuncio. **Ma è pubblico**: una foto caricata solo per l'autofill e poi scartata resta leggibile per sempre da chi ne conosce l'URL (3.2) | **Scartata, ed è questo il motivo registrato della decisione** |
| **Terzo bucket dedicato**, privato, es. `ai-input` | Semantica pulita, ciclo di vita proprio, e un unico posto da svuotare. Costa una migrazione con le sue policy, e **un quarto punto** in cui tenere allineati MIME e dimensione (3.3) | **SCELTA** |

**(a-bis) Le due domande nuove — CHIUSE (12 agosto 2026, secondo tempo).**

- **Come si chiama: `foto-ai`.** Non `ai-input`, che era il segnaposto usato per
  parlarne. Il nome è pubblico — compare negli URL e nei percorsi, e cambiarlo
  dopo significa migrare oggetti — quindi è stato scelto per dire che cosa
  contiene, non da dove viene. Sta accanto ad `annunci` e `cantina`, che sono
  nomi di dominio in italiano e non sigle tecniche.
- **Pubblico o privato: privato.** È la risposta che chiude davvero il problema
  per cui `annunci` era stato scartato. Un bucket dedicato ma pubblico avrebbe
  riprodotto identica la leggibilità perpetua da URL: la decisione (a) sceglieva
  *dove*, questa sceglie *se qualcuno può leggerlo*, e senza la seconda la prima
  non serviva a niente. **Da qui discende la risposta al ciclo di vita (b)**: se
  l'oggetto non è raggiungibile senza una firma, un orfano è inerte, e la pulizia
  smette di essere un requisito di riservatezza per diventare solo igiene di
  spazio.
- **Conseguenza operativa: chi firma la lettura, e per quanto.** Con un bucket
  privato la function che inoltra a PhotoRoom non può ricevere un URL pubblico.
  La risposta arriva dalla 6.3(e) e non è una firma: **la function scarica i byte
  e li inoltra come `imageFile`**, perché deve comunque spogliare i metadati EXIF
  prima di mandarli a un terzo, e togliere metadati significa riscrivere il file.
  Un URL firmato non sarebbe bastato in nessun caso. **Il bucket privato quindi
  non costa niente in più** rispetto a uno pubblico: il percorso di lettura della
  function è lo stesso.

**(a-ter) Una conseguenza da mettere a bilancio.** Il bucket dedicato è la terza
riga della tabella, quindi ne eredita il costo: **un quarto punto in cui tenere
allineati MIME e dimensione** (3.3), oltre ai tre di oggi. Non è un argomento
contro la decisione — è la manutenzione che la decisione compra, e va scritta
adesso perché al momento del codice si vede solo se qualcuno l'ha scritta.

**(b) Ciclo di vita — CHIUSA: nessuna pulizia.** Le opzioni pesate erano tre:
nessuna pulizia (coerente con oggi, e con la 7.2 che ha scelto la stessa strada
per le righe scadute dello storico Sommelier); cancellazione esplicita quando il
wizard si chiude senza pubblicare; svuotamento in blocco del bucket dedicato.

La scelta è la prima, e **la ragione non è l'inerzia: è che la privatezza del
bucket ha già chiuso il problema che la pulizia doveva chiudere.** Il debito degli
orfani era accettato al 3.4 con l'argomento «un file mai referenziato non è
raggiungibile se non da chi ne conosce già l'URL» — argomento che il 3.2 indeboliva
per `annunci`, che è pubblico. Su `foto-ai`, che è privato, l'argomento torna
valido nella sua forma forte: **senza firma non è raggiungibile da nessuno**. Ciò
che resta è consumo di spazio, che è manutenzione e non riservatezza.

Vale anche il vincolo di contesto che il documento registrava: `pg_cron` resta
escluso dalla decisione 1a della Fase 7d, e un secondo job GitHub Actions è già
stato scartato una volta nella 7.2 perché aggiungerebbe uno scheduler a uno che è
a 18 run falliti su 18. **Una pulizia periodica non aveva quindi neppure un
meccanismo disponibile** senza riaprire una decisione di un'altra fase.

> **Da scrivere, non da lasciare implicito** — stessa disciplina del TTL dello
> storico Sommelier, dove «le righe scadute restano a tabella» è finita nel
> commento di tabella, nella migrazione e in un caso di griglia: **`foto-ai`
> accumula oggetti orfani per costruzione, e nel v0 nessuno li rimuove.** Va
> detto nel commento del bucket e nella migrazione che lo crea. Il costo è
> monetario e cresce con l'uso; la riservatezza no.

**(c) Limite di dimensione — CHIUSA: 5 MB, invariato.** È il numero già in vigore
nei tre punti allineati del 3.3, e questa è la scelta di **non** cambiarlo per il
caso nuovo. La domanda era legittima — un'immagine inoltrata a un terzo e pagata
a chiamata non è la stessa cosa di una che resta in piattaforma — ma abbassare il
limite qui avrebbe prodotto la situazione peggiore: **una foto accettata dal
wizard e rifiutata dall'autofill**, cioè due soglie diverse che l'utente non può
distinguere. Il costo per chiamata si governa con il limite di frequenza (6.5),
che è lo strumento previsto, non con la dimensione del file.

Conseguenza già a bilancio dal 6.1(a-ter): **`foto-ai` è il quarto punto** in cui
i 5 MB vanno tenuti allineati. Sono quattro perché il numero è lo stesso; sarebbero
stati quattro **e divergenti** se fosse cambiato.

**(d) Tipi MIME — CHIUSA: `image/jpeg`, `image/png`, `image/webp`.** Tre, non i
quattro dei bucket esistenti: **`image/avif` esce**, ed è l'unica divergenza
deliberata di `foto-ai` dai bucket che lo precedono.

Il motivo è un fatto verificato sulla documentazione del fornitore, non una
preferenza — che è esattamente ciò che il punto (d) chiedeva prima di decidere:
**PhotoRoom non accetta AVIF in ingresso.** Accetta PNG, JPEG e WEBP (più HEIC
sulla sola rimozione dello sfondo), e AVIF compare **solo in uscita**, fra i
formati di `export.format`. Ammettere AVIF nel bucket avrebbe quindi significato
accettare un file che la 7.13 non può lavorare, e scoprirlo alla prima chiamata
invece che alla configurazione.

Ne segue la risposta all'altra metà della domanda — che cosa si ripubblica: il
risultato di PhotoRoom torna in un formato **scelto da noi** via `export.format`,
quindi non c'è nessun formato imprevisto da accogliere. Si sceglie fra i tre
ammessi e l'`allowed_mime_types` non deve inseguire il fornitore.

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

- **Il costo doppio non c'è, ed è la 6.4a ad averlo escluso.** La domanda era se
  la spunta 7.3b si calcolasse **alla pubblicazione** o **durante il wizard**,
  insieme all'autofill: momenti diversi significano nessuna chiamata da
  condividere e quindi nessun costo doppio; stesso momento significa costo doppio
  reale, da mettere a bilancio nella 6.5. **La 6.4a ha risposto «alla
  pubblicazione»**, quindi i momenti sono diversi e il contro della riga scelta
  sparisce da sé. Restava aperta perché «prima questa domanda decideva
  l'architettura, adesso ne misura il prezzo»: il prezzo misurato è **zero**.
- **Due function significano due nomi, due `AI_ALLOWED_ORIGINS` da leggere con lo
  stesso modulo, due scope di frequenza e due voci in `docs/ENVIRONMENT.md`.**
  Non è nuovo lavoro di progetto: è il costo per funzionalità che la Fase 10 ha
  già pagato tre volte.

### 6.3 PhotoRoom: chiave, budget, e quale delle due modalità — CHIUSA (12 agosto 2026)

**Chiusa in tutti e cinque i punti, più uno che la sezione non poneva** (6.3c-bis:
dove vivono gli sfondi curati a mano). Il fornitore resta non integrato in nessuna
forma (3.8): queste sono decisioni su come lo si integrerà.

**(a) Dove vive la chiave, e dietro quale modulo — CHIUSA: modulo proprio, sul
pattern di `payment-provider.ts`.** La seconda riga della tabella qui sotto. È il
precedente esistente per «un fornitore esterno che non è un LLM», ed è la forma
coerente con ciò che la 7.13 già dichiarava — PhotoRoom **non passa
dall'astrazione `AIProvider`**. La commissione che ha prodotto la prima stesura
proponeva «lo stesso pattern di `ai-provider.ts`»: era la proposta sbagliata, per
il motivo scritto nella prima riga, e la decisione l'ha corretta.

**(a) Le opzioni pesate.** Una parte era già vincolata e
non è in discussione: la chiave sta **nell'ambiente della Edge Function** — mai
nel repository, mai nel browser — con il vincolo di piattaforma che le variabili
non possono iniziare per `SUPABASE_`, e va aggiunta a `docs/ENVIRONMENT.md` e al
`.env.example` pertinente **nello stesso cambiamento che la introduce**. Ciò che
era aperto è **la forma del modulo**:

| Opzione | Implicazione | Esito |
| --- | --- | --- |
| **Dentro `_shared/ai-provider.ts`** | Nessun file nuovo. Ma PhotoRoom **non fa completamento di testo** e non entra nell'interfaccia `AiProvider`, che ha due sole firme, `completeText` e `streamText` (`supabase/functions/_shared/ai-provider.ts:46-50`). Entrarci significa allargare un'interfaccia per un fornitore che non ne condivide la semantica — e quel file è il punto unico di cambio per i modelli linguistici, non per i servizi di immagine | Scartata |
| **Modulo proprio, sul pattern di `payment-provider.ts`** | È il precedente esistente per «un fornitore esterno che non è un LLM»: un modulo con la propria interfaccia e i propri tipi (`supabase/functions/_shared/payment-provider.ts:82`, `:139`, `:172` — tre interfacce distinte per tre capacità dello stesso fornitore). Un file nuovo, ma la separazione è quella che la 7.13 già dichiara quando dice che PhotoRoom **non passa dall'astrazione `AIProvider`** | **SCELTA** |
| **Nessuna astrazione: chiamata diretta dentro la function** | La più corta. Ma nessun punto unico da cambiare se il fornitore cambia, e il fallimento non ha una forma tipizzata — cioè il contrario di quello che le due astrazioni esistenti hanno comprato | Scartata |

**La ragione per cui questa non era una scelta di stile.** La 7.13 dice già che
PhotoRoom non passa da `AIProvider`; la domanda vera era se meritasse
un'astrazione **sua** o nessuna. Il precedente utile è che entrambe le astrazioni
esistenti sono nate quando un fornitore era **uno solo** — e sono servite quando è
diventato più d'uno.

**(b) L'impegno della 7.11 copre PhotoRoom? — CHIUSA: no, PhotoRoom esce dal 18
agosto e prende una data propria, legata all'apertura di `11c`.**

La risposta letterale della 7.11 era sì: enumera fra le variabili necessarie «la
chiave PhotoRoom (7.13)» (`271c7dc:1293-1296`) e apre osservando che «i provider
sono almeno tre, più PhotoRoom (7.13). Non è una chiave, sono quattro» (`:1249`).
La decisione **la corregge deliberatamente**, e per la ragione che la 7.11 stessa
enuncia: quella scadenza era stata costruita come **precondizione di merge della
Fase 10**, e la Fase 10 è mersa **spenta** senza PhotoRoom. La funzionalità che usa
quella chiave non ha branch e non lo avrà finché `11c` non si apre. Lasciarla
implicitamente al 18 agosto significava **farla scadere senza che servisse a
niente** — cioè fabbricare esattamente la scadenza inerte che il caso 7g ha già
insegnato a riconoscere: *«una scadenza che non scade non è una scadenza»*.

Il 18 agosto resta quindi la data delle **chiavi dei modelli linguistici** (7.11
al netto di PhotoRoom). La chiave PhotoRoom è una **precondizione di apertura di
`11c`**, il che significa che `11c` non si apre senza, e che nessuna data
calendariale la governa prima di allora.

**(c) Cutout puro o compositing — CHIUSA: sceglie il venditore, con «solo
ritaglio» preselezionato.** La 7.13 aveva deciso che il catalogo di sfondi è
curato a mano e che il compositing su sfondo nativo è l'opzione tecnica preferita;
non aveva deciso **come si sceglie fra le due modalità in ogni singola chiamata**.

| Criterio | Che cosa significa in interfaccia | Costo | Esito |
| --- | --- | --- | --- |
| **Sceglie il venditore** | Vede il catalogo di sfondi, ne prende uno, oppure sceglie «solo ritaglio» (cutout su trasparenza o su fondo pieno) | Un passo in più nel wizard; il venditore deve capire una distinzione tecnica | **SCELTA** |
| **Sempre compositing, con uno sfondo di default** | Nessuna scelta da fare: la foto esce già impaginata | Un default che decide l'estetica del catalogo al posto del venditore, e nessuna via d'uscita se lo sfondo non gli piace | Scartata |
| **Cutout sempre, sfondo solo se lo chiede** | Il ritaglio è il servizio; lo sfondo è un extra | Se il compositing è la parte che vale, la si nasconde dietro un'azione che pochi troveranno | Scartata |

Le due domande che nessuno dei tre criteri risolveva da solo, chiuse insieme a
esso:

- **Il default è «solo ritaglio», non il primo sfondo del catalogo.** La domanda
  era reale: un catalogo curato a mano ha un primo elemento, e quel primo elemento
  diventa il default per omissione se nessuno decide. La scelta è l'opzione che
  non impagina niente al posto del venditore — **ed è anche l'opzione che costa
  meno**, il che qui non è una coincidenza ma un fatto misurato sul listino del
  fornitore: **una chiamata di *Image Editing* vale cinque chiamate di *Remove
  Background*.** Un default di compositing avrebbe quintuplicato il costo di ogni
  foto per una scelta che nessuno ha fatto.
- **Se il ritaglio riesce male, l'utente vede un'anteprima e conferma
  esplicitamente.** Il risultato non sostituisce la foto finché il venditore non
  lo accetta. È la risposta al caso che la 7.5 non copre: la 7.5 risolve il
  fallimento **dichiarato** del provider (503, 502, errore generico e mai il
  messaggio del fornitore), ma qui il fallimento è **silenzioso** — PhotoRoom
  risponde `200` con un'immagine sbagliata. Nessun codice di stato lo intercetta,
  e l'unico giudice disponibile è l'occhio di chi ha scattato la foto. **Ne segue
  un vincolo di implementazione**: la foto originale non viene mai sovrascritta
  dalla risposta del fornitore.

**(c-bis) Dove vivono gli sfondi curati — CHIUSA: un quarto bucket, `sfondi`,
pubblico.** Questa domanda **la sezione 6 non la poneva**: la §5 nominava «bucket
degli sfondi curati» in una riga di tabella e nessuna decisione lo copriva. È
stata posta e chiusa perché lasciarla implicita avrebbe significato inventarla
durante `11c`.

Pubblico, e per una ragione opposta a quella di `foto-ai`: **un catalogo di sfondi
è materiale editoriale della piattaforma, non un dato di un utente.** Non c'è
niente da proteggere, ogni venditore deve poterlo sfogliare, e servirlo dalla CDN
senza RLS è ciò che `annunci` già fa bene. Le policy di scrittura non seguono il
pattern «cartella dell'utente» degli altri tre bucket, perché **nessun utente ci
scrive**: li carica Enrico una volta, come dice la 7.13.

Conta per il conto delle migrazioni: **i bucket nuovi di questa fase sono due**,
non uno — `foto-ai` in `11a` e `sfondi` in `11c` — e ciascuno sta nel checkpoint
che lo usa.

**(d) Il budget — CHIUSA: tetto sul conto del fornitore, valore fissato al momento
in cui si configura la chiave.** Vale il principio della 7.11 — il tetto sta sul
conto del fornitore, perché è l'unico che ferma anche una chiave uscita — e vale
il rifiuto della 7.4 a un secondo tetto nostro; la conferma richiesta era che
valesse anche per un fornitore a consumo per immagine, e vale.

Ciò che la decisione aggiunge, ed è la parte che merita di sopravvivere, è
**perché il numero non viene fissato adesso**, con le parole di chi ha deciso:
*«nessun consumo reale è mai stato osservato per nessun fornitore AI in questo
progetto, e un numero scelto senza dati sarebbe esattamente il tipo di valore
inventato che il resto della fase ha sempre evitato»*. Il tetto si fissa quando si
configura la chiave, che è il momento in cui esiste un pannello del fornitore
davanti a chi lo decide. **Vale per tutti i fornitori nuovi, PhotoRoom compreso.**

**(e) Un dato di un utente esce verso un terzo nuovo — CHIUSA: sì, serve una riga
in `docs/SECURITY.md`, e include il punto EXIF.** I metadati vanno **spogliati
prima dell'inoltro a un terzo**.

Il punto EXIF non era nella domanda ed è la ragione per cui la risposta è sì e non
«è già coperto». Una fotografia di bottiglia scattata in casa porta nei metadati
**le coordinate GPS del luogo dello scatto**, più modello dell'apparecchio e ora
esatta. Inoltrarla intatta a PhotoRoom — o a un modello di visione — significa
**esportare l'indirizzo di casa del venditore** a un fornitore che non ha nessuna
ragione di riceverlo e nessun contratto che lo nomini. Non è un rischio teorico:
è il comportamento predefinito di ogni telefono, e nessun percorso attuale toglie
i metadati, perché finora le foto non uscivano dalla piattaforma.

> **Conseguenza tecnica, e non è piccola: spogliare l'EXIF costringe la function a
> scaricare i byte.** Non basta passare al fornitore un URL — firmato o pubblico
> — perché togliere metadati significa **riscrivere il file**. L'immagine si
> carica in memoria nella function, si ripulisce e si inoltra come `imageFile`.
> Questo è ciò che rende gratuito il bucket privato del 6.1(a-bis): il percorso di
> lettura sarebbe stato identico anche con un bucket pubblico.

### 6.4 Le due migrazioni: forma delle colonne, RLS e grant — CHIUSA (12 agosto 2026)

**Chiusa**, ed è la decisione con più conseguenze.

**(a) La spunta di completezza su `listings` — CHIUSA: `enum` a tre valori.** La
colonna non esiste: verificato per interrogazione diretta al catalogo di
produzione (3.5), `listings` non ha nulla che assomigli a una spunta di
completezza, quindi il disegno era interamente da fare e nessun vincolo storico lo
restringeva.

| Forma | Implicazione | Esito |
| --- | --- | --- |
| `boolean` | Semplice. Ma non distingue «verificata e incompleta» da «mai verificata», e il default `false` mente su entrambe | Scartata |
| **`enum`** a tre valori (`non_verificata`, `incompleta`, `completa`) | Distingue i tre stati veri. Un tipo nuovo, e il vincolo della 7f: **castare esplicitamente ogni ramo di un `case`**, mai un letterale nudo | **SCELTA** |
| Punteggio `smallint` + soglia | Più informativo, ma espone all'utente un numero che l'AI non sa produrre in modo stabile, e la soglia diventa una regola di prodotto nascosta | Scartata |

**Le tre domande che la forma non risolveva da sola, chiuse insieme a essa.**

- **Quando si calcola: alla pubblicazione.** Non durante il wizard. Questo chiude
  anche la domanda che la 6.2 aveva lasciato aperta di proposito — se autofill e
  spunta condividano una chiamata di visione — e la chiude nel senso che
  **elimina il costo doppio**: i due momenti sono diversi, quindi non c'è nessuna
  chiamata da condividere e il contro registrato al 2.4 (11.B) **sparisce da sé**.
  La 6.2 diceva «prima questa domanda decideva l'architettura; adesso ne misura il
  prezzo»: il prezzo misurato è zero.
- **Scade quando il venditore cambia le foto, e il ricalcolo è esplicito.** Non
  automatico: un trigger significherebbe **una chiamata AI dentro una
  transazione**, che il documento già segnalava da evitare e che resta esclusa. Il
  cambio di foto riporta la colonna a `non_verificata`; tornare a `completa`
  richiede che qualcuno chieda il ricalcolo. Il vantaggio dell'`enum` a tre valori
  si vede qui: `non_verificata` è uno stato vero e dicibile, mentre un `boolean`
  avrebbe dovuto mentire scegliendo fra `false` e `null`.
- **È visibile anche al compratore anonimo**, quindi entra in `public_listings`,
  la vista pubblica a colonne chiuse.

> **La visibilità all'anonimo è la risposta che rende portante il vincolo di
> etichettatura della 7.3, e va detto qui.** Finché la spunta fosse rimasta
> visibile al solo venditore, «completezza documentale» e «autenticità
> certificata» sarebbero state una sfumatura di linguaggio interno. Mostrata a un
> estraneo che sta decidendo se comprare, la spunta diventa **una promessa del
> prodotto verso di lui** — ed è esattamente il caso che l'invariante
> «le risposte non certificano autenticità o valore» (`docs/SECURITY.md:189-197`)
> non era stato scritto per coprire, perché finora riguardava testo generato e non
> un elemento di interfaccia. Le parole scelte per quell'elemento **sono parte
> della decisione 7.3**, non una nota di stile, e questa risposta le rende
> vincolanti invece che consigliate.

**(b) L'esito del triage — CHIUSA: convive con `priorita`, in una tabella
collegata `report_triage`.** La parte già **decisa** dalla Fase 10 era che l'esito
è **persistito e non ricalcolato a ogni apertura del pannello**
(`CONTESTO_IA/01_STATO_ATTUALE.md:1132-1135`, e la tabella riassuntiva della spec
Fase 10 a `271c7dc:50`). Restavano aperte due cose, e la prima è quella scoperta
al 3.6. Il secondo tempo del 12 agosto le ha chiuse entrambe, e ne ha aperta e
chiusa una terza che nessuna delle due poneva: **da dove parte la chiamata**.

*Nota per chi legge le fonti, e una correzione fatta.* Su `271c7dc` il **corpo**
di `§7.12` (`:761-766`) era rimasto alla formulazione precedente e diceva ancora
«va risolto prima della 10e», mentre la tabella di stato dello stesso documento
(`:50`) e il verbale (`CONTESTO_IA/01_STATO_ATTUALE.md:1132-1135`) lo registravano
già chiuso. Non era una decisione da riaprire, era una riga di prosa non
aggiornata — e **la stessa PR che porta questo documento la aggiorna**, perché una
frase falsa in una spec vigente non si segnala e si lascia: si corregge. È la sola
modifica che questa PR fa a un file diverso da questo.

**Prima domanda — il rapporto con `priorita`, e non più «dove lo metto».**
Il verbale dice «colonna persistita su `reports` **(o su una tabella collegata)**»:
la persistenza era decisa, il posto no. Ma il 3.6 ha cambiato la domanda, e vale
la pena dire come, perché la formulazione che arriva dalla Fase 10 non è più
quella giusta.

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

| Risposta | Forma concreta | Implicazione | Esito |
| --- | --- | --- | --- |
| **Convive** | **Colonna nuova accanto a `priorita`** | Le due classificazioni si possono confrontare — utile per misurare se l'AI batte la regola a 21 ingressi. Ma il pannello deve decidere **su quale delle due ordinare**, e una coda non può avere due ordinamenti insieme. Serve un secondo indice. Il confronto è il vero guadagno, e va voluto: se nessuno lo guarderà mai, questa è la colonna in più che non serve | Scartata |
| **Convive** | **Tabella collegata** (`report_triage`) | `reports` resta intatta; ci stanno anche punteggio, motivazione, modello usato e data — cioè la tracciabilità di *quale* modello ha detto *cosa* e *quando*, che una colonna sola non porta. Costa una `JOIN` nella vista di coda e una tabella nuova con le sue policy | **SCELTA** |
| **Sostituisce** | **L'AI scrive `priorita`** | Nessuna colonna nuova, ordinamento e indice già pronti, pannello invariato: la più economica di tutte. **Ma `priorita` è una colonna con una regola di dominio dietro** (`:222-225`), e sovrascriverla rende la regola deterministica non più verificabile — non si distingue più una priorità dedotta dal motivo da una dedotta dal modello. E assomiglia molto a «l'AI decide», che la 7.12 vieta per nome | Scartata |
| **Non è la stessa cosa** | **L'esito non è una priorità** | L'AI produce categoria, sintesi e segnali che la regola non può vedere — per esempio «più segnalazioni sullo stesso bersaglio», che nessuna funzione del solo `motivo` potrà mai dedurre. **Non compete con `priorita`**: elimina il conflitto alla radice e sfrutta l'unica cosa che l'AI sa fare e la regola no. Ma cambia che cosa la 7.12 promette al moderatore, e la promessa era «classifica e ordina» | Scartata |

**Come è stata affrontata, e la risposta alla domanda che la governava.** Non
partendo dallo schema ma da *che cosa il moderatore non riesce a fare oggi con la
coda ordinata per `priorita`*. La risposta data è **distinguere la gravità dentro
le `alta`**: la regola a 21 ingressi mette nello stesso scaglione tutto ciò che
contiene `truff`, `frod`, `pagament` o `molest`, e dentro quello scaglione la coda
è ordinata per data e basta. È il caso che la sezione stessa indicava come
tipicamente risolto dalla convivenza — e la convivenza è stata scelta nella forma
della **tabella collegata**, non della colonna, perché una tabella porta anche
quale modello ha prodotto l'esito e quando, che è ciò che rende l'affermazione
dell'AI **verificabile invece che solo visibile**.

**Ordinamento — CHIUSA: `priorita` resta primaria, il triage ordina dentro il
gruppo.** Il conflitto che la tabella qui sopra segnalava («una coda non può avere
due ordinamenti insieme») si scioglie ordinando in cascata invece che scegliendo:
prima `priorita`, poi il punteggio del triage, poi la data. La regola deterministica
resta il primo criterio — quindi **non è mai scavalcata da un modello**, che è la
forma in cui la 7.12 «nessuna azione autonoma» si traduce in un `order by` — e
l'AI ordina solo là dove oggi non c'è nessun ordine. **Costo da mettere a
bilancio:** l'indice esistente `reports_stato_priorita_idx on public.reports
(stato, priorita desc, created_at desc)` (`:231-232`) non copre più
l'ordinamento; ne serve uno nuovo che tenga conto della colonna della tabella
collegata.

**Contenuto — CHIUSA: punteggio più motivazione breve. Nessun enum di categorie.**
Questo chiude anche la (c) qui sotto: non c'è nessuna tassonomia da definire,
quindi non c'è nessuna delle tre alternative da scegliere. Il punteggio è ciò che
ordina dentro il gruppo; la motivazione breve è ciò che permette al moderatore di
**non fidarsi** del punteggio senza aprire la segnalazione. Un numero da solo
sarebbe un oracolo, e un oracolo che nessuno può controllare è precisamente la
forma di «l'AI decide» che la 7.12 vieta anche quando il bottone lo preme un
umano.

**Seconda domanda — chi lo vede. CHIUSA: no, non compare in `my_reports`.** Una
colonna su `reports` è invisibile finché non entra in `moderation_report_queue`
(3.5), e la scelta è che entri **solo** lì. La proposta ovvia del documento è stata
confermata: la valutazione automatica di una segnalazione è materiale di lavoro
del moderatore, e la 9a aveva già cura di tenere fuori dalle proiezioni
raggiungibili dal segnalante ciò che non le riguardava (`:218-221`). Ora è scritta.

**Terza domanda, che nessuna delle due poneva — da dove parte la chiamata.
CHIUSA: la chiama il client dopo l'RPC.** È emersa chiudendo il «quando»: il
triage gira **all'invio della segnalazione**, ma `segnalazione_invia` è una
funzione Postgres e **non può chiamare un fornitore esterno** — `pg_net` è escluso
dalla decisione 1a della Fase 7d, non rinviato. Serviva quindi una Edge Function,
e serviva decidere da dove viene invocata.

| Opzione | Implicazione | Esito |
| --- | --- | --- |
| **Il client chiama `ai-triage` dopo l'RPC** | `segnalazione_invia` resta intatta. Se il client non chiama, il triage non avviene: la valutazione è **facoltativa** | **SCELTA** |
| **`segnalazione_invia` diventa una Edge Function che fa entrambe le cose** | Il triage è garantito. Ma modifica una superficie della Fase 9 **già distribuita**, e lega l'invio di una segnalazione alla riuscita di una chiamata a un terzo | Scartata |

La motivazione, con le parole di chi ha deciso, perché è il principio e non il
dettaglio a dover sopravvivere: *«`segnalazione_invia` è una superficie della Fase
9 già distribuita e già verificata in questa stessa sessione — toccarla per farla
diventare un'Edge Function è esattamente il tipo di modifica a un sistema già in
produzione che questo progetto evita sistematicamente… l'opzione 2 lega l'invio di
una segnalazione — un'azione critica già esistente — alla riuscita di una chiamata
a un fornitore esterno. È il contrario del principio che regge tutta questa fase:
`AI_ENABLED` fallisce chiuso proprio perché una funzionalità AI non deve mai
diventare un blocco per qualcosa che già funziona»*. E sul costo accettato: *«il
triage è facoltativo se il client non chiama la function — è reale ma
esplicitamente non pericoloso: la coda ha comunque `priorita`, già deterministica e
già in produzione, come rete di sicurezza. È un degradare bene, non un fallire
silenzioso»*.

**Questa risposta apre il guardiano della 6.7**, ed è per quello che la 6.7 esiste:
una function chiamata dal browser, su un percorso che non è quello di
`report:submit`, ha bisogno di un limite proprio — e la 6.5(4) ha deciso che quel
limite **non è un bucket di frequenza**.

**(c) Le categorie del triage — CHIUSA per assorbimento: non esistono.** La
domanda era se valesse il meccanismo di `report_reasons` — fonte unica in
`frontend/src/data/moderation.ts` più vincolo referenziale in database — e la
risposta è che **non c'è niente a cui applicarlo**: il contenuto deciso è
punteggio e motivazione breve, non una categoria. Le tre opzioni che erano sul
tavolo (enum chiuso, tabella di riferimento, testo libero) decadono tutte insieme.

Resta valida, e vale la pena conservarla per una fase futura che volesse
riaprirla, la distinzione che rendeva la domanda non banale: `report_reasons` è il
**menu di un utente** e deve coincidere con ciò che il database accetta; una
tassonomia di triage sarebbe **l'uscita di un modello**, che nessun menu mostra, e
i due casi non si governano con lo stesso meccanismo.

**(d) La colonna e la tabella** vanno scritte da una `SECURITY DEFINER` come unica
porta, restano fuori dal `GRANT` e non sono mai scrivibili dal client. Questo è
già vincolato dalle tre regole di esposizione e **non è una decisione aperta**:
è un requisito. Aperta era solo la forma, e ora è chiusa.

La forma scelta al (b) — una tabella collegata invece di una colonna — **non
allenta il requisito, lo sposta**: `report_triage` nasce con RLS accesa e nessun
grant client, come le tre tabelle di dominio della 9a, e le sue righe si leggono
**solo** attraverso `moderation_report_queue` in `JOIN`. Vale in particolare la
prima regola di esposizione: il moderatore raggiunge righe che non ha creato,
quindi la tabella non prende un `GRANT SELECT` di tabella intera, e il filtro sta
dentro la vista `security_invoker = off` dove nessun client può allargarlo.
`listings`, invece, ha già grant **per colonna** (3.5): la colonna nuova
semplicemente non entra nell'elenco, e nasce chiusa senza dover restringere niente.

### 6.5 Limite di frequenza e valori numerici — CHIUSA (12 agosto 2026)

**La forma la fissava già la 7.4 e non si riapre:** **un bucket per funzionalità**,
**finestra oraria**, **nessuna esenzione per `admin`**, **nessun secondo tetto
nostro** oltre al limite di frequenza per il v0. Erano aperti i numeri, e sono
chiusi.

| Scope | Limite | Perché quel numero |
| --- | --- | --- |
| `ai:autofill` | **30 / ora** | È la cadenza dell'uso reale: si invoca **mentre si compila**, una volta per foto, e `MAX_FOTO = 6` (3.3). Trenta sono cinque annunci in un'ora, che è una sera di catalogazione, non un abuso |
| `ai:completezza` | **10 / ora** | Si invoca **una volta per annuncio**, alla pubblicazione (6.4a), e di nuovo solo se il venditore cambia le foto e chiede il ricalcolo. Dieci annunci pubblicati in un'ora è già oltre l'uso plausibile |
| `ai:sfondo` | **15 / ora** | L'unica pagata **a immagine** a un fornitore esterno, quindi l'unica in cui il limite si traduce direttamente in fattura. Sta in mezzo perché non tutte le foto passano dallo sfondo, ma più di una per annuncio sì |
| *triage 7.12* | **nessuno scope nuovo** | Vedi il punto 4 e la 6.7 |

I tre numeri **non sono ereditati da nessuna proposta**. Quelli della 7.4 erano
`10 / 3600 s` per entrambi gli scope allora previsti, mai verificati contro un uso
reale (3.9), e il precedente più recente è che la riconferma numerica della Fase 10
**ha dovuto correggere due valori su tre** perché `10 / 3600` si esauriva dentro
una sola conversazione. Qui la stessa lezione è applicata prima e non dopo:
ciascuno dei tre è tarato sulla cadenza della funzionalità che limita, e le tre
cadenze sono diverse — il che è precisamente l'argomento per cui la 7.4 aveva
rifiutato il bucket unico del legacy.

**4. Il triage non prende uno scope, e questa è una risposta e non un'omissione.**
La domanda originale aveva due rami: se il triage gira sul flusso di invio di una
segnalazione, il limite che conta è già `report:submit` a `10 / 3600 s`
(`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524`) e un
secondo bucket sullo stesso percorso sarebbe il «secondo tetto» che la 7.4 ha
respinto; se invece gira su richiesta del moderatore, è un percorso diverso e la
domanda si riapre. **La risposta è il primo ramo: gira all'invio della
segnalazione.** Ma la 6.4b ha poi stabilito che la chiamata parte **dal client,
dopo l'RPC** — quindi non è letteralmente lo stesso percorso, e il guardiano che
rende vera la risposta «nessuno scope nuovo» va scritto. È la 6.7.

**5. I nomi degli scope: `ai:autofill`, `ai:completezza`, `ai:sfondo`.** La 7.4
proponeva `ai:visione` e `ai:sfondo`, ma `ai:visione` era nato quando 7.3a e 7.3b
erano una cosa sola: con due function un nome condiviso avrebbe rifatto, per la
porta di servizio, il bucket unico che la 6.2 aveva appena separato. **`AiScope`
passa da tre valori a sei** (`supabase/functions/_shared/ai-gate.ts:66`), e i
numeri restano dove sono già — in quel file, punto unico (3.9).

**6. Dimensione massima del file: 5 MB, invariata.** Chiusa al 6.1(c), con il
motivo per cui non è stata ereditata ma riconfermata per il caso nuovo.

**7. Tetto mensile per fornitore: sul conto del fornitore, valore fissato al
momento in cui si configura la chiave.** Chiusa al 6.3(d), con la motivazione
sull'assenza di dati di consumo. Vale per tutti i fornitori nuovi, PhotoRoom
compreso.

**Nota del 13 agosto 2026 — il 15/ora di `ai:sfondo` è stato riesaminato e
confermato.** La §10.3 ha ricavato che una pressione sul pulsante dello sfondo
vale **sei** chiamate e non una, quindi il limite copre due conversioni complete
l'ora: un motivo legittimo per riaprire questo numero. La sessione lo ha
**lasciato a 15**, con il criterio di Enrico — *«prima di pagare»* — e con la
condizione di riapertura scritta: **costi reali e cadenza d'uso osservata dopo
che `11c` è in produzione**, non un conto teorico. Questa riga registra che il
numero è stato guardato di nuovo; la 6.5 non è riaperta, e chi implementa `11c`
scrive **15**.

### 6.6 La prova del provider fotografico — CHIUSA (12 agosto 2026)

La 7.1 la impone e **non è ancora stata fatta**: qui è deciso come si fa, non che
è fatta.

- **Chi la conduce: Enrico.** L'osservazione che il confronto fra due uscite non
  richiede accesso al progetto — e quindi potrebbe farlo chiunque — resta vera, ma
  la prova richiede **foto vere di bottiglie vere**, e la 7.1 vieta per nome un
  benchmark su documenti puliti. Chi ha la cantina è chi può produrre il materiale.
- **Con quali foto: sei foto reali della cantina di Enrico, due volutamente
  difficili** — riflesso sul vetro, etichetta parzialmente coperta. La proposta del
  documento è stata confermata così com'era.
- **Con quale criterio: campi corretti su nove, e campi inventati, contati
  separatamente.** I nove sono quelli di `ai-catalogo`
  (`supabase/functions/ai-catalogo/index.ts:31-33`). La ragione per cui i due
  conteggi devono restare due, con le parole di chi ha deciso: contare solo i campi
  corretti *«premia un modello che riempie tutti e nove i campi tirando a
  indovinare rispetto a uno che ne lascia quattro onestamente vuoti»*. L'invenzione
  è l'errore peggiore perché il `confidence` non la cattura — un modello sicuro di
  un'annata che non ha letto restituisce un numero alto su un dato falso.
- **Quando: prima di aprire `11a`.** Non «può avvenire dopo la sessione che chiude
  le altre decisioni», che era la proposta più permissiva del documento. La ragione
  è quella scritta due paragrafi più sotto e vale anche in senso pratico: la prova
  non cambia *se* si scrive un adapter, cambia *quale*, e riscriverne uno dopo
  averlo scritto costa più che aspettare sei fotografie.

> **Conseguenza immediata, e non aggirabile.** La prova richiede due candidati
> interrogabili, quindi **richiede le chiavi**, che al 12 agosto 2026 non esistono
> per nessun fornitore (7.11, scadenza 18 agosto 2026). Mettendo la prova prima di
> `11a`, questa decisione rende `11a` **non apribile finché la 7.11 non è
> soddisfatta** — il che è la conclusione, non un effetto collaterale: era già
> vero che il codice era bloccato dalla 7.1, e ora è scritto nell'ordine giusto.

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

### 6.7 Il guardiano di `ai-triage` — CHIUSA (12 agosto 2026), derivata

**Non è una decisione nuova: è ciò che rende vera una risposta già data**, e viene
scritta perché una conseguenza lasciata implicita è una conseguenza che al momento
del codice nessuno ritrova. Stessa disciplina applicata al TTL dello storico
Sommelier, dove «le righe scadute restano a tabella» non è rimasto un ragionamento
di sessione ma è finito nel commento di tabella, nella migrazione e in un caso di
griglia.

**Il problema.** La 6.5(4) risponde che il triage **non ha uno scope di
frequenza**, con l'argomento che gira sul percorso dell'invio di una segnalazione,
già limitato da `report:submit` a `10 / 3600 s`. La 6.4b però stabilisce che la
chiamata parte **dal client, dopo l'RPC**. Le due risposte insieme lasciano una
Edge Function invocabile da un browser su un percorso che `report:submit` **non
copre**: chi ha già inviato una segnalazione può chiamare `ai-triage` quante volte
vuole, e ogni chiamata è una chiamata a un fornitore a pagamento.

**La risposta non è un bucket.** Aggiungerne uno sarebbe il «secondo tetto» che la
7.4 ha respinto per nome, e sarebbe anche la soluzione sbagliata al problema
giusto: il numero di valutazioni sensate **non è un numero all'ora**, è **una per
segnalazione**. Il vincolo naturale è quello, e già limita il totale a ciò che
`report:submit` consente di creare.

**L'enforcement, esplicito e in tre punti.** «Una valutazione per segnalazione, e
solo dal suo segnalante» non è un principio da ricordare: è un vincolo da
scrivere, e sta scritto in tre posti perché ciascuno copre ciò che gli altri non
coprono.

1. **Vincolo di unicità su `report_triage.report_id`**, nella migrazione che crea
   la tabella. È l'unico dei tre che regge anche contro una corsa fra due
   richieste simultanee e contro un percorso futuro che nessuno ha previsto —
   compreso `service_role`, che i `GRANT` del client non vincolano. Un `unique` è
   anche l'indice della `JOIN` con la coda, quindi non costa niente in più.
2. **Controllo *prima* della chiamata al fornitore**, dentro `ai-triage`: la
   function verifica che la segnalazione esista, che il chiamante ne sia il
   segnalante, e che **non abbia già una riga in `report_triage`** — e solo dopo
   spende. Senza questo controllo il vincolo di unicità farebbe comunque il suo
   lavoro, ma **fallendo all'`insert`, cioè dopo aver pagato la chiamata**: la
   spesa che il guardiano esiste per evitare sarebbe già stata fatta.
3. **Un caso di griglia che lo esercita**, come per il TTL: due chiamate sulla
   stessa segnalazione, la seconda non produce una seconda riga. Una griglia
   scritta e mai eseguita non è una prova, e questo caso serve proprio perché il
   guardiano è la parte che nessuno guarda quando funziona.

> **Il costo accettato, dichiarato qui e non altrove.** Se il client non chiama,
> la valutazione non avviene: il triage è **facoltativo per costruzione**. La
> 6.4b lo accetta esplicitamente, e la rete di sicurezza è che la coda ha comunque
> `priorita` — deterministica, già in produzione, già l'ordinamento primario per
> la 6.4b. È un degradare bene, non un fallire silenzioso, e l'alternativa
> (garantire il triage legandolo a `segnalazione_invia`) è quella che è stata
> scartata.

---

## 7. Effort e dipendenze

**Dipendenze esterne alla fase, che nessuna quantità di codice chiude.** Con la
sezione 6 chiusa, **sono l'unica cosa che separa la fase dal suo primo branch** —
e nessuna delle tre è soddisfatta al 12 agosto 2026:

1. **Le chiavi dei fornitori di modelli** (7.11, 18 agosto 2026). La chiave
   PhotoRoom **non è più in questa scadenza**: la 6.3(b) le ha dato una data
   propria, che è l'apertura di `11c`.
2. **La prova su foto reali** (6.6), che la sessione ha messo **prima** di `11a` e
   che a sua volta dipende dal punto 1.
3. **Il pannello di moderazione della Fase 9 esercitato almeno una volta** su una
   sessione reale, prima di `11d`.

**Ordine di grandezza aggiornato alle decisioni del 12 agosto (secondo tempo)**,
sapendo che l'adapter di visione è lavoro vero (3.7) e non configurazione. Ogni
riga è cresciuta rispetto alla prima stesura, e il conto va letto prima di aprire
un branch, non durante:

| Voce | Stima | Era |
| --- | --- | --- |
| Migrazioni | **Quattro**, una per checkpoint: bucket `foto-ai` e policy (`11a`); `enum` e colonna di completezza su `listings` con la sua `SECURITY DEFINER` e l'aggiunta a `public_listings` (`11b`); bucket `sfondi` e policy (`11c`); tabella `report_triage`, `JOIN` e nuovo indice sulla coda (`11d`) | «Due più una terza» |
| Edge Function | **Quattro nuove**: `ai-autofill`, `ai-completezza`, `ai-sfondo`, `ai-triage`. **Da sei distribuite si passa a dieci** | «Tre, da tre a sei o sette» |
| Bucket di Storage | **Due nuovi**: `foto-ai` privato, `sfondi` pubblico. Da due si passa a quattro | Uno |
| Scope di frequenza | **Tre nuovi**: `ai:autofill`, `ai:completezza`, `ai:sfondo`. `AiScope` da tre valori a sei | Due proposti |
| Adapter di provider | **Due nuovi**: quello di visione (Claude o Gemini, entrambi da zero) e quello di PhotoRoom, che non passa da `AiProvider` e ha un modulo proprio (6.3a) | Idem |
| Superfici UI | Wizard `/vendi` (foto → autofill; scelta sfondo con anteprima e conferma), badge di completezza sull'annuncio **e su `public_listings`**, `SfondoIAPanel` reale, pannello di moderazione | Idem, senza l'anteprima |
| Griglie SQL | Una per migrazione — quindi **quattro** — **da eseguire almeno una volta** prima di chiamarle prove. Fra i casi obbligatori: l'unicità della 6.7 e la mancata pulizia di `foto-ai` della 6.1(b) | «Una per migrazione» |

**Il conteggio delle Edge Function ha una conseguenza operativa, non solo
contabile.** Le tre corse misurate in 7.10 (§2.5) ridistribuirono **tutte** le
function esistenti, quindi anche un merge che non le tocca può rimettere in
produzione i tre percorsi dei pagamenti e i tre della Fase 10. Non si presume che
la corsa parta o completi: la si verifica dopo. È la ragione per cui
`_shared/cors.ts` deve avere diff vuoto in ogni PR di questa fase, e per cui
l'ambiente di ogni function nuova va configurato e verificato **prima** del
merge che può attivarla.

**Il debito che questa fase eredita e deve chiudere.** La 7.13 ha tolto
`SfondoIAPanel` dalla lista di cutover per chiuderlo «in questa fase», ma la 7.13
è restata fuori dal checkpoint unico della Fase 10. Quella fase è ora la **11**:
fino ad allora `frontend/src/routes/vendi.tsx:569-579` continua a promettere uno
sfondo che è un `setTimeout` di 1100 ms e un toast «Sfondo applicato (demo)».
**Se la Fase 11 non lo chiude, il debito torna sulla lista di cutover della Fase
12** e non sparisce da solo.

---

## 8. Che cosa deve succedere prima che si apra un branch

I primi due punti sono **fatti**; i due che restano non dipendono da questo
documento e nessuno dei due si chiude scrivendo codice.

1. ~~Una sessione organizzativa che chiude ciò che della sezione 6 resta
   aperto~~ — **fatta il 12 agosto 2026, in due tempi.** Tutte e sei le aree hanno
   una risposta registrata con data e motivazione; due domande che la sezione non
   poneva sono state poste e chiuse (6.3c-bis, 6.4b terza domanda) e una
   conseguenza è stata derivata e scritta (6.7).
2. ~~Le risposte trascritte in `CONTESTO_IA/01_STATO_ATTUALE.md` e in questo
   documento, con data~~ — **fatte dalla PR che porta questo aggiornamento**,
   sola documentazione, sul modello della #34 e della #37.
3. **La configurazione delle chiavi dei fornitori di modelli** (7.11, 18 agosto
   2026). Senza, la prova della 6.6 non è eseguibile: non ci sono due candidati da
   confrontare.
4. **La prova della 6.6**, che la sessione ha messo **prima** di `11a`.
5. Solo allora `migration/phase-11-…`, un checkpoint per volta — e `11c` non prima
   che esista la chiave PhotoRoom, `11d` non prima che il pannello della Fase 9
   sia stato esercitato almeno una volta.

> **Perché il branch non si è aperto nella stessa sessione che ha chiuso le
> decisioni.** Non per prudenza: perché la sessione ha deciso, un'ora prima, che
> la prova 6.6 viene **prima** di `11a`, e quella prova richiede chiavi che al 12
> agosto 2026 non esistono. Aprire `11a` subito dopo avrebbe contraddetto la
> decisione appena presa. Gli altri tre checkpoint sono bloccati a loro volta —
> `11b` da `11a`, `11c` da una chiave la cui data è l'apertura di `11c` stesso,
> `11d` dal pannello mai esercitato. **Fermarsi a un checkpoint onesto non è un
> fallimento; forzare tutto in una sessione per finire prima lo è.**

Alla data di questa decisione, applicare qualunque cosa al progetto reale —
migrazione, function, configurazione — richiedeva **una conferma esplicita e
distinta per perimetro**. Questa è storia della sessione, non policy corrente:
`CLAUDE.md` oggi autorizza autonomamente il lavoro tecnico richiesto dal task,
fermi i gate organizzativi sullo scope e tutte le protezioni operative.

---

## 9. La revisione legale — una proposta iniziale, non una chiusura

> **APERTA.** Questa sezione registra una **proposta**, non una decisione, e non
> fa parte della §6 — che resta chiusa per intero. Il blocco è quello scritto in
> `CHANGES.log`: **«la Fase 11 non potrà essere chiusa prima di quella revisione
> senza che qualcuno la dichiari»**, e nessuna riga di questo documento è quella
> dichiarazione.

**La proposta, del 12 agosto 2026.** Enrico propone **un'informativa su privacy e
uso dell'IA mostrata in fase di registrazione**, perché ogni utente sappia,
iscrivendosi, che il sito usa l'intelligenza artificiale.

Sta scritta qui perché è **il primo materiale che questa fase consegna alla
revisione legale**, e perché una proposta che resta in una conversazione non
arriva a chi quella revisione dovrà farla.

### 9.1 Che cosa copre ragionevolmente

L'obbligo **generale di trasparenza**: chi interagisce con un sistema di IA deve
saperlo (AI Act, art. 50, dal **2 agosto 2026** — la stessa data già citata in
§1.2). Un'informativa alla registrazione è la forma consueta con cui quell'obbligo
si assolve, e questa fase ne aumenta la rilevanza invece di lasciarla dov'era: da
tre funzionalità AI si passa a sette, e due delle nuove — la spunta di completezza
(7.3b) e il triage (7.12) — producono effetti che l'utente **vede o subisce**
invece di richiedere.

### 9.2 Che cosa **non** copre da solo

L'obbligo del **DSA sulla dichiarazione dei motivi** per la singola decisione di
moderazione che un utente subisce (art. 17). Quell'obbligo riguarda **quella
decisione**: la sua motivazione specifica, e l'indicazione se nel prenderla siano
stati usati mezzi automatizzati. Non si assolve con un'accettazione generica data
mesi prima all'iscrizione. Un venditore a cui viene rimosso un annuncio ha diritto
di sapere perché è stato preso **quel** provvedimento, e un'informativa di
registrazione non risponde a quella domanda.

È questa la ragione per cui la proposta è registrata come parziale invece di
chiudere il blocco: **sono due obblighi diversi**, e la proposta ne indirizza uno.

### 9.3 Che cosa riduce il rischio senza eliminarlo

La **7.12 non dà all'IA nessuna azione autonoma**: classifica e ordina, il bottone
lo preme un umano, e in `audit_log` non esiste un'identità «attore AI». Il DSA è
più severo sulle decisioni **interamente automatizzate**, quindi quel vincolo —
preso per altre ragioni — **riduce** l'esposizione. Non la elimina: la
dichiarazione dei motivi è dovuta anche per una decisione umana, e resta dovuta
anche quando l'automazione si è limitata a ordinare la coda che l'umano ha
guardato.

### 9.4 Che cosa la revisione deve ancora rispondere

Domande, non risposte. Nessuna è decisa qui e nessuna va riempita in silenzio
durante l'implementazione — è la stessa disciplina della §6, applicata a un'area
che questa fase **non** chiude.

1. **Se e in che misura il DSA si applichi** a una piattaforma di queste
   dimensioni, e quali obblighi restino comunque. Viene prima delle altre tre, e
   questo documento non la risponde.
2. Se la dichiarazione dei motivi sia **già dovuta oggi** — la moderazione della
   Fase 9 è distribuita e le sue sette RPC scrivono `audit_log` — o se lo diventi
   con la Fase 11. Il triage non crea l'obbligo: sposta il momento in cui conviene
   accorgersene.
3. Se l'informativa alla registrazione basti per gli **utenti già iscritti**, che
   alla registrazione non l'hanno vista.
4. Se e come vada dichiarato che **la coda del moderatore è ordinata anche da un
   modello**: la 6.4b lo mette dentro un `order by`, non dentro una decisione.
5. Come si formulano le parole della spunta 7.3b, che la 6.4a ha reso **visibile
   al compratore anonimo**. Il vincolo «completezza documentale, mai autenticità
   certificata» è deciso (§2.1); la validazione legale di come è formulato no
   (§1.2).

### 9.5 La prima azione concreta: le etichette di trasparenza sui pannelli esistenti

Il **13 agosto 2026** le tre superfici IA che la Fase 10 ha messo in produzione
hanno ricevuto **un'etichetta visibile che dichiara l'IA nel momento in cui
l'utente la usa**:

| Superficie | Etichetta |
| --- | --- |
| Pannello Sommelier del Layout | «Parla con il tuo sommelier IA» |
| Pannello Assistente del passo Identificazione | «Fatti suggerire i campi dall'assistente IA» |
| Pannello di abbinamento in `/esplora` | «Chiedi gli abbinamenti al sommelier IA» |

**Perché serviva, visto che i pannelli dicevano già «AI».** Lo dicevano nel
titolo: «Sommelier AI» è il nome del pannello, cioè un'insegna. L'obbligo della
§9.1 è che chi interagisce con un sistema di IA lo sappia, e saperlo per aver
interpretato un nome non è la stessa cosa che leggerlo detto.

Il testo vive in un modulo solo — `frontend-next/src/lib/phase10/etichette-ia.ts`
— con i suoi test (`etichette-ia.test.ts`, cinque casi), per due ragioni che
valgono più della comodità: quando la revisione legale risponderà, le parole si
cambiano in **un punto**; e un test verifica che le superfici coperte siano
esattamente quelle esistenti, così una **quarta** superficie IA — le quattro di
questa fase lo saranno — non può essere aggiunta senza etichetta in silenzio. È
la stessa forma del vincolo `SESSION_ID_VALIDO` della 10b: la regola sta accanto
al valore, non nella memoria di chi lo modifica.

**Che cosa questo non sposta.** Nulla della §9.2: la dichiarazione dei motivi del
DSA riguarda **quella** decisione di moderazione, e un'etichetta su un pannello
non la fornisce più di quanto la fornisse l'informativa alla registrazione.
**Il blocco della revisione legale resta dov'era.** Questa è un'azione che
indirizza l'obbligo **generale**, non la chiusura di un'area aperta, e le cinque
domande della §9.4 restano tutte e cinque senza risposta.

> **Che cosa questa sezione non cambia.** Non modifica il perimetro della §1, non
> aggiunge una quinta funzionalità, non tocca nessuna decisione della §6 e non
> apre nessun checkpoint della Fase 11: la §9.5 è testo di interfaccia su
> superfici della **Fase 10**, già mersate, non lavoro di implementazione di
> questa fase. La revisione legale resta **fuori dalla fase** (§1.2) e resta ciò
> senza cui la fase non si dichiara chiusa.

---

## 10. Copy e flusso pronti per `11a` e `11c` — registrati, non costruiti

> **NON APRE NIENTE.** Questa sezione registra **testo pronto** per quando i due
> checkpoint apriranno, deciso in sessione il **13 agosto 2026**. Non riapre la
> §6, non anticipa un branch e non è lavoro fatto: `11a` e `11c` restano bloccati
> esattamente come li lascia la §8 — `11a` dalla prova 6.6 e dalle chiavi che non
> esistono, `11c` da una chiave PhotoRoom la cui data è **per definizione**
> l'apertura di `11c` (6.3b).
>
> **La §10.3 è chiusa nello stesso giorno**, in un secondo passaggio: i tre punti
> che la prima stesura lasciava come domande sono ora **tre decisioni di
> sessione**, con la stessa forza di quelle della §6. Una di esse riguarda un
> valore della 6.5 e **lo conferma** — `ai:sfondo` resta a 15/ora — quindi non
> riapre niente: registra a quale condizione quel numero tornerà in sessione.

Sta scritta qui per la stessa ragione della §9: il testo di interfaccia deciso in
una conversazione e non scritto da nessuna parte viene reinventato da chi apre il
branch. E le parole di queste due superfici non sono neutre — una promette
un'azione automatica su campi che il venditore poi pubblica, l'altra sostituisce
le fotografie di un annuncio.

### 10.1 `11a` — il pulsante dell'autofill (7.3a)

**«Riempi i campi automaticamente con l'IA».**

«Automaticamente» è esatto e va tenuto: la 7.3a **riempie**, non suggerisce, e
questo la distingue dal pannello di catalogazione della Fase 10, la cui etichetta
dice apposta «fatti **suggerire** i campi» (§9.5) perché lì applicare il
suggerimento è un secondo gesto. Le due superfici convivono nello stesso passo
del wizard e non vanno descritte con le stesse parole.

Il presidio non è nel verbo ma nel passo: i campi del wizard restano modificabili
a mano — la pagina lo dice già in cima al passo Identificazione — e la
pubblicazione resta un gesto successivo del venditore. Quello che «riempi
automaticamente» promette è il risparmio di battitura, non l'assenza di
controllo.

**Due obblighi che si trascinano dietro**, entrambi già decisi altrove e citati
qui perché è dove qualcuno li leggerà:

- La 7.3a è **una quarta superficie IA**, quindi le serve la sua etichetta di
  trasparenza, cioè una quarta voce in `frontend-next/src/lib/phase10/etichette-ia.ts`.
  Il test di quel modulo fallisce se la superficie viene aggiunta senza (§9.5).
- La foto che alimenta l'autofill esce dalla piattaforma, quindi vale la 6.3(e):
  **EXIF spogliato prima dell'inoltro**, e la function scarica i byte invece di
  passare un URL firmato.

### 10.2 `11c` — il flusso dello sfondo (7.13)

**Pulsante: «Passa al set fotografico IA».**

La sequenza, per esteso:

1. Il venditore **sceglie lo sfondo** fra quelli curati del bucket `sfondi`
   (6.3c-bis).
2. Preme il pulsante, che avvia la conversione di **tutte le foto dell'annuncio**
   con quello sfondo. Se il limite orario si esaurisce a metà, la conversione
   **si ferma lì** invece di essere rifiutata in partenza (§10.3a).
3. Il risultato porta a una **schermata a rullino**: ogni foto convertita è
   mostrata **accanto alla propria originale**. Le foto che la conversione non ha
   raggiunto restano con la sola originale, e si vedono.
4. Il venditore **conferma o rifiuta la sostituzione**. La conferma è
   **cumulativa con eccezioni** (§10.3c): esiste un «conferma tutte» rapido, e
   accanto a esso il venditore può **escludere** una singola foto o **farla
   rifare** prima di confermare.

**Il punto quattro è il punto.** Premere il pulsante non sostituisce niente: è la
6.3 — anteprima con conferma esplicita, perché il fallimento di PhotoRoom è
**silenzioso** (`200` con un'immagine sbagliata, non un `503`) — resa concreta
come interazione. Il rullino affiancato è ciò che rende visibile un fallimento
che nessun codice può accorgersi di aver subito, e l'originale non viene mai
sovrascritto.

**I tre vincoli di interfaccia che il punto quattro porta con sé**, chiusi in
sessione il 13 agosto 2026 (§10.3) e scritti qui perché è qui che chi implementa
li legge:

- **Il «conferma tutte» esiste, ma non è l'unico gesto disponibile.** Le due
  eccezioni — escludere, far rifare — sono ciò che tiene aperta la via per il caso
  che la 6.3 esiste per intercettare.
- **L'originale non viene mai sovrascritto**, nemmeno dopo la conferma cumulativa:
  è la condizione che rende innocuo fermarsi a metà.
- **Uno stato misto è uno stato legittimo del rullino**, non un errore da
  nascondere: un annuncio con tre foto convertite e tre no è ciò che il venditore
  vede quando i gettoni finiscono, e va disegnato, non evitato.

Da notare, perché è facile leggerlo al contrario: **questo pulsante è il percorso
di compositing**, quello che costa cinque *Remove Background* a chiamata. La 6.3
resta invariata — è il venditore a scegliere, con «solo ritaglio» **preselezionato**
— e questo è il ramo che sceglie chi vuole lo sfondo, non il predefinito.

Quando questo flusso esisterà, il pannello `SfondoIAPanel` di `frontend/`
(`frontend/src/routes/vendi.tsx:569-577`, un `setTimeout` di 1100 ms e un toast
«Sfondo applicato (demo)») smette di essere una promessa non mantenuta. È l'esito
che la 7.13 aveva scelto al posto di lasciarlo lì.

### 10.3 Il conto del rullino contro il limite orario — CHIUSA (13 agosto 2026)

**Chiusa in tutti e tre i punti, in sessione con Enrico**, lo stesso giorno in
cui il conto è stato fatto. Non sono scelte di chi implementa: sono **decisioni
di sessione**, come tutte quelle della §6, e vanno lette insieme al flusso della
§10.2 di cui vincolano i punti 2 e 4.

Il conto da cui nascono, per intero. Vengono dall'aver messo accanto due numeri
già decisi:

- `MAX_FOTO = 6` (`frontend-next/src/hooks/useSellWizard.ts:69`);
- `ai:sfondo` a **15 chiamate l'ora** (6.5).

Una pressione su un annuncio pieno vale **sei** chiamate. Quindi il limite copre
**due conversioni complete l'ora**, e alla terza restano tre gettoni per sei
foto: il rullino si ferma **a metà**.

**(a) Rifiuto in partenza o arresto a metà — CHIUSA: si ferma a metà, il
pulsante non si disabilita.**

Le foto già convertite **restano pronte**; le altre restano con la propria
originale finché il limite orario non si ricarica. Il venditore vede **quali
sono già fatte e quali no** — un rullino a stati misti, non un rifiuto totale.

| Opzione | Che cosa vede il venditore | Esito |
| --- | --- | --- |
| **Parte e si ferma a metà** | Un rullino in cui alcune foto hanno la conversione accanto all'originale e altre no. Il lavoro già fatto è utilizzabile subito; il resto si completa quando il secchiello si ricarica | **SCELTA** |
| **Rifiuta in partenza se il secchiello non copre tutto l'annuncio** | Un pulsante che non fa niente, per un vincolo che riguarda **una parte** dell'annuncio. Un venditore con cinque foto e tre gettoni non converte nemmeno le tre che potrebbe | Scartata |

La ragione è quella scritta nella colonna: **un rifiuto totale per un vincolo
parziale butta via lavoro che si poteva fare.** Fermarsi a metà non rompe niente
— gli originali non vengono mai sovrascritti (§10.2, punto 4) — e la
preoccupazione registrata quando la domanda era aperta, cioè che il venditore
ottenga un risultato parziale *senza che nessuno gliel'abbia detto*, non è più
tale: il rullino affiancato **è** il modo in cui glielo si dice, perché una foto
non convertita si vede a colpo d'occhio accanto a una convertita.

Il criterio con cui Enrico l'ha decisa è lo stesso della (b), ed è suo:
**«prima di pagare»**. Costruire un cancello preventivo — contare i gettoni,
confrontarli con il numero di foto, disabilitare il pulsante — è codice scritto
contro un costo che nessuno ha ancora osservato. La forma che degrada in modo
visibile non ha bisogno di essere indovinata in anticipo.

**(b) Il 15/ora va rivisto? — CHIUSA: resta 15/ora, per ora.**

**Non si rialza a tavolino.** La 6.5 ha fissato quel numero su una chiamata per
pressione, non su sei: il conto qui sopra è quindi un motivo legittimo per
riaprirlo, ma un motivo non è ancora un dato. Enrico ha legato la revisione ai
**costi reali** e non a un conto teorico — **«prima di pagare»** è la sua stessa
formulazione — e il dato che serve è **quanti annunci un venditore converte per
sessione**, che non esiste finché `11c` non è in produzione.

Quindi: **si riapre con dati veri, dopo che `11c` è live, non prima.** Resta un
punto della **6.5 da riportare in sessione** allora — non un valore che chi
implementa può alzare in silenzio, e non un default che si sposta da sé. Chi
apre `11c` scrive **15**, e se il numero si rivelerà sbagliato lo dirà l'uso.

**(c) La conferma può essere cumulativa? — CHIUSA: cumulativa con eccezioni.**

**Un «conferma tutte» rapido, ma il venditore può escludere o far rifare
singolarmente una foto prima di confermare.** È un vincolo di interfaccia della
§10.2, non una nota di comodità: sta scritto sotto, al punto 4 della sequenza,
dove chi implementa lo legge.

La preoccupazione che teneva la domanda aperta era che un «accetta tutte»
riduca l'attenzione proprio dove la 6.3 la voleva alta. La forma scelta la
risolve senza rinunciare alla comodità: il gesto rapido esiste, ma **non è
l'unico gesto disponibile**, e le due eccezioni — escludere una foto, farla
rifare — sono ciò che tiene aperta la via per il caso che la 6.3 esiste per
intercettare, cioè la conversione sbagliata che PhotoRoom ha restituito con un
`200`. Confermare tutto resta una scelta del venditore; **non è l'unica cosa che
il rullino gli permette di fare.**
