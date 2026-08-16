# Fase 10 - AiService reale via Edge Function

Stato: **specifica organizzativa, approvata per intero l'11 agosto 2026.** Questo
documento non contiene SQL né codice: è il documento delle decisioni, e resta la
fonte da cui l'implementazione discende. Il branch previsto dal backlog è
`migration/phase-10-ai-service` (`docs/MIGRATION_PHASE_1_BACKLOG.md:542`) e si
apre a decisioni chiuse, cioè adesso.

> **La Fase 10 è chiusa dall'11 agosto 2026** — PR #35, squash `442c98c` alle
> 18:53:14 UTC — al suo unico checkpoint **10a + 10b + 10c**, con perimetro le
> tre funzionalità migrate. **Le quattro ammesse per eccezione (7.3a, 7.3b, 7.12,
> 7.13) non sono state costruite e non sono più Fase 10: sono la Fase 11**, non
> iniziata e senza branch, e il cutover è diventato la Fase 12. Le sotto-fasi
> 10d/10e/10f della sezione 6 vanno lette con quella rinumerazione. La sezione 7
> resta la fonte delle decisioni che le descrivono: sono già chiuse, ed è per
> questo che la Fase 11 parte da lì e non da zero.

> **Rinumerazione del 16 agosto 2026, successiva a quella qui sopra.** Il cutover
> **non è più la Fase 12: è la Fase 13**, perché la **Fase 12** è ora
> Club/Community, che segue direttamente la Fase 11 nell'ordine di dipendenza.
> Dove questo documento dice «il cutover è diventato la Fase 12» — nel riquadro
> qui sopra e nel «Come è andata a finire» della sezione 6 — sta **raccontando la
> rinumerazione dell'11 agosto 2026** e resta com'era scritto quel giorno: è un
> resoconto, non l'indicazione del numero corrente. Il numero corrente del
> cutover è **13**, ed è quello usato nei punti di questo documento che lo
> nominano come fase viva: la 1.3 e le due voci di «lista di cutover» dentro la
> sezione 7.

Ogni affermazione di questo documento porta la fonte `file:riga` da cui viene.
Ciò che non aveva una fonte era marcato **decisione aperta**; non ne resta
nessuna.

**I numeri di riga sono presi su `8dd56c0`**, cioè `origin/main` dopo il merge
della PR #33. I file di `CONTESTO_IA/` sono citati per **sezione** e non per
riga, perché sono aggiornati a ogni fase e una riga vi resta valida per poco.

## Stato delle decisioni

La sessione organizzativa dell'**11 agosto 2026** ha letto questa specifica in due
tempi. Prima ha chiuso cinque decisioni, aggiungendone due che la prima stesura
non aveva previsto — il conto è passato da undici a tredici. Poi, letto il
resoconto delle otto proposte, ha chiuso **anche quelle**, più i due punti
conseguenti che nessuna decisione copriva. **Tutte chiuse:**

| | Decisione | Risposta della sessione |
| --- | --- | --- |
| 7.1 | Provider AI, per compito | **Chiusa** — non un solo fornitore |
| 7.2 | Storico Sommelier | **Chiusa** — A, tabella Postgres |
| 7.3 | Identificazione da foto | **Chiusa** — dentro per eccezione, come 7.3a + 7.3b |
| 7.12 | Moderazione AI | **Chiusa** — solo triage, nessuna azione autonoma |
| 7.13 | Ritaglio e sfondo | **Chiusa** — dentro per eccezione, sfondi curati |
| 7.4 | Budget e limiti numerici | **Chiusa** — un bucket per funzionalità, finestra oraria, nessun secondo tetto |
| 7.5 | Fallimento e timeout del provider | **Chiusa** — mappatura legacy invariata, `AI_ENABLED` fail-closed |
| 7.6 | Origini CORS e forma della function | **Chiusa** — nessun rename, `AI_ALLOWED_ORIGINS` a parte; una function per funzionalità |
| 7.7 | Streaming della chat | **Chiusa** — SSE, troncamento come caso atteso lato client |
| 7.8 | Catalogo dell'abbinamento | **Chiusa** — lato server, deviazione dichiarata |
| 7.9 | Chi può usare l'AI | **Chiusa** — segue i due livelli 9b/9c; anonimo → 401 |
| 7.10 | Gate di autorizzazione | **Chiusa** — è il merge; conferma per perimetro invariata |
| 7.11 | Chi configura chiave e budget, e quando | **Chiusa** — Enrico, entro il 18 agosto 2026, più il fail-closed |
| — | TTL dello storico (segue dalla 7.2) | **Chiuso** — applicato in lettura, nessuna cancellazione fisica in v0 |
| — | Dove finisce l'esito del triage (segue dalla 7.12) | **Chiuso** — colonna persistita su `reports`, seconda migrazione |

Le sezioni della 7 conservano la proposta accanto alla risposta quando le due
divergono, perché sapere **che cosa è stato scartato e perché** vale più della
risposta da sola. Dove le decisioni hanno cambiato il perimetro descritto nella
prima stesura, il testo è stato corretto sul posto e la correzione è segnalata.

**Una correzione che riguarda questo documento**, e non una decisione: la prima
stesura affermava, nella 7.10, che «distribuire una Edge Function non è un merge,
è un `deploy` separato che nessuna decisione precedente copre». **È falso**, e la
verifica è nella 7.10 stessa. Il merge distribuisce le function, automaticamente
e tutte insieme. Questo cambia in meglio la 7.10 e in peggio la 7.11.

---

## 0. Il problema di partenza: il backlog dice due righe, il codice ne dice cinquecento

Il backlog scrive sulla Fase 10 esattamente questo:

> Provider AI reale via Edge Function proxy (`ai-identify-bottle` e
> equivalenti), rate-limit lato server, chiave e budget configurati fuori dal
> repository.
>
> — `docs/MIGRATION_PHASE_1_BACKLOG.md:544-546`

Tre cose vanno dette subito, perché cambiano il perimetro rispetto a quella
frase.

1. **`ai-identify-bottle` non esiste.** Non è un file vuoto né uno stub: non c'è
   né nel repository (`supabase/functions/` contiene solo `_shared/`,
   `connect-onboarding/`, `payments-checkout/`, `payouts-release/` e
   `deno.json`) né sul progetto reale, dove `list_edge_functions` su
   `pijnmcllmfgjmgsvtcej`, letto l'11 agosto 2026, riporta le sole tre function
   `payments-checkout`, `connect-onboarding`, `payouts-release`. Il nome del
   backlog è un'intenzione, non un contratto già scritto.
2. **L'identificazione bottiglia da fotografia non esiste nemmeno nel legacy.**
   Il backend accetta un campo `ocr_text` (`backend/ai_routes.py:228`) ma
   **nessun chiamante di `frontend/` lo invia mai**: l'unico punto di consumo
   manda solo `hint`, cioè testo scritto a mano dall'utente
   (`frontend/src/hooks/useSellWizard.ts:66`). Una ricerca su tutto
   `frontend/src` per `ocr`, `tesseract`, `getUserMedia`, `capture=`, `scanner`
   non restituisce nessun percorso di acquisizione immagine. Quindi
   `ai-identify-bottle` non sarebbe la migrazione di una funzionalità esistente:
   **sarebbe una funzionalità nuova**, e le funzionalità nuove sono vietate
   durante la migrazione (`CLAUDE.md`, sezione «Migration architecture», regola
   «No new features during migration»).
3. **Il perimetro reale è cinque rotte, non una.** `backend/ai_routes.py` monta
   un router con prefisso `/ai` (`backend/ai_routes.py:16`) che espone cinque
   endpoint su tre funzionalità distinte: chat Sommelier con storico
   persistente, abbinamento cibo-vino, suggerimento di catalogazione.

**Come la sessione dell'11 agosto 2026 ha risposto.** Il punto 2 resta vero
nell'analisi e superato nella conclusione: la sessione ha ammesso
l'identificazione da foto **come eccezione esplicita**, sdoppiata in 7.3a e 7.3b,
e ha ammesso allo stesso titolo il ritaglio/sfondo della 7.13 e il triage di
moderazione della 7.12. Sono le prime funzionalità nuove autorizzate dall'inizio
della migrazione, e sono autorizzate perché una sessione le ha volute per nome,
non perché la regola sia decaduta: la regola vale ancora per tutto il resto.

Il perimetro della fase è quindi **tre funzionalità migrate più quattro ammesse
per eccezione**, e l'unica delle sette con dati da spostare resta la chat. Il
conto va detto per intero perché è il vero costo della fase, e perché è
esattamente il tipo di crescita che il resto della migrazione ha evitato: la
Fase 10 è la prima che aggiunge prodotto invece di spostarlo.

---

## 1. Perimetro

### 1.1 Enunciato di fase

| Requisito | Fonte |
| --- | --- |
| Branch `migration/phase-10-ai-service` | `docs/MIGRATION_PHASE_1_BACKLOG.md:542` |
| Provider AI reale via Edge Function proxy, rate-limit lato server, chiave e budget fuori dal repository | `docs/MIGRATION_PHASE_1_BACKLOG.md:544-546` |
| `AiService` dietro Edge Function / provider astratto; **nessuna chiave segreta deve raggiungere il browser** | `CONTESTO_IA/02_STORIA_FASI.md`, sezione «Fase 10 — AI reale» |
| «`AiService` reale via Edge Function», dominio con migrazione prevista | `docs/ROADMAP_V1.md:87` |
| Dominio «AI reale» non migrato | `CONTESTO_IA/01_STATO_ATTUALE.md:143` |
| L'AI è la penultima fase: dopo di essa solo il cutover (11) | `CLAUDE.md`, sezione «Migration architecture» |

### 1.2 Rinvii lasciati dalle fasi precedenti

Come per la Fase 9, il perimetro non è scritto in un solo posto. Questi sono
tutti i rinvii che le fasi precedenti hanno lasciato alla 10, e ciascuno è un
pezzo di parità che la fase deve o ripristinare o dichiarare perduto.

| Rinvio | Fonte |
| --- | --- |
| Il pannello «Assistente AI» del passo Identificazione **non è stato portato** in `frontend-next`, perché chiama `/api/ai/listing-suggestion` sul backend FastAPI | `docs/MIGRATION_PHASE_1_BACKLOG.md:122-124` |
| `askListingAI` / `applyAiSuggestion` **rimossi** dal wizard di `frontend-next`, con rinvio esplicito alla Fase 10 scritto nel codice | `frontend-next/src/hooks/useSellWizard.ts:71-72` |
| Stessa rimozione dichiarata nell'intestazione della pagina `/vendi` | `frontend-next/src/app/vendi/page-client.tsx:45-46` |
| `SommelierChat` **non portato**: dipende dal layer servizi (`@/services/api-client`) che richiede un backend reale | `frontend-next/src/components/vinea/Layout.tsx:19-21` |
| Il Sommelier è **l'unica eccezione nota e documentata** al principio «nessun cambiamento di comportamento visibile rispetto a `frontend/`» | `docs/ROADMAP_V1.md:136-137` |
| Il pannello AI del wizard resta fuori fino alla Fase 10 | `CONTESTO_IA/02_STORIA_FASI.md:197` |
| «AI e suggerimenti appartengono alla Fase 10» — esclusione dichiarata dalla Fase 8 | `docs/PHASE_8_MESSAGING_NOTIFICATIONS_SPEC.md:27` |

Il punto 5 di questa tabella merita di essere letto due volte. La roadmap
riconosce il Sommelier come **l'unica** deviazione accettata dalla parità
comportamentale: portarlo, o dichiarare che non torna, è il debito più vecchio
che questa fase eredita.

### 1.3 Fuori perimetro, dichiarato

