# Fase 10 - AiService reale via Edge Function

Stato: **specifica organizzativa, non approvata.** Nessuna riga di SQL, nessuna
migrazione, nessuna Edge Function, nessun codice applicativo. Il branch previsto
dal backlog è `migration/phase-10-ai-service`
(`docs/MIGRATION_PHASE_1_BACKLOG.md:542`) e **non è stato aperto**: si apre solo
dopo che le decisioni della sezione 7 sono state chiuse in sessione
organizzativa, come è stato fatto per la Fase 9.

Ogni affermazione di questo documento porta la fonte `file:riga` da cui viene.
Ciò che non ha una fonte è marcato **decisione aperta** e va risposto in chat
organizzativa prima di qualunque SQL o Edge Function.

**I numeri di riga sono presi su `8dd56c0`**, cioè `origin/main` dopo il merge
della PR #33. I file di `CONTESTO_IA/` sono citati per **sezione** e non per
riga, perché sono aggiornati a ogni fase e una riga vi resta valida per poco.

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

Il primo lavoro della sessione organizzativa non è scegliere un provider: è
decidere **quali di queste tre funzionalità la Fase 10 porta**, sapendo che una
quarta — l'identificazione da foto — non ha oggi niente da migrare.

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

- **Il cutover (Fase 11).** Anche a Fase 10 completa, `frontend/` + `backend/`
  restano la versione servita: la dismissione è una decisione separata
  (`docs/MIGRATION_PHASE_1_BACKLOG.md:552-555`).
- **Lo spegnimento delle rotte `/ai` del backend FastAPI.** Finché `frontend/` è
  servito, `SommelierChat.tsx`, `useSellWizard.ts` ed `esplora.tsx` continuano a
  chiamarle. La regola «un solo scrittore autorevole per dominio»
  (`CLAUDE.md`, sezione «Migration architecture») va interpretata qui: l'AI non
  ha uno stato scritto condiviso se non lo storico Sommelier, ed è esattamente
  su quello che la sezione 5 apre una decisione.
- **KYC, hardening operativo e revisione legale**, che
  `CONTESTO_IA/01_STATO_ATTUALE.md` tiene fuori da ogni fase di migrazione.
- **Il pannello «Migliora lo sfondo con IA»**, che è già portato e **non è AI**:
  vedi 2.6.

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
(`docs/MIGRATION_PHASE_1_BACKLOG.md:124-125`). **Resta fuori dalla Fase 10.**
Renderlo reale sarebbe una funzionalità nuova.

Va però registrato che oggi la UI promette all'utente una cosa che non accade:
appartiene alla lista di cutover della Fase 11, accanto a
`bottle_units.visibilita`, non a questa fase.

### 2.7 Riepilogo: cosa la Fase 10 può migrare e cosa dovrebbe inventare

| Funzionalità | Esiste in `frontend/`? | Ha uno stato persistente? | Migrazione o novità |
| --- | --- | --- | --- |
| Chat Sommelier | Sì, completa con storico | **Sì** — storico su MongoDB | Migrazione, ed è l'unica con dati da spostare |
| Abbinamento cibo-vino | Sì | No, richiesta senza stato | Migrazione |
| Suggerimento catalogazione da testo | Sì | No, richiesta senza stato | Migrazione |
| Identificazione bottiglia da foto | **No** | — | **Novità** — vietata durante la migrazione |
| «Migliora lo sfondo con IA» | Simulata, già portata | No | Fuori perimetro |

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

---

## 5. Il nodo vero della fase: dove vive lo storico Sommelier

Delle tre funzionalità migrabili, due sono richieste senza stato: un proxy che
autentica, limita, chiama il provider e restituisce. Lo storico Sommelier è
l'unica che ha dati, e quindi l'unica che tocca lo schema, RLS, i grant e la
regola «un solo scrittore autorevole per dominio».

Le tre strade possibili, con le conseguenze già visibili:

