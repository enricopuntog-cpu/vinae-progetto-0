# Fase 7f — verifica della correzione di `ordine_contestazione_risolvi`

Rapporto della **PR #25**. Documenta un rischio economico reale che è stato
chiuso: fino al 5 agosto 2026 nessuna contestazione poteva essere chiusa a favore
del venditore, e i suoi fondi restavano bloccati per sempre.

Ogni fatto qui ha la sua provenienza. Dove c'è un numero, è misurato.

## 1. Il difetto

`supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql:1125`, ramo
`else` di `public.ordine_contestazione_risolvi` — quello che serve gli esiti
`respinta` e `risolta`:

```sql
update public.orders set
  stato = case when p_esito = 'respinta' then 'consegnato'
                                        else 'completato' end,
  payout_stato = case when p_esito = 'respinta' then 'trattenuto'
                                               else 'in_attesa'  end,
  contestato_at = null,
  contestazione_motivo = null
where id = v_order.id returning * into v_order;
```

`public.orders.stato` è di tipo `public.order_stato` e `payout_stato` di tipo
`public.payout_stato`: due enum. L'espressione assegnata non è un letterale.

### Perché un letterale funziona e un `case` fra due letterali no

Un letterale isolato ha tipo `unknown` e si lascia coercire al tipo della colonna
di destinazione. Un `case` fra due letterali no: la risoluzione dei tipi lo porta
a `text`, e da `text` a un enum **non esiste conversione implicita**. L'`UPDATE`
non compila, e la funzione solleva alla prima esecuzione del ramo:

```
42804  column "stato" is of type public.order_stato but expression is of type text
```

Sono i **due soli siti di quella forma in tutte le migrazioni del progetto**,
verificato per ricerca su `supabase/migrations/`.

### Perché era invisibile

Il ramo `rimborsata` esce **prima** di quell'`UPDATE`: chiama
`private.tracking_registra` e salta al blocco finale. Quindi la funzione
funzionava per un esito su tre, e una chiamata parziale non la smascherava. Il
caso 19 della griglia 7c — che esercita `rimborsata` — passava.

## 2. La conseguenza sul denaro

Il commento della 7c sopra a quell'`UPDATE` dichiara l'intenzione:

> il flag va azzerato: è su `contestato_at` che filtrano
> `ordine_auto_rilascio_esegui`, `payout_coda` e `payout_prepara`, e lasciarlo
> acceso terrebbe i fondi del venditore congelati per sempre.

È esattamente ciò che accadeva, perché l'unico codice che azzera il flag è quello
che non compilava. Una contestazione respinta o risolta lasciava:

- `orders.stato = 'contestato'`;
- `orders.payout_stato = 'bloccato'`;
- `orders.contestato_at` valorizzato.

Con `contestato_at` acceso l'ordine resta fuori da ogni predicato di rilascio, e
la riga di `public.payouts` resta a `bloccato` **senza uscita**: né la conferma
del compratore né l'auto-rilascio possono più sbloccarla. Il venditore aveva
ragione nella controversia e non veniva pagato.

**Nessun ordine reale è stato colpito.** Al momento della correzione
`public.orders`, `public.payments`, `public.disputes` e `public.payouts` hanno
zero righe, riverificato dopo l'esecuzione (sezione 4). Il difetto era **latente,
non realizzato**.

## 3. La correzione

`supabase/migrations/20260805160250_phase_7f_fix_contestazione_enum_cast.sql`.
Un `create or replace function` che ridefinisce la funzione con i quattro
letterali castati:

```sql
update public.orders set
  stato = case when p_esito = 'respinta'
               then 'consegnato'::public.order_stato
               else 'completato'::public.order_stato end,
  payout_stato = case when p_esito = 'respinta'
                      then 'trattenuto'::public.payout_stato
                      else 'in_attesa'::public.payout_stato end,
  contestato_at = null,
  contestazione_motivo = null
where id = v_order.id returning * into v_order;
```

