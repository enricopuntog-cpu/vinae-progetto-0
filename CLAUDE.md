# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Handoff Bridge

At session start, read `CHANGES.log` after this file. At the end of every work
session or before handing off/context reset, update it obligatorily: keep its
four headings exact, `NEXT STEPS` at exactly 3 atomic items, facts only, no
pleasantries, no secrets. Verify Git state before writing and preserve
unresolved blockers.

## What this is

Vinea is an Italian wine-club web app (personal cellar catalog, wine discovery, themed clubs,
peer-to-peer marketplace flows). The repo is **mid-migration**: a legacy stack (`frontend/` +
`backend/`) is the only version actually served to users, while `frontend-next/` + Supabase is
the target architecture being built alongside it, one domain at a time. Never assume
`frontend-next/` is live in production — check `docs/ROADMAP_V1.md` for the current phase.

## Repository layout

```text
frontend/       React 19, TanStack Start, TypeScript, Tailwind — CURRENT production frontend
backend/        FastAPI + MongoDB (Motor, async) — CURRENT production backend, transitional by design
frontend-next/  Next.js App Router, Supabase — TARGET frontend, migrated domain by domain
supabase/       SQL migrations + config for the target backend (Postgres/RLS/Auth)
docs/           architecture, security, environment, migration roadmap/backlog, ADRs
.github/        CI (lint/typecheck/test/build for both frontends + backend)
```

`frontend/` and `frontend-next/` are near-duplicates of the same design system
(`components/ui/**`, `components/vinea/**`, `data/**`, `config/**`) — when porting a
component, diff against the `frontend/` version rather than rewriting from scratch.

## Commands

### frontend/ (current, TanStack Start) — Bun 1.3.14 only, no other package manager/lockfile
```bash
cd frontend
bun install --frozen-lockfile
bun run dev          # vite dev, port 3000
bun run lint
bun run typecheck
bun run test         # Bun's native test runner
bun run test:watch
bun run build
```
Run a single test file: `bun test src/hooks/useCellar.test.ts`.

### frontend-next/ (target, Next.js App Router) — Bun 1.3.14
```bash
cd frontend-next
bun install --frozen-lockfile
bun run dev
bun run lint
bun run typecheck
bun run test         # Bun's native test runner — run in CI behind a minimum-count floor
bun run build
```
CI runs these tests and **enforces a floor**: the `Test` step of the `frontend-next` job sets
`MIN_TESTS` (255 today) and fails when fewer cases pass than that. The floor is there because
`bun test` exits 0 when the test files exist but contain no cases — without it a suite that
silently empties itself would still be green. Raise it deliberately when tests are added;
lowering it is a decision, not housekeeping. These tests are type-checked as well: `tsconfig.json`
includes `**/*.ts` and `@types/bun` is among the devDependencies.

### backend/ (current, FastAPI/MongoDB) — Python 3.12
```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
cp .env.example .env   # Windows: Copy-Item .env.example .env
python -m uvicorn server:app --host 127.0.0.1 --port 8001 --reload
python -m compileall -q .
python -m ruff check .
python -m pytest -q
```
Run a single test: `python -m pytest tests/test_auth.py -q`. Tests must run with `APP_ENV=test`,
no network, no real MongoDB, no real Stripe/AI credentials — everything is swapped for in-memory
fakes (see `backend/tests/conftest.py`).

### supabase/
Migrations live in `supabase/migrations/*.sql`, applied via the Supabase CLI. Naming is
timestamp-prefixed (`20260728000545_auth_profiles_roles.sql`). Every migration that touches a
real domain needs RLS policies, and ideally pgTAP tests, per ADR 002.

**A migration file that has been pushed at least once is frozen — never edit it in place.**
Every later correction is a NEW migration file with a more recent timestamp: in draft too,
before review too, and even when the previous version was never applied to the real project.
"No database has ever run it, so editing it is safe" is no longer a valid test. Supabase creates
a preview branch for each PR and runs the migrations on it as soon as the PR opens, and an
environment that has already recorded a version as applied does not re-run it when the text
changes — it compares the version, not the content. Editing in place therefore leaves that
environment silently out of sync with the file, with nobody watching. The episode that produced
this rule is recorded in `CONTESTO_IA/03_ARCHITETTURA_REGOLE_DEBITI.md`.

**Never assign a bare `case` to an enum column.** A lone literal is `unknown` and coerces to the
destination column's type; a `case` between two literals resolves to **`text`**, and text→enum has
no implicit cast, so the statement fails to compile with `42804`. Cast **both** branches
(`'consegnato'::public.order_stato`), not just the first — then the `case` is the enum by
construction rather than by a resolution rule one extra literal could move again. Read the enum's
exact name from `pg_type` instead of assuming it, and check the labels exist: a cast to a
non-existent label is a `22P02` at runtime, the same defect moved. Phase 7c shipped this bug into
production in `ordine_contestazione_risolvi`, where it meant no dispute could ever be closed in the
seller's favour and their funds stayed frozen — `docs/PHASE_7F_FIX_VERIFICATION.md`.

CI (`.github/workflows/ci.yml`) runs three independent jobs — `frontend`, `frontend-next`,
`backend` — each in its own working directory. All must pass before merge to `main`.

## Migration architecture — read before touching frontend-next/ or supabase/

The full picture is in `docs/ROADMAP_V1.md`, `docs/MIGRATION_PHASE_1_BACKLOG.md`, and
`docs/adr/001-target-architecture.md` / `002-migration-strategy.md`. The load-bearing rules:

- **One phase = one branch = one draft PR.** Never work on two migration phases in parallel on
  the same domain. A phase does not start without explicit prior approval recorded in the
  organizational log referenced by those docs.
- **No new features during migration** — the goal is behavioral parity with `frontend/`, not
  product improvement. If a page in `frontend-next/` seems to need functionality that doesn't
  exist yet in `frontend/`, that's a signal to stop and flag it, not to build it.
- **Only one authoritative writer per domain at a time.** Once a domain (e.g. Auth) moves to
  Supabase, the FastAPI/MongoDB path for that domain stops being the writable source of truth.
  Legacy reads may remain only if explicitly planned for that phase.
- **`frontend/` + `backend/` stay the served version** until `frontend-next/` reaches verified
  functional parity across all migrated domains — cutover (Phase 12) is a separate, explicit
  decision, never automatic.
- Domain migration order follows dependency, not convenience: Auth (5) → Listings/Catalog (6) →
  Orders/Payments (7) → Messaging/Notifications (8) → Moderation (9) → AI (10) →
  AI extensions admitted by exception (11) → Cutover (12).
  **The phases were renumbered on 11 August 2026 by PR #36**, when Phase 10 closed: the cutover
  was Phase 11 and is now Phase 12, and the four features decisions 7.3/7.12/7.13 admitted by
  exception became the new Phase 11 — they are not Phase 10 and had no phase of their own, so
  they belonged nowhere. Two classes of file keep the old number on purpose, because editing
  them is forbidden or meaningless: the two `supabase/migrations/*.sql` that mention it in a
  comment — a pushed migration is frozen, and one of those four occurrences is inside a
  `comment on column`, so "Fase 11" is live text in the production catalog on
  `bottle_units.visibilita` — and
  `docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md`, which is the minutes of
  one day and not a live plan.
