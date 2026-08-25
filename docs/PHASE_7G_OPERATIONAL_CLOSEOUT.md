# Fase 7g — chiusura operativa dell'auto-rilascio

## Decisioni chiuse

- **1c:** le notifiche native di fallimento GitHub Actions arrivano al
  proprietario operativo Enrico / `enricopuntog-cpu`. Enrico ruota
  `PAYOUTS_JOB_TOKEN` ogni 90 giorni e subito dopo una sospetta esposizione.
  Nessuna integrazione esterna di notifica appartiene alla 7g.
- **1d:** cadenza `0 */6 * * *` e `PAYOUTS_BATCH_LIMIT=50`.
- **2c resta separata:** tetto futuro di 5 tentativi, marcatore derivato da
  `fee_tentativi >= 5`, nessun nuovo valore di `public.payment_stato`, nessuna
  migrazione in questo checkpoint.

## Implementazione locale

- `.github/workflows/payouts-auto-release.yml`: `schedule` più
  `workflow_dispatch`, timeout di job 5 minuti, timeout HTTP 45 secondi,
  concorrenza unica senza cancellare una richiesta già in corso, batch 50.
- `.github/scripts/payouts-release-job.mjs`: invia legacy anon JWT più
  `PAYOUTS_JOB_TOKEN`; non legge né invia la service role. Fallisce su timeout,
  HTTP non 2xx, JSON o payload inatteso, `falliti > 0` o backlog di sanità.
- `supabase/functions/payouts-release/index.ts`: accetta il batch esplicito,
  massimo 500, e restituisce il conteggio delle righe con
  `auto_rilascio_scadenza` più vecchia di 24 ore e
  `payout_stato='trattenuto'`.
- Con `PAYMENTS_ENABLED=false` la function autentica e misura soltanto la
  sanità: non chiama `ordine_auto_rilascio_esegui`, non prepara Transfer e non
  chiama Stripe.

Il gateway della function resta `verify_jwt=true`. Per questo il secret GitHub
`SUPABASE_ANON_KEY` deve contenere la legacy anon JWT, usata in `apikey` e
`Authorization`. Una chiave `sb_publishable_...` non è un JWT: adottarla richiede
una decisione separata sulla configurazione del gateway. La service role rimane
solo nell'ambiente server della function.

## Verifica locale

Il runner è stato verificato senza rete e senza invocare la Edge Function reale:

```text
node --check .github/scripts/payouts-release-job.mjs
node --check .github/scripts/payouts-release-job.test.mjs
node --test .github/scripts/payouts-release-job.test.mjs
npx --yes deno@latest check --config supabase/functions/deno.json supabase/functions/payouts-release/index.ts
```

Risultato: **8 test superati, 0 falliti**. Coperti richiesta e header, gate
spento, HTTP non 2xx senza lettura del body, payload inatteso, fallimento di un
rilascio, backlog oltre 24 ore, timeout e batch fuori limite.
Il controllo di tipo Deno della Edge Function è superato.

Validati inoltre JSON del manifest, YAML del workflow, TOML Supabase, struttura
di `CHANGES.log`, `git diff --check` e scansione locale dei pattern di segreto:
tutti superati.

## Stato remoto rimasto aperto al checkpoint 7g

Questo checkpoint non configurò né ruotò nulla. Prima dell'attivazione restavano
da completare:

1. configurare la variabile Actions `SUPABASE_URL` e i secret
   `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN`, verificando che quest'ultimo
   coincida con il secret della Edge Function;
2. portare il workflow sul branch di default e verificare che le notifiche
   native di fallimento raggiungano `enricopuntog-cpu`;
3. eseguire un primo `workflow_dispatch` reale con `PAYMENTS_ENABLED=false`:
   deve restituire solo sanità e zero azioni di rilascio. L'invocazione reale non
   fu eseguita in 7g e resta una protezione obbligatoria prima di abilitare i
   pagamenti.

## Gate dello scheduler — 2026-08-25

Il punto 1 sopra restò aperto, e per mesi il workflow provò comunque a invocare
la function a ogni cadenza: i secret mancavano, il runner falliva prima della
richiesta, e ogni sei ore comparve un fallimento schedulato indistinguibile da
uno scheduler rotto. Non era una regressione: era uno scheduler mai autorizzato
che non sapeva dirlo.

La variabile Actions `PAYOUTS_SCHEDULER_ENABLED` rende esplicita la differenza
fra i due casi:

- assente, vuota o diversa dalla stringa esatta `true`: nessun secret letto,
  nessuna richiesta HTTP, nessun payout, uscita pulita con notice
  `Payouts scheduler disabilitato`;
- esattamente `true`: percorso reale invariato, con `SUPABASE_URL`,
  `SUPABASE_ANON_KEY` e `PAYOUTS_JOB_TOKEN` obbligatori. Configurazione
  mancante, HTTP non 2xx, payload inatteso, timeout, `falliti > 0` e backlog
  oltre 24 ore restano fallimenti pieni. Il gate non nasconde errori: sceglie
  soltanto se lo scheduler ha il diritto di partire.

Il gate vive nel runner e non in un `if:` YAML perché la decisione resti in un
solo punto eseguibile dai test. La variabile remota non è stata impostata in
questo build, e il gate resta quindi chiuso. Restano validi i punti 1-3 sopra.

La sessione 7g registrò inoltre come non autorizzati SQL e fixture remoti, deploy
manuali, impostazioni Supabase, configurazione o rotazione secret, chiamate
Stripe, push, PR, merge e `PAYMENTS_ENABLED`. È un confine storico di quel
task, non la policy operativa corrente: `CLAUDE.md` autorizza oggi il normale
ciclo Git e Supabase richiesto dal task, senza rimuovere la prova a pagamenti
spenti né le altre protezioni tecniche.
