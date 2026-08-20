# CLAUDE.md

Operational constitution for agents working in the Vinea repository. Keep this
file concise and current. Pull-request history, incident narratives and dated
measurements belong in `CONTESTO_IA/` or the relevant document under `docs/`.

## Bootstrap

1. Read this file, then `CHANGES.log`.
2. Run `git status --short --branch`, inspect the current branch/worktree and
   preserve local work that is not yours.
3. Read `CONTESTO_IA/README.md` only to route any additional, task-specific
   context. Do not load the whole historical archive by default.
4. For migration work, read `docs/ROADMAP_V1.md`,
   `docs/MIGRATION_PHASE_1_BACKLOG.md`, ADR 001/002 and the relevant domain
   migrations/specification before editing.
5. Verify facts that can drift — Git state, CI, remote schema, deployment state,
   feature flags — instead of trusting an old narrative.

Vinea is mid-migration:

```text
frontend/       React 19 + TanStack Start — current served frontend
backend/        FastAPI + MongoDB — current served backend, transitional
frontend-next/  Next.js App Router + Supabase — target frontend and separate beta
supabase/       PostgreSQL/RLS/Auth/Storage/Edge Functions for the target stack
docs/           architecture, security, environment, roadmap and specifications
CONTESTO_IA/    durable structural and dated historical memory
```

`frontend/` + `backend/` remain the served product. The public
`frontend-next/` beta is not the cutover. Never assume the target stack is the
production authority for a domain without checking the roadmap and code.

## Source hierarchy

When sources conflict, use this order:

1. current user instructions and the explicit scope of the current task;
2. this current constitution;
3. `CHANGES.log` for current operational state and near-term blockers;
4. code, migrations, Git/CI state and measured runtime facts;
5. current ADRs, security/environment documentation and roadmap;
6. `CONTESTO_IA/` and dated specifications, minutes, reports and archived
   prompts as durable history.

A dated record remains evidence of what was decided or observed then; it does
not override a newer current rule. Do not rewrite history to pretend an old
approval rule never existed. Classify it as historical and apply the current
constitution. `CONTESTO_IA/context-manifest.json` is a dated, non-authoritative
snapshot.

## Agent autonomy and scope

An agent with the required tools is autonomously authorized to complete the
normal technical lifecycle:

`branch → implementation → tests → commit → push → PR → CI → CI fixes → merge → post-merge verification`

This authorization also applies to PRs containing migrations. Normal Git and
Supabase operations do not require per-command or per-PR user confirmation.
Autonomy is permission to execute approved scope, not permission to invent
scope.

The agent may autonomously create and apply migrations; change schema, RPCs,
triggers, RLS and Storage policies; deploy Edge Functions; create the technical
fixtures required by the task; and perform remote verification, when the task
requires those operations and the environment provides the necessary tools.

The following remain product or organizational decisions, not command-level
approval gates:

- admitting a new feature during the migration;
- opening a new migration phase when the roadmap requires an organizational
  decision;
- changing a closed product, legal, commercial or provider decision;
- Phase 13 cutover from `frontend/` + `backend/` to the target stack.

“No new features during migration” remains active except for features admitted
explicitly by name. Phase order is dependency order:

`Auth (5) → Listings/Catalog (6) → Orders/Payments (7) → Messaging (8) → Moderation (9) → AI (10) → AI extensions (11) → Club/Community (12) → Cutover (13)`

Phase 12 is Club/Community. Phase 13 is Cutover. The cutover is separate and
never follows automatically from a green PR or the completion of earlier
phases.

## Git workflow

- Never implement directly on `main`; start from an updated default branch on a
  dedicated branch or existing task worktree.
- Preserve uncommitted work, untracked files, stashes and other worktrees. Do
  not clean, reset, delete or overwrite work you did not create.
- Keep commits small, descriptive and limited to one logical change.
- Push the branch, open/update the PR, inspect the exact head SHA and run the
  relevant checks. Fix failures rather than bypassing them.
