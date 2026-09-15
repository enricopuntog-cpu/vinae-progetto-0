# Vetrina a successo — documento di progettazione

> **Documento di sola progettazione. Nessuna riga di codice, nessuna migrazione,
> nessun SQL applicato.** L'SQL della §11 è mostrato perché sia discutibile, non
> perché sia pronto: non esiste come file sotto `supabase/migrations/`, non è
> stato eseguito da nessuna parte e non deve esserlo prima di una decisione
> separata.
>
> **Ammissione.** «Nessuna funzionalità nuova durante la migrazione» resta in
> vigore. La vetrina a successo è ammessa **per eccezione esplicita e per nome**
> da Enrico il **14 settembre 2026**, come già avvenuto per le quattro
> funzionalità della Fase 11 e per la 12b+12c. L'ammissione riguarda la
> **progettazione**; l'implementazione richiede una decisione separata.
>
> **Stato di riferimento.** Le righe di codice citate sono quelle di
> `origin/main` al commit `0a226aa`. Lo stato di produzione citato in §3 è stato
> letto in sola lettura sul progetto `pijnmcllmfgjmgsvtcej` il **15 settembre
> 2026**.

---

## 1. Che cos'è

Un venditore può attivare la **vetrina** su un proprio annuncio. Se e solo se
quella bottiglia si vende, la piattaforma trattiene il **4% del prezzo del
venditore** dal bonifico che gli spetta. Se non si vende, il venditore non paga
nulla.

Il compratore non vede alcun ricarico: **il totale che paga è identico con o
senza vetrina**.

Due conseguenze vanno dette subito, perché sono il documento intero:

1. Si rompe deliberatamente l'invariante «il venditore incassa esattamente il
   prezzo che chiede» — ma **solo per chi sceglie la vetrina**, e solo su un
   annuncio per cui l'ha scelta. Chi non la attiva continua a incassare
   `prezzo_cents` esatti.
2. Cambia l'importo del **Transfer al venditore**, che è la parte più delicata
   del codice esistente. Tutto ciò che segue serve a dire esattamente dove
   cambia, e che cosa impedisce che quell'importo sia influenzabile da un
   client.

### 1.1 Che cosa questo documento NON decide

**Che cosa il venditore riceve in cambio del 4% non è definito da nessuna parte**
— né nell'ammissione, né qui. «Vetrina» nomina un corrispettivo, non un
servizio. Prima dell'implementazione va deciso se sia una posizione in
evidenza nella ricerca, uno spazio in homepage, un contrassegno sull'annuncio o
altro, perché la scelta ha conseguenze tecniche che questo documento non può
anticipare: vedi §13.1. Il meccanismo di **addebito** progettato qui è
indipendente dalla risposta e resta valido qualunque essa sia.

---

## 2. Perché la forma «a successo» è la parte facile

Un costo che matura solo alla vendita sembra la parte difficile e non lo è. Lo
schema della Fase 7b è già costruito attorno a un momento in cui i parametri
economici si fissano — la creazione dell'ordine — e a un momento in cui il
denaro si muove verso il venditore — il rilascio. La vetrina si inserisce in
quei due momenti e in nessun altro:

- **se non si vende, l'ordine non nasce**, e non nasce nulla da trattenere.
  Non serve uno storno, non serve un rimborso, non serve un job che ripulisca:
  la condizione «se e solo se si vende» è la stessa condizione che fa esistere
  la riga `public.orders`;
- **se si vende**, la trattenuta è un numero congelato sull'ordine alla
  creazione, esattamente come gli altri parametri economici, e viene sottratta
  in un punto solo del percorso di payout.

La parte difficile è un'altra, ed è la §6.

---

## 3. Dove il denaro si muove oggi

Misurato leggendo il codice distribuito, non dedotto.

### 3.1 Alla creazione dell'ordine

`public.order_checkout_reserve` — versione corrente in
[`20260804160000_phase_7c_delivery_packaging.sql:627`](../supabase/migrations/20260804160000_phase_7c_delivery_packaging.sql),
che sostituisce quella della 7b:

1. legge la configurazione corrente con `private.marketplace_config_corrente()`;
2. calcola il totale di mercato con `private.marketplace_totale_cents`;
3. **congela sull'ordine i tre parametri e il risultato**:
   `margine_obiettivo_bps`, `riferimento_stripe_percentuale_bps`,
   `riferimento_stripe_fisso_cents`, `commissione_cents`;
4. risolve e congela l'imballaggio dalla versione corrente di
   `public.packaging_options`;
5. crea la riga `public.payments` con
   `amount_cents = orders.addebito_totale_cents`.

Due colonne generate, e la differenza fra loro è la ragione per cui la vetrina
non tocca nulla qui:

```text
orders.totale_cents          = prezzo_cents + commissione_cents
orders.addebito_totale_cents = prezzo_cents + commissione_cents + imballaggio_cents
```

`totale_cents` è la base della formula del rincaro e della riconciliazione;
`addebito_totale_cents` è **quanto paga il compratore**, ed è l'importo della
riga `payments`. La 7c ha deliberatamente rifiutato di sommare l'imballaggio
dentro `totale_cents` perché avrebbe falsato `commissione_effettiva_bps` e fatto
pagare al compratore una commissione calcolata anche sul cartone. **La vetrina
non entra in nessuna delle due**: vedi §4.4.

### 3.2 Al rilascio

`public.payout_prepara` —
[`20260803150000_phase_7b_stripe_connect_marketplace.sql:1309`](../supabase/migrations/20260803150000_phase_7b_stripe_connect_marketplace.sql).
Qui c'è **l'unica riga in tutto il progetto che decide quanto riceve il
venditore**, alla riga 1354:

```sql
  insert into public.payouts (
    order_id, seller_id, provider, destination_account_id, amount_cents, currency,
    stato, idempotency_key
  ) values (
    v_order.id, v_order.seller_id, v_payment.provider, v_account.provider_account_id,
    -- Il venditore riceve il prezzo, non il totale: la commissione resta alla
    -- piattaforma per il solo fatto di non essere trasferita.
    v_order.prezzo_cents, v_order.currency, 'in_corso',
    'vinea-payout-' || replace(v_order.id::text, '-', '')
  )
```

