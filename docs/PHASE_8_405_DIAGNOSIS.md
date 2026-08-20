# Fase 8 — le tre RPC che rispondono 405, causa misurata

Diagnosi del 18 agosto 2026 su `pijnmcllmfgjmgsvtcej` (produzione). Nessuna
ipotesi qui è dedotta dal codice: ogni riga ha la misura che la produce.

## 1. Il fatto, prima della causa

`edge_logs`, ultime 24 ore, aggregato su `/rest/v1/rpc/%`:

| path | metodo | status | n |
|---|---|---|---|
| `/rest/v1/rpc/notifications_page` | POST | **405** | 63 |
| `/rest/v1/rpc/conversations_page` | POST | **405** | 62 |
| `/rest/v1/rpc/notifications_page` | OPTIONS | 200 | 7 |
| `/rest/v1/rpc/conversations_page` | OPTIONS | 200 | 7 |

Sono le **sole** quattro righe: nessun'altra RPC compare, con nessuno status.

**Prima correzione alla premessa: `conversation_open` non risponde 405.** Non
compare affatto nei log, perché non viene mai raggiunta — `/messaggi` muore
sull'elenco prima che si possa aprire una conversazione. La sua presenza
nell'elenco dei sintomi era un'inferenza, non una misura.

## 2. Il corpo del 405 è la causa, e non è il verbo

Il 405 non arriva vuoto:

```
HTTP/1.1 405 Method Not Allowed
{"code":"25006","message":"cannot execute INSERT in a read-only transaction"}
```

`25006` è `read_only_sql_transaction`, e PostgREST lo traduce in 405. Ma **nessuna
delle due funzioni contiene una `insert`**: sono due `return query select` puri
(`20260806224517_phase_8_messaging_notifications.sql:1050` e `:1193`). La insert
viene da fuori.

## 3. Da dove viene la insert

`authenticator` porta un hook di pre-richiesta, montato dalla Fase 7
(`20260731135455_phase_7_order_payment_service.sql:140`):

```
pgrst.db_pre_request = private.vinea_check_request
```

`private.vinea_check_request()` gira **dentro la transazione di ogni richiesta**
e fa esattamente questo:

```sql
if v_method is null or v_method in ('GET', 'HEAD', 'OPTIONS') then
  return;                                   -- le letture non si contano
end if;
...
perform private.rate_limit_consume(...);    -- e questa è una INSERT
```

`private.rate_limit_consume` fa `insert into private.rate_limit_buckets … on
conflict do update`. È l'unica insert in gioco.

## 4. Perché solo alcune funzioni

**PostgREST sceglie READ ONLY o READ WRITE dalla volatilità della funzione
chiamata, non dal verbo HTTP.** Una RPC `stable`/`immutable` gira in transazione
di sola lettura *anche chiamata in POST*, che è come `supabase-js` chiama sempre
`.rpc()`. Quindi:

- funzione `stable` + POST → transazione READ ONLY → l'hook prova la insert →
  `25006` → **405**;
- funzione `volatile` + POST → transazione READ WRITE → l'hook scrive → la
  chiamata prosegue normalmente.

L'hook filtra sul **metodo HTTP**, ma la proprietà che decide è **il modo della
transazione**. Sono due cose diverse, e la Fase 8 è la prima che le separa: fino
alla Fase 7 ogni POST cadeva su funzioni `volatile`, quindi il ramo non era mai
stato esercitato.

## 5. La controprova, isolata sulla sola volatilità

Chiamate dirette con la sola chiave anon, fuori dal frontend. `anon` non ha
`EXECUTE` su nessuna di queste, quindi **la risposta attesa a valle dell'hook è
`42501 permission denied`**: leggerla significa che l'hook è passato.

| funzione | volatilità | POST | corpo |
|---|---|---|---|
| `conversations_page` | STABLE | **405** | `25006 cannot execute INSERT in a read-only transaction` |
| `notifications_page` | STABLE | **405** | `25006` idem |
| `messages_page` | STABLE | **405** | `25006` idem |
| `notifications_unread_count` | STABLE | **405** | `25006` idem |
| `conversation_open` | VOLATILE | 401 | `42501 permission denied for function` |
| `message_send` | VOLATILE | 401 | `42501 permission denied for function` |