- **Il cutover (Fase 13, era la Fase 11 fino all'11 agosto 2026 e la Fase 12 fino
  al 16 agosto 2026).** Anche a Fase
  10 completa, `frontend/` + `backend/` restano la versione servita: la
  dismissione è una decisione separata
  (`docs/MIGRATION_PHASE_1_BACKLOG.md:606-612`).
- **Lo spegnimento delle rotte `/ai` del backend FastAPI.** Finché `frontend/` è
  servito, `SommelierChat.tsx`, `useSellWizard.ts` ed `esplora.tsx` continuano a
  chiamarle. La regola «un solo scrittore autorevole per dominio»
  (`CLAUDE.md`, sezione «Migration architecture») va interpretata qui: l'AI non
  ha uno stato scritto condiviso se non lo storico Sommelier, ed è esattamente
  su quello che la sezione 5 apre una decisione.
- **KYC, hardening operativo e revisione legale**, che
  `CONTESTO_IA/01_STATO_ATTUALE.md` tiene fuori da ogni fase di migrazione. La
  decisione 7.12 aggiunge una ragione per cui la revisione legale resta fuori e
  vincola: è il motivo per cui la moderazione AI si ferma al triage.
- **L'autonomia della moderazione AI oltre il triage** — decisione 7.12: nessuna
  azione eseguita dall'AI, nessuna identità «attore AI» nell'`audit_log`.

**Corretto dalla sessione dell'11 agosto 2026**: il pannello «Migliora lo sfondo
con IA» era dichiarato qui fuori perimetro perché oggi è simulato e renderlo
reale sarebbe una funzionalità nuova (2.6). La decisione 7.13 lo fa **entrare**
per eccezione esplicita, con PhotoRoom come opzione tecnica e un catalogo di
sfondi curato a mano.

---

## 2. Inventario del legacy, cioè cosa esiste davvero oggi

### 2.1 `backend/ai_provider.py` — l'interfaccia astratta esiste già

L'invariante «il provider AI è astratto e sostituibile» non è un obiettivo della
Fase 10: è **già implementato** nel legacy, ed è la forma che la fase deve
riprodurre, non inventare.

| Elemento | Righe | Cosa fa |
| --- | --- | --- |
| `AIProviderError` | `backend/ai_provider.py:10-11` | Errore di dominio unico, che nasconde l'errore del provider |
| `AIProvider` (Protocol) | `backend/ai_provider.py:14-16` | Due soli metodi: `stream_text` e `complete_text`, entrambi con `system`, `prompt`, `request_id` |
| `DisabledAIProvider` | `backend/ai_provider.py:19-27` | Fallisce chiuso: solleva `AIProviderError("Il servizio AI non è configurato")` |
| `OpenAIProvider` | `backend/ai_provider.py:30-72` | Adapter OpenAI; rifiuta di costruirsi senza chiave (`:33`) |
| `build_ai_provider` | `backend/ai_provider.py:75-85` | Fabbrica: `openai` o `disabled`, qualunque altro valore è `RuntimeError` |

Due dettagli che la Fase 10 deve conservare perché sono decisioni di sicurezza,
non stile:

- **Ogni eccezione del provider è convertita in `AIProviderError`**
  (`backend/ai_provider.py:56-57` e `:71-72`). Il messaggio del provider non
  raggiunge mai il client. È la stessa regola di `docs/SECURITY.md:193-194`:
  «gli errori interni sono registrati lato server e restituiti al client in
  forma generica».
- **`request_id` viene passato al provider come campo `user`**
  (`backend/ai_provider.py:49` e `:67`), costruito come
  `sommelier:{user.id}:{session_id}` (`backend/ai_routes.py:77`),
  `pairing:{user.id}:{uuid4}` (`:194`) o `listing:{user.id}:{uuid4}` (`:269`).
  È correlazione per abuso lato provider. **Contiene l'identificativo utente**:
  se il provider cambia, è un dato personale che esce verso un terzo, e va
  trattato come tale nella decisione 7.1.

### 2.2 `backend/ai_routes.py` — cinque rotte, tre funzionalità

| # | Metodo e percorso | Righe | Forma |
| --- | --- | --- | --- |
| 1 | `POST /ai/sommelier/chat` | `:47-108` | Streaming SSE (`text/event-stream`, `:106`) |
| 2 | `GET /ai/sommelier/history/{session_id}` | `:111-122` | JSON |
| 3 | `DELETE /ai/sommelier/history/{session_id}` | `:125-136` | JSON |
| 4 | `POST /ai/pairing` | `:181-223` | JSON con schema validato |
| 5 | `POST /ai/listing-suggestion` | `:251-279` | JSON con schema validato |

**Tutte e cinque richiedono autenticazione** (`Depends(current_user)` su ogni
handler; asserito da `backend/tests/test_ai_backend.py:17`,
`test_ai_routes_require_auth`) e **tutte e cinque consumano lo stesso bucket di
rate limit** (`_enforce_ai_limit`, `backend/ai_routes.py:26-38`, chiamata come
prima istruzione di ogni handler).

I vincoli scritti in ciascuna, che sono il contratto da riprodurre:

**Chat Sommelier** (`:47-108`)
- `session_id` vincolato a 4-64 caratteri e all'alfabeto `^[A-Za-z0-9_-]+$`
  (`:43`); `message` a 1-2000 caratteri (`:44`); `extra="forbid"` (`:42`).
- Il contesto inviato al provider è **solo la coda** dello storico:
  `messages[-sommelier_context_messages:]` (`:56`), non tutta la conversazione.
- La risposta è **troncata mentre viene emessa**: un contatore
  `remaining_chars` parte da `sommelier_max_response_chars` e interrompe lo
  stream (`:72`, `:79-87`). Il tetto vale sia sui byte trasmessi sia su quelli
  salvati.
- Su `AIProviderError` lo stream emette un evento di errore **generico** e
  termina senza salvare nulla (`:88-90`).
- Solo a stream concluso e non vuoto l'scambio viene persistito (`:92-101`).

**Abbinamento** (`:181-223`)
- Il **catalogo candidato è inviato dal client**: `PairingRequest.catalog`,
  da 1 a 60 voci (`:148`), costruito nel browser da
  `frontend/src/routes/esplora.tsx:102-105`.
