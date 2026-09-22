# Architettura, regole permanenti e debiti

## Mappa del repository

```text
frontend/       React 19 + TanStack Start — versione corrente servita
backend/        FastAPI + MongoDB — backend corrente, transitorio
frontend-next/  Next.js App Router — frontend target
supabase/       migrazioni PostgreSQL, RLS, test e query — backend target
docs/           roadmap, ADR, sicurezza, ambiente, sviluppo e report
.github/        CI indipendente per frontend, frontend-next e backend
CONTESTO_IA/    handoff sintetico per nuove IA/chat
```

## Direzione architetturale

- Il prodotto target è Next.js + TypeScript + Supabase/PostgreSQL.
- La migrazione conserva l'investimento visuale e comportamentale del
  frontend corrente.
- Le implementazioni reali sono adapter dietro le interfacce in
  `frontend-next/src/services/types.ts`.
- Le 8 slice dello store restano i confini di dominio.
- Auth Supabase reale e switcher demo Guest/User/Admin coesistono
  intenzionalmente finché tutti i domini non sono migrati.
- Il profilo di signup viene creato dal trigger PostgreSQL, non da un insert
  client.
- Redirect OAuth e magic-link usano l'origine corrente, che deve comunque
  essere autorizzata nel progetto Supabase.

## Regole di migrazione

1. Una fase usa branch e PR dedicati; non portare due fasi avanti in parallelo
   sulla stessa area.
2. L'ammissione di una nuova fase o funzionalità è una decisione organizzativa
   sul perimetro. Non è un gate di conferma per i singoli comandi tecnici.
3. Nessuna nuova funzionalità durante la migrazione, salvo quelle ammesse
   esplicitamente per nome; l'obiettivo ordinario è la parità.
4. Ogni dominio migrato ha un solo writer autorevole.
5. `frontend/` + `backend/` restano serviti fino alla Fase 13. Il cutover era la
   Fase 11 fino all'11 agosto 2026 e la Fase 12 fino al 16 agosto 2026; oggi la
   Fase 12 è Club/Community e la Fase 13 è Cutover.
6. Un agente dotato degli strumenti necessari completa autonomamente il ciclo
   `branch → implementazione → test → commit → push → PR → CI → fix CI → merge
   → verifica post-merge`, anche quando la PR contiene migrazioni. Si lavora
   fuori da `main`, il metodo ordinario è squash e il merge richiede i controlli
   pertinenti verdi e l'head esatto `MERGEABLE`/`CLEAN`. Force push su `main`,
   bypass deliberato della CI, distruzione di lavoro altrui e merge con controlli
   rilevanti falliti restano vietati.
7. Prima del merge, `CHANGES.log` deve descrivere lo stato che la PR produrrà.
   `CLAUDE.md` cambia solo quando cambia una regola costituzionale; questa
   cartella cambia quando serve memoria durevole.
8. Il lavoro Supabase richiesto dal task è tecnico e autonomo: migrazioni,
   schema, RPC, trigger, RLS, Storage, Edge Function, fixture necessarie e
   verifiche remote. Prima di ogni scrittura si verificano progetto, ref,
   ambiente e stato remoto; si opera migration-first e non si disabilita RLS
   globalmente.
9. Le fixture tecniche devono essere necessarie, minime e isolate. La pulizia va
   garantita anche sul percorso d'errore; i residui vanno riletti e riportati.
   Non si cancellano o riscrivono arbitrariamente dati reali.
10. Dopo `apply_migration` via API/MCP, allineare il file locale alla versione
    assegnata dal server e verificare la migration history e gli oggetti
    effettivi. Il merge non prova l'applicazione: l'integrazione può non partire
    e una corsa successiva può distribuire un backlog.
11. Un file di migrazione già pushato o distribuito almeno una volta non si
    modifica più in place: ogni correzione è un nuovo file con timestamp più
    recente. Un ambiente che ha già registrato una versione non ne riesegue il
    testo modificato. È successo sulla PR #19, dove l'anteprima eseguì la prima
    bozza della migrazione di Fase 7b e non riprese la riscrittura successiva.

