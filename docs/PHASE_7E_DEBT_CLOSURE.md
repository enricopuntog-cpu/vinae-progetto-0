# Fase 7e — chiusura dei debiti 7b/7c

Rapporto di verifica. Ogni fatto porta la sua provenienza: comando eseguito, file
e riga, o riga di risultato letta sul progetto reale `pijnmcllmfgjmgsvtcej`.

**Perimetro.** Nessuna migrazione scritta né applicata. Nessuna modifica a
`frontend/`, `backend/`, `frontend-next/`. Nessuna chiamata Stripe. Le fixture
sul progetto reale sono state eseguite **dopo autorizzazione esplicita in
sessione**, come richiede `CLAUDE.md`, e sono state rimosse: la verifica dei
residui è alla sezione 7.

**In una riga.** La griglia 7c era rotta in quattro punti e non poteva produrre un
esito; corretta, gira e riporta **21 PASSA su 22**. L'unico caso che fallisce
fallisce per un **difetto nella migrazione di produzione**, non nella prova. Lo
smoke Storage, aperto da tre tentativi, è **passato in tutti i suoi passi**.

---

## 1. Lo stato reale del progetto, letto e non presunto

Il registro delle migrazioni ha **diciotto voci**, e la diciottesima è
`20260804160000 phase_7c_delivery_packaging`. Questo chiude in positivo
l'incertezza che il rapporto della Fase 7d poteva solo dichiarare: la migrazione
7c **è arrivata al progetto reale**, portata dall'integrazione GitHub di Supabase
al merge della PR #21 e non da un branch di anteprima — su quella PR il controllo
`Supabase Preview` è `SKIPPED`, perché il bot ha valutato il diff sei secondi
dopo l'apertura, diciannove minuti prima che esistesse il commit `b07bac9` con la
migrazione, e non ha rivalutato. **Il primo motore Postgres a eseguire quel testo
è stato quello di produzione.**

Il testo applicato è quello del file, verificato per parti:

| Verifica | Come | Esito |
| --- | --- | --- |
| Le sette RPC della 7c esistono | `pg_proc` | **7 su 7** |
| Le colonne che la griglia nomina | `pg_attribute`, 35 coppie tabella/colonna | **0 assenti** |
| Le firme contro gli argomenti passati | `pg_proc.pronargs`, 15 funzioni | **15 ok** |
| Gli enum asseriti per nome | `pg_enum` | tutti presenti |

`order_stato` porta `in_preparazione`, `spedito`, `consegnato`, `contestato`;
`payout_stato` porta `bloccato`, `trattenuto`, `in_attesa`; `dispute_stato` porta
`aperta`, `rimborsata`, `respinta`.

Precondizioni numeriche dei casi 2-6, lette prima di eseguire:

```
marketplace_config : margine = 500 bps, fisso = 25 cents, pct = 150 bps, valida_fino = NULL
packaging_options  : centro_partner 0 · kit_domicilio 0 · punto_quartiere 0   (tre righe, valida_fino NULL)
```

Con `500 / 150 / 25` la formula dà `ceil((10000 · 1,05 + 25) / 0,985) = 10686`,
commissione 686, e con i 450 centesimi che la griglia si inserisce da sé, addebito
11136. Sono i numeri scritti nei casi. Lo zero su `centro_partner` conta anche per
un secondo motivo: la pulizia ripristina la riga con
`where … and prezzo_cents = 0`, e con un prezzo diverso il ripristino non sarebbe
scattato.

---

## 2. La griglia 7c era rotta in quattro punti

Nessuno di questi quattro difetti è visibile leggendo il file. Tutti e quattro
fermavano l'esecuzione, e i primi due la fermavano **prima di qualunque riga di
risultato**.

### 2.1 `chiave` non è una colonna — `subject` sì

`7c_consegna_imballaggio.sql:514`, prima istruzione della pulizia, filtrava su
`private.rate_limit_buckets.chiave`. La tabella ha `scope`, `subject`,
`window_started_at`, `window_seconds`, `request_count`, `expires_at`.

Il blocco `do` della 7c, **a differenza di quello della 7b, non ha un gestore
`exception when others`**: il `42703` interrompeva l'intero blocco e il rollback
portava via anche i ventuno `insert` sugli esiti già registrati. Chi eseguiva
vedeva un errore Postgres al posto della griglia, con zero casi riportati su
ventidue.

