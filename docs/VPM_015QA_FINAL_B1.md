# VPM-015QA-FINAL-B1 — PaymentIntent orfani degli ordini Accessori

Hardening del 3 novembre 2026 sopra B5B/B5C/QA-FINAL-A. **Integra, non riscrive**: nessun
nuovo checkout, webhook, client Stripe o motore di rimborso; nessuna tabella nuova. Nessun
interruttore acceso, nessun pagamento, rimborso o chiamata Stripe reali.

## 1. Difetto

`payments-checkout` crea il PaymentIntent presso Stripe **dopo** `accessori_pagamento_apri` e lo
lega **dopo** con `accessori_pagamento_collega`. Se l'acquirente annulla in mezzo, QA-FINAL-A
chiude il pagamento non collegato come `expired`, la collega fallisce (502) e l'intento resta
vivo presso Stripe. Un suo incasso non trovava nessuna riga (`Pagamento non riconosciuto`):
denaro non riconciliabile.

## 2. Strategia

Contratto Stripe verificato (docs.stripe.com, `POST /v1/payment_intents/{id}/cancel`): annullabile in
`requires_payment_method`, `requires_confirmation`, `requires_action`, `requires_capture` e, di rado,
`processing`; già annullato o non annullabile ⇒ errore (`payment_intent_unexpected_state`).

Migrazione additiva `20261103120000_vpm_015qa_final_b1_intenti_orfani.sql`:

| Elemento | Funzione |
| --- | --- |
| `accessori_pagamenti.intento_orfano_stato/_at` | `da_annullare`, `annullato`, `incerto`, `incassato` |
| `accessori_pagamento_orfano_gestisci` (service_role) | sotto lock ordine → pagamento decide: `collegato` (richiesta concorrente riuscita), `aperto` (ancora pagabile: retry), `conflitto` (altro intento), `orfano` (registra l'intento sulla riga chiusa) |
| `accessori_pagamento_orfano_esito` (service_role) | registra l'esito dell'annullo; `incassato` riverifica importo, valuta e ordine ⇒ `refund_due` (coda B5C); divergenza ⇒ `incerto` visibile |
| wrapper `accessori_pagamento_applica_evento` | un `settled` firmato su un intento **mai registrato** si riconosce solo per ordine dei metadata + riga ancora non collegata + importo/valuta ⇒ `refund_due`, **mai vendita**; `payment_intent.canceled` firmato chiude un annullo incerto |
| `accessori_pagamenti_intenti_orfani` (admin) | elenco di `da_annullare` e `incerto` |
| `accessori_pagamento_collega` (CREATE OR REPLACE) | lo stesso intento registrato come orfano non si ricollega: una richiesta concorrente non riceve il client secret |

Edge Function: `gestisciCollegaFallita` chiama la decisione; solo su `orfano` usa
`annullaCheckout` dell'adapter Stripe esistente (chiave idempotente `cancel-<intent>`), poi registra
l'esito. Un `client_secret` di un intento non collegato non esce mai. Se la decisione stessa fallisce,
**non si annulla nulla** (l'intento potrebbe essere collegato).

## 3. Esiti

| Esito Stripe | Registrazione |
| --- | --- |
| cancellazione confermata | `annullato` |
| già annullato (riletto) | `annullato` (idempotente) |
| `succeeded` | `incassato` ⇒ `refund_due`, un rimborso in coda; nessuna vendita/accredito |
| `processing` | `incerto` (Stripe non lo annulla) ⇒ admin; `succeeded`/`canceled` firmati lo risolvono |
| rete/timeout/risposta ambigua/segreto assente | `incerto`, mai «annullato» |
| webhook concorrente | evento deduplicato; un annullo tardivo non declassa un `incassato` |

Recupero di un `incerto`: l'evento firmato `payment_intent.canceled` (anche dopo annullo manuale dalla
dashboard) lo chiude; `succeeded` lo porta a `refund_due`.

## 4. Prove

- `supabase/tests/12zt_vpm_qa_final_b1_intenti_orfani.sh` (15 prove su sessioni PostgreSQL reali, nel
  gate): regolare, annullo prima/dopo l'intento, due collega concorrenti, collega contro annullo (3 giri),
  aperto/conflitto, incerto + recupero firmato, incassato, incasso su orfano registrato e **mai
  registrato**, divergenze, checkout spento, orfano con ordine scaduto (mai vendita), privilegi/immutabilità, invarianti (vino e venditore intatti).
- `frontend-next/src/lib/accessori-ordini/accessori-intenti-orfani.test.ts` (26 test): esegue la **vera**
  Edge Function (runtime Deno finto, client Supabase finto, Stripe mock con macchina a stati; Deno non è
  disponibile in locale, perciò gli import sono riscritti in una copia identica); soglia CI 3306.
- Mutazioni: rimuovere l'annullo, ignorare la decisione, non adottare l'incasso non collegato, non
  risolvere con `canceled`, non riverificare l'importo ⇒ test rossi.

## 5. Limiti (pre-live, per QA-FINAL-B2)

1. **Stripe reale in test mode non provato**: contratto letto dalla documentazione, non eseguito.
2. Se il database è irraggiungibile proprio dopo la creazione dell'intento, nulla viene annullato né
   registrato; l'eventuale incasso è riconosciuto dal webhook (ordine dei metadata) e va a `refund_due`,
   ma un intento mai pagato resta presso Stripe fino alla scadenza naturale (nessun client secret emesso).
3. Un annullo `incerto` senza evento firmato successivo richiede l'azione manuale in Stripe (l'elenco
   admin lo mostra); non esiste un job di ritentativo automatico.
4. Un incasso con importo/valuta/ordine divergente su intento non registrato solleva `P0001` e Stripe
   ritenta (come per il vino): resta visibile nei log/dashboard Stripe, non in elenco admin.
5. `buyer_id` non è nel payload normalizzato del webhook: l'identità è ordine + importo + valuta + riga non collegata.
6. Il rimborso reale dei `refund_due` resta quello di B5C (non eseguito qui).
7. Un incasso adottato su un ordine ancora pagabile lascia l'ordine `in_attesa_pagamento` (riserva) fino
   alla scadenza naturale (15 minuti): nessuna vendita, il rimborso è in coda.
8. Un orfano `incerto` ricevuto oltre il primo tentativo viene ritentato quando una richiesta concorrente
   rilancia la decisione (`orfano` finché non confermato); non c'è un job periodico.

## 6. Revisioni indipendenti

Audit di sicurezza (agente `vinea-security-auditor`) e code review (`vinea-code-reviewer`): nessun
bloccante. Recepiti: retry dell'annullo di un orfano non confermato, vendita impossibile su un orfano
registrato con ordine scaduto (prova 14), `collega` che non restituisce il secret di un orfano,
messaggio 409 neutro, commenti sulle funzioni. Accettati e documentati: limiti 2–8.
