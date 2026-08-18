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
- **A PR whose diff contains zero files under `supabase/migrations/` may be squash-merged by a
  Claude Code session autonomously, without asking first** — admitted by name by Enrico on
  **16 August 2026** and recorded by **PR #47**. The boundary is that directory and nothing else:
  whatever else the diff touches (`frontend-next/src/`, `backend/`, documentation, CI config)
  neither narrows nor widens it. Three conditions hold together — the three CI jobs (`frontend`, `frontend-next`, `backend`)
  all green, and GitHub reporting `mergeable: MERGEABLE` **and** `mergeStateStatus: CLEAN` **on
  the head commit being merged**, not on an earlier one. **Any PR carrying even a single migration
  file stays an explicit merge by Enrico, without exceptions.** The reason is that in this repo the
  merge is the **only** gate for migrations (decision 7.10, recorded below): there is no separate
  apply command, so a PR carrying SQL has no later step at which anybody reviews it. What the
  **18 August 2026** re-measurement of the three Phase 12 merges corrects is the word *instant*.
  The merge triggers a **Supabase integration run**, and that run **can fail to start**. On the
  merge of **PR #49** (17 August 2026, 17:50:10 UTC) it never ran: `3a6ba69` carries four check
  runs and none of them is `Supabase Preview`. Its three 12b/12c migrations reached production
  **5h 27m 05s later**, carried by the run that the merge of **PR #50** triggered — a PR with
  **zero** migration files. So "zero files under `supabase/migrations/`"
  still answers the question the exception actually asks — *does this PR add SQL of its own* — and
  the boundary does not move; but it does **not** promise that a given merge distributes nothing.
  **Whoever merges a PR carrying migrations re-reads the ledger with `list_migrations` afterwards
  and reports the count**, rather than treating the merge as proof that they applied — and whoever
  merges without them checks the ledger still matches the files on `main`, because a backlog lands
  on an arbitrary later merge and the merge that clears it is not the one that owns it. Wait past a
  minute before concluding: a read taken mid-apply returns the *previous* count, the same stale-read
  trap `list_edge_functions` has. Edge Functions are the other half and behave differently: their
  redeploy has **never** skipped a merge, in nine measurements.
  This narrows the "explicit approval in-session" rule under "Process rules" below; it
  does not abolish it, and it changes nothing about starting a phase, applying SQL or fixtures to
  the real project, or the cutover — each stays its own separate authorization.
- **No new features during migration** — the goal is behavioral parity with `frontend/`, not
  product improvement. If a page in `frontend-next/` seems to need functionality that doesn't
  exist yet in `frontend/`, that's a signal to stop and flag it, not to build it.
- **Only one authoritative writer per domain at a time.** Once a domain (e.g. Auth) moves to
  Supabase, the FastAPI/MongoDB path for that domain stops being the writable source of truth.
  Legacy reads may remain only if explicitly planned for that phase.
- **`frontend/` + `backend/` stay the served version** until `frontend-next/` reaches verified
  functional parity across all migrated domains — cutover (Phase 13) is a separate, explicit
  decision, never automatic.
