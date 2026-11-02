# VPM-015QA-FINAL-A — Annullamento contro pagamento e ultima unità Partner

Collaudo e hardening del 3 novembre 2026 sopra B5A–B5D e C. **Verifica e corregge,
non riscrive**: nessuna tabella nuova, nessun sistema di giacenze o checkout
alternativo, nessun interruttore acceso, nessun pagamento reale.

## 1. Difetto corretto

`public.accessori_ordine_annulla` rifiutava solo l'ordine già pagato. Un
PaymentIntent collegato e ancora confermabile non impediva l'annullo, che
l'acquirente poteva chiamare direttamente (la UI B5D nasconde «Annulla», ma non
è un controllo). L'incasso arrivato dopo finiva in `refund_due`: nessun fondo
perso, ma l'esito dipendeva da una corsa evitabile.

Migrazione `20261103090000_vpm_015qa_final_a_annulla_con_pagamento.sql`
(`CREATE OR REPLACE`, stessi grant; le migrazioni distribuite non sono toccate).

## 2. Regola (decisa dal database, mai dal browser)

Lock `ordine → pagamento`, lo stesso ordine di `pagamento_apri`,
`pagamento_applica_evento`, rimborsi e rilascio: nessuna inversione.

| Pagamento | Annullo ordinario |
| --- | --- |
| nessuno | ammesso |
| `checkout_pending` **non collegato** | ammesso; il pagamento passa a `expired` (`ordine_annullato`) |
| `checkout_pending` **collegato**, prenotazione non scaduta | rifiutato `22023 pagamento_in_corso` |
| `checkout_pending`, prenotazione scaduta | ammesso → `scaduto`; pagamento `expired` |
| `processing` fino a 1 h dopo la scadenza | rifiutato `pagamento_in_corso` (stessa finestra della pulizia B5B) |
| `processing` oltre 1 h dopo la scadenza | ammesso → `scaduto` |
| ordine `pagato` | rifiutato `ordine_pagato` (invariato) |

Nessun blocco permanente: il rifiuto finisce con l'evento firmato (`paid`,
`failed` → `annullato`, `expired` → `scaduto`) o, al più, con la scadenza della
prenotazione (`prenotazione_min`, 15 minuti dal rinnovo) più l'ora di
protezione del `processing`. Il chiudi-scadute B5B resta com'è.

`accessori_pagamento_collega` non cambia: un pagamento non collegato chiuso
dall'annullo è `expired`, quindi la collega fallisce (`ordine_non_pagabile`) e
l'Edge Function non restituisce il `client_secret`: l'intento orfano non è
confermabile dal browser. Un incasso tardivo di un ordine chiuso resta il
percorso B5B/B5C (`refund_due`, rimborso in coda una volta, nessun accredito al
venditore).

UI: `pagamento_in_corso` ha un messaggio in `MESSAGGI_ORDINI_ACCESSORI`.

## 3. Prove (stack Postgres effimero, sessioni reali)

`supabase/tests/12zs_vpm_qa_final_a_concorrenza.sh`, agganciata a
`12g_ci_run.sh` dopo 12zr con la stessa guardia di identità (loopback, nonce,
nessun utente reale), fixture `@conc-12zs.test`, residui = 0, interruttori
ripristinati nel trap EXIT. 12 prove:

1. apertura pagamento contro annullo (3 giri): mai un intento agganciato a un ordine annullato;
2. pagamento collegato: annullo rifiutato, `failed` libera 4/4/4, annullo poi idempotente, replay `duplicate`;
3. `processing`: annullo rifiutato, incasso applicato una volta (2/2/2), replay `duplicate`, dopo il pagamento `ordine_pagato`;
4. incasso contro annullo con pagamento collegato (3 giri): sempre `pagato/paid`, annullo rifiutato, nessun `refund_due`;
5. due annulli paralleli: idempotenti;
6. scaduta + collegato: annullo → `scaduto`, incasso tardivo → `refund_due`, un solo rimborso in coda, nessun accredito al venditore;
7. `processing` oltre la scadenza: rifiutato entro l'ora, ammesso oltre, poi `refund_due`;
8. evento `expired`;
9. **ultima unità Partner**: due acquirenti, una sola prenotazione; retry con la stessa chiave = stesso ordine; il perdente resta rifiutato; 1/1/0; `partner:1500`;
10. il vincitore paga: giacenza 0 = somma dei movimenti (carico 1, vendita −1), post-vendita una volta;
11. sospensione contro prenotazione, poi revoca: nessuna nuova prenotazione, gli ordini già prenotati si incassano (nessun fondo congelato);
12. aliquote invariate (vino 800/1500, accessori 1000/1500), vino non toccato, nessun doppio rimborso.

La 12zo (concorrenza B5B, prova 3) resta verde: con pagamento collegato
l'esito è ora sempre `pagato`.

Mutazioni (migrazione sostituita da varianti, griglia rieseguita): vedi
`CHANGES.log` per l'esito.

## 4. Residuo noto (audit di sicurezza)

Annullo tra `apri` e `collega`: l'Edge Function ha già creato il PaymentIntent, ma
`collega` fallisce e la risposta è 502 senza `client_secret`; un nuovo `apri` è
rifiutato (ordine non più in attesa). L'intento orfano non è quindi confermabile dal
browser. Se lo fosse comunque, il webhook non troverebbe il pagamento («Pagamento non
riconosciuto»): nessuna riga `refund_due`. Chiusura prevista: annullare l'intento
orfano nell'Edge Function quando `collega` fallisce (richiede un metodo di
annullo nell'adapter e un deploy: fuori dal perimetro di questa PR, da portare a
QA-FINAL-B/pre-lancio). Le prove 1 e 5 coprono il lato database.

## 5. Non verificato

Stripe.js e PaymentIntent reali in test mode; browser E2E (QA-FINAL-B).
