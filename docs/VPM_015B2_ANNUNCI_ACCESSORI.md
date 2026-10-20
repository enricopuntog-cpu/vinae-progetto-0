# VPM-015B2 — Annunci Accessori: fondazione tecnica della vendita

Contratto del sotto-blocco 015B2 (21 ottobre 2026), costruito su
[VPM-015A](VPM_015A_ACCESSORI.md) (catalogo) e
[VPM-015B1](VPM_015B1_CANTINA_ACCESSORI.md) (Cantina Accessori personale).
**Nessuna vendita, nessun checkout, nessun ordine, nessun pagamento, nessuna
spedizione.** Questo blocco prepara, in modo verificabile, ciò che un blocco
successivo potrà collegare: la tariffa, la quantità prenotabile e l'annuncio. Un
«annuncio Accessori» qui è una **bozza di preparazione** che nessuno può acquistare.

## 1. Decisioni commerciali del titolare (vincolanti)

| Dominio | Classe del venditore | Margine netto obiettivo | Dove vive |
| --- | --- | --- | --- |
| Vino | privato | 8% (800 bps) | `public.marketplace_config` (invariata) |
| Vino | Partner | 15% (1500 bps) | `public.marketplace_config` (invariata) |
| Accessori | privato | **10% (1000 bps)** | `private.marketplace_margini_dominio` |
| Accessori | Partner | **15% (1500 bps)** | `private.marketplace_margini_dominio` |

- Il prezzo richiesto dal venditore è ciò che riceve. Commissione Vinea e
  copertura dei costi di pagamento si **aggiungono** al prezzo pagato
  dall'acquirente, come per le bottiglie. La base percentuale è il prezzo dei
  prodotti, **spedizione esclusa**.
- Il margine è **netto di riferimento** rispetto ai costi di pagamento, non un
  utile fiscale né un guadagno garantito: la fee reale può essere diversa e si
  riconcilia con il meccanismo esistente (`order_margine_riconciliazione`), senza
  rettifiche retroattive sugli importi accettati.
- Il 10% non si applica al vino dei privati; ai prodotti commerciali Partner non
  si applica mai una tariffa privata.

## 2. Motore economico: riuso, non duplicazione

**Una formula sola**, invariata: `private.marketplace_totale_cents(P, m, p, F)` =
`ceil((P·(10000 + m) + F·10000) / (10000 − p))`. Il costo fisso `F` si applica
**una sola volta per transazione**, sul subtotale dell'ordine (non per pezzo, non
una seconda volta per la spedizione).

**Nessun parametro Stripe duplicato.** La percentuale (`p`, oggi 209 bps), la
quota fissa (`F`, oggi 25 centesimi) e la finestra di verifica si leggono dalla riga
corrente di `marketplace_config` **della classe del venditore**. Solo il margine
`m` è per dominio. Cambiare la fee di riferimento = il solo meccanismo già
presente (chiudere e riaprire le righe correnti di `marketplace_config`); cambiare
un margine accessori = chiudere la riga di `marketplace_margini_dominio` e aprirne
una nuova. Nessuna formula nel frontend.

Componenti:

- **`public.dominio_merceologico`** (`vino`, `accessori_enologici`): *attenzione*,
  gli «accessori» di `private.pagamento_fee_accessori_cents` sono gli importi
  accessori dell'**ordine** (imballaggio 7c, trasporto), un concetto diverso dai
  gadget enologici; per questo l'etichetta del dominio è `accessori_enologici`.
