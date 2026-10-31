# AI Skills Lab — rapporto finale Ciclo 2

31 ottobre 2026. Questo rapporto distingue verifiche dal laboratorio, attività non eseguite e consegna Git. Non trasforma un audit statico in una prova runtime. Il Ciclo 1 non è prova del Ciclo 2; le cinque pubblicazioni e la CI sulla testa e sul merge vanno verificate separatamente prima di dichiarare chiuso il ciclo.

## Recupero e perimetro

Quattro originali non tracciati recuperati **in sola lettura** dal checkout principale: `docs/VINEA_SKILLS_FINAL_REPORT.md`, `docs/VINEA_SKILLS_USAGE.md`, `docs/VINEA_SKILLS_PM_HANDOFF.md`, `docs/VINEA_CLAUDE_CACHE_AUDIT.md`. Sono rimasti intatti; le correzioni sono scritte nel worktree separato `skills-ciclo-2-consegna`, creato da `origin/main` a `dc7a6bed51563568b6ed2d6a6ee4096949d41021`. Anche il registro Ciclo 1 versionato su `main` è stato usato come base, non sovrascritto nel checkout principale. Il catalogo JSON di 119 fonti è stato recuperato da un archivio temporaneo locale (29 ottobre), e riprodotto nel registro per ID, priorità e stato con sintesi sanificate, senza URL social o dati privati. Nessun originale, dato di produzione, migration o prodotto è stato modificato.

## Esito per area

| Area | Stato | Evidenza concreta | Limiti |
|---|---|---|---|
| DESIGN | VERIFICATO | `frontend-design` v1.1.1 usato nel task isolato; benchmark Taste v2/Impeccable con tre screenshot desktop e tre mobile, misure, JSON Playwright distinti: 14/14 contro 12/14 e 12/14. Decisione motivata: conservare baseline, non adottare entrambi. | Nessun candidato ha usato il browser; screenshot e prototipi sono solo nel lab; la mutazione focus è sfuggita per l'outline Chrome. |
| QA | COMPLETATO CON LIMITAZIONI | `@playwright/cli` 0.1.22 Apache-2.0 consultato con `npm exec --help`; confrontato con Playwright Test 1.64.1 già usato nel benchmark. Nessun owner E2E esplicito né PR E2E aperta trovata. | CLI solo help; test negativo e percorso MCP NON ESEGUITI, nessuna pretesa di sostituire suite E2E. |
| MARKETING | COMPLETATO CON LIMITAZIONI | Skill `copywriting`, `seo-audit`, `cro` caricate una per volta in tre sessioni headless isolate e scritte in tre demo temporanee NON PUBBLICATE; audit statico anche di `product-marketing`. | Nessuna metrica commerciale o indicizzazione misurata, nessun contenuto di prova pubblicato e nessuna installazione nel profilo. |
| ARCH/SEC | COMPLETATO CON LIMITAZIONI | SkillSpector v2.13.2 eseguito `--no-llm` senza credenziali, proxy blackhole; audit statici di Archify, Remotion, Strix e Agent-Reach. Risultati e coperture nel registro. | Archify trial NON ESEGUITO (scan CRITICAL parziale e comando eseguibile); Remotion NON ESEGUITO (licenza non verificata e nessun task video); Strix runtime BLOCCATO (Docker/agenti/telemetria), Agent-Reach rete NON ESEGUITA. |
| CACHE | COMPLETATO CON LIMITAZIONI | Letture SQLite OmniRoute readonly: 972 chiamate nella finestra, 18.382 righe storiche, 55 switch, 14 ritorni a Claude. Audit separato con denominatori. | Nessun dato euro affidabile: ledger 5 righe e costo provider non popolato. I test headless non appartengono necessariamente alla finestra della base. Causa degli switch NON VERIFICATA. |

### Tre demo marketing (non pubblicate)

- Copywriting: 697 parole, 4.437 B, 12 turni, costo CLI stimato $0,401; segnala claim non supportati «pregiati», «tra privati», «italiani», «Compra» e «cataloga»; tre alternative, la terza subordinata a prove; CTA del demo legata allo switcher `ruolo`, non alla sessione reale.
- SEO: 769 parole, 4.919 B, 11 turni, $0,336; `robots.ts` con `disallow: /`, sitemap non presente nei file copiati, description ~55 caratteri, meta/OG/hero non uniformi, canonical assente, `/accessori` noindex e 404 senza gate. Distingue osservazione statica da runtime non eseguito; non propone indicizzazione degli Accessori.
- CRO: 634 parole, 4.340 B, 12 turni, $0,395; ipotesi CTA «Esplora», prerequisito di allineamento hero/sessione reale; senza baseline non calcola sample size o risultati. Tutte rispettano la regola di non fissare un nome di brand nel copy.

L'audit marketing ha avuto un tentativo fallito (`is_error`, fallback Gemini, $1,371 stimati) e un successivo successo ($1,858), **non** una singola prova a $1,86. Gli audit statici hanno tentato Bash una volta nei run Impeccable e Marketing: entrambi i tentativi sono stati negati perché il tool non era disponibile; non ne derivano comandi eseguiti. Costi CLI stimati, non fatture: audit circa $13,36 (inclusi entrambi i run marketing), benchmark $3,23, task design $0,808, setup $0,235, tre demo $1,13; totale circa $18,77. Nessun nuovo benchmark a pagamento richiesto.

## Adozione e scarti

Nuove installazioni persistenti: **nessuna**. `frontend-design` v1.1.1 era già installato nel profilo `vinea-coding` per il worktree Ciclo 1; qui si è verificato l'uso in task isolato e il benchmark 14/14, non l'installazione in altri profili. SkillSpector v2.13.2 (`abd82935…`, Apache-2.0) è stato provato solo nel laboratorio con `--no-llm`, non installato globalmente. Le tre skill marketing sono state caricate da copie project-scoped temporanee, con test runtime Skill e tre demo, non installate nel profilo permanente. Playwright CLI è stato invocato solo per help. Taste/Impeccable non adottati per regressione di palette; Archify sospeso per scan CRITICAL parziale e necessità di eseguire codice; Remotion per licenza non verificata e mancanza di task; Strix per limiti runtime; Agent-Reach per necessità di rete e verifica di accesso; Vercel Skills duplicato delle fonti #12/#59. Altri bundle o MCP con credenziali non installati.

## Consegna

Il registro contiene la riconciliazione sanificata delle 119 voci e i risultati scanner/benchmark. La guida d'uso delimita i profili e propone prompt; l'handoff separa le decisioni per area; l'audit cache distingue misure e ipotesi. La chiusura richiede una **nuova** PR su questa branch, sei check richiesti verdi sulla testa esatta, squash merge e verifica di CI e `Supabase DB regression` sul commit di `origin/main`. Finché queste prove non esistono, la **consegna Git è NON VERIFICATA** e non si dichiara concluso il Ciclo 2. Nessun cambiamento a routing, fallback, modelli, compressione, TTL, Supabase o Netlify Production.

Sulla prima testa della PR il job `Frontend Next` ha fallito sul gate audit per l'advisory GHSA-g3hv-75wg-m249 (`minimatch` <11.0.1, moderata, raggiunta tramite eslint), pubblicata dopo l'ultimo merge e quindi presente anche su `main`. La correzione è un override `minimatch` 11.0.1 in `frontend-next/package.json` con lockfile Bun rigenerato; il gate non è stato allentato. Localmente audit pulito, lint, typecheck, 3111 test e build verdi. È una dipendenza di sviluppo, non una modifica di prodotto.
