# Riconciliazione pre-Fase 7 — rapporto di handoff

Documento autosufficiente. Chi lo legge non ha bisogno di alcun contesto
precedente del repository per valutare la Fase 7.

- Data della verifica: 2 agosto 2026.
- Repository: `enricopuntog-cpu/vinae-progetto-0`.
- Natura della verifica: sola lettura su Git e GitHub. Nessuna azione su risorse
  remote (Supabase, Storage, Stripe) è stata eseguita durante questa verifica,
  per vincolo esplicito del mandato.
- Orari: UTC salvo diversa indicazione.

## 0. Contesto minimo indispensabile

Vinea è un'app web italiana per un wine club. Il repository è a metà migrazione:
`frontend/` (TanStack Start) + `backend/` (FastAPI/MongoDB) sono **la versione
effettivamente servita**; `frontend-next/` (Next.js App Router) + `supabase/`
sono l'architettura **di destinazione**, migrata un dominio alla volta.

Ordine dei domini: Auth (5) → Listings/Catalogo (6) → **Ordini/Pagamenti (7)** →
Messaggistica (8) → Moderazione (9) → AI (10) → Cutover (11).

Regole di processo rilevanti per questo rapporto (da `CLAUDE.md` e `AGENTS.md`):

- una fase = un branch = una draft PR;
- **nessuna fase inizia senza approvazione esplicita** registrata nel log
  organizzativo;
- nessun merge autonomo verso `main`; nessun lavoro diretto su `main`;
- nessun SQL applicato a un progetto Supabase remoto senza approvazione
  esplicita nella sessione corrente.

## 1. Stato Git verificato

Comandi eseguiti: `git fetch --prune origin`, `git log --oneline --decorate -20
origin/main`, `git status --short --branch`.

- `origin/main` = `main` locale = `3037bf4f8fa5269895bb01a998d85bb5f629cd34`.
- Working tree pulito, nessun file non tracciato, nessun divergere da origin.
- Ultimi commit su `origin/main`:

```text
3037bf4  Fase 6d-2a — Catalogo e percorsi Cantina (#17)
dc1fe88  Chiude il gate post-merge della Fase 6d-1 (#16)
e2e4fcb  Riconcilia handoff post-merge della Fase 6d-1 (#15)
61e3fde  Fase 6d-1 — Security invariants and remote drift repair (#14)
a857f3b  Migration/phase 6c cellar UI (#12)
```

## 2. PR #17 — Fase 6d-2a: stato esatto

<https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17>

| Campo | Valore verificato |
|---|---|
| Stato | `MERGED` |
| Titolo | Fase 6d-2a — Catalogo e percorsi Cantina |
| Branch sorgente | `migration/phase-6d-2a-catalog-cellar-paths` |
| Base | `main` |
| Aperta il | 2026-07-31 11:43:21Z |
| Merge il | 2026-07-31 **13:37:21Z** (15:37:21 +02:00) |
| Merge da | `enricopuntog-cpu` (proprietario del repository) |
| Tipo di merge | **squash** — `3037bf4` ha un solo padre, `dc1fe88` |
| Commit di merge | `3037bf4f8fa5269895bb01a998d85bb5f629cd34` |
| HEAD del branch al merge | `c54939213686ea5ca02e26434a3079cfd474be89` |
| Dimensione | 19 file, +1581 / −191 |
| Review su GitHub | **nessuna**: zero review, zero commenti |

Il branch sorgente `origin/migration/phase-6d-2a-catalog-cellar-paths` **non è
stato eliminato** dopo il merge e punta ancora a `c549392`.

### 2.1 Il merge è stato preceduto da CI verde? Sì

| Run | SHA | Evento | Creata | Conclusa | Esito |
|---|---|---|---|---|---|
| #44 (`30635023614`) | `c549392` — **l'esatto commit mergiato** | pull_request | 13:34:49Z | 13:35:52Z | `success` |
| #45 (`30635200772`) | `3037bf4` — merge su main | push | 13:37:24Z | — | `success` |

I tre job della run #44 sono tutti `success`:
`Backend - lint, syntax and tests`, `Frontend - lint, typecheck, test, build`,
`Frontend Next - lint, typecheck, build`.