Il diff effettivo sono quattro cast. Il resto del corpo è quello della 7c,
riportato per intero perché `create or replace` sostituisce il corpo e i commenti
che motivano le decisioni (b) e (c) sparirebbero dal database.

Tre scelte, con la loro ragione:

- **la 7c non è stata modificata in place.** È a ledger sul progetto reale, quindi
  vale la regola 11: ogni correzione è un file nuovo con timestamp successivo.
- **i nomi dei due enum sono stati letti da `pg_type` prima di scrivere il cast**,
  non assunti: `public.order_stato` e `public.payout_stato`, entrambi
  `typtype = 'e'`. Il messaggio d'errore nominava solo il primo. Verificate anche
  le quattro etichette: `consegnato` (5) e `completato` (7) in `order_stato`,
  `trattenuto` (1) e `in_attesa` (2) in `payout_stato`. Un cast verso un'etichetta
  inesistente sarebbe stato un `22P02` a runtime, cioè lo stesso difetto spostato.
- **il cast sta su entrambi i rami di ogni `case`**, non solo sul primo: così il
  tipo del `case` è l'enum per costruzione, e non per una regola di risoluzione che
  un letterale in più potrebbe spostare di nuovo.

### Un secondo `42804` che non c'era

Nello stesso ramo `else`, subito sotto, `private.tracking_registra` riceve un
altro `case when p_esito = 'respinta'` — e quella chiamata non era mai stata
eseguita in vita sua. Se il terzo parametro fosse stato un enum, correggere solo
i due `UPDATE` avrebbe spostato il guasto di tre righe. Verificato prima di
scrivere: la firma è
`(p_order_id uuid, p_tipo tracking_event_tipo, p_titolo text, p_descrizione text, p_luogo text)`,
quindi `p_titolo` è `text` e il `case` è corretto così. Verificato anche che
`public.order_events.tipo` è `text` e non un enum. **I due cast sono la
correzione completa.**

## 4. Verifica sul progetto reale

Progetto `pijnmcllmfgjmgsvtcej`, 5 agosto 2026.

### 4.1 La funzione applicata è quella approvata

Letto con `pg_get_functiondef` dopo l'applicazione:

| Controllo | Prima | Dopo |
| --- | --- | --- |
| `md5` del corpo | `0152a8a984cda9748184952f79ea3bcb` | `63bc36e8aab21148ca1d88577fc1627e` |
| Lunghezza | 3378 | 3784 |
| Contiene `::public.order_stato` | no | **sì** |
| Contiene `::public.payout_stato` | no | **sì** |
| Arietà (nessun overload) | 1 | **1** |
| `prosecdef` | `true` | `true` |
| `proconfig` | `search_path=""` | `search_path=""` |

Firma, `security definer`, `search_path` e ACL non sono cambiati. L'ACL era già
chiuso ai ruoli client (`postgres=X/postgres`, `service_role=X/postgres`) e il
`revoke` in coda alla migrazione è difensivo e idempotente.

### 4.2 Il ledger

`list_migrations` restituisce **diciannove righe**. La diciannovesima è
`20260805160250 phase_7f_fix_contestazione_enum_cast`.

Questa è **l'unica migrazione del progetto applicata per via diretta e non dal
merge su `main`**, quindi è anche la sola per cui il riallineamento del filename
alla versione assegnata dal server serve davvero: nasceva `20260805120000_…` ed è
stata rinominata `20260805160250_…` mentre il file non era ancora stato pushato.
Non è una modifica in place di un file distribuito: la regola 11 non era in gioco,
la regola 10 sì. Al merge di questa PR l'integrazione GitHub troverà la versione
già registrata e non rieseguirà il file — comportamento voluto.

### 4.3 Griglia 7c rieseguita per intero: **22 PASSA, 0 FALLISCE**

`supabase/tests/7c_consegna_imballaggio.sql`, con la correzione in campo e
l'impalcatura nuova. Nessuna riga 99, quindi nessun errore fuori dai casi.