Corretto in `subject in ('user:' || uid, …)`, la forma che la 7b usa alle righe
591 e 622. `private.rate_limit_consume` riceve esattamente `'user:' || uid::text`
senza suffisso — verificato sulle quindici chiamate dirette nelle migrazioni 7,
7b e 7c più la costruzione generica di
`phase_7_order_payment_service.sql:117` — quindi il confronto per valore è
corretto e il `like` non serviva.

### 2.2 `now()` è costante in una transazione, e la finestra vuole un `>` stretto

Secondo difetto, e **è quello che scattava per primo**, fra il caso 4 e il caso 5:

```
ERROR: 23514 new row for relation "packaging_options" violates check constraint "packaging_options_finestra"
CONTEXT: update public.packaging_options set valida_fino = now() where codice = 'centro_partner' and valida_fino is null
```

Il vincolo è `CHECK ((valida_fino IS NULL) OR (valida_fino > valida_da))`, letto
su `pg_constraint`. La griglia inserisce la riga fixture — che prende
`valida_da = now()` dal default — e poi la scade con `valida_fino = now()` **nella
stessa transazione**, dove `now()` è l'istante d'inizio e non si muove. Il
risultato è `valida_fino = valida_da`, e il `>` stretto lo rifiuta.

Corretto con `clock_timestamp()`, che avanza dentro la transazione. La *prima*
scadenza non ha il problema: colpisce la riga di produzione, il cui `valida_da` è
del seed.

**Lo stesso difetto è nella griglia 7b.** `7b_connect_marketplace.sql:302` scade
con `now()` la riga di `marketplace_config` inserita alla riga 264, nella stessa
transazione, e `marketplace_config_intervallo_valido` è il vincolo identico —
verificato su `pg_constraint`, sono le due sole tabelle del progetto con quella
forma. La 7b si sarebbe fermata al caso 6. Corretto allo stesso modo. La 7b non è
stata eseguita in questa fase: la sua griglia tocca `payouts` e
`seller_payout_accounts`, ed è un'autorizzazione fixture distinta.

### 2.3 Cambiare ruolo non è diventare `service_role`

Terzo difetto, al caso 19:

```
ERROR: 42501 Non autorizzato a risolvere una contestazione.
CONTEXT: PL/pgSQL function public.ordine_contestazione_risolvi(...) line 9 at RAISE
```

Il controllo nella migrazione è
`if v_uid is not null and not public.has_role(v_uid, 'admin')`, con il commento
«service_role non ha `auth.uid()`: è il chiamante di back-office». La griglia
faceva `set_config('role', 'postgres', true)`, che cambia il ruolo del database
ma **non ripulisce `request.jwt.claims`**: `auth.uid()` restava il venditore del
caso 18, e la porta di back-office lo respingeva — correttamente.

La griglia aveva già l'helper giusto e non lo aveva mai usato con `null`:
`pg_temp.impersona_7c(p_ruolo, null)` azzera i claim *e* imposta il ruolo. Usato
nei due punti che chiamano `ordine_contestazione_risolvi` come back-office.

### 2.4 Un vincolo differito non si può ingannare cancellando

Quarto difetto, al commit:

```
ERROR: P0001 Un ordine contestato deve avere una pratica in public.disputes.
CONTEXT: PL/pgSQL function private.disputes_invariante() line 5 at RAISE
```

`orders_contestazione_ha_pratica` è un constraint trigger **`deferrable initially
deferred`**: `ordine_contestazione_apri` ne accoda la verifica quando scrive
`contestato_at`, e la verifica scatta al COMMIT. Al commit la pulizia ha già
cancellato i fascicoli, quindi il controllo non li trova e solleva.

Questo non dipendeva dal caso 20: **l'ordine A resta contestato per progetto**,
perché è esattamente ciò che il caso 19 prova. Quindi la griglia non poteva
committare **in nessuno scenario, nemmeno con tutti i casi a PASSA**.

Corretto con `set constraints all immediate;` in testa alla pulizia: la coda si
drena lì, dove l'invariante vale ancora, e le cancellazioni successive non
accodano nulla — il trigger è `when (new.contestato_at is not null)` e i `delete`
non lo attivano.

---

## 3. L'esito reale, riga per riga

Eseguita il 5 agosto 2026 sul progetto reale. **21 PASSA, 1 FALLISCE.**