- Il modello deve rispondere JSON puro; `_extract_json` (`:168-178`) tollera un
  blocco ```` ``` ```` e, in seconda battuta, cerca il primo oggetto graffato.
- **L'output del modello è validato contro l'input**: ogni `wine_id` proposto
  deve appartenere al catalogo inviato ed essere unico (`:202-220`), e se i
  vini validi non sono esattamente `min(3, len(catalog))` la richiesta fallisce
  con 502 (`:221-222`). Il modello non può introdurre un vino che non esiste.
- Mappatura errori: provider giù → 503 (`:197-198`); JSON malformato → 502
  (`:199-200`).

**Suggerimento di catalogazione** (`:251-279`)
- Accetta `ocr_text` (≤ 2000) **oppure** `hint` (≤ 500), e rifiuta con 400 se
  mancano entrambi (`:228-229`, `:258-259`).
- La risposta è tipizzata con nove campi e `confidence` vincolata a `[0,1]`
  (`:232-241`); i campi assenti prendono il default invece di far fallire la
  chiamata (`:272`).
- Il prompt di sistema dice esplicitamente «Non inventare dati non deducibili»
  (`:247`).

### 2.3 Lo storico Sommelier: dove vivono ownership, tetto e TTL

`CLAUDE.md` elenca fra gli invarianti di sicurezza trasversali: «Sommelier chat
history, orders, and transactions are readable only by their owner or an
explicitly authorized role; history has ownership, a max message count, and a
TTL». Nel legacy quell'invariante è realizzato in tre righe precise, ed è utile
sapere quali perché sono le tre cose che una versione Postgres deve rifare:

| Proprietà | Dove | Come |
| --- | --- | --- |
| Ownership | `backend/repositories.py:194` | Indice **unico** su `(owner_id, session_id)`; ogni lettura filtra su entrambi (`:198-201`) |
| Tetto messaggi | `backend/repositories.py:223` | `$push` con `$slice: -max_messages`: la finestra è mantenuta dall'operazione di scrittura, non da una pulizia successiva |
| TTL | `backend/repositories.py:195` e `:224` | Indice TTL su `expires_at` con `expireAfterSeconds=0`, e ogni scrittura riporta `expires_at` a `now + ttl_days` |

Il `session_id` **è scelto dal client**: nasce in `localStorage` da
`Math.random()` (`frontend/src/components/vinea/SommelierChat.tsx:12-25`, in
particolare `:19`). Oggi questo **non** è un buco, perché la chiave di lettura è
la coppia `(owner_id, session_id)` e `owner_id` viene dal token, non dal corpo
della richiesta: indovinare un `session_id` altrui non serve a niente.

Diventa un buco nel momento in cui una versione Postgres tenesse la riga
identificata dal solo `session_id`. Questo è precisamente il caso che le regole
di esposizione della sezione 4.3 esistono per impedire, e va scritto nella spec
di implementazione come vincolo, non lasciato all'attenzione di chi scrive la
migrazione.

Conseguenza collaterale già vera oggi, da registrare come parità: **svuotare il
`localStorage` perde la conversazione**, perché il client non ha modo di
elencare le proprie sessioni — non esiste una rotta che le enumeri.

### 2.4 Il rate limit AI attuale

- Chiave unica per utente e **condivisa fra tutte e cinque le rotte**:
  `ai:user:{user.id}` (`backend/ai_routes.py:29`). Non c'è un bucket per
  funzionalità: una raffica di abbinamenti consuma il budget della chat.
- Valori: `AI_RATE_LIMIT=20` richieste, `AI_RATE_WINDOW_SECONDS=60`
  (`backend/.env.example:44-45`, `docs/ENVIRONMENT.md:195-196`).
- Superato il limite: 429 con header `Retry-After`
  (`backend/ai_routes.py:33-38`), asserito da
  `backend/tests/test_ai_backend.py:120`.
- Due implementazioni dietro un Protocol (`backend/rate_limit.py:20-21`):
  `InMemoryRateLimiter` (`:24`) e `MongoRateLimiter` (`:42`).
  `docs/SECURITY.md:154-155` avverte che quello in memoria regge una sola
  istanza e che un deployment orizzontale richiede storage condiviso e atomico.

### 2.5 I tre punti di consumo in `frontend/`

| Chiamante | Riga | Cosa invia |
| --- | --- | --- |
| `SommelierChat.tsx` | `:51` GET storico, `:81` POST chat, `:155` DELETE storico | `session_id` da `localStorage`; parsing dei chunk con `sommelierChunkSchema` (`:109`) |
| `useSellWizard.ts` | `:63-67` | **Solo `hint`**, mai `ocr_text` |
| `esplora.tsx` | `:106-110` | `query` più il catalogo costruito nel browser (`:102-105`) |

I quattro schemi Zod di risposta sono in
`frontend/src/services/api-contracts.ts`: `pairingSchema` (`:16-24`),
`listingSuggestionSchema` (`:26-36`), `sommelierHistorySchema` (`:44-46`),
`sommelierChunkSchema` (`:48-51`). Sono il contratto client già scritto, e la
Fase 10 può riusarli come definizione della forma di risposta attesa.

Una nota di comportamento che la parità deve considerare: **il pannello del
Sommelier è montato per chiunque**, senza gate di sessione
(`frontend/src/components/vinea/Layout.tsx:19` e `:255`), mentre l'API richiede
autenticazione. Un visitatore anonimo apre il pannello, scrive, e riceve un 401.

### 2.6 Ciò che si chiama AI e non lo è

`SfondoIAPanel` — il pannello «Migliora lo sfondo con IA» del passo Foto
(`frontend/src/routes/vendi.tsx:214-215`) — **non chiama nessun servizio**: è un
`setTimeout` di 1100 ms seguito da un toast che dice «Sfondo applicato (demo)»
(`frontend/src/routes/vendi.tsx:569-579`).

È per questo che il backlog l'ha portato in `frontend-next` mentre lasciava
indietro l'Assistente AI: «è invece portato perché in `frontend/` è già
interamente simulato e non chiama nessun servizio»
(`docs/MIGRATION_PHASE_1_BACKLOG.md:124-125`).

**La decisione 7.13 lo fa entrare nella Fase 10**, e con una conseguenza che va
detta qui perché è il contrario di ciò che questa sezione concludeva nella prima
stesura: il debito non va sulla lista di cutover accanto a
`bottle_units.visibilita`, **si chiude con la 7.13** — che il checkpoint unico
della Fase 10 ha lasciato fuori, quindi si chiude nella Fase 11. Oggi la UI promette
all'utente uno sfondo che non viene mai applicato; dalla 7.13 in poi o viene
applicato davvero, o il pannello va tolto. La terza via — lasciarlo lì a
promettere — è quella che la decisione ha scartato.

Due conseguenze tecniche della 7.13, che non sono decisioni ma discendono da
essa: PhotoRoom **non è un provider di modelli linguistici**, quindi non entra
nell'astrazione `AIProvider` della 2.1 e porta con sé una seconda chiave di
natura diversa (7.11); e il catalogo di sfondi curati è un insieme di immagini
che deve stare da qualche parte, cioè uno Storage bucket con le sue policy, che
la decisione non nomina.

### 2.7 Riepilogo: cosa la Fase 10 può migrare e cosa dovrebbe inventare

Aggiornata con le decisioni dell'11 agosto 2026. La colonna «Migrazione o
novità» è la sola che quelle decisioni hanno cambiato: nessuna di esse ha
cambiato che cosa esiste.

| Funzionalità | Esiste in `frontend/`? | Ha uno stato persistente? | Migrazione o novità |
| --- | --- | --- | --- |
| Chat Sommelier | Sì, completa con storico | **Sì** — storico su MongoDB | Migrazione, ed è l'unica con dati da spostare |
| Abbinamento cibo-vino | Sì | No, richiesta senza stato | Migrazione |
| Suggerimento catalogazione da testo | Sì | No, richiesta senza stato | Migrazione |
| Autofill catalogo da foto etichetta (7.3a) | **No** | No | **Novità ammessa** per eccezione |
| Spunta di completezza documentale (7.3b) | **No** | **Sì** — l'esito sta sull'annuncio | **Novità ammessa** per eccezione |
| Triage di moderazione (7.12) | **No** | Da decidere, vedi 7.12 | **Novità ammessa**, senza azione autonoma |
| Ritaglio e sfondo reale (7.13) | Simulata, già portata | No | **Novità ammessa** per eccezione |

Una riga di questa tabella merita attenzione perché contraddice la lettura
comoda della sezione 5: **7.3b ha uno stato persistente**. La spunta di
completezza è un attributo dell'annuncio, e un attributo dell'annuncio è una
colonna. Non è la sola funzionalità con dati, quindi, e la sezione 5 va letta
come «dove vive lo storico», non come «l'unico punto in cui la fase tocca lo
schema».

---

## 3. Cosa esiste già lato target — la risposta è: niente

Questa è la differenza più importante rispetto alla Fase 9, che partiva con
l'interfaccia `ModerationService` già scritta e da riempire.

- **Non esiste un'interfaccia `AiService`.**
  `frontend-next/src/services/types.ts` è lungo 996 righe e l'ultima interfaccia
  dichiarata è `ModerationService` (`:970`). Nessuna interfaccia AI, nessun tipo
  di richiesta o risposta AI, nessun riferimento al Sommelier.
- **Non esiste un adapter né una directory di fase.**
  `frontend-next/src/services/` contiene `auth-service.ts`, `cellar-service.ts`,
  `listing-service.ts`, `wine-meta.ts`, `types.ts` e le cartelle `phase7/`,
  `phase7c/`, `phase8/`, `phase9/`. Non c'è `phase10/`.
- **Non esiste nessuna Edge Function AI**, né nel repository né sul progetto
  reale (vedi 0.1). `supabase/config.toml:385-396` dichiara le tre function
  esistenti e nessun'altra.
- **`frontend-next` non chiama l'AI da nessuna parte.** Una ricerca di
  `/api/ai` su tutto `frontend-next/src` restituisce **una sola occorrenza**, ed
  è un commento che rinvia alla Fase 10
  (`frontend-next/src/hooks/useSellWizard.ts:72`).
- **Non esiste una variabile d'ambiente AI lato target.**
  `frontend-next/.env.example` copre Supabase, Stripe, Connect e il job di
  rilascio; nessuna riga riguarda l'AI.

La Fase 10 parte quindi da zero su tre livelli — interfaccia, adapter, Edge
Function — mentre la Fase 9 ne aveva già uno. Questo va tenuto presente nella
stima della sezione 8.

---

## 4. Pattern già vincolanti, da riusare e non reinventare

### 4.1 Il pattern delle Edge Function

`payments-checkout` è la forma canonica, e ogni riga ha una ragione:

| Passo | Riga | Perché |
| --- | --- | --- |
| Origine verificata prima di tutto | `supabase/functions/payments-checkout/index.ts:104-105` | `corsHeadersFor` restituisce `null` per origini non in allowlist → 403 |
| `OPTIONS` → 204, metodo diverso da `POST` → 405 | `:106-107` | Superficie minima |
| Flag di funzionalità → 503 | `:108-109` | `PAYMENTS_ENABLED` spegne la funzione senza rimuoverla |
| Bearer estratto dalla richiesta | `:112-116` | 401 se assente o malformato |
| **Client di servizio costruito dall'env della function** | `:119` | `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`; il browser non li vede mai |
| Identità risolta dal token, non dal corpo | `:122-123` | `supabase.auth.getUser(accessToken)` → 401 se non valido |
| Il lavoro passa da una RPC | `:135` | L'autorizzazione vive in database |
| `verify_jwt = true` | `supabase/config.toml:386` | Il gateway rifiuta prima di eseguire |

L'allowlist CORS è un insieme di **origini complete**, non sottostringhe, letto
da `PAYMENT_ALLOWED_ORIGINS` (`supabase/functions/_shared/cors.ts:1-18`), con
`Vary: Origin` (`:16`). Coerente con `docs/SECURITY.md:144-147`.

`docs/SECURITY.md:167-169` fissa la regola generale: «la `service_role` resta
confinata a Edge Function e Route Handler, non è un meccanismo client». È lo
stesso motivo per cui la 9c ha messo `order_checkout_reserve` dietro
`payments-checkout` invece di esporla al browser.

**Decisione aperta 7.6** discute se le origini AI condividano
`PAYMENT_ALLOWED_ORIGINS` o abbiano una variabile propria.

### 4.2 Il rate limit lato server esiste già ed è pronto

Il backlog chiede «rate-limit lato server». Esiste, è in produzione dalla Fase 7
e non va riscritto:

- `private.rate_limit_buckets`
  (`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:10-24`):
  RLS attiva, ogni privilegio revocato da `public`, `anon`, `authenticated`
  (`:20-21`), indice su `expires_at` (`:23-24`).
- `private.rate_limit_consume(scope, subject, limit, window_seconds)`
  (`:26-90`): finestra fissa allineata (`:48-51`), incremento atomico via
  `on conflict … do update` (`:59-61`), e al superamento un errore `PGRST` che
  PostgREST traduce in **429 con `Retry-After` calcolato** (`:63-81`). La
  pulizia è opportunistica e non richiede `pg_cron` (`:83-86`) — coerente con la
  decisione 1a della Fase 7d, che esclude `pg_cron`.
- **`public.rate_limit_consume` è già esposta a `service_role` e a nessun altro**
  (`:143-160`: `revoke … from public, anon, authenticated` a `:157-158`,
  `grant … to service_role` a `:159-160`). Cioè: **una Edge Function con client
  di servizio può già consumare un bucket via `rpc()` senza nessuna nuova
  migrazione.** È la porta che serve alla Fase 10, e c'è.

Gli `scope` già in uso danno la convenzione di nomenclatura e l'ordine di
grandezza dei valori. I nomi di file della colonna «Fonte» sono abbreviati e
stanno tutti in `supabase/migrations/`:

| Scope | Limite / finestra | Fonte |
| --- | --- | --- |
| `proposal:send`, `proposal:counter`, `proposal:accept`, `proposal:reject` | 20 / 60 s | `20260731135455_…:401`, `:443`, `:476`, `:512` |
| `checkout` | 10 / 60 s | `20260731135455_…:557` |
| `order:delivered`, `order:prepare`, `order:ship`, `order:packaging`, `listing:packaging` | 30 / 60 s | `20260803150000_…:1092`, `20260804160000_…:869`, `:942`, `:1254`, `:471` |
| `order:confirm` | 20 / 60 s | `20260803150000_…:1140` |
| `order:dispute`, `order:review` | 10 / 60 s | `20260803150000_…:1187`, `20260804160000_…:1188` |
| `report:submit` | **10 / 3600 s** | `20260810152000_…:524` |

Da notare che la Fase 9 ha introdotto la prima finestra oraria anziché al
minuto. Un budget AI è più vicino a quel caso che al checkout: **decisione
aperta 7.4**.

### 4.3 Le regole di esposizione Postgres

Se la Fase 10 persiste qualcosa — e lo storico Sommelier è persistenza — valgono
integralmente le tre regole vincolanti da 6d-1 (`CLAUDE.md`, sezione «Postgres
exposure rules»):

1. Nessun `GRANT SELECT` di tabella intera a un ruolo che può raggiungere righe
   non proprie.
2. Le letture passano da una vista `security_invoker = off` a colonne chiuse.
   Per le letture della **propria** riga il modello è `my_reports` /
   `my_listing_moderation` della 9a.
3. Una colonna con una regola di dominio dietro non è scrivibile dal client:
   esce dal `GRANT` e ottiene una `SECURITY DEFINER` come unica porta.

Applicate allo storico Sommelier, queste tre regole dicono già quasi tutto:
`owner_id` non è scrivibile dal client, la riga si legge attraverso una vista
filtrata su `auth.uid()`, e l'unica porta di scrittura è la funzione che
aggiunge lo scambio. Vale anche l'avvertenza della 9b: se si aggiunge una
colonna a una tabella che ha un `GRANT UPDATE` di tabella intera, quel grant va
ristretto **nello stesso momento**.

### 4.4 Gli invarianti AI già scritti

`docs/SECURITY.md:189-197` elenca sei invarianti già in vigore. Non sono
obiettivi da riscoprire: sono il criterio con cui la Fase 10 verrà giudicata.

| Invariante | Dove è già realizzato oggi |
| --- | --- |
| Prompt e output hanno limiti di dimensione | `backend/ai_routes.py:43-44`, `:148`, `:228-229`, `:79-87` |
| Il provider ha timeout controllati | `AI_TIMEOUT_SECONDS`, `backend/ai_provider.py:36` |
| Gli errori interni sono generici verso il client | `backend/ai_provider.py:56-57`, `backend/ai_routes.py:88-90`, `:197-200` |
| Il provider è astratto e sostituibile | `backend/ai_provider.py:14-16`, `:75-85` |
| Lo storico ha ownership, limite massimo e TTL | `backend/repositories.py:194`, `:223`, `:195` |
| Le risposte non certificano autenticità o valore | `backend/ai_routes.py:21-22`, `:247` (prompt di sistema) |

L'ultimo è l'unico realizzato **solo** dal prompt di sistema, cioè da qualcosa
che il modello può disattendere. Il legacy compensa nell'abbinamento validando
gli `id` proposti contro il catalogo inviato (`backend/ai_routes.py:202-222`) —
è un buon precedente: dove si può, il vincolo si verifica in codice invece che
chiederlo al modello.

Quell'invariante diventa più difficile con la decisione 7.3b, e va segnalato qui
perché è la sezione che lo enuncia: finora «non certificare autenticità» valeva
per un testo generato, dove l'affermazione è del modello. La spunta di
completezza è un elemento di interfaccia che il prodotto mostra come proprio, e
un utente non distingue «le foto richieste ci sono tutte» da «questa bottiglia è
autentica» se non glielo si dice. Lì il vincolo non si verifica in codice: si
verifica nella scelta delle parole, ed è la ragione per cui la 7.3 lo scrive come
parte della decisione e non come nota di stile.

---

## 5. Dove vive lo storico Sommelier — deciso: A

Delle tre funzionalità migrabili, due sono richieste senza stato: un proxy che
autentica, limita, chiama il provider e restituisce. Lo storico Sommelier è
l'unica delle tre che ha dati, e quindi quella che tocca lo schema, RLS, i grant
e la regola «un solo scrittore autorevole per dominio».

**La sessione dell'11 agosto 2026 ha scelto A: tabella Postgres in Supabase.**
La motivazione registrata è di prodotto e non di architettura — un consulente a
cui si torna a parlare deve ricordare la conversazione, e nessuna persistenza
sarebbe un peggioramento rispetto a ciò che `frontend/` fa oggi.

Le due strade scartate restano scritte perché una decisione senza le alternative
che ha escluso non è riapribile in modo onesto. **B — nessuna persistenza, la
conversazione vive nel browser**: costo zero di schema e TTL che sparisce, ma
perdita di parità rispetto a `frontend/`, dove lo storico sopravvive alla
ricarica. **C — il Sommelier non viene portato in Fase 10**: le due funzionalità
senza stato migrano e la chat resta su `frontend/` fino al cutover, lasciando
dichiarato il debito già dichiarato in `docs/ROADMAP_V1.md:136-137`.

### 5.1 Che cosa costa A, adesso che è scelta

Una migrazione con tabella, RLS, vista di lettura a colonne chiuse, una
`SECURITY DEFINER` per l'append con il tetto messaggi, e una strategia di TTL.
Le prime quattro sono lavoro noto e hanno un modello in casa. **Il TTL no**, ed
è l'unico punto della decisione A che non ha ancora una risposta: Mongo lo
ottiene con un indice (`backend/repositories.py:195`), Postgres non ha
l'equivalente, e `pg_cron` è **escluso** dalla decisione 1a della Fase 7d, non
rinviato. Le tre strade praticabili:

| Strada | Modello in casa | Il costo vero |
| --- | --- | --- |
| Cancellazione opportunistica alla scrittura | `rate_limit_consume` (`20260731135455_…:83-86`) | Una conversazione mai più toccata non scade mai: il TTL vale per chi torna, non per chi sparisce — ed è chi sparisce che il TTL dovrebbe proteggere |
| Secondo job GitHub Actions | La 7g | Aggiunge un secondo workflow schedulato a uno che oggi è a 18 run su 18 in `failure` (8.3) |
| Scadenza applicata in lettura | Il filtro `expires_at > now()` dentro la vista | I dati restano in tabella: nasconde, non cancella. Se il TTL è una promessa di cancellazione, questa non la mantiene |

Nessuna è gratis e nessuna è ovvia, e le tre producono schemi diversi: non era un
dettaglio implementativo che si aggiusta dopo.

> **Deciso (11 agosto 2026): la terza — scadenza applicata in lettura.** La vista
> di lettura filtra su `expires_at`, e **nessuna cancellazione fisica è
> pianificata per il v0**. Va scritto esplicitamente nella spec di implementazione
> e nel codice che **le righe scadute restano a tabella** finché non arriva una
> pulizia futura: è una decisione consapevole, non un buco lasciato aperto.

La strada scelta è quella la cui obiezione — «nasconde, non cancella» — è la sola
delle tre che si può **dichiarare** invece di subire. Le altre due hanno un difetto
che agisce di nascosto: la cancellazione opportunistica non scade mai una
conversazione abbandonata, cioè proprio il caso che il TTL dovrebbe coprire, e il
secondo job Actions aggiunge uno schedulatore a uno che è a 18 run su 18 in
`failure`. Qui il difetto è visibile in una riga di documentazione, e la pulizia
futura è un lavoro che si può aggiungere senza cambiare lo schema.

**Conseguenza della 7.2 = A sul resto della fase:** la Fase 10 contiene SQL.
Cade quindi l'ipotesi, contemplata dalla prima stesura, di una fase interamente
reversibile e senza migrazioni, e con essa cade il ragionamento della 8.2 su
quello scenario. Le due decisioni che ne discendono sono la 7.7 (lo streaming è
più difficile con la persistenza) e la 7.10 (con una migrazione, il gate di
autorizzazione serve davvero).

---

## 6. Suddivisione in sotto-fasi

Riscritta dopo le decisioni dell'11 agosto 2026, che hanno portato il perimetro
da tre funzionalità a sette, e **confermata dalla sessione che ha chiuso le otto
restanti**: il primo checkpoint è **10a + 10b insieme**, e le quattro
funzionalità nuove restano fuori. La sessione dell'11 agosto 2026 vi ha poi
aggiunto la **10c** — stesso branch, stessa PR, sul modello della Fase 9, dove
9a/9b/9c sono stati tre checkpoint dentro un solo PR mersato una volta a fine
fase. La ragione registrata è che sono meno
specificate — Storage, MIME, integrazione PhotoRoom, forma esatta dell'esito del
triage sono decisioni di dettaglio non ancora scritte — e **ciascuna merita la
propria sessione di spec prima del codice**, sul modello dei 9a/9b/9c separati
della Fase 9.

| | Contenuto | SQL? | Che cosa serve prima | Stato |
| --- | --- | --- | --- | --- |
| **10a** | La porta: una Edge Function proxy sul pattern di 4.1 — origine, metodo, flag, bearer, `auth.getUser`, bucket via `public.rate_limit_consume`, provider dietro adapter, risposta validata. Copre abbinamento e suggerimento da testo. Porta l'interfaccia `AiService` in `frontend-next/src/services/types.ts` e l'adapter | No | 7.4, 7.5, 7.6, 7.8, 7.9, 7.11 | **Consegnata** — PR #35 |
| **10b** | Lo storico e la chat: migrazione, RLS, vista a colonne chiuse, `SECURITY DEFINER` di append con il tetto messaggi, scadenza applicata in lettura (5.1), rotta chat SSE | **Sì** | 10a, più la 7.7 | **Consegnata** — PR #35, migrazione applicata |
| **10c** | Il ripristino UI: pannello Assistente nel wizard di vendita, pannello Sommelier nel Layout, pannello abbinamento in `/esplora` — senza quest'ultimo `ai-pairing` resta senza chiamante e la 7.8 senza superficie | No | 10a + 10b | **Consegnata** — PR #35 |
| ~~10d~~ → **Fase 11** | La visione: autofill da foto (7.3a) e spunta di completezza (7.3b). La spunta è un attributo dell'annuncio, quindi **una seconda migrazione** | **Sì** | sessione di spec propria, più la scelta del provider di visione (7.1) | Non iniziata |
| ~~10e~~ → **Fase 11** | Lo sfondo (7.13): relay verso PhotoRoom, bucket Storage per gli sfondi curati, e la sostituzione del `setTimeout` di `SfondoIAPanel` | Probabile — policy di Storage | sessione di spec propria | Non iniziata |
| ~~10f~~ → **Fase 11** | Il triage di moderazione (7.12): classificatore, e la **colonna persistita su `reports`** decisa insieme alla 7.12 — quindi una migrazione | **Sì** | sessione di spec propria, e il pannello della Fase 9 esercitato almeno una volta su una sessione reale | Non iniziata |

**Perché in quest'ordine, e non per interesse.** 10a stabilisce il contratto e il
costo reale di una chiamata al provider senza toccare lo schema: è la parte
reversibile, ed è quella che dice se i numeri della 7.4 sono giusti. 10b viene
subito dopo perché è **parità dovuta**, non aggiunta.

Poi vengono le quattro funzionalità nuove, e vengono dopo per una ragione che va
scritta: se la fase si allunga, ciò che si taglia è quello che è stato aggiunto,
non quello che era dovuto. Mettere la visione prima dello storico significherebbe
poter finire la Fase 10 con un prodotto più ricco di `frontend/` su un fronte e
più povero su un altro — che è il modo esatto in cui un cutover si blocca.

10f è ultima anche per un motivo indipendente: il pannello di moderazione della
Fase 9 esiste in produzione ma **nessun suo comportamento vi è mai stato
esercitato** (`CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 9 — decisioni
organizzative»). Aggiungere un classificatore che ordina una coda che nessuno ha
ancora visto funzionare è costruire sul non verificato.

