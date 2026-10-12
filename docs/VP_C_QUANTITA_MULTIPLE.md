# VP-C — Quantità multiple per privati e Partner

Blocco C del filone «Vinea Partner + Quantità multiple» (vedi
[`ROADMAP_V1.md`](ROADMAP_V1.md#filone-vp--vinea-partner--quantità-multiple)).
Avviato dal titolare il 12 ottobre 2026 con la decisione di prodotto: **ogni
utente Vinea — privato con Cantina personale o Partner approvato con
catalogo aziendale — registra e vende quantità multiple dello stesso vino**,
con un solo motore d'inventario e regole commerciali diverse per classe di
venditore.

Questo documento è il contratto architetturale del blocco. Lo stato di ogni
parte è dichiarato in fondo; ciò che è solo progettato è scritto come tale.

## 1. Decisione: una quantità è un conteggio di unità

`public.bottle_units` resta **l'unica fonte di verità** dell'inventario: una
riga per bottiglia fisica, con la sua posizione 3D, le note, le fotografie, il
costo d'acquisizione, lo stato (chiusa/aperta/consumata), la degustazione, lo
storico di proprietà e gli eventuali annunci e ordini.

- Nessuna colonna `quantita` viene aggiunta a bottiglie, vini o annunci. Ogni
  quantità mostrata (posseduta, in vendita, disponibile, riservata, venduta) è
  il **conteggio** di unità che soddisfano un predicato.
- Un raggruppamento visivo («Barolo 2019 — 12 bottiglie») non cancella la
  granularità: ogni azione che riguarda una bottiglia (aprire, spostare,
  annotare, vendere) agisce su **una** riga.
- Le alternative scartate: un numero decorativo su `listings` (diverge dalle
  unità reali e non sa quali bottiglie sono vendute) e una tabella di giacenze
  parallela (seconda fonte di verità che può divergere da `bottle_units`).

## 2. Attributi che distinguono le unità

Due unità sono **omogenee** — raggruppabili e vendibili nello stesso annuncio —
solo se coincidono:

| Attributo | Dove vive | Note |
| --- | --- | --- |
| Vino (produttore, nome, annata) | `bottle_units.wine_id` | l'annata fa parte dell'identità del vino |
| Formato | `bottle_units.formato` (nuovo) | attributo fisico dell'unità; prima stava solo sul vino |
| Classe d'inventario | `bottle_units.inventario` (nuovo) | `personale` o `commerciale` |
| Partner | `bottle_units.partner_id` (nuovo) | solo per le unità commerciali |
| Proprietario | `bottle_units.owner_id` | |

Condizione, conservazione e storia sono dichiarazioni dell'annuncio, valide per
tutte le sue unità: il venditore le attesta per l'insieme. Costo, data e lotto
d'acquisizione sono provenienza privata, visibile solo al proprietario, e non
distinguono le unità per l'acquirente.

Formati ammessi (elenco chiuso, CHECK sul database): 0,1875 · 0,375 · 0,5 ·
0,75 · 1 · 1,5 · 3 · 4,5 · 5 · 6 · 9 · 12 · 15 L. Le unità esistenti hanno
ereditato il formato del loro vino (tutte `0,75 L` in produzione al 12 ottobre
2026): nessun numero letto finora è cambiato.

Formato, lotto, classe, Partner, vino e proprietario sono **immutabili** dopo
la nascita dell'unità, anche per i ruoli privilegiati (trigger
`bottle_units_inventario_guard`). Il passaggio di proprietà resta quello di
sempre: l'acquirente riceve **una nuova unità**, il venditore conserva la sua
con `ceduta_at`.

## 3. Aggiunta multipla in Cantina (parte 1)

`public.cellar_bottiglie_aggiungi(produttore, nome, annata, regione, tipo,
formato, quantita, idempotency_key, visibilita, immagini, costo_per_bottiglia,
acquisita_il)`:

- crea da **1 a 120** unità identiche in una sola transazione (limite:
  dimensione ragionevole di una transazione e di una schermata, 10 casse da 12;
  chi ne ha di più ripete l'operazione);
- registra l'operazione in `private.cellar_lotti` con la chiave
  d'idempotenza (`owner_id, idempotency_key` unici) e un'impronta dei dati:
  lo stesso tentativo ripetuto restituisce **le stesse unità** (`replay`),
  la stessa chiave con dati diversi è rifiutata (`chiave_idempotenza_riusata`);
  due sessioni concorrenti con la stessa chiave si serializzano sull'indice
  unico e producono un solo lotto (provato su connessioni reali);
- il costo è **per bottiglia** e va su ogni unità; le fotografie (≤6, bucket
  privato `cantina`) sono condivise dalle unità del lotto;
- ogni unità nasce con lo stesso `lotto_id`, che è provenienza e non una
  quantità autorevole.

`cellar_bottiglia_aggiungi` (una bottiglia, usata dal frontend distribuito)
resta intatta.

## 4. Inventario commerciale del Partner (parte 1)

`public.scorte_partner_aggiungi(..., formato, quantita, idempotency_key,
immagini)` usa lo **stesso nucleo** dell'aggiunta privata
(`private.inventario_lotto_crea`) con classe `commerciale`:

- solo il titolare di un Partner **attivo** con account attivo; un Partner
  sospeso conserva le scorte ma non ne aggiunge; revocato, in verifica,
  invitato o privato → rifiuto;
- le unità restano del titolare (`owner_id`) ma sono `commerciale` e legate al
  Partner (`partner_id`); il guardiano rifiuta un'unità commerciale con un
  Partner di cui il proprietario non è titolare;
- **nessuna conversione**: una bottiglia personale non diventa commerciale e
  viceversa, perché la classe non cambia mai;
- le porte del patrimonio personale le escludono: niente apertura né
  degustazione (`inventario_commerciale`), niente posizione 3D, niente Cantina
  pubblica (CHECK `inventario = 'personale' or visibilita = 'privata'`), niente
  analitica patrimoniale (`cellar_portfolio_analitica` filtra `personale`).

Finché la parte 2 non definisce il percorso dei prodotti, un'unità commerciale
non entra in nessun annuncio (`partner_vendita_non_disponibile`).

## 5. Interruttori fail-closed

`private.inventario_impostazioni` (una riga, nessun grant client):

| Interruttore | Valore | Si accende con |
| --- | --- | --- |
| `ordini_multi_unita` | `false` | VP-E: tariffazione logistica per quantità e colli multipli |
| `vendita_partner` | `false` | VP-D: margine Partner 1500 bps e checkout professionale |

Si cambiano solo con una migrazione dei blocchi che soddisfano le dipendenze.
`PAYMENTS_ENABLED=false` resta invariato.

## 6. Annunci, prenotazioni e ordini multi-unità (parte 2)

Migrazione `20261012150000_vp_c_annunci_allocazioni_ordini.sql`.

### 6.1 Due tabelle, nessuna quantità scritta

- **`private.listing_unita`** — quali bottiglie fisiche un annuncio offre.
  Un'unità è in al più un annuncio non terminale (indice unico parziale su
  `listing_aperto`, specchio di `listings.stato` tenuto da un trigger). Il
  ritiro (`ritirata_at`) conserva la storia; la stessa bottiglia può rientrare
  con una riga nuova. Ogni annuncio storico ha ricevuto la sua riga (uno a
  uno) e ogni annuncio nuovo, da qualunque porta nasca, riceve quella della
  sua unità rappresentativa da un trigger.
- **`private.listing_allocazioni`** — quali bottiglie sono prenotate da una
  proposta accettata o da un ordine, e la loro cessione. Un'unità ha al più
  un'allocazione non rilasciata (indice unico parziale): è il vincolo che
  impedisce di vendere due volte la stessa bottiglia, anche fra sessioni
  concorrenti. Ordini e proposte accettate storici hanno ricevuto la loro
  allocazione (zero righe in produzione al 12 ottobre 2026).

Entrambe in `private`, senza grant client, con RLS; le FK verso annunci,
ordini e proposte sono in cascata (nessuna porta li cancella: scatta solo
nelle pulizie delle fixture), quelle verso le bottiglie `restrict`.

`listings.bottle_unit_id` resta come **unità rappresentativa**: sempre una
bottiglia offerta e non ceduta mentre l'annuncio è in corso
(`private.listing_rappresentante_aggiorna`), così i trigger e le letture
storiche continuano a funzionare. `listings.inventario` dice se l'annuncio è
personale o un prodotto commerciale, coincide con la classe di ogni unità ed
è immutabile.

### 6.2 Quantità derivate

`private.listing_conteggi(annuncio)` conta, fra le appartenenze:

| Quantità | Definizione |
| --- | --- |
| offerte | non ritirate e non cedute |
| disponibili | offerte, chiuse, non eliminate, del venditore, senza allocazione aperta e non scaduta |
| riservate | offerte con un'allocazione aperta e non scaduta |
| vendute | non ritirate, con un'allocazione ceduta in questo annuncio |
| ritirate | appartenenze ritirate |

Invarianti: disponibili + riservate = offerte; nessuna quantità negativa (sono
conteggi); nessuna supera le unità reali (ogni conteggio è di righe di
`bottle_units`). Un'allocazione scaduta e non ancora ripulita conta già come
disponibile; la ripulisce (`private.listing_scadute_rilascia`) la prima porta
che prende il lock dell'annuncio: checkout, proposta, accettazione, modifica
della quantità.

Lo stato fra `attivo`, `riservato` e `venduto` è una conseguenza
(`private.listing_stato_ricalcola`, solo per annunci attivi o riservati):
disponibili > 0 → `attivo`; 0 disponibili e prenotazioni → `riservato`
(`reserved_by` = il compratore se è uno solo, come per gli annunci storici);
0 disponibili, 0 prenotazioni e vendite → `venduto`, senza cancellare nulla.
`public_listings.quantita` è ora il numero di bottiglie **disponibili** e un
annuncio senza disponibili non è in vetrina.

### 6.3 Annunci da più bottiglie

- `listing_crea_lotto(unita[], prezzo_per_bottiglia, …)` — bozza da 1 a 120
  bottiglie scelte esplicitamente: tutte proprie, chiuse, identiche (vino,
  annata, formato, classe, Partner) e in nessun altro annuncio in corso o
  prenotazione. Il prezzo è **per bottiglia**. Pubblicazione, dichiarazioni
  logistiche e moderazione restano quelle di sempre; `listing_pubblica`
  verifica sotto lock **ogni** bottiglia offerta.
- `listing_quantita_imposta(annuncio, quantita, unita[]?)` — da 1 a 120,
  mai sotto le bottiglie prenotate (`quantita_sotto_prenotate`). Riduce
  ritirando bottiglie disponibili (ultime entrate, la rappresentativa per
  ultima); aumenta con le bottiglie indicate o, senza elenco, con le prime
  compatibili libere della propria Cantina (`unita_compatibili_insufficienti`
  se non bastano). Ammessa in bozza, modifiche richieste, attivo e riservato.
- Una bottiglia offerta — rappresentativa o no — non si apre, non si toglie
  dalla Cantina e non entra in un altro annuncio; una ritirata torna libera.
- Le dichiarazioni logistiche non cambiano mentre l'annuncio ha ordini aperti
  (`ordini_in_corso`): un annuncio da più bottiglie resta attivo durante le
  vendite e il piano di spedizione di un ordine pagato le legge.

### 6.4 Prenotazione, proposte e ordini

- **Checkout** (`order_checkout_reserve[_saldo]`, solo `service_role`, nuovo
  parametro facoltativo `p_quantita`): sotto il lock dell'annuncio sceglie le
  prime N bottiglie disponibili in ordine d'ingresso, crea **un** ordine con
  `quantita = N`, `prezzo_unitario_cents`, `prezzo_cents = N × prezzo` e
  N allocazioni con la scadenza della prenotazione. Una richiesta oltre la
  disponibilità è rifiutata (`quantita_non_disponibile`); la stessa chiave
  d'idempotenza restituisce lo stesso ordine.
- **Una sola determinazione economica**: la commissione si calcola una volta
  sul subtotale con la formula e i parametri congelati di sempre
  (`marketplace_totale_cents`), quindi un solo costo fisso di pagamento per
  ordine; l'imballaggio resta per ordine. `marketplace_config` (800 bps) non
  cambia e gli ordini esistenti non si muovono.
- **Rilascio**: un ordine che diventa `annullato` — scadenza, pagamento fallito
  o scaduto dal fornitore, `order_checkout_release` — rilascia le sue
  bottiglie da trigger, qualunque porta lo abbia annullato.
- **Liquidazione** (`order_settle_paid`): richiede tante allocazioni aperte
  quanta è la quantità, poi per ognuna crea l'unità nuova dell'acquirente
  (stesso vino e formato), segna `ceduta_at` su quella del venditore, toglie
  la sua posizione 3D e registra la cessione; ripeterla non trasferisce di
  nuovo. Non legge lo stato dell'annuncio: un pagamento avvenuto non si
  congela per una moderazione.
- **Proposte**: `proposals.quantita` e prezzi sempre **per bottiglia**.
  L'accettazione prenota subito le N bottiglie fino alla scadenza della
  proposta e rifiuta solo le proposte concorrenti che la disponibilità residua
  non può più soddisfare (per un annuncio da una bottiglia: tutte, come
  prima). Il checkout di una proposta riusa le sue allocazioni e la sua
  quantità. Un annuncio che esce dalla vendita (sospensione, scadenza)
  scioglie le prenotazioni delle sole proposte (`annuncio_chiuso`), mai quelle
  degli ordini.
- `orders_unico_non_annullato_per_listing` è sostituito dall'unicità delle
  allocazioni per bottiglia: più acquisti successivi dello stesso annuncio
  sono possibili, la stessa bottiglia mai due volte.

### 6.5 Gate ancora chiusi

- `ordini_multi_unita = false`: ordini e proposte per più di una bottiglia sono
  rifiutati (`multi_bottiglia_non_disponibile`). Il motore è provato a
  interruttore acceso solo dentro le transazioni di prova; il piano di
  spedizione conosce solo `bottiglia_1` e la tariffazione per colli multipli
  è VP-E. Oggi si vende **una bottiglia per ordine**, anche da un annuncio che
  ne offre molte.
- `vendita_partner = false`: un prodotto commerciale può esistere solo in
  bozza (`listing_crea_lotto` per un Partner attivo); pubblicazione,
  attivazione diretta, proposte e checkout sono rifiutati
  (`partner_vendita_non_disponibile`, `partner_checkout_non_disponibile`),
  qualunque sia lo stato del Partner, quindi nessuna tariffa dei privati può
  essere applicata a un Partner. `vetrina_partner_catalogo(partner)` legge
  solo prodotti commerciali pubblicati del Partner attivo, mai annunci
  personali del titolare: oggi restituisce `[]`.
- Partner revocato: nessuna politica nuova. I gate di VP-A/VP-B restano su
  attivo e sospeso; le sue scorte commerciali restano non vendibili per il
  gate di classe. La decisione resta del titolare.

### 6.6 Analitica e osservazioni di prezzo

`cellar_portfolio_analitica` collega acquisti e vendite **per bottiglia**
attraverso le allocazioni; gli importi di un ordine da N bottiglie si
ripartiscono (`private.quota_cents`: divisione intera, resto alla prima) e la
somma delle quote è sempre l'importo, quindi nulla è contato due volte. Le
osservazioni di prezzo usano il prezzo per bottiglia e il formato dell'unità.

### 6.7 Porte di lettura

| Porta | Chi | Che cosa |
| --- | --- | --- |
| `listing_quantita_mie()` | venditore | conteggi di ogni proprio annuncio |
| `cantina_unita_annunci()` | proprietario | le proprie bottiglie in vendita, prenotate o vendute, una per una |
| `ordine_unita(ordine)` | parti dell'ordine | al compratore le unità ricevute, al venditore le cedute |
| `vetrina_partner_catalogo(partner)` | chiunque | prodotti commerciali pubblicati del Partner attivo |
| `inventario_capacita()` | chiunque | specchio degli interruttori e dei limiti per l'interfaccia, che non ne è l'autorità |

### 6.8 Correzione della parte 1

Il formato di un'unità creata senza formato esplicito veniva copiato dal vino;
`wines.formato` è testo libero del catalogo («Magnum 1,5 L») e l'elenco chiuso
lo avrebbe rifiutato. La parte 2 lo normalizza (`private.formato_da_testo`:
litri o centilitri riconosciuti, altrimenti 0,75 L). In produzione tutti i vini
erano `0,75 L`: nessuna unità è cambiata e nessun inserimento è fallito.

### 6.9 Griglie manuali storiche

Le griglie manuali `7_ordini_pagamenti`, `7b_connect_marketplace` e
`price_intelligence_1a` falliscono già su `main` prima di VP-C (11 casi della
PI e il passo di pubblicazione della 7/7b: precedono il cancello logistico del
28 settembre 2026), con gli stessi esiti dopo VP-C. Non sono nel gate CI.

## 7. Interfacce (parte 3)

Nessuna migrazione. Tutti i numeri mostrati sono conteggi fatti dal database;
l'interfaccia non ne è l'autorità e le porte riverificano ogni gesto.

- **Cantina privata** (`/cantina`): una scheda per gruppo **vino + formato**
  (`lib/cantina/gruppo.ts`, `chiaveGruppo`: per il formato standard la chiave
  resta lo slug del vino, quindi nessuna preferenza esistente cambia). Sotto la
  scheda un riepilogo per righe («11 bottiglie · 0,75 L · 5 in vendita · 1
  aperta · 6 libere») e il **dettaglio bottiglie**: una riga per unità con
  stato, posizione, eventuale annuncio, costo e «Apri» su quella sola
  bottiglia. I comandi della scheda agiscono su una bottiglia chiusa e libera.
  Lo stato di vendita di ogni unità viene da `cantina_unita_annunci`, quindi
  anche una bottiglia non rappresentativa di un annuncio multiplo risulta in
  vendita e non apribile; se quella lettura fallisce la Cantina si mostra lo
  stesso e il database continua a rifiutare l'apertura. Si leggono solo unità
  `personale`. La vista 3D e gli altri strumenti restano per unità.
- **Aggiunta** (`/vendi`, modalità Cantina): campi Formato e «Quante
  bottiglie» (1-120), costo per bottiglia, una chiave d'idempotenza per gesto
  rinnovata solo dopo il successo; anteprima con quantità e formato.
- **Vendita** (`/vendi` da una bottiglia): «Bottiglie in vendita» fra 1 e le
  bottiglie libere dello stesso gruppo (`unitaVendibiliDelGruppo`); più di una
  passa da `listing_crea_lotto`, una sola dalla porta di sempre. Prezzo per
  bottiglia. Il selettore «Scegli dalla tua Cantina» mostra un gruppo con il
  numero di bottiglie libere invece di una scheda per bottiglia.
- **Scheda annuncio**: «Prezzo per bottiglia» e bottiglie disponibili; al
  venditore i conteggi (in vendita, disponibili, prenotate, vendute) e la
  modifica della quantità in vendita; all'acquirente, finché
  `ordini_multi_unita` è spento, la frase «Per ora si acquista una bottiglia
  per ordine» e nessun selettore. Il selettore compare solo se
  `inventario_capacita()` lo permette e porta `?quantita=` al checkout.
- **Checkout**: la quantità dall'indirizzo vale solo se intera fra 1 e le
  disponibili (e 24); la stima è sul subtotale; servizio pagamenti ed Edge
  Function `payments-checkout` passano un numero di bottiglie, mai un importo,
  e la Edge Function rifiuta valori fuori 1-24. `PAYMENTS_ENABLED=false`
  invariato.
- **Storico ordini**: «N bottiglie × prezzo» quando la quantità è maggiore di 1
  (colonne `quantita`, `prezzo_unitario_cents`).
- **Cantina commerciale del Partner**: scorte reali raggruppate per vino e
  formato da `creaScortePartnerService` (solo righe `commerciale`), modulo
  «Aggiungi scorte» per il Partner attivo (assente se sospeso), nessuna
  apertura, degustazione, stima economica o 3D; i prodotti in vetrina restano
  «pubblicazione non ancora aperta».
- **Vetrina**: il catalogo legge solo `vetrina_partner_catalogo` (prodotti
  commerciali pubblicati), mai gli annunci personali; oggi è vuoto e mostra
  «Catalogo in preparazione».

Prova locale nel browser (stack CLI 2.117.0 con le 85 migrazioni, fixture
`@vpc-e2e.test` solo locali): aggiunta di 12 Barolo 2019 dal wizard → una
scheda «12 bottiglie · 0,75 L», capitale noto 624 € = 12 × 52 €; 3 Magnum dello
stesso vino → scheda separata; apertura della bottiglia 3 dal dettaglio → una
sola unità aperta con la sua nota, 11 chiuse; vendita di 5 su 11 libere al
prezzo di 80 € per bottiglia → annuncio attivo 5/5/0/0/0; acquisto simulato di
una bottiglia (checkout di servizio e liquidazione) → 4 disponibili, una
bottiglia nella Cantina del compratore; riduzione a 3 dalla scheda; vista
dell'acquirente con 3 disponibili e «una bottiglia per ordine»; Partner attivo
con 24 unità in scorta in formato 1,5 L, vetrina con catalogo in preparazione;
375 px senza scroll orizzontale su Cantina, scheda e Cantina commerciale.

## 8. Requisiti differiti e prerequisiti

- **VP-E** (logistica per quantità e colli multipli): il piano di spedizione
  conosce solo `bottiglia_1`; servono SKU e tariffe per più bottiglie, poi una
  migrazione che accenda `ordini_multi_unita`. Il motore (allocazione di N
  bottiglie, una commissione sull'aggregato, liquidazione per unità) è già
  provato dalla griglia 12za a interruttore acceso in transazione.
- **VP-D** (vendita professionale): margine 1500 bps, checkout professionale,
  pubblicazione dei prodotti commerciali e porta per creare i prodotti
  dall'interfaccia del Partner (il database ha già `listing_crea_lotto` per le
  bozze commerciali); poi una migrazione che accenda `vendita_partner` e
  sostituisca i gate.
- **Decisione aperta del titolare**: politica del Partner revocato (scorte
  commerciali oggi conservate e non vendibili; annunci personali come i
  privati).
- **Non incluso**: correzione del formato di un'unità già creata (formato
  immutabile; per un errore si toglie l'unità e la si aggiunge di nuovo);
  fotografie per prodotto commerciale.

## 9. Stato

| Parte | Contenuto | Stato |
| --- | --- | --- |
| 1 | Formato per unità, lotti idempotenti, aggiunta multipla privata, scorte commerciali del Partner, confini fra le classi, interruttori | In produzione: PR #212 (merge `f3cd788`), migrazione `20261012090000`, griglia `12z` |
| 2 | Appartenenza annuncio-unità, allocazioni, annunci multi-unità, proposte e ordini con quantità, gate | In produzione: PR #213 (merge `c75f4d3`), migrazione `20261012150000`, griglia `12za`, concorrenza `12z_vp_c_concorrenza.sh` (6 prove) |
| 3 | Interfacce (§7) | Implementata, provata in locale nel browser; PR delle interfacce |
