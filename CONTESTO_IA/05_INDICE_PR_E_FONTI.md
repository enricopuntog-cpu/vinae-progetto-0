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
| [#15](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/15) | 30-07-2026 | merged | Riconciliazione handoff post-merge 6d-1 e prompt operativi |
| [#16](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/16) | 30-07-2026 | merged | Evidenze post-merge 33/33, 11/11 e residui fixture zero |
| [#17](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/17) | 31-07-2026 | merged | Fase 6d-2a — provenienza catalogo e percorsi Cantina |
| [#18](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/18) | 03-08-2026 | merged | Fase 7 — proposte, ordini e pagamenti; squash `2a47952` |
| [#19](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/19) | 04-08-2026 | merged | Fase 7b — Connect, commissione e trattenuta fondi; squash `5e6b8e4` |
| [#20](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/20) | 04-08-2026 | merged | Documentazione e handoff allineati al merge della 7b; squash `1782a1a` |
| [#21](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/21) | 04-08-2026 | merged | Fase 7c — consegna, tracking e imballaggio; squash `471b529`; `Supabase Preview` `SKIPPED` |
| [#22](https://github.com/enricopuntog-cpu/vinae-progetto-0/pull/22) | 05-08-2026 | merged | Fase 7d — decisioni economiche, sola documentazione: 1a, 1e, 3a decise; 2c approvata in design; 3e aperta |

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
è verde sull'HEAD `6bbe4dd`. Le griglie sono state autorizzate ed eseguite
separatamente dopo il merge: risultati finali 33/33 e 11/11, verifier storico
13/13 e residui fixture zero.

### PR #17, #18 e #19

- #17 è la Fase 6d-2a, unita in `main` il 31 luglio 2026 con merge squash
  `3037bf4`. Lo smoke Storage del bucket `cantina` resta però aperto: il merge
  non lo include.
- #18 è la Fase 7, unita il 3 agosto 2026 con merge squash `2a47952`.
- #19 è la Fase 7b, unita il 4 agosto 2026 con merge squash `5e6b8e4`, CI verde
  sulla run
  [`30900108638`](https://github.com/enricopuntog-cpu/vinae-progetto-0/actions/runs/30900108638).

Per #18 e #19 vale una distinzione che il solo stato «merged» non mostra, ed è
l'opposto di quella che questo documento riportava prima. Il merge **ha
distribuito**: l'integrazione GitHub di Supabase ha portato entrambe le
migrazioni a ledger e reso `ACTIVE` le tre Edge Function, senza che nessuno
lanciasse un comando. Verificato in lettura il 4 agosto 2026. Non sono fasi
inerti: sono fasi vive e mai percorse — tabelle di denaro a zero righe, nessun
percorso UI, `PAYMENTS_ENABLED=false`, nessuna chiamata Stripe.

### PR #21 e #22

- **#21 è la Fase 7c**, unita il 4 agosto 2026 con merge squash `471b529`. Il suo
  controllo `Supabase Preview` è **`SKIPPED`**: il bot ha valutato il diff sei
  secondi dopo l'apertura della PR, diciannove minuti prima che esistesse il
  commit con la migrazione, e non ha rivalutato. Conseguenza da non perdere:
  della 7c **nessun motore Postgres ha eseguito lo SQL prima di quello di
  produzione**. È la stessa classe di problema della regola 11, dal lato opposto
  — là l'anteprima aveva eseguito troppo presto, qui non ha eseguito affatto.
- **#22 è la Fase 7d**, sola documentazione: due file, nessuno SQL. Ha chiuso in
  sessione organizzativa le decisioni **1a** (scheduler esterno su GitHub Actions,
  non `pg_cron`), **1e** (scheduler acceso e verificato prima di
  `PAYMENTS_ENABLED`) e **3a** (la voce «protezione» esce dal modello Supabase e
  resta in `frontend/` fino alla Fase 11). La **2c** ha design approvato — tetto a
  5 tentativi con colonne contatore su `payments` — e **schema non scritto**. La
  **3e** resta aperta ed è una domanda commerciale, non tecnica.

### Il branch di anteprima della #19

Supabase crea un branch di anteprima per ogni PR ed esegue le migrazioni
all'apertura. Sulla #19 quel branch ha eseguito la **prima bozza** della
migrazione di Fase 7b — commissione 5% piatta — e non ha mai ripreso la
riscrittura a netto garantito, perché un ambiente che ha già registrato una
versione come eseguita confronta la versione e non il testo. Il progetto reale
non è toccato, perché quella versione non l'ha mai eseguita. Da qui la regola 11
delle regole di migrazione.

## Fonti autorevoli nel repository

| Fonte | Uso |
| --- | --- |
| [`../AGENTS.md`](../AGENTS.md) | Istruzioni correnti per agenti, se presente |
| [`../CLAUDE.md`](../CLAUDE.md) | Comandi, convenzioni sulle migrazioni e invarianti di sicurezza vincolanti |
| [`../CHANGES.log`](../CHANGES.log) | Ponte di handoff: stato corrente, task attivo, tre prossimi passi, blocchi |
| [`../docs/ROADMAP_V1.md`](../docs/ROADMAP_V1.md) | Sequenza e stato logico delle fasi |
| [`../docs/MIGRATION_PHASE_1_BACKLOG.md`](../docs/MIGRATION_PHASE_1_BACKLOG.md) | Perimetri, debiti e handoff futuri |
| [`../docs/adr/001-target-architecture.md`](../docs/adr/001-target-architecture.md) | Architettura target |
| [`../docs/adr/002-migration-strategy.md`](../docs/adr/002-migration-strategy.md) | Strategia incrementale |
| [`../docs/SECURITY.md`](../docs/SECURITY.md) | Invarianti di sicurezza |
| [`../docs/ENVIRONMENT.md`](../docs/ENVIRONMENT.md) | Variabili e ambienti |
| [`../docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md) | Git, verifiche e definition of done |
| [`../docs/PHASE_6D1_SUPABASE_REVIEW.md`](../docs/PHASE_6D1_SUPABASE_REVIEW.md) | Esito della verifica reale 6d-1 |
| [`../docs/PHASE_6D1_FINAL_EXECUTION_REPORT.md`](../docs/PHASE_6D1_FINAL_EXECUTION_REPORT.md) | Fotografia storica conclusiva del branch 6d-1 |
| [`../docs/PHASE_6D2A_SPEC.md`](../docs/PHASE_6D2A_SPEC.md) | Decisioni della Fase 6d-2a |
| [`../docs/PHASE_7_VERIFICATION.md`](../docs/PHASE_7_VERIFICATION.md) | Verifiche locali e gate remoti della Fase 7 |
| [`../docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md`](../docs/superpowers/plans/2026-08-05-phase-7d-decisioni-economiche.md) | Decisioni economiche della 7d: auto-rilascio, fee reale, spedizione e protezione, con l'esito della sessione organizzativa in testa |
| [`../supabase/repair/README.md`](../supabase/repair/README.md) | Riparazione del ledger delle migrazioni e replay misurato |
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