`MIN_TESTS` in CI era a **204** quando questa sezione è stata scritta ed è a
**255** dal merge della PR #35 (`.github/workflows/ci.yml:99`): come in ogni fase
precedente va alzato deliberatamente quando i test aumentano.

**Come è andata a finire.** I primi tre checkpoint sono stati consegnati insieme
nella PR #35 e la fase si è chiusa lì. Gli ultimi tre non sono stati costruiti e
**non sono più Fase 10**: sono diventati la **Fase 11 — estensioni AI ammesse per
eccezione**, non iniziata e senza branch, e il cutover è diventato la Fase 12. La
ragione registrata qui sopra — sono meno specificate, e ciascuna merita la propria
sessione di spec — è la stessa che ha portato a separarle anche di numero invece
di lasciarle come coda aperta di una fase dichiarata chiusa.

---

## 7. Decisioni

**Tutte e tredici chiuse dalla sessione organizzativa dell'11 agosto 2026**, in
due tempi: prima 7.1, 7.2, 7.3, 7.12 e 7.13; poi, letto il resoconto delle
proposte, dalla 7.4 alla 7.11 più i due punti conseguenti. Non si riaprono senza
tornare a quella sessione, con la stessa regola delle dieci decisioni della
Fase 9.

**L'ordine di questa sezione non è numerico**: vengono prima le cinque chiuse nel
primo tempo — 7.1, 7.2, 7.3, 7.12, 7.13 — e poi le otto del secondo, dalla 7.4
alla 7.11. Ognuna porta la risposta in blocco citato e, sotto, la proposta con cui
era stata istruita: dove le due divergono la divergenza è segnalata, perché sapere
che cosa è stato scartato e perché vale più della risposta da sola. La
numerazione è quella originale della prima stesura e non è stata rifatta, perché
le decisioni vengono citate per numero altrove.

### 7.1 Quale provider, e a chi escono i dati — CHIUSA (11 agosto 2026)

**Non un solo fornitore: uno per compito.** L'astrazione `AIProvider` del legacy
(`backend/ai_provider.py:14-16`) regge nativamente più di un provider e non va
forzata a uno solo.

| Compito | Provider | Stato della scelta |
| --- | --- | --- |
| Chat Sommelier | GPT-5 | **Preferenza, da confermare** con 5-6 conversazioni reali prima di fissarla |
| Foto: autofill 7.3a e completezza 7.3b | Claude o Gemini | **Da scegliere provandoli su foto vere di etichette**, non su un benchmark generico |
| Triage di moderazione 7.12 | Il livello più economico disponibile (Haiku, GPT-5-mini, Gemini Flash o equivalente) | Chiusa nel criterio: qui **il volume conta più della qualità** |