La deroga del 16 agosto 2026 che limitava il merge autonomo alle PR senza file
sotto `supabase/migrations/` resta un fatto storico nelle voci PR #47–#51, ma è
stata sostituita dalla policy corrente sopra.

## Regole di tipo che hanno già rotto il denaro una volta

- **Mai assegnare un `case` nudo a una colonna enum.** Un letterale isolato ha tipo
  `unknown` e si lascia coercire dalla colonna di destinazione; un `case` fra due
  letterali si risolve a **`text`**, e da `text` a un enum non esiste conversione
  implicita: l'istruzione non compila e solleva `42804`. Il cast va su **entrambi** i
  rami di ogni `case`, non solo sul primo, così il tipo è l'enum per costruzione e non
  per una regola di risoluzione che un letterale in più potrebbe spostare di nuovo.
- **Il nome dell'enum si legge da `pg_type`, non si assume**, e si verifica che le
  etichette esistano: un cast verso un'etichetta inesistente è un `22P02` a runtime,
  cioè lo stesso difetto spostato.
- Perché è una regola e non un consiglio: la Fase 7c ha portato in produzione
  esattamente questo errore in `ordine_contestazione_risolvi`, e la conseguenza era
  che **nessuna contestazione poteva chiudersi a favore del venditore e i suoi fondi
  restavano bloccati per sempre**. Corretto dalla Fase 7f — vedi
  [`../docs/PHASE_7F_FIX_VERIFICATION.md`](../docs/PHASE_7F_FIX_VERIFICATION.md).
- Il difetto era invisibile a lettura e a chiamata parziale, perché un ramo su tre
  usciva prima di quell'`update`. L'ha trovato una griglia eseguita, non una revisione.

## Confini di fiducia

- Il frontend non assegna ruoli, non conferma pagamenti e non decide prezzo,
  valuta o proprietario.
- Identità, ownership e permessi sono verificati lato server/database.
- Un pagamento è affidabile solo da `payment_status=paid` e da webhook Stripe
  firmato e deduplicato.
- CORS e redirect usano allowlist di origin complete.
- Dati privati, ordini e conversazioni sono leggibili solo dal proprietario o
  da ruoli autorizzati.
- Provider auth/AI/payment sono dietro interfacce sostituibili e testabili con
  fake.

## Regole Supabase introdotte dalla 6d-1

- Nessun `SELECT` di tabella intera a ruoli che possono raggiungere righe non
  proprie.
- Le letture pubbliche passano da viste a elenco chiuso di colonne.
- Le colonne con regole di dominio non sono aggiornabili direttamente dal
  client.
- Gli invarianti fra tabelle sono protetti anche da trigger, così valgono
  anche per scrittori privilegiati.
- `anon` non deve poter eseguire funzioni `SECURITY DEFINER`.
- Le RPC applicative verificano `auth.uid()`, proprietà, stato e usano un
  `search_path` sicuro.
- Una bottiglia aperta, consumata, cancellata o ceduta non è vendibile.
- Una bottiglia con annuncio non terminale non può essere aperta o rimossa.
- Una vendita pubblicata richiede una data di nascita dichiarata compatibile
  con la maggiore età.

## Eccezione accettata: viste `SECURITY DEFINER` (lint Supabase 0010)