| n | Esito | Caso | Atteso | Misurato |
| --- | --- | --- | --- | --- |
| 1 | **PASSA** | E — l'imballaggio dichiarato sull'annuncio si congela sull'ordine | codice = centro_partner, imballaggio_cents = 450 | `codice=centro_partner cents=450` |
| 2 | **PASSA** | E — `totale_cents` NON contiene l'imballaggio: la base della 7b non si muove | totale_cents = 10686 | `totale_cents=10686` |
| 3 | **PASSA** | E — `addebito_totale_cents` somma l'imballaggio | addebito = 11136 | `addebito=11136` |
| 4 | **PASSA** | E — il pagamento addebita il totale comprensivo di imballaggio | amount_cents = 11136 | `amount_cents=11136` |
| 5 | **PASSA** | E — cambiare il listino non muove un ordine già nato | cents 450, addebito 11136 | `cents=450 addebito=11136` |
| 6 | **PASSA** | E — senza dichiarazione i due totali coincidono | codice NULL, cents 0, totale = addebito = 10686 | `codice=NULL cents=0 totale=10686 addebito=10686` |
| 7 | **PASSA** | E — un codice di imballaggio inesistente viene rifiutato | errore «non disponibile» | `22023: Modalità di imballaggio non disponibile.` |
| 8 | **PASSA** | A — il compratore non può preparare la spedizione | errore «Ordine non trovato» | `42501: Ordine non trovato.` |
| 9 | **PASSA** | A — la preparazione porta a `in_preparazione`, il venditore vede `da_spedire` | stato/seller | `stato=in_preparazione seller=da_spedire` |
| 10 | **PASSA** | A — un ordine pagato e mai aperto è «nuovo», non «da_preparare» | seller = nuovo | `seller=nuovo` |
| 11 | **PASSA** | A — un tracking troppo corto viene rifiutato | errore «tracking non valido» | `22023: Numero di tracking non valido.` |
| 12 | **PASSA** | A — la spedizione registra stato, corriere e tracking insieme | spedito / BRT / VNA-7712-441 | `stato=spedito corriere=BRT tracking=VNA-7712-441` |
| 13 | **PASSA** | A — un ordine spedito non torna in preparazione | errore «non è in preparazione» | `P0001: Questo ordine non è in preparazione.` |
| 14 | **PASSA** | B — la spedizione scrive un evento con corriere e tracking in descrizione | un evento | `eventi=1` |
| 15 | **PASSA** | B — la consegna dichiarata da una RPC 7b produce comunque la timeline | un evento | `eventi=1` |
| 16 | **PASSA** | B — un client non può inserire un evento di tracking | permesso negato | `42501: permission denied for table tracking_events` |
| 17 | **PASSA** | C — l'apertura crea il fascicolo e blocca i fondi via la RPC 7b | contestato / bloccato / aperta | `ordine=contestato payout=bloccato pratica=aperta` |
| 18 | **PASSA** | C — il venditore non può respingere la contestazione che blocca i suoi fondi | permesso negato | `42501: permission denied for function ordine_contestazione_risolvi` |
| 19 | **PASSA** | D — «rimborsata» chiude la pratica e lascia l'ordine contestato | contestato / bloccato / rimborsata | `ordine=contestato payout=bloccato pratica=rimborsata` |
| **20** | **PASSA** | **D — «respinta» riporta l'ordine a `consegnato` e azzera il flag che blocca i fondi** | **stato = consegnato, payout = trattenuto, contestato_at = NULL** | **`stato=consegnato payout=trattenuto flag_nullo=t`** |
| 21 | **PASSA** | D — un ordine si recensisce una volta sola | errore «già stato recensito» | `P0001: Questo ordine è già stato recensito.` |
| 22 | **PASSA** | F — nessuna colonna privata o porta di scrittura è aperta ai ruoli client | privilegi = 0 | `privilegi trovati 0` |