**A — Tabella Postgres in Supabase.** Coerente con ogni altra fase. Costo: una
migrazione con tabella, RLS, vista di lettura a colonne chiuse, una
`SECURITY DEFINER` per l'append con il tetto messaggi, e una strategia di TTL.
Il TTL è il punto scomodo: Mongo lo fa con un indice (`backend/repositories.py:195`),
Postgres no, e `pg_cron` è **escluso** dalla decisione 1a della Fase 7d, non
rinviato. Restano la cancellazione opportunistica sul modello di
`rate_limit_consume` (`20260731135455_…:83-86`), un secondo job GitHub Actions
sul modello della 7g, o una scadenza applicata in lettura. Nessuna è gratis.

**B — Nessuna persistenza: la conversazione vive nel browser.** Costo zero di
schema, e il TTL diventa un non-problema. Ma è una perdita di parità
comportamentale rispetto a `frontend/`, dove lo storico sopravvive alla
ricarica, ed è esattamente il tipo di decisione che va presa in sessione e non
dedotta.

**C — Il Sommelier non viene portato in Fase 10.** Le due funzionalità senza
stato migrano, la chat resta su `frontend/` fino al cutover. Il debito è già
dichiarato (`docs/ROADMAP_V1.md:136-137`) e resterebbe dichiarato.

Questa è la **decisione aperta 7.2**, ed è quella che determina se la fase
contiene SQL o no. Se la risposta è B o C, la Fase 10 potrebbe non avere
migrazioni: sarebbe la prima dalla 5 in poi.

---

## 6. Suddivisione proposta in sotto-fasi

Proposta, non decisa: dipende dall'esito di 7.2 e 7.3.

**10a — la porta.** Una Edge Function proxy sul pattern di 4.1: origine, metodo,
flag, bearer, `auth.getUser`, consumo del bucket via
`public.rate_limit_consume`, chiamata al provider dietro un adapter, risposta
validata. Nessuna persistenza. Copre abbinamento e suggerimento di
catalogazione, cioè le due funzionalità senza stato. Contiene l'interfaccia
`AiService` in `frontend-next/src/services/types.ts` e l'adapter.

**10b — lo storico**, solo se 7.2 risponde «A»: migrazione, RLS, vista,
`SECURITY DEFINER` di append, meccanismo di scadenza, e la rotta chat con lo
streaming.

**10c — il ripristino della UI**: pannello Assistente AI nel wizard e, secondo
7.2, il pannello Sommelier nel Layout.

Perché in quest'ordine: 10a stabilisce il contratto e il costo reale di una
chiamata al provider senza toccare lo schema, che è la parte reversibile. 10b è
l'unica con SQL e quindi l'unica soggetta al gate di autorizzazione. 10c non
può precedere nessuna delle due perché consumerebbe interfacce che non esistono.

`MIN_TESTS` in CI è a **204** (`.github/workflows/ci.yml:99`): come in ogni fase
precedente va alzato deliberatamente quando i test aumentano.

---

## 7. Decisioni aperte — richiedono una risposta esplicita prima di qualunque codice

### 7.1 Quale provider, e a chi escono i dati

Il legacy usa OpenAI con default `gpt-4.1-mini` (`docs/ENVIRONMENT.md:168`,
`backend/config.py:76`). Non c'è nessuna fonte nel repository che dica che il
provider debba restare quello. Da decidere: provider e modello; se l'adapter
deve reggerne più d'uno fin da subito o solo essere sostituibile; e se il
`request_id`, che oggi contiene l'identificativo utente
(`backend/ai_routes.py:77`, `:194`, `:269`), continua a essere trasmesso al
provider o viene sostituito da un identificativo opaco non riconducibile.

### 7.2 Lo storico Sommelier: A, B o C

Vedi sezione 5. **È la decisione che determina se questa fase scrive SQL.**
Se A, serve anche la risposta su come si applica il TTL, dato che `pg_cron` è
escluso.

### 7.3 Identificazione bottiglia: dentro o fuori

Il backlog nomina `ai-identify-bottle` (`docs/MIGRATION_PHASE_1_BACKLOG.md:544`)
ma nel prodotto servito non esiste nessun percorso foto → etichetta (vedi 0.2).
Portarla è una funzionalità nuova, e le funzionalità nuove sono vietate durante
la migrazione. Le opzioni sono: (a) fuori, e il nome nel backlog va corretto;
(b) dentro come eccezione esplicita, motivata e registrata; (c) rinviata al
dopo-cutover. Da decidere anche se l'identificazione e il suggerimento di
catalogazione sono **una porta o due**: oggi sono un solo endpoint con due
campi alternativi (`backend/ai_routes.py:226-229`), e la differenza è che una
foto richiede Storage, dimensione massima, tipo MIME e un costo per chiamata
diverso da quello del testo.