Il metodo di prova è parte della decisione, non un suggerimento. Per la chat:
5-6 conversazioni realistiche — un regalo per un'occasione, un abbinamento per
una cena, una domanda su un vino sconosciuto — fatte girare anche solo a mano,
fuori da qualunque migrazione, su GPT-5 e su un'alternativa (Claude Sonnet 5), e
la scelta si fa sul risultato. Per le foto: vetro, curvatura, luce non perfetta,
non documenti puliti. **Finché queste prove non sono state fatte, la 10a e la 10c
non hanno il loro provider**, e questo è un blocco reale sulla suddivisione della
sezione 6.

Tre conseguenze che la decisione lascia scoperte e che vanno risolte in fase di
implementazione:

- **Il `request_id` contiene l'identificativo utente** (`backend/ai_routes.py:77`,
  `:194`, `:269`) e viene passato al provider come campo `user`
  (`backend/ai_provider.py:49`, `:67`). Con un solo provider era un dato che
  usciva verso un terzo; con tre o quattro è lo stesso dato verso tre o quattro.
  La 7.1 non ha deciso se resta così o diventa un identificativo opaco.
- **Più provider significa più chiavi**, e la 7.11 va letta al plurale.
- **PhotoRoom (7.13) non è in questa tabella** perché non è un provider di
  modelli linguistici: non passa dall'astrazione `AIProvider` e ha una chiave sua.

### 7.2 Lo storico Sommelier — CHIUSA (11 agosto 2026): A, tabella Postgres

Vedi sezione 5 per la motivazione registrata e le alternative scartate, e la 5.1
per ciò che la decisione **non** chiude: **come si applica il TTL**, dato che
`pg_cron` è escluso dalla decisione 1a della Fase 7d. Le tre strade praticabili
producono schemi diversi, quindi la risposta serve prima della migrazione e non
dopo.

Questa decisione stabilisce che **la Fase 10 scrive SQL.**

### 7.3 Identificazione bottiglia — CHIUSA (11 agosto 2026): dentro, per eccezione

Il backlog nomina `ai-identify-bottle` (`docs/MIGRATION_PHASE_1_BACKLOG.md:544`)
ma nel prodotto servito non esiste nessun percorso foto → etichetta (vedi 0.2):
portarla è una funzionalità nuova, e le funzionalità nuove sono vietate durante
la migrazione. **La sessione l'ha ammessa come eccezione esplicita**, e l'ha
sdoppiata: non è una funzionalità, sono due.

**7.3a — autofill dei campi catalogo da foto dell'etichetta.** Il venditore
fotografa l'etichetta, l'AI propone produttore, annata, regione e gli altri campi.
È l'erede diretto del «suggerimento di catalogazione» del legacy
(`backend/ai_routes.py:251-279`) con una foto reale al posto dei campi testuali
`ocr_text`/`hint` (`:228-229`). Resta un **suggerimento**: i nove campi tipizzati
e il `confidence` in `[0,1]` (`:232-241`) sono già la forma giusta, e il default
sui campi assenti (`:272`) è già il comportamento giusto.

**7.3b — spunta di completezza documentale.** Alla pubblicazione l'AI verifica
che le foto coprano il prodotto per intero — etichetta, livello, tappo — e in
caso affermativo l'annuncio mostra una spunta di completezza. Stessa chiamata di
visione della 7.3a, output diverso: **le due condividono la Edge Function.**

**Il vincolo di onestà è parte della decisione, non una raccomandazione:** la
spunta va etichettata come completezza documentale e **mai** come autenticità
certificata. Nessuna AI può certificare l'autenticità di una bottiglia da una
fotografia. Questo si aggancia a un invariante già in vigore — «le risposte non
certificano autenticità o valore» (`docs/SECURITY.md:189-197`, realizzato oggi
dal solo prompt di sistema, `backend/ai_routes.py:21-22`, `:247`) — e lo rende
più difficile da rispettare, perché stavolta l'affermazione non è in un testo
generato ma in un elemento di interfaccia che il prodotto mostra come proprio.

Due conseguenze tecniche che la decisione non nomina e che discendono da essa:

1. **La spunta è un attributo persistente dell'annuncio**, quindi una colonna, e
   una colonna con una regola di dominio dietro. Per la terza regola di
   esposizione (4.3) **non è scrivibile dal client**: esce dal `GRANT` e ottiene
   una `SECURITY DEFINER` come unica porta. Un venditore che possa scriversi da
   solo la spunta di completezza l'ha resa priva di significato.
2. **Una foto richiede Storage, dimensione massima, tipo MIME**, e ha un costo
   per chiamata diverso da quello del testo — che è la ragione per cui la 7.4
   propone un bucket separato per la visione.

### 7.12 Moderazione AI — CHIUSA (11 agosto 2026): solo triage, nessuna azione

**Per il lancio v0 l'AI classifica e ordina, non decide.** Il classificatore
lavora dentro il pannello di moderazione della Fase 9 già esistente e un
moderatore umano preme sempre il bottone finale. Nessuna nuova RPC di esecuzione,
**nessuna identità «attore AI» nell'`audit_log`**: non serve, perché l'AI non
scrive niente di moderazione.

L'autonomia parziale discussa in una sessione precedente — tutto tranne la
rimozione, con escalation umana alla seconda riapertura — **è rinviata
esplicitamente, non decisa.** La motivazione registrata è che gli obblighi di
trasparenza dell'AI Act, in vigore dal 2 agosto 2026, e del DSA sulle decisioni
automatizzate rendono quella forma più rischiosa, e che richiede prima una
revisione legale che questa fase non fa — coerente con la 1.3, che tiene la
revisione legale fuori da ogni fase di migrazione.

**Il punto conseguente che la 7.12 apriva è chiuso, non aperto.** La decisione
7.12 vincola che cosa l'AI può fare, non dove finisce ciò che produce; dove
finisce lo ha deciso la stessa sessione dell'11 agosto 2026, ed è **persistito
accanto alla segnalazione, non ricalcolato a ogni apertura del pannello**: una
colonna su `reports` (o una tabella collegata), quindi **una migrazione**, con la
4.3 a governarne i grant. L'alternativa scartata era il ricalcolo a ogni
apertura — nessun SQL per la 7.12, ma una chiamata al provider per ogni
visualizzazione della coda. Registrato nella tabella di stato in testa a questo
documento e in `CONTESTO_IA/01_STATO_ATTUALE.md`, sezione «Fase 10 — decisioni
organizzative».

**La Fase 11 lo eredita chiuso**, e ci ha trovato dentro una domanda che nel
momento della decisione nessuno aveva misurato: `reports.priorita` **esiste già**,
è derivata da una regola di dominio deterministica e la coda è **già** ordinata su
di essa. Che rapporto abbia l'esito del triage con quella colonna — convivenza,
sostituzione, o un'altra cosa — è aperto e si decide lì, non qui:
`docs/PHASE_11_AI_EXTENSIONS_SPEC.md`.

### 7.13 Ritaglio e sfondo — CHIUSA (11 agosto 2026): dentro, per eccezione

**PhotoRoom** come opzione tecnica preferita, per il compositing su sfondo nativo
e non il solo cutout. Il **catalogo di sfondi è curato a mano da Enrico, non
generato al volo**: un piccolo insieme di immagini caricate una volta, e il
venditore sceglie se usarne una o tenere la propria foto.

Questa decisione fa entrare nella fase il pannello `SfondoIAPanel`, che la prima
stesura di questa spec dichiarava fuori perimetro (1.3 e 2.6) perché oggi è
interamente simulato — un `setTimeout` di 1100 ms e un toast «Sfondo applicato
(demo)» (`frontend/src/routes/vendi.tsx:569-579`). L'effetto collaterale è che il
debito «la UI promette una cosa che non accade» **non va sulla lista di cutover:
si chiude con la 7.13**, in un senso o nell'altro — e la 7.13 è restata fuori dal
checkpoint unico, quindi si chiude nella Fase 11.

Quello che la decisione non nomina e serve: il bucket Storage dove vivono gli
sfondi curati, con le sue policy; il limite di dimensione e il tipo MIME
dell'immagine in ingresso; e il fatto che la foto di un utente viene trasmessa a
un terzo diverso dai provider di modelli, il che porta PhotoRoom nella 7.11
accanto alle chiavi dei modelli e non al posto loro.

### 7.4 Budget e limiti numerici — CHIUSA (11 agosto 2026): un bucket per funzionalità, finestra oraria

Vincolante e già scritto: il rate limit sta lato server
(`docs/MIGRATION_PHASE_1_BACKLOG.md:545`) e i valori restano fuori dal
repository (`:545-546`).