- `frontend-next/src/services/types.ts` defines the service interfaces
  (`AuthService`, `ListingService`, etc.) that both mock and real (Supabase) implementations
  satisfy — these interfaces map ~1:1 to the 8 domain slices already split out of
  `frontend/src/lib/vinea-store.tsx` in Sprint 1. New Supabase-backed services should be adapters
  behind these interfaces, not replacements for them.
- In `frontend-next`, real Supabase auth (`real-auth-domain.ts`, `auth-service.ts`) and the mock
  demo-switcher role system (`auth-domain.ts`, Guest/User/Admin) intentionally coexist — the mock
  switcher still drives UI for domains not yet migrated. Don't try to unify them until the
  corresponding domain is actually migrated.
- Profile row creation on signup happens via a Postgres trigger (`handle_new_user()`), not a
  client-side `INSERT` — this avoids depending on a session existing immediately after `signUp()`
  when email confirmation is required.
- OAuth/magic-link redirects use `window.location.origin` dynamically rather than a hardcoded
  origin (a fixed `localhost` breaks cross-device flows); the origin used must still be in the
  Supabase project's allowed Redirect URLs.
## Process rules not covered above

- Never work directly on `main`. Never force-push.
- Merging to `main` is allowed **only after explicit approval given in-session**, and only as a
  **squash merge**. Approval granted on 5 August 2026 replaces the manual click, it does not
  replace the approval itself: without an explicit go-ahead for that PR, do not merge.
- **Before closing or merging any PR, update `CHANGES.log`, `CLAUDE.md` and `CONTESTO_IA/` with the
  state that PR actually produces** — its number, what it changes, what it leaves open — and commit
  that as the **last commit of the PR itself**, before the squash merge. Not afterwards: after the
  squash the branch is gone and the update would need a PR of its own. A generic summary does not
  satisfy this rule; the facts of that PR do.
- Do not use Lovable or Emergent to generate or modify code, even to fix a bug
  quickly — both are retired tooling for this project.
- Commits are small and descriptive, one logical change each.
- Any SQL migration that touches the real (non-local) Supabase project: stop
  before applying it, show the exact SQL for review, and wait for explicit
  confirmation in-session before running `supabase db push` or equivalent.

## Working method

If the Superpowers plugin is installed and active (check with `/plugin` or
`claude plugin list`), use it for any phase touching real data or carrying
technical risk: brainstorm/spec before writing code, then small tasks with a
checkpoint (test/lint/typecheck/build) and an atomic commit at each checkpoint.
If it isn't installed or active, apply the same discipline manually — plan
first, implement, verify at each step. Its absence is not a blocker.
## Cross-cutting security invariants (apply to both stacks)

These hold for `backend/` today and must hold for any Supabase/Edge Function replacement:

- The frontend is never a trust boundary: it cannot assign itself roles, confirm a payment, or
  supply price/currency/owner for a transaction. All of that is resolved server-side.
- Payment state is only ever trusted from `payment_status=paid` plus a signed, deduplicated
  Stripe webhook — a Checkout Session's `status=complete` alone proves nothing.
- CORS/redirect origins are explicit allowlists (no `*` in shared/production environments);
  matching is by full origin, not substring/domain suffix.
- Sommelier chat history, orders, and transactions are readable only by their owner or an
  explicitly authorized role; history has ownership, a max message count, and a TTL.
- Auth/AI/payment provider credentials are abstracted behind an interface
  (`TokenVerifier`, `AIProvider`) so providers are swappable and tests can inject fakes without
  network or real credentials.
- The platform markup is computed server-side and **frozen on the order** — result and the three
  parameters that produced it. A client never sends a commission, and changing
  `marketplace_config` later must not move an order that already exists.
- Money moves only by not being moved: the charge carries neither `transfer_data` nor
  `on_behalf_of`, so funds stay on the platform balance and the seller's Transfer is created
  separately at release, for the seller's price alone (Phase 7b).
- Capability flags that mean "this seller can be paid" (`charges_enabled`, `payouts_enabled`,
  and the `seller_enabled` role derived from them) are written only by applying a signed provider
  event, never by a request from the seller.

### Economic decisions closed in Phase 7d (binding — PR #22)

Phase 7d wrote no SQL. It closed decisions that constrain what later phases may build:

- **Auto-release is driven by an external scheduler (GitHub Actions), not `pg_cron`** (decision
  1a). `pg_cron` + `pg_net` are excluded, not deferred: they would put the service role key and the
  job token in clear text in `cron.job`, and `pg_net` is fire-and-forget, so `cron.job_run_details`
  records `succeeded` even on a `401`/`503`. Reproposing them requires reopening the decision.
  Cadence confirmed by decision 1d: `0 */6 * * *` with `PAYOUTS_BATCH_LIMIT` 50. A scheduled
  workflow only runs from the default branch, so the file has to live on `main`.
- **The scheduler is switched on and verified before `PAYMENTS_ENABLED`, never after** (decision
  1e). Inverted, the first run inherits a historical backlog of orders past their deadline.
- The scheduled workflow authenticates with the **legacy anon JWT plus `PAYOUTS_JOB_TOKEN`**, not
  the service role key: `payouts-release` builds its privileged client from the function's own env,
  so the caller's JWT only crosses the gateway and carries no database authority. With
  `verify_jwt=true`, a new `sb_publishable_...` key cannot replace the legacy anon JWT without a
  separate gateway/config decision. The workflow sends no service role credential.
- Decision 1c assigns native GitHub Actions failure notifications and `PAYOUTS_JOB_TOKEN` rotation
  to Enrico / `enricopuntog-cpu`. Rotation is every 90 days and immediately after suspected
  exposure. Phase 7g adds no external notification integration and does not configure or rotate
  the secret remotely.
- With `PAYMENTS_ENABLED=false`, `payouts-release` authenticates the scheduler and performs only
  the read-only health count for orders whose `auto_rilascio_scadenza` is older than 24 hours and
  whose `payout_stato='trattenuto'`; it does not claim orders or call Stripe. This is the safe
  precondition for verifying the scheduler before payments are enabled.
- **The "protezione" (3%) line is out of the Supabase model** (decision 3a). It stays untouched in
  `frontend/` until the Phase 12 cutover, where its removal has to be on the cutover list. It was
  measured at 0.59–0.60× the net margin Phase 7b already withholds, and in the real Stripe path it
  was never actually charged.
