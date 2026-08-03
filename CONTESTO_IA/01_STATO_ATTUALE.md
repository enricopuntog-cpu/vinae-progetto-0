# Stato attuale verificato

Fotografia del **3 agosto 2026**.

## Repository

| Voce | Valore |
| --- | --- |
| Repository GitHub | [`enricopuntog-cpu/vinae-progetto-0`](https://github.com/enricopuntog-cpu/vinae-progetto-0) |
| Branch attivo | `migration/phase-7-order-payment-service` |
| HEAD del branch | `62cf75a` |
| Base verificata | `3037bf4` — merge squash della PR #17 |
| `origin/main` verificato | `3037bf4` — Fase 6d-2a integrata |
| Distanza del branch attivo da `origin/main` | 33 commit avanti, 0 indietro |
| Distanza dal proprio `origin` | 0 avanti, 0 indietro |
| Ultima fase integrata in `main` | Fase 6d-2a — provenienza catalogo e percorsi Cantina |
| Attività corrente | Fase 7 sul branch dedicato, in attesa del merge della PR #18 |
| PR della 6d-1 | [#14](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14) — merged |
| PR di riconciliazione | [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) — merged |
| PR di verifica post-merge 6d-1 | [#16](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/16) — merged il 30 luglio 2026 |
| PR della 6d-2a | [#17](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17) — merged il 31 luglio 2026 |
| PR della Fase 7 | [#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) — aperta, draft, mai mergiata |

## Stato Git e prove

La PR #14 è stata unita in `main` con merge commit `61e3fde`. L'HEAD finale del
branch era `6bbe4dd`; la run GitHub Actions
[`30554736346`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30554736346)
è verde per backend, frontend e frontend-next.

Il 30 luglio 2026 la migration history del progetto Supabase
`pijnmcllmfgjmgsvtcej` registra anche
`20260730162046 fix_6d1_bottle_message_encoding`. La migrazione corregge la
codifica UTF-8 dei messaggi di `bottiglia_apri` e `bottiglia_cancella` senza
modificare dati applicativi.

Le griglie remote autorizzate separatamente restituiscono 33/33 e 11/11. Il
verifier repair storico resta 13/13 e il controllo finale dei residui fixture
restituisce zero in tutte le categorie registrate. Il rapporto corrente è
[`../docs/PHASE_6D1_POST_MERGE_VERIFICATION.md`](../docs/PHASE_6D1_POST_MERGE_VERIFICATION.md).

## Quale versione è servita

- `frontend/` — React 19 + TanStack Start: **frontend corrente servito**.
- `backend/` — FastAPI + MongoDB: **backend corrente servito**, transitorio.
- `frontend-next/` — Next.js App Router: **frontend target in migrazione**.
- `supabase/` — PostgreSQL, Auth, RLS, Storage e migrazioni: **backend target**.

`frontend-next/` non va descritto come produzione. Il cutover appartiene alla
Fase 11 e richiede una decisione esplicita.

## Domini già migrati nello stack target

| Dominio | Stato |
| --- | --- |
| Auth email/password e magic link | Integrato in `main` — Fase 5a |
| OAuth Google + callback server-side | Integrato in `main` — Fase 5b |
| OAuth Facebook | Codice predisposto, provider/UI disabilitati per configurazione esterna non funzionante |
| Catalogo e annunci in lettura | Integrato in `main` — Fase 6a |
| Creazione/pubblicazione annunci e foto | Integrato in `main` — Fase 6b |
| Cantina: schema, metadati e posizioni | Integrato in `main` — Fase 6c-1 |
| Cantina: pagina, store reale, vendita da bottiglia | Integrato in `main` — Fase 6c-2 |
| Invarianti bottiglia–annuncio e hardening RLS | Integrati in `main` — Fase 6d-1; prove post-merge 33/33 e 11/11, residui zero |
| Provenienza catalogo e percorsi Cantina | Integrati in `main` — Fase 6d-2a, PR #17 al merge squash `3037bf4`; smoke Storage del bucket `cantina` ancora aperto |
| Ordini, proposte, pagamenti | Sul branch `migration/phase-7-order-payment-service` — Fase 7; draft PR #18 aperta e mai mergiata, nulla applicato al progetto Supabase reale |
| Messaggi e notifiche | Non migrati — Fase 8 |
| Moderazione e audit persistente | Non migrati — Fase 9 |
| AI reale | Non migrata — Fase 10 |
| Cutover | Non iniziato — Fase 11 |

## Fase 6d-1 integrata

La PR #14 ha integrato migrazioni, regole agenti, repair della deriva, verifier
e documentazione. I punti principali sono:

- revoca dei privilegi di lettura/scrittura troppo ampi;
- viste pubbliche a elenco chiuso di colonne;
- una sola bottiglia fisica per annuncio e un solo annuncio non terminale per
  bottiglia;
- blocco di vendita per bottiglie aperte, consumate, cancellate o già cedute;
- controllo maggiore età server-side per la vendita;
- RPC atomiche per apertura e rimozione;
- trigger bidirezionali sugli invarianti bottiglia–annuncio;
- `ceduta_at` e liberazione dello slot quando una vendita si conclude;
- test SQL versionati e query di verifica del catalogo PostgreSQL;
- documentazione del passaggio di responsabilità alla futura Fase 7.

La verifica read-only post-repair documentata in
[`../docs/PHASE_6D1_SUPABASE_REVIEW.md`](../docs/PHASE_6D1_SUPABASE_REVIEW.md)
riporta:

- 13/13 controlli nominali `PASSA`;
- 0 funzioni `SECURITY DEFINER` eseguibili da `anon`;
- 8 RPC applicative eseguibili da `authenticated`;
- 0 duplicati non terminali e 0 mismatch venditore/proprietario.

Le baseline pre-repair erano 31/33 e 7/11. Il retest finale post-repair è
33/33 e 11/11; la correzione dei due messaggi UTF-8 è versionata nella
migrazione `20260730162046`. Questi risultati chiudono il gate tecnico ma non
dichiarano il prodotto pronto per la produzione.

## Fase 7 — proposte, ordini, pagamenti

**Stato:** lavorata sul branch `migration/phase-7-order-payment-service`, draft
PR [#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) aperta e
mai mergiata. Nulla è ancora applicato al progetto Supabase reale.

Consegnato sul branch:

- schema versionato in
  [`20260731135455_phase_7_order_payment_service.sql`](../supabase/migrations/20260731135455_phase_7_order_payment_service.sql),
  917 righe: `proposals`, `orders`, `payments`, `order_events`,
  `payment_provider_events`, con prenotazione atomica dell'unità in
  `order_checkout_reserve`, idempotenza sulla chiave `(provider, event_id)`,
  RLS e grant a colonne chiuse;
- rate limiting condiviso lato server: `private.rate_limit_buckets`,
  `private.vinea_check_request` e l'aggancio a PostgREST tramite
  `alter role authenticator set pgrst.db_pre_request` alla riga 140;
- Edge Function
  [`payments-checkout`](../supabase/functions/payments-checkout/index.ts) dietro
  il gate server-side `PAYMENTS_ENABLED=false`, con l'adapter Stripe isolato
  dietro l'interfaccia `PaymentProvider`;
- webhook Stripe come Route Handler Next.js su corpo raw, con firma HMAC
  verificata prima del parsing e deduplicazione degli eventi già registrati;
- adapter reali di `ProposalService`, `OrderService` e `PaymentService` in
  [`frontend-next/src/services/phase7/`](../frontend-next/src/services/phase7/);
- riparazione del ledger delle migrazioni con
  `20260729234000_rls_auto_enable_bootstrap`, che rende la storia ricostruibile
  da zero.

### Verifica remota — 3 agosto 2026

Riportata dalla chat organizzativa, che ha creato un branch Supabase di sviluppo
temporaneo e lo ha eliminato nella stessa sessione. Nessun branch esiste ora
oltre a `main`.

| Cosa | Esito |
| --- | --- |
| Replay del ledger riparato | 15 su 15, nessun arresto |
| Migrazione di Fase 7, 917 righe | applicata per intero, senza errori |
| Tabelle `public` create | 5 — `proposals`, `orders`, `payments`, `order_events`, `payment_provider_events` |
| Funzioni create | 11 |
| `rolconfig` di `authenticator` | contiene `pgrst.db_pre_request=private.vinea_check_request` |

L'ultima riga chiude l'unica incognita tecnica che restava: il privilegio
`alter role` esiste davvero. È una misura eseguita fuori dal repository e
registrata come tale, non riverificabile da Git; prova che la storia è
ricostruibile, non che il branch temporaneo fosse identico al progetto reale.

### Fuori scope e non autorizzato da questa fase

- `apply_migration` della migrazione di Fase 7 sul progetto reale;
- distribuzione della Edge Function `payments-checkout`;
- esecuzione della griglia
  [`supabase/tests/7_ordini_pagamenti.sql`](../supabase/tests/7_ordini_pagamenti.sql)
  — 16 casi, mai eseguita; gira in una sola sessione, quindi la gara concorrente
  non è provata dai casi che verificano l'invariante;
- smoke Storage della 6d-2a, ancora aperto e indipendente da questa fase;
- Stripe Connect, payout, KYC e contestazioni operative.

## Prossimo confine corretto

Non resta alcun gate tecnico per il merge della PR #18: la verifica remota del
3 agosto 2026 ha chiuso l'ultima incognita. Restano azioni umane e gate
separati, in quest'ordine:

1. incollare il corpo aggiornato nella PR #18, toglierle lo stato draft e
   mergiarla a mano su GitHub — decisione di Enrico, mai autonoma;
2. dopo il merge, autorizzare esplicitamente `apply_migration` della migrazione
   di Fase 7 sul progetto reale e riallineare il filename alla versione
   assegnata dal server;
3. autorizzare separatamente il deploy di `payments-checkout`, l'esecuzione
   della griglia `7_ordini_pagamenti.sql` e lo smoke Storage della 6d-2a.
