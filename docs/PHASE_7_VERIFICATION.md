# Fase 7 — verifica del checkpoint locale

Data: 31 luglio 2026. Branch: `migration/phase-7-order-payment-service`.

## Riconciliazione iniziale

- `origin/main` verificato a `3037bf4f8fa5269895bb01a998d85bb5f629cd34`.
- PR #17 verificata come squash-merge; i tre job GitHub Actions risultavano verdi.
- Migration history Supabase letta senza scritture: ultima versione remota
  `20260731120340 catalog_cellar_paths`.
- Nessun SQL remoto, fixture SQL, deploy Edge Function o chiamata Stripe è stato eseguito.

## Smoke Storage autorizzato

Lo smoke non è stato avviato. La sessione del browser Supabase è stata
reindirizzata alla pagina di login, quindi non era disponibile un percorso Auth
Admin/API per eliminare con certezza i due utenti tecnici al termine. Creare gli
utenti con la sola chiave publishable avrebbe violato il requisito di cleanup
totale. Non sono stati creati utenti, oggetti o URL firmati e non è stata fatta
alcuna serie di retry; lo stato del precedente limite Auth non è quindi stato
misurato.

Per riprendere: autenticare la dashboard, eseguire una singola registrazione e,
se risponde `429`, fermarsi. Se riesce, completare upload PNG nel bucket privato
`cantina`, lettura owner, signed URL, rifiuto della lettura diretta con il secondo
JWT, quindi eliminare oggetto e utenti via API amministrativa.

## Verifiche locali

| Controllo | Esito |
|---|---|
| `bun test` | 10 test passati, 0 falliti |
| `bun run typecheck` | passato |
| `bun run lint` | 0 errori; 23 warning preesistenti fuori dalla verticale |
| `bun run build` | passato; Route Handler webhook incluso |
| `git diff --check` | passato |

Docker e Deno non sono disponibili in questa postazione, quindi la migrazione
non è stata applicata a un database locale e la Edge Function non è stata
eseguita. Il deploy successivo deve prima validare la migrazione su un ambiente
isolato, controllare advisor RLS/performance, verificare i grant Data API e solo
poi configurare segreti e Stripe test mode.

## Gate prima di qualunque ambiente remoto

1. Approvazione esplicita separata per applicare la migrazione SQL.
2. Verifica che la versione assegnata dal server coincida con il filename locale
   e nuova lettura della migration history.
3. Approvazione esplicita separata per distribuire `payments-checkout`.
4. `PAYMENTS_ENABLED=false` durante migrazione, deploy e smoke tecnico.
5. Stripe esclusivamente in test mode; nessun pagamento reale e nessun payout.

---

# Chiusura locale — 2 agosto 2026

Secondo intervento sul branch, dopo la riconciliazione e le due proposte.
Nove commit, da `b463bfb` a `2ce1186`, sopra `cd7b1a0`.

## File toccati, per passo

| Passo | Commit | File | Righe |
|---|---|---|---|
| 1 — proposte pendenti | `b463bfb` | `CHANGES.log`, `PHASE_7_COVERAGE_PROPOSAL.md`, `PHASE_7_PAYMENT_PROVIDER_PROPOSAL.md` | +612 −3 |
| 1b — correzione | `4d82fa4` | le due proposte | −3 |
| 2 — residuo e manifest | `a821878` | `CHANGES.log`, `CONTESTO_IA/context-manifest.json` | +17 −14 |
| 3 — interfaccia | `a0e0887` | `frontend-next/src/services/types.ts` | +85 |
| 4 — schema | `d0df7f1` | `20260731135455_phase_7_order_payment_service.sql` | +133 −58 |
| 5 — Edge Function | `d90d668` | `types.ts`, `_shared/payment-provider.ts`, `payments-checkout/index.ts`, `payments-checkout/providers/stripe.ts` | +246 −56 |
| 6 — codice morto e traduttore | `aabe1ab` | 8 file sotto `frontend-next/src` | +186 −132 |
| 7 — CI | `c2ae515` | `ci.yml`, `bun.lock`, `package.json`, `tsconfig.json` | +28 −2 |
| 8 — griglia SQL | `2ce1186` | `supabase/tests/7_ordini_pagamenti.sql`, `README.md` | +520 |

`4d82fa4` corregge un difetto introdotto da `b463bfb`: le due proposte erano
state committate con due marcatori di sintassi utensile in coda al file.

## File rimossi e rinominati

Rimossi, dopo aver riconfermato che nessun file li importava fuori dal proprio
test:

- `frontend-next/src/lib/payments/fixed-window-rate-limiter.ts` e il suo test
- `frontend-next/src/lib/payments/reservation-concurrency.test.ts`, che non
  importava nulla dal progetto e verificava una funzione definita al suo interno