- The normal repository merge method is squash. Agent autonomy replaces the old
  confirmation gate; it does not relax CI or repository integrity.
- Before merge, make the branch documentation describe the state the PR will
  produce. Always update `CHANGES.log`; update this constitution only when an
  operative invariant changes; update the relevant durable history/router when
  the change needs long-lived context. Documentation updates should be the last
  logical commit before merge.
- Merge only when relevant checks are green and GitHub reports the head as
  mergeable/clean. After merge, fetch `origin/main` and verify the final files
  and deployment/runtime effects from the remote default branch.

Always forbidden:

- force-pushing or rewriting `main`;
- deliberately bypassing CI or hooks;
- destroying another person’s or agent’s work;
- merging while knowing a relevant check fails.

## Supabase workflow

Technical Supabase work within task scope is autonomous, including production
operations. Apply these safeguards every time:

1. Verify the exact project ref, branch/environment and current remote state
   before any write. Never infer production from a local config filename.
2. Use migration-first schema evolution. Commit the migration and its RLS,
   grants, tests and documentation together.
3. A migration file that has been pushed or distributed at least once is
   frozen, including drafts and preview branches. Correct it with a newer
   timestamped migration; never edit the old version in place.
4. After API/MCP migration application, reconcile any server-assigned version
   with the local filename and reread migration history.
5. Never disable RLS globally for convenience. Design the narrow policy,
   privilege or `SECURITY DEFINER` door the domain needs.
6. Never commit secrets. New environment variables require the relevant
   `.env.example` and `docs/ENVIRONMENT.md` in the same change.
7. Do not arbitrarily delete or rewrite real user data. Technical fixtures must
   be required by the task, minimized, isolated, cleaned on success and error,
   and followed by residue verification. Deliberately preserved residues must
   be reported.
8. Verify the effective schema, policies, functions, Storage objects and
   behavior after deployment. A ledger row alone does not prove the object body
   is correct.

A PR merge does **not** prove that its migrations were applied. The Supabase
integration run may fail to start; a backlog can be applied by a later,
unrelated merge. Wait for the integration, then reread the production migration
ledger and compare it with migration files on `origin/main`. Edge Functions may
also redeploy on a merge that does not touch their source, so verify their state
and configure fail-closed environments before a merge that can activate them.

For this repository, once a domain moves to Supabase it has one authoritative
writer. Legacy reads may remain only when explicitly planned; two writable
sources of truth are forbidden.

## Security invariants

### Trust boundaries

- The frontend is never a trust boundary. It cannot assign roles, confirm a
  payment, or supply authoritative price, currency, owner or commission.
- Identity, ownership, state and authorization are resolved server-side or in
  the database on every privileged operation.
- A payment is trusted only from `payment_status=paid` plus a signed,
  deduplicated Stripe webhook. Checkout `status=complete` is insufficient.
- CORS and redirect origins are explicit full-origin allowlists; never `*`,
  substring or suffix matching in shared/production environments.
- Private AI history, orders, transactions, conversations and notifications are
  owner-scoped or explicitly role-scoped, with applicable TTL and size caps.
- Auth, AI and payment providers stay behind injectable interfaces so tests use
  fakes without network or real credentials.

### PostgreSQL exposure

RLS filters rows, never columns:

- Do not grant whole-table reads to a client role that can reach non-owned rows.
- Public reads use `security_invoker = off` views with explicit closed column
  lists. A newly added base-table column remains private until deliberately
  exposed.
- Domain-controlled columns are absent from client write grants and are changed
  only through a checked `SECURITY DEFINER` function.
- Cross-table invariants also use triggers so privileged writers are bound.
- Privileged functions verify `auth.uid()`, ownership and state, use a safe
  `search_path`, and do not receive broad `anon` execution rights.
- Never use `public.has_role()` inside a caller-privilege RLS policy where the
  caller lacks `SELECT` on `user_roles`; use the established checked door for
  that domain.

### Money