- **A fee-reconciliation retry cap must never be a new value of `public.payment_stato`** (decision
  2c, design approved, schema not written). `payout_prepara`, `ordine_auto_rilascio_esegui` and
  `conferma_ricezione` all filter on `payments.stato = 'paid'`, so a new value would freeze the
  seller's funds because the platform cannot read its own cost. Derive the marker from a
  `fee_tentativi >= N` counter and keep it out of every release predicate.
- `spedizione` stays undecided until decision 3e (one invoice or two from the logistics partner)
  has a commercial answer. Designing before it arrives means betting.

### Phase 7g operational closeout — PR #26

PR #26 is the delivery vehicle for the external scheduler selected in Phase 7d. It adds the
six-hour GitHub Actions workflow, its fail-closed Node runner and the read-only overdue-payout
health response in `payouts-release`. The PR keeps `PAYMENTS_ENABLED=false`, sends only the legacy
anon JWT plus `PAYOUTS_JOB_TOKEN` and never sends the service role key. It leaves GitHub
variable/secret configuration, token rotation, the first real `workflow_dispatch`, SQL, fixtures
and payment activation outside the merge. The PR merged on 6 August 2026 as squash `f9c53e0`;
those remote operations remain separate gates.

### Phase 8 messaging and notifications — PR #27 merged

PR #27 merged into `main` on 7 August 2026 at 11:36 UTC as squash `4f96864`, with all four checks
`SUCCESS` — Frontend, Frontend Next, Backend and `Supabase Preview` — on the branch's final head
`b32ff9d`. It adds the additive messaging/notification migration, closed-column RLS and RPC ports,
private Realtime Broadcast invalidations, TypeScript adapters, mock parity and the `/messaggi` and
`/notifiche` routes. Browser channels call `realtime.setAuth()` before subscribing, use only
`config.private = true`, treat payloads as closed invalidations and reload canonical rows through
the RPC adapters. Logout or user change removes every channel and invalidates stale callbacks.
`MIN_TESTS` in the `frontend-next` CI job was **166** at that merge; Phase 9 raised it to **204**
and the Phase 10 10a+10b checkpoint to **234**, then 10c to **255**.

The merge distributed the migration: `20260806224517 phase_8_messaging_notifications` is the
**twentieth row of the production ledger**, re-read with `list_migrations` on 9 August 2026, and it
matches the twenty files in `supabase/migrations/` on `main`. Nobody ran a command — the GitHub
integration applied it, as it has for every phase since Phase 7.

The Phase 8 proofs — static grid 20/20, fixture grid 23/23, five concurrent cases, authenticated
Realtime smoke, zero residues in ten classes — were taken on the isolated Supabase Preview
`jggjaqcdbcbxdxhnggio`, which was tied to the PR. **That Preview no longer exists**: `list_branches`
on the real project now reports only the `main` branch. Those numbers are a report of that phase,
not a state that can be re-measured on demand — the same distinction that applies to every grid in
this project. In particular, the `private_only` Realtime restriction was configured on the Preview,
never on production: whether production Realtime allows public channels is unverified.

Two production facts that outlive the merge: the Phase 8 tables have not been re-read since, so the
schema is distributed but its data state is unverified; and the Phase 7g scheduled workflow
`Phase 7 - auto-release payouts` has run 11 times from `main` and **failed every time** with
`Configurazione mancante: SUPABASE_URL`, because the GitHub variables and secrets were never
configured. The runner is fail-closed and never reached the network, but decision 1e — scheduler
switched on and verified *before* `PAYMENTS_ENABLED` — is not satisfied.

### Phase 9 moderation — PR #32, merged and distributed