Rinominati nello schema, in posto e senza migrazione di patch, perché la
migrazione non è mai stata applicata ad alcun database:

| Prima | Dopo |
|---|---|
| `stripe_webhook_events` | `payment_provider_events`, chiave `(provider, event_id)` |
| `payments.stripe_session_id` | `payments.provider_session_id` |
| `payments.stripe_payment_intent_id` | `payments.provider_intent_id` |
| `payments.stripe_event_created_at` | `payments.provider_event_at` |
| `payment_apply_stripe_event` | `payment_apply_provider_event` |
| — | `payments.provider`, `public.payment_outcome`, `payment_provider_events.provider_event_type` |

## Esiti ai checkpoint

Ogni riga è stata eseguita, non dedotta.

| Passo | typecheck | lint | test | build |
|---|---|---|---|---|
| 3 | 0 | 0 errori, 23 warning | — | 0 |
| 5 | 0 | 0 errori, 23 warning | — | 0 |
| 6 | 0 | 0 errori, 23 warning | 12/12 | 0 |
| 7 | 0 | 0 errori, 23 warning | 12/12 | 0 |
| 8 | 0 | — | 12/12 | — |

I 23 warning sono gli stessi preesistenti fuori dalla verticale, invariati.

## Stato dei test locali

Il numero da guardare non è quanti passano ma quanti toccano codice spedito.

| | Prima | Dopo |
|---|---|---|
| Test totali | 10 | 12 |
| Che esercitano codice di produzione | 4 | 12 |
| Che esercitano una reimplementazione | 6 | 0 |
| File di test | 5 | 3 |

I 6 test che non coprivano nulla verificavano copie TypeScript di logica che
vive in Postgres. Una di quelle copie **era già divergente**: da `expired`, un
evento `completed` non pagato dava `processing` in TypeScript e nessun
cambiamento in SQL.

Cinque dei nuovi casi leggono il file di migrazione vero e falliscono se le due
implementazioni tornano a divergere. Sono stati verificati **in rosso**, non
solo in verde:

- rinominando il ramo `p_outcome = 'authorized'` della RPC → 2 casi falliscono;
- aggiungendo un valore all'enum `public.payment_outcome` → 1 caso fallisce;
- con un errore di tipo piantato in un file di test, `bun run typecheck` esce 2
  dove prima non vedeva nulla.

Dopo ogni prova la migrazione è stata ripristinata e confrontata con
`git diff`: identica.

## Copertura CI

`bun test` con bun 1.3.14: esce **1** se non trova alcun file di test, ma esce
**0** se i file esistono e non contengono casi. Verificato, non assunto. Il
verde da solo non dimostra quindi che i test siano stati eseguiti, e lo step CI
confronta il numero di test superati con una soglia (`MIN_TESTS`) invece di
fidarsi dell'exit code.

## Confine verso il fornitore

Fuori da `supabase/functions/payments-checkout/providers/stripe.ts` restano due
sole occorrenze di Stripe nella Edge Function: la riga di `import` e la riga di
costruzione dell'adapter. Nessun `api.stripe.com`, nessuna variabile `STRIPE_`.
La migrazione non contiene più alcuna occorrenza della stringa `stripe`, in
nessuna forma.

## Invarianti riverificati dopo le modifiche

- Funzioni `SECURITY DEFINER` con `set search_path = ''`: **11 su 11**, come
  prima del rinominio.
- `ceduta_at`: la migrazione di Fase 7 non lo scrive in nessun punto. L'unica
  occorrenza è una lettura in guardia dentro `order_checkout_reserve`. Il solo
  scrittore resta il trigger `listings_marca_bottiglia_ceduta`
  (`20260730140948_…sql:244-263`), che scatta all'ingresso di
  `listings.stato = 'venduto'`.
- Prezzo, valuta e proprietario restano risolti server-side; la RPC continua a
  riconfrontare importo, valuta e ordine con la riga scritta alla prenotazione.

## Ciò che NON è stato fatto, e resta gate separato

Nessuna di queste azioni è stata eseguita in questo intervento, e nessuna è
autorizzata da esso:

1. **Nessun SQL applicato al remoto.** La migrazione di Fase 7 non è stata
   applicata a nessun database, né remoto né locale.
2. **Nessuna verifica di esecuzione del SQL.** Docker, Deno, `psql` e la CLI
   Supabase non sono disponibili in postazione: la migrazione riscritta non è
   stata eseguita né controllata sintatticamente da un motore Postgres. È
   revisione a vista.
3. **La griglia `7_ordini_pagamenti.sql` non è mai stata eseguita.** I 16 esiti
   attesi derivano dal testo del SQL, non da un'esecuzione.
4. **Nessuna Edge Function distribuita.** Il parse dei tre file Deno è stato
   fatto con `tsc --noResolve`, che prova la sintassi e non il runtime.
