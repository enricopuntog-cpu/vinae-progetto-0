# Fase 7 — specifica ordini, proposte e pagamenti

Data: 31 luglio 2026. Branch: `migration/phase-7-order-payment-service`.

## Perimetro del checkpoint

Il checkpoint porta nel target Next.js/Supabase i contratti locali di
`ProposalService`, `OrderService` e `PaymentService`, lo schema versionato, la
Edge Function di checkout e il Route Handler del webhook. Tutto resta disattivo
per default. Non applica SQL, non distribuisce funzioni, non usa credenziali
Stripe e non esegue pagamenti.

`frontend/` e `backend/` restano la versione servita e la sorgente di confronto.
Spedizione, protezione acquisti e metodi demo conservano il comportamento del
prototipo; nessun payout, KYC o Stripe Connect entra in questa fase.

## Fonti autoritative

- Identità: JWT Supabase verificato dal server.
- Annuncio, seller, prezzo e valuta: righe bloccate di `listings` e
  `bottle_units`, mai il payload del browser.
- Buyer: utente verificato che invoca il checkout.
- Pagamento: solo evento Stripe firmato con `payment_status=paid` o evento
  asincrono di successo già verificato.
- Stato pubblico dell'annuncio: `listings.stato`; la transizione a `venduto`
  lascia a `listings_marca_bottiglia_ceduta` la prima valorizzazione di
  `ceduta_at`.

## Macchine a stati

### Proposta

```text
inviata -> controproposta -> accettata -> convertita
   |             |              |
   +-----------> rifiutata      +-> scaduta prima del checkout
   +-----------> scaduta
```

Una sola proposta `inviata` o `controproposta` è ammessa per coppia
annuncio/compratore. Solo il buyer invia; solo il seller contropropone, accetta
o rifiuta. L'accettazione blocca l'annuncio come `riservato`; la scadenza viene
ricontrollata nella transazione di checkout.

### Ordine

```text
in_attesa_pagamento -> pagato -> in_preparazione -> spedito -> consegnato
                                                       -> verifica -> completato
                                  |                         |
                                  +-> annullato             +-> contestato
                                                               -> rimborsato
```

Gli stati venditore restano una proiezione compatibile con il prototipo, non
una seconda sorgente di verità. Il primo checkpoint espone solo le transizioni
necessarie a prenotazione e pagamento; spedizione, contestazioni e recensioni
restano tipizzate ma non vengono anticipate con nuove interfacce.

### Pagamento

```text
checkout_pending -> processing -> paid -> partially_refunded -> refunded
         |              |
         +-> failed     +-> failed
         +-> expired
```

`paid`, `partially_refunded` e `refunded` non retrocedono per eventi tardivi.
`checkout.session.completed` senza `payment_status=paid` produce al massimo
`processing`. Ogni `event.id` Stripe è deduplicato prima di applicare effetti.

## Prenotazione, concorrenza e idempotenza

`order_checkout_reserve` è l'unica porta che prepara un checkout:

1. prende il lock della riga `listings`;
2. scade una prenotazione precedente non pagata quando necessario;
3. ricontrolla `stato`, `expires_at`, ownership e integrità della bottiglia;
4. valida e blocca l'eventuale proposta accettata;
5. risolve buyer, seller, prezzo e valuta nel database;
6. crea o recupera l'ordine con chiave idempotente per buyer;
7. porta l'annuncio a `riservato` e assegna una scadenza breve.

Una constraint impedisce due ordini non annullati sullo stesso annuncio. Due
compratori concorrenti serializzano sul lock dell'annuncio: uno prenota, l'altro
riceve un conflitto leggibile. La chiave inviata a Stripe deriva da ordine e
idempotency key e rende sicuri i retry.

## Compensazione degli errori parziali

- Se Stripe fallisce prima di creare una sessione, l'Edge Function invoca
  `order_checkout_release`: annulla l'ordine ancora non pagato e riapre
  l'annuncio.
- Se Stripe crea la sessione ma l'aggancio locale fallisce, la prenotazione non
  viene rilasciata: lo stesso retry usa la medesima chiave Stripe, recupera la
  sessione e ritenta l'aggancio senza duplicare l'addebito.
- Una prenotazione orfana scade; la successiva prenotazione la riconcilia nella
  stessa transazione.
- Il webhook è una transazione database unica: se l'applicazione fallisce,
  anche la registrazione dell'evento torna indietro e Stripe può riprovare.

## Cessione della bottiglia

Il webhook pagato porta l'annuncio a `venduto`. Il trigger esistente valorizza
`ceduta_at` con `coalesce` e libera lo slot; il codice di Fase 7 non scrive mai
quella colonna. Nella stessa transazione viene creata una nuova `bottle_unit`
privata per il buyer, collegata allo stesso vino. L'unità storica del seller non
cambia proprietario e non rientra nella sua Cantina.

## Rate limiting

### Data API

Un hook `pgrst.db_pre_request` limita tutte le richieste mutative autenticate
alla Data API, comprese le RPC già esistenti. Il contatore fixed-window vive in
`private`, usa un UPSERT atomico e una chiave composta da soggetto, ambito e
finestra. GET e HEAD non scrivono contatori.

### Checkout e webhook

La RPC invocata dall'Edge Function consuma un bucket per utente verificato prima
di prenotare.
Il Route Handler consuma il bucket webhook solo dopo la verifica della firma;
traffico non firmato o volumetrico deve essere filtrato al bordo. I limiti sono
sono fissati nel contratto SQL di questo checkpoint; i limiti webhook sono
configurabili per ambiente. In locale i test usano un limiter in memoria con
orologio iniettato; su più istanze l'unica implementazione ammessa è il
contatore Postgres condiviso e atomico.

## Feature flag e segreti

`PAYMENTS_ENABLED=false` è il gate server-side. La UI può usare
`NEXT_PUBLIC_PHASE_7_PAYMENTS_ENABLED=false` solo per nascondere il percorso,
mai per autorizzarlo. `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` e
`SUPABASE_SERVICE_ROLE_KEY` sono esclusivamente server-side.

## RLS e privilegi

- `proposals`, `orders`, `payments` e `order_events` hanno RLS attiva.
- Buyer e seller leggono solo righe in cui partecipano.
- Nessun ruolo client inserisce o aggiorna ordini e pagamenti direttamente.
- Le transizioni sono funzioni dedicate; il browser non sceglie lo stato di
  arrivo.
- `stripe_webhook_events` e i bucket di rate limit non hanno grant client.
- Tutte le foreign key usate da ownership e join hanno un indice dedicato.

## Protezione dagli eventi tardivi

Ogni aggiornamento applica sia una precedenza monotona sia il timestamp Stripe.
Un evento `expired` o `failed` non modifica un pagamento già pagato o rimborsato;
un evento pagato può correggere uno stato non terminale. I rimborsi sono
monotoni per importo e distinguono parziale da totale.