### 7.4 Budget e limiti numerici

Vincolante e già scritto: il rate limit sta lato server
(`docs/MIGRATION_PHASE_1_BACKLOG.md:545`) e i valori restano fuori dal
repository (`:545-546`). Aperti sono i numeri e la forma:

- un solo bucket per tutte le funzionalità, come oggi (`ai:user:…`,
  `backend/ai_routes.py:29`), o uno per funzionalità come fa il resto del
  progetto (4.2)?
- finestra al minuto come il checkout o oraria come `report:submit`?
- esiste un tetto **oltre** al rate limit — un budget mensile per utente o per
  progetto — e che cosa succede quando si esaurisce?
- il limite vale anche per un `admin`?

### 7.5 Comportamento quando il provider fallisce o è lento

Il legacy: 503 se il provider è giù, 502 se risponde in un formato inatteso
(`backend/ai_routes.py:197-200`), evento di errore generico nello stream
(`:88-90`), timeout a 30 s (`docs/ENVIRONMENT.md:169`). Da decidere se la
versione Supabase mantiene la stessa mappatura, se esiste un
`AI_ENABLED`/`disabled` equivalente a `DisabledAIProvider`
(`backend/ai_provider.py:19-27`) — che sarebbe il gemello di `PAYMENTS_ENABLED`
e permetterebbe di distribuire la fase spenta — e se un fallimento va registrato
da qualche parte. Nota: le Edge Function hanno un limite di durata proprio, che
è un vincolo diverso dal timeout applicativo.

### 7.6 Origini CORS e superficie della function

Le tre function esistenti leggono l'allowlist da `PAYMENT_ALLOWED_ORIGINS`
(`supabase/functions/_shared/cors.ts:3`). Da decidere se l'AI condivide quella
variabile — il cui nome diventerebbe fuorviante — o ne ha una propria. Da
decidere anche se le funzionalità AI sono **una function con più operazioni** o
una per funzionalità: la Fase 9 ha scelto sette RPC distinte invece di una
parametrica (`CLAUDE.md`, sezione «Phase 9 moderation»), ed è un precedente che
va o seguito o contraddetto consapevolmente.

### 7.7 Lo streaming

La chat legacy è SSE (`backend/ai_routes.py:104-108`) e il client consuma i
chunk incrementalmente (`frontend/src/components/vinea/SommelierChat.tsx:109`).
Da decidere se la versione Supabase mantiene lo streaming — che complica
troncamento, persistenza a fine stream e gestione degli errori a metà risposta —
oppure risponde in un colpo solo, accettando una latenza percepita maggiore.
Dipende da 7.2: senza persistenza il problema si semplifica molto.

### 7.8 Il catalogo dell'abbinamento

Oggi il client invia fino a 60 vini scelti da sé
(`backend/ai_routes.py:148`, `frontend/src/routes/esplora.tsx:102-105`). Non è
una falla — sono dati pubblici e l'output è validato contro l'input
(`backend/ai_routes.py:202-222`) — ma significa che la dimensione del prompt, e
quindi il costo, la decide il browser. Da decidere se in Supabase il catalogo
continua ad arrivare dal client o viene risolto lato server da `public_listings`
/ `wines`. La seconda strada costa una query in più e toglie al client il
controllo del costo.

### 7.9 Chi può usare l'AI

Oggi: qualunque utente autenticato (`backend/tests/test_ai_backend.py:17`). Da
decidere se in Supabase l'accesso resta uguale, se un utente sospeso o rimosso
ai sensi della 7.6b conserva l'accesso all'AI, e se il pannello Sommelier
continua a essere montato per gli anonimi come oggi
(`frontend/src/components/vinea/Layout.tsx:255`) o viene mostrato solo a chi ha
una sessione.

**Nota vincolante, che non è una decisione aperta**: qualunque risposta si dia
sul sospeso/rimosso, **non deve toccare la macchina dei pagamenti**. È la
regola già fissata per la 9c in `CLAUDE.md` — «Nothing in 9c may make the
payment machine react to `stato_utente`» — e la classe di difetto 7c/7f che
protegge (un pagamento congelato senza uscita) non cambia natura perché il
predicato lo aggiunge la Fase 10.

