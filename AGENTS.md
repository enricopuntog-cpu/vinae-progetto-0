# Project Context & Rules

## Handoff Bridge

At session start, read `CLAUDE.md`, then `CHANGES.log`. At the end of every work
session or before handing off/context reset, update `CHANGES.log`
obligatorily: keep its four headings exact, `NEXT STEPS` at exactly 3 atomic
items, facts only, no pleasantries, no secrets. Verify Git state before writing
and preserve unresolved blockers.

## Tech Stack
- Next.js App Router (versione effettiva vincolata in `frontend-next/package.json`)
- TailwindCSS
- TypeScript

## Code Style & Constraints
- ALWAYS use functional components and Arrow Functions.
- No class components.
- Keep components small (<100 lines). Break down if larger.
- Use absolute imports (`@/components/...`).

## Token-Saving Output Rules
- DO NOT wrap code in polite intros or outros (e.g., "Sure, here is the code").
- ONLY output the specific lines or functions that changed. Do not output the entire file.
- If a file needs a minor tweak, use unified diff format or precise line replacements.

# Istruzioni per gli agenti

Prima di lavorare in questo repository, leggere integralmente `CLAUDE.md` e
considerarlo vincolante.

- Non modificare direttamente `main`.
- Non applicare SQL a un progetto Supabase remoto senza approvazione esplicita
  nella sessione corrente.
- L'approvazione al deploy di una migrazione non autorizza automaticamente test
  remoti che inseriscono o cancellano fixture: richiedere conferma separata.
- Dopo `apply_migration` via API/MCP, allineare subito il nome del file alla
  versione assegnata dal server e verificare la migration history.
- Non eseguire merge automatici, con **una sola eccezione ammessa per nome il 16
  agosto 2026**: una PR il cui diff contiene **zero file sotto
  `supabase/migrations/`** può essere mersa autonomamente, purché i tre job CI
  siano verdi e GitHub riporti `mergeable: MERGEABLE` e
  `mergeStateStatus: CLEAN` sull'head commit che si sta per mergiare. Con anche
  un solo file di migrazione il merge resta esplicito di Enrico. Confine esatto
  e motivazione in `CLAUDE.md`.
- `frontend/` e `backend/` restano la versione servita.
- `frontend-next/` e Supabase sono l'architettura di destinazione.

Per vincoli, processo, sicurezza, comandi e roadmap, fare riferimento a
`CLAUDE.md` senza duplicarne qui il contenuto.
