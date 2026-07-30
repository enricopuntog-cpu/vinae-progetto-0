# Indice Pull Request e fonti

## Pull Request

| PR | Data merge/chiusura | Stato | Contenuto |
| --- | --- | --- | --- |
| [#1](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/1) | 27-07-2026 | merged | Sprint 0 — hardening pre-release |
| [#2](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/2) | 27-07-2026 | merged | Sprint 1 — store in 8 slice + hook |
| [#3](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/3) | 27-07-2026 | merged | Fase 1 — roadmap, ADR, backlog |
| [#4](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/4) | 27-07-2026 | merged | Fase 2 — scaffold Next.js |
| [#5](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/5) | 27-07-2026 | merged | Fase 3 — pagine mock + store; assorbe Fase 4 |
| [#6](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/6) | 28-07-2026 | merged | Fase 5a — Auth Supabase |
| [#7](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/7) | 28-07-2026 | merged | Fase 5b — OAuth e callback |
| [#8](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/8) | 28-07-2026 | merged | Prima registrazione amministrativa della Fase 6a |
| [#9](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/9) | 28-07-2026 | merged | PR descrittiva/canonica della Fase 6a |
| [#10](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/10) | 28-07-2026 | merged | Fase 6b — scrittura annunci |
| [#11](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/11) | 29-07-2026 | merged | Fase 6c-1 — schema Cantina |
| [#12](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/12) | 29-07-2026 | chiusa, non merged | Duplicato draft amministrativo della 6c-1 |
| [#13](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/13) | 29-07-2026 | merged | Fase 6c-2 — interfaccia Cantina |
| [#14](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/14) | 30-07-2026 | merged | Fase 6d-1 — invarianti di sicurezza e repair deriva remota |
| [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) | 30-07-2026 | draft | Riconciliazione handoff post-merge 6d-1 e prompt operativi |

## Anomalie della cronologia da conoscere

### PR #8 e #9

Entrambe risultano merged con lo stesso branch/head di Fase 6a. Nel Git
locale:

- `d718287` (`#8`) contiene il diff effettivo della fase;
- `f537882` (`#9`) non mostra un ulteriore diff;
- la #9 contiene però la descrizione completa e viene usata come fonte
  narrativa canonica.

Non contare #8 e #9 come due fasi funzionali.

### PR #11, #12 e #13

- #11 è la Fase 6c-1 integrata;
- #12 è una draft duplicata, chiusa senza merge;
- #13 è la Fase 6c-2 integrata.

Il subject del commit locale `a857f3b` può mostrare `(#12)` anche se GitHub
identifica la PR di UI come #13. Per lo stato remoto e il corpo della PR,
usare GitHub come fonte.

### PR #14

La PR #14 è stata unita con merge commit `61e3fde`. La CI finale
[`30554736346`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30554736346)
è verde sull'HEAD `6bbe4dd`. I documenti inclusi nel merge dichiaravano ancora
pendenti le griglie remote post-repair 33/33 e 11/11: il merge non va usato come
prova implicita della loro autorizzazione o del loro esito.

## Fonti autorevoli nel repository

| Fonte | Uso |
| --- | --- |
| [`../AGENTS.md`](../AGENTS.md) | Istruzioni correnti per agenti, se presente |
| [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md) | Sequenza e stato logico delle fasi |
| [`../docs/MIGRATION_PHASE_1_BACKLOG.md`](../docs/MIGRATION_PHASE_1_BACKLOG.md) | Perimetri, debiti e handoff futuri |
| [`../docs/adr/001-target-architecture.md`](../docs/adr/001-target-architecture.md) | Architettura target |
| [`../docs/adr/002-migration-strategy.md`](../docs/adr/002-migration-strategy.md) | Strategia incrementale |
| [`../docs/SECURITY.md`](../docs/SECURITY.md) | Invarianti di sicurezza |
| [`../docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md) | Variabili e ambienti |
| [`../docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md) | Git, verifiche e definition of done |
| [`../docs/PHASE_6D1_SUPABASE_REVIEW.md`](../docs/PHASE_6D1_SUPABASE_REVIEW.md) | Esito della verifica reale 6d-1 |
| [`../docs/PHASE_6D1_FINAL_EXECUTION_REPORT.md`](../docs/PHASE_6D1_FINAL_EXECUTION_REPORT.md) | Fotografia storica conclusiva del branch 6d-1 |
| [`../supabase/tests/README.md`](../supabase/tests/README.md) | Ordine e scopo dei test SQL |
| [`../frontend-next/src/services/types.ts`](../frontend-next/src/services/types.ts) | Contratti dei servizi target |
| [`06_PROMPT_CHAT_OPERATIVE.md`](06_PROMPT_CHAT_OPERATIVE.md) | Prompt sequenziali per le prossime chat |

## Gerarchia pratica delle prove

Per decidere se qualcosa è davvero completato:

1. verificare che il codice sia nel branch corretto;
2. verificare che la PR sia merged, se si dichiara “in `main`”;
3. verificare migrazioni e catalogo remoto per lo stato Supabase;
4. leggere test/report e non dedurre l'esito dalla sola presenza dei file;
5. distinguere sempre tra “testato”, “integrato” e “in produzione”.