E lo stesso `conversations_page` chiamato in **GET** risponde `401 / 42501`, non
405: in GET l'hook esce sul primo `if`, la insert non avviene, e la funzione
viene raggiunta. Unica variabile mossa fra le due metà della tabella: la
volatilità. La causa è confermata, non ipotizzata.

## 6. Cosa era in effetti rotto

**Quattro** funzioni, non tre — tutte e sole le `stable` della Fase 8 chiamate
dal frontend:

`conversations_page`, `notifications_page`, `messages_page`,
`notifications_unread_count`.

Le altre `stable`/`immutable` esposte al client (`cellar_ambiente_e_mio`,
`cellar_modulo_e_mio`, `has_role`, `order_seller_stato`) non sono mai chiamate
via `.rpc()` dal frontend: servono dentro SQL. Non sono toccate.

## 7. Le quattro ipotesi escluse, con la misura che le esclude

1. **Schema cache non ricaricata.** Esclusa: una funzione ignota dà `PGRST202`
   con 404, misurato su `messages_page` chiamata senza il parametro
   obbligatorio. Qui il 404 arriva quando *deve*, quindi la cache vede le
   funzioni.
2. **Funzioni assenti o con firma diversa.** Escluse: `pg_proc` le riporta tutte
   e nove in `public` con gli argomenti attesi.
3. **`GRANT EXECUTE` mancante.** Escluso: `has_function_privilege('authenticated', …)`
   è `true` per tutte e nove.
4. **Database in sola lettura per quota disco (piano Free).** Esclusa, ed è
   l'ipotesi che somiglia di più al messaggio d'errore: se l'intero database
   fosse in sola lettura anche `conversation_open` e `message_send` in POST
   fallirebbero con `25006`, e invece arrivano al controllo dei permessi.
   `private.rate_limit_buckets` ha 14 righe, scritte da quello stesso hook.
5. **Mismatch lato client (verbo o nome sbagliato).** Escluso: gli adapter
   chiamano i nomi giusti e `supabase-js` usa POST, che per una RPC è corretto.
   Il difetto è a valle, nell'hook.

## 8. Perché la Fase 8 non l'ha visto

Le griglie di prova si eseguono nel **SQL Editor**, cioè in una sessione
Postgres diretta: non passano da PostgREST, quindi non incontrano né l'hook di
pre-richiesta né la transazione di sola lettura. Un difetto che vive
esattamente nel tratto che le griglie non attraversano.

## 9. Le due lacune aperte di `CHANGES.log`, verificate sul progetto reale

Riletto il progetto invece di fidarsi della riga che le registra. Una delle due
era descritta in modo più allarmante del vero, l'altra era semplicemente da
fare.

### 9.1 Realtime `private_only` — la riga confondeva due cose diverse

`CHANGES.log:200` dice che «la restrizione Realtime `private_only` è stata
configurata sulla sola Preview della Fase 8, mai sulla produzione». Sono due
meccanismi distinti e vanno separati, perché stanno in due posti diversi e uno
dei due **c'è**:

**L'autorizzazione Realtime è in produzione, ed è la metà che protegge davvero
i dati.** `realtime.messages` ha RLS attiva e **una** policy:

```
vinea_phase8_private_broadcast_select   SELECT   to authenticated
  extension = 'broadcast' AND (
    EXISTS (select 1 from conversation_participants cp
            where cp.user_id = auth.uid()
              and realtime.topic() = 'conversation:' || cp.conversation_id)
    OR realtime.topic() = 'user:' || auth.uid() || ':notifications'
  )
```

È scoping corretto, non un blocco: ammette esattamente i due topic legittimi —
la conversazione di cui si è partecipanti, e le proprie notifiche — e niente
altro. Non esiste policy di `INSERT` perché **nessun client pubblica**: i
broadcast li emette il database con `realtime.send()` da trigger
(`20260806224517…:398` e `:431`). Il client può solo ricevere.

**La pubblicazione `supabase_realtime` ha zero tabelle.** Postgres Changes non è
usato affatto: la Fase 8 passa solo da Broadcast. Nessun feed di riga esposto.

**Quello che manca è l'interruttore di progetto `private_only`**, che vieta
globalmente i canali *pubblici*. Vive nelle impostazioni Realtime del progetto,
non nel database: **non è leggibile né scrivibile da SQL, e fra gli strumenti
MCP non c'è un canale per la configurazione Realtime** — stessa situazione della
configurazione Auth della #50, il cui canale è la dashboard con la sessione
reale.