L'addebito non porta `transfer_data` né `on_behalf_of`: i fondi restano sul
balance della piattaforma e il Transfer verso il venditore nasce separatamente
al rilascio («separate charges and transfers»). La commissione resta alla
piattaforma **per il fatto stesso di non muoversi**, e la trattenuta della
vetrina si comporterà esattamente allo stesso modo.

### 3.3 Stato di produzione, 15 settembre 2026

| Oggetto | Misura |
| --- | --- |
| ledger delle migrazioni | 52 voci, ultima `20260915120000_marketplace_config_margine_otto_percento` |
| `public.marketplace_config` | due righe: `id = 1` chiusa il 15/09 alle 14:58:28 con `500 / 150 / 25 / 14`; `id = 2` corrente con **`800 / 209 / 25 / 14`** |
| `public.orders`, `public.payments`, `public.payouts` | 0 righe |

Nessun ordine esiste, quindi **nessuna migrazione retroattiva sarebbe
necessaria** se la vetrina fosse implementata adesso. È una comodità di oggi e
non una proprietà del progetto: vale finché le tabelle sono vuote.

---

## 4. Lo schema proposto

### 4.1 Il flag: sull'annuncio, non sul venditore

`public.listings` guadagna due colonne:

```sql
alter table public.listings
  add column vetrina_attiva boolean not null default false,
  add column vetrina_attivata_at timestamptz;
```

**Sull'annuncio e non sul profilo** perché la scelta è per bottiglia: un
venditore può volere in vetrina la bottiglia importante e non le altre, e un
flag sul profilo renderebbe impossibile dirlo. È la stessa collocazione scelta
dalla 7c per `listings.imballaggio_codice`, e per la stessa ragione: sceglie il
venditore, sull'annuncio, prima che l'ordine esista.

**Non entra nel `grant update` del client.** Oggi
[`20260728193937_listings_catalog.sql:334`](../supabase/migrations/20260728193937_listings_catalog.sql)
concede a `authenticated` l'aggiornamento di `prezzo_cents`,
`prezzo_mercato_cents`, `condizione`, `conservazione`, `storia`,
`degustazione`, `immagini`, `tag` — e di nient'altro. `vetrina_attiva` resta
fuori da quell'elenco, per la terza regola di esposizione della 6d-1: **una
colonna con una regola di dominio dietro non è scrivibile dal client e ha una
`SECURITY DEFINER` come unica porta.** La porta è
`public.listing_vetrina_imposta`, §11.

**Non entra in `public.public_listings`.** La vista pubblica è a elenco colonne
chiuso: una colonna aggiunta oggi alla tabella base resta privata finché
qualcuno non la elenca lì dentro di proposito. Non elencarla è ciò che rende
vera, per costruzione e non per attenzione, la frase «il compratore non vede
alcuna differenza». Se in futuro la vetrina dovesse diventare visibile al
compratore — vedi §13.1 — quella sarebbe una decisione separata e una riga in
più in quella vista, non un effetto collaterale di questa.

### 4.2 L'aliquota: una colonna su `marketplace_config`, non una tabella nuova

```sql
alter table public.marketplace_config
  add column vetrina_bps integer not null default 0
    check (vetrina_bps between 0 and 5000);
```

**Perché lì.** `marketplace_config` è già la configurazione economica
versionata su `valida_da` / `valida_fino`, già letta al checkout da
`private.marketplace_config_corrente()`, già congelata sull'ordine. Una colonna
in più eredita gratuitamente il versionamento, la lettura, il congelamento e la
regola secondo cui un parametro non si modifica in luogo ma chiudendo una riga e
aprendone un'altra. Una tabella nuova avrebbe richiesto un secondo lettore, una
seconda lettura al checkout e un secondo storico da tenere allineato, per
custodire **un solo scalare**.

Il progetto crea invece tabelle versionate separate quando il dominio lo è
davvero: `public.packaging_options` è un *listino* con molti codici, e ha
infatti un indice `unique (codice) where valida_fino is null` invece di un
indice a riga unica. Il 4% non è un listino: è un numero.