- **`private.marketplace_margini_dominio`**: versionata (una riga corrente per
  dominio e classe), `check (dominio <> 'vino')` (il vino resta in
  `marketplace_config`: una seconda sede sarebbe una seconda fonte di verità),
  immutabile anche per i privilegiati (si chiude, non si riscrive né si cancella).
  Una coppia senza riga → nessun preventivo (mai un ripiego su un'altra classe).
- **`private.preventivo_dominio(dominio, classe, prezzo, quantità, spedizione?)`**:
  nucleo unico. Per il `vino` usa la stessa riga e la stessa formula del checkout
  (il suo risultato coincide con `private.preventivo_classe`: provato). Restituisce
  subtotale, commissione, totale, parametri e la scomposizione
  *quota Vinea* + *costo del pagamento di riferimento* (= `round(totale·p) + F`).
- **Spedizione** (`p_spedizione_cents`, usata dalle prove): la commissione **non**
  cambia; l'acquirente sostiene la fee percentuale generata dalla spedizione, da
  `private.pagamento_fee_accessori_cents` (un solo `ceil`, nessuna seconda quota
  fissa). Esempio (privato, 45 €, spedizione 9 €): +19 centesimi; Partner: +20.
  Con spedizione ignota i campi sono **nulli**, mai 0.

| Prezzo venditore | Accessori privato (10%) | Accessori Partner (15%) | Vino privato (8%) |
| --- | --- | --- | --- |
| 5,00 € | 5,88 € | 6,13 € | 5,78 € |
| 10,00 € | 11,50 € | 12,01 € | 11,29 € |
| 20,00 € | 22,73 € | 23,75 € | 22,32 € |
| 50,00 € | 56,43 € | 58,99 € | 55,41 € |
| 100,00 € | 112,61 € | 117,72 € | 110,57 € |
| 10.000,00 € | 11.235,07 € | 11.745,74 € | 11.030,80 € |
| 6 × 10,00 € | 67,67 € (non 6 × 11,50 €) | 70,73 € | — |

L'arrotondamento è sempre per eccesso: provato su 6000 prezzi (da 0,01 € a
30.000 €, due classi) che il margine obiettivo è raggiunto al netto della fee di
riferimento e che **un centesimo in meno non basterebbe**.

## 3. Modello dati

Tutto in `private`, RLS attiva, **nessun grant** ai ruoli client; le sole porte sono
funzioni `public.annunci_accessori_*` per `authenticated`.

| Oggetto | Ruolo |
| --- | --- |
| `private.annunci_accessori` | annuncio di un accessorio posseduto; stati `bozza`, `in_revisione`, `ritirato` (**lo stato «attivo» non esiste**) |
| `private.annunci_accessori_impostazioni` | singleton: `preparazione_attiva` (spenta di default) e `pubblicazione_attiva` (vincolata a falso da un CHECK) |
| `private.annunci_accessori_categorie` | categorie vendibili, **fail-closed** |
| `private.marketplace_margini_dominio` | margini versionati per dominio e classe |

Colonne dell'annuncio: venditore (`seller_id`, = proprietario dell'accessorio,
verificato dal trigger), accessorio (`cantina_accessorio_id`, immutabile), `quantita`
(1–120), `prezzo_unitario_cents` (1,00 €–10.000,00 €), `condizione`,
`descrizione`, `dichiarazione_conforme`, dati facoltativi del pacco (peso, tre
misure, fragile), date. **Nome, categoria, foto e quantità posseduta restano
solo nell'accessorio della Cantina**: l'annuncio non li copia (nessuna doppia
fonte di verità).

**Separazione.** Nessuna FK da o verso `listings`, `orders`, `payments`, `proposals`,
`bottle_units`, `wines`; nessuna vista; nessuna colonna di ordine o di classe. Un
annuncio Accessori non può comparire fra le bottiglie né essere raggiunto da un
checkout, per costruzione.

## 4. Quantità e anti doppia vendita

- **Posseduto** = `cantina_accessori.quantita` (unica fonte). **Impegnato** = somma
  delle quantità degli annunci aperti (`bozza`, `in_revisione`) dello stesso
  accessorio, **sempre derivata** (`private.annuncio_accessorio_impegnati`): non è una
  colonna. **Disponibile** = posseduto − impegnato.
- Si può mettere in vendita da **1 a N** pezzi senza vendere tutto (es.: 6 calici,
  2 proposti, 4 non impegnati).
- Un solo annuncio aperto per accessorio (indice unico parziale): il primo blocco
  limita un annuncio a un solo accessorio; carrelli e ordini misti sono esclusi.
- **Vincolo per ogni writer, anche privilegiato**: il trigger prende `FOR UPDATE`
  sull'accessorio e rifiuta `quantità + altri impegni > posseduto`. L'ordine dei lock
  è sempre *accessorio, poi annuncio*.
- La Cantina (B1) non può togliere la merce sotto un annuncio aperto: la quantità
  non scende sotto l'impegnato, non si archivia né si rimuove un accessorio con un
  annuncio aperto, non si cambia categoria con l'annuncio in revisione. La
  cancellazione dell'account passa libera.
- Un ritentativo con lo stesso id è idempotente (anche in concorrenza: la bozza è
  riletta dopo il lock).