> **Deciso.** Un bucket di rate limit **per funzionalità** — chat, abbinamento,
> catalogazione, e le foto quando entreranno — **non uno condiviso** come nel
> legacy. **Finestra oraria**, sul modello di `report:submit`
> (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524`, cioè
> `10, 3600`) introdotto dalla Fase 9, **non al minuto** come il checkout.
> **Nessun tetto aggiuntivo oltre al rate limit** per il lancio v0: un budget
> mensile è rimandabile a dopo il lancio se emerge la necessità. Il limite **vale
> anche per un ruolo `admin`**, nessuna eccezione.

**Due punti in cui la decisione ha corretto la proposta.** La proposta metteva
`ai:chat`, `ai:pairing` e `ai:catalogo` su finestra al minuto e teneva l'oraria
per le sole chiamate di visione: la decisione ha esteso l'oraria a tutto. E la
proposta aggiungeva un secondo bucket `ai:giorno` 100 / 86400 s consumato da ogni
funzionalità in aggiunta al proprio: **respinto**, non esiste un secondo tetto
nostro. Il tetto complessivo per il v0 è quello configurato **sul conto del
provider** (7.11), che è l'unico che protegge anche da una chiave uscita.

**Una conseguenza numerica che l'implementazione deve rendere visibile.** Il
legacy limita la chat a `AI_RATE_LIMIT=20` per 60 s (`backend/.env.example:44-45`);
`10 / 3600 s` è un ordine di grandezza più stretto, e una conversazione Sommelier
realistica è di cinque-quindici battute. Preso alla lettera, l'utente esaurisce il
bucket **dentro una conversazione sola**. La decisione ha fissato la **forma** —
finestra oraria, un bucket per funzionalità — e ha citato `10 / 3600` come
modello; i quattro numeri stanno perciò in **un solo punto del codice**, dichiarati
e modificabili con una riga, e `ai:chat` è quello che merita una conferma
numerica prima che la fase si accenda.

**La proposta, per intero — un bucket per funzionalità, non uno solo.** Il precedente è il
progetto intero: ogni operazione ha il suo `scope` (4.2), e nessuna fase ne ha
mai condiviso uno fra operazioni diverse. Il bucket unico del legacy
(`ai:user:{user.id}`, `backend/ai_routes.py:29`) ha già un difetto registrato
nella 2.4 — una raffica di abbinamenti consuma il budget della chat — e con la
7.3 il difetto peggiora, perché una chiamata di visione e una di testo non
costano lo stesso e un contatore unico non sa distinguerle.

| Scope proposto | Limite / finestra | Perché quel valore |
| --- | --- | --- |
| `ai:chat` | 20 / 60 s | Parità con `AI_RATE_LIMIT=20` (`backend/.env.example:44-45`); è la superficie conversazionale, dove una raffica è legittima |
| `ai:pairing` | 10 / 60 s | Forma `checkout` (`20260731135455_…:557`): azione deliberata, non ripetuta a raffica |
| `ai:catalogo` | 10 / 60 s | Stessa forma; è un passo di un wizard |
| `ai:visione` | **10 / 3600 s** | Forma `report:submit` (`20260810152000_…:524`), la finestra oraria introdotta dalla Fase 9. È la chiamata più cara e la meno ripetuta: un venditore fotografa una bottiglia una volta |
| `ai:sfondo` | **10 / 3600 s** | Stessa natura: immagine, provider a pagamento per chiamata |

**Quello che vale dopo la decisione** è la stessa tabella con la finestra portata
a `3600` ovunque:

| Scope | Limite / finestra | Nota |
| --- | --- | --- |
| `ai:chat` | 10 / 3600 s | Il numero da riconfermare, per la ragione scritta sopra |
| `ai:pairing` | 10 / 3600 s | |
| `ai:catalogo` | 10 / 3600 s | |
| `ai:visione` | 10 / 3600 s | Non entra nella 10a: arriva con le funzionalità foto |
| `ai:sfondo` | 10 / 3600 s | Non entra nella 10a: arriva con la 7.13 |

**Quello che vale davvero, dopo la riconferma numerica dell'11 agosto 2026.** La
riga «numero da riconfermare» qui sopra è stata riconfermata, e la risposta ha
cambiato due valori su tre. I limiti in vigore in
`supabase/functions/_shared/ai-gate.ts` sono:

| Scope | Limite / finestra | Perché quel numero |
| --- | --- | --- |
| `ai:chat` | **40** / 3600 s | Circa tre conversazioni realistiche intere (5-15 battute l'una) invece di esaurirsi dentro la prima |
| `ai:pairing` | **15** / 3600 s | Durante una sessione di navigazione si prova più di una combinazione |
| `ai:catalogo` | **10** / 3600 s | Invariato: è un'azione per annuncio, non per sessione |

Restano vincolanti e non sono parametri di quel file: finestra oraria per tutti e
tre, nessuna eccezione per `admin`, nessun tetto secondario oltre al rate limit
per la v0. `ai:visione` e `ai:sfondo` non hanno ancora un numero perché non hanno
ancora una funzionalità: si fissano nelle sessioni di spec della 10d e della 10e.

**Proposta respinta — un secondo tetto, sulla stessa meccanica.** La domanda «esiste un
tetto oltre al rate limit» ha una risposta che non costa niente:
`private.rate_limit_consume` prende `window_seconds` come parametro
(`20260731135455_…:26-90`), quindi una finestra giornaliera è lo stesso
meccanismo con un numero diverso. Proposta: `ai:giorno`, 100 / 86400 s, consumato
da **tutte** le funzionalità in aggiunta al proprio bucket. Nessuna nuova
migrazione, nessun codice nuovo, e il tetto complessivo per utente esiste.
**Respinta**: per il v0 non c'è un secondo tetto nostro, e un budget mensile è
rimandabile a dopo il lancio se emerge la necessità.

**Proposta accolta — il tetto di progetto non sta nel database.** Un contatore globale
che ferma tutti gli utenti è un'interruzione di servizio che nessuno vede
arrivare, e soprattutto non protegge dal caso che costa davvero: una chiave che
esce. Proposta: il tetto di progetto è un **limite di spesa configurato sul
provider**, che vale anche per chiamate che non passano da noi. Va con la 7.11.

**Proposta accolta — il limite vale anche per `admin`.** Il limite protegge il budget,
non l'utente. La Fase 9 ha stabilito che il moderatore è il ruolo `admin`
esistente e non un ruolo a parte (`CLAUDE.md`, sezione «Phase 9 moderation»):
un'esenzione sarebbe una via privilegiata sfruttabile se un account `admin` viene
compromesso, cioè esattamente lo scenario in cui il tetto serve.

### 7.5 Comportamento quando il provider fallisce o è lento — CHIUSA (11 agosto 2026): mappatura legacy invariata, `AI_ENABLED` fail-closed

Il legacy: 503 se il provider è giù, 502 se risponde in un formato inatteso
(`backend/ai_routes.py:197-200`), evento di errore generico nello stream
(`:88-90`), timeout a 30 s (`docs/ENVIRONMENT.md:169`).

> **Deciso.** Si mantiene la mappatura del legacy: provider giù → **503**,
> risposta in formato inatteso → **502**, errore **generico** nello stream e nella
> risposta, **mai il messaggio del provider al client**. **`AI_ENABLED` come
> gemello di `PAYMENTS_ENABLED`**: fallisce chiuso se assente, il che permette di
> distribuire la fase spenta. **Timeout applicativo vincolato al limite di durata
> proprio della Edge Function, non oltre.** Un fallimento va **loggato**: per il
> v0 il log della function basta, **nessuna tabella dedicata**.

La proposta è stata accolta per intero; il testo che segue è la motivazione con
cui era stata formulata, e vale come motivazione della decisione.

**Proposta accolta — mappatura invariata.** 503 provider non disponibile, 502 risposta
inutilizzabile. Non è conservatorismo: i quattro schemi Zod di risposta esistono
già lato client (`frontend/src/services/api-contracts.ts`, 2.5) e cambiare i
codici significherebbe cambiare anche loro, cioè allargare la fase senza guadagno.

**Proposta — sì a un flag `AI_ENABLED`, nella forma esatta di
`PAYMENTS_ENABLED`.** Cioè `Deno.env.get("AI_ENABLED") !== "true"` → 503, che è
letteralmente ciò che fa `supabase/functions/payments-checkout/index.ts:108`:
manca la variabile, la funzione è spenta. È il gemello nell'ambiente Edge di
`DisabledAIProvider`, che fallisce chiuso (`backend/ai_provider.py:19-27`).

Qui il flag conta **più** che per i pagamenti, e la ragione è il fatto verificato
nella 7.10: le Edge Function vengono distribuite dal merge, automaticamente. Una
function AI unita a `main` senza flag va in produzione entro un minuto, con
qualunque ambiente si trovi. Con il flag assente per default, va in produzione
spenta.

**Proposta accolta — timeout applicativo a 30 s, invariato**, realizzato con un
`AbortController` sulla `fetch` verso il provider. Il numero non è arbitrario e
non va alzato: la piattaforma chiude una richiesta che non risponde entro **150 s
con un 504** (`request idle timeout`, documentazione Supabase «Edge Functions —
Limits»), e un 504 del gateway non ha corpo, non ha il nostro messaggio generico
e non è distinguibile da un guasto nostro. Tenere il timeout applicativo un
ordine di grandezza sotto quello di piattaforma significa che **il fallimento
resta nostro** e quindi descrivibile. È esattamente la forma che la decisione
chiede — «vincolato al limite di durata proprio della Edge Function, non oltre» —
e i 30 s la soddisfano con un margine di cinque volte.

Due limiti di piattaforma che vanno scritti qui perché condizionano il disegno,
non solo la messa a punto: il **wall clock** è 150 s sul piano free e 400 s sui
piani a pagamento, e la **CPU è 2 s per richiesta**, esclusa la I/O asincrona.
Un proxy sta comodamente dentro entrambi, perché il suo tempo è attesa e non
calcolo — ma è la ragione tecnica per cui la 7.13 deve **rilanciare** l'immagine
a PhotoRoom e non elaborarla nella function.

**Proposta accolta — nessuna tabella per i fallimenti.** Il fallimento si registra nei
log della function con il `request_id`, senza contenuto del prompt e senza
identificativo utente. Una tabella nuova è una migrazione nuova e una superficie
di esposizione nuova; l'`audit_log` della Fase 9 è per le decisioni di
moderazione e non va riusato per gli errori di un fornitore
(decisione 7.3 della Fase 9: `audit_log` non si cancella mai — riempirlo di
errori di rete è un modo per rendere inutile quella garanzia).

### 7.6 Origini CORS e superficie della function — CHIUSA (11 agosto 2026): nessun rename, una variabile a parte

Le tre function esistenti leggono l'allowlist da `PAYMENT_ALLOWED_ORIGINS`
(`supabase/functions/_shared/cors.ts:3`), con `http://localhost:3000` come
default quando la variabile manca.

> **Deciso. Nessun rename.** `PAYMENT_ALLOWED_ORIGINS` resta intatta e **non
> viene toccata**: zero rischio sul codice dei pagamenti in produzione. Le
> function AI leggono una variabile propria, **`AI_ALLOWED_ORIGINS`**, con lo
> stesso pattern di `supabase/functions/_shared/cors.ts` — origini complete e non
> sottostringhe, `Vary: Origin`. Sulla forma della superficie: **una function per
> funzionalità, non una parametrica**, seguendo il precedente delle sette RPC
> distinte della Fase 9.

**La decisione ha respinto la proposta sulle origini, e ha ragione.** La proposta
puntava a una lista sola rinominata `ALLOWED_ORIGINS`, con una catena di fallback
temporanea per non rompere i pagamenti al merge. Ma la catena di fallback è una
mitigazione di un rischio che si può semplicemente non correre: dato che il merge
ridistribuisce **tutte** le function (7.10), toccare `_shared/cors.ts` significa
rimettere in produzione il percorso dei pagamenti a ogni merge successivo,
chiunque lo faccia e per qualunque motivo. Il guadagno era di igiene dei nomi. Il
rischio era 403 su tre function in produzione. Non è uno scambio conveniente.

Conseguenza operativa per l'implementazione: le function AI **non importano**
`_shared/cors.ts`. Il pattern viene replicato in un modulo separato, così il file
condiviso dai pagamenti resta identico byte per byte e il suo diff, in ogni PR
della Fase 10, è vuoto.

**Proposta respinta — una sola lista, con un nome corretto, introdotta in
modo che non possa rompere i pagamenti.** Le origini sono una proprietà del
deployment, non del dominio: è lo stesso browser che chiama i pagamenti e l'AI.
Due liste da tenere allineate a mano sono un generatore di deriva, e una lista
che si chiama `PAYMENT_…` ma governa anche l'AI è una trappola per chi la leggerà
fra sei mesi. Quindi: `ALLOWED_ORIGINS`.

Ma il rename non è gratis, e il motivo è il fatto verificato nella 7.10: il merge
ridistribuisce **tutte** le function. Se `_shared/cors.ts` inizia a leggere
`ALLOWED_ORIGINS` e quella variabile non è configurata al momento del merge,
`corsHeadersFor` ricade sul default `http://localhost:3000`, e da quell'istante
**ogni chiamata di pagamento dall'origine reale prende 403** — su tre function,
non su una. Proposta operativa, in quest'ordine:

1. si configura `ALLOWED_ORIGINS` nell'ambiente del progetto **prima** del merge;
2. il commit che rinomina legge `ALLOWED_ORIGINS ?? PAYMENT_ALLOWED_ORIGINS ??`
   il default, così il merge è sicuro anche se il passo 1 è stato dimenticato;
3. la rimozione di `PAYMENT_ALLOWED_ORIGINS` dalla catena è una riga sulla lista
   di cutover della Fase 13, con la sua data.

Il passo 2 è una scorciatoia temporanea e va scritta come tale: senza il passo 3
diventa un residuo, esattamente come `bottle_units.visibilita`.

**Proposta accolta sulla superficie — quattro function, non una parametrica e non sette.**
Il precedente della Fase 9 sono sette RPC distinte invece di una parametrica
(`CLAUDE.md`, sezione «Phase 9 moderation»), e va seguito nello spirito: una
porta per operazione, non un `action` nel corpo. Ma sette RPC in Postgres costano
una funzione ciascuna, mentre sette Edge Function costano sette unità di deploy e
sette cold start, e due delle nostre funzionalità **devono** stare insieme perché
la 7.3 dice che condividono la chiamata di visione.

| Function | Copre | Perché sta da sola |
| --- | --- | --- |
| `ai-sommelier` | Chat, storico, cancellazione | È l'unica che fa streaming e l'unica che scrive |
| `ai-pairing` | Abbinamento cibo-vino | Senza stato, e con la 7.8 fa una lettura che le altre non fanno |
| `ai-catalogo` | Suggerimento da testo, autofill 7.3a, completezza 7.3b | La 7.3 impone che 7.3a e 7.3b condividano la chiamata; il suggerimento da testo è lo stesso dominio con un input più povero |
| `ai-sfondo` | 7.13 | Provider diverso, chiave diversa, non passa dall'astrazione `AIProvider` |

Il triage di moderazione (7.12) **non compare**: non è una superficie chiamata dal
browser di un utente. La sua forma dipende da dove finisce l'esito, che la
sessione ha poi deciso — colonna persistita su `reports` — ma resta fuori dal
primo checkpoint.

Dei quattro, il **primo checkpoint 10a+10b ne scrive tre**: `ai-pairing` e
`ai-catalogo` senza stato nella 10a, `ai-sommelier` con storico e streaming nella
10b. `ai-sfondo` e la parte di visione di `ai-catalogo` arrivano con le
funzionalità foto, che hanno la loro sessione di spec.

### 7.7 Lo streaming — CHIUSA (11 agosto 2026): SSE, con il troncamento come caso atteso

La chat legacy è SSE (`backend/ai_routes.py:104-108`) e il client consuma i chunk
incrementalmente (`frontend/src/components/vinea/SommelierChat.tsx:109`).

> **Deciso.** Lo **streaming SSE si mantiene** per la chat Sommelier. Vincolo
> esplicito, da scrivere **nel codice e nella spec di implementazione**: una Edge
> Function che inoltra uno stream **può essere troncata** se il worker viene
> ritirato a metà risposta — comportamento documentato da Supabase — e **il client
> deve gestire un troncamento parziale come caso atteso, non come errore raro**.

Il secondo periodo è la parte che la proposta non aveva: non basta che la
function usi `EdgeRuntime.waitUntil()`, deve esistere anche un comportamento
definito dal lato che riceve. Uno stream che finisce senza l'evento di chiusura
non è un errore da mostrare: è una risposta parziale da tenere.

**Proposta accolta — si mantiene SSE.** Tre ragioni, in ordine di peso:

1. **Il contratto client esiste già ed è versionato.** `sommelierChunkSchema`
   (`frontend/src/services/api-contracts.ts:48-51`) descrive il chunk. Rispondere
   in un colpo solo significa riscrivere anche il client, cioè allargare la fase
   per ottenere meno.
2. **La persistenza a fine stream non è un problema nuovo.** Il legacy lo ha già
   risolto: si salva solo a stream concluso e non vuoto (`backend/ai_routes.py:92-101`),
   e su errore del provider si emette un evento generico e non si salva niente
   (`:88-90`). Con la 7.2 = A la stessa regola vale, su una tabella invece che su
   un documento.
3. **La latenza percepita è il prodotto**, in una funzionalità la cui unica
   ragione di esistere è sembrare una conversazione.

**Il vincolo tecnico da scrivere adesso, non da scoprire in produzione.** Uno
stream SSE inoltrato da una Edge Function può essere troncato quando il worker
viene ritirato: la documentazione Supabase lo elenca come scenario noto
(«Edge Functions worker timeouts and WebSocket drops», scenario «SSE or AI streams
end before completion») e indica il rimedio — tenere l'isolate vivo per tutta la
durata dell'inoltro con `EdgeRuntime.waitUntil()` sulla `pipeTo` dello stream a
monte, restituendo il lato leggibile come `text/event-stream`. Senza quel
dettaglio lo stream si interrompe **in modo intermittente e a metà risposta**,
che è la classe di difetto peggiore: non fallisce nei test e non fallisce sempre.

**Va riprodotto anche il troncamento in uscita.** Il contatore `remaining_chars`
del legacy (`backend/ai_routes.py:72`, `:79-87`) interrompe lo stream al tetto e
vale sia sui byte trasmessi sia su quelli salvati. Con la 7.2 = A quel contatore
non è più solo una difesa sul traffico: è ciò che tiene la riga dentro il tetto
messaggi, quindi appartiene alla stessa migrazione.

### 7.8 Il catalogo dell'abbinamento — CHIUSA (11 agosto 2026): lato server, deviazione dichiarata

> **Deciso.** Il catalogo per l'abbinamento **si risolve lato server**, da
> `public_listings` / `wines`, **non dal client**. È una **deviazione dichiarata**
> rispetto a `frontend/`, che oggi manda un catalogo statico di diciotto voci
> dimostrative: la Fase 10 porta l'AI a ragionare su dati reali invece che su dati
> finti. **Costa una query in più per chiamata — accettato.**

Oggi il client invia fino a 60 vini scelti da sé (`backend/ai_routes.py:148`,
`frontend/src/routes/esplora.tsx:102-105`). Non è una falla — sono dati pubblici
e l'output è validato contro l'input (`backend/ai_routes.py:202-222`) — ma la
dimensione del prompt, e quindi il costo, la decide il browser.

**Un fatto che cambia la domanda, e che la prima stesura di questa spec non
riportava.** Quei vini non vengono dal database: `esplora.tsx` li prende da
`@/data/wines` (`frontend/src/routes/esplora.tsx:14`), che è un **file statico**
con diciotto voci (`frontend/src/data/wines.ts`), presente identico anche in
`frontend-next/src/data/wines.ts`. Il catalogo dell'abbinamento nel prodotto
servito è quindi un insieme di dati dimostrativi, non l'inventario reale.

**Proposta accolta — risolto lato server da `public_listings`.** Riprodurre «il client
manda il catalogo» significherebbe che in `frontend-next` l'AI continua a
ragionare su un file statico di diciotto vini mentre il progetto ha un catalogo
vero. La parità qui è una trappola: si conserverebbe il meccanismo perdendo il
significato. Quattro ragioni concrete:

1. **La vista esiste ed espone già i campi giusti.** `public_listings` è una
   vista `security_invoker = off` a colonne chiuse e contiene `produttore`,
   `nome`, `annata`, `regione`, `denominazione`, `tipo`
   (`supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql:500-530`),
   cioè esattamente i campi con cui `esplora.tsx:102-105` costruisce l'etichetta.
2. **È il pattern che le regole di esposizione vogliono** (4.3): la lettura
   pubblica passa dalla vista, non da una policy sulla tabella base.
3. **La validazione dell'output diventa più forte, non più debole.** Oggi il
   modello è validato contro ciò che il client ha mandato; risolvendo lato
   server è validato contro ciò che la function ha letto, quindi un `wine_id`
   proposto è dimostrabilmente un annuncio reale e pubblicato.
4. **Il costo torna sotto controllo nostro**, che è il presupposto della 7.4.

Con un tetto esplicito: la `select` porta un `limit` di **60**, lo stesso numero
già scritto in `backend/ai_routes.py:148`, così il prompt resta limitato anche
quando il catalogo cresce.

**Va dichiarato come deviazione, non nascosto.** L'insieme dei candidati cambia
rispetto a `frontend/`: non è una funzionalità nuova — è la stessa funzionalità
che legge la fonte vera — ma è un comportamento osservabile diverso, e va
registrato accanto all'unica altra deviazione dichiarata del progetto, il
Sommelier (`docs/ROADMAP_V1.md:136-137`).

### 7.9 Chi può usare l'AI — CHIUSA (11 agosto 2026): segue i due livelli 9b/9c

Oggi: qualunque utente autenticato (`backend/tests/test_ai_backend.py:17`).

> **Deciso.** L'accesso all'AI **segue i due livelli di sospensione già stabiliti
> dalla 9b/9c**. Primo livello, che blocca le sole scritture social: **non tocca**
> l'accesso AI. Secondo livello, che blocca anche la visione: **blocca anche
> l'AI**, stessa superficie delle altre funzioni sociali. Il pannello Sommelier
> **resta montato anche per gli anonimi** come oggi — chi non ha sessione riceve
> un **401** dalla Edge Function, che è parità di comportamento con `frontend/`.

**Proposta accolta — l'accesso resta a ogni utente autenticato**, nessun ruolo nuovo.

**Proposta accolta — `rimosso` perde l'AI, `sospeso` la mantiene.** Non è una regola
inventata per l'occasione: è l'applicazione letterale della decisione 7.6b della
Fase 9, dove il primo livello blocca le sole scritture social e il secondo toglie
anche l'accesso in visione (`supabase/migrations/20260810180000_phase_9b_moderation_actions.sql:44-47`).
Il Sommelier è una superficie di consultazione, quindi cade sotto il secondo
livello e non sotto il primo. C'è anche una ragione indipendente: con la 7.2 = A
la chat **scrive**, e sarebbe l'unico posto in cui un utente rimosso continua a
scrivere.

**Proposta accolta — il controllo sta nella Edge Function, non in una policy.** Due
motivi verificati, non stilistici:

- la function risolve già l'identità dal token
  (`supabase/functions/payments-checkout/index.ts:122-123`), quindi il controllo
  cade dove l'identità è appena stata stabilita;
- l'helper `private.utente_stato_di` esiste
  (`supabase/migrations/20260810180000_phase_9b_moderation_actions.sql:161-172`,
  `SECURITY DEFINER`, e restituisce `attivo` per un uid sconosciuto) ma vive in
  `private` e **non ha un wrapper `public`**: chiamarlo da PostgREST richiederebbe
  una migrazione in più. Non serve: `service_role` ha `bypassrls`
  (`supabase/migrations/20260810210000_phase_9_rimosso_blocca_commercio.sql:159-160`),
  quindi il client di servizio legge `profiles.stato_utente` direttamente.

Sulla tabella dello storico, se nasce, la RLS ripete il predicato nella forma già
usata dalla 9c — `not exists (select 1 from public.profiles me where me.id =
(select auth.uid()) and me.stato_utente = 'rimosso')`
(`supabase/migrations/20260810210000_phase_9_rimosso_blocca_commercio.sql:166-170`)
— così il controllo esiste in due punti indipendenti e non solo nel codice.

**Proposta accolta — il pannello resta montato per gli anonimi.** Oggi chiunque lo apre e
prende un 401 dall'API (`frontend/src/components/vinea/Layout.tsx:19`, `:255`,
2.5). È brutto, ma è il comportamento servito, e cambiarlo qui sarebbe migliorare
il prodotto durante una migrazione. Va sulla lista di cutover della Fase 13.

