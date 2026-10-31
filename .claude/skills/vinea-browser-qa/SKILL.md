---
name: vinea-browser-qa
description: Esegue e interpreta la suite browser Vinea (Playwright su stack Supabase locale isolato) dopo una modifica frontend significativa o per riprodurre un difetto visibile nel browser. Mai contro produzione. Non autorizza commit, push o merge.
argument-hint: "[smoke | completa | -g <titolo caso> | esplora <percorso>]"
---

# /vinea-browser-qa

Verifica il comportamento **reale** di Vinea in un browser: sessioni di utenti
distinti, form, Storage, pagine servite da una build di produzione. Un controllo
di tipo, un test unitario o una chiamata REST non lo sostituiscono.

Argomenti ricevuti: $ARGUMENTS

Questa skill non concede permessi: i comandi passano dai normali controlli di
Claude Code, il subagente `vinea-qa-runner` non li esegue (la sua lista bianca
non ammette né Docker né Playwright) e nulla qui tocca produzione, commit, push
o merge.

## 1. Quando serve

- Hai cambiato `frontend-next/src/**` in modo visibile all'utente (pagine,
  dialoghi, moduli, gate, testi, layout) o hai toccato Accessori, Cantina,
  annunci, moderazione.
- Devi riprodurre o chiudere un difetto «lo vedo nel browser».
- Prima di dichiarare completa una modifica frontend: riporta quali casi hanno
  girato davvero, non «i test passano».

Non serve per modifiche solo a documenti, script CI o backend senza effetto sulla
UI. Se non puoi isolare l'ambiente, il caso è `NON VERIFICATO`: non si forza.

## 2. Ambiente: solo isolato

La suite parte solo se API, app e database sono provabilmente locali
(`frontend-next/e2e/support/target.ts`): loopback, nessun riferimento al progetto
di produzione, container `supabase_db_*`, ledger delle migrazioni uguale ai file
del commit, nessun utente estraneo alla fixture. Se la guardia rifiuta, **non
aggirarla**: correggi l'ambiente o segnala `NON VERIFICATO`.

Mai: chiavi o URL di produzione, `E2E_*` che puntano a un host remoto,
credenziali reali, password digitate nel browser. Le password della fixture
nascono a runtime e non toccano il disco.

## 3. Procedura

1. `git status` e SHA: i test provano il checkout corrente.
2. Docker attivo? `bun run e2e:stack up` (da `frontend-next/`). Senza Docker:
   `NON VERIFICATO (nessuno stack isolato)`.
3. Primo uso sulla macchina: `bun install --frozen-lockfile` e
   `bun x playwright install chromium webkit` (versione fissata dal lockfile).
4. Esegui il più piccolo insieme pertinente (comandi in
   [references/comandi-e-ambiente.md](references/comandi-e-ambiente.md)):
   `bun run e2e:smoke`; per un caso `bun run e2e --project=chromium-desktop -g "<titolo>"`;
   per cross-browser e 375 px `bun run e2e`.
5. Leggi il risultato: report, screenshot, trace e `diagnostica.json` per caso
   (errori console, richieste fallite, 5xx).
6. Classifica ogni rosso come difetto applicativo o d'infrastruttura
   ([references/diagnosi-esiti.md](references/diagnosi-esiti.md)).
7. Corretto il difetto, **rilancia solo i casi pertinenti**, poi lo smoke
   completo prima di chiudere.
8. `bun run e2e:stack down --conferma` quando hai finito (distrugge i dati di ogni stack locale del progetto).

## 4. Responsive e accessibilità

I casi `@cross` girano su Chromium desktop, Chromium a 375 px e WebKit: nessuno
scorrimento orizzontale, un solo `h1`, immagini con `alt`, controlli con nome,
campi con etichetta (`support/pagina.ts`). Non sostituiscono la revisione di
`vinea-ux-auditor`: per giudizi visivi passa gli screenshot dei casi, non
affidarti al solo esito verde.

## 5. Scrivere o cambiare un caso

Convenzioni, selettori e regole per fixture, pulizia e diagnostica:
[references/scrivere-test.md](references/scrivere-test.md). Ogni asserzione di
**assenza** attende prima il caricamento (`attendiCaricamento`), altrimenti è un
falso verde. Un caso nuovo si prova anche «al contrario»: rompi di proposito la
funzione in un ambiente isolato e verifica che il caso diventi rosso.

## 6. Report

    FATTI VERIFICATI
    - <comando>: <n passati / n totali>, progetti, SHA
    - artefatti: report, screenshot, trace (percorso)
    NON VERIFICATO
    - <caso o ambiente> — <perché>
    RISCHI
    - <difetto riprodotto> — caso, file:riga, trace
    RACCOMANDAZIONI
    - <comando esatto per riprodurre>

Strumenti browser disponibili e loro stato (provato, non provato, non
installato): [references/strumenti-browser.md](references/strumenti-browser.md).
Esplorazione di pagine non coperte da un caso: stesso file, sezione «Esplorare».

## Completamento

Completo quando i casi pertinenti hanno un esito riportato con i comandi
eseguiti, la pulizia ha riportato residui e interruttori a zero e lo stack è
fermo o dichiarato acceso. Un caso non eseguito è `NON VERIFICATO`, mai verde.