- Domain migration order follows dependency, not convenience: Auth (5) → Listings/Catalog (6) →
  Orders/Payments (7) → Messaging/Notifications (8) → Moderation (9) → AI (10) →
  AI extensions admitted by exception (11) → Club/Community (12) → Cutover (13).
  **The phases were renumbered again on 16 August 2026 by PR #46**: the cutover was Phase 12 and is now
  **Phase 13**, and the new **Phase 12** is Club/Community, which takes that number because it
  follows Phase 11 directly in dependency order. Phase 12 is structured in three checkpoints
  **12a/12b/12c**, detailed in that phase's organizational document, **not yet written in this
  repo**; **checkpoint 12a opened on 17 August 2026** on `migration/phase-12a-club-readonly`
  (PR #48), and **12b + 12c shipped together on 17 August 2026** (PR #49) — this line used to say
  they were "not started", which stopped being true the same day and was still here on
  **18 August 2026**, contradicting two sections further down this same file. What remains true is
  narrower and is the only part to carry forward: **`public.clubs` has 0 rows**, so the club
  surface has schema, RLS and a working club-specific reporting mechanism, and **no real
  destination** — re-measured on the real project on 18 August 2026, detail in the 12b+12c section
  below. That renumbering shipped **before** the phase
  branch was opened — it is the prerequisite that frees the number, not the phase itself.
  Unlike 11 August, **no frozen file keeps the old number**: searching "Fase 12"/"Phase 12" in
  `supabase/migrations/*.sql` and `docs/superpowers/plans/` returns **zero results**, verified
  rather than assumed from the rule.
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
  **One exception, admitted by name on 16 August 2026**: a PR whose diff contains **zero files
  under `supabase/migrations/`** may be squash-merged autonomously, with the three CI jobs green
  and `mergeable: MERGEABLE` / `mergeStateStatus: CLEAN` read on the head commit being merged.
  Exact boundary and reasoning in the "Migration architecture" bullet above. A PR with even one
  migration file is still an explicit merge by Enrico.
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
  `frontend/` until the Phase 13 cutover, where its removal has to be on the cutover list. It was
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
this project. The sentence this paragraph used to carry about the `private_only` Realtime
restriction — configured on the Preview, never on production — **was wrong on both halves, and PR
#52 closed it**: the Realtime **authorization** half (the RLS policy on `realtime.messages`) *is* in
production and correctly scoped, and the project-level restriction to private channels is **already
in force** as well. Do not reopen it; the toggle is named for the opposite of what the phrase
`private_only` suggests, and the detail is in the PR #52 section at the end of this file.

**Phase 8 was distributed but not working for eleven days, and the fix is in production since
18 August 2026 — read the PR #52 section at the end of this file before trusting anything here about
its runtime behaviour.** Its four `stable` read RPCs answered **405** to every page load by a
logged-in user, so the phase was never exercised in production: re-read for the first time on
18 August 2026, its four tables held **zero rows**, and they still do. That re-read closes the
"tables not re-read since the merge" gap this paragraph used to open. **The 405 itself is closed**
by the merge of PR #52 (squash `dde9b52`), verified against the real project with an authenticated
user — but **no message has ever travelled end to end there**, so parity of the phase's behaviour
remains unmeasured, not proven. The other production fact that outlives the merge: the Phase 7g scheduled workflow
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
  `bottiglia_crea` parameter written by both frontends. It belongs on the Phase 13 cutover list.

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
  43 seconds after that merge. Same gap as the previous measurement. **A fourth, fifth and sixth
  time on 13 August 2026**: after PR #39 (frontend code, no function line) the six were at 19/18/18
  and 5/5/5; after PR #40 (five documentation files, zero lines under `supabase/functions/`) at
  20/19/19 and 6/6/6, 55.8 seconds after that merge; and after PR #41 (four documentation files,
  same zero) they are at **21/20/20 and 7/7/7**, again sharing one `updated_at`, **55.3 seconds**
  after it. **A seventh time on the merge of PR #42** — documentation only again: **22/21/21 and
  8/8/8**, one shared `updated_at` of `2026-08-13T21:10:18.307Z`, **36.3 seconds** after it.
  Seven measurements, **five of them on documentation-only PRs** (#33, #37, #40, #41, #42). The
  gaps are 43, 43, 49, 59, 55.8, 55.3 and 36.3 seconds — and the seventh is **shorter than all six
  before it**, so it *widens* the observed range rather than confirming the earlier "around a
  minute". Recorded that way on purpose, not smoothed into the previous claim. What does not move
  is the conclusion: the merge is the deploy gate and it redeploys everything, so Phase 11's **four
  new functions** will be born with whatever environment the merge finds.
  **One caveat for whoever measures the eighth**: `list_edge_functions` can serve a **stale**
  `updated_at` for a few seconds after the redeploy. On PR #42 a read at +39.3 s still returned the
  *previous* merge's value although the redeploy had already been stamped at +36.3 s — reporting
  that read would have claimed the pattern had broken. Wait past a minute before concluding
  anything. One precision correction, which changes no conclusion: those gaps are computed from the
  API's unambiguous epoch-milliseconds value and need **none** of the one-hour adjustment earlier
  readings noted as constant. That offset was a reading artefact, not a property of the API.

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

**§10.3 is now closed — three session decisions, 13 August 2026, PR #40**, merged as squash
`91f8d82` at 20:09:43 UTC after its conditional go-ahead was re-verified in session rather than
inherited from an earlier reading — including that all four checks were read on the exact
`head_sha` `beea3a52…`, not merely "on the PR". They bind `11c` the same
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

### Phase 12 — Club/Community. 12a merged; 12b + 12c open together in one PR.

Renumbered in on **16 August 2026 by PR #46**, taking the number the cutover held: Club/Community follows
Phase 11 directly in dependency order, so the cutover moved to **Phase 13**. The phase is
structured in **three checkpoints, 12a/12b/12c**, detailed in **that phase's organizational
document, which is not yet written in this repo** — until it is, the content of 12b and 12c is
not to be inferred from here.

**Checkpoint 12a is merged** as squash `e2132ee`,
[PR #48](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/48), 17 August 2026.
Its perimeter is **read-only plus a real follow**, and the boundary is what matters: `/community`
and `/community/[slug]` come back on real rows, an authenticated user follows and unfollows a
club, and **no user-writable content exists** — no posts, no replies, no reactions. Those belong
to 12b, and 12a does not create an empty table waiting for them: the surface exists from the
moment the table exists, not from the moment it is populated. The two tabs that would hold them
stay visible and say so. **This does not admit content writing by name** — that admission belongs
to the session that opens 12b — **and it does not close the phase.**

What 12a fixes in place, and that later checkpoints inherit:

- **`clubs` has no client write door at all, and that is measured rather than conservative.** The
  expected shape would be an admin write policy with `public.has_role(auth.uid(), 'admin')`. An RLS
  policy evaluates its predicate with the *caller's* privileges, and `authenticated` has no `SELECT`
  on `public.user_roles` since 6d-1 — so neither `has_role()` nor its inlined `exists` works inside a
  policy: both raise `permission denied for table user_roles` for everyone, admins included. It is the
  same defect `wines_insert_staff` has carried since Phase 6a, recorded by 9a and deliberately not
  fixed. The 9a trick — inlining the predicate in a `security_invoker = off` view — solves *reading*,
  not writing. 12a has no screen that creates a club, so a door with no caller would be surface
  without a user; when 12b or 12c want one it is a `SECURITY DEFINER` function (exposure rule 3),
  never a policy.
- **`club_memberships.user_id` comes from `DEFAULT auth.uid()` and is outside the `INSERT` grant**,
  which is `grant insert (club_slug)` and nothing else. No service method takes a `userId` in any
  position — not a style preference: such a parameter would have nowhere to land.
- **Public reads go through `public_clubs`**, `security_invoker = off` with a closed column list,
  which also publishes the two things the base table does not have: the member count (nobody may read
  `club_memberships` beyond their own rows) and the caller's own `seguito`.
- **Following a club is a social write** and takes the 9b guard unchanged — `private.scrittura_social_guard()`
  already has the `else auth.uid()` branch for tables whose actor is not a row column. A `rimosso`
  caller does not read `public_clubs`, same shape as `public_listings`. **No orders, payments,
  disputes or payouts table is named anywhere in the migration**, so the 9c constraint holds by
  construction.
- **The seed fixture is a separate gate from the migration**, and lives in
  `supabase/queries/02_PROPOSTA_NON_ESEGUIRE_SEED_CLUB_FASE_12A.sql` for two measured reasons: under
  `supabase/migrations/` the merge would apply it to the real project by itself (decision 7.10), and
  the name `supabase/seed.sql` is loaded on every `db reset` and on preview branches, because
  `config.toml` has `[db.seed]` enabled on exactly that path.
- Decision **7.6a** is not reopened: `report_target_tipo` keeps its five labels and gains neither
  `post` nor `commento`. That decision deferred them «until clubs have a Supabase schema» — 12a gives
  clubs a schema but gives posts none, so there is still nothing for those two targets to resolve to.

#### Checkpoint 12b + 12c — club content and its moderation. One PR, never two merges.

Shipped as [PR #49](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/49), squash `3a6ba69`,
17 August 2026 — **merged, and in production**: its three migrations are rows 27-29 of the ledger,
distributed 5h 27m later by the merge of PR #50 (see the PR #51 section).

**Re-measured on the real project on 18 August 2026**, because a stale line elsewhere in this file
still called 12b/12c "not started" and that had to be settled by measurement rather than by reading:
all five club tables exist as ordinary tables with RLS on — `clubs` (9 columns), `club_memberships`
(4), `club_posts` (13), `club_post_risposte` (8), `club_post_like` (3) — and **all five hold zero
rows**. The reporting mechanism is **club-specific and live**, not the generic Phase 9 one:
`segnalazione_invia` resolves the target against the real tables
(`when 'post' then exists (select 1 from public.club_posts cp where cp.id = p_target_id)` and its
twin on `club_post_risposte`), and both `moderazione_rimozione` and `moderazione_ripristino` carry a
dedicated `elsif v_report.target_tipo in ('post','commento')` branch. **A measurement trap worth
inheriting**: the body of `moderazione_rimozione` does **not** contain the string `club_posts` — the
table reference lives in the delegated helper `private.moderazione_contenuto_club_transizione`, so a
`like '%club_posts%'` probe there returns a false negative.

**What this does not change**: the admission of club content writing stays **ammessa per eccezione**
— the 16 August 2026 decision is untouched as a decision, only its progress status moved. And
because `clubs` is empty, there is still **no real destination** for a club post: any later work
that wants one needs the seed fixture
(`supabase/queries/02_PROPOSTA_NON_ESEGUIRE_SEED_CLUB_FASE_12A.sql`), which is a separate
authorization nobody has given.

**12b and 12c never separate in merge.** 12b introduces user-writable public text; 12c
introduces the way to report and remove it. Merging 12b alone would open a window — of a length
decided by when 12c gets approved — in which anyone publishes on a public surface and nobody can
report what they read. It is the same rule decision **7.6a** already applied in the other
direction.

**Fase 12b+12c — scrittura di contenuti nei club, ammessa per eccezione.** La scrittura di
contenuti pubblici nei club (`club_posts`, `club_post_risposte`, `club_post_like`) è ammessa per
eccezione esplicita e per nome da Enrico, in sessione di coordinamento della Fase 12. È la seconda
funzionalità nuova autorizzata durante la migrazione dopo le quattro della Fase 11 — «niente
funzionalità nuove durante la migrazione» non è decaduta: continua a valere per tutto ciò che una
sessione non ha chiesto per nome. L'ammissione è condizionata e inseparabile dalla 12c: nessun
contenuto pubblico scrivibile va in produzione senza un modo per segnalarlo, la stessa regola già
valida per la 7.6a.

**Decision 7.6a is fulfilled, not reopened.** It deferred `post` and `commento` «until clubs have a
Supabase schema». 12a gave clubs a schema but gave posts none, so the condition still held; 12b
gives posts and replies one, and with that the two labels finally have a table to resolve to. 12c
adds them to `report_target_tipo`, which takes it from five values to **seven** — the seven of the
mock.

What 12b+12c fix in place, and that later work inherits:

- **`report_target_tipo` is an enum, not a check constraint, and that forces THREE migration
  files.** In PostgreSQL 12+ `alter type ... add value` may sit inside a transaction, but the new
  value **cannot be used in the transaction that adds it**, and Supabase applies each file in its
  own. Measured in session, not deduced: `ERROR: unsafe use of new value ... HINT: New enum values
  must be committed before they can be used.` The middle file
  (`20260817120500_phase_12c_report_target_enum.sql`) exists **only** to be that transaction — do
  not fold it into either neighbour.
- **Extending the enum would have opened a hole in 9a on its own.** `reports_target_coerente` is a
  `case target_tipo ... end` with **no `else`**; a `case` with no match returns `NULL`, and a
  `CHECK` whose predicate is `NULL` **passes**. The bare `add value` would therefore have let a
  `post` report carry `target_listing_id`. Both constraints are redefined, and the new `else false`
  makes an eighth label added tomorrow **fail closed** instead of silently passing. Same shape, but
  benign, in `segnalazione_invia`'s `v_esiste`, which failed closed already.
- **`listing_id` has two overlapping conditions, read off the mock rather than assumed.** Always:
  the listing must be **publicly visible**, read from `public_listings` so "public" stays defined in
  one place. Additionally, when `tipo = 'annuncio'`: it must be **the author's own** — the mock's
  two `annuncio` posts are «**Vendo** Barolo Brunate 2018» and «**Vendo** Magnum Ornellaia 2017»
  (`frontend/src/data/communities.ts:179`, `:265`), where the post's author *is* the seller.
- **Removal is logical, never a physical DELETE**, and its only door is a `SECURITY DEFINER`
  function — none of `rimosso_at`/`rimosso_da`/`rimosso_motivo` is in any client **write** grant.
  Read side, measured on the real project 18 August 2026 and more precise than "outside every
  client grant" as this line first read: `authenticated` does hold `SELECT` on **`rimosso_at`**,
  which is what lets a reader be told a post was removed, while `rimosso_da` and `rimosso_motivo`
  are granted to nobody — who removed it and why stay inside moderation. The two
  actions are **new branches inside `moderazione_rimozione` and `moderazione_ripristino`**, not new
  RPCs: those already branch on `target_tipo` and would otherwise write the audit row **without
  removing anything**. No per-target "remove this post" door, because it would have no caller.
  This produces the **first `audit_log` row with `scope = 'club'`** — 9a created that label noting
  nothing could yet be born with it.
- **`private.scrittura_social_guard()` is reused unchanged** on all three tables. It is the 9b
  general guard, already mounted on `listings`, `messages`, `conversations` and (12a)
  `club_memberships` — not something found only on club tables. It is **not redefined**.
- **The rate limit lives in the same `SECURITY DEFINER` trigger as the cross-table checks**, so it
  binds every path including `service_role`: `club:post` **10/hour**, `club:risposta` **30/hour**,
  **no bucket for likes** (idempotent and reversible). Session values, reopenable on observed use,
  like Phase 10's three.
- **`rate_limit_exceeded` is now among the frontend's readable error codes** — but only in
  `phase12`. Without it the user reads the generic «Riprova» exactly when retrying will fail for an
  hour. Phases 7, 8 and 9 have the same gap and it is **not** closed here: their limits are
  per-minute, where "retry" is nearly right.
- **The grid was executed**: `supabase/tests/12bc_club_content_moderazione.sql`, **47 PASSA / 0
  FALLISCE** on PostgreSQL 15.19, after applying all 29 migrations from empty, each in its own
  transaction. Four runs — 25/42, 45/47, 46/47, 47/47 — and **none** of the failures was a
  migration defect: five classes of grid defect, none visible by reading. The most insidious:
  **SQL does not guarantee evaluation order of `and` operands**, so "write then verify" cases were
  passing by luck. It has **never** run on the real project, and doing so is a separate per-grid
  authorization — this one **writes**.
- **A test now enforces the 12b/12c bond**: `public-surface-contract.test.ts` asserts that the
  component rendering post and reply bodies is the one importing `ReportDialog`, with both
  `targetType="post"` and `targetType="commento"`, and that the allowed reasons match
  character-for-character between `data/moderation.ts` and the migration. The 12a test that
  asserted content writing was *closed* was rewritten onto the new, narrower boundary rather than
  deleted.
- **Deliberately absent**: no author-side delete of one's own post (so self-reporting a post stays
  possible and is an author's only route to review); no notifications on reply or like; no club
  `moderatore` role (7.1 stays deferred); no nested threads; no real poll behind the `sondaggio`
  type. `MIN_TESTS` 367 → **402**.
- **A pre-existing Phase 9 defect, recorded and NOT fixed here**: `report_reasons` holds the reasons
  **without accents** (`'Identita sospetta'`, 9a:107) while `data/moderation.ts:46` sends
  `"Identità sospetta"`, so that report fails the closed-list check. It affects `profilo` and other
  accented reasons, **not** `post`/`commento`, whose seven reasons are accent-free in both copies.

**Opening any further checkpoint stays a separate explicit approval**, and «no new features during
migration» keeps governing everything no session has admitted by name.

## Beta `frontend-next` production-like — **in produzione** dal 16 agosto 2026

La PR [#44](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/44) parte
da `origin/main` `f3f0155` ed è **mersa in squash come `8b003995`** il 16 agosto
2026 alle 12:04:44 UTC: la beta è pubblica su
`https://timely-lokum-43a12e.netlify.app`. **Non è un cutover** — `frontend/` +
`backend/` restano la versione servita e la beta è un sito separato — e non apre
la Fase 11. L'HEAD pre-documentazione `84b8767` aveva CI GitHub Actions verde —
run `31946914430`, #152 — e Deploy Preview pubblico
`https://deploy-preview-44--timely-lokum-43a12e.netlify.app`, deploy
`6a81acfbee2b64c77b28addc`. Il progetto Free `timely-lokum-43a12e` usa base
`frontend-next`, build `bun run build`, publish `.next` e runtime `Next.js`.

La beta separa visibilità e autorità. Le tre superfici IA sono visibili con
`NEXT_PUBLIC_AI_UI_ENABLED=true`, ma `NEXT_PUBLIC_AI_ACTIONS_ENABLED=false` e
`AI_ENABLED=false` fermano ogni azione prima del client/provider. Checkout e
packaging sono visibili, mentre `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED=false`,
`PAYMENTS_ENABLED=false` e `PACKAGING_ENABLED=false` bloccano ordine, Stripe,
prenotazioni, etichette e tracking. Solo la stringa esatta `true` abilita un
gate; i valori `NEXT_PUBLIC_*` non sono autorizzazione server. Il pannello demo
`SfondoIAPanel` non è raggiungibile nel target e `/community` restituisce 404.

Supabase Auth consente temporaneamente il callback del Deploy Preview oltre al
wildcard localhost. Netlify contiene le sole variabili pubbliche Supabase e i
flag previsti, senza service role, provider IA o segreti Stripe. Gli smoke
desktop e 390×844 hanno verificato catalogo e annuncio reali, noindex, 404 e i
blocchi IA senza chiamate Edge Function; i flussi autenticati reali restano
`NON ESEGUITO` perché non sono state create credenziali o fixture. `frontend/`,
`backend/`, migrazioni, function e Fase 11 restano invariati.

Dopo lo squash della #44 il callback Auth di produzione
`https://timely-lokum-43a12e.netlify.app/auth/callback` è stato aggiunto e
quello temporaneo del preview rimosso. Il rollback è il ripristino del
precedente deploy Netlify e non cancella dati Supabase.

### L'origine dei redirect Auth la decide il server — PR #45, binding

**Nessun percorso può costruire un redirect da un dato che arriva con la
richiesta.** `/auth/callback` lo faceva, da `request.nextUrl.origin`: i cookie
di sessione scritti da `exchangeCodeForSession` sono legati all'hostname, quindi
rispondere su un dominio diverso da quello su cui l'utente resta significa
scriverli dove nessuno andrà a rileggerli. L'ordine di risoluzione completo è in
`docs/ENVIRONMENT.md`; qui stanno i fatti che vincolano il codice futuro.

- **Su Netlify, a runtime, esiste la sola `URL`.** `CONTEXT`,
  `DEPLOY_PRIME_URL` e `AUTH_REDIRECT_ORIGIN` sono variabili di **build** e non
  sono leggibili da una route. Misurato con un header diagnostico temporaneo
  sulla Deploy Preview della #45, poi rimosso. Una regola che dipende dal solo
  `CONTEXT` **non scatta mai**: la prima stesura del modulo faceva così e
  mandava **in produzione** chi stava provando la preview — la regressione
  opposta a quella che la PR correggeva.
- **`request.nextUrl.origin` non è il dominio pubblico.** Sulla Deploy Preview
  vale il **dominio immutabile del deploy**
  (`6a81e37c…--timely-lokum-43a12e.netlify.app`), mentre `Host` e
  `x-forwarded-host` portano quello giusto: **il dominio buono sopravvive solo
  nell'intestazione**. In produzione i due coincidono, ed è la ragione per cui
  cinque sonde sul callback pubblico non mostravano niente — **il sintomo
  esiste dove i due valori divergono**, e va cercato lì.
- **L'alias Netlify accettato è un elenco chiuso derivato da `URL`**, mai
  dall'`Host` creduto sulla parola: forma `<qualcosa>--<nome-sito>.netlify.app`
  con il nome del sito preso dal server, e **dominio immutabile escluso a
  parte** per prefisso di ventiquattro cifre esadecimali. Un host falsificato
  vale al massimo un altro deploy nostro, mai un dominio di terzi.
- **`X-Vinea-Origine-Sorgente` nomina la regola che ha deciso, mai un valore di
  ambiente.** Non è ornamento: su Netlify l'origine del server e quella della
  richiesta coincidono, quindi dal solo `Location` una risoluzione sbagliata
  passa per corretta. È l'header che ha reso visibile la regressione qui sopra.
- **Un `next` filtrato con il solo `startsWith("/")` è un redirect aperto**:
  `//host` e `/\host` sembrano relativi e i browser li leggono come assoluti
  verso un altro host — il secondo perché negli schemi speciali la barra
  rovesciata è normalizzata in barra.

`AUTH_REDIRECT_ORIGIN` è **solo server**, non `NEXT_PUBLIC_*`, e su Netlify si
lascia vuota. `MIN_TESTS` da 315 a **341**.

### Registrazione e profilo: correzione delle Fasi 5a/5b — PR #50, mersa

[PR #50](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/50), base
`3a6ba69`, 18 agosto 2026. **Non è una fase nuova**: è correzione e
completamento delle Fasi **5a** e **5b**, chiuse il 28 luglio 2026 con le PR #6
e #7, e va registrata come nota e non come numero di fase — precedente la **#45**,
che corresse un difetto della beta senza aprirne uno, e la #39 per la Fase 10.
Aprire un numero avrebbe rotto la corrispondenza fra numero e dominio su cui
poggia l'ordine di dipendenza, e promesso una sessione organizzativa che nessuno
ha tenuto. Ventisei file, **zero sotto `supabase/migrations/`**.

Cosa fissa in modo vincolante per il lavoro futuro:

- **La destinazione di rientro Auth si compone in un posto solo**,
  `frontend-next/src/lib/auth/ritorno-auth.ts`, per i tre flussi che rientrano
  con un `code` (`registra`, `inviaMagicLink`, `accediConOAuth`). Il difetto
  corretto è che `registra()` e `inviaMagicLink()` mandavano
  `window.location.origin` **nudo**: Supabase confronta il valore con l'elenco
  «Redirect URLs» e, non trovando corrispondenza, **non rifiuta** — ricade in
  silenzio sul Site URL. Un errore di configurazione qui non produce un
  messaggio, produce un utente su un dominio sbagliato. È anche la destinazione
  sbagliata di per sé: il client è PKCE, quindi il link torna con un `?code=`
  che **solo `/auth/callback` scambia**.
- **La configurazione Auth del progetto reale è stata cambiata il 18 agosto
  2026**, su autorizzazione esplicita: Site URL `http://localhost:3000` →
  `https://timely-lokum-43a12e.netlify.app`, più
  `https://timely-lokum-43a12e.netlify.app/**` fra i Redirect URLs, che passano
  a tre voci. **Nessun wildcard sulle Deploy Preview**, per decisione: il jolly
  copre un segmento arbitrario e ogni preview di qualunque PR diventerebbe una
  destinazione valida per un token di sessione. Tabelle prima/dopo, misurate con
  la stessa sonda di sola lettura, in `docs/ENVIRONMENT.md`.
- **La configurazione Auth remota non ha un canale MCP né CLI in questo
  ambiente**: si tocca dalla dashboard con la sessione reale, una impostazione
  alla volta e rileggendo. **Mai `supabase config push`**, che spingerebbe
  l'intero blocco `[auth]` di `config.toml` — dove `site_url` è
  `http://127.0.0.1:3000`, diverso da quello di produzione, il che dimostra che
  quel file non è la leva del progetto reale.
- **Lettura e scrittura del profilo escono da `AuthService` e stanno in
  `ProfileService`**, così `profiles` ha una porta sola. Il contratto **non ha
  `userId` in firma**: la riga è quella di `auth.uid()`, risolta dalla sessione
  dentro il servizio. Sostituisce una `ProfileService` dimostrativa mai
  implementata, come la Fase 10 fece con `AiService`.
- **Nessuna migrazione, e questo è verificato non assunto**: `bio`, `citta`,
  `provincia`, `esperienza` e `avatar_url` sono già tutte nel `GRANT UPDATE` per
  colonna della 9b, e `profiles_update_own` esiste dalla 5a.
- **Gli avatar sono un insieme curato servito da noi**, sei SVG in
  `public/avatar/`, e la lettura passa da `avatarSicuro()` con elenco chiuso —
  `avatar_url` è scrivibile dal client, quindi un URL esterno memorizzato lì
  trasformerebbe la scheda in un tracciatore per chi la apre. Il caricamento di
  una foto propria è rimandato: un bucket nuovo riapre le domande che la Fase 11
  chiuse in sessione per `foto-ai` — privato/pubblico, MIME, orfani, **spoglio
  EXIF** — e la migrazione che lo crea si applicherebbe da sé al merge (7.10).
- **Il consenso a Termini e Privacy non è registrato da nessuna parte**, e non lo
  era già prima nemmeno per il percorso email, dove la casella è un requisito del
  pulsante e nient'altro. `/completa-profilo` ora lo chiede anche a chi entra da
  Google o Facebook, quindi i due percorsi sono **pari** — pari a zero. La
  colonna è scritta e **non applicata** in
  `supabase/queries/03_PROPOSTA_NON_ESEGUIRE_CONSENSO_TERMINI.sql`, in due
  varianti: **rinviata alla revisione legale per decisione esplicita del
  18 agosto 2026**, perché se basti l'istante o serva anche la versione del testo
  accettato è ciò che la §9 della spec Fase 11 deve dire.
- `MIN_TESTS` 402 → **433**.

**Provato end-to-end il 18 agosto 2026, e la correzione regge**: quando l'email
arriva davvero, il link riporta su `/auth/callback` e il giro si chiude. Va fatto
**sul dominio di produzione** — le preview restano fuori dai Redirect URLs,
quindi lì fallirebbe per configurazione e non per un difetto. Limite noto e non
una regressione: con PKCE il `code_verifier` sta nel browser da cui è partita la
registrazione, quindi chi apre l'email su un **altro dispositivo** non completa
lo scambio (vale identico per OAuth) e finisce su `/accedi?errore=…`, che è dove
deve andare, visto che la conferma lato server è già avvenuta.

**Le email di conferma però spesso non partono, e la causa è nota**:
`over_email_send_rate_limit` del mailer di prova incorporato in Supabase, poche
email l'ora perché è pensato per lo sviluppo e non per il traffico reale. **Non è
un difetto del codice della #50** e non va indagato di nuovo. Il rimedio è un SMTP
proprio, ed è **rimandato per una ragione precisa**: attivare Resend richiede di
verificare via DNS un dominio, e `timely-lokum-43a12e.netlify.app` è assegnato da
Netlify, non è nostro e non è verificabile. La configurazione SMTP si fa quando la
beta avrà **un dominio custom** — quello è il prerequisito, non la scelta del
fornitore.

### La distribuzione delle migrazioni non è il merge, è la corsa dell'integrazione — PR #51

Documentazione soltanto, 18 agosto 2026, aperta subito dopo il merge della #50 e
nata da una sua verifica post-merge. Il fatto, misurato su
`repos/…/commits/<sha>/check-runs` per i tre merge della Fase 12 e non su
`gh pr checks`:

| merge | quando (UTC) | corsa `Supabase Preview` sul commit di merge |
|---|---|---|
| #48 `e2132ee` — una migrazione | 07:58:49 | `success`, partita 07:59:19 — **+30 s** |
| #49 `3a6ba69` — **tre** migrazioni | 17:50:10 | **assente**: quattro check, nessuno suo |
| #50 `6b0e999` — **zero** migrazioni | 23:16:44 | `success`, 23:17:15 → 23:17:29 — **+31 s** |

Le tre migrazioni 12b/12c sono quindi rimaste su `main` e **fuori dalla produzione
per 5h 27m 05s**, e a distribuirle è stata la corsa innescata dal merge di una PR
che non ne conteneva nessuna. Riletto dopo: ledger a **29 righe**, ultima
`20260817121000 phase_12c_club_moderation`, coincidenti con i **29 file** di
`supabase/migrations/` su `origin/main`. Le sei Edge Function sono ripartite
insieme — **30/29/29 e 16/16/16**, un solo `updated_at`
`2026-08-17T23:17:27.365Z`, **43,4 s** dopo il merge: sul redeploy la 7.10 è
misurata una **nona** volta e non ha mai saltato un giro.

Quello che cambia è scritto dove la regola vive, nel punto dell'eccezione della
#47 sopra: il confine «zero file sotto `supabase/migrations/`» **resta dov'è**,
perché risponde ancora alla domanda che l'eccezione pone davvero — *questa PR
aggiunge SQL suo?* — ma la motivazione «arriva sul progetto reale nello stesso
istante» era troppo forte, e **il controllo è rileggere il ledger dopo il merge**
invece di dare l'applicazione per avvenuta. Il caso della #49 sfugge a entrambe le
reti che c'erano: il `Supabase Preview` della PR era `skipped` — «This git branch
is not associated with any Supabase Branch» — quindi quelle tre migrazioni non
sono **mai** state eseguite da Supabase su un database suo prima di arrivare in
produzione, e l'unica esecuzione reale resta la griglia locale su PostgreSQL
15.19, 47 PASSA / 0 FALLISCE.

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

### PostgREST sceglie la transazione dalla volatilità, non dal verbo — PR #52

Correzione di un difetto in produzione della **Fase 8**, non una fase nuova: va
registrata come nota, come la #50 per le Fasi 5a/5b e la #45 per la beta. Per
undici giorni, dal merge della #27, **ogni pagina caricata da un utente
autenticato riceveva 405** dalle RPC di lettura di messaggi e notifiche.

**La causa non è il verbo, ed è un'interazione fra due fasi.** L'hook
`pgrst.db_pre_request = private.vinea_check_request` montato dalla **Fase 7**
(`20260731135455…:140`) gira dentro la transazione di *ogni* richiesta e consuma
un bucket di rate limit — cioè una `insert` — per ogni metodo diverso da
`GET`/`HEAD`/`OPTIONS`. Ma **PostgREST sceglie `READ ONLY` o `READ WRITE` dalla
volatilità della funzione chiamata, non dal verbo HTTP**: una RPC dichiarata
`stable` gira in transazione di sola lettura *anche* chiamata in POST, che è come
`supabase-js` chiama sempre `.rpc()`. La insert falliva con `25006`
(`read_only_sql_transaction`), che **PostgREST traduce in `405 Method Not
Allowed`** — ed è il motivo per cui il sintomo non somigliava alla causa.

L'hook filtrava sul **metodo HTTP**, ma la proprietà che decide è **il modo della
transazione**. Fino alla Fase 7 le due cose non si erano mai separate, perché
ogni POST cadeva su funzioni `volatile`. **Chi scrive una RPC `stable` d'ora in
poi tenga presente che è questo, e non il verbo, a determinare cosa può scrivere
durante quella richiesta.**

Quello che il lavoro fissa in modo vincolante:

- **Le funzioni colpite erano quattro, non tre**, e sono tutte e sole le `stable`
  della Fase 8 chiamate dal frontend: `conversations_page`, `notifications_page`,
  `messages_page`, `notifications_unread_count`. **`conversation_open` non era fra
  queste**: è `volatile`, non compare mai nei log, e non veniva raggiunta perché
  `/messaggi` moriva sull'elenco prima. Era un'inferenza, non una misura.
- **La controprova isola la sola volatilità**, con chiamate dirette fuori dal
  frontend e la sola chiave anon: `stable` in POST → `405`/`25006`; `volatile` in
  POST → `401`/`42501`, cioè l'hook è passato e la funzione è stata raggiunta. Lo
  **stesso** endpoint `stable` chiamato in **GET** → `401`/`42501`. Unica
  variabile mossa: la volatilità.
- **Esclusa per misura, non per ragionamento, l'ipotesi che somiglia di più al
  messaggio d'errore**: database in sola lettura per quota disco del piano Free.
  Se lo fosse, anche `conversation_open` e `message_send` in POST fallirebbero
  con `25006`, e invece arrivano al controllo dei permessi;
  `private.rate_limit_buckets` aveva 14 righe scritte da quello stesso hook.
- **La correzione è un file nuovo**,
  `20260818090000_phase_8_fix_pre_request_read_only.sql`: la 20260731135455 è
  spinta, quindi congelata. Aggiunge all'hook l'uscita quando
  `current_setting('transaction_read_only', true) = 'on'`. **Non apre un buco**:
  una transazione di sola lettura non può mutare niente, quindi nessuna scrittura
  sfugge al tetto, e le letture questo hook non le ha mai contate — è ciò che
  dichiara già il ramo `GET`/`HEAD`/`OPTIONS`.
- **È applicata e verificata in produzione**, non solo scritta. La #52 è mersa in
  squash come `dde9b52` il 18 agosto 2026 alle 09:22:03 UTC; il ledger reale è a
  **30 righe** e il corpo della funzione è davvero cambiato — `md5` da
  `f58d62a0…` a `99287d28…`, e la definizione contiene `transaction_read_only`.
  La griglia rieseguita dà **9 PASSA / 0 FALLISCE**, con il caso [5] che passa.
  Con un JWT reale le quattro RPC rispondono `200`, `200`, `200` e — su un id
  inesistente — `403`/`42501`, che è la funzione raggiunta che rifiuta.
  `conversation_open` dà `400`/`P0001`: **conferma che non era fra le colpite** e
  che l'errore riportato su di essa era un effetto a cascata lato client.
  `private.rate_limit_buckets` resta a **14 righe** dopo quelle quattro letture,
  che è il tetto sulle scritture intatto e non allentato.
- **La consegna end-to-end non è mai stata esercitata**, né prima né dopo: le
  quattro tabelle sono a zero righe e aprire una conversazione richiede un
  annuncio altrui, cioè una fixture. Il 405 è chiuso; la parità di comportamento
  della fase resta **non misurata**, che non è la stessa cosa di «funziona».
- **Una griglia eseguita nel SQL Editor non può vedere questa classe di difetto**,
  ed è perché la Fase 8 passava verde con il difetto in produzione: una sessione
  Postgres diretta non passa da PostgREST, quindi non incontra né l'hook né la
  transazione di sola lettura. `supabase/tests/8_fix_pre_request_read_only.sql`
  chiude il buco con `set transaction read only`, che è la sola riga che riproduce
  in SQL ciò che PostgREST fa da solo. **È stata eseguita sul progetto reale prima
  della correzione — 8 PASSA / 1 FALLISCE, l'unico fallimento è il caso [5], che è
  il difetto** — e non scrive nulla: unica griglia del repository di cui si possa
  dire senza distinguo.
- **La lacuna Realtime di `CHANGES.log` confondeva due meccanismi.**
  L'**autorizzazione** è in produzione: `realtime.messages` ha RLS e la policy
  `vinea_phase8_private_broadcast_select`, che ammette esattamente i due topic
  legittimi. Nessuna policy di `INSERT` perché nessun client pubblica — i
  broadcast li emette il database con `realtime.send()` da trigger. La
  pubblicazione `supabase_realtime` ha **zero tabelle**. **E anche la restrizione
  ai soli canali privati era già in vigore**, verificata in dashboard da Enrico il
  18 agosto 2026: l'interruttore si chiama **«Allow public access to channels»**,
  è **disattivato**, e la sua descrizione dice che se disabilitato saranno ammessi
  solo canali privati. È l'inverso lessicale di «`private_only` da accendere», ma
  lo stesso stato di fatto — **non c'era niente da accendere e qui non c'è mai
  stato un gap**. Non è leggibile né scrivibile da SQL o MCP: il canale è la
  dashboard, come per la configurazione Auth della #50. Chi rilegge non riapra la
  voce per un fraintendimento del nome; e comunque il client apre **solo** canali
  privati (`realtime.ts:123`, `:131`, `:137`).
- **`MessagingService` e `NotificationService` in `types.ts` sono già nella forma
  della Fase 8** — `Result<T>`, cursori, nessun `userId` — e sono quelle che gli
  adapter implementano. Non c'è interfaccia morta lì. Il difetto di forma esiste
  ma è di **`ModerationService`** (`types.ts:1145`), promesse nude e `userId` in
  firma: è Fase 9, e non si tocca qui.

### Ciclo di vita dell'annuncio: rimozione, modifica, riuso delle foto — PR #54

**Mersa in squash come `1783779` il 18 agosto 2026 alle 17:45:13 UTC**, e la migrazione è in
produzione. Tre job CI `success`, `mergeable: MERGEABLE` e `mergeStateStatus: CLEAN` letti **sul
commit di testa** `4fb898d`. Il ledger passa da **30 a 31 righe** — ultima
`20260819090000 annuncio_modifica_attivo`, coincidente con i 31 file su `main` — e a distribuirla
è stata la corsa innescata da **questo** merge: `Supabase Preview` è partito **+33 s** dopo ed è
`success`. **Non è il caso della #49.** Che l'oggetto sia cambiato è misurato e non dedotto dalla
riga di ledger, com'è la lezione della #52: `using` con i tre stati, `with_check` invariato, tre
policy, trigger `BEFORE INSERT OR UPDATE`, e `GRANT UPDATE` per `authenticated` **fermo alle otto
colonne di contenuto**. Le sei Edge Function sono ripartite insieme — 34/33/33 e 20/20/20, un solo
`updated_at`, **44,5 s** dopo il merge: **decima** misura della 7.10, mai saltata.

Hardening, **non una fase nuova**: va registrata come nota, come la #45 per la beta, la #50 per
le Fasi 5a/5b e la #52 per la Fase 8. Nessuna sessione organizzativa ha assegnato un numero a
questo lavoro, e nel repository non ne esiste traccia — cercato e verificato, non assunto.

Quello che il lavoro fissa in modo vincolante:

- **`listings_select_pubblici` NON esiste sul progetto reale.** `pg_policy` su `public.listings`
  restituisce **tre** policy — `listings_insert_own`, `listings_select_own`, `listings_update_own`
  — e la lettura pubblica passa dalla vista `public_listings` (`security_invoker = off`), com'è la
  regola di esposizione della 6d-1. Chi legge una premessa che nomina quella policy la corregga:
  una sospensione toglie la riga **dalla vista**, non da una policy, e `listings_select_own` non
  guarda lo stato — quindi **il proprietario la sua riga ce l'ha sempre**, in qualunque stato.
- **La lettura del proprietario non richiede schema nuovo, ed è misurato.** I tre `GRANT SELECT`
  che servono esistono già (`listings`, `bottle_units`, `wines`) e le tre policy di lettura
  lasciano passare la catena per il proprietario. L'innesto su `profiles` **deve nominare il
  vincolo** (`profiles!listings_seller_id_fkey`): da `listings` partono **tre** chiavi esterne
  verso `profiles` — `seller_id`, `reserved_by`, `stato_aggiornato_da` — e un innesto ambiguo non
  è un valore sbagliato, è un errore in faccia a chi apre la pagina.
- **`anon` non ha NESSUN grant su `public.listings`.** Una lettura di quella tabella fatta senza
  sessione non torna vuota: torna `42501 permission denied`, perché il permesso di tabella viene
  **prima** della RLS. Chi scrive una lettura "tanto la RLS filtra" su una tabella senza grant per
  `anon` sta scrivendo un errore nei log a ogni richiesta anonima. Trovato aprendo la pagina, non
  leggendo il codice.
- **`sospeso` è terminale, e la UI lo dice prima di agire.** Tre misure: l'indice
  `listings_un_solo_annuncio_non_terminale` non lo copre; `listing_pubblica` riparte solo da
  `bozza`/`modifiche_richieste`; nessuna funzione riporta un annuncio ad `attivo` all'infuori di
  `listing_pubblica` e delle due del checkout, nessuna raggiungibile da `sospeso`. **La
  riattivazione non esiste e non è stata costruita**: per rivendere si crea un annuncio nuovo, il
  che è possibile proprio perché lo stato è terminale e libera la bottiglia dall'indice. Renderlo
  non terminale cambierebbe il significato di quell'indice, quindi è una decisione di dominio con
  una sessione propria.
- **La modifica di un annuncio attivo è applicata**, dalla migrazione
  `supabase/migrations/20260819090000_annuncio_modifica_attivo.sql`, autorizzata **per nome e con
  entrambi gli statement insieme** dalla sessione di coordinamento del **18 agosto 2026**. Il file
  è nato come proposta in `supabase/queries/` e stava lì per una ragione che resta valida per la
  prossima: sotto `supabase/migrations/` il merge lo applica da sé (7.10) **e** il ramo di preview
  lo eseguirebbe all'apertura della PR, cioè prima della revisione. Una proposta cambia cartella
  quando la revisione è avvenuta, non prima — è la stessa collocazione, e la stessa ragione, della
  proposta di fixture della 12a e di quella sul consenso, che invece restano lì.
- **Quella migrazione contiene DUE statement, e il secondo non era nella richiesta.**
  `listings_scrittura_social_guard` era montato **BEFORE INSERT soltanto** su `listings`, mentre su
  `messages` e sulle tre tabelle dei club copre anche l'UPDATE. È stato innocuo finché
  `listings_update_own` si fermava alle bozze, che nessun estraneo vede. Con `attivo` ammesso, un
  utente **sospeso al primo livello** potrebbe riscrivere prezzo e testo di un annuncio pubblico —
  la scrittura social che la 7.6b gli toglie. **Chi applicasse solo il primo statement aprirebbe un
  buco nella 9b**, e per questo non si dividono: un test lo pretende dal file. Il corpo della
  funzione non si tocca: ricava l'attore da `seller_id` via `to_jsonb(new)`, che su UPDATE c'è
  identico.
- **`STATI_MODIFICABILI` e quella policy si muovono insieme, e un test lo impone in entrambe le
  direzioni.** Un pulsante che scrive dove la policy non fa passare non solleva niente: l'UPDATE
  aggiorna **zero righe e riporta `ok`**. È il difetto peggiore della categoria, perché è
  silenzioso — e non è teoria: la corsa di controllo della griglia lo ha visto succedere ai casi
  `[3]` e `[4]`, che passavano **anche senza** la migrazione. A misurare la modifica è `[3b]`, che
  rilegge il valore. Chi tocca quei casi non tolga `[3b]` credendo che `[3]` gli basti.
- **Le foto di una bottiglia si COPIANO da `cantina` ad `annunci`, non si referenziano.** `cantina`
  è privato e si legge con URL firmato; `annunci` è pubblico e `listings.immagini` viene ricomposto
  in URL pubblico da `urlImmagine()`. Un percorso di `cantina` dentro `listings.immagini` darebbe
  un URL pubblico verso un oggetto che lì non esiste. E puntare l'annuncio al file privato non è
  comunque una scelta disponibile: sarebbe pubblicare la cantina di qualcuno per il fatto di
  averla messa in vendita una volta. **Il client manda solo l'id della bottiglia**; i percorsi li
  legge il server e la RLS decide se quella riga è sua — stessa ragione per cui `firmaUploadFoto`
  costruisce il percorso invece di accettarlo.
- **Il disallineamento fra card e scheda è misurato sui dati reali.** `sabbioni-i-rifugi-2017`,
  l'unico annuncio creato davvero da un utente attraverso il wizard, ha `listings.immagini = []`
  mentre la sua bottiglia ha una foto nel bucket `cantina`; le due scritture distano tre minuti.
  In Cantina la bottiglia si vede, perché `rigaAVino()` ripiega sulle foto di cantina quando
  l'annuncio non ne ha (`cellar-service.ts:258-264`); nella scheda pubblica no, perché
  `public_listings` non ha ripiego e `rigaAWine()` mette il segnaposto. **Quella è la radice, e il
  riuso la chiude alla sorgente** — non riscrive gli annunci già nati vuoti, che restano da
  correggere a mano o con il comando di modifica, che dal 18 agosto 2026 funziona anche su un annuncio attivo.
- **Il prezzo ereditato si propone compilato ma non si pubblica senza conferma.** Fra il vecchio
  annuncio e il nuovo può essere passato molto tempo: il lavoro risparmiato resta risparmiato, la
  decisione resta del venditore.
- **La griglia è stata ESEGUITA prima del merge, e la corsa di controllo conta quanto quella
  verde.** `supabase/tests/annuncio_modifica_attivo.sql` è girata su un **branch di anteprima
  Supabase** creato per questo, nato dalle trenta migrazioni di produzione, **PostgreSQL 17.6** —
  la famiglia del progetto reale, non il 15.19 locale della 12b/12c. **Due corse: 7 PASSA /
  5 FALLISCE senza la migrazione, 12 PASSA / 0 FALLISCE con essa.** La prima serve a escludere una
  griglia verde in entrambi i casi, che non misurerebbe nulla, ed è quella che ha trovato i due
  difetti descritti sopra e qui sotto. **Sul progetto reale non è girata**, e resta
  un'autorizzazione separata per griglia: questa **scrive**. Chi apre una griglia nuova prenda
  questo giro come forma — applicare su un ramo usa-e-getta e misurare due volte costa un branch a
  ore e chiude la regola della 7e senza toccare la produzione.
- **Una griglia SQL non vede la classe di difetto della #52, e questa nemmeno.** Una sessione
  Postgres diretta non passa da PostgREST: se la modifica di un annuncio attivo rispondesse `405`
  per la volatilità di una funzione, qui sarebbe invisibile. **Il percorso del client va provato dal
  client**, e non lo è stato.
- `MIN_TESTS` 433 → **451**. Un test lega `STATI_MODIFICABILI` alla migrazione **in entrambe le
  direzioni** — protesta sia se l'elenco si allarga senza il file sia se il file arriva senza
  l'elenco — e un altro pretende che la griglia porti in testa i numeri di **entrambe** le corse,
  così che nessuno la riporti a «mai eseguita» per distrazione.
- **Debito noto accettato, non risolto**: un annuncio attivo modificato **non ritorna in revisione**.
  Accettato dalla sessione di coordinamento del 18 agosto 2026 per questa migrazione, con la
  richiesta esplicita di scriverlo invece di lasciarlo implicito; se le modifiche sostanziali debbano
  far ripassare per approvazione è una domanda per una fase successiva. Le altre due conseguenze
  accettate allo stesso modo: il prezzo può cambiare fra visualizzazione e checkout, e una modifica
  non lascia traccia di cosa ci fosse prima.
