# Rapporto RECOVERY-001 — AI Skills Lab

31 ottobre 2026. Audit esaustivo delle fonti e integrazione delle competenze mancanti. Il rapporto distingue ciò che è stato **verificato**, ciò che è stato solo **letto** e ciò che **non è stato provato**. Non rifà VPM-LAB-002 né i Cicli 1 e 2.

## Stato in una riga

Fonti recuperate e riconciliate; 7 skill di terzi e 1 interna integrate, integre e caricate dal profilo `vinea-coding`; **la prova di invocazione di tutte e 8 è NON VERIFICATA** perché il login OAuth della CLI è scaduto durante la sessione. Per i criteri del titolare («non dichiarare VERIFICATA una skill non testata nella configurazione effettiva») il ciclo **non è chiudibile** finché `claude-skill-runtime-check.mjs` non è eseguito con l'accesso rinnovato.

## Numeri

| Misura | Valore |
|---|---:|
| Fonti totali | 119 |
| Fonti realmente esaminate (didascalia letta per intero) | 89 (40 con strumenti, 29 senza strumento, 20 non pertinenti) |
| Fonti NON RISOLTE (strumento non nominato: elenco/link/video via DM) | 29 |
| Fonti NON LETTE (#103, Notion non accessibile) | 1 |
| Voci di inventario in `VINEA_SKILLS_CANDIDATES.md` | 51 (che raccolgono circa 85 strumenti o servizi nominati, contati per nome, escluse le singole skill dei repository multi-skill) |
| Skill tecnicamente installabili (solo Markdown, licenza da file, niente hook/MCP, entro i limiti) | 15: le 7 adottate e 8 idonee ma rinviate per merito (copy-editing, schema, ai-seo, launch, pricing, customer-research, site-architecture, Stop Slop) |
| Candidate esaminate con scanner | 29 scansioni SkillSpector in questo ciclo + 9 del Ciclo 2 |
| Skill adottate e installate | 7 di terzi + 1 interna (`vinea-marketing`) |
| Skill caricate dal profilo `vinea-coding` dopo il lavoro | 16 nel progetto (8 interne, 7 di terzi, `frontend-design`) |

Per area (caricate): DEV/QA 4 (`vinea-task`, `vinea-test`, `vinea-review`, `vinea-skill-evaluation`); SICUREZZA 2 (`vinea-security`, `vinea-external-skill-audit`); DESIGN 4 (`vinea-design`, `frontend-design`, `review-animations`, `animation-performance`); DATABASE 1 (`supabase-postgres-best-practices`); MARKETING 5 (`vinea-marketing`, `copywriting`, `seo-audit`, `cro`, `product-marketing`). «Operative» ≠ «provate»: vedi sopra.

## Nuove competenze rispetto alle otto skill di prima

1. **Marketing** (assente): copy, audit SEO statico, ipotesi CRO, contesto di prodotto, con il comando `/vinea-marketing` che impone fatti verificabili, nessuna pubblicazione e revisione legale per gli alcolici.
2. **Movimento nel frontend**: revisione (`/review-animations`) e prestazioni (`animation-performance`) delle animazioni, subordinate ai token Vinea.
3. **Prestazioni PostgreSQL** (indici, policy RLS, blocchi) complementari agli invarianti di `vinea-security`.
4. **Integrità delle skill di terzi**: lock con commit e SHA-256 e verificatore in CI che rifiuta derive e superfici pericolose.
5. **Prova di invocazione riproducibile** (`claude-skill-runtime-check.mjs`).

## Cosa è stato fatto e come

- **Fonti**: catalogo di 119 ID e didascalie integrali recuperati dal pacchetto del 29 ottobre e dall'archivio del Ciclo 2 (il solo documento di partenza; l'export Instagram non è sul disco). Strumenti estratti per ID senza inventare nomi: `VINEA_SKILLS_SOURCE_COVERAGE.md`.
- **Provenienza**: per circa 40 repository, commit, licenza, numero di skill, hook, MCP e installer dal GitHub tree API (nessun codice eseguito). Molti repository sono avanzati dal Ciclo 2: ogni adozione è fissata al commit auditato.
- **Audit**: cinque gruppi di audit statici in sola lettura (subagenti) con copertura dichiarata; le conclusioni sono in `VINEA_SKILLS_CANDIDATES.md`. gstack e Ruflo: triage mirato (non lettura integrale); Archify: `bin/archify.mjs` non letto per intero; i rilievi `gstack-review` non riesaminati uno a uno.
- **Scanner**: SkillSpector 2.13.2 `--no-llm`, credenziali rimosse dall'ambiente, proxy verso una porta chiusa. Tutti i rilievi delle skill adottate sono stati letti a mano (falsi positivi). Il riesame di UI/UX Pro Max ha classificato tutti i 15 HIGH come falsi positivi e letto a mano i file non coperti.
- **Integrazione**: copia byte-identica dai blob git dei commit auditati (coi LICENSE), lock `claude-skills.lock.json`, verificatore e test (19/19, 6 nuovi), aggiornamento di `vinea-task`, `vinea-design`, `vinea-review`, `vinea-security`, nuova `vinea-marketing`.

