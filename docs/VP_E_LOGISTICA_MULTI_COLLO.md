# VP-E — Logistica multi-bottiglia e multi-collo

Blocco E del filone «Vinea Partner + Quantità multiple» (vedi
[`ROADMAP_V1.md`](ROADMAP_V1.md#filone-vp--vinea-partner--quantità-multiple)).
Avviato dal titolare il 12 ottobre 2026: **logistica per ordini da 1 a 24
bottiglie divisi in uno o più colli, con un preventivo unico per ordine**,
riusando inventario (VP-C), classi economiche (VP-D), configurazione
logistica (WP6A/WP6B/WP6C) e piano di spedizione esistenti.

Questo documento è il contratto tecnico del blocco. Lo stato è in fondo; ciò
che è solo predisposto è scritto come tale.

## 1. Decisioni vincolanti

- **Nessun dato inventato.** Tariffe, misure, pesi, disponibilità dei
  servizi e costi vengono solo dalla configurazione esistente. Se manca un
  dato indispensabile il percorso è **fail-closed** e dice quale
  configurazione manca, per formato d'imballaggio.
- **Colli pieni.** Un collo contiene esattamente la capacità del suo
  imballaggio: nessuna regola di riempimento parziale è stata decisa, quindi
  nessuna è applicata.
- **Un servizio per ordine.** Tutti i colli viaggiano con lo stesso servizio,
  perché il piano WP6B assegna un servizio per ordine.
- **Logistica separata dalla commissione.** Imballaggio dei colli, trasporto,
  altri costi transazionali e buffer sono `orders.logistica_cents`, fuori da
  `totale_cents` e dalla commissione (privati 800 bps, Partner 1500 bps). La
  quota fissa di pagamento resta **una per ordine**. Dal 13 ottobre 2026
  (§10) l'acquirente sostiene anche la fee di pagamento incrementale che
  logistica e imballaggio 7c generano: riga separata
  `orders.fee_pagamento_accessori_cents`, mai una seconda quota fissa.
- **Una bottiglia non cambia.** Gli ordini da una bottiglia, la consegna a
  mano e tutti gli ordini storici hanno `logistica_cents = 0`, nessun collo
  congelato e il piano di sempre.
- **PUDO-first.** Il checkout addebita la destinazione «punto di ritiro». La
  consegna a domicilio si preventiva se un servizio la dichiara, ma **non si
  ordina**: l'ordine non conserva un indirizzo di consegna e il piano WP6B
  porta solo a un punto di ritiro (decisione WP6B n. 4).
- **L'obiettivo commerciale è riferito, non imposto.** Dal 13 ottobre 2026
  (§10) il costo reale logistico è confrontato **per transazione** con
  l'obiettivo di 10 € IVA inclusa, solo quando le bottiglie costano meno di
  50 € (`logistics_obiettivo_transazione_config`); la soglia storica
  (`logistics_unit_economics_config`, 15 €) è una metrica separata, anch'essa
  per transazione, e non dichiara mai raggiunto l'obiettivo nuovo. Nessuno
  dei due è una tariffa o un blocco.
- Interruttori invariati in produzione: `ordini_multi_unita = false`,
  `vendita_partner = false`, `PAYMENTS_ENABLED=false`.

## 2. Compatibilità formato di bottiglia → imballaggio

`private.logistics_formato_imballaggio` (versionata, RLS, nessun grant) rende
esplicito ciò che i nomi dei formati WP6A/WP6B già dichiarano:

| Formato bottiglia | Imballaggio | Bottiglie per collo |
| --- | --- | --- |
| 0,75 L | `bottiglia_1`, `bottiglia_2`, `bottiglia_3`, `bottiglia_6`, `bottiglia_12` | 1, 2, 3, 6, 12 |
| 1,5 L (Magnum) | `magnum_1_5l` | 1 |

Ogni altro formato (0,1875, 0,375, 0,5, 1, 3 L e oltre) non ha imballaggio:
`formato_non_supportato`. Una compatibilità non è una disponibilità:
`bottiglia_12` non ha contributo né tariffa e il pianificatore la ignora.

## 3. Pianificatore dei colli

`private.logistica_piano(formato, quantità, capability)`:

1. servizi candidati: correnti, attivi, idonei, con la capability **esatta**
   della rotta, tutti i limiti noti e le reti PUDO richieste dagli estremi;
2. per ogni servizio, i formati d'imballaggio utilizzabili: contributo
   corrente (`logistics_packaging_contributions`), SKU operativo attivo
   (`logistics_packaging_skus`: misure, peso prudenziale) accettato dal motore
   WP6B `logistics_service_compatibili` su quel servizio, tariffa commerciale
   attiva (`logistics_commercial_rate_sources`, prezzo finale IVA inclusa);
3. composizione di colli pieni di **costo minimo** (contributo + trasporto),
   a parità meno colli, poi i formati più capienti; fra i servizi vince il
   costo, poi meno colli, poi provider, servizio, id.

Peso del collo = peso prudenziale dello SKU (come il piano WP6B); volume =
`ceil(l × w × h / 1000)` cm³. **Nessun peso volumetrico**: nessun divisore è
configurato e le tariffe commerciali sono per formato, non per peso.

Senza composizione possibile risponde `ok=false` con, per ogni formato, le
configurazioni mancanti (`private.logistica_formato_mancanti`):
`contributo_imballaggio`, `imballaggio_operativo`, `tariffa_trasporto`,
`tariffa_trasporto_non_attiva`, `servizio_per_rotta`, `servizio_non_attivo`,
`idoneita_operativa`, `limiti_operativi`, `formato_non_ammesso_dal_servizio`,
`rete_pudo_origine`, `rete_pudo_destinazione`, `collo_oltre_limiti`; e
`combinazione_colli` quando ogni formato è configurato ma le bottiglie non
riempiono colli pieni.

## 4. Preventivo unico e quattro modalità

`private.logistica_preventivo_ordine(annuncio, quantità, destinazione,
prezzo)`: origine dalla dichiarazione dell'annuncio (`dropoff_pudo` → punto,
`ritiro_domicilio` → domicilio), destinazione chiesta; capability
`PUDO_TO_PUDO`, `PUDO_TO_HOME`, `HOME_TO_PUDO`, `HOME_TO_HOME` come dati.
Regole riprese da WP6A/WP6B:

- l'acquirente paga il trasporto con partenza da punto se più basso
  dell'effettivo; la differenza è la **deduzione del venditore** per il ritiro
  a domicilio, componente separata e mai nel totale dell'acquirente;
- altri costi solo se dichiarati componenti di preventivo
  (`logistics_fulfillment_costs`): `per_order` una volta, `per_unit` per
  bottiglia; canoni, setup e stoccaggio mai;
- buffer logistico (`logistics_quote_config`, oggi zero) sul subtotale,
  fuori dal costo reale;
- totale = imballaggio + trasporto + altri costi + buffer.

Porta `public.listing_logistica_preventivo(annuncio, quantità, prezzo?)`
(anon e authenticated, stessa visibilità di `listing_preventivo`): opzione
«punto di ritiro» (consigliata, ordinabile), opzione «domicilio»
(preventivata se configurata, `ordinabile=false`,
`indirizzo_consegna_non_gestito`), le quattro modalità con la sola
disponibilità, la parte di mercato della classe e `totaleOrdineCents`
(mercato + logistica) quando la logistica è addebitata. Il fornitore non
esce mai; trasporto per collo, deduzione, costo reale e obiettivo solo al
venditore.

## 5. Checkout, ordine, piano

- `order_checkout_reserve` (firma invariata): con più di una bottiglia e
  `delivery_mode = 'spedizione'` esige il preventivo verso il punto di
  ritiro, dentro la stessa transazione e sotto il lock dell'annuncio; se non
  è disponibile rifiuta con `logistica_non_configurata` e l'elenco dei motivi
  nel `detail`, senza ordine né prenotazioni.
- L'ordine congela `logistica_cents` e `logistica_destinazione`;
  `addebito_totale_cents` (generata) = prezzo + commissione + imballaggio 7c
  + logistica, quindi il pagamento e la Edge Function (`amount_cents`) la
  comprendono senza modifiche. Il trasferimento al venditore resta il solo
  prezzo del venditore.
- `private.ordine_logistica` (testata) e `private.ordine_colli` (colli con
  SKU, misure, peso, contributo, tariffa) sono immutabili anche per uno
  scrittore privilegiato; si cancellano solo con l'ordine.
- Vincolo differito `orders_logistica_coerente`: un ordine di più bottiglie
  spedite ha la sua logistica coerente con importo, destinazione e bottiglie;
  ogni altro ordine non ne ha.
- `orders_economia_immutabile` comprende la logistica.
- Piano WP6B: un ordine multi-collo nasce con le misure del collo 1; un
  servizio si assegna, un punto di destinazione si propone e una rotta resta
  pronta solo se il servizio regge **tutti** i colli
  (`private.logistica_servizio_regge_ordine`); la deduzione per il ritiro a
  domicilio somma i colli. `logistics_plan_leggi` espone i colli;
  `public.ordine_logistica_leggi` (authenticated, parti dell'ordine) espone la
  logistica congelata.

## 6. Interfacce

- Scheda annuncio: con più bottiglie scelte (selettore attivo solo con
  `ordini_multi_unita`), il preventivo del database: colli con imballaggio,
  misure e peso, imballaggio, trasporto, totale con spedizione; domicilio
  come alternativa non ordinabile; le configurazioni mancanti in italiano.
- Checkout: righe «Imballaggio spedizione (N colli)» e «Trasporto al punto di
  ritiro» nel riepilogo; con la spedizione non configurata nessun totale
  stimato, avviso con i motivi e «Conferma pagamento» disabilitata (il
  database rifiuterebbe comunque).
- Storico ordini: «Spedizione e imballaggio» = addebito − totale di mercato −
  imballaggio 7c (numeri congelati, nessuna colonna nuova letta) e i colli
  dalla porta dedicata.

## 7. Prove

- Griglia `supabase/tests/12zc_vp_e_logistica_multi_collo.sql` (33 casi) nel
  gate `Supabase DB regression`; fixture di prova
  `12zc_vp_e_fixture_logistica.sql` (provider fittizi `vpe_prova`/`vpe_casa`,
  solo nella transazione), inclusa anche da 12za e 12zb, i cui ordini di più
  bottiglie spedite ora esigono la logistica.
- Concorrenza su sessioni reali `12zc_vp_e_concorrenza.sh` (4 prove):
  ultime bottiglie contese con più colli, stessa chiave da due sessioni, due
  acquisti che esauriscono l'annuncio, tariffa ritirata durante un acquisto.
- Mutazioni di controllo: servizio che «regge sempre» e vincolo differito
  svuotato → casi 28, 32 e 33 rossi.
- Frontend: `src/services/vp-e-logistica.test.ts` (parser con identità,
  servizio, etichette, checkout, storico, guardrail senza vettori né tariffe
  nel codice).

## 8. Requisiti differiti e prerequisiti dell'accensione

- **Configurazione operativa della produzione** (oggi tutto fail-closed):
  SKU operativi WP6A per i formati da usare (misure e peso prudenziale del
  collo pieno), servizi attivi e idonei con i cinque limiti operativi, tariffe
  commerciali `active`, reti PUDO e rubrica dei punti. Sono i cinque
  lucchetti WP6C, da aprire con le porte admin.
- **Consegna a domicilio**: **chiuso** dalla migrazione `20261013160000`
  (§11: indirizzo congelato sull'ordine, piano WP6B verso il domicilio). In
  produzione nessun servizio dichiara ancora `PUDO_TO_HOME`/`HOME_TO_HOME`,
  quindi resta fail-closed.
- Divisore volumetrico e peso reale per formato di bottiglia: non configurati;
  servono solo se un listino sarà a fasce di peso.
- Cartone da 12 bottiglie: compatibile ma senza contributo né tariffa.
- Prove fotografiche e tracking restano per ordine (non per collo); la
  deduzione per il ritiro a domicilio è riferita e congelata, non ancora
  trattenuta sul pagamento al venditore (WP7).
- Fee di pagamento sulla parte logistica: **chiuso** dalla migrazione
  `20261012234500` (§10).
- Proposte: la logistica si verifica al checkout, non all'invio o
  all'accettazione della proposta.
- Ordine da una Magnum singola: il piano WP6B di un ordine da una bottiglia
  usa ancora lo SKU `bottiglia_1` (comportamento precedente, non toccato).

## 9. Stato

| Parte | Contenuto | Stato |
| --- | --- | --- |
| Database | Compatibilità, pianificatore, diagnosi, preventivo, porte, checkout, congelamento, vincolo, piano | Migrazione `20261012230000`, griglia `12zc`, concorrenza `12zc_vp_e_concorrenza.sh` |
| Interfacce | Scheda, checkout, storico ordini | `frontend-next`, provate in locale nel browser |
| Accensione | `ordini_multi_unita` | **Spento**: richiede la configurazione operativa (§8) e l'autorizzazione del titolare |
| Fee sulla logistica | Copertura della fee di pagamento su logistica e imballaggio 7c, metrica per transazione | Migrazione `20261012234500`, griglia `12ze` (§10) |
| Indirizzi e API | Rubrica, origine domicilio/sede, destinazione domicilio, congelamento, coda per gli adattatori | Migrazione `20261013160000`, griglia `12zg` (§11) |

## 10. Fee di pagamento sulla logistica (13 ottobre 2026)

Decisione del titolare: margine netto obiettivo **8%** (privati) e **15%**
(Partner) al netto della fee di pagamento di riferimento sull'**intero**
addebito; il venditore riceve il prezzo richiesto; l'acquirente sostiene la
fee incrementale generata dai costi accessori, evidenziata nel preventivo e
nel riepilogo; nessuna seconda quota fissa.

Formula (`private.pagamento_fee_accessori_cents`, unica fonte, parametri
versionati e congelati sull'ordine: oggi `p` = 209 bps, `F` = 25 c), con `P`
prezzo, `m` margine, `A` = imballaggio 7c + logistica:

```text
addebito = ceil( (P·(10000 + m) + (F + A)·10000) / (10000 − p) )
totale   = marketplace_totale_cents(P, m, p, F)      (invariato)
copertura = addebito − totale − A                    (0 se A = 0)
```

Un solo `ceil` sull'insieme: al netto di `p·addebito + F` restano `P`, `A` e
`m·P`, e un centesimo in meno non basterebbe. La commissione non cambia.

| Caso (privati) | Mercato | Accessori | Copertura | Addebito |
| --- | --- | --- | --- | --- |
| 1 × 45 € spedita | 4990 | 0 | 0 | 4990 |
| 3 × 10 € | 3335 | 801 | 17 | 4153 |
| 2 × 45 € + imballaggio 7c 4,50 € | 9954 | 450 + 791 | 26 | 11221 |
| 1 × 100 € + imballaggio 7c 4,50 € | 11057 | 450 | 9 | 11516 |
| 8 × 40 € | 35324 | 1822 | 39 | 37185 |
| Partner 8 × 40 € | 37612 | 1822 | 38 | 39472 |

(Accessori e logistica: configurazione **di prova** delle griglie, non tariffe
reali.)

- `orders.fee_pagamento_accessori_cents` nasce a 0 (ordini storici invariati),
  entra in `addebito_totale_cents` e nel pagamento, è immutabile insieme a
  `imballaggio_cents` e verificata dal vincolo differito
  `orders_logistica_coerente` per ogni writer (`fee_accessori_incoerente`).
- `listing_logistica_preventivo`: `feePagamentoCents` per opzione e in testa,
  `imballaggioAnnuncioCents`, `totaleOrdineCents` = mercato + imballaggio 7c +
  logistica + copertura, uguale all'addebito del checkout.
- `order_margine_riconciliazione`: fee di riferimento, margine proiettato e
  reale calcolati sull'intero addebito (accessori sottratti come costi
  passanti), più `margine_obiettivo_cents`; lo scarto misura la fee reale
  contro il riferimento congelato, senza presumere la tariffa contrattuale
  futura.
- Metrica logistica: `obiettivoTransazioneCents`, `obiettivoApplicabile`,
  `entroObiettivoTransazione`, `sogliaStoricaCents`, `entroSogliaStorica`
  (solo al venditore); `costoRealePerBottigliaCents` resta informativo.
- Senza logistica addebitata (una bottiglia, consegna a mano) la migrazione
  `20261013090000` aggiunge al preventivo `feePagamentoSenzaLogisticaCents`:
  la copertura sul solo imballaggio 7c dell'annuncio, la stessa che il
  checkout congela (1×45 € + 7c 4,50 € → 9, addebito 5449; consegna a mano
  2×45 € + 7c → 9, 10413; griglia `12ze` casi 17-18). Il riepilogo del
  checkout legge imballaggio, logistica e copertura solo da questo preventivo
  (`accessoriCheckout`), non dal listino beta locale; se un importo non è
  determinabile non mostra un totale.

## 11. Indirizzi e logistica pronta per API (pre-lancio, 13 ottobre 2026)

Migrazione `20261013160000_logistica_indirizzi_api.sql`, griglia `12zg`. Un
solo motore per privati e Partner: estende questo blocco e il piano WP6B,
nessun sistema parallelo. Nessun dato operativo è seminato; senza
configurazione il percorso resta fail-closed.

- **Rubrica** `private.indirizzi` (destinatario, via, CAP, città, provincia,
  Paese, telefono, note; solo Paesi abilitati dai registri VP-F, oggi `IT`),
  nessun grant client, porte `indirizzo_salva`, `indirizzi_miei`,
  `indirizzo_archivia`; un domicilio di ritiro e un indirizzo di consegna
  predefiniti; massimo 20 attivi.
- **Origine**: punto di ritiro (drop-off, consigliato), domicilio del privato
  (`ritiro_domicilio` + domicilio di ritiro predefinito) o **sede del
  Partner** (prodotto commerciale con ritiro: origine `sede`, indirizzo dai
  dati del Partner). La sede ha capability proprie `SEDE_TO_PUDO` e
  `SEDE_TO_HOME` (servizi, tariffe, porta admin `admin_logistics_service_versiona`,
  motore `logistics_service_compatibili`, piano `sede_pickup`): BRT o un altro
  corriere si abilitano al ritiro in sede **come dati**, quando contratto e
  capability lo permettono. Il ritiro a domicilio dei privati non vale per
  una sede. Senza indirizzo d'origine: `indirizzo_ritiro_mancante`.
- **Destinazione**: punto di ritiro (default, PUDO-first) o domicilio
  dell'acquirente, scelta prima del checkout con `checkout_consegna_imposta`
  (firma del checkout invariata). Il domicilio è ordinabile solo se un
  servizio della rotta è configurato, ed è **sempre addebitato**, anche per
  una bottiglia; il servizio lo sceglie il routing VP-E, mai il venditore.
- **Congelamento**: il checkout scrive `private.ordine_indirizzi` (modalità e
  istantanea di entrambi gli estremi, immutabile, si cancella solo con
  l'ordine); il vincolo differito `orders_logistica_coerente` esige la
  logistica per il domicilio e gli indirizzi coerenti con origine e
  destinazione, per ogni writer; il piano WP6B legge la modalità congelata,
  per il domicilio non chiede un punto e usa il servizio congelato, e il
  trigger `logistics_shipment_plans_modalita_congelata` impedisce di cambiarla.
  Modificare o archiviare un indirizzo non tocca gli ordini.
- **Riservatezza**: `ordine_indirizzi_leggi` (solo le parti): ognuno vede per
  intero solo il proprio indirizzo, della controparte tipo, città e
  provincia. Il venditore non riceve il domicilio dell'acquirente.
- **Pronta per API, nessuna chiamata**: `private.logistics_provider_operazioni`
  (capacità per corriere, operazione `prenotazione_ritiro`/`etichetta`/`tracking`
  e capability, tutte spente, versionate) e la coda idempotente
  `private.spedizione_operazioni` (`in_attesa` → `inviata`/`confermata`/`fallita`/`annullata`,
  chiave `vinea:<ordine>:<operazione>`), riempita solo da
  `private.spedizione_operazione_prepara` quando la capacità è accesa. Gli
  adattatori lato server leggeranno gli indirizzi da `ordine_indirizzi` al
  momento dell'invio.
- **Economia invariata**: commissioni 8%/15% netti, copertura della fee
  (§10, formula unica sull'intero addebito) e imballaggio 7c come prima; il
  domicilio entra nella logistica addebitata e nella copertura come ogni
  logistica.

Limiti dichiarati: l'interfaccia per gestire la rubrica e scegliere il
domicilio nel checkout non è ancora nell'app (servizio `indirizzi-service`
pronto, preventivo che espone il domicilio ordinabile); nessun adattatore
reale né Edge Function per prenotazioni, etichette e tracking; nessun
servizio, tariffa, punto o capacità di produzione configurati.