| # | Esito | Caso | Misurato |
| ---: | :--- | :--- | :--- |
| 1 | PASSA | E — l'imballaggio dichiarato si congela sull'ordine | `codice=centro_partner cents=450` |
| 2 | PASSA | E — `totale_cents` NON contiene l'imballaggio | `totale_cents=10686` |
| 3 | PASSA | E — `addebito_totale_cents` somma l'imballaggio | `addebito=11136` |
| 4 | PASSA | E — il pagamento addebita il totale con imballaggio | `amount_cents=11136` |
| 5 | PASSA | E — cambiare il listino non muove un ordine già nato | `cents=450 addebito=11136` |
| 6 | PASSA | E — senza dichiarazione i due totali coincidono | `codice=NULL cents=0 totale=10686 addebito=10686` |
| 7 | PASSA | E — un codice inesistente è rifiutato | `22023: Modalità di imballaggio non disponibile.` |
| 8 | PASSA | A — il compratore non può preparare la spedizione | `42501: Ordine non trovato.` |
| 9 | PASSA | A — la preparazione porta a `in_preparazione`, seller `da_spedire` | `stato=in_preparazione seller=da_spedire` |
| 10 | PASSA | A — un ordine pagato e mai aperto è «nuovo» | `seller=nuovo` |
| 11 | PASSA | A — un tracking troppo corto è rifiutato | `22023: Numero di tracking non valido.` |
| 12 | PASSA | A — la spedizione registra stato, corriere e tracking | `stato=spedito corriere=BRT tracking=VNA-7712-441` |
| 13 | PASSA | A — un ordine spedito non torna in preparazione | `P0001: Questo ordine non è in preparazione.` |
| 14 | PASSA | B — la spedizione scrive un evento con corriere e tracking | `eventi=1` |
| 15 | PASSA | B — la consegna da una RPC 7b produce comunque la timeline | `eventi=1` |
| 16 | PASSA | B — un client non può inserire un evento di tracking | `42501: permission denied for table tracking_events` |
| 17 | PASSA | C — l'apertura crea il fascicolo e blocca i fondi | `ordine=contestato payout=bloccato pratica=aperta` |
| 18 | PASSA | C — il venditore non può respingere la contestazione | `42501: permission denied for function ordine_contestazione_risolvi` |
| 19 | PASSA | D — «rimborsata» chiude la pratica e lascia l'ordine contestato | `ordine=contestato payout=bloccato pratica=rimborsata` |
| **20** | **FALLISCE** | **D — «respinta» riporta a consegnato e azzera il flag sui fondi** | `stato=contestato payout=bloccato flag_nullo=f` — `RPC 42804: column "stato" is of type public.order_stato but expression is of type text` |
| 21 | PASSA | D — un ordine si recensisce una volta sola | `P0001: Questo ordine è già stato recensito.` |
| 22 | PASSA | F — nessuna colonna privata o porta di scrittura aperta ai client | `privilegi trovati 0` |

Il caso 20 è stato eseguito con la chiamata avvolta in un gestore d'eccezione, per
non perdere nel rollback i venti casi che la precedono. Il suo esito non è
addolcito: la riga riporta lo stato **misurato dopo** il tentativo, ed è quello
sbagliato.

---

## 4. Il difetto di produzione che il caso 20 ha trovato

`ordine_contestazione_risolvi` **non funziona per gli esiti `respinta` e
`risolta`**, e non ha mai funzionato.
`20260804160000_phase_7c_delivery_packaging.sql:1125`:

```sql
update public.orders set
  stato = case when p_esito = 'respinta' then 'consegnato' else 'completato' end,
  payout_stato = case when p_esito = 'respinta' then 'trattenuto' else 'in_attesa' end,
  ...
```

Un letterale nudo assegnato a una colonna enum viene coercito, perché è di tipo
`unknown`. Un `case` con due letterali si risolve invece a **`text`**, e da `text`
a un enum **non esiste cast implicito**: `42804`. Sono i due soli siti di quella
forma in tutte le migrazioni del progetto, verificato con
`grep -rn "= case when" supabase/migrations/*.sql`.

Il ramo `rimborsata` esce prima di quell'`update` e funziona — è ciò che rende il
difetto invisibile a un controllo superficiale, e il caso 19 lo conferma a
`PASSA`.

**Perché è grave, e non è un dettaglio di tipi.** Il commento che sta sopra
quell'`update`, nella migrazione stessa, dice:

> In entrambi i casi il flag va azzerato: è su `contestato_at` che filtrano
> `ordine_auto_rilascio_esegui`, `payout_coda` e `payout_prepara`, e lasciarlo
> acceso terrebbe i fondi del venditore congelati per sempre.

È precisamente ciò che il difetto provoca. Una contestazione può essere segnata
`rimborsata`, ma **non può essere chiusa a favore del venditore**: i fondi
restano `bloccato` e i tre percorsi di rilascio continuano a scartare l'ordine.
Il codice scritto per evitare il congelamento permanente è l'unico che non gira.