**Nota vincolante, che non è una decisione aperta**: qualunque risposta si dia
sul sospeso/rimosso, **non deve toccare la macchina dei pagamenti**. È la regola
già fissata per la 9c in `CLAUDE.md` — «Nothing in 9c may make the payment
machine react to `stato_utente`» — e la classe di difetto 7c/7f che protegge (un
pagamento congelato senza uscita) non cambia natura perché il predicato lo
aggiunge la Fase 10. Leggere `stato_utente` dentro una function AI non è quel
caso, perché quella function non tocca nessun ordine: è però la ragione per cui
il controllo va lì e in nessun altro posto.

### 7.10 Dove sta il gate di autorizzazione — CHIUSA (11 agosto 2026): è il merge

> **Deciso**, e confermato dalla correzione che segue: **il gate di distribuzione
> delle Edge Function è il merge**, lo stesso delle migrazioni. **Nessuna azione di
> deploy separata da autorizzare.** Vale comunque la regola già in vigore:
> l'applicazione al progetto reale — **sia migrazione sia function** — richiede
> una **conferma esplicita e distinta per perimetro** nella sessione
> organizzativa, come per la Fase 9.

**Prima la correzione, perché la decisione ne dipende.** La prima stesura di
questa sezione affermava che «distribuire una Edge Function non è un merge, è un
`deploy` separato che nessuna decisione precedente copre». È falso, e questa è la
verifica che lo smentisce — letta l'11 agosto 2026 con `list_edge_functions` sul
progetto reale `pijnmcllmfgjmgsvtcej`, confrontata con i tempi di merge di GitHub:

