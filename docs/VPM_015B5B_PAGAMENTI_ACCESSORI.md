# VPM-015B5B — Pagamenti degli ordini Accessori

Contratto del sotto-blocco 015B5B (2 novembre 2026), costruito su
[VPM-015B5A](VPM_015B5A_CHECKOUT_ACCESSORI.md). **Integra, non riscrive**: gli ordini Accessori
prenotati entrano nel sistema pagamenti già esistente (Edge Function `payments-checkout`, adapter
PaymentIntent, webhook firmato, registro eventi). Resta fuori B5C (resi, contestazioni, liquidazione
al venditore). `PAYMENTS_ENABLED` e tutte le flag Accessori restano **spente**: nessun addebito,
rimborso o trasferimento reale.

## 1. Che cosa è riusato e che cosa è nuovo

| Riusato (invariato o esteso di poche righe) | Nuovo (adapter di dominio minimo) |
| --- | --- |
| `payments-checkout/index.ts` (auth, gate `PAYMENTS_ENABLED`, CORS/origini di ritorno, `rispostaCheckout`): +1 ramo `accessoriOrdineId` | `private.accessori_pagamenti` (un pagamento per ordine) |
| `providers/stripe.ts` (PaymentIntent, **niente** `transfer_data`/`on_behalf_of`): +1 riga di metadata `vinea_dominio` | `accessori_pagamento_apri` / `_collega` / `_applica_evento` (solo `service_role`) |
| `_shared/payment-provider.ts`, `services/types.ts`: campo opzionale `dominio` | `accessori_pagamenti_rimborso_dovuto()` (elenco admin) |
| Webhook `api/public/webhooks/stripe/route.ts` + `stripe-signature.ts` + `stripe-event.ts`: unico verificatore, +1 instradamento | `private.accessori_ordine_vendita_applica(ordine, modo)` (nucleo di B5A con il modo scritto) |
| `public.payment_provider_events`: stesso registro e stessa deduplica `(provider, event_id)` | `apriPagamentoAccessori` in `services/phase7/payment-service.ts` |
| `public.payment_outcome` e `traduciEventoStripe` (nessun nuovo vocabolario) | |

**Perché non `public.payments`**: `payments.order_id` è una chiave esterna verso `public.orders`, e B5A ha
stabilito che un ordine Accessori non è una riga di `orders` (nessun listing, nessuna bottiglia). Forzarlo
sarebbe stato un refactoring del pagamento del vino. `private.accessori_pagamenti` ne ripete la macchina a stati
(`checkout_pending → processing → paid | failed | expired`, più `refund_due`, `partially_refunded`, `refunded`).

## 2. Flusso

1. Ordine B5A `in_attesa_pagamento` → il browser chiama `payments-checkout` con **solo** `accessoriOrdineId`.
2. `accessori_pagamento_apri(ordine, acquirente)` (sotto lock dell'ordine): verifica proprietà, stato e scadenza,
   checkout aperto; scrive il pagamento con l'importo **dello snapshot dell'ordine** (`totale_acquirente_cents`);
   **rinnova una volta la riserva** (`prenotazione_min`, 15) — la guardia dell'ordine ammette solo questo aumento di
   `scade_at`. Ripetuta, restituisce la stessa riga (e la sessione già collegata → `riprendiCheckout`).
3. L'adapter apre il PaymentIntent con chiave presso il fornitore `accessori-<ordine>` (due richieste parallele →
   uno stesso intento) e metadata `vinea_dominio=accessori`; `accessori_pagamento_collega` lo lega (una sessione
   diversa → `sessione_diversa`).
