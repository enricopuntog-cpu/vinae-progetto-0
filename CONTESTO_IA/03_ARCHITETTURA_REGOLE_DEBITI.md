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
5. `frontend/` + `backend/` restano serviti fino alla Fase 11.
6. Non lavorare direttamente su `main`, non force-pushare e non fare merge
   autonomamente.
7. Non usare Lovable o Emergent per generare/modificare il codice.
8. Le migrazioni sul progetto Supabase reale richiedono revisione dell'SQL e
   conferma esplicita in sessione prima di `supabase db push` o equivalenti.
9. I test remoti che inseriscono o cancellano fixture richiedono una conferma
   esplicita separata dall'approvazione al deploy.
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

## Debiti e decisioni ancora aperte

### Bloccanti prima di denaro reale o beta pubblica

- Stripe Connect, payout e onboarding venditore: progettati e merged con la
  Fase 7b, ma non applicati ad alcun database e mai provati contro Stripe,
  nemmeno in test mode. Restano fuori il KYC oltre l'onboarding ospitato,
  l'interfaccia di gestione delle contestazioni e il recupero automatico di un
  rimborso successivo a un Transfer già creato;
- schedulazione dell'auto-rilascio: richiede `pg_cron` e `pg_net` sul progetto
  ed è oggi un blocco commentato in fondo alla migrazione di Fase 7b;
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
  ancora `supabase/**`, e le griglie SQL si eseguono a mano;
- test frontend per `frontend-next/`: esistono e sono imposti in CI da
  `MIN_TESTS`, ma coprono logica pura e adapter, non le pagine;
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
il job imposta `MIN_TESTS` (83 oggi) e fallisce se passano meno casi di così.
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