5. **Nessuna chiamata Stripe**, in test mode o altro. Nessun webhook registrato
   presso il fornitore: il percorso pubblico del Route Handler non è stato
   cambiato proprio per non toccare un URL che un giorno sarà registrato.
6. **Nessun merge, nessuna PR segnata pronta per revisione.** La PR #18 resta
   draft e resta priva dell'autorizzazione di avvio fase.
7. **Lo smoke Storage 6d-2a resta aperto**, invariato rispetto a sopra.
8. **Nessun job CI per le griglie SQL.** Il blocco `do` finale prepara il
   terreno; il job non esiste.

---

# Deriva pre-esistente: la storia migrazioni non ricostruisce il database

Data: 2 agosto 2026. Scoperta creando il branch Supabase `phase-7-migration-verify`
(`ccnufawxtaykgjftvauc`, genitore `pijnmcllmfgjmgsvtcej`), che è finito in
`MIGRATIONS_FAILED` **prima** di arrivare alla migrazione di Fase 7.

Questo debito è indipendente dalla Fase 7 e la precede di giorni.

## L'errore riportato non è la causa

L'errore visibile è:

```
ERROR: function public.bottiglia_apri(uuid, text) does not exist
```

sollevato da `20260729234500_security_invariants_followup.sql:35`. Ma
`bottiglia_apri` non ha niente che non va:

- esiste sul progetto reale con la firma esatta `(p_bottle_unit_id uuid, p_nota text)`,
  `security definer`, `search_path=""`;
- è creata da tre file tracciati: `20260729230000:341`, `20260730140948:30`,
  `20260730162046:1`.

Non è deriva non tracciata. È solo il primo statement che tocca un oggetto assente.

## La causa: sette migrazioni su quattordici sono registrate vuote

`supabase_migrations.schema_migrations` conserva in `statements` il SQL di ogni
versione. Un branch replica **quella colonna**, non i file del repository. Sette
righe su quattordici hanno `statements` vuoto: la versione risulta applicata e
non viene eseguito nulla.

| Versione | Nome | Byte nel file | Caratteri registrati |
|---|---|---|---|
| 20260728000545 | auth_profiles_roles | 5891 | 5838 |
| 20260728073915 | oauth_profile_without_dob | 3877 | 3845 |
| 20260728193937 | listings_catalog | 21840 | **0** |
| 20260728194500 | seed_wines_catalog | 2707 | **0** |
| 20260729112500 | listings_write | 22005 | **0** |
| 20260729180000 | cellar_schema | 27402 | **0** |
| 20260729180500 | seed_wine_meta | 7999 | **0** |
| 20260729210000 | listing_crea_da_bottiglia | 11704 | **0** |
| 20260729230000 | security_invariants | 47896 | **0** |
| 20260729234500 | security_invariants_followup | 24548 | 24505 |
| 20260729235500 | security_helper_invoker | 2005 | 1532 |
| 20260730140948 | security_invariants_remote_drift_repair | 9615 | 9615 |
| 20260730162046 | fix_6d1_bottle_message_encoding | 4410 | 4390 |
| 20260731120340 | catalog_cellar_paths | 19712 | 19692 |

**141 553 byte di DDL sono registrati come applicati e conservati come niente.**

Le differenze nelle righe non vuote sono intestazioni di commento rimosse da
`apply_migration` più il newline finale. Verificato sul caso più sospetto,
`20260729235500` (473 caratteri di scarto): il contenuto registrato è identico al
file meno le prime 8 righe di commento. Le sette migrazioni registrate non sono
quindi da rifare — solo le sette vuote.

## Prova diretta sul branch, non deduzione

Interrogando il catalogo del branch fallito:

- `schema_migrations` contiene nove versioni, da `20260728000545` a `20260729230000`;
- le relazioni in `public` sono **due**: `profiles`, `user_roles`;
- le funzioni in `public` sono **due**: `handle_new_user`, `has_role`.

Le sei versioni vuote hanno segnato il proprio numero senza creare nulla. Mancano
`wines`, `bottle_units`, `listings`, `cellar_environments`, `cellar_modules`,
`cellar_slots`, i tre enum, `slugifica`, `listing_crea`, `listing_pubblica`,
`listing_sospendi`, `listing_scadi`, `utente_maggiorenne`, `bottiglia_apri`,
`bottiglia_cancella` e i due trigger di annuncio.

Correggere il solo `REVOKE` di riga 35 sposterebbe l'errore alla riga 40
(`bottiglia_cancella`), poi a `listing_crea`, poi a ogni tabella toccata dal
follow-up. **Non esiste un primo errore da correggere: metà della storia è in bianco.**

## Seconda deriva, distinta: `rls_auto_enable` non è tracciata da nessuna parte

