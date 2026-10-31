# Strumenti browser: cosa funziona davvero

Stato misurato il 31 ottobre 2026 (VPM-LAB-003). Tre categorie, da non
confondere: **PROVATO** (eseguito qui con esito), **PRESENTE** (strumento o skill
elencato, mai eseguito in questa prova), **STORICO** (misura di un ciclo
precedente, non una prova attuale).

## Il mezzo principale: Playwright Test dal terminale

| Capacità | Stato | Come |
|---|---|---|
| Aprire un browser, navigare il frontend | **PROVATO** | `bun run e2e` avvia build + `next start` e apre Chromium e WebKit |
| Compilare form, click, selezioni, upload | **PROVATO** | casi `accessori-vendita-parziale` (Cantina, foto PNG→WebP, dialoghi, segnalazione, moderazione) |
| Utenti distinti con sessioni isolate | **PROVATO** | un contesto di browser per ruolo (`contestoAutenticato`), cinque utenti di fixture |
| Errori di console, rete, risposte 5xx | **PROVATO** | fixture `diagnostica` in `support/test.ts`, allegata ai casi |
| Screenshot desktop e mobile | **PROVATO** | Chromium desktop, Chromium 375×812, WebKit; screenshot dei casi in `e2e/artifacts/` |
| Riprodurre un difetto, riesaminarlo, rieseguirlo | **PROVATO** | trace (`retain-on-failure`), `-g "<titolo>"`, ciclo regressione→rosso→ripristino→verde |
| WebKit (Safari) | **PROVATO** | progetto `webkit-desktop`, 8 casi `@cross`; WebKit 27.2 di Playwright su Windows |
| Eseguirlo in un'altra sessione Claude Code, profilo `vinea-coding` | **NON VERIFICATO** | l'evento `init` del profilo elenca la skill e i sei subagenti; la chiamata al modello da questa sessione è fallita per autenticazione (OAuth del profilo scaduto, nessuna credenziale ereditata). Si prova dalla shell del titolare: vedi sotto |
| Eseguirlo con `vinea-qa-runner` | **NON PREVISTO** | la sua lista bianca non ammette Docker né Playwright; non si allarga |

Prova del profilo `vinea-coding` (da una shell con il profilo già configurato,
senza token negli argomenti):

    CLAUDE_CONFIG_DIR=~/.claude/profiles/vinea-coding node .github/scripts/claude-skill-runtime-check.mjs --solo vinea-browser-qa --budget-usd 0.5

verifica che la skill sia elencata e richiamata con lo strumento `Skill`
(in sola lettura). L'esecuzione effettiva della suite da quel profilo richiede
una sessione con `Bash(bun --cwd frontend-next run e2e:smoke)` consentito;
vedi `docs/E2E_BROWSER.md`.

## Gli altri strumenti della sessione desktop

| Strumento | Stato | Note |
|---|---|---|
| Browser integrato (`mcp__Claude_Browser__*`) | **PROVATO** per navigare, leggere il testo, viewport 375 px, screenshot, console, rete su `127.0.0.1:3100`. **PRESENTE, non provato** per click e `form_input` su Vinea | Solo nelle sessioni desktop: non esiste in `claude -p`, in CI né nel profilo `vinea-coding` headless. Utile per ispezionare a mano, non per la regressione |
| Claude in Chrome (`mcp__claude-in-chrome__*`) | **PRESENTE, non provato** | Usa il Chrome reale dell'utente con le sue sessioni: non per le fixture, non per l'isolamento |
| Computer use (`mcp__computer-use__*`) | **PRESENTE, non provato** | Browser a livello «sola lettura»; non adatto ai test |
| `frontend-design`, `vinea-design`, `vinea-ux-auditor` | **PRESENTE** | Giudicano o guidano il design: non aprono un browser |
| Benchmark Ciclo 2 (14 casi Playwright Test nel laboratorio) | **STORICO** | Non è la suite del progetto e non copre Accessori reali |
| Playwright CLI (`@playwright/cli`) | **NON INSTALLATO** | Auditato e rinviato (registro). Vedi sotto |

Regola: non dichiarare disponibile una capacità non provata. In un report scrivi
«provato» solo per ciò che hai eseguito nella sessione.

## Esplorare pagine non coperte da un caso

Serve per trovare problemi che i casi non anticipano. Senza strumenti nuovi:

1. crea uno spec temporaneo `frontend-next/e2e/esplora-<tema>.e2e.ts`
   (`.gitignore` lo esclude), con `ripristinaFixture`, `contestoAutenticato` e
   `descriviPagina(page, "nome", info)` da `support/esplora.ts`;
2. `bun run e2e --project=chromium-desktop esplora`;
3. leggi testi, controlli, campi, link e screenshot; poi trasforma ciò che
   conta in un caso vero e cancella lo spec esplorativo.

Misurato qui: questo percorso ha descritto Cantina, admin Accessori, vetrina e
dettaglio in un solo giro, e ha scoperto a priori due condizioni che un caso
statico non avrebbe visto (pagine che restano su «Carico…» finché la sessione non
arriva; `next dev` che non idrata da `127.0.0.1`). Resta un limite: richiede di
scrivere lo spec, non è navigazione libera. Playwright CLI offrirebbe sessioni
interattive da shell, ma porta rischi già documentati nel registro (`allowed-tools`
ampio, `attach` al browser reale, installazione globale `@latest`) e nessun
beneficio dimostrato rispetto a questo percorso: **non adottato**; una nuova
valutazione è una decisione del titolare.
