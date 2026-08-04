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
`MIN_TESTS` (83 today) and fails when fewer cases pass than that. The floor is there because
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

- Never work directly on `main`. Never force-push. Never merge autonomously —
  merges to `main` require explicit approval recorded in the organizational log.
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
