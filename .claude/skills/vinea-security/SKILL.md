---
name: vinea-security
description: Controllo di sicurezza mirato su codice, SQL e configurazioni di Vinea contro gli invarianti di CLAUDE.md, senza prove contro servizi reali. Usare per modifiche a Supabase, backend, auth, pagamenti o configurazioni di sicurezza.
argument-hint: "[file, cartella o PR]"
paths:
  - "supabase/**"
  - "backend/**"
  - "frontend-next/src/**/auth/**"
  - "**/*.sql"
  - ".github/workflows/**"
  - ".claude/**"
---

# /vinea-security

Controllo statico di sicurezza. Nessuna prova attiva: niente richieste HTTP a
servizi reali, niente SQL contro Supabase (né locale né remoto), niente
penetration test, niente lettura di segreti.

Argomenti ricevuti: $ARGUMENTS

## 1. Perimetro

Individua i file da esaminare dagli argomenti o dal diff
(`git diff --name-only origin/main...HEAD`).

## 2. Controlli

- Esegui il comando integrato `/security-review` sul perimetro.
- Passa l'elenco dei file (o il file temporaneo del diff, fuori dal repository)
  al subagente `vinea-security-auditor`.
- La checklist è quella di `CLAUDE.md`, *Security invariants*: Trust
  boundaries, PostgreSQL exposure, Money; più *Supabase workflow* per le
  migrazioni. Cita le sezioni, non ricopiarle.

## 3. Report

    FATTI VERIFICATI
    - [gravità] <rischio> — file:riga — invariante: <sezione>
    NON VERIFICATO
    - <cosa> — <perché> (stato remoto, PostgREST, browser)
    RISCHI
    - <rischio residuo>
    RACCOMANDAZIONI
    - <correzione>

## Completamento

Completo quando ogni file del perimetro è stato esaminato e ogni rischio è
classificato. Le correzioni le applica il Claude principale.
