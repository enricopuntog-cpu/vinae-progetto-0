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

## Debiti e decisioni ancora aperte

### Bloccanti prima di denaro reale o beta pubblica

- progettazione Stripe Connect, payout, KYC/onboarding venditore, rimborsi e
  contestazioni;
- verifica legale italiana/UE su vendita di alcolici, età, privacy e modello
  marketplace;
- rate limiting condiviso per RPC/Edge Functions;
- threat model e revisione indipendente;
- gestione centralizzata segreti, CSP/HSTS, osservabilità, alert;
- backup, restore e disaster recovery;
- Leaked Password Protection in Supabase Auth.

### Debiti della migrazione

- trasferimento reale della proprietà della bottiglia al compratore in Fase 7;
- scheduler affidabile per scadenza annunci;
- catalogo condiviso: `listing_crea` può inserire un vino tramite
  `SECURITY DEFINER`; la Fase 6d-2a deve distinguere catalogo curato e vino
  inserito dall'utente prima della Fase 7;
- prove remote post-repair 33/33 e 11/11 ancora da autorizzare e documentare;
- automazione dei test Supabase in CI con database effimero;
- test frontend per `frontend-next/`;
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
bun run build
```

Non esiste ancora uno script `test` in `frontend-next/`.

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