## Prove runtime

| Prova | Esito |
|---|---|
| Sessione headless in `vinea-coding`: evento `init` | le 7 skill di terzi, `vinea-marketing` e `frontend-design:frontend-design` sono elencate; nessun duplicato né collisione di nome con le skill di superpowers/utente. VERIFICATO |
| Stesso test col profilo di default | le skill di progetto sono elencate; `frontend-design` assente (plugin non installato in quel profilo). VERIFICATO |
| Invocazione di ogni nuova skill con un task di sola lettura | **NON ESEGUITA**: «Failed to authenticate: OAuth session expired and could not be refreshed», costo 0, 0 turni utili. NON VERIFICATO |
| Interferenza tra skill / prova negativa (un task non pertinente non attiva le skill di marketing) | NON VERIFICATA (richiede la stessa autenticazione) |
| `claude-setup-verify` e test | verificatore OK; test 19/19 |
| Suite CI completa, check richiesti sulla testa, post-merge | vedi la PR; NON eseguiti all'atto di questo rapporto |

## Secondo passaggio (31 ottobre 2026)

Il 31 ottobre 2026, secondo passaggio, la CLI 2.1.316 riporta `loggedIn: false` in entrambi i profili: Anthropic Direct («OAuth session expired and could not be refreshed») e `vinea-coding` (credenziali del profilo senza token di accesso; OmniRoute su `127.0.0.1:20128` risponde 401 senza chiave e nel mio ambiente non esiste una chiave valida). Nessuna chiamata al modello è partita (costo 0). L'accesso è un'azione del titolare e non è stato aggirato. Lo script di prova è stato corretto prima di qualsiasi esecuzione: corrispondenza esatta del nome della skill (un nome nel testo o un nome simile non contano), prova strutturale per le skill manuali, esiti distinti per autenticazione, errore API, timeout e interferenza, strumenti ridotti a `Skill`, `Read`, `Grep`, `Glob` con `--tools`, limite di tempo e di spesa per sessione, tetto al buffer di uscita, nuova prova negativa (un task di programmazione non deve attivare le skill di marketing), esito salvato senza prompt né percorsi personali. 15 test offline del classificatore passano; l'esito reale resta NON VERIFICATO per tutte e otto le skill e per la prova negativa.

## Rischi, costi, limitazioni

- **Rischio principale**: skill contestuali di marketing e `supabase-postgres-best-practices` possono attivarsi in contesti non voluti (la seconda dichiara «carica prima di qualsiasi SQL»). Mitigazione: precedenza di `CLAUDE.md` scritta nelle skill interne; da misurare con la prova di invocazione.
- **Conflitto noto**: i budget di durata di `review-animations` (UI sotto 300 ms) contraddicono i token Vinea (320/520 ms): le skill `vinea-design` e `vinea-review` dichiarano che i token prevalgono.
- **Contesto marketing**: `.agents/product-marketing.md` è stato redatto il 31 ottobre 2026 come **BOZZA — NON APPROVATA DAL TITOLARE**, solo con fatti del repository etichettati per stato (`[VERIFICATO]`, `[BETA]`, `[SPENTO]`, `[PIANIFICATO]`, `[IPOTESI]`, `[LEG]`), senza ricerche di mercato, testimonianze, risultati o promesse. `vinea-marketing` lo tratta come orientamento e non come fonte di claim. Finché il titolare non lo approva, l'output delle skill di marketing resta bozza.
- **Costo di contesto**: ≈1,2k token per sessione (coperti dalla cache); nessun nuovo servizio a pagamento; nessun benchmark a pagamento in questo ciclo. Il costo dei subagenti di audit non è misurato in USD.
- **Ambiente**: Python e FFmpeg non installati (bloccano UI/UX Pro Max, Claude Ads, Founder Skill, HyperFrames); Docker presente.
- **Limiti degli audit**: statici e parziali; un audit statico non equivale a un benchmark pratico. Nessun confronto prestazionale nuovo tra strumenti equivalenti.
- Nessuna modifica a `CLAUDE.md`, migration, database, OmniRoute o funzionalità applicative.

## Git

Worktree `skills-recovery-001`, branch `docs/skills-recovery-001`, da `origin/main` `a6e34ed` (PR #246 già integrata). PR, SHA di testa e stato dei check: nella PR e in `CHANGES.log`.

## Per chiudere il ciclo

1. Il titolare rinnova l'accesso (vedi `VINEA_SKILLS_USAGE.md`) ed esegue `claude-skill-runtime-check.mjs` nel profilo `vinea-coding`; si aggiorna il registro con gli esiti reali (otto skill più prova negativa).
2. Il titolare rivede e approva `.agents/product-marketing.md` (bozza già presente).

3. Merge a check verdi e verifica da `origin/main` (lock, verificatore, `init` del profilo da un clone pulito).
