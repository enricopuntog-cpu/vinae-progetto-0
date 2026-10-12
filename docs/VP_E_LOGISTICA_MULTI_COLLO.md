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
  quota fissa di pagamento resta **una per ordine** sul subtotale (VP-C/VP-D).
- **Una bottiglia non cambia.** Gli ordini da una bottiglia, la consegna a
  mano e tutti gli ordini storici hanno `logistica_cents = 0`, nessun collo
  congelato e il piano di sempre.
- **PUDO-first.** Il checkout addebita la destinazione «punto di ritiro». La
  consegna a domicilio si preventiva se un servizio la dichiara, ma **non si
  ordina**: l'ordine non conserva un indirizzo di consegna e il piano WP6B
  porta solo a un punto di ritiro (decisione WP6B n. 4).
- **L'obiettivo commerciale è riferito, non imposto.** Il costo reale per
  bottiglia è confrontato con l'obiettivo configurato
  (`logistics_unit_economics_config`, oggi 15 € IVA inclusa per transazione);
  l'obiettivo di 10 € per bottiglie sotto 50 € non è stato trasformato in una
  tariffa né in un blocco.
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
- **Consegna a domicilio**: richiede un indirizzo di consegna sull'ordine
  (dato personale, nuovo dominio) e un piano WP6B che non porti solo a un
  punto; oggi nessun servizio dichiara `PUDO_TO_HOME`/`HOME_TO_HOME`.
- Divisore volumetrico e peso reale per formato di bottiglia: non configurati;
  servono solo se un listino sarà a fasce di peso.
- Cartone da 12 bottiglie: compatibile ma senza contributo né tariffa.
- Prove fotografiche e tracking restano per ordine (non per collo); la
  deduzione per il ritiro a domicilio è riferita e congelata, non ancora
  trattenuta sul pagamento al venditore (WP7).
- Fee di pagamento sulla parte logistica: la commissione copre la quota del
  fornitore di pagamento calcolata sul subtotale (formula VP-C/VP-D
  invariata); sull'importo logistico non c'è copertura dedicata.
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