**Il caso 20 è la prova della correzione.** Nella Fase 7e la stessa riga
misurava `stato=contestato payout=bloccato flag_nullo=f`: i tre valori sono
cambiati tutti e tre nel verso giusto, e `flag_nullo` è passato da `f` a `t`.
Quel booleano è la cosa che conta sul denaro: è `contestato_at is null`, cioè
esattamente il predicato su cui filtrano i tre percorsi di rilascio.

Il caso 19 continua a passare, quindi la correzione **non ha rotto il ramo che
funzionava**: `rimborsata` lascia ancora l'ordine `contestato` e i fondi
`bloccato`, che è la decisione (c) della 7c — `rimborsato` lo scrive solo un
evento firmato del fornitore.

### 4.4 Provenienza dell'esecuzione, dichiarata

La griglia è stata eseguita in **una sola chiamata**, perché `esiti_7c` è una
tabella temporanea e gli helper vivono in `pg_temp`: due chiamate sarebbero due
sessioni e la seconda non troverebbe nulla.

Del file versionato è stato eseguito tutto tranne il blocco `do $verdetto$`
finale, che solleva un'eccezione se un caso non passa. Quel blocco esiste per dare
un exit code diverso da zero a un futuro job CI, ed è dichiarato tale nel file
stesso; qui avrebbe abortito la transazione e portato via proprio la tabella degli
esiti da leggere. Il verdetto è quindi calcolato dalle 22 righe qui sopra e non
da lui: **22 PASSA, 0 FALLISCE, nessuna riga 99.**

Con 0 FALLISCE quel blocco non avrebbe comunque sollevato nulla. Resta una
differenza fra ciò che il file contiene e ciò che è stato eseguito, e va detta.

### 4.5 Residui: zero su 26 controlli

Riletti dopo l'esecuzione, non dichiarati.

| Oggetto | Misurato | Atteso |
| --- | --- | --- |
| `orders` | 0 | 0 |
| `payments` | 0 | 0 |
| `payouts` | 0 | 0 |
| `disputes` | 0 | 0 |
| `tracking_events` | 0 | 0 |
| `order_reviews` | 0 | 0 |
| `order_events` | 0 | 0 |
| `payment_provider_events` (totali) | 0 | 0 |
| `payment_provider_events` con `evt_7c_%` | 0 | 0 |
| `wines` con `produttore = 'Test7c'` | 0 | 0 |
| `profiles` con `vinea_test_%` | 0 | 0 |
| `profiles` con `vinea_smoke_%` | 0 | 0 |
| `auth.users` | 5 | 5, la linea di base reale |
| `auth.identities` | 5 | 5 |
| `public.profiles` | 5 | 5 |
| `listings` | 9 | 9 preesistenti |
| `bottle_units` | 9 | 9 preesistenti |
| `listings` orfani senza profilo | 0 | 0 |
| `listings` creati oggi | 0 | 0 |
| `bottle_units` create oggi | 0 | 0 |
| `packaging_options` righe totali | 3 | 3 |
| `packaging_options` con `prezzo_cents <> 0` | 0 | 0 — produzione ripristinata |
| `packaging_options` con `valida_fino` non nulla | 0 | 0 — produzione ripristinata |
| `packaging_options` con la descrizione fixture | 0 | 0 |
| `rate_limit_buckets` con finestra di oggi | 0 | 0 |
| oggetti nel bucket `cantina` | 0 | 0 |

`listings` e `bottle_units` a 9 non sono residui: sono preesistenti, e i tre
controlli sotto di loro lo provano — zero orfani, zero righe create oggi.

La griglia tocca dati di produzione per necessità: scade la riga `centro_partner`
di `packaging_options` e ne inserisce una a prezzo non nullo, perché con
`prezzo_cents = 0` i due totali coinciderebbero e i casi 2-6 non proverebbero
nulla. Le tre righe a zero cents con `valida_fino` nulla confermano che la
pulizia ha ripristinato il listino.

## 5. L'impalcatura della griglia, e una cosa che non funzionava come dichiarato

La 7e lasciava aperta la decisione se la griglia 7c dovesse prendere il gestore
`exception when others` che la 7b ha. La risposta è **sì, ma quel gestore da solo
non fa la cosa per cui lo si voleva**, e la differenza è misurata.

