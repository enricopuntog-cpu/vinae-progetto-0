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

1. Una fase = un branch = una PR draft.
2. Nessuna fase successiva senza approvazione esplicita.
3. Nessuna nuova funzionalità durante la migrazione: cercare parità.
4. Un solo writer autorevole per dominio.
5. `frontend/` + `backend/` restano serviti fino alla Fase 12 (era la Fase 11
   fino all'11 agosto 2026: alla chiusura della Fase 10 il cutover è diventato
   la 12 e le quattro estensioni AI ammesse per eccezione sono diventate la 11).
6. Non lavorare direttamente su `main` e non force-pushare mai. Il merge su
   `main` è consentito **solo dopo approvazione esplicita data in sessione** e
   **solo in squash**: l'autorizzazione del 5 agosto 2026 sostituisce il click
   manuale, non l'approvazione. Prima di chiudere o mergiare qualunque PR,
   aggiornare `CHANGES.log`, `CLAUDE.md` e questa cartella con lo stato che
   quella PR produce davvero — numero, cosa cambia, cosa resta aperto — come
   **ultimo commit della PR stessa**, prima dello squash e non dopo: dopo lo
   squash il branch non c'è più e l'aggiornamento richiederebbe una PR a parte.
7. Non usare Lovable o Emergent per generare/modificare il codice.
8. Le migrazioni sul progetto Supabase reale richiedono revisione dell'SQL e
   conferma esplicita in sessione prima di `supabase db push` o equivalenti.
9. I test remoti che inseriscono o cancellano fixture richiedono una conferma
   esplicita separata dall'approvazione al deploy. L'autorizzazione è **per
   griglia e non per progetto**: quella concessa per la 7c non copre la 7b. La
   pulizia va garantita anche sul percorso d'errore, e i residui vanno riletti e
   riportati dopo l'esecuzione, non dichiarati.
10. Dopo `apply_migration` via API/MCP, allineare il file locale alla versione
    assegnata dal server e verificare la migration history.
11. Un file di migrazione già pushato almeno una volta non si modifica più in
    place: ogni correzione successiva è un nuovo file con timestamp più
    recente, anche in bozza e anche se la versione precedente non è mai stata
    applicata al progetto reale. Il branch di anteprima che Supabase crea per
    ogni PR esegue le migrazioni all'apertura, e un ambiente che ha già
    registrato una versione come eseguita non la rilancia quando il testo
    cambia: controlla la versione, non il contenuto. È successo sulla PR #19,
    dove l'anteprima ha eseguito la prima bozza della migrazione di Fase 7b
    (commissione 5% piatta) e non ha mai ripreso la riscrittura a netto
    garantito.

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
  resta fino al cutover di Fase 12, dove la sua rimozione va scritta nella lista
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
  distribuiti sul progetto reale al merge — schema a ledger e tre Edge Function
  `ACTIVE` — ma mai percorsi da un ordine e mai provati contro Stripe, nemmeno
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
- gestione centralizzata segreti, CSP/HSTS, osservabilità, alert;
- backup, restore e disaster recovery;
- Leaked Password Protection in Supabase Auth.

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

Lo script `test` esiste ed è eseguito anche in CI, dietro una soglia minima:
il job imposta `MIN_TESTS` (166 oggi) e fallisce se passano meno casi di così.
La soglia serve perché `bun test` esce 0 quando i file di test ci sono ma non
contengono casi: senza di lei una suite che si svuota in silenzio resterebbe
verde. Si alza di proposito quando si aggiungono test; abbassarla è una
decisione, non manutenzione.

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