Both checkpoints plus one extension shipped together on `migration/phase-9-moderation-service`: 9a
is schema, append-only audit and read-only projections; 9b is the seven distinct moderation RPCs,
the five listing transitions, and the two-level user suspension of decision 7.6b; 9c carries the
second level onto commerce. PR #32 opened on 11 August 2026 with all four checks green — including
`Supabase Preview`, which applied the four migrations to the isolated preview `fomwzziqrajwmqfuzqaz`
before the merge. Decision 7.9 makes a single explicit in-session confirmation cover both the merge
and the application; that confirmation was **asked again after 9c widened the perimeter, and
obtained on 11 August 2026** — the earlier one covered only the three migrations verified then.
It merged as squash `cd81df6` on 11 August 2026, and the production ledger — re-read straight
after — is at **twenty-four rows**, last one `20260810210000 phase_9_rimosso_blocca_commercio`,
distributed by the GitHub integration rather than by a command. A read-only check confirms
`reports`, `report_events` and `audit_log` exist and are empty, `public_bottle_units` is gone, the
`orders_commercio_rimosso_guard` trigger is present and the seven commerce `SELECT` policies filter
on `stato_utente`; `authenticated` has no whole-table `UPDATE` on `profiles` and none of the four
moderation columns is writable. **No Phase 9 behaviour has ever been exercised there** — schema,
grants and counts were read, not a transition run. Two boundaries were accepted as they stand: `public.proposals` stays outside the
`rimosso` block, and an already-paid order of a later-removed seller can stall before `consegnato`,
covered by the existing exits (the buyer's `conferma_ricezione` from `pagato`, or `ordine_contesta`).
Running any Phase 9 grid against the real project remains a **separate, per-grid** authorization
that this confirmation does not grant.

Ten decisions from the 10 August 2026 organizational session are binding and are not reopened
without going back to that session; they are recorded in `CONTESTO_IA/01_STATO_ATTUALE.md` under
«Fase 9 — decisioni organizzative». The ones that constrain future code:

- The moderator is the existing `admin` role — no `moderator` role, club scope deferred (7.1).
  The predicate is **written out as an `exists` on `public.user_roles`, never `public.has_role()`**:
  that helper is `SECURITY INVOKER` and `authenticated` has no `SELECT` on `user_roles`, so it
  raises `permission denied` for every caller. It stays broken for `wines_insert_staff` /
  `wines_update_staff` / `wines_delete_staff` too — recorded, deliberately not fixed.
- `audit_log` is never deleted (7.3), reports carry no assignment column (7.5), `post`/`commento`
  are not reportable until clubs have a schema (7.6a), there is no SLA (7.8a) and no appeal field
  (7.8b). Adding any of them is reopening a decision.
- Suspension has two levels (7.6b): the first blocks social writes only — listings and messages —
  and leaves commerce untouched; the second also removes read access. 9b applied the second level
  to the social surface only; the organizational session **reopened that and widened it** — 9c adds
  order creation, the seven commerce `SELECT` policies and `conferma_ricezione`. The first level is
  unchanged: a suspended user still buys and sells.
- **Nothing in 9c may make the payment machine react to `stato_utente`.** The scheduler,
  `ordine_auto_rilascio_esegui`, `payout_coda`, `payout_prepara`, `payout_registra_esito`, the
  Stripe webhook and `ordine_contestazione_risolvi` are untouched, and a grid case asserts that
  their bodies never name the column. Adding a condition there is the 7c/7f defect class: a payment
  frozen with no exit because one extra predicate stops existing logic from completing. For the
  same reason the seller's manual transitions (`ordine_segna_spedito`, `ordine_segna_consegnato`, …)
  stay open for a removed seller — they are what carries an already-paid order to `consegnato`,
  which is where the verification window and therefore auto-release start.
- `public_bottle_units` is gone (7.7), but `bottle_units.visibilita` and the
  `bottle_unit_visibilita` enum survive as a documented inert residue: the column is a
  `bottiglia_crea` parameter written by both frontends. It belongs on the Phase 12 cutover list.

PR #33 carried the post-merge verification onto `main` — squash `8dd56c0`, 11 August 2026,
documentation only. The production ledger was re-read on 11 August 2026 and is unchanged at
twenty-four rows.

### Phase 10 AI — CLOSED, merged and distributed off

**Phase 10 is closed at its single checkpoint.** PR #35 merged as squash `442c98c` on
11 August 2026 at 18:53:14 UTC, four checks green on the final head `c5034a6`. The closed
perimeter is **the three migrated features**: Sommelier chat with Postgres history, food-wine
pairing, cataloguing suggestion from text. Do not describe this phase as "in progress".

Measured straight after the merge, not declared:

- **The production ledger is at twenty-five rows**, last one
  `20260811160000 phase_10b_sommelier_storico` — the GitHub integration distributed it, as for
  every phase since Phase 7. `public.sommelier_messaggi` exists with RLS on and **zero rows**,
  `my_sommelier_messages` is `security_invoker = off`, and the three `SECURITY DEFINER` doors
  carry the exact grants declared: `sommelier_contesto_leggi` and `sommelier_scambio_registra`
  to `service_role` only, `sommelier_storico_cancella` also to `authenticated`. No `anon`
  anywhere. **No Phase 10 behaviour has ever been exercised there** — schema and grants were
  read, not a conversation run; running the `10b_sommelier_storico.sql` grid on the real project
  is still a **separate, per-grid** authorization.
- **Six Edge Functions are `ACTIVE`**: the three existing ones plus `ai-pairing`, `ai-catalogo`,
  `ai-sommelier`, all `verify_jwt=true`. The three new ones were created 38 seconds after the
  merge and all six share one `updated_at` 43 seconds after it — the three pre-existing
  functions went to version 15/14/14 with new bundle hashes although the PR touched none of
  their source. That is decision 7.10 measured a second time: the merge is the deploy gate, and
  it redeploys everything. **Measured a third time on 12 August 2026**, after the merge of PR #37
  — documentation only: the six went to **17/16/16 and 3/3/3**, all sharing one `updated_at`
  43 seconds after that merge. Same gap as the previous measurement.

**`AI_ENABLED` stays off** until Enrico configures the provider key and budget — decision 7.11,
committed deadline **Monday 18 August 2026**. The phase is distributed **off, by construction**:
the flag fails closed, which is exactly what made it safe to merge before the keys existed. This
is not an unfinished edge of the phase; it is the phase's designed end state until that date.

The four features admitted by exception are **not** Phase 10 and are **not** started: they are
the new Phase 11, with no branch. See the renumbering note in the migration rules above.

#### How it got there — all thirteen decisions closed first

`docs/PHASE_10_AI_SERVICE_SPEC.md` is the organizational spec, same standard as Phase 9: every
claim carries a `file:line` source, line numbers pinned to `8dd56c0`. The organizational session of
**11 August 2026** ran in two passes — five decisions first (plus two the spec had not foreseen,
taking the count from eleven to thirteen), then, after the report on the eight proposals, **the
remaining eight plus the two consequent points no decision covered**. Nothing is open. The
implementation branch `migration/phase-10-ai-service` opened after that, not before.

**The first checkpoint is 10a + 10b + 10c, and deliberately not all seven features.** 10a is the
stateless AI door — food-wine pairing and cataloguing suggestion from text — 10b is the
Sommelier history plus the SSE chat, and 10c puts the three UI surfaces back on top of them: the
Sommelier panel in the Layout, the Assistant panel in the sell wizard's Identification step, and
the pairing panel in `/esplora`. The photo features (7.3a/7.3b), moderation triage (7.12) and
real background compositing (7.13) stay out: they are less specified (Storage, MIME, PhotoRoom
integration) and **each earns its own spec session before code**, on the model of Phase 9's
separate 9a/9b/9c.

All thirteen are recorded in full in `CONTESTO_IA/01_STATO_ATTUALE.md` under «Fase 10 —
decisioni organizzative». What constrains code:

- **7.1 — not one provider, one per task.** GPT-5 for the Sommelier chat (a preference, to be
  confirmed against 5-6 real conversations first), Claude or Gemini for the photo features (to be
  chosen on real label photos, not a clean-document benchmark), the cheapest tier available for the
  moderation classifier. The legacy `AIProvider` abstraction already carries more than one provider
  natively and must not be forced down to one. **Until those trials are run the phase has no
  provider** — the one prerequisite that no amount of code closes.
- **7.2 — A, a Postgres table** for the Sommelier history, so **Phase 10 writes SQL**. The
  consequent TTL question was closed with it: **expiry is applied at read**, the read view filters
  on `expires_at`, and **no physical deletion is planned for v0** — expired rows stay in the table
  until a future cleanup, which must be stated in code and spec rather than left implicit.
  `pg_cron` remains excluded by Phase 7d decision 1a; opportunistic cleanup was rejected because it
  never expires an abandoned conversation, and a second Actions job because it would add a
  scheduler to one sitting at 18 failed runs out of 18.
- **7.3, 7.12, 7.13 — four new features admitted by explicit exception**: photo autofill (7.3a),
  a documentary-completeness badge (7.3b), moderation triage (7.12), real background compositing
  (7.13). These are the first new features authorized since the migration began, and they take the
  perimeter from three features to seven. «No new features during migration» **has not lapsed** —
  it still governs everything a session has not asked for by name. Two riders: the 7.3b badge must
  be labelled documentary completeness and **never** certified authenticity, and 7.12 gives the AI
  **no autonomous action and no «AI actor» identity in `audit_log`** — it classifies and ranks, a
  human presses the button. The triage result is a **persisted column on `reports`**, not recomputed
  on each panel opening — that is the phase's **second** migration, after the Sommelier history.
- **7.4 — one rate-limit bucket per feature, hourly window, no second cap of ours.** Not one shared
  bucket like the legacy's `ai:user:{id}`. The window is `report:submit`'s
  (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524` — `10, 3600`), **not the
  checkout's per-minute one**. No extra ceiling beyond the rate limit for v0; a monthly budget is
  deferrable to after launch. The limit **applies to `admin` too** — an exemption is a privileged
  path in exactly the scenario the cap exists for.
- **7.5 — legacy error mapping unchanged**: provider down → 503, unusable response shape → 502,
  a generic error in the stream and in the response, and **never the provider's message to the
  client**. `AI_ENABLED` is the twin of `PAYMENTS_ENABLED` — **fail-closed when absent**, which is
  what makes it safe to merge the phase before the keys exist. The application timeout is bound by
  the Edge Function's own duration limit and never beyond it. Failures are logged to the function
  log; **no dedicated table** (a new table is a new migration and a new exposure surface, and
  `audit_log` is for moderation decisions).
- **7.6 — no rename, and one function per feature.** `PAYMENT_ALLOWED_ORIGINS` **stays untouched**:
  the AI functions read their own `AI_ALLOWED_ORIGINS`, replicating the `_shared/cors.ts` pattern
  (full origins, never substrings, `Vary: Origin`) in a **separate module**, so the payments path's
  shared file has an empty diff in every Phase 10 PR. This matters because the merge redeploys
  *all* functions: editing `_shared/cors.ts` puts the payments path back into production on every
  later merge, whoever makes it and for whatever reason. Surface follows Phase 9's seven distinct
  RPCs — one door per operation, no `action` field in the body.
- **7.7 — SSE stays**, and the truncation constraint is written in the code, not discovered in
  production: an Edge Function forwarding a stream **can be cut off** when the worker is withdrawn,
  so the function keeps the isolate alive for the whole relay and **the client treats a partial
  truncation as an expected case, not a rare error**.
- **7.8 — the pairing catalog is resolved server-side** from `public_listings`/`wines`, not sent by
  the client. This is a **declared deviation** from `frontend/`, which today sends a static
  eighteen-entry demo file (`frontend/src/routes/esplora.tsx:14`, `:102-105`): parity here would
  preserve the mechanism and lose the meaning. It costs one extra query per call — accepted.
- **7.9 — AI access follows the two suspension levels of 9b/9c.** First level (social writes only)
  does **not** touch AI access; second level (which also removes read access) blocks AI too, same
  surface as the other social features. The Sommelier panel **stays mounted for anonymous users**
  as today — no session means a 401 from the Edge Function, which is parity with `frontend/`.
- **7.10 — the deploy gate is the merge**, the same one as migrations; there is no separate deploy
  action to authorize. Applying anything to the real project — migration or function — still needs
  an **explicit, per-perimeter confirmation** in the organizational session, as in Phase 9.
- **7.11 — Enrico configures provider keys and budget by Monday 18 August 2026**, a commitment with
  a name and a date. The technical guard is independent of it: **no Phase 10 merge with `AI_ENABLED`
  implicitly true** when the variables aren't readable in the environment — fail-closed by design,
  not entrusted to the discipline of whoever merges. That distinction is what failed in the 7g case.

**Edge Functions are deployed by the merge, all of them, every time.** Verified 11 August 2026 and
previously unrecorded: `list_edge_functions` gives the three functions a `created_at` 35-37 seconds
after the merge of the PR that introduced them, and an `updated_at` identical across all three,
49 seconds after the merge of **PR #33** — a three-file documentation PR touching no function code.
No workflow in `.github/workflows/` deploys functions and nobody has ever run `supabase functions
deploy`. Consequences: the deployment gate is the same one as for migrations, a merge redeploys
functions the PR never touched, and therefore **a function's environment is configured before the
merge, never after**, with a flag that keeps it off when the environment is missing. This corrects
the spec's own first draft, which claimed a separate `deploy` step no decision covered.

The inventory contradicts the two-line backlog entry on three points, and those corrections are
what future work must start from rather than the backlog:

- **`ai-identify-bottle` does not exist**, in the repository or on the real project.
  `supabase/functions/` holds only `_shared/`, `connect-onboarding/`, `payments-checkout/`,
  `payouts-release/`; `list_edge_functions` on `pijnmcllmfgjmgsvtcej` reports the same three
  deployed functions and no other. The name in the backlog is an intention, not a contract.
- **Bottle identification from a photograph does not exist in the legacy either.** The backend
  accepts an `ocr_text` field (`backend/ai_routes.py:228`) but no caller in `frontend/` ever sends
  it — the single call site sends only `hint` (`frontend/src/hooks/useSellWizard.ts:66`) — and
  there is no image-capture path anywhere in `frontend/src`. Building it is a **new feature**, and
  decision 7.3 admitted it anyway as an explicit exception — the analysis stands, the conclusion
  was overridden by a session that wanted it by name.
- **The real perimeter of what is *migrated* is five routes over three features**, not one:
  Sommelier chat with persistent history, food pairing, and cataloguing suggestion
  (`backend/ai_routes.py:16`). Only the chat has data to move. With 7.2 answered A and four new
  features admitted, the phase's total perimeter is seven features and **at least three migrations**
  — the history, the 7.3b badge (an attribute of a listing, therefore a column the exposure rules
  keep out of the client's `GRANT`), and the persisted triage result on `reports`.

Two things already exist and must not be rebuilt. The `AIProvider` abstraction the security
invariants call for is **already implemented** in `backend/ai_provider.py:14-16`, with a
fail-closed `DisabledAIProvider` (`:19-27`) and every provider exception collapsed into a generic
`AIProviderError` (`:56-57`, `:71-72`). And the server-side rate limit the backlog asks for is in
production since Phase 7: `public.rate_limit_consume` is granted to `service_role` and to nobody
else (`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:157-160`), so an Edge
Function holding a service client can consume a bucket via `rpc()` **without any new migration**.

One correction to that inventory, found when the code was written: **an `AiService` interface did
already exist**, at `frontend-next/src/services/types.ts:987` — after `ModerationService`, not
instead of it — with `identificaBottiglia`, `miglioraSfondo` and `suggerisciAbbinamento`, no
implementation of any kind, and the same three methods duplicated in `frontend/src/services/types.ts:153`.
It did not describe the migrated perimeter: two of its three methods are features the legacy does
not have, and the two that exist — Sommelier chat and cataloguing suggestion — were missing. The
10a checkpoint replaces it with the real contract. What remains true: no adapter and no `phase10/`
directory before that branch, no AI environment variable, and exactly one `/api/ai` occurrence in
`frontend-next/src`, a comment deferring to Phase 10 (`frontend-next/src/hooks/useSellWizard.ts:72`).

### Phase 10 checkpoint 10a + 10b + 10c — what the code now fixes in place

- **`supabase/functions/_shared/cors.ts` has an empty diff and must keep it.** The AI functions read
  `AI_ALLOWED_ORIGINS` through `_shared/ai-cors.ts`, a separate module that replicates the pattern
  rather than importing it. Editing the shared file would put the payments path back into
  production on every later merge.
- **The rate-limit numbers live in one place**, `supabase/functions/_shared/ai-gate.ts`, and were
  fixed in session on 11 August 2026: `ai:chat` **40/hour**, `ai:pairing` **15/hour**,
  `ai:catalogo` **10/hour**. The first draft put all three at 10, copying the `report:submit` model
  the decision cited; a real Sommelier conversation is five to fifteen turns, so `ai:chat` at 10
  emptied inside the first one. Still binding and not parameters of that file: hourly window for
  all three, no `admin` exemption, no secondary cap beyond the rate limit for v0.
- **`sommelier_messaggi.ordinale`, not `created_at`, orders a conversation.** Both rows of one
  exchange are inserted by the same statement and share `now()`; ordering by time left it
  indeterminate whether the question precedes the answer, and made the message-cap delete pick an
  arbitrary subset — an exchange could survive with the answer and lose the question. Running the
  grid found this; reading it had not. The cap, the context read, the view and the adapter all use
  `ordinale`.
- **The read view filters on `(owner_id, session_id)` and never on `session_id` alone.** The client
  picks the `session_id` with `Math.random()`; `owner_id` comes from `auth.uid()` inside the view.
- **Expired history rows are not deleted.** The view filters on `expires_at` and v0 has no physical
  cleanup — stated in the table comment, in the migration and in grid case 09 rather than left
  implicit.

10c restores the three UI surfaces on top of `AiService`, and fixes four more things in place:

- **The Sommelier panel stays mounted for anonymous visitors** (7.9) — the refusal comes from the
  service, not from the UI, which is parity with `frontend/`. But **the history is not read at all
  without a session**: `my_sommelier_messages` filters on `auth.uid()` inside the view, so for an
  anonymous client the answer is zero rows with certainty and the request is guaranteed useless.
- **A "already requested" marker for an async read belongs in a `ref`, never in state.** In state the
  `setState` causes a render, the render re-runs the effect because the marker is among its
  dependencies, and the cleanup aborts the request that just started — the panel would always open
  empty on a conversation that exists in the database.
- **The pairing panel resolves the AI's identifiers through `Wine.listingId`, not `Wine.id`.** After
  7.8 the function proposes `public_listings.id`, the primary key, while the frontend's `Wine.id` is
  the slug (`frontend-next/src/services/listing-service.ts:154-155`). `listingId ?? id` is the idiom
  already used for this same distinction.
- **Clearing derived results belongs in a derivation, not in an effect.** Next 16's
  `set-state-in-effect` ESLint rule rejects a synchronous `setState` inside an effect and is right:
  `frontend/`'s version re-renders on every keystroke to erase something that can simply not be
  drawn.

One divergence from `frontend/` declared in 10c: a `tipologia` outside the five allowed values does
not reach the wizard's fields. In `frontend/` publishing is a demo toast, so an invented type at
worst blanks a dropdown; here the wizard really writes and that value would reach `bottiglia_crea`.

Two constraints that were never open decisions and that 7.9 does not relax. Reading `stato_utente`
inside an AI function must not make the **payment machine** react to it — the same rule fixed for
9c, and the 7c/7f defect class it protects against does not change nature because a later phase
adds the predicate. That is precisely why 7.9's check lives in the Edge Function and in the history
table's own RLS, and nowhere near an order. And the AI key lives in the Edge Function's own
environment, never in the repository and never in the browser
(`docs/MIGRATION_PHASE_1_BACKLOG.md:567-570`); adding it means updating `docs/ENVIRONMENT.md` and
the relevant `.env.example` in the same change.

### Phase 11 — AI extensions admitted by exception. Not started, no branch.

The four features decisions **7.3, 7.12 and 7.13** admitted by explicit exception during Phase 10
and that its single checkpoint left out: photo autofill (7.3a), documentary-completeness badge
(7.3b), moderation triage (7.12), real crop and background (7.13). They are the first new
features authorized since the migration began, and they were authorized **by name** — "no new
features during migration" still governs everything else.

The four decisions describing them are **already closed**, in section 7 of
`docs/PHASE_10_AI_SERVICE_SPEC.md`. **Everything else was closed on 12 August 2026**, in two
sessions of the same day — Storage, PhotoRoom, the shape of the migrations, every numeric value
and the photo-provider trial. **Section 6 of the spec has no open areas left.**

The phase's size after those answers: **four migrations** (one per checkpoint), **four new Edge
Functions** — deployed functions go from six to **ten** — **two Storage buckets**, **three rate
scopes** and **two provider adapters**. It was "two migrations plus a third" and "three functions".
All four features carry SQL, not two.

**Each feature earns its own spec session before code**, on the model of Phase 9's separate
9a/9b/9c. Two riders carried over from the decisions: 7.3b's badge is **documentary
completeness** and never certified authenticity, and 7.12 gives the AI **no autonomous action
and no "AI actor" identity in `audit_log`** — it classifies and ranks, a human presses the button.

#### The organizational spec exists — `docs/PHASE_11_AI_EXTENSIONS_SPEC.md`

Same standard as Phases 9 and 10: every claim carries a `file:line` source, line numbers pinned
to **`271c7dc`** (the squash of PR #36), 38 absolute citations machine-verified. Three inherited
claims were re-verified against the real project and **corrected** — start from these, not from
the two-line backlog entry:

- **The signed photo-upload path already exists and is well built**
  (`frontend-next/src/app/vendi/actions.ts:43-79`, `frontend-next/src/hooks/useSellWizard.ts:192-216`).
  Size limit and MIME types are not virgin questions: they already have an answer replicated in
  **three aligned places**, and a new bucket adds a fourth.
- **Only one provider adapter is implemented, and it is OpenAI.** Choosing Claude or Gemini for
  the photos (7.1) is **not setting a variable**: it is writing an adapter, widening the task
  union, and adding a signature that takes an image. Implementation work, to be counted.
- **`reports.priorita` already exists** — a three-value enum written only by the server inside
  `segnalazione_invia`, derived from a deterministic domain rule, with the moderator queue
  **already ordered** on it and its own index. 7.12's triage does not land on empty ground: the
  question was no longer "where does the result live" but **what relation it has to `priorita`**.
  Answered 12 August 2026: **coexistence**, with `priorita` still the primary ordering.

The decisions closed in session on **12 August 2026**, in two passes, recorded in full in
`CONTESTO_IA/01_STATO_ATTUALE.md` under «Fase 11 — decisioni organizzative». First pass:

- **Storage: a dedicated bucket**, not reuse of `annunci`/`cantina` — because `annunci` is public,
  so an autofill-only photo later abandoned would stay world-readable forever to anyone with the
  URL. "Dedicated" does not decide "private"; the second pass decided that too.
- **7.3a and 7.3b are two distinct Edge Functions**, not one shared — "one door per operation",
  as in Phase 9's seven RPCs and Phase 10's three functions. This **supersedes the 7.6 table**,
  which put both inside `ai-catalogo`. The downside accepted then — one vision call serving both
  would mean double cost — **was cancelled by the second pass**: the badge is computed at
  publication and the autofill during the wizard, so there is no call to share.
- The spec lives in **its own PR**, separate from #36.
- **PR #36's go-ahead was conditional**, not unconditional — "se quella PR è completa sì, se no la
  completiamo e mergiamo". The condition was verified and one incompleteness found and fixed
  before merge: #36 did not record its own number. Recording the conditional form rather than
  "approved" is deliberate.

Second pass — what constrains code:

- **Bucket `foto-ai`, private, no cleanup, 5 MB, three MIME types.** Private is what actually
  closes the problem that disqualified `annunci`: a dedicated *public* bucket would reproduce the
  perpetual URL-readability identically. Orphan cleanup is therefore hygiene, not confidentiality
  — and **that `foto-ai` accumulates orphans that nothing removes in v0 must be written** in the
  bucket comment and in the migration, same discipline as the Sommelier history TTL.
  **`image/avif` is out** — the one deliberate divergence from the two existing buckets — because
  **PhotoRoom does not accept AVIF as input** (verified on the provider's documentation, which is
  what the question demanded before deciding). 5 MB is unchanged: lowering it here would produce a
  photo the wizard accepts and the autofill rejects.
- **PhotoRoom gets its own module** on the `payment-provider.ts` pattern, never inside
  `ai-provider.ts` (two signatures, neither takes an image). **Its key leaves the 18 August
  deadline** and gets a date tied to opening `11c` — leaving it on 18 August would make it expire
  without being needed, the inert-deadline shape of the 7g case. **The seller chooses** crop vs
  compositing, with **"cutout only" preselected**: one *Image Editing* call costs five *Remove
  Background* calls, so a compositing default would quintuple the per-photo cost for a choice
  nobody made. PhotoRoom's failure is **silent** (`200` with a wrong image, not a 503), so the
  result goes through **a preview with explicit confirmation** and never overwrites the original.
- **EXIF is stripped before forwarding to any third party**, and `docs/SECURITY.md` gets a line
  saying so — a bottle photo taken at home carries the GPS coordinates of where it was shot.
  **Consequence: the function must download the bytes**; stripping metadata means rewriting the
  file, so a signed URL would never have sufficed and the image is uploaded as `imageFile`. That
  is what makes the private bucket free.
- **A fourth bucket `sfondi`, public**, for 7.13's hand-curated catalog — editorial material of
  the platform, not a user's data, and no user writes to it. The phase's new buckets are **two**.
- **The completeness badge is an `enum` of three values**, computed **at publication**, **expiring**
  on photo change with **explicit recalculation** (never a trigger — that would be an AI call
  inside a transaction), and **visible to anonymous buyers** in `public_listings`. That visibility
  is what makes 7.3's labelling constraint load-bearing rather than a matter of internal wording.
- **The triage result coexists with `priorita`, in a linked table `report_triage`.** The question
  that decided it was not schema but *what the moderator cannot do today*, and the answer is
  **telling apart severity inside the `alta` bucket**. Ordering is **cascaded**: `priorita` first,
  triage score inside the group, then date — so a model never overrides the deterministic rule,
  which is how "no autonomous action" becomes an `order by`. Content is **score plus a short
  rationale**, no category enum. **Not exposed in `my_reports`.** The existing
  `reports_stato_priorita_idx` no longer covers the ordering; a new index is needed.
- **The client calls `ai-triage` after the RPC — `segnalazione_invia` is not touched.** It is a
  Postgres function and cannot call an external provider (`pg_net` excluded by Phase 7d decision
  1a), so an Edge Function was required; grafting it onto the existing RPC would tie a critical
  existing action to a third party's availability, which is the opposite of why `AI_ENABLED` fails
  closed. Accepted cost: triage is **optional** if the client does not call — degrading well, not
  failing silently, because the queue still has `priorita` as its net.
- **Rate limits: `ai:autofill` 30/hour, `ai:completezza` 10/hour, `ai:sfondo` 15/hour.** None
  inherited — 7.4 proposed `10 / 3600` for everything, and Phase 10's numeric re-confirmation had
  to correct two of three values. **No new scope for the triage.** `AiScope` goes from three values
  to six. Unchanged: hourly window, no `admin` exemption, no second ceiling of ours for v0.
- **Spend caps live on each provider's account**, value set **when the key is configured** — no
  real consumption has ever been observed for any AI provider in this project, and a number chosen
  without data would be exactly the invented value the rest of the phase has avoided.
- **The photo-provider trial (6.6) comes before `11a`:** Enrico, six real photos of his own cellar
  including two deliberately difficult, scored on **two separate counts** — correct fields out of
  `ai-catalogo`'s nine **and** invented fields — because counting only correct ones rewards a model
  that guesses all nine over one that honestly leaves four blank, and invention is the error
  `confidence` does not catch.
- **The `ai-triage` guard is enforced in three places, not left implicit** in checking who calls:
  a **uniqueness constraint on `report_triage.report_id`** (the only one that holds against a race
  between concurrent requests and against `service_role`), a **check before the provider call**
  inside the function (without it the constraint fires at `insert`, i.e. *after* paying), and a
  **grid case** exercising it. This is what makes "no new scope" true: the natural bound is one
  evaluation per report, and the total is already capped by `report:submit`.

**No implementation branch was opened, and that is a decision rather than caution.** All four
checkpoints are blocked by external dependencies: `11a` by the 6.6 trial, which the same session
placed *before* it and which needs keys that do not exist (7.11, 18 August 2026); `11b` by `11a`;
`11c` by a PhotoRoom key whose date is by definition `11c`'s own opening; `11d` by the Phase 9
moderation panel, never exercised on the real project.

**The legal review stays outside the phase, and the phase does not close without it.** §9 of the
spec records the **first proposal** handed to that review — an AI/privacy notice shown at
registration, proposed 12 August 2026. It is recorded as a **proposal, not a closed point**: it
reasonably covers the AI Act's general transparency duty (art. 50), but not on its own the DSA's
statement of reasons for the individual moderation decision a user suffers (art. 17), which
attaches to *that* decision and is not discharged by a generic acceptance given months earlier.
7.12's human-in-the-loop reduces the exposure — the DSA is stricter on fully automated decisions —
without eliminating it. §9 is deliberately **not** part of section 6, which stays closed in full.

**The first concrete action toward that duty is shipped, and it is Phase 10 code, not Phase 11.**
PR #39 (13 August 2026) puts a visible AI transparency label on each of the three AI surfaces
Phase 10 put in production — the Sommelier panel, the sell wizard's Identification assistant, the
`/esplora` pairing panel. They already said "AI", but in the **panel title**: "Sommelier AI" is a
sign, not a statement. The copy lives in **one module**,
`frontend-next/src/lib/phase10/etichette-ia.ts`, with five tests, for two load-bearing reasons: the
wording changes in **one place** when the legal review answers, and a test asserts the covered
surfaces are exactly the existing ones, so a **fourth** AI surface — Phase 11's four will be —
cannot be added without a label in silence. Same shape as 10b's `SESSION_ID_VALIDO` constraint.
`MIN_TESTS` went 255 → **260**. Each line describes what the surface actually does: cataloguing
*suggests* and does not fill, because applying the suggestion is a second explicit gesture, and a
test pins that. They say "IA", not "AI", deliberately — the panels keep "AI" as part of their own
name, and a label written the same way would read as another sign. **This moves nothing in §9.2**:
the DSA statement of reasons attaches to *that* moderation decision, the legal-review block stays
where it was, and all five §9.4 questions stay unanswered.

**§10 of the spec records copy and flow for `11a` and `11c` — registered, not built.** The autofill
button (7.3a) is «Riempi i campi automaticamente con l'IA», kept verbally distinct from
cataloguing's «fatti suggerire» because they are two different operations in the same wizard step.
The background flow (7.13) is four steps: pick a curated background, press «Passa al set fotografico
IA» which converts **every** photo of the listing, land on a **filmstrip** screen showing each
converted photo beside its original, and **confirm or reject per photo**. Step four is 6.3 made
concrete — the preview with explicit confirmation exists because PhotoRoom fails **silently** (`200`
with a wrong image), and the side-by-side strip is what makes visible a failure no code can notice.
§10.3 derives an arithmetic nobody had done from two already-decided numbers: `MAX_FOTO = 6` and
`ai:sfondo` at **15/hour** mean one press on a full listing costs **six** calls, so the limit covers
**two complete conversions per hour** and the third strip stops **halfway**. `11a` and `11c` remain
blocked exactly as before.

**§10.3 is now closed — three session decisions, 13 August 2026, PR #40.** They bind `11c` the same
way §6 does; they are not an implementer's call. **(a) The strip stops halfway; the button does not
disable itself upfront.** Already-converted photos stay ready, the rest keep their original until
the hourly bucket refills. A total refusal for a constraint covering *part* of the listing throws
away work that could have been done — five photos and three tokens would convert none of the three
possible — and the worry that kept the question open, a partial result nobody announced, dissolves:
the side-by-side strip **is** how it is announced. **(b) `ai:sfondo` stays at 15/hour.** The
arithmetic is a legitimate reason to reopen the number, but a reason is not data. The criterion is
Enrico's, in his own words — **«prima di pagare»** — so it reopens on **real costs** and observed
usage **after `11c` is live**, not on a theoretical count. It stays a **6.5 point to bring back to a
session** then; whoever implements `11c` writes **15**. **(c) Confirmation is bulk with exceptions**
— a quick "confirm all", but the seller can **exclude** or **redo** a single photo first. That one is
written as an **interface constraint inside §10.2**, at step 4 of the sequence, not merely as a note,
alongside two more: the original is never overwritten even after a bulk confirm, and **a mixed state
is a legitimate state of the strip** — to be designed, not avoided. **None of the three reopens §6**:
(b) touches a 6.5 value and **confirms** it, and a note at the end of 6.5 records that the number was
looked at again and under what condition it returns to a session.

### Postgres exposure rules (binding since Phase 6d-1)

RLS filters rows, never columns. These three rules are what keeps that gap closed — breaking
one of them is how a private column ends up readable by strangers:

- **No whole-table read grant to a role that can reach rows it does not own.** If a policy lets
  `anon` or a non-owner `authenticated` see a row, that table gets a column-scoped `GRANT SELECT`
  or none at all. A table whose RLS restricts every client role to its own rows may keep the
  table-level grant (`bottle_units` does) — the deciding question is which rows the role reaches,
  not which table it is.
- **Public reads go through a `security_invoker = off` view with a closed column list**, never
  through a policy on the base table. `public_listings` is the pattern (and `my_reports`,
  `my_listing_moderation` are the same shape for own-row reads): the filter is written inside
  the view where no client can widen it, and a column added to the base table later stays
  private until someone deliberately lists it. `public_bottle_units` was the second example
  until Phase 9a dropped it — decision 7.7.
- **A column with a domain rule behind it is not writable by the client.** It leaves the
  column-level `GRANT` and gets a `SECURITY DEFINER` function as its only door — `listings.stato`
  (6a), `bottle_units.stato` and `deleted_at` (6d-1), `profiles.stato_utente` and its three
  companion columns (9b). Cross-table invariants that an index or `CHECK` cannot express get a
  trigger as well, so `service_role` is bound by them too. Note the 9b case: `profiles` had a
  **whole-table** `UPDATE` grant, so adding a moderation column to it without narrowing that
  grant would have let a suspended user lift their own suspension.

Versioned SQL/RLS proofs live in `supabase/tests/` and are run by hand in the Supabase SQL
Editor — see that directory's README. They are not migrations and CI does not run them yet.

**A versioned grid that has never been executed is not a proof.** Phase 7e measured the cost:
the 7c grid was broken in four ways, none of them visible by reading the file, and it could not
have committed under any scenario — not even with every case passing. Its first real run gave
21 PASSA / 1 FALLISCE, and the one failure was a defect in the migration with a consequence on
money, not a defect in the test. The grids for Phase 7 (16 cases), 7b (23) and 6d-2a (18) are
still unexecuted; treat their expected outcomes as text, not results.

Fixture authorization is **per grid, not per project**: approval to run the 7c grid does not
cover 7b. Cleanup must be guaranteed on the error path too, and residues get re-read and
reported after the run rather than declared. To create a test user that can actually
authenticate, follow the verified procedure in `CONTESTO_IA/04_HANDOFF_NUOVA_IA.md` — the Auth
API path hits a project-wide SMTP limit, and the SQL path needs an `auth.identities` row plus
four `varchar` token columns set to empty string rather than `NULL`.

Full detail: `docs/SECURITY.md`, `docs/ARCHITECTURE.md`, `docs/ENVIRONMENT.md`.

## Environment variables

Never commit `.env`; copy the `.env.example` in each of `frontend/`, `backend/` (and
`frontend-next/.env.local` for Supabase keys). Adding a new variable requires updating the
relevant `.env.example` **and** `docs/ENVIRONMENT.md` in the same change — this is treated as
part of "done," not optional documentation.

## Definition of done (from docs/DEVELOPMENT.md)

A change is complete when: it's typed and readable; errors don't leak internal details;
permissions are checked server-side; deterministic local tests exist; lint/typecheck/test/build
all pass; docs and env examples are updated; no secrets or reliance on temporary preview
environments are introduced.