**Perché `default 0` e non `default 400`.** Fail-closed. Il valore di default
viene scritto sulla riga **corrente** (`id = 2`, quella dell'8%), che è nata
prima che la vetrina esistesse: farle acquisire retroattivamente un'aliquota del
4% significherebbe dire che quella configurazione prevedeva una trattenuta che
non prevedeva. La migrazione aggiunge la colonna a zero, **poi chiude la riga
corrente e ne apre una nuova** con `vetrina_bps = 400` e gli altri quattro
parametri invariati. Lo storico resta onesto e il momento in cui la vetrina
diventa esigibile è una data leggibile nella tabella.

**Conseguenza da accettare consapevolmente.** Con la colonna qui, cambiare
l'aliquota della vetrina richiede di chiudere e riaprire la riga economica
intera, ri-timbrando anche margine e fee di riferimento con valori identici. Non
è un difetto: è la stessa disciplina che si applica a ogni altro parametro, ed è
il motivo per cui la tabella è versionata.

**Esposizione.** `vetrina_bps` **non** va aggiunta a
`public.public_marketplace_config`. Quella vista ha un significato dichiarato
nel proprio commento — «serve alla UI per calcolare un preventivo prima che
l'ordine esista» e «i tre parametri sono pubblici perché il rincaro deve essere
spiegabile a chi lo paga» — e la vetrina non entra nel rincaro e non riguarda
chi lo paga. Metterla lì renderebbe il commento falso. Serve invece una seconda
vista a elenco colonne chiuso, `public.public_vetrina_config`, con la sola
`vetrina_bps`: §11.

### 4.3 Il congelamento sull'ordine

```sql
alter table public.orders
  add column vetrina_bps integer not null default 0
    check (vetrina_bps between 0 and 5000),
  add column vetrina_trattenuta_cents integer not null default 0
    check (vetrina_trattenuta_cents >= 0);
```

**Si congelano entrambi**, il parametro e il risultato, per la ragione già
scritta dalla 7b sui tre parametri della commissione: senza il parametro un
ordine vecchio non è più spiegabile una volta che la configurazione è cambiata;
senza il risultato l'importo andrebbe ricalcolato al rilascio, e un
ricalcolo è un'occasione di divergere da ciò che era stato mostrato al
venditore.

Non serve una terza colonna booleana: **`vetrina_bps > 0` è il flag**. Una riga
con `vetrina_bps = 0` è un ordine nato senza vetrina, e lo dice senza
ambiguità.

Due vincoli, e il secondo è quello che conta:

```sql
alter table public.orders
  add constraint orders_vetrina_congelata
    check (vetrina_bps > 0 or vetrina_trattenuta_cents = 0),
  add constraint orders_vetrina_non_supera_il_prezzo
    check (vetrina_trattenuta_cents < prezzo_cents);
```

Il primo dice che non si trattiene nulla senza un'aliquota. **Non** è scritto
come una doppia implicazione — `(vetrina_bps = 0) = (vetrina_trattenuta_cents =
0)` — perché sarebbe falso: su un prezzo abbastanza basso il 4% arrotondato per
difetto vale zero centesimi, e un ordine perfettamente legittimo verrebbe
rifiutato dalla tabella.

Il secondo è la garanzia di sicurezza vera, ed è **strettamente minore**, non
minore-o-uguale: `public.payouts.amount_cents` ha già un `check (amount_cents >
0)`, quindi una trattenuta pari all'intero prezzo farebbe fallire
`payout_prepara` con un errore di vincolo in un punto dove un errore è
particolarmente costoso — a incasso già avvenuto e a fondi già fermi. Il vincolo
su `orders` rende quello stato irraggiungibile, **e vincola anche uno scrittore
privilegiato**, che è il motivo per cui è un `check` e non un controllo dentro
una funzione.

Andrebbe congelato anche `orders.vetrina_attiva_al_checkout`? No: sarebbe
`vetrina_bps > 0` scritto due volte, e due colonne che devono concordare sono
due colonne che un giorno non concordano.

### 4.4 Che cosa NON cambia — l'elenco è la garanzia

| Oggetto | Cambia? |
| --- | --- |
| `private.marketplace_totale_cents` | **No.** Non riceve nemmeno un parametro in più. |
| `orders.totale_cents` (generata) | **No.** Resta `prezzo_cents + commissione_cents`. |
| `orders.addebito_totale_cents` (generata) | **No.** Resta `prezzo + commissione + imballaggio`. |
| `orders.prezzo_cents` | **No.** Resta quello che il venditore ha chiesto. |
| `orders.commissione_cents` | **No.** |
| `payments.amount_cents` | **No.** Nasce da `addebito_totale_cents`, che non si muove. |
| `public.public_marketplace_config` | **No.** |
| `public.public_listings` | **No.** |
| il percorso del webhook e la riconciliazione dell'incasso | **No.** |

Questa tabella è l'affermazione «il compratore paga lo stesso». Non è una
promessa di attenzione: la vetrina **non aggiunge alcun addendo alla catena
delle colonne generate**, quindi l'importo addebitato non può cambiare nemmeno
per errore.

---

## 5. L'effetto esatto sul percorso di payout

Cambia **una riga**, e va scritta per intero. In `public.payout_prepara`,
l'`insert into public.payouts`:

```sql
    -- prima
    v_order.prezzo_cents, v_order.currency, 'in_corso',

    -- dopo
    v_order.prezzo_cents - v_order.vetrina_trattenuta_cents, v_order.currency, 'in_corso',
```

Tutto il resto della funzione resta identico: il lock sull'ordine, l'uscita
immediata su `gia_trasferito`, il blocco su ordine contestato, la verifica che
l'incasso sia `paid` e non rimborsato, la verifica che il venditore abbia
`charges_enabled` e `payouts_enabled`, la chiave di idempotenza derivata
dall'id dell'ordine, l'`on conflict (order_id) do update`.

Attenzione a un dettaglio dell'`on conflict`: la riga `payouts` esistente **non
aggiorna `amount_cents`** nel ramo di conflitto, e non deve iniziare a farlo.
Un secondo tentativo dopo un fallimento deve ritrasferire lo stesso importo del
primo, altrimenti la chiave di idempotenza presso il fornitore protegge un
importo diverso da quello che sta proteggendo.

Poiché il Transfer è l'unico movimento verso il venditore e la trattenuta è una
sua riduzione, **la trattenuta resta alla piattaforma per il fatto stesso di non
muoversi**, esattamente come la commissione. Non serve un secondo Transfer, non
serve un `application_fee`, non serve un `on_behalf_of`. Questo è il pregio
dell'architettura «separate charges and transfers» già scelta: aggiungere una
trattenuta è una sottrazione, non un movimento nuovo.

### 5.1 Che cosa va registrato negli eventi

Il percorso dell'ordine scrive `public.order_events`, e da lì deve poter essere
ricostruito l'estratto conto del venditore senza leggere `payouts`:

- `checkout_reserved` — il payload porta già i tre parametri economici
  congelati; aggiungere `vetrina_bps` e `vetrina_trattenuta_cents`;
- `payout_trasferito` — il payload porta già `amount_cents`, che sarà l'importo
  **ridotto**; aggiungere `vetrina_trattenuta_cents` perché l'evento dica da
  solo perché quel numero non è il prezzo.

### 5.2 La riconciliazione

`public.order_margine_riconciliazione` calcola oggi

```text
margine_proiettato_cents = totale_cents - fee_riferimento_cents - prezzo_cents
```

Con una vetrina, il ricavo reale della piattaforma su quell'ordine è più alto di
`vetrina_trattenuta_cents`, e la vista lo sottostima.

**La trattenuta non va sommata dentro `margine_*`.** Sarebbe la stessa
sostituzione che la 7c ha rifiutato per l'imballaggio: `margine_*` significa «il
margine ottenuto dal rincaro», e un margine gonfiato da un ricavo di natura
diversa renderebbe incomparabili gli ordini con e senza vetrina e falserebbe la
verifica che l'8% si realizza davvero. Servono **colonne additive**:

```sql
  o.vetrina_bps,
  o.vetrina_trattenuta_cents,
  (margine_proiettato_cents + o.vetrina_trattenuta_cents) as ricavo_proiettato_totale_cents,
  (margine_reale_cents + o.vetrina_trattenuta_cents)      as ricavo_reale_totale_cents
```

La vista non ha `GRANT` verso ruoli client — è conto economico della
piattaforma — quindi ampliarla non espone nulla. Va però **ricreata** con
`create or replace`, e `create or replace view` consente di aggiungere colonne
solo in coda.

---

## 6. Che cosa impedisce al client di manipolare la trattenuta

È la domanda centrale. La risposta non è «una funzione controlla»: sono **cinque
strati indipendenti**, quattro dei quali esistono già oggi e non vengono
toccati.

**1. `public.orders` non ha alcun `GRANT` di scrittura verso i ruoli client.**
Non è una scelta presa colonna per colonna: la tabella espone a `authenticated`
solo `grant select (...)`. `vetrina_bps` e `vetrina_trattenuta_cents` nascono
dunque non scrivibili da PostgREST **per la stessa ragione per cui non lo è
`commissione_cents`**, e non perché qualcuno si sia ricordato di escluderle.
Entrano nell'elenco `grant select`, in nessun altro.

**2. L'importo è calcolato, mai ricevuto.** `order_checkout_reserve` ha cinque
parametri — `p_buyer_id`, `p_listing_id`, `p_proposal_id`, `p_delivery_mode`,
`p_idempotency_key` — e **nessuno di essi è un importo o un'aliquota**. È la
regola che la 7b aveva già applicato alla commissione. L'aliquota viene da
`private.marketplace_config_corrente()`; il flag viene da
`listings.vetrina_attiva` letto **sotto il lock che la funzione prende già**
(`select * into v_listing from public.listings where id = p_listing_id for
update`). Nessun input del chiamante entra nel calcolo.

**3. Il flag non è scrivibile dal client.** `listings.vetrina_attiva` resta
fuori dal `grant update (...) on public.listings` e si scrive solo da
`public.listing_vetrina_imposta`, che verifica `auth.uid()`, verifica che il
chiamante sia il `seller_id` dell'annuncio, verifica lo stato dell'annuncio e
consuma un rate limit. È la forma esatta di `listing_imballaggio_dichiara`.

**4. `payout_prepara` non è raggiungibile da un client, e non riceve importi.**
È `revoke execute ... from public, anon, authenticated` e `grant execute ... to
service_role`; prende un solo parametro, `p_order_id`, e **legge** la colonna
congelata. Nemmeno l'esecutore fidato può proporre un importo diverso: non c'è
un parametro in cui scriverlo.

**5. Il vincolo di tabella lega anche uno scrittore privilegiato.**
`orders_vetrina_non_supera_il_prezzo` non vive dentro una funzione — vive nella
tabella. Una `UPDATE` diretta di `service_role` che portasse la trattenuta oltre
il prezzo verrebbe rifiutata dal database. È la stessa ragione per cui la 7b ha
messo `seller_enabled_sync` in un trigger e non nelle RPC: «così vincola anche
`service_role`, che delle RPC può fare a meno».

**Il momento in cui il flag viene letto.** Il flag viene letto una sola volta,
alla creazione dell'ordine, sotto il lock sull'annuncio. Da lì in poi
`listings.vetrina_attiva` può cambiare quante volte si vuole senza che l'ordine
si muova — che è la stessa proprietà, e lo stesso meccanismo, del congelamento
dei tre parametri economici.

---

## 7. L'arrotondamento, e in favore di chi

```sql
v_vetrina_cents := floor(v_price::numeric * v_vetrina_bps / 10000)::integer;
```

**Per difetto, e la scelta è deliberata.** La 7b arrotonda il totale **per
eccesso** e ne dà la ragione: «un centesimo sotto l'obiettivo è comunque sotto
l'obiettivo». Lì l'arrotondamento è a favore della piattaforma, su un importo
dichiarato al compratore e spiegabile con la formula pubblica.

Qui no. La trattenuta è un costo che una persona fisica paga alla piattaforma, e
arrotondarlo per eccesso significherebbe trattenere, su alcuni prezzi, un
pelo più del 4% dichiarato. Con `floor`, l'affermazione «la piattaforma trattiene
il 4% del tuo prezzo» resta vera alla lettera per ogni prezzo possibile: quando
un centesimo non si può dividere, resta al venditore.

Costa alla piattaforma **meno di un centesimo per ordine** e rende inutile una
nota a piè di pagina nel testo commerciale. Rende inoltre
`orders_vetrina_non_supera_il_prezzo` soddisfatto per costruzione a ogni
aliquota inferiore al 100%.

---

## 8. Visibilità prima della conferma

Il vincolo è che la scelta del venditore **e l'importo che gli verrà
trattenuto** siano inequivocabili prima che confermi l'attivazione.

**Il numero viene dal server, non dal browser.** Il rischio da evitare è che la
UI calcoli `prezzo × 4%` per conto proprio: sarebbe un secondo posto in cui vive
la regola economica, e il giorno in cui l'aliquota cambia i due posti
divergono. Quindi due porte:

- `public.listing_vetrina_preventivo(p_listing_id uuid)` — `stable`, riservata
  al proprietario dell'annuncio, restituisce
  `{ vetrina_bps, prezzo_cents, trattenuta_prevista_cents, incasso_previsto_cents }`
  **calcolati dal database** con la stessa espressione che userà il checkout. È
  ciò che la schermata di conferma mostra;
- `public.listing_vetrina_imposta(p_listing_id uuid, p_attiva boolean)` —
  restituisce lo stesso oggetto **dopo** aver scritto, così la schermata di
  conferma e la ricevuta dell'azione dicono lo stesso numero senza che il client
  lo ricostruisca.

**Preventivo, non promessa.** Il numero mostrato all'attivazione è calcolato con
l'aliquota corrente **in quel momento** e con il prezzo corrente dell'annuncio.
Quello che verrà davvero trattenuto è calcolato con l'aliquota corrente **alla
creazione dell'ordine** e con il prezzo di allora. Due cose possono muoversi in
mezzo:

- **il prezzo**, che il venditore stesso può cambiare — `prezzo_cents` è nel
  `grant update` del client. Se lo alza, la trattenuta sale. Questo è ovvio e
  non richiede nulla;
- **l'aliquota**, che il venditore non controlla. Questo **non** è ovvio, ed è
  la domanda aperta §13.2.

La UI deve quindi dire che cosa sta mostrando: non «ti tratterremo 1,80 €» ma
«oggi, a questo prezzo, la trattenuta sarebbe 1,80 € — il 4% del prezzo al
momento della vendita». La differenza è la sola frase che rende la schermata
onesta se l'aliquota cambia.

**Il compratore non deve vederlo.** `vetrina_attiva` non entra in
`public_listings`; `vetrina_bps` e `vetrina_trattenuta_cents` entrano invece nel
`grant select` di `orders`, che è concesso ai partecipanti dell'ordine — cioè
anche al **compratore**. Va deciso se questo sia accettabile. Il compratore
vedrebbe due colonne che non lo riguardano e che non hanno alcun effetto su
quanto ha pagato; d'altra parte la policy di `orders` non distingue per colonna
fra i due partecipanti, e distinguere richiederebbe una vista separata. La
raccomandazione è **non concedere affatto quelle due colonne ai client** e
mostrare il dato al venditore attraverso una porta dedicata: vedi §10.

---

## 9. Che cosa succede nei casi che non sono la vendita

| Caso | Effetto sulla trattenuta |
| --- | --- |
| L'annuncio non si vende, scade o viene ritirato | Nessun ordine, nessuna trattenuta. Non c'è nulla da annullare. |
| Ordine creato ma pagamento mai completato (`expired`, `annullato`) | La trattenuta è congelata sull'ordine ma `payout_prepara` non arriva mai a eseguirsi: richiede `payments.stato = 'paid'`. Nessun denaro si muove. |
| Ordine contestato | `payout_prepara` esce con `bloccato`. Nessun Transfer, nessuna trattenuta. |
| Rimborso totale | `payout_prepara` esce con `bloccato` su `amount_refunded_cents > 0`. Nessun Transfer. |
| **Rimborso parziale** | Oggi `payout_prepara` blocca su **qualunque** rimborso, quindi il caso non si presenta. Se un giorno il rimborso parziale venisse ammesso, la trattenuta andrebbe ricalcolata o rinunciata: **§13.3**. |
| Transfer fallito e ritentato | Stesso importo ridotto, stessa chiave di idempotenza. Vedi §5. |

---

## 10. RLS, privilegi, esposizione

| Oggetto | Decisione |
| --- | --- |
| `listings.vetrina_attiva`, `vetrina_attivata_at` | **Nessun** `grant update` a `authenticated`. Nessun `grant select` aggiuntivo: il venditore legge il proprio stato dalla porta `listing_vetrina_preventivo`, non dalla tabella. RLS di `listings` invariata. |
| `public.public_listings` | Invariata. La vetrina non compare. |
| `marketplace_config.vetrina_bps` | La tabella è già `revoke all ... from public, anon, authenticated` con RLS attiva. Nessuna modifica. |
| `public.public_vetrina_config` | Nuova vista `security_invoker = off, security_barrier = true`, **una sola colonna**, `grant select to anon, authenticated`. Serve a pubblicare l'aliquota come si pubblica un listino. |
| `public.public_marketplace_config` | **Invariata.** Vedi §4.2. |
| `orders.vetrina_bps`, `vetrina_trattenuta_cents` | **Nessun `grant select`** ai ruoli client, per la ragione di §8: la policy di `orders` non distingue venditore e compratore. Il venditore li legge da `public.ordine_vetrina_estratto(p_order_id)`, `SECURITY DEFINER`, che verifica `auth.uid() = seller_id`. |
| `public.listing_vetrina_imposta`, `listing_vetrina_preventivo`, `ordine_vetrina_estratto` | `revoke execute from public, anon`; `grant execute to authenticated`. `search_path = ''`. Verifica di `auth.uid()`, di proprietà e di stato dentro la funzione. |
| `public.payout_prepara` | Privilegi invariati: `service_role` soltanto. |
| `public.order_margine_riconciliazione` | Privilegi invariati: nessun `GRANT` client. |

---

## 11. L'SQL proposto — mostrato, non applicato

> **Questo blocco non è un file di migrazione.** Non esiste sotto
> `supabase/migrations/`, non è stato eseguito su nessun database — né di
> produzione, né di anteprima, né locale — e il suo `timestamp` è un
> segnaposto: quello vero va scelto al momento dell'implementazione e dev'essere
> successivo all'ultima riga del ledger allora in vigore.

```sql
-- supabase/migrations/AAAAMMGGhhmmss_vetrina_a_successo.sql   [PROPOSTA]

begin;

-- ---------------------------------------------------------------------------
-- 1. L'aliquota entra nella configurazione economica versionata
-- ---------------------------------------------------------------------------

alter table public.marketplace_config
  add column vetrina_bps integer not null default 0
    check (vetrina_bps between 0 and 5000);

comment on column public.marketplace_config.vetrina_bps is
  'Quota del prezzo del venditore trattenuta dal bonifico quando l''annuncio '
  'era in vetrina, in punti base. Non tocca in alcun modo ciò che paga il '
  'compratore. Zero significa vetrina non esigibile in questa versione della '
  'configurazione.';

-- La riga corrente è nata prima della vetrina: acquisisce zero, non 400, e la
-- vetrina diventa esigibile da una riga nuova con una data propria.
update public.marketplace_config
   set valida_fino = now()
 where valida_fino is null;

insert into public.marketplace_config (
  margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
  riferimento_stripe_fisso_cents, auto_rilascio_giorni, vetrina_bps,
  valida_da, nota
)
select
  margine_obiettivo_bps, riferimento_stripe_percentuale_bps,
  riferimento_stripe_fisso_cents, auto_rilascio_giorni, 400,
  now(),
  'Vetrina a successo attivata al 4% del prezzo del venditore. Gli altri '
  'quattro parametri sono invariati e ripetuti perché una riga di '
  'configurazione è autosufficiente.'
from public.marketplace_config
where valida_fino = (select max(valida_fino) from public.marketplace_config);

-- ---------------------------------------------------------------------------
-- 2. L'aliquota è pubblica, ma non dalla vista del rincaro
-- ---------------------------------------------------------------------------

create view public.public_vetrina_config
with (security_invoker = off, security_barrier = true)
as
select c.vetrina_bps
from public.marketplace_config c
where c.valida_fino is null;

revoke all on public.public_vetrina_config from public, anon, authenticated;
grant select on public.public_vetrina_config to anon, authenticated;

comment on view public.public_vetrina_config is
  'Aliquota corrente della vetrina a successo, a elenco colonne chiuso. '
  'Separata da public_marketplace_config perché la vetrina non entra nel '
  'rincaro e non riguarda chi lo paga: unirle renderebbe falso il commento di '
  'quella vista.';

-- ---------------------------------------------------------------------------
-- 3. Il flag sull'annuncio
-- ---------------------------------------------------------------------------

alter table public.listings
  add column vetrina_attiva boolean not null default false,
  add column vetrina_attivata_at timestamptz;

comment on column public.listings.vetrina_attiva is
  'Vetrina scelta dal venditore per QUESTO annuncio. Ha una regola di dominio '
  'dietro, quindi NON entra nel GRANT UPDATE del client: si scrive solo da '
  'listing_vetrina_imposta. Non compare in public_listings: il compratore non '
  'vede alcuna differenza, e non la vede per costruzione.';

-- ---------------------------------------------------------------------------
-- 4. Il congelamento sull'ordine
-- ---------------------------------------------------------------------------

alter table public.orders
  add column vetrina_bps integer not null default 0
    check (vetrina_bps between 0 and 5000),
  add column vetrina_trattenuta_cents integer not null default 0
    check (vetrina_trattenuta_cents >= 0);

alter table public.orders
  add constraint orders_vetrina_congelata
    check (vetrina_bps > 0 or vetrina_trattenuta_cents = 0),
  add constraint orders_vetrina_non_supera_il_prezzo
    check (vetrina_trattenuta_cents < prezzo_cents);

comment on column public.orders.vetrina_bps is
  'Aliquota della vetrina congelata alla creazione. Zero significa ordine nato '
  'senza vetrina. Una modifica successiva di marketplace_config non tocca '
  'questa riga.';
comment on column public.orders.vetrina_trattenuta_cents is
  'Quanto viene sottratto al bonifico del venditore. NON è un addendo del '
  'totale: il compratore paga addebito_totale_cents, che non contiene questo '
  'numero e non lo contiene per costruzione.';

-- Nessun grant di lettura ai ruoli client: la policy di orders non distingue
-- compratore e venditore, e queste due colonne riguardano solo il secondo.

-- ---------------------------------------------------------------------------
-- 5. La porta di attivazione, e il preventivo
-- ---------------------------------------------------------------------------

create or replace function private.vetrina_trattenuta_cents(
  p_prezzo_cents integer,
  p_vetrina_bps integer
)
returns integer
language sql
immutable
set search_path = ''
as $$
  -- Per difetto: quando un centesimo non si può dividere, resta al venditore.
  select floor(p_prezzo_cents::numeric * p_vetrina_bps / 10000)::integer;
$$;

revoke execute on function private.vetrina_trattenuta_cents(integer, integer)
  from public, anon, authenticated;

create or replace function public.listing_vetrina_preventivo(p_listing_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
  v_bps integer;
  v_trattenuta integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;

  select * into v_listing from public.listings where id = p_listing_id;
  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;

  select c.vetrina_bps into v_bps from public.marketplace_config c
  where c.valida_fino is null;
  if v_bps is null then
    raise exception 'Configurazione di mercato mancante.' using errcode = 'P0001';
  end if;

  v_trattenuta := private.vetrina_trattenuta_cents(v_listing.prezzo_cents, v_bps);

  return jsonb_build_object(
    'vetrina_attiva', v_listing.vetrina_attiva,
    'vetrina_bps', v_bps,
    'prezzo_cents', v_listing.prezzo_cents,
    'trattenuta_prevista_cents', v_trattenuta,
    'incasso_previsto_cents', v_listing.prezzo_cents - v_trattenuta
  );
end;
$$;

create or replace function public.listing_vetrina_imposta(
  p_listing_id uuid,
  p_attiva boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta.' using errcode = '42501';
  end if;
  perform private.rate_limit_consume('listing:vetrina', 'user:' || v_uid::text, 30, 60);

  select * into v_listing from public.listings where id = p_listing_id for update;
  if not found or v_listing.seller_id <> v_uid then
    raise exception 'Annuncio non trovato.' using errcode = '42501';
  end if;

  -- 'riservato' incluso di proposito: durante la finestra di prenotazione un
  -- checkout può essere in corso, e il risultato dipenderebbe da chi prende
  -- prima il lock. Deterministico non basta: dev'essere spiegabile.
  if v_listing.stato in ('venduto', 'scaduto', 'riservato') then
    raise exception 'La vetrina non è modificabile ora.' using errcode = 'P0001';
  end if;

  update public.listings
     set vetrina_attiva = coalesce(p_attiva, false),
         vetrina_attivata_at = case
           when coalesce(p_attiva, false) then coalesce(vetrina_attivata_at, now())
           else null
         end
   where id = v_listing.id;

  return public.listing_vetrina_preventivo(p_listing_id);
end;
$$;

revoke execute on function
  public.listing_vetrina_preventivo(uuid),
  public.listing_vetrina_imposta(uuid, boolean)
  from public, anon;
grant execute on function
  public.listing_vetrina_preventivo(uuid),
  public.listing_vetrina_imposta(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. order_checkout_reserve: congela la vetrina
-- ---------------------------------------------------------------------------
--
-- La funzione va RICREATA per intero a partire dalla versione della 7c, che è
-- quella in vigore. Rispetto a quella cambiano esattamente tre punti, riportati
-- qui isolati; il resto — lock, ricontrollo di idempotenza, scadenza,
-- bottiglia, proposta, imballaggio, payments — è invariato e non va riscritto
-- a memoria ma copiato dal file distribuito.
--
--   (a) dopo `v_config := private.marketplace_config_corrente();`
--
--         v_vetrina_bps := case when v_listing.vetrina_attiva
--                               then v_config.vetrina_bps else 0 end;
--         v_vetrina_cents := private.vetrina_trattenuta_cents(v_price, v_vetrina_bps);
--
--       `v_listing` è già sotto `for update` dalla riga che apre la funzione:
--       nessuna lettura aggiuntiva, nessuna nuova finestra di corsa.
--
--   (b) l'INSERT into public.orders guadagna due colonne in coda:
--
--         vetrina_bps, vetrina_trattenuta_cents
--         ...
--         v_vetrina_bps, v_vetrina_cents
--
--   (c) il payload di order_events 'checkout_reserved' guadagna
--       'vetrina_bps' e 'vetrina_trattenuta_cents'.
--
-- NON cambiano: il calcolo di v_totale, v_commissione, la risoluzione
-- dell'imballaggio e l'INSERT into public.payments, che continua a nascere da
-- v_order.addebito_totale_cents.

-- ---------------------------------------------------------------------------
-- 7. payout_prepara: l'unica riga che sposta denaro
-- ---------------------------------------------------------------------------
--
-- Anche questa va ricreata per intero dalla versione 7b. Cambia una riga
-- dell'INSERT into public.payouts:
--
--     -  v_order.prezzo_cents, v_order.currency, 'in_corso',
--     +  v_order.prezzo_cents - v_order.vetrina_trattenuta_cents,
--     +  v_order.currency, 'in_corso',
--
-- Il ramo `on conflict (order_id) do update` NON tocca amount_cents, e non deve
-- iniziare a farlo: un secondo tentativo deve trasferire lo stesso importo del
-- primo, altrimenti la chiave di idempotenza presso il fornitore protegge un
-- numero diverso da quello che sta proteggendo.
--
-- Il payload di order_events 'payout_trasferito' guadagna
-- 'vetrina_trattenuta_cents'.

commit;
```

---

## 12. La griglia che servirebbe

Sotto `supabase/tests/`, nella forma già usata da
`supabase/tests/marketplace_config_margine_otto.sql`: `begin;`, tabella
temporanea degli esiti, `pg_temp.registra(...)`, conteggio finale, `rollback;`.
**Con una corsa di controllo prima della migrazione**: una griglia verde in
entrambi i mondi non misura nulla.

A differenza della griglia del margine, questa **deve scrivere** — non esiste
un ordine da osservare finché non se ne crea uno. Le fixture vanno create nella
transazione e annullate dal `rollback`, con verifica dei residui.

| # | Caso |
| --- | --- |
| 01 | La riga corrente di `marketplace_config` ha `vetrina_bps = 400`; la precedente è chiusa e ha `vetrina_bps = 0`. |
| 02 | `public.public_vetrina_config` espone **una** riga e **una sola** colonna. |
| 03 | `public.public_marketplace_config` espone ancora esattamente quattro colonne: la vetrina non vi è comparsa. |
| 04 | `public.public_listings` non espone `vetrina_attiva`. |
| 05 | `authenticated` non ha `UPDATE` su `listings.vetrina_attiva` (`has_column_privilege`). |
| 06 | `authenticated` non ha `SELECT` su `orders.vetrina_bps` né su `orders.vetrina_trattenuta_cents`. |
| 07 | `anon` non ha `EXECUTE` su `listing_vetrina_imposta`; `authenticated` sì. |
| 08 | `listing_vetrina_imposta` chiamata da un utente che non è il venditore solleva `42501`. |
| 09 | `listing_vetrina_imposta` su un annuncio `riservato` solleva `P0001`. |
| 10 | **Ordine senza vetrina**: `vetrina_bps = 0`, `vetrina_trattenuta_cents = 0`, `payouts.amount_cents = prezzo_cents`. È il caso di non regressione. |
| 11 | **Ordine con vetrina** su 4500 cents: `vetrina_bps = 400`, trattenuta 180, `payouts.amount_cents = 4320`. |
| 12 | Nello stesso ordine: `payments.amount_cents` è **identico** a quello del caso 10 a parità di prezzo e imballaggio. È l'affermazione «il compratore paga lo stesso», misurata. |
| 13 | `orders.totale_cents` e `orders.addebito_totale_cents` identici fra caso 10 e caso 11. |
| 14 | Bordi dell'arrotondamento: prezzi 1, 24, 25, 1000, 10000, 50000 cents — la trattenuta è `floor(prezzo × 4%)` e **mai** superiore. |
| 15 | `orders_vetrina_non_supera_il_prezzo` rifiuta una `UPDATE` diretta che porti la trattenuta a `prezzo_cents`. |
| 16 | `orders_vetrina_congelata` rifiuta `vetrina_bps = 0` con trattenuta positiva. |
| 17 | `payout_prepara` su ordine contestato esce `bloccato` **e non crea** alcuna riga `payouts`. |
| 18 | Secondo `payout_prepara` dopo un fallimento: stesso `amount_cents`, stessa `idempotency_key`, `tentativi` incrementato. |
| 19 | `order_margine_riconciliazione`: `margine_proiettato_cents` è **identico** fra caso 10 e caso 11; il ricavo totale differisce di 180. |
| 20 | `order_events` del caso 11 contiene `vetrina_trattenuta_cents` sia in `checkout_reserved` sia in `payout_trasferito`. |

---

## 13. Domande ancora aperte

### 13.1 Che cosa riceve il venditore — decisione di prodotto

Il 4% è il prezzo di qualcosa che non è stato definito. Finché non lo è, non si
può implementare la funzionalità completa, solo il suo meccanismo di addebito.
La risposta ha conseguenze tecniche precise:

- **se la vetrina cambia l'ordinamento della ricerca**, allora diventa
  indirettamente visibile al compratore, e `public_listings` o l'ordinamento a
  monte devono saperlo. Va inoltre valutata la trasparenza sui parametri di
  ordinamento e sulla pubblicità a pagamento prevista dal Digital Services Act
  (artt. 26 e 27): un posizionamento pagato che l'utente non può distinguere da
  un risultato organico è precisamente ciò che quelle norme regolano. **Da
  chiarire con il consulente legale, non qui**;
- **se è un contrassegno sull'annuncio**, va aggiunto a `public_listings` e il
  compratore lo vede — il che è compatibile con «il totale che paga è identico»,
  ma va detto esplicitamente perché non è più vero che «il compratore non vede
  alcuna differenza»;
- **se è uno spazio in homepage o una selezione redazionale**, non tocca lo
  schema degli annunci ed è la variante con meno conseguenze.

### 13.2 L'aliquota è quella dell'attivazione o quella della vendita?

Il vincolo dato — congelare l'aliquota **sull'ordine alla creazione** — è
rispettato in ogni caso e non è in discussione. La domanda è se debba esistere
**anche** un congelamento sull'annuncio al momento dell'attivazione.

- **Come progettato qui**: vale l'aliquota corrente alla vendita. Un venditore
  che attiva la vetrina al 4% e vende dopo un aumento al 5% paga il 5%. Semplice,
  coerente con `marketplace_config`, e richiede che la UI dica «il 4% al momento
  della vendita» invece di «1,80 €».
- **L'alternativa**: `listings.vetrina_bps_congelato`, scritto
  all'attivazione e letto al checkout al posto della configurazione corrente. Il
  venditore paga esattamente ciò che ha visto. Costa una colonna, e costa il
  fatto che un aumento di listino non raggiunge gli annunci già in vetrina
  finché non vengono riattivati.

**Non è una scelta tecnica.** La seconda è più garantista verso il venditore; la
prima è più semplice da governare. Decisione di Enrico.

### 13.3 Rimborso parziale

Oggi non esiste: `payout_prepara` blocca su qualunque
`amount_refunded_cents > 0`. Se un giorno il rimborso parziale venisse ammesso,
la trattenuta andrebbe ricalcolata sul prezzo effettivamente incassato, oppure
rinunciata per intero. **Non va risolto adesso** — ma va scritto, perché il
giorno in cui il rimborso parziale viene progettato questo è un vincolo che
quella progettazione eredita.

### 13.4 Reversibilità e storico dell'attivazione

`vetrina_attivata_at` viene azzerata alla disattivazione. Va deciso se serva
uno storico delle attivazioni — utile solo se in futuro la vetrina avesse una
durata o un costo fisso, che oggi non ha. Progettarlo adesso sarebbe lavoro
speculativo.

### 13.5 La vetrina e l'aliquota professionale

Se la seconda funzionalità ammessa —
[aliquota differenziata per classe di venditore](ALIQUOTA_PER_CLASSE_VENDITORE_SPEC.md)
— venisse implementata, va deciso se l'aliquota della vetrina sia anch'essa per
classe. Con la colonna su `marketplace_config` la risposta è gratuita se si
sceglie la **strada A** di quel documento (una riga per classe: `vetrina_bps`
diventa per classe automaticamente) e richiede una colonna in più se si sceglie
la strada B. È un argomento in più per la strada A, e va registrato come tale.

---

## 14. Dipendenza esterna: il trattamento fiscale e documentale

**Da chiarire con il commercialista prima dell'attivazione. Non è una domanda
tecnica e non viene risolta qui.**

La trattenuta non è uno sconto sul prezzo: è un **corrispettivo per un servizio
reso dalla piattaforma a un venditore**, che nella maggioranza dei casi è una
**persona fisica non soggetto IVA**. Ne discendono almeno queste domande, che
vanno poste così come sono:

1. il corrispettivo è imponibile IVA, e con quale aliquota?
2. la piattaforma deve emettere un documento — fattura o ricevuta — al venditore
   privato per ogni trattenuta, o è sufficiente un rendiconto periodico?
3. il fatto che il corrispettivo sia **trattenuto** dal bonifico anziché
   incassato separatamente cambia il momento impositivo o la forma del
   documento?
4. ai fini della soglia e degli obblighi di comunicazione sui redditi dei
   venditori realizzati tramite piattaforma (DAC7 e normativa nazionale di
   recepimento), il corrispettivo trattenuto va esposto come commissione?
5. il testo commerciale mostrato al venditore deve indicare l'importo al lordo o
   al netto dell'eventuale IVA?

**Conseguenza operativa:** finché queste risposte non esistono, la funzionalità
può essere progettata e persino implementata dietro un flag chiuso, ma **non può
essere attivata verso utenti reali**. È lo stesso schema del prerequisito
esterno usato per i pagamenti: `PAYMENTS_ENABLED` resta `false` e questa
funzionalità non lo tocca in alcun modo.

---

## 15. Riepilogo dell'impatto

| Area | Impatto |
| --- | --- |
| Migrazioni | Una nuova, non applicata. Nessuna modifica a 7b/7c, che sono distribuite e **congelate**. |
| Funzioni ricreate | `order_checkout_reserve` (dalla versione 7c), `payout_prepara` (dalla versione 7b), `order_margine_riconciliazione`. |
| Funzioni nuove | `private.vetrina_trattenuta_cents`, `public.listing_vetrina_preventivo`, `public.listing_vetrina_imposta`, `public.ordine_vetrina_estratto`. |
| Colonne nuove | 1 su `marketplace_config`, 2 su `listings`, 2 su `orders`. |
| Viste nuove | 1, `public.public_vetrina_config`. |
| Invarianti di sicurezza toccati | Nessuno. L'importo del Transfer resta calcolato dal server, congelato, non ricevuto e vincolato da un `check` di tabella. |
| Invarianti economici toccati | Uno, deliberatamente: «il venditore incassa esattamente il prezzo che chiede» diventa «…a meno che non abbia scelto la vetrina su quell'annuncio». |
| `frontend/`, `backend/` | Nessuno. |
| `frontend-next/` | Le due schermate della §8, non progettate qui. |
| `PAYMENTS_ENABLED` | Invariato, `false`. |