Accenderlo **non può rompere la consegna fra le due parti di una
conversazione**, e non è una previsione: il client apre **solo** canali privati
— `client.realtime.setAuth()` prima di iscriversi
(`frontend-next/src/services/phase8/realtime.ts:123`) e
`{ config: { private: true } }` su entrambi i topic (`:131`, `:137`). Un
interruttore che vieta i canali pubblici non tocca chi non ne apre. Il rischio
è l'opposto di quello temuto: finché resta spento, **un canale pubblico è
ammesso** — e un canale pubblico non passa dalla policy qui sopra.

### 9.2 Le tabelle della Fase 8, rilette

Prima rilettura dopo il merge del 7 agosto 2026.

| tabella | RLS | policy | in `supabase_realtime` | righe |
|---|---|---|---|---|
| `conversations` | on | 1 | no | **0** |
| `conversation_participants` | on | 1 | no | **0** |
| `messages` | on | 1 | no | **0** |
| `notifications` | on | 1 | no | **0** |

Schema e chiusure come attese. **Il dato è zero ovunque**: la Fase 8 non è mai
stata esercitata in produzione, il che è coerente con un difetto che rifiuta
ogni chiamata da undici giorni. Per contrasto, nello stesso momento `profiles`
ha 10 righe, `listings` 10 e `private.rate_limit_buckets` 14 — quest'ultima è
anche la prova che il ramo di scrittura dell'hook funziona quando la
transazione glielo permette.

Conseguenza diretta sulla verifica end-to-end: **non c'è nulla da leggere**, e
crearlo significa due utenti autenticati reali e una conversazione, cioè
**scrittura sul progetto reale**. La fixture non rientrava nel perimetro di
questa PR e non fu creata; non è un gate operativo corrente per singolo comando.

## 10. La correzione, provata prima di applicarla

`Supabase Preview` sulla PR #52 è **`skipping`** — «This git branch is not
associated with any Supabase Branch», lo stesso caso che la #51 ha registrato
per la #49. Quel SQL arriverebbe quindi in produzione **senza essere mai stato
eseguito da Supabase su un database suo**. Per non lasciarlo non provato, il
corpo corretto è stato messo alla prova sul progetto reale **senza toccare
niente**: definito in `pg_temp`, che sparisce con la sessione, mentre
`private.vinea_check_request` resta quella di produzione.

| | caso | esito |
|---|---|---|
| A | **corpo corretto**, POST in transazione di sola lettura | **PASSA** — `ok`, la guardia esce |
| B | **funzione di produzione**, stessa identica condizione | **PASSA** — `25006`, cioè il difetto |
| C | **corpo corretto**, POST in transazione di scrittura | **PASSA** — `ok` |
| D | il bucket di rate limit è comparso davvero | **PASSA** — 1 riga per quello scope |

A e B girano **nella stessa transazione**, uno dopo l'altro: è il confronto
prima/dopo con ogni altra variabile ferma. C e D provano la cosa che più conta
dopo la correzione, cioè che **il tetto sulle scritture non è allentato** — in
transazione di scrittura la guardia non scatta e il contatore viene consumato.

Il ramo di scrittura è stato eseguito dentro una transazione poi annullata, e i
residui sono stati **riletti dopo**, non dichiarati: `0` righe per lo scope
usato, `private.rate_limit_buckets` di nuovo a **14** come prima. E la funzione
di produzione **non contiene** `transaction_read_only`, che è la controprova che
nulla è stato applicato.

## 11. L'esito in produzione, misurato dopo il merge

La #52 è stata autorizzata per nome in sessione — merge e SQL insieme — ed è
mersa in squash come **`dde9b52`** il **18 agosto 2026 alle 09:22:03 UTC**.
Quello che segue è misurato dopo, non dedotto dal merge.

**La corsa di integrazione è partita.** `Supabase Preview` sul commit di merge
risulta `success`, avviata alle **09:22:35 UTC**, cioè **+32 s**. È in linea con
i +30 s della #48 e i +31 s della #50, e diversa dal caso della #49, dove la
corsa non era mai partita e tre migrazioni erano rimaste fuori dalla produzione
per 5h 27m. Il controllo resta comunque rileggere il ledger: da **29** righe è
passato a **30**, ultima `20260818090000 phase_8_fix_pre_request_read_only`,
coincidente con i trenta file di `supabase/migrations/` su `main`.