Registrata dopo il security audit del 17 settembre 2026 (PR #119). Il linter
Supabase segnala come ERROR (lint 0010, `security_definer_view`) le viste
`public.*` che girano con i privilegi del proprietario. Per Vinea sono
**intenzionali e corrette** e **non vanno convertite a
`security_invoker = on`**: sono il meccanismo con cui dati curati arrivano ad
`anon` e ad `authenticated`, che giustamente non hanno grant sulle tabelle base.
Convertirle romperebbe il marketplace pubblico, i club e le code di
moderazione. Il filtro vive nel loro `WHERE` e nel loro elenco chiuso di
colonne: per esempio `moderation_report_queue` filtra su
`user_roles.role = 'admin'`, `my_reports` su `reporter_id = auth.uid()`,
`public_listings` su `stato = 'attivo'` senza colonne PII.

Elenco chiuso delle sedici viste accettate al 18 settembre 2026, tutte di
proprietà di `postgres`:

- pubbliche: `public_listings`, `public_clubs`, `public_club_posts`,
  `public_club_post_risposte`, `public_marketplace_config`,
  `public_packaging_options`, `wine_price_history`;
- del proprietario: `my_reports`, `my_report_events`, `my_certifications`,
  `my_listing_moderation`, `my_sommelier_messages`;
- di moderazione: `moderation_report_queue`, `moderation_report_events`,
  `moderation_dispute_queue`, `moderation_audit_log`.

Regola: una nuova vista `public_*`, `my_*` o `moderation_*` con
`security_invoker = off` deve avere un `WHERE` di filtro esplicito (stato
pubblico, `auth.uid()` o ruolo verificato) e un elenco chiuso di colonne, e va
aggiunta a questo elenco nella stessa PR. Una vista che compare nel lint 0010 e
non è in questo elenco è un difetto da esaminare, non un'eccezione.

## Grant di `public.profiles` dopo l'hardening del 18 settembre 2026

Migrazione `20260918090918_security_hardening_grants.sql` (PR #119):
`anon` non ha alcun privilegio su `public.profiles`; `authenticated` ha
`SELECT` di tabella e `UPDATE` **di colonna** sulle otto colonne della Fase 9b
(`username, bio, citta, provincia, esperienza, avatar_url, dob, obiettivi`);
`INSERT`/`DELETE` non esistono per i client, perché la riga nasce dal trigger
`on_auth_user_created`. La tabella ha `FORCE ROW LEVEL SECURITY`, innocuo per
`handle_new_user()` perché il proprietario `postgres` ha `rolbypassrls`. Non
sostituire mai il grant di colonna con un `grant update on public.profiles`:
renderebbe scrivibili dal client `stato_utente` e `provvedimenti`, lasciando il
solo trigger `profiles_stato_utente_guard` a fermare un utente sospeso.
`public_marketplace_config` è in sola lettura per `anon` e `authenticated`.

## Step-up auth sulle porte che fanno uscire denaro (18 settembre 2026)

Le sessioni restano lunghe per scelta; la contropartita, decisa dalla chat
organizzativa, è un'autenticazione **recente** (15 minuti) per il denaro che
esce verso l'utente. Migrazione `20260918102406_step_up_auth_prelievi.sql`.

- **Regola.** Ogni porta che fa uscire denaro verso l'utente chiama
  `perform private.autenticazione_recente_richiedi(900);` come **prima
  istruzione dopo il ramo di replay** e prima di rate limit, blocchi e
  scritture. Ogni nuova porta di questo tipo deve farlo nella stessa PR che la
  crea. Il replay di una richiesta già accettata non chiede riautenticazione:
  non crea nulla e ha la sua idempotenza.
- **Ambito deciso, non allargabile senza decisione.** Protetta oggi solo
  `public.balance_prelievo_richiedi`. Non protette per decisione di prodotto:
  `order_checkout_reserve_saldo` (merce all'indirizzo del compratore; costo di
  conversione) e `balance_prelievo_annulla` (annullare non è dannoso). Cambio
  password ed email: interruttori della dashboard Auth, non codice.
- **Come si misura.** La claim `session_id` del JWT (verificata con un token
  reale) individua la riga di `auth.sessions`; conta
  `greatest(sessions.created_at, max(mfa_amr_claims.updated_at))`. Il refresh
  sposta `refreshed_at`/`updated_at`, non quei due (misurato). Mai
  `max(created_at)` su tutte le sessioni dell'utente: un login fresco sul
  telefono farebbe passare una sessione vecchia rubata altrove. Fail-closed se
  manca la claim o la riga (sessione chiusa con logout: 403 misurato).
- **Risposta.** `raise sqlstate 'PGRST'` con `code = reauth_required` e
  `status 403`, non 401 (un 401 innesca refresh/logout nei client). PostgREST
  esige la chiave `headers` nel DETAIL anche vuota: senza, il client riceve un
  `500 PGRST121` (misurato).
- **Client.** `frontend-next` apre `ConfermaIdentita` e ripete la stessa
  chiamata con la stessa chiave di idempotenza. I metodi si leggono dalle
  identità (`getUser()`): identità `email` → password; `google`/`facebook` →
  nuovo giro OAuth con rientro su `/account` (l'importo va reinserito). Un
  account nato con Google non vede mai un campo password.
- **Limite noto.** Un account con identità `email` ma senza password (nato da
  magic link) vede il campo password e deve usare «password dimenticata». Un
  account Google che ha impostato una password Vinea ha solo l'identità
  `google` e conferma con Google.

## Regole di denaro introdotte dalla 7b

- La commissione è calcolata lato server e **congelata sull'ordine** insieme ai
  tre parametri che l'hanno prodotta. Il client non la propone mai, e cambiare
  `marketplace_config` dopo non tocca gli ordini già nati.
- La formula sta in un posto solo, `private.marketplace_totale_cents`, usata
  tanto dalla prenotazione quanto dalla vista di riconciliazione. Due copie da
  tenere allineate sarebbero due copie che divergono.
- L'arrotondamento del totale è sempre per eccesso: per difetto il margine
  scenderebbe sotto l'obiettivo di un centesimo.
- I fondi restano alla piattaforma perché non vengono mossi: l'addebito non
  porta `transfer_data` né `on_behalf_of`, e il Transfer nasce solo al rilascio,
  per il solo prezzo del venditore.
- La fee davvero trattenuta si misura e basta: nessun percorso di rilascio fondi
  la legge, e lo scarto rispetto alla fee di riferimento non è compensato da
  alcun automatismo.
- `charges_enabled`, `payouts_enabled` e il ruolo `seller_enabled` che ne deriva
  si scrivono solo applicando un evento firmato del fornitore, mai su richiesta
  del venditore. Il vincolo sta in un trigger, così vale anche per
  `service_role`.

## Decisioni economiche chiuse dalla 7d (vincolanti, PR #22)

La 7d non ha scritto SQL. Ha chiuso decisioni che vincolano ciò che le fasi
successive possono costruire.

- **1a — l'auto-rilascio lo chiama uno scheduler esterno (GitHub Actions), non
  `pg_cron`.** `pg_cron` e `pg_net` sono esclusi, non rinviati: metterebbero
  service role key e job token in chiaro in `cron.job`, e `pg_net` è
  fire-and-forget, quindi `cron.job_run_details` registra `succeeded` anche su
  `401`/`503`. Riproporli richiede di riaprire la decisione. La 1d ha confermato
  `0 */6 * * *` e `PAYOUTS_BATCH_LIMIT` 50; un workflow schedulato gira solo dal
  branch di default, quindi il file dovrà stare su `main`.
- **1e — lo scheduler si accende e si verifica prima di `PAYMENTS_ENABLED`, mai
  dopo.** Invertito, la prima esecuzione erediterebbe un backlog storico di
  ordini già scaduti.
- **La credenziale del workflow è legacy anon JWT più `PAYOUTS_JOB_TOKEN`, non
  la service role key.** `payouts-release` costruisce il client privilegiato
  dalle variabili d'ambiente della function, quindi il JWT del chiamante serve
  solo ad attraversare il gateway e non porta autorità sul database. Finché
  `verify_jwt=true`, una chiave `sb_publishable_...` richiede una decisione
  separata sulla configurazione del gateway.
- **1c è chiusa:** notifiche native di fallimento e rotazione del job token sono
  responsabilità di Enrico / `enricopuntog-cpu`; rotazione ogni 90 giorni e
  immediata dopo sospetta esposizione. Nessuna integrazione esterna in 7g.
- **3a — la voce «protezione» (3%) esce dal modello Supabase**; in `frontend/`
  resta fino al cutover di Fase 13, dove la sua rimozione va scritta nella lista
  di cutover o nessuno se ne ricorderà.
- **2c — un tetto ai tentativi di riconciliazione della fee non deve mai essere
  un valore nuovo di `public.payment_stato`.** `payout_prepara`,
  `ordine_auto_rilascio_esegui` e `conferma_ricezione` filtrano tutti su
  `payments.stato = 'paid'`: un valore nuovo congelerebbe i fondi del venditore
  perché la piattaforma non riesce a leggere il proprio costo, e cancellerebbe le
  proprie prove, dato che `payments_fee_da_riconciliare_idx` filtra anch'esso
  `stato = 'paid'`. Il marcatore va derivato da un contatore `fee_tentativi >= N`
  e non deve entrare in alcun predicato di rilascio. Design approvato — opzione A,
  colonne contatore su `payments`, tetto a 5 — **schema non scritto**.
- **`spedizione` non si decide** finché la 3e non ha risposta commerciale: un
  importo unico o due dal partner logistico. Progettare prima è scommettere.

## Debiti e decisioni ancora aperte

### Bloccanti prima di denaro reale o beta pubblica

- Stripe Connect, payout e onboarding venditore: merged con la Fase 7b e
  verificati sul progetto reale dopo la corsa d'integrazione — schema a ledger e
  tre Edge Function `ACTIVE` — ma mai percorsi da un ordine e mai provati contro
  Stripe, nemmeno
  in test mode. Restano fuori il KYC oltre l'onboarding ospitato,
  l'interfaccia di gestione delle contestazioni e il recupero automatico di un
  rimborso successivo a un Transfer già creato;
- schedulazione dell'auto-rilascio: **integrata dalla 7g** con la PR #26 al
  merge squash `f9c53e0`, con sanità oltre 24 ore e modalità read-only quando
  `PAYMENTS_ENABLED=false`. Restano aperti configurazione di variabile e secret,
  verifica delle notifiche native e prima invocazione reale con pagamenti spenti;
- verifica legale italiana/UE su vendita di alcolici, età, privacy e modello
  marketplace;
- rate limiting condiviso per RPC/Edge Functions;
- threat model e revisione indipendente;
- gestione centralizzata segreti, osservabilità, alert;
- CSP: dalla PR #119 gli header di sicurezza e HSTS con `includeSubDomains;
  preload` sono in `netlify.toml` e la CSP è in **Report-Only**. Resta aperta la
  CSP enforcing con nonce via middleware, da scrivere dopo aver letto le
  violazioni raccolte in produzione;
- backup e restore: prova isolata completata il 19 settembre; backup B2
  cifrato operativo dal 22 settembre, con download S3 e SHA-256 verificati
  senza decrypt. Resta la prova completa di decrypt/restore isolato con Enrico
  e la chiave privata `age` offline. HARDENING FUTURO non bloccante: ruotare
  la B2 Application Key con least privilege dopo tale prova, rimuovendo
  `bypassGovernance` e `deleteFiles`;
- Leaked Password Protection in Supabase Auth (azione manuale da dashboard);
  valutare le passkey.

### Debiti della migrazione

- trasferimento della proprietà della bottiglia al compratore: chiuso dalla
  Fase 7, che al pagamento confermato crea l'unità privata del compratore in
  `orders.buyer_bottle_unit_id` e conserva quella storica del venditore;
- scheduler affidabile per scadenza annunci;
- catalogo condiviso: chiuso dalla Fase 6d-2a, che ha introdotto
  `wines.provenienza` e `creato_da` e ha tolto ai client la vecchia via
  `listing_crea`; resta da sorvegliare la moderazione della provenienza;
- automazione delle prove remote 33/33 e 11/11, oggi eseguite manualmente;
- automazione dei test Supabase in CI con database effimero: nessun job copre
  ancora `supabase/**`, e le griglie SQL si eseguono a mano. **La 7e ha misurato
  quanto costa:** la griglia 7c, versionata e mai eseguita, era rotta in quattro
  punti e non poteva committare in nessuno scenario; nessuno dei quattro difetti si
  vedeva leggendo il file. Una griglia versionata e mai eseguita non è una prova.
  Restano senza esito la griglia della Fase 7 (16 casi), quella della 7b (23) e
  quella della 6d-2a (18);
- test frontend per `frontend-next/`: esistono e sono imposti in CI da
  `MIN_TESTS`; la Fase 8 aggiunge contratti, adapter, mock e Realtime, mentre le
  pagine sono state verificate con uno smoke locale nel browser;
- revisione delle viste proprietario/security barrier prima del cutover;
- valutazione degli indici dopo traffico rappresentativo;
- rate limiting delle RPC Supabase;
- formattazione `formatEUR` che arrotonda alla visualizzazione gli importi con
  centesimi.

### Decisioni prodotto/infrastruttura non chiuse

- hosting del frontend Next.js;
- piano e regione Supabase;
- provider email transazionale;
- strategia di feature flag/cutover progressivo;
- provider AI e budget.

## Decisioni operative chiuse il 21 settembre 2026

- La finestra di contestazione e di 48 ore dalla consegna. Le prove sono
  fotografie private WebP ricodificate lato client senza EXIF; compratore,
  venditore e admin le leggono solo tramite URL firmati temporanei. Il venditore
  risponde entro 48 ore. La stima di tre giorni lavorativi parte dalla
  documentazione completa e non e una garanzia. Il payout resta bloccato usando
  il motore gia esistente; nessun rimborso o provider viene acceso.
- I Club nascono come proposte e richiedono approvazione. Possono essere aperti
  o chiusi, hanno richieste di ingresso, moderatori, regolamento versionato,
  link esterni e audit append-only. La superficie resta chiusa con flag UI
  spenta e grant pubblici revocati finche flusso UI e contenuti non sono provati.
- Il banner incidenti e scrivibile solo da `admin` o `emergency_delegate`, con
  audit append-only. La migrazione non assegna il ruolo a nessuno. La pagina di
  stato statica deve essere distribuita su infrastruttura separata.
- La destinazione offsite scelta e Backblaze B2 EU Central con cifratura `age`,
  Object Lock e retention 30 giornalieri, 12 settimanali, 12 mensili. Il job
  è attivo dal 22 settembre 2026 e resta fail-closed se il gate non vale
  esattamente `true` o se configurazione, retention o readback non sono validi.

## Comandi di verifica

### `frontend/`

```powershell
cd frontend
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

### `frontend-next/`

```powershell
cd frontend-next
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

Lo script `test` esiste ed è eseguito anche in CI, dietro la soglia minima
`MIN_TESTS` definita in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
La soglia è volatile e va letta dal workflow: serve perché `bun test` esce 0
quando i file di test esistono ma non contengono casi. Si alza deliberatamente
quando si aggiungono test; non si abbassa come manutenzione.

### `backend/`

```powershell
cd backend
python -m compileall -q .
python -m ruff check .
$env:APP_ENV = "test"
python -m pytest -q
```

I test backend non devono usare rete, MongoDB reale o credenziali
Stripe/AI.

## Fonti dettagliate

- [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md)
- [`../docs/MIGRATION_PHASE_1_BACKLOG.md`](../docs/MIGRATION_PHASE_1_BACKLOG.md)
- [`../docs/adr/001-target-architecture.md`](../docs/adr/001-target-architecture.md)
- [`../docs/adr/002-migration-strategy.md`](../docs/adr/002-migration-strategy.md)
- [`../docs/SECURITY.md`](../docs/SECURITY.md)
- [`../docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)
- [`../docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md)
