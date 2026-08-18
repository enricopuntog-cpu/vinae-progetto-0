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
