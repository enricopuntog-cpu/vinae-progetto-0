---
name: vinea-test
description: Esegue i test pertinenti di Vinea (frontend, frontend-next, backend, script CI) solo dopo una modifica al codice o su richiesta esplicita di test, e riporta evidenze e regressioni. Non autorizza commit, push o merge.
argument-hint: "[area o SHA]"
---

# /vinea-test

Scegli ed esegui i controlli pertinenti alla modifica, poi riporta le evidenze.
Questa skill non autorizza commit, push o merge: decide il Claude principale.

Argomenti ricevuti: $ARGUMENTS

## 1. Scegli i controlli

Dal diff rispetto a `origin/main` (`git diff --name-only origin/main...HEAD`):

| File toccati | Controlli (da `CLAUDE.md`, *Testing and definition of done*) |
|---|---|
| `frontend/**` | `bun install --frozen-lockfile`, `lint`, `typecheck`, `test`, `build` |
| `frontend-next/**` | come sopra; rispetta la soglia minima di test in `.github/workflows/ci.yml` |
| `backend/**` | `python -m compileall -q .`, `python -m ruff check .`, `python -m pytest -q` |
| `.github/scripts/*.mjs` | `node --test .github/scripts/<nome>.test.mjs` |
| `.claude/**` | `node .github/scripts/claude-setup-verify.mjs` e i test `claude-*.test.mjs` |
| `supabase/**` | griglie solo nel workflow CI `Supabase DB regression`: qui sono `NON VERIFICATO` finché il gate non riporta |

Esegui prima il controllo più piccolo, poi lo stack completo toccato.

## 2. Dove eseguirli

- Sul worktree corrente: esegui tu i comandi.
- Su uno SHA preciso, senza toccare il worktree corrente: delega al subagente
  `vinea-qa-runner` passandogli SHA e controlli; lui lavora in un worktree
  isolato con comandi a lista bianca.

Mai credenziali reali: i test backend usano `APP_ENV=test` e i fake di
`backend/tests/conftest.py`; nessuno stack Supabase locale, nessuna rete verso
servizi di produzione.

## 3. Report

    FATTI VERIFICATI
    - <comando>: <esito, conteggi pass/fail> (SHA)
    NON VERIFICATO
    - <controllo> — <perché>
    RISCHI
    - <regressione> — file:riga
    RACCOMANDAZIONI
    - <comando esatto per riprodurre>

## Completamento

Completo quando ogni controllo pertinente ha un esito riportato; una regressione
è isolata con il comando per riprodurla.