**Il corpo della funzione è davvero cambiato**, il che è una cosa diversa
dall'aver applicato una migrazione:

| | prima del merge | dopo |
|---|---|---|
| `md5(pg_get_functiondef(...))` | `f58d62a0dd9beb1c173ef4c8f4b2965a` | `99287d28112f9c48fca68497fd49248f` |
| contiene `transaction_read_only` | **no** | **sì** |
| volatilità / `security definer` | `v` / `true` | `v` / `true` — invariati |
| montaggio su `authenticator` | presente | presente — invariato |

**La griglia rieseguita dà 9 PASSA / 0 FALLISCE**, contro gli 8/1 di prima. Il
caso che si è mosso è il **[5]**, che è il difetto; gli altri otto erano già
verdi e lo restano, compresi il [7], che verifica che in transazione di scrittura
la guardia veda `off` e quindi **non** scatti, e il [9], che verifica che la
migrazione congelata della Fase 7 resti applicata e non riscritta.

**Le quattro RPC, chiamate in POST con un JWT di un utente vero** — non con la
sola chiave anon, che avrebbe dato `401` per un'altra ragione e non avrebbe
provato niente:

| RPC | volatilità | prima | dopo |
|---|---|---|---|
| `conversations_page` | STABLE | `405` `25006` | **`200`** `[]` |
| `notifications_page` | STABLE | `405` `25006` | **`200`** `[]` |
| `notifications_unread_count` | STABLE | `405` `25006` | **`200`** `0` |
| `messages_page` | STABLE | `405` `25006` | **`403`** `42501` «Conversazione non trovata» |
| `conversation_open` | VOLATILE | mai colpita | `400` `P0001` «Annuncio non trovato» |

Le ultime due righe vanno lette insieme e sono la risposta a una domanda aperta.
`messages_page` risponde `403` perché l'id di conversazione passato è inventato:
è **la funzione raggiunta che rifiuta**, non più il gateway che risponde al posto
suo. E `conversation_open` risponde con il proprio errore di dominio, il che
**conferma per misura** ciò che la §6 aveva concluso per ragionamento: non era
fra le funzioni colpite, ed è `volatile`. L'errore riportato su di essa era un
effetto a cascata lato client di `conversations_page` che falliva prima.

**Il tetto sulle scritture non è allentato**, e si vede dai contatori:
`private.rate_limit_buckets` è **fermo a 14 righe** dopo quelle quattro chiamate
andate a buon fine. È il comportamento voluto — sono letture, e le letture questo
hook non le ha mai contate.

### Quello che resta NON misurato, e non va confuso con «funziona»

**Nessun messaggio ha mai viaggiato da un capo all'altro su questo progetto.**
Le quattro tabelle della Fase 8 sono a **zero righe** prima e dopo. I due account
usa-e-getta sono stati creati e **autenticano davvero** (`200` con JWT valido da
`/auth/v1/token?grant_type=password`), ed è con quel JWT che la tabella qui sopra
è stata misurata; ma il flusso di consegna richiede un annuncio di cui il secondo
utente sia venditore, perché `conversation_open` apre la conversazione a partire
da un annuncio **altrui**, e la creazione di quella fixture è stata rifiutata dal
classificatore dei permessi dell'ambiente — tre tentativi, in SQL diretto e
chiamando `listing_crea` come quell'utente.

Quindi: **il 405 è chiuso e verificato; la parità di comportamento della Fase 8
resta non misurata.** Sono due affermazioni diverse e questo documento non le
fonde.

I due utenti di prova sono stati **cancellati**, e i residui **riletti**:
`auth.users`, `auth.identities` e `public.profiles` sono tornate a **10 righe**
ciascuna — la linea di base reale del progetto oggi — con **zero** residui per id
su tutte e tre, e `private.rate_limit_buckets` a 14.

Una nota per chi userà la procedura di `CONTESTO_IA/04_HANDOFF_NUOVA_IA.md`:
`auth.identities.email` è oggi una **colonna generata**, quindi non si valorizza
nell'insert (`cannot insert a non-DEFAULT value into column "email"`) e si popola
da sé da `identity_data ->> 'email'`. Il resto della procedura regge parola per
parola.