### 7.10 Dove sta il gate di autorizzazione

Per la Fase 9 la decisione 7.9 stabilì che una sola conferma esplicita in
sessione copre merge e applicazione, e che l'autorizzazione a eseguire una
griglia è **per griglia, non per progetto** (`CLAUDE.md`, sezione «Phase 9
moderation»). Da decidere se la stessa forma vale per la Fase 10, tenendo
presenti due differenze: se 7.2 risponde B o C potrebbe non esserci nessuna
migrazione da applicare; e **distribuire una Edge Function non è un merge**, è
un `deploy` separato che nessuna decisione precedente copre. Va detto
esplicitamente chi lo esegue e quando.

### 7.11 Dove vivono chiave e budget

Vincolante: «chiave e budget configurati fuori dal repository»
(`docs/MIGRATION_PHASE_1_BACKLOG.md:545-546`) e «nessuna chiave segreta deve
raggiungere il browser» (`CONTESTO_IA/02_STORIA_FASI.md`, sezione «Fase 10»).
La chiave vive quindi nell'env della Edge Function, come
`SUPABASE_SERVICE_ROLE_KEY` per `payments-checkout`
(`supabase/functions/payments-checkout/index.ts:119`), e va aggiunta a
`docs/ENVIRONMENT.md` e al `.env.example` pertinente nello stesso cambiamento
che la introduce (`CLAUDE.md`, sezione «Environment variables»).

Resta aperto **chi la configura e quando**, e va detto guardando un precedente
scomodo: i segreti dello scheduler della Fase 7g non sono mai stati configurati,
`gh variable list` e `gh secret list` sul repository sono **entrambi vuoti**
all'11 agosto 2026, e il workflow `Phase 7 - auto-release payouts` è a **18 run
su 18 in `failure`**. Una fase che dipende da un segreto configurato a mano
fuori sessione ha già un precedente di come va a finire se nessuno se ne
assume la responsabilità con una data.

---

## 8. Effort e dipendenze

### 8.1 Dipendenze da ciò che è già in piedi

| Dipendenza | Stato | Fonte |
| --- | --- | --- |
| Auth Supabase reale | Migrata dalla Fase 5a | `frontend-next/src/services/types.ts:5-7` |
| Rate limit server-side con porta per `service_role` | **Esiste, in produzione** | `20260731135455_…:143-160` |
| Pattern Edge Function + CORS allowlist | **Esiste, tre function attive** | `supabase/config.toml:385-396`; `list_edge_functions`, 11 agosto 2026 |
| Regole di esposizione Postgres | Vincolanti da 6d-1 | `CLAUDE.md`, sezione «Postgres exposure rules» |
| Interfaccia `AiService` | **Non esiste** | `frontend-next/src/services/types.ts`, 996 righe, ultima interfaccia `:970` |
| Edge Function AI | **Non esiste** | `supabase/functions/`; `list_edge_functions` |

### 8.2 Ordine di grandezza

Con storico persistente (7.2 = A): una migrazione, una o più Edge Function, una
interfaccia e un adapter nuovi, tre pannelli UI da ripristinare, una griglia di
verifica versionata. Paragonabile alla Fase 9, con una difficoltà in più — il
TTL senza `pg_cron` — e una in meno: nessun enforcement trasversale su domini
già esistenti.

Senza storico persistente (B o C): nessuna migrazione, e la fase si riduce alla
Edge Function più l'interfaccia più la UI. Sensibilmente più piccola di ogni
fase da 6 in poi, e — non secondario — **la prima interamente reversibile**,
perché niente di ciò che produce entra nello schema.

### 8.3 Debito non di questa fase, ma che la precede

I segreti GitHub `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN` non
sono configurati (`gh variable list` e `gh secret list` vuoti all'11 agosto
2026), quindi la decisione 1e della Fase 7d — scheduler acceso e verificato
**prima** di `PAYMENTS_ENABLED` — non è soddisfatta. Non blocca la Fase 10 e non
le appartiene, ma è la ragione per cui la decisione 7.11 va chiusa con un nome e
una data invece che con un'intenzione.