- `public.rls_auto_enable()` ritorna `event_trigger`, proprietario `postgres`,
  `security definer`, `search_path=pg_catalog`. Il corpo scorre
  `pg_event_trigger_ddl_commands()` e abilita RLS sulle tabelle nuove in `public`.
- È agganciata all'event trigger `ensure_rls` su `ddl_command_end`, proprietario
  `postgres`. Tutti gli altri sei event trigger del progetto sono di
  `supabase_admin`, cioè di Supabase.
- **Nessun file di migrazione la crea.** L'unica menzione in tutto il repository è
  `20260729234500:86`, che le revoca `execute`.

Quindi, anche riparata la prima deriva, la replica fallirebbe di nuovo a quella
riga. Questa è deriva vera, dello stesso genere riparato in parte dalla
`20260730140948`, che però non la copriva.

**Effetto sulla Fase 7:** nessuno. La migrazione di Fase 7 abilita RLS
esplicitamente su tutte e sei le tabelle che crea (righe 20, 335–339), quindi non
dipende da `ensure_rls`. L'effetto è sul metodo: un branch senza `ensure_rls` non
è un proxy fedele della produzione per qualunque migrazione che crei una tabella
senza `enable row level security` esplicito.

## Conseguenza sulla verifica della Fase 7

La migrazione di Fase 7 **non è applicabile oggi** sul branch: referenzia
`listings`, `bottle_units`, `profiles` e gli enum, che lì non esistono. Il piano
«far girare la Fase 7 su un Postgres qualsiasi» resta valido ma è ora subordinato
alla riparazione della storia.

## Ciò che NON è stato fatto in questa diagnosi

- Nessuna migrazione di correzione scritta: la fermata obbligatoria la vincola a
  revisione preventiva.
- Nessuna scrittura sul progetto reale né sul branch: solo `select` di catalogo.
- Il branch `phase-7-migration-verify` è stato lasciato in `MIGRATIONS_FAILED`,
  non cancellato e non ricreato.

---

# Smoke Storage — perché il 429, e il setup alternativo

## La causa del 429, verificata sui documenti e non dedotta

Il limite che ha respinto il secondo tentativo è quello di invio email del
servizio SMTP incorporato. I documenti Supabase lo descrivono così, per gli
endpoint `/auth/v1/signup`, `/auth/v1/recover` e `/auth/v1/user`:

- l'ambito è **«Sum of combined requests project-wide»**, non per IP e non per utente;
- la configurabilità è **«Custom SMTP Only»**, con la nota «You can only change
  this with a custom SMTP setup».

Da qui le tre risposte alla domanda posta:

1. **Il passaggio a Pro non ha cambiato questo limite.** Non è legato al piano ma
   alla presenza di un SMTP proprio. Il piano dell'organizzazione è `pro`,
   verificato, e resta irrilevante per questo limite.
2. **Non è per IP né per utente**, quindi cambiare rete o indirizzo non aiuta.
3. Aspettare funziona ma è a ore, e il primo tentativo aveva già consumato quota
   fallendo per il TLD `.invalid`.

## Perché le griglie SQL non hanno mai visto questo limite

`6d-2a_catalog_cellar_paths.sql:117` crea gli utenti con `insert into auth.users`
diretto e li elimina con `delete from auth.users` (righe 330, 345). Non passa
dall'API HTTP di Auth, quindi non incontra alcun rate limit. Lo smoke Storage
invece passava da `signUp` perché servono JWT veri per esercitare le policy dello
Storage — ed è esattamente lì che ha preso il 429.

## Setup alternativo proposto, prima di un terzo tentativo

Non usare `signUp`. Usare l'**Auth Admin API** con la chiave `service_role`:

- `POST /auth/v1/admin/users` con `email_confirm: true` crea un utente già
  confermato. Non essendoci email di conferma da spedire, il limite dell'SMTP
  incorporato non viene toccato e il 429 non può ripresentarsi.
- La pulizia è `DELETE /auth/v1/admin/users/{id}`: garantita e scriptabile, senza
  dipendere da una sessione dashboard attiva. È precisamente il requisito che
  aveva bloccato il terzo tentativo.
- Il JWT per esercitare Storage si ottiene poi con
  `POST /auth/v1/token?grant_type=password`, che non spedisce email.
- Indirizzi: `@example.com`, non `@example.invalid`. `.invalid` non è un TLD
  valido per il validatore di Auth ed è ciò che ha fatto fallire il primo
  tentativo.

Da confermare alla prima esecuzione, perché non è stato provato: che
`admin/users` non spedisca email è comportamento atteso dell'endpoint, non un
fatto misurato qui. Se comparisse un 429 anche per quella via, l'ipotesi sarebbe
da rifare.

Resta il vincolo già noto: la chiave `service_role` non va incollata in chat né
committata, e lo smoke va eseguito in una sessione dove sia già disponibile.