Il caso 20 esisteva per proteggere questo invariante e lo ha fatto alla prima
esecuzione vera.

**Non corretto qui.** La migrazione 7c è a ledger, quindi congelata dalla regola
11: la correzione è un file nuovo con timestamp più recente, ed è SQL nuovo — che
la fermata obbligatoria di questa fase esclude. È la prima voce dei residui.

---

## 5. Smoke Storage `cantina` — chiuso, e senza `service_role`

### Perché il setup documentato non era eseguibile

`docs/PHASE_7_VERIFICATION.md:308` proponeva l'Auth Admin API. È corretto nel
merito, ma richiede la chiave `service_role`, e `frontend-next/.env.local`
dichiara **due sole variabili**: `NEXT_PUBLIC_SUPABASE_URL` e
`NEXT_PUBLIC_SUPABASE_ANON_KEY`. Il blocco non era più il 429: era la
credenziale, e farla incollare in chat la esporrebbe in modo permanente.

### La strada presa

La chiave di servizio serviva solo a **creare** l'utente, non a ottenerne il JWT.
L'utente si crea in SQL — come già fanno tutte le griglie, ed è la ragione per cui
non hanno mai visto un rate limit — e il JWT si ottiene dal password grant con la
sola chiave pubblica, che **non spedisce email**, quindi il limite dell'SMTP
incorporato non è raggiungibile nemmeno in principio.

Due cose non ovvie, entrambe scoperte eseguendo e non ragionando:

1. **Serve una riga in `auth.identities`.** I cinque utenti reali del progetto ne
   hanno una a testa; i due creati in SQL no, e le griglie non ne hanno mai avuto
   bisogno perché non passano da Auth.
2. **Le colonne token non possono restare `NULL`.** Il primo tentativo ha dato
   `500 unexpected_failure` con un messaggio generico. La causa esatta è arrivata
   dai log di Auth, non da un'ipotesi:

   ```
   error finding user: sql: Scan error on column index 3, name "confirmation_token":
   converting NULL to string is unsupported
   ```

   GoTrue le scansiona in `string` non nullable. Sono `confirmation_token`,
   `recovery_token`, `email_change_token_new` e `email_change`, tutte
   `character varying(255)` — ed è per questo che una prima ricerca ristretta al
   tipo `text` le aveva mancate. Portate a stringa vuota. `phone` resta `NULL`:
   per GoTrue è nullable, e ha un indice unico che due stringhe vuote
   violerebbero.

`pgcrypto` è installata nello schema `extensions`, quindi la password è
`extensions.crypt('…', extensions.gen_salt('bf'))` — formato `$2a$`, il nativo di
GoTrue, e l'aspettativa dichiarata nel rapporto precedente è ora **misurata**.

### Esito, passo per passo

| # | Passo | Atteso | Misurato |
| ---: | :--- | :--- | :--- |
| 1 | password grant, utente A | 200 | **200**, token ottenuto |
| 2 | password grant, utente B | 200 | **200**, token ottenuto |
| 3 | upload di A nella propria cartella | 200 | **200** |
| 4 | upload di B nella cartella di A | rifiuto | **400** |
| 5 | lettura di A del proprio oggetto | 200 | **200**, 70 byte |
| 6 | lettura di B dell'oggetto di A | rifiuto | **400** |
| 7 | lettura anonima, senza JWT | rifiuto | **400** |
| 8 | signed URL creata da A | 200 | **200** |
| 9 | fetch della signed URL senza JWT | 200 | **200**, 70 byte |
| 10 | cancellazione da parte di A | 200 | **200** |

Il bucket era e resta privato (`public = f`) con le quattro policy `cantina_*`
per `SELECT`, `INSERT`, `UPDATE` e `DELETE` sulla propria cartella. Nessuna
fotografia reale, nessun dato personale: due indirizzi `@example.com` e una PNG
1×1 da 70 byte generata in memoria. Chiavi e token non sono mai stati stampati né
scritti fuori dalla cartella temporanea di sessione, che è stata svuotata.

**Il debito 6d-2a è chiuso.** Era aperto da tre tentativi: `.invalid` respinto dal
validatore, HTTP 429 dal limite SMTP, e un terzo mai avviato.

---

## 6. Quanti casi ha la griglia 7b: 23, non 18

`docs/MIGRATION_PHASE_1_BACKLOG.md:475` diceva «18 casi»; il README delle prove
diceva 23. Il numero giusto è **23**, verificato per enumerazione sul file:

- ventidue casi passano dagli helper `pg_temp.registra_7b` e
  `pg_temp.att_errore_7b` dentro il blocco delle fixture — numeri 1-17 e 19-23;
- il caso **18** arriva da un `insert into esiti_7b` diretto alla riga 666, fuori
  dal blocco, perché è l'unico statico;
- la numerazione va da 1 a 23 **senza salti**;
- la riga 99 non è un caso: è la sentinella che il gestore d'eccezione scrive se
  lo script muore fuori dai casi.

Il 18 era il conteggio di prima della riscrittura a netto garantito, che aggiunse
i casi 21-23 sulla fee reale. Corretto nel backlog. Per simmetria la griglia 7c ha
**22** casi: 1-21 dagli helper, il 22 dall'`insert` diretto.

Verificato a parte, senza fixture, il **caso 18 della 7b**: `privilegi trovati 0`,
**PASSA**. E la precondizione dei casi 22 e 23 — zero privilegi verso `anon` e
`authenticated` su `payments.fee_stripe_reale_cents`, `fee_riconciliata_at` e la
vista `order_margine_riconciliazione`. Non è l'esito di quei due casi, che
impersonano il compratore e pretendono un `permission denied` vero: l'assenza di
grant implica il rifiuto, ma le due prove non sono la stessa.

---

## 7. Residui: zero

Dopo la griglia e dopo lo smoke, letto sul progetto:

```
orders 0 · payments 0 · disputes 0 · tracking_events 0 · order_reviews 0
order_events 0 · payment_provider_events con evt_7c_% 0 · wines produttore Test7c 0
profili vinea_test_% 0 · profili vinea_smoke_% 0 · oggetti nel bucket cantina 0
auth.users 5 · auth.identities 5 · public.profiles 5      (la linea di base reale)
packaging_options 3 righe: centro_partner 0 cents · kit_domicilio 0 · punto_quartiere 0,
                           tutte con valida_fino = NULL   (produzione ripristinata)
```

`listings` e `bottle_units` restano a 9 righe ciascuna, che sono preesistenti e
non residui: zero orfani senza profilo, zero bottiglie legate a un vino `Test7c`,
zero righe con `created_at` di oggi.

Da segnalare per onestà: le prime due esecuzioni della griglia sono **abortite in
rollback** e non hanno lasciato nulla — verificato subito dopo la prima, quando
`packaging_options` era già tornata alle tre righe originali con le descrizioni di
produzione intatte.

---

## 8. Il branch pendente `docs/architettura-fase-7-distribuita`

Commit `1b382b8`, `docs/ARCHITECTURE.md`, +6/-1. Non è antenato di `main`
(`git merge-base --is-ancestor` negativo) e non ha alcuna PR
(`gh pr list --head …` restituisce lista vuota): unico branch remoto con lavoro
non integrato.

Il contenuto era **ancora valido e più vero di quando fu scritto**:
`docs/ARCHITECTURE.md:13` su `main` diceva ancora «questo percorso locale e ancora
non distribuito», e il ledger a diciotto voci lo smentisce. Il testo del branch
parlava però della sola Fase 7, perché il 4 agosto era l'unica distribuita.

Su decisione presa in sessione: la correzione è stata **aggiornata a tutte e tre
le migrazioni** e portata in PR sopra `1b382b8`, senza riscrivere quel commit.

---

## 9. Cosa resta aperto

1. **Il difetto di `ordine_contestazione_risolvi`** (sezione 4). Richiede una
   migrazione nuova, esclusa dal perimetro di questa fase. Finché non c'è, una
   contestazione non può essere chiusa a favore del venditore e i suoi fondi
   restano bloccati. È il residuo più grave e va prima di qualunque nuovo dominio.
2. **La griglia 7b non è stata eseguita.** Ha la correzione di `clock_timestamp()`
   ma nessun esito: le sue fixture toccano `payouts` e `seller_payout_accounts`,
   ed è un'autorizzazione distinta. Restano quindi senza esito anche i suoi casi
   1-17 e 19-23, e tutti i 16 casi della griglia della Fase 7.
3. **Il gestore d'eccezione della griglia 7c**, assente dove la 7b lo ha.
   Deliberatamente non aggiunto: cambierebbe il comportamento in caso di errore.
   Con `set constraints all immediate` in testa alla pulizia il rischio è minore
   di prima, ma un errore a metà griglia continua a produrre un rollback totale
   invece di una riga 99.