CI conclusa alle 13:35:52Z, merge alle 13:37:21Z: **89 secondi dopo**, sullo
stesso SHA. Il gate CI pre-merge è quindi confermato. La CI post-merge su `main`
è anch'essa verde.

Nota storica: `CHANGES.log` presente su `main` cita la run `30629492177` (#43)
sull'HEAD `e6329a5`. Quella run è reale e verde, ma **precede** l'ultimo commit
della PR (`c549392`, "Document Phase 6d-2a fixture verification"). La run che
copre davvero il codice mergiato è la #44. Nessuna contraddizione: entrambe sono
verdi, ma per il gate pre-merge va citata la #44.

### 2.2 Contenuto effettivo del merge

```text
CHANGES.log                                             |  43 +-
docs/MIGRATION_PHASE_1_BACKLOG.md                       |  14 +
docs/PHASE_6D2A_FIXTURE_VERIFICATION.md                 | 113 ++++
docs/PHASE_6D2A_SPEC.md                                 |  37 ++
docs/ROADMAP_V1.md                                      |   9 +
docs/SECURITY.md                                        |  18 +-
frontend-next/src/app/home/page-client.tsx              |  43 +-
frontend-next/src/app/vendi/actions.ts                  |  25 +-
frontend-next/src/app/vendi/bottle-selector.tsx         |  76 +++
frontend-next/src/app/vendi/page-client.tsx             |  33 +-
frontend-next/src/components/vinea/WineCard.tsx         |  50 +-
frontend-next/src/data/wines.ts                         |   8 +
frontend-next/src/hooks/useSellWizard.ts                |  99 +--
frontend-next/src/services/cellar-service.ts            | 123 +--
frontend-next/src/services/listing-service.ts           |  44 +-
frontend-next/src/services/types.ts                     |  40 +-
supabase/migrations/20260731120340_catalog_cellar_paths.sql | 594 +++++
supabase/tests/6d-2a_catalog_cellar_paths.sql           | 382 +++++
supabase/tests/README.md                                |  21 +-
```

Il merge contiene esclusivamente catalogo e percorsi Cantina. **Non contiene
ordini, proposte, pagamenti né trasferimento di proprietà.**

### 2.3 I gate 6d-2a dichiarati corrispondono al merge?

Verificati direttamente sul contenuto di `3037bf4`:

| Gate dichiarato | Esito della verifica | Evidenza |
|---|---|---|
| Griglia remota 18/18 `PASSA`, 0 `FALLISCE` | **Documentato e coerente** | `docs/PHASE_6D2A_FIXTURE_VERIFICATION.md` righe 16-48: tabella dei 18 casi tutti `PASSA` + output `[{"passa":18,"fallisce":0,"totale":18}]` |
| SHA-256 del file griglia eseguito | **CONFERMATO byte per byte** | `supabase/tests/6d-2a_catalog_cellar_paths.sql` = `6ed78d2dfa163cdf98c73a51599d16400c40a6cabbdfb9e0b099d4d49991d951`, identico a quello dichiarato |
| SHA-256 della migrazione | **CONFERMATO byte per byte** | `supabase/migrations/20260731120340_catalog_cellar_paths.sql` = `ffb0d4351e12bade1891e7912825a9d9ecb410b2c0df642e9c2d5f129d7d5834` |
| Backfill provenienza + `creato_da` | **CONFERMATO nel SQL** | righe 12-50: enum `wine_provenienza ('staff','utente')`, backfill `update`, `set not null`, default `'staff'`, indice parziale `wines_creato_da_idx` |
| RLS + grant di colonna | **CONFERMATO nel SQL** | `revoke select on public.wines from anon, authenticated` (r. 93) + `grant select (...)` a colonne chiuse (r. 94); policy `wines_select_curated` / `wines_select_own_user` / `wines_insert_staff`; quattro policy `cantina_*` su `storage.objects` |
| RPC con `search_path = ''` | **CONFERMATO 4/4** | righe 214, 319, 412, 457 per `private.catalogo_risolvi_vino_utente`, `public.cellar_bottiglia_aggiungi`, `public.listing_crea_da_bottiglia`, `public.cellar_ambiente_crea` |
| Zero residui fixture | **Documentato e coerente** | caso 18 della griglia + query read-only indipendente con `totale: 0` su auth_users, profiles, wines, bottle_units, listings, cellar_environments, cellar_modules, storage_objects |

**Limite di questa verifica, da tenere presente.** La griglia 18/18 e i residui
zero sono l'esito di un'esecuzione **sul progetto Supabase remoto**: non sono
riproducibili da Git e in questa sessione il progetto remoto non è stato
interrogato (vincolo del mandato). Ciò che Git dimostra è che *il file eseguito è
esattamente quello versionato* (SHA-256 identico) e che *la migrazione versionata
implementa davvero backfill, RLS, grant di colonna e `search_path` dichiarati*.
Il verbale dell'esecuzione resta una dichiarazione documentale, non riverificata.

**Conclusione PR #17: il merge corrisponde a quanto `CHANGES.log` dichiara come
gate 6d-2a chiuso, con la sola correzione della run CI da citare (#44, non #43).**

## 3. Smoke Storage autenticato sul bucket `cantina` — RESTA APERTO

**Non è stato eseguito in nessun momento fra la chiusura della sessione
precedente e oggi.** Non è stato trovato alcun riscontro di esecuzione in commit,
PR, branch o documenti; al contrario, esistono due registrazioni esplicite di
mancata esecuzione, cronologicamente successive l'una all'altra.

Primo tentativo — `docs/PHASE_6D2A_FIXTURE_VERIFICATION.md` su `main`
(righe 69-86), scritto prima del merge della PR #17:

- primo tentativo respinto da Auth perché il TLD `.invalid` non è accettato;
  nessun utente creato;
- secondo tentativo con `example.com` respinto dal rate limit Auth con HTTP 429,
  prima della creazione di sessioni;
- nessun upload, nessun oggetto inserito via SQL;
- verifica finale: `utenti_storage = 0`, `profili_storage = 0`,
  `oggetti_cantina = 0`.

Secondo tentativo — `docs/PHASE_7_VERIFICATION.md` sul branch della PR #18
(righe 13-24), scritto dopo il merge della PR #17:

- lo smoke **non è stato avviato**: la sessione del browser Supabase era
  reindirizzata al login, quindi non era disponibile un percorso Auth Admin/API
  per eliminare con certezza i due utenti tecnici al termine;
- creare gli utenti con la sola chiave publishable avrebbe violato il requisito
  di cleanup totale;
- nessun utente, oggetto o URL firmato creato; nessun retry; lo stato del
  precedente rate limit Auth non è quindi stato misurato.

### Procedura residua per chiuderlo

1. Autenticare la dashboard Supabase e garantire un percorso Auth Admin/API per
   il cleanup.
2. Eseguire **una sola** registrazione tecnica; se risponde `429`, fermarsi.
3. Se riesce: upload di una PNG nella cartella del proprietario nel bucket
   privato `cantina`, lettura owner, creazione e lettura della signed URL.
4. Verificare il **rifiuto** della lettura diretta con il secondo JWT.
5. Cancellare oggetto e utenti via API amministrativa.
6. Riverificare zero utenti, zero profili, zero oggetti nel bucket.

Il bucket è già verificato come privato, con limite upload 5 MiB, MIME immagine
e quattro policy per cartella proprietaria; quel che manca è la **prova end-to-end
autenticata** dell'isolamento fra proprietari.

## 4. PR #18 — Fase 7: stato esatto

<https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18>

| Campo | Valore verificato |
|---|---|
| Stato | `OPEN`, **draft** |
| Titolo | Fase 7 — ordini e pagamenti (checkpoint locale) |
| Branch | `migration/phase-7-order-payment-service` |
| Base | `main` (`3037bf4`) |
| HEAD | `fe3c9723e9c7a6f4884d091b18097ad3c76f4bc8` |
| Creata il | 2026-07-31 14:15:33Z |
| Ultimo aggiornamento | 2026-07-31 14:17:12Z |
| Commit | **6**, nessuno oltre a quelli noti |
| Dimensione | 34 file, +2027 / −78 |
| Mergeable | `MERGEABLE` / `CLEAN` |
| Merge | **nessuno** |
| Review / commenti | **nessuna**: zero review, zero commenti |

I 6 commit, in ordine:

```text
92b80b3f  2026-07-31T14:12:59Z  docs: define phase 7 order payment checkpoint
e40a2be9  2026-07-31T14:13:19Z  feat(supabase): add phase 7 payment core
6f3d14ab  2026-07-31T14:13:26Z  feat(next): add phase 7 payment adapters
5d96b18f  2026-07-31T14:13:53Z  docs: record phase 7 security gates
712912d5  2026-07-31T14:14:49Z  chore: update phase 7 handoff
fe3c9723  2026-07-31T14:17:10Z  chore: record phase 7 draft PR
```

Confermato: **resta draft, nessun merge, esattamente i 6 commit già noti.**

### 4.1 Cosa è incluso

**Schema** — un solo file nuovo,
`supabase/migrations/20260731135455_phase_7_order_payment_service.sql` (841
righe). La sua intestazione dichiara: *"File locale: non applicato al progetto
remoto."* Contiene:

- rate limiting condiviso: tabella `private.rate_limit_buckets` (RLS attiva,
  `revoke all` da `public`/`anon`/`authenticated`), funzione
  `private.rate_limit_consume`, hook `private.vinea_check_request`, wrapper
  `public.rate_limit_consume`;
- enum: `proposal_stato`, `order_stato`, `delivery_mode`, `payment_stato`;
- tabelle: `proposals`, `orders`, `payments`, `order_events`,
  `stripe_webhook_events` (deduplicazione webhook);
- policy `*_participants_select` su proposte, ordini, pagamenti ed eventi;
- RPC: `proposal_invia`, `proposal_controproponi`, `proposal_accetta`,
  `proposal_rifiuta`, `order_checkout_reserve` (prenotazione atomica),
  `payment_checkout_attach`, `order_checkout_release` (compensazione),
  `payment_apply_stripe_event`;
- tutte le funzioni con `security definer` e `set search_path = ''`.

**Edge Function** — `supabase/functions/payments-checkout/index.ts` (158 righe)
con `_shared/cors.ts` e `deno.json`. `supabase/config.toml` aggiunge
`[functions.payments-checkout] verify_jwt = true`.

**Webhook** — `frontend-next/src/app/api/public/webhooks/stripe/route.ts`
(`runtime = "nodejs"`), su corpo raw, con: gate `PAYMENTS_ENABLED !== "true"` →
`503`; firma HMAC verificata prima di qualunque parsing; whitelist eventi;
deduplicazione; protezione dagli eventi tardivi.

**Libreria pagamenti** — `frontend-next/src/lib/payments/`:
`stripe-signature.ts`, `stripe-event.ts`, `payment-state.ts`,
`fixed-window-rate-limiter.ts`, ognuna con il proprio file `.test.ts`.

**Adapter** — `frontend-next/src/services/phase7/`: `proposal-service.ts`,
`order-service.ts`, `payment-service.ts`, `shared.ts`, più l'estensione di
`services/types.ts` (+115 righe).

**Documentazione** — `docs/PHASE_7_VERIFICATION.md`,
`docs/superpowers/plans/2026-07-31-phase-7-order-payment-{checkpoint,design}.md`,
aggiornamenti a `ARCHITECTURE.md`, `ENVIRONMENT.md`, `SECURITY.md`,
`ROADMAP_V1.md`, `MIGRATION_PHASE_1_BACKLOG.md`,
`frontend/docs/{BACKEND_CONTRACTS,STATE_MACHINES}.md` e
`frontend-next/.env.example` (10 nuove variabili, fra cui
`PAYMENTS_ENABLED=false`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
`SUPABASE_SERVICE_ROLE_KEY`, gli allowlist di origine e i parametri di rate
limit).

### 4.2 Cosa è escluso

- **Nessuna applicazione remota**: la migrazione Fase 7 non è stata applicata al
  progetto Supabase. L'ultima migrazione remota nota resta
  `20260731120340 catalog_cellar_paths`.
- **Nessun deploy** della Edge Function `payments-checkout`.
- **Nessuna chiamata Stripe**, nessun pagamento reale, nessuna fixture remota.
- **Nessun collegamento UI**: verificato che i tre adapter in `services/phase7/`
  non sono importati da alcuna pagina o componente — importano soltanto il
  proprio `shared.ts`. La verticale non è raggiungibile dall'interfaccia.
- Fuori scope dichiarato: Stripe Connect, payout, KYC, contestazioni operative,
  Fase 8.
- Docker e Deno non disponibili sulla postazione: migrazione non applicata a un
  database locale, runtime Edge non eseguito.

### 4.3 Esito di test / lint / typecheck / build

**Verificato su GitHub Actions** — run #47 (`30637964542`) sull'HEAD `fe3c9723`,
creata 14:17:20Z, conclusa 14:18:13Z, `success` su tutti e tre i job:
`Backend - lint, syntax and tests`, `Frontend - lint, typecheck, test, build`,
`Frontend Next - lint, typecheck, build`. Anche la run #46 (`30637845042`) sul
penultimo HEAD `712912d5` è `success`.

**Dichiarato in `docs/PHASE_7_VERIFICATION.md`** (esecuzione locale, non
riverificata in questa sessione):

| Controllo | Esito dichiarato |
|---|---|
| `bun test` | 10 test passati, 0 falliti |
| `bun run typecheck` | passato |
| `bun run lint` | 0 errori; 23 warning preesistenti fuori dalla verticale |
| `bun run build` | passato, Route Handler webhook incluso |
| `git diff --check` | passato |

Il conteggio "10 test" è **strutturalmente confermato**: 10 casi `it()`
distribuiti su 5 file (`fixed-window-rate-limiter` 1, `payment-state` 4,
`reservation-concurrency` 1, `stripe-event` 2, `stripe-signature` 2).

### 4.4 Scoperta rilevante per il revisore: i test Fase 7 non sono coperti dalla CI

Fatto verificato, non un'opinione:

- la PR #18 aggiunge `"test": "bun test"` a `frontend-next/package.json`;
- il job `frontend-next` di `.github/workflows/ci.yml` esegue **soltanto**
  `lint`, `typecheck`, `build` — **non** `test`;
- la stessa PR modifica `frontend-next/tsconfig.json` da
  `"exclude": ["node_modules"]` a `"exclude": ["node_modules", "**/*.test.ts"]`.

Conseguenza: i 10 test della verticale pagamenti **non vengono eseguiti dalla CI**
e i loro file **non vengono neppure sottoposti a typecheck**. La run verde #47
non è quindi una prova del comportamento di firma HMAC, deduplicazione,
concorrenza e rate limiting: quella prova esiste solo come esecuzione locale
dichiarata. Chi revisiona la Fase 7 dovrebbe decidere se aggiungere lo step
`test` al job `frontend-next` prima di considerare chiuso il checkpoint.

Nessuna correzione è stata applicata: è un rilievo, non un intervento.

## 5. Nota per la zona organizzativa — Fase 7 avviata senza autorizzazione esplicita

Registrata come fatto, senza riscrivere la cronologia e senza alterare la PR.

Il processo del repository richiede, in tre punti distinti e concordanti:

- `CLAUDE.md`: *"Una fase non inizia senza approvazione esplicita preventiva
  registrata nel log organizzativo."*
- `docs/ROADMAP_V1.md` su `main` (`3037bf4`, mergiato con la PR #17): *"la fase
  non può iniziare finché quel rapporto non è integrato e la fase non è
  autorizzata esplicitamente."*
- `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`: *"Nessuna fase successiva senza
  approvazione esplicita."*

Lo stesso `CHANGES.log` presente su `main`, scritto dalla PR #17, indica al punto
3 di NEXT STEPS: *"Eseguire merge o avviare la Fase 7 solo dopo autorizzazioni
esplicite separate."*

Cronologia verificata:

| Ora (UTC) | Evento |
|---|---|
| 2026-07-31 13:37:21 | Merge della PR #17 su `main` |
| 2026-07-31 14:12:59 | Primo commit di Fase 7 (`92b80b3f`) |
| 2026-07-31 14:15:33 | Apertura della draft PR #18 |

La Fase 7 è iniziata **35 minuti e 38 secondi** dopo il merge della PR #17.

Ricerca dell'autorizzazione, esito negativo:

- nessun commento e nessuna review sulla PR #17 o sulla PR #18;
- nessuna voce di autorizzazione alla Fase 7 in `CHANGES.log` (né su `main` né
  sul branch Fase 7), in `CONTESTO_IA/**` o in `docs/**`;
- `CONTESTO_IA/**` non è stato toccato dalla PR #18: il log organizzativo non
  registra affatto l'avvio della fase;
- `docs/superpowers/plans/2026-07-31-phase-7-order-payment-checkpoint.md` elenca
  quattro "gate completati prima del codice" (verifica PR #17, lettura read-only
  della migration history, correzione degli stati post-merge, tentativo di smoke
  Storage) — **nessuno dei quattro è un'autorizzazione**;
- inoltre il quarto gate, lo smoke Storage, **non è stato superato**: risulta non
  avviato. La Fase 7 è quindi iniziata anche con un gate 6d-2a ancora aperto.

**Circostanze attenuanti, registrate per equità.** Il lavoro è stato contenuto in
modo coerente con il rischio: branch dedicato, PR mantenuta **draft**, nessun
merge, nessuna scrittura remota, feature flag `PAYMENTS_ENABLED=false`, nessun
collegamento UI, e la PR dichiara espressamente che *"Le future operazioni remote
richiedono approvazioni esplicite separate"*. L'anomalia riguarda **l'avvio della
fase**, non l'esecuzione di azioni irreversibili: nulla di ciò che è stato fatto
ha toccato dati reali o l'ambiente servito.

Decisioni che spettano alla zona organizzativa, non a questo rapporto:
ratificare a posteriori l'avvio, sospendere la PR #18 fino allo smoke Storage, o
chiuderla e ripartire dopo autorizzazione formale.

## 6. Altro lavoro non documentato in `CHANGES.log`

Nessun branch, PR o commit di lavoro sostanziale è stato trovato oltre a quanto
sopra. Restano questi residui, tutti innocui e nessuno citato in `CHANGES.log`:

1. **Stash locale** `stash@{0}` — `On (no branch): codex-transfer-phase-6d-1-worktree`,
   creato 2026-07-30 14:53:17Z su base `82ae7fc` ("docs: record phase 6d-1 remote
   drift", 2026-07-30 13:47:33Z). 16 file, +969/−49. È una **istantanea superata** del trasferimento
   Fase 6d-1: `main` contiene già una versione più recente di quei file e in più
   `CONTESTO_IA/06_PROMPT_CHAT_OPERATIVE.md`, che nello stash non esiste. Non è
   mai stato pushato. Può essere eliminato, ma la decisione non è di questo
   rapporto.
2. **Branch locale** `codex/automatizza-handoff-agentsmd` → `a857f3b`. Non esiste
   su origin ed è già antenato di `main`: puntatore morto.
3. **Branch locale** `migration/phase-6c-cellar-schema` → `04f0886`, remoto
   `[gone]`. Residuo del squash-merge della PR #11; la PR #12, duplicato draft
   dello stesso branch, fu chiusa senza merge il 2026-07-29 08:44:13Z. Il
   contenuto è su `main` come `20260729180000_cellar_schema.sql`.
4. **Branch remoti di PR già mergiate, mai eliminati** — dodici, fra cui
   `migration/phase-6d-2a-catalog-cellar-paths` (PR #17). Nessuno contiene lavoro
   non integrato.

## 7. Sintesi per chi valuta la Fase 7

| Domanda | Risposta verificata |
|---|---|
| PR #17 è stata mergiata? | Sì, squash su `3037bf4`, 2026-07-31 13:37:21Z |
| Il merge era preceduto da CI verde? | Sì, run #44 sullo stesso SHA `c549392`, verde 89 s prima |
| I gate 6d-2a dichiarati corrispondono al merge? | Sì; SHA-256 di migrazione e griglia confermati byte per byte; l'esito remoto 18/18 resta una dichiarazione documentale non riverificata da Git |
| Smoke Storage `cantina` completato? | **No — resta aperto**, due tentativi falliti registrati, nessun oggetto o utente creato |
| PR #18 è ancora draft? | Sì, `OPEN` + draft, 6 commit, HEAD `fe3c9723`, nessun merge |
| La Fase 7 ha toccato risorse remote? | No: nessun SQL applicato, nessun deploy, nessuna chiamata Stripe |
| CI verde sulla PR #18? | Sì, run #47, ma **non esegue i 10 test** della verticale pagamenti |
| La Fase 7 era autorizzata? | **No** — nessuna autorizzazione esplicita risulta registrata in alcuna fonte del repository |