- Platform markup is calculated server-side and frozen on the order together
  with the parameters that produced it. Later config changes do not move an
  existing order.
- The charge carries neither `transfer_data` nor `on_behalf_of`; funds stay on
  the platform balance and the seller Transfer is created separately at
  release, for the seller price only.
- `charges_enabled`, `payouts_enabled` and derived seller capability roles are
  written only from signed provider events, never from seller requests.
- Payment completion paths must not react to moderation state in a way that can
  freeze already-paid funds without an exit.

## Invariant technical conventions

- Both frontends use **Bun 1.3.14 only** and their committed lockfiles. Do not add
  another package manager or lockfile.
- `frontend/` and `frontend-next/` intentionally share many components. When
  porting for parity, diff against the served version instead of rewriting.
- Service contracts are in `frontend-next/src/services/types.ts`; Supabase
  implementations are adapters behind them.
- Real Supabase auth and the demo Guest/User/Admin switcher intentionally
  coexist until their dependent domains migrate.
- Signup profile creation is a PostgreSQL trigger, not a client `INSERT`.
- Auth return destinations are composed through the existing server/client auth
  helpers. Never derive a trusted redirect origin from unvalidated request data.
- Keep feature flags fail-closed: only the exact string `true` enables gates
  that use that convention.

### PostgreSQL enum assignments

Never assign a bare `CASE` of string literals to an enum column. PostgreSQL
resolves the expression as `text`, causing `42804`. Read the exact enum type from
`pg_type`, verify every label exists, and cast **both** branches:

```sql
case
  when ... then 'consegnato'::public.order_stato
  else 'rimborsato'::public.order_stato
end
```

Casting a nonexistent label merely moves the defect to runtime (`22P02`).

### PostgREST transaction mode

PostgREST chooses read-only/read-write transaction mode from function
volatility, not the HTTP verb. A `stable` RPC called with POST still runs read
only. Request hooks that may write must exit on:

```sql
current_setting('transaction_read_only', true) = 'on'
```

The second argument is boolean `true`, not the string `'on'`. Direct SQL grids
do not pass through PostgREST; test the client/RPC path when that distinction
matters.

## Testing and definition of done

Run the smallest relevant check first, then the full affected stack before
merge. CI has independent `frontend`, `frontend-next` and `backend` jobs; all
relevant jobs must pass.

### `frontend/`

```bash
cd frontend
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

### `frontend-next/`

```bash
cd frontend-next
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
bun run build
```

The target frontend test job enforces a minimum test-count floor defined in
`.github/workflows/ci.yml`. Raise it deliberately when tests are added; never
lower it as housekeeping. Tests are type-checked.

### `backend/`

```bash
cd backend
python -m compileall -q .
python -m ruff check .
python -m pytest -q
```

Backend tests run with `APP_ENV=test`, no network, no real MongoDB and no real
Stripe/AI credentials; use the fakes in `backend/tests/conftest.py`.

Supabase grids under `supabase/tests/` are versioned manual proofs, not CI. A
grid that has never executed is not evidence. Record environment/version,
before/after control runs when applicable, pass/fail counts, cleanup and
residues. SQL Editor tests do not cover PostgREST or browser behavior.

A change is done when it is typed and readable; permissions are enforced
server-side; errors do not leak internals; deterministic tests exist; relevant
lint/typecheck/test/build checks pass; docs/env examples are aligned; no secret
or temporary-preview dependency is introduced; and remote effects are verified
when the task changes them.

## Handoff

`CHANGES.log` is the only mandatory current handoff. Before ending a work
session or a context reset:

1. verify Git state;
2. update it with facts only;
3. keep exactly these four headings:

```text
## CURRENT STATE
## ACTIVE TASK
## NEXT STEPS
## BLOCKERS / NOTES
```

`NEXT STEPS` must contain exactly three atomic items. Preserve unresolved
blockers, do not add pleasantries or secrets, and do not turn the file back into
a PR chronicle. Put durable architecture/history in `CONTESTO_IA/`, routed by
its README.