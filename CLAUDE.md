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
`MIN_TESTS` (123 today) and fails when fewer cases pass than that. The floor is there because
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
  functional parity across all migrated domains — cutover (Phase 11) is a separate, explicit
  decision, never automatic.
- Domain migration order follows dependency, not convenience: Auth (5) → Listings/Catalog (6) →
  Orders/Payments (7) → Messaging/Notifications (8) → Moderation (9) → AI (10) → Cutover (11).
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
  `frontend/` until the Phase 11 cutover, where its removal has to be on the cutover list. It was
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
and payment activation outside the merge. The PR was opened as draft on 6 August 2026, passed all
four checks without review requests and moved to ready-for-review; CI and Supabase Preview must be
green again on its final pre-merge documentation head before the authorized squash merge.

### Postgres exposure rules (binding since Phase 6d-1)

RLS filters rows, never columns. These three rules are what keeps that gap closed — breaking
one of them is how a private column ends up readable by strangers:

- **No whole-table read grant to a role that can reach rows it does not own.** If a policy lets
  `anon` or a non-owner `authenticated` see a row, that table gets a column-scoped `GRANT SELECT`
  or none at all. A table whose RLS restricts every client role to its own rows may keep the
  table-level grant (`bottle_units` does) — the deciding question is which rows the role reaches,
  not which table it is.
- **Public reads go through a `security_invoker = off` view with a closed column list**, never
  through a policy on the base table. `public_listings` and `public_bottle_units` are the
  pattern: the filter is written inside the view where no client can widen it, and a column
  added to the base table later stays private until someone deliberately lists it.
- **A column with a domain rule behind it is not writable by the client.** It leaves the
  column-level `GRANT` and gets a `SECURITY DEFINER` function as its only door — `listings.stato`
  (6a), `bottle_units.stato` and `deleted_at` (6d-1). Cross-table invariants that an index or
  `CHECK` cannot express get a trigger as well, so `service_role` is bound by them too.

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