- **Per il blocco successivo.** Quando esisterà un acquisto, una vendita parziale
  dovrà ridurre `cantina_accessori.quantita` e la quantità dell'annuncio nella
  **stessa transazione e sotto lo stesso lock dell'accessorio**, e le prenotazioni
  dovranno seguire il modello di `listing_allocazioni` (VP-C). La FK annuncio →
  accessorio oggi è `on delete cascade` (serve alla cancellazione dell'account):
  con gli ordini dovrà diventare `restrict`.

## 5. Chi può vendere e che cosa

Il percorso è quello degli accessori **personali dei privati**. La classe e
l'ammissione le decide il database (`private.annuncio_accessorio_venditore`), mai il
client:

| Venditore | Classe | Ammesso | Motivo |
| --- | --- | --- | --- |
| Privato | privato | sì | — |
| Partner invitato o in verifica | privato | sì | come per le bottiglie |
| Partner **attivo o sospeso** | partner | **no** | `partner_percorso_non_consentito` |
| Partner **revocato** non riabilitato | privato | **no** | `partner_revocato` |
| Account non attivo | privato | no | `account_non_attivo` |

Un Partner non ottiene mai la tariffa dei privati né può usare il percorso
personale per aggirare catalogo commerciale, stato Partner e condizioni di vendita
professionale. La riga 1500 bps esiste e la distinzione economica è provata, ma
nessuna porta la espone a un Partner: l'editor dei prodotti Partner Accessori è
**rinviato** (sviluppo indipendente). `vendita_partner` e `ordini_multi_unita`
restano `false`.

**Alcolici e regolamentati.** Una categoria si vende solo se ha una regola
`vendibile` (nessuna riga = no): oggi sono ammesse 7 categorie e le loro 10
sottocategorie (Apertura, Calici, Degustazione, Decanter, Raffreddamento,
Conservazione, Espositori); restano **chiuse** Set regalo (può contenere bevande),
Pulizia (prodotti chimici) e Altri accessori (contenitore generico), e ogni
categoria futura nasce chiusa. In più il venditore dichiara, per l'invio in
revisione, che l'articolo non è alcolico né regolamentato (armi, sciabole).
Alcolici, sciabole e articoli regolamentati non sono vendibili in nessun caso.

## 6. Interruttore e percorso di pubblicazione

- `preparazione_attiva` (database, **spenta di default**): bozze e revisione.
  Richiede anche la funzione Cantina Accessori (B1). Accensione solo col ruolo
  `accessori_release` (stesso marcatore transazionale di 015A/B1, vincola anche i
  privilegiati), spegnimento a ogni admin, registro append-only con motivo.
  Un admin reale può collaudare anche da spenta. Nessuna variabile d'ambiente.
- **Pubblicazione chiusa, anche via RPC diretta.** `annunci_accessori_pubblica` risponde
  sempre `pubblicazione_chiusa` (provato per proprietario, admin e titolare);
  `pubblicazione_attiva` è vincolata a falso; non esiste uno stato acquistabile. Il
  blocco che aprirà la vendita sostituirà quella funzione e il vincolo, non un
  semplice interruttore.
- «In revisione» è uno stato di attesa **senza destinatario operativo**: moderazione
  e approvazione degli annunci Accessori (stati `modifiche_richieste`, `rifiutato`,
  coda admin) sono il blocco successivo. Fino ad allora un annuncio in revisione si
  può solo riportare in bozza o ritirare.
- Le fotografie dell'annuncio sono quelle dell'accessorio (bucket privato B1): per
  una pubblicazione futura servirà una copia congelata all'approvazione.

## 7. Logistica (predisposta, indisponibile)

- La spedizione ordinaria è **a carico dell'acquirente**; il venditore prepara il
  pacco con un imballaggio idoneo; **nessun costo di scatola** è addebitato o
  rimborsato; nessun Vinea Pack; la commissione non si applica alla spedizione.
- L'annuncio può portare **peso, tre misure e fragilità** del pacco (dichiarazioni
  facoltative, validate): serviranno a preventivare quando esisterà una tariffa.