Un blocco PL/pgSQL con clausola `exception` è una **sottotransazione**: quando
l'errore viene catturato, tutto ciò che il blocco ha scritto sul database viene
annullato — `esiti_7c` compresa. Provato il 5 agosto 2026 con due sonde su sole
tabelle temporanee, senza toccare dati applicativi:

| Forma | Righe superstiti dopo un guasto |
| --- | --- |
| Gestore sul blocco, come nella 7b | **1** — la sola sentinella 99 |
| Guardia dentro il caso | **4 su 4**, incluso il caso guasto e quelli dopo |

L'impalcatura è quindi in due parti:

- **tredici guardie `begin/exception` per singolo caso**, che fanno il lavoro
  vero. Ognuna avvolge l'azione e la misura, scrive `v_guasto` e lascia la
  registrazione **fuori** dalla sottotransazione. Il sesto parametro `p_guasto` di
  `registra_7c` forza `FALLISCE` a prescindere dalla condizione: senza quella
  regola un'azione annullata lascerebbe nelle variabili di misura i valori del caso
  precedente, e una condizione soddisfatta per inerzia produrrebbe un **PASSA
  falso**. Il `>>` in coda al dettaglio è il segnale che il numero accanto non va
  letto.
- **la rete esterna nella forma della 7b**, che copre ciò che sta fuori dai casi —
  allestimento dei fixture e pulizia. Un errore là non esce più come errore
  Postgres grezzo, la riga 99 ne registra `sqlstate` e messaggio, e la pulizia
  viene ritentata sul percorso d'errore. In quello scenario gli esiti dei casi sono
  perduti comunque: senza gestore la transazione abortisce e li porta via
  ugualmente, con la differenza che non si vede nulla. **Il gestore non perde mai
  più di quanto si perderebbe senza di lui.**

Aggiungere il sesto parametro cambia la firma, quindi `create or replace` avrebbe
creato un **overload** invece di sostituire: in una sessione che avesse già
eseguito una versione precedente del file, ogni chiamata a cinque argomenti
sarebbe diventata ambigua (`42725`). Per questo entrambi i registratori sono
precedute da un `drop function if exists` della firma vecchia.

La griglia 7b ha lo stesso limite sul suo gestore. **Non è stata toccata in questa
fase:** restò fuori dal perimetro verificato di quel checkpoint.

### Provenienza da correggere del rapporto della 7e

La tabella a 22 righe riportata nella Fase 7e proviene da una **variante
strumentata** della griglia, non dal file committato: in quel momento il file non
aveva alcuna guardia attorno al caso 20, quindi il `42804` avrebbe abortito la
transazione e portato via anche i 21 esiti già registrati. Il file committato oggi
la guardia ce l'ha, ed è per questo che l'esecuzione di questa fase è riproducibile
dal repository. La tabella della sezione 4.3 viene dal file come è versionato.

## 6. Cosa questa fase non ha fatto

- Nessuna riga di `frontend/`, `backend/`, `frontend-next/`.
- Nessuna chiamata a Stripe, nemmeno in test mode. `PAYMENTS_ENABLED` resta
  `false`.
- Nessuna modifica alla griglia 7b.
- L'esito `risolta` di `ordine_contestazione_risolvi` **continua a non essere
  esercitato separatamente** da `respinta`: percorrono lo stesso ramo e
  differiscono per tre costanti. Due delle tre sono proprio quelle che questa fase
  ha castato, quindi il caso 20 prova la forma del cast per entrambi; ma le righe
  di `risolta` restano corrette e non eseguite. Limite dichiarato, invariato.
- Le griglie della Fase 7 (16 casi), della 7b (23) e della 6d-2a (18) restavano
  **senza esito** a questo checkpoint. La policy allora vigente trattava le
  fixture per griglia; oggi non è un gate di conferma, ma restano obbligatori
  ambiente idoneo, isolamento, cleanup anche in errore e verifica dei residui.