| Function | Timestamp riportato | Merge corrispondente | Scarto |
| --- | --- | --- | --- |
| `payments-checkout`, creazione | 2026-08-03 15:34:57 | PR #18, 14:34:22 UTC | 1h 00m 35s |
| `connect-onboarding`, creazione | 2026-08-04 11:19:22 | PR #19, 10:18:47 UTC | 1h 00m 35s |
| `payouts-release`, creazione | 2026-08-04 11:19:24 | PR #19, 10:18:47 UTC | 1h 00m 37s |
| **Tutte e tre**, ultimo aggiornamento | 2026-08-11 10:19:43 | PR #33, 09:18:54 UTC | 1h 00m 49s |

Lo scarto costante di un'ora è un disallineamento di riferimento nei timestamp
restituiti dall'API; il residuo — da 35 a 49 secondi — è la latenza vera. Tre
conclusioni, e nessuna dipende da come si spiega l'ora:

1. **Distribuisce il merge.** In `.github/workflows/` ci sono due soli file,
   `ci.yml` e `payouts-auto-release.yml`, e nessuno dei due esegue un deploy di
   function. Nessuno ha mai lanciato `supabase functions deploy`: le tre function
   sono comparse da sole dopo i merge che le introducevano, come le migrazioni.
2. **Le distribuisce tutte, ogni volta.** Le tre hanno un `updated_at` identico e
   sono state ridistribuite al merge della **PR #33**, che tocca tre soli file —
   `CHANGES.log`, `CLAUDE.md`, `CONTESTO_IA/01_STATO_ATTUALE.md` — e nessuna riga
   di function. Una PR di sola documentazione ha rimesso in produzione tutto il
   codice delle Edge Function.
3. Quindi il gate esiste già ed è lo stesso delle migrazioni.

**Proposta accolta — vale la forma della decisione 7.9 della Fase 9**, cioè una sola
conferma esplicita in sessione che copre insieme il merge e ciò che il merge
applica; e l'autorizzazione a eseguire una griglia di verifica resta **per
griglia, non per progetto** (`CLAUDE.md`, sezione «Phase 9 moderation»).

**Proposta accolta — con un'aggiunta che la Fase 9 non aveva bisogno di fare.** Per una
migrazione, «applicare» significa modificare uno schema che poi resta lì; per una
Edge Function significa che **codice nuovo inizia a rispondere a richieste entro
un minuto**, con l'ambiente che trova in quel momento. Ne discende una regola
operativa che va confermata insieme alla conferma di merge:

> L'ambiente della function si configura **prima** del merge che la introduce, mai
> dopo, e la function ha un flag che la tiene spenta se l'ambiente manca (7.5).

È la stessa forma della decisione 1e della Fase 7d — scheduler acceso e verificato
*prima* di `PAYMENTS_ENABLED`, mai dopo — e la ragione per riproporla qui è che
quella decisione, nel caso 7g, non è stata rispettata: il risultato è a 18 run su
18 in `failure` (8.3). Con le Edge Function l'errore non aspetta uno scheduler: si
manifesta al primo utente.

Nota che questo rende **più stretta**, non più larga, la 7.6: rinominare una
variabile letta da `_shared/cors.ts` non tocca solo la function che si sta
scrivendo, ma tutte quelle già in produzione, al merge successivo, chiunque lo
faccia e per qualunque motivo. **È il ragionamento che ha portato la sessione a
respingere il rename**: la 7.6 si chiude non rinominando niente.

### 7.11 Dove vivono chiave e budget — CHIUSA (11 agosto 2026): Enrico, entro il 18 agosto 2026

Vincolante e non in discussione: «chiave e budget configurati fuori dal
repository» (`docs/MIGRATION_PHASE_1_BACKLOG.md:545-546`) e «nessuna chiave
segreta deve raggiungere il browser» (`CONTESTO_IA/02_STORIA_FASI.md`, sezione
«Fase 10»). Le chiavi vivono quindi nell'ambiente della Edge Function, come
`SUPABASE_SERVICE_ROLE_KEY` per `payments-checkout`
(`supabase/functions/payments-checkout/index.ts:119`), e vanno aggiunte a
`docs/ENVIRONMENT.md` e al `.env.example` pertinente nello stesso cambiamento che
le introduce (`CLAUDE.md`, sezione «Environment variables»).

Era aperto **chi le configura e quando**, e la 7.1 ha peggiorato la domanda: i
provider sono almeno tre, più PhotoRoom (7.13). Non è una chiave, sono quattro.

> **Deciso.** **Enrico si assume la configurazione di chiave e budget del o dei
> provider, entro lunedì 18 agosto 2026.** È un impegno con nome e data, non solo
> un vincolo tecnico. Il vincolo tecnico resta comunque: **nessun merge di Fase 10
> con `AI_ENABLED` implicitamente vero** se le variabili non sono leggibili
> nell'ambiente — stessa logica di `PAYMENTS_ENABLED`, **fail-closed by design,
> non affidata alla disciplina di chi fa il merge**.

**Una sfumatura in cui la decisione è migliore della proposta.** La proposta
diceva «la PR della 10a non viene mersa finché le variabili non sono leggibili
nell'ambiente»: è una regola che presidia il **comportamento** di chi merga, e
quel presidio è esattamente quello che ha fallito nel caso 7g. La decisione lo
sposta sulla **forma del codice** — il flag fallisce chiuso, quindi un merge senza
configurazione distribuisce la fase **spenta** invece di distribuirla rotta — e ci
aggiunge un impegno personale con una data vera. Dei due, il flag è quello che non
si dimentica; la data è quella che rende la fase utile.

**Proposta accolta — la responsabilità è di Enrico / `enricopuntog-cpu`.** Non è una
scelta: è l'unica persona con accesso al progetto, e assegnarla a un ruolo
generico sarebbe fingere che esista qualcun altro. È la stessa assegnazione della
decisione 1c della Fase 7d per `PAYOUTS_JOB_TOKEN`.

**Proposta corretta dalla decisione — la data non è una data, è una precondizione di merge.** Il
precedente scomodo va guardato in faccia: i segreti dello scheduler della Fase 7g
non sono mai stati configurati, `gh variable list` e `gh secret list` sul
repository sono **entrambi vuoti** all'11 agosto 2026, e `Phase 7 - auto-release
payouts` è a **18 run su 18 in `failure`**. Lì la decisione diceva «prima di
`PAYMENTS_ENABLED`», cioè prima di un evento che non è ancora accaduto: una
scadenza che non scade non è una scadenza. Proposta:

> La PR della 10a non viene mersa finché le variabili non sono leggibili
> nell'ambiente Edge Function del progetto. Non «poi le configuriamo»: la
> configurazione è parte della definizione di fatto della 10a, come lo sono lint,
> typecheck e documentazione aggiornata (`docs/DEVELOPMENT.md`, «Definition of
> done»).

Questo si aggancia direttamente alla 7.10: dato che il merge distribuisce, «prima
del merge» è l'unico momento in cui «prima» significa qualcosa.

**Proposta accolta — i nomi, con un vincolo di piattaforma da rispettare.** Le variabili
d'ambiente di una Edge Function **non possono iniziare con `SUPABASE_`**, prefisso
riservato dalla piattaforma (documentazione Supabase, «Edge Functions — Limits»),
e il tetto è di 100 segreti per progetto — non stringente qui, ma è il conto
dentro cui stanno anche le quattro nuove. Servono: una chiave per provider
secondo la 7.1, il nome del modello per compito, `AI_ENABLED` (7.5), la chiave
PhotoRoom (7.13) e — dopo la 7.6, che ha respinto il rename — `AI_ALLOWED_ORIGINS`
**accanto** a `PAYMENT_ALLOWED_ORIGINS`, non al suo posto.

**Proposta accolta — il budget sta sul provider, non nel nostro codice.** Un tetto che
applichiamo noi ferma i nostri utenti; un limite di spesa configurato sul conto
del provider ferma anche una chiave che è uscita, che è il caso in cui il denaro
si perde davvero. I due tetti non sono alternativi: i bucket per utente della 7.4
proteggono dall'abuso, il limite sul provider protegge dall'incidente.

**Proposta accolta — rotazione ogni 90 giorni e subito dopo sospetta esposizione**, la
stessa cadenza già decisa per `PAYOUTS_JOB_TOKEN` (Fase 7d, decisione 1c). Non
c'è ragione per cui una chiave a consumo debba durare più a lungo di un token di
job che non costa niente.

**Fuori da qualunque sessione IA.** Configurare questi valori richiede le
credenziali reali di chi ha accesso al progetto: nessuna sessione assistita può
farlo, tentarlo o indovinarli, e questa spec non li contiene.

---

## 8. Effort e dipendenze

### 8.1 Dipendenze da ciò che è già in piedi

| Dipendenza | Stato | Fonte |
| --- | --- | --- |
| Auth Supabase reale | Migrata dalla Fase 5a | `frontend-next/src/services/types.ts:5-7` |
| Rate limit server-side con porta per `service_role` | **Esiste, in produzione** | `20260731135455_…:143-160` |
| Pattern Edge Function + CORS allowlist | **Esiste, tre function attive** | `supabase/config.toml:385-396`; `list_edge_functions`, 11 agosto 2026 |
| Regole di esposizione Postgres | Vincolanti da 6d-1 | `CLAUDE.md`, sezione «Postgres exposure rules» |
| Distribuzione delle Edge Function | **Automatica al merge**, tutte insieme | Verifica nella 7.10 |
| Interfaccia `AiService` | **Non esiste** | `frontend-next/src/services/types.ts`, 996 righe, ultima interfaccia `:970` |
| Edge Function AI | **Non esiste** | `supabase/functions/`; `list_edge_functions` |
| Provider scelti e provati | **Nessuno**, la 7.1 chiude il criterio e non il nome | 7.1 |

### 8.2 Ordine di grandezza

Riscritta dopo le decisioni dell'11 agosto 2026, che hanno cambiato la risposta.

Lo scenario «senza migrazioni» descritto dalla prima stesura **è caduto**: la 7.2
ha scelto A, quindi la fase scrive SQL, e non è la prima fase interamente
reversibile dalla 5 in poi. Al contrario: con le quattro funzionalità nuove
ammesse per eccezione, la Fase 10 è **la più grande da quando la migrazione è
cominciata**, e va detto adesso che è il momento in cui si può ancora decidere
diversamente.

Il conto, per come le decisioni la lasciano oggi:

| Voce | Quantità |
| --- | --- |
| Migrazioni | **Almeno due** — storico Sommelier (7.2), spunta di completezza (7.3b) — più eventualmente triage persistito (7.12) e policy di Storage (7.13) |
| Edge Function | **Quattro**, secondo la proposta 7.6 |
| Interfaccia e adapter | Uno ciascuno, da zero |
| Superfici UI | Sei: Sommelier, pannello AI del wizard, cattura foto, spunta sull'annuncio, sfondo reale, ordinamento del pannello di moderazione |
| Provider da scegliere e provare | Tre di modelli più PhotoRoom |
| Griglie di verifica | Almeno una, versionata |

Due difficoltà che non hanno un precedente in casa: **il TTL senza `pg_cron`**
(5.1) e **la prima chiamata a un fornitore a consumo**, dove un difetto non
produce un errore ma una fattura.

E una che non è tecnica: **la 7.1 non ha ancora un provider**, perché la scelta è
subordinata a prove empiriche che nessuno ha fatto. La 10a e la 10c non possono
iniziare prima. È il punto in cui questa fase è più esposta, perché è l'unico
prerequisito che non si chiude scrivendo codice.

### 8.3 Debito non di questa fase, ma che la precede

I segreti GitHub `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN` non
sono configurati (`gh variable list` e `gh secret list` vuoti all'11 agosto
2026), quindi la decisione 1e della Fase 7d — scheduler acceso e verificato
**prima** di `PAYMENTS_ENABLED` — non è soddisfatta. Non blocca la Fase 10 e non
le appartiene, ma è la ragione per cui la decisione 7.11 va chiusa con un nome e
una data invece che con un'intenzione.
