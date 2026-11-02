# VPM-015QA-FINAL-B2 — collaudo E2E Accessori, Stripe test mode e post-vendita

Data: 3 novembre 2026. Baseline: `main` = `639a420` (PR #262). Nessuna migrazione, nessun codice di
prodotto: una correzione all'harness di prova, un test runtime e questo rapporto.

## Stato

**QA-FINAL-B2: PARZIALE.** Chiusi: browser Accessori privati su tre browser, runtime del Refund provider
con `fetch` finto. **NON VERIFICATI e bloccanti prima del live**: Stripe in test mode (nessuna
credenziale `pk_test_`/`sk_test_`/segreto webhook nell'ambiente: Fase B BLOCCATA) e percorso browser
Partner (nessuno spec; coperto solo dalle griglie DB `12zr` e `12zp`).

## Ambiente

Stack Supabase effimero e isolato, creato da questa sessione: copia di `supabase/` in una cartella
temporanea con `project_id = vinea_b2_e2e` e porte `553xx` (lo stack condiviso `p_rogettto_vinae`, 101
migrazioni, non è stato toccato). 107 migrazioni applicate da zero, ledger = file. Suite lanciata con
`E2E_SUPABASE_URL`, `E2E_ANON_KEY`, `E2E_DB_CONTAINER` puntati allo stack isolato; la guardia di
isolamento del runner l'ha accettato.

## Browser (suite esistente, riutilizzata)

| Progetto | Esito |
| --- | --- |
| Chromium desktop | verde |
| Chromium 375 px | verde |
| WebKit | verde |

Totale **58/58** (3,2 min) dopo la correzione sotto; residui e interruttori a fine corsa: 0 e tutti falsi.
Coperti (spec `accessori-*`): Cantina → annuncio → quantità, prenotazione, riepilogo economico = database,
«Paga» con doppio click (un solo pagamento, solo l'id ordine), errore e riprova, «in elaborazione», il
solo redirect non conferma, conferma solo da `stato=pagato`, permessi e ruoli, interruttori spenti,
overflow a 375 px, accessibilità di base. Provider: **mock** (Stripe.js e `payments-checkout` finti nel
browser). Sessione scaduta e contestazione/annullo-scadenza-rimborso nel browser: non coperti da spec.

### Difetto trovato e corretto (P1 di harness)

`supabase/tests/12zk_vpm_015b3_e2e_cleanup.sql` rimuoveva solo il provider di prova `e2e_b5a`; lo spec
B5D crea `e2e_b5d` e non veniva ripulito. Primo progetto verde, secondo (mobile, WebKit) in collisione
(`logistics_service_definitions_corrente_idx`): la suite completa risultava 2 rossi + 6 non eseguiti, mai
visto in CI perché esegue solo lo smoke su Chromium desktop. Ora la pulizia copre entrambi i provider.

## Runtime del Refund provider (mock di `fetch`)

`rimborso-provider-runtime.test.ts` esegue `creaStripeRefundProvider` (4 test): richiesta a
`/v1/refunds` con `payment_intent`, importo, metadata di dominio, nessun campo `transfer*`; chiave di
idempotenza identica ai tentativi ripetuti; segreto assente ⇒ nessuna chiamata; rete assente, risposta
illeggibile e rifiuto del fornitore ⇒ errori tipizzati senza segreti. **Mock, non Stripe**: il comportamento
del provider reale resta NON VERIFICATO.

## Stripe test mode (Fase B): BLOCCATA

Verificata la sola presenza (nessun valore stampato): `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
`NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` assenti nell'ambiente dell'agente. Tutti i 20 scenari del punto 4
sono quindi **NON VERIFICATI con Stripe reale**. **BLOCCANTE PRIMA DEL LIVE.** Prerequisiti: chiavi TEST
in un ambiente autorizzato e isolato, webhook di test con segreto, ritorno/CORS consentiti, Stripe CLI o
endpoint raggiungibile per eventi firmati; da verificare in particolare la copia dei metadata del
PaymentIntent sulla Charge e `charge.refunded`.

## Post-vendita e riconciliazione

Invariato rispetto al CI di B5C/B1 (griglie 12zp, 12zq, 12zt; non rieseguite, non toccate). Non
rieseguiti in questa corsa: contestazione 48 h, decisione admin, evidenze, rimborso parziale/totale.

### Procedura operativa per i casi `incerto` e `refund_due` (mancava)

Non esiste una pagina admin: gli elenchi `accessori_pagamenti_intenti_orfani()` e
`accessori_pagamenti_rimborso_dovuto()` sono porte RPC per l'admin. Finché non c'è una pagina:

1. Un admin chiama le due RPC con la propria sessione (Studio/SQL Editor in sola lettura non basta: serve
   `auth.uid()` admin) e legge stato, importo, valuta, id ordine e id PaymentIntent.
2. `incerto`: cercare il PaymentIntent in Stripe Dashboard per id. Se `canceled`, nulla da fare: arriva
   (o va rinviato) l'evento firmato `payment_intent.canceled` che lo chiude. Se `succeeded`, deve
   comparire `refund_due` e il rimborso lo esegue `payouts-release`; se `processing`, attendere l'evento
   firmato. Mai annullare o rimborsare a mano senza annotare l'id.
3. `refund_due`: si chiude solo con `charge.refunded` firmato; non marcare a mano.
4. Qualsiasi incasso che non si riconcilia (importo/valuta/ordine divergenti) è un blocco pre-live.

## Rischi

| Livello | Rilievo | Stato |
| --- | --- | --- |
| P1 | Stripe test mode non eseguita (20 scenari, provider reale, `charge.refunded`, metadata Charge) | aperto, bloccante live |
| P1 | Nessuna pagina admin per orfani `incerto` e `refund_due` (solo RPC); procedura sopra | aperto, bloccante live; UI = nuova funzione, decisione del founder |
| P1 | Percorso browser Partner (sospensione/revoca, ordine già prenotato, 1500 bps, post-vendita Partner) senza spec; richiede fixture Partner e pulizia di tabelle di audit append-only | aperto, coperto solo da DB 12zr/12zp |
| P1 (corretto) | Pulizia E2E non copriva `e2e_b5d` | corretto in questa PR |
| P2 | Sessione scaduta e contestazione/annullo nel browser senza spec; job periodico di riconciliazione non creato (nessuna necessità tecnica dimostrata) | aperto |
| P2 | Metodi di pagamento asincroni vs finestra di prenotazione di 15 min | da decidere con la scelta dei metodi |
| P3 | Notifiche post-vendita non collegate (già in B5C) | aperto |

Nessun P0.
