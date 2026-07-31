# Fase 7 — piano atomico del primo checkpoint

## Gate completati prima del codice

1. Verificare PR #17, merge squash, CI e `origin/main`.
2. Verificare read-only la migration history, senza rieseguire griglie.
3. Correggere gli stati post-merge in ROADMAP, backlog e `CHANGES.log`.
4. Tentare una sola volta lo smoke Storage soltanto con cleanup API garantito;
   in caso contrario documentare il blocco e non creare fixture.

## Implementazione

1. Creare con la CLI una migrazione locale Fase 7; se la CLI non è disponibile,
   registrare il blocco e creare un file timestampato senza applicarlo.
2. Aggiungere limiter Postgres condiviso e pre-request hook Data API.
3. Aggiungere enum, tabelle, constraint, indici, RLS e grant di proposte,
   ordini, pagamenti, eventi e deduplicazione webhook.
4. Aggiungere RPC atomiche per proposte, prenotazione, compensazione, aggancio
   sessione e applicazione webhook.
5. Implementare `payments-checkout` con JWT verificato, flag server-side,
   rate limit, riserva database e idempotenza Stripe.
6. Implementare il Route Handler webhook su raw body, firma HMAC, whitelist
   eventi, rate limit post-firma e RPC transazionale.
7. Aggiornare i contratti e aggiungere gli adapter reali dei tre servizi senza
   collegare percorsi UI non ancora portati.
8. Aggiornare esempi ambiente, architettura, sicurezza e stato della roadmap.

## Verifica

1. Testare firma valida/non valida e tolleranza temporale.
2. Testare replay dello stesso evento e rifiuto di regressioni tardive.
3. Testare due compratori concorrenti e retry idempotente.
4. Testare limiter locale e ispezionare staticamente hook/UPSERT SQL.
5. Eseguire `test`, lint, typecheck e build di `frontend-next`.
6. Eseguire controlli di sintassi SQL disponibili, `git diff --check` e scansione
   segreti.
7. Committare per checkpoint, pushare solo il branch Fase 7, aprire draft PR e
   monitorare la CI senza passare a ready e senza merge.