- **Nessuna tariffa inventata.** Le tariffe commerciali esistenti sono per formato
  di bottiglia (il formato d'imballaggio ha un CHECK sui soli formati vino) e non
  descrivono un collo di accessori. Il preventivo di spedizione risponde quindi
  `disponibile: false`, motivo `tariffa_accessori_non_configurata`, e l'interfaccia
  scrive «Preventivo non disponibile», **mai 0 €**. Nessuna spedizione reale,
  imballaggio acquistato o ritiro prenotato. Sede unica del fatto:
  `private.annuncio_accessorio_spedizione()`.
- Le capability PUDO/domicilio non vengono promesse: nessuna modalità è offerta.

## 8. Interfaccia

Nessun redesign; nessun pulsante d'acquisto; navigazione mobile intatta.

- **Cantina → Accessori**: ogni scheda mostra «Prepara vendita» (o «Gestisci
  annuncio» con lo stato e «Non in vendita») solo se la preparazione è abilitata e
  l'accessorio non è archiviato; a funzione spenta, nulla. Un Partner vede perché non
  può usare questo percorso.
- **Finestra di preparazione**: avviso permanente «Le vendite non sono ancora
  attive»; pezzi (con quanti ne possiedi), prezzo per pezzo in euro, condizione,
  descrizione, dati del pacco (facoltativi), dichiarazione di conformità, **riepilogo
  economico del database** (Tu ricevi · Commissione Vinea · Copertura costi di
  pagamento · Prezzo per l'acquirente, spedizione esclusa · Spedizione: non
  disponibile), «Salva bozza», «Invia in revisione» (richiede almeno una foto e le
  modifiche salvate), «Riporta in bozza», «Ritira annuncio». Il riepilogo è un
  preventivo letto dal server e coerente (subtotale = prezzo × quantità, totale =
  subtotale + commissione, commissione = quota Vinea + costo di pagamento); una
  risposta incoerente diventa «non disponibile».
- **Admin → `/admin/accessori`**: pannello dell'unico interruttore (conferma
  scritta `ATTIVA` e motivo per accendere).

## 9. Prove

- Griglia `supabase/tests/12zj_vpm_015b2_annunci_accessori.sql` (39 casi, nel gate
  `Supabase DB regression`): economia (margini, formula, 5/10/20/50/100 €,
  importo elevato, quantità 1/2/6/120, una sola quota fissa, spedizione, margine su
  6000 casi, configurazione modificabile e mancante, vino 8%/15% invariato),
  immutabilità delle tariffe, interruttore e rilascio, isolamento, campi economici
  rifiutati, validazione, sovra-allocazione per ogni writer, guardia della
  Cantina, revisione, pubblicazione chiusa, categorie, Partner attivo/sospeso/
  revocato/in verifica, cancellazione account, separazione dal mercato, inventario
  e volatilità delle funzioni, privacy delle note.
- `supabase/tests/12zj_vpm_015b2_concorrenza.sh` (7 prove su sessioni PostgreSQL
  separate): annuncio vs riduzione della quantità e viceversa (attesa misurata),
  due annunci sullo stesso accessorio, ritentativo concorrente con lo stesso id,
  archiviazione vs annuncio e viceversa, invariante finale. Fixture
  `@conc-12zj.test`, residui 0, interruttori ripristinati e verificati.
- Mutazioni di controllo (stack locale): margine privato a 800, quantità impegnata
  azzerata, guardia della Cantina rimossa, Partner ammesso, pubblicazione aperta,
  `anon` con `execute`, tutte le categorie vendibili → i casi 1, 3, 5, 6, 8, 9, 10,
  15, 16, 18, 22–31, 34 diventano rossi.
- `frontend-next`: parser e validazione (`annunci-accessori.test.ts`), servizio con
  client finto, contratto (`annunci-accessori-contratto.test.ts`: nessun percorso di
  transazione, nessun comando d'acquisto, solo RPC `annunci_accessori_*`, mai la
  pubblicazione, forma della migrazione) e render dei componenti. Soglia CI: 3040.

## 10. Escluso e da decidere

Escluso: `PAYMENTS_ENABLED`, vendita reale, checkout, ordini, trasferimenti Stripe,
payout, spedizioni reali, acquisto di imballaggi, vendita Partner Accessori
operativa e suo editor, configuratori, sciabole e articoli regolamentati, alcolici,
carrelli misti vino/accessori, moderazione e pubblicazione degli annunci (B3).

Decisioni per il titolare:

1. **Tariffa di spedizione degli accessori**: un modello a fasce di peso o per
   formato di collo, con servizi e capability reali, prima di qualunque preventivo.
2. **Categorie ancora chiuse** (Set regalo, Pulizia, Altri accessori): se e a quali
   condizioni aprirle; criterio per le categorie nuove.
3. **Moderazione** di titoli, descrizioni e foto degli annunci prima della
   pubblicazione, e chi la esegue.
4. **IVA e condizioni di vendita** per beni non-vino (garanzia legale, recesso):
   LEG/FIN, non decise.
5. **Prezzo minimo/massimo** (oggi 1 €–10.000 € per pezzo) e quantità massima per
   annuncio (120).