4. Il webhook firmato legge `metadata.vinea_dominio` (che torna nell'evento firmato): `accessori` →
   `accessori_pagamento_applica_evento`; altrimenti `payment_apply_provider_event` (vino, **invariata**). Ciascuna RPC
   cerca il pagamento per riferimento del fornitore tra i **propri** pagamenti: un evento di un altro dominio non
   trova nulla (`P0001`, nessun effetto, il fornitore ritenta).
5. `settled` valido ⇒ `accessori_ordine_vendita_applica(..., 'provider')`: ordine `pagato` (modo `provider`),
   annuncio −N e Cantina −N **una volta**, pagamento `paid`.

Nessun ordine è `pagato` senza un evento attendibile: `apri`/`collega` non scrivono mai `paid`, e il solo modo
`provider` si raggiunge dal nucleo chiamato dall'evento.

## 3. Pagamento tardivo e incasso non applicabile (decisione)

Scelta: **rinnovo unico della riserva all'apertura + percorso di compensazione durevole**, la soluzione minima
compatibile con CLAUDE.md (*Money*: un pagamento completato non deve restare senza uscita).

- All'apertura la riserva diventa `now() + prenotazione_min` (mai di più, una volta sola).
- Se l'incasso (`settled`) arriva quando l'ordine **non è più applicabile** — prenotazione scaduta (adesso o all'ora
  dell'evento), ordine annullato/scaduto/fallito, annuncio oscurato o ritirato (il rilascio B5A ha già annullato
  l'ordine), ordine già pagato in altro modo, inventario incoerente — il pagamento passa a **`refund_due`** con il
  motivo (`prenotazione_scaduta`, `ordine_chiuso:<motivo>`, `ordine_gia_pagato`, `inventario_incoerente`) e la RPC
  risponde `late_paid_requires_refund` (stesso vocabolario del vino). Nessuna quantità si tocca.
- `refund_due` è idempotente (un secondo incasso resta `refund_due`); il segnale firmato `charge.refunded` lo porta a
  `refunded` (o `partially_refunded`) con l'importo. L'elenco `accessori_pagamenti_rimborso_dovuto()` (admin) rende
  visibili i casi aperti. **Il rimborso reale non è eseguito da questo blocco**: serve l'operazione di rimborso (Stripe)
  o l'automazione, prima del live.
- Un pagamento fallito (`failed`/`expired`) chiude l'ordine (`pagamento_fallito` / `scadenza`) e libera la
  disponibilità (derivata); se Stripe riprova lo stesso intento con successo, l'incasso va a `refund_due`.
- Moderazione: resta il rilascio B5A (l'annuncio non pubblicato annulla le prenotazioni non pagate); l'incasso
  successivo va a `refund_due`, non si congela.
- L'incasso già avvenuto **non si ferma** per interruttori spenti: l'applicazione non controlla `checkout_attivo`
  (solo l'apertura lo richiede).
- Limite noto: metodi asincroni (PayPal/Satispay/addebiti) che si concludono oltre la riserva rinnovata finiscono in
  `refund_due`. La scelta dell'insieme di metodi per gli Accessori è una decisione di go-live (§5).

## 4. Commissioni e fondi (invariati)

Accessori privati 10%, vino privati 8%, Vinea Partner invariato, copertura della fee di pagamento già nello snapshot,
spedizione separata dalla base commissionale: tutto viene dal preventivo B4/ordine B5A, **mai ricalcolato**.
L'incasso non porta `transfer_data`/`on_behalf_of`: i fondi restano sul balance della piattaforma. **Nessun payout**:
gli ordini Accessori non hanno alcuna porta di liquidazione, e `payouts-release` non nomina il dominio (provato da un
test di contratto); il rilascio dopo consegna arriva con B5C.

## 5. Prove

- `supabase/tests/12zo_vpm_015b5b_pagamenti_accessori.sql` — **28 casi** (nel gate `Supabase DB regression`):
  privilegi, gate spento, apertura idempotente con importo dallo snapshot, rinnovo unico, un solo intento, pagamento
  corretto, processing, evento duplicato e fuori ordine, importo/valuta/ordine/dominio divergenti, ordine vino
  scambiato, gate spento dopo l'apertura, fallito, tardivo dopo il fallimento, compensazione e rimborso, scaduta,
  intento annullato, oscuramento, annullo contro incasso (due ordini), ultimo pezzo, immutabilità, proprietà, elenco
  admin, nessun payout, vino invariato, invarianti.
- `supabase/tests/12zo_vpm_015b5b_concorrenza.sh` — **5 prove su sessioni reali** con barriera: stesso evento due
  volte, due eventi diversi, incasso contro annullamento (3 giri), due aperture, invarianti.
- Mutazioni di controllo (importo non confrontato, scadenza ignorata, dominio non verificato) → casi rossi.
- `frontend-next`: test del webhook (8: instradamento, firma falsa, payload alterato, gate spento, ritentativo),
  test di contratto B5B (16), soglia CI 3206.
- Locale: 12zn nello stesso stack dà gli stessi 2 casi rossi di stato locale (1 e 4) con e senza questa migrazione.

## 6. Cosa manca prima del live

1. Montaggio del **Payment Element** nel frontend (oggi nessun dominio lo monta; nessuna dipendenza `stripe-js`) e
   azione «Paga» sulla pagina dell'ordine: `apriPagamentoAccessori` è già il servizio.
2. Esecuzione del **rimborso reale** per i `refund_due` (operazione Stripe o job), e sua riconciliazione.
3. Registrazione in Stripe dell'endpoint webhook con gli eventi già in whitelist e configurazione di
   `PAYMENTS_ENABLED`, `STRIPE_*`, origini di ritorno (nessuna nuova variabile ambiente).
4. Scelta dei metodi di pagamento ammessi per gli Accessori (asincroni ammessi o no).
5. B5C: resi, contestazioni, rilascio dei fondi dopo la consegna, notifiche, IVA/fatturazione dei beni non-vino.
6. Accensione di `checkout_attivo` / `ACCESSORI_ORDINI_ENABLED` (`accessori_release`).
