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

## 6. Annunci, prenotazioni e ordini multi-unità (parte 2 — progettata)

Progetto approvato per la migrazione successiva; **non ancora implementato**
alla data della parte 1.

- **Annuncio ↔ unità**: tabella `private.listing_unita (listing_id,
  bottle_unit_id, aggiunta_at, ritirata_at)`; un'unità è in al più un annuncio
  non terminale (indice unico parziale). `listings.bottle_unit_id` resta come
  unità rappresentativa (compatibilità con annunci, ordini e letture storiche)
  ed è sempre membro dell'annuncio. La vista di servizio
  `public.listing_bottle_units`, creata nel 2026 proprio per questo passaggio,
  diventa il riflesso della tabella. Ogni annuncio storico riceve la sua
  riga di appartenenza (uno a uno), senza cambiare comportamento.
- **Prezzo unitario**: `listings.prezzo_cents` è il prezzo **per bottiglia**;
  le proposte portano una `quantita` e un prezzo per bottiglia.
- **Allocazioni**: `private.listing_allocazioni (listing, unità, acquirente,
  proposta | ordine, scadenza, rilasciata_at, ceduta_at,
  buyer_bottle_unit_id)`; un'unità ha al più un'allocazione aperta (indice
  unico parziale). Una proposta accettata o un checkout prenotano **unità
  specifiche** sotto il lock dell'annuncio; l'annullamento, la scadenza o il
  pagamento fallito le rilasciano; il pagamento le cede una per una, ognuna
  con la sua unità dell'acquirente.
- **Quantità derivate** per annuncio: offerte, disponibili (membro, non
  ritirato, chiusa, non ceduta, nessuna allocazione aperta e non scaduta),
  riservate, vendute, ritirate. Lo stato dell'annuncio fra
  `attivo`/`riservato`/`venduto` si ricalcola da questi conteggi: una vendita
  parziale lascia l'annuncio `attivo`, l'ultima unità lo porta a `venduto`
  senza cancellarne la storia.
- **Ordini**: `orders.quantita` e `orders.prezzo_unitario_cents`;
  `orders.prezzo_cents` resta il **subtotale** del venditore
  (`prezzo_unitario × quantita`) e la commissione si calcola **una volta**
  sull'aggregato, con la formula e i parametri congelati di sempre (un solo
  costo fisso di pagamento). `orders_unico_non_annullato_per_listing` è
  sostituito dall'unicità delle allocazioni aperte per unità.
- **Gate**: ordini e proposte con quantità > 1 rifiutati finché
  `ordini_multi_unita` è spento; prodotti commerciali mai pubblicabili né
  acquistabili finché `vendita_partner` è spento (nessuna tariffa dell'8%
  applicabile a un Partner).

## 7. Stato

| Parte | Contenuto | Stato |
| --- | --- | --- |
| 1 | Formato per unità, lotti idempotenti, aggiunta multipla privata, scorte commerciali del Partner, confini fra le classi, interruttori | Implementata: migrazione `20261012090000`, griglia `12z` e concorrenza `12z_vp_c_concorrenza.sh` |
| 2 | Appartenenza annuncio-unità, allocazioni, annunci multi-unità, proposte e ordini con quantità | Progettata (§6), non implementata |
| 3 | Interfacce: Cantina raggruppata, aggiunta multipla, quantità in vendita, scheda e selettore, catalogo commerciale | Non iniziata |
