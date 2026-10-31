# Rapporto RECOVERY-001 — AI Skills Lab

31 ottobre 2026. Audit esaustivo delle fonti e integrazione delle competenze mancanti. Il rapporto distingue ciò che è stato **verificato**, ciò che è stato solo **letto** e ciò che **non è stato provato**. Non rifà VPM-LAB-002 né i Cicli 1 e 2.

## Stato in una riga

Fonti recuperate e riconciliate; 7 skill di terzi e 1 interna integrate, integre e caricate dal profilo `vinea-coding`. Nel collaudo finale OmniRoute la chiamata reale al modello è riuscita: **8/8 skill invocate con prova strutturale e task concluso; prova negativa OK**. Le sei contestuali sono provate dallo strumento `Skill`; le due manuali dall'espansione del comando registrata nella trascrizione della CLI, dopo aver corretto il verificatore (il comando su stdin non veniva espanso).

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
| Nuove skill verificate con invocazione strutturale e task concluso | 8/8 |
| Prova negativa (task di programmazione non attiva skill marketing) | OK |

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
| Invocazione di ogni nuova skill con un task di sola lettura | 8/8 OK: sei con chiamata `Skill` nel flusso, due manuali con espansione del comando nella trascrizione. La risposta del task non basta |
| Interferenza tra skill / prova negativa (task di codice non attiva le skill di marketing) | OK; 3 turni, $0,101585 stimati, zero skill marketing richiamate |
| `claude-setup-verify` e test locali | verificatore OK (6 agenti, 8 interne, 7 di terzi nel lock); test offline della prova runtime 25/25; suite Continuity completa ripetuta sul commit finale |
| Suite CI completa, check richiesti sulla testa, post-merge | nella PR #247 e in `CHANGES.log` (SHA di testa e check) |

### Collaudo finale delle nove prove (31 ottobre 2026)

CLI 2.1.316, profilo `vinea-coding` via OmniRoute: `claude auth status` riportava `loggedIn: true` e una chiamata headless reale ha risposto `OK` (`success`, costo stimato $0,0575266). Nessun token copiato o mostrato. Il verificatore usa solo `Skill`, `Read`, `Grep`, `Glob`, budget massimo $0,50 per prova, timeout per prova di 240–300 s; nessuna scrittura del prodotto, pubblicazione o accesso al database di produzione. Il JSON del primo giro era in una directory temporanea locale e includeva estratti delle risposte: lo script è stato poi ristretto a non salvarli; non è un artefatto del repository.

| Prova | Caricata | Invocazione strutturale | Task | Costo stimato USD | Esito |
|---|---|---|---|---:|---|
| `copywriting` | sì | `Skill: copywriting` | alternativa headline, solo lettura | 0,2245934 | **VERIFICATA** |
| `seo-audit` | sì | `Skill: seo-audit` | audit statico, solo lettura | 0,1742002 | **VERIFICATA** |
| `cro` | sì | `Skill: cro` | ipotesi e metrica, solo lettura | 0,1899994 | **VERIFICATA** |
| `product-marketing` | sì | `Skill: product-marketing` | sezioni compilabili da README/roadmap, solo lettura | 0,2020668 | **VERIFICATA** |
| `animation-performance` | sì | `Skill: animation-performance` | revisione `dialog.tsx`, solo lettura | 0,1654582 | **VERIFICATA** |
| `review-animations` | sì | espansione di `/review-animations` nella trascrizione (giro 3) | revisione `dialog.tsx`, solo lettura | 0,2004016 | **VERIFICATA** |
| `supabase-postgres-best-practices` | sì | `Skill: supabase-postgres-best-practices` | revisione indici/RLS di migrazione locale, solo lettura | 0,3048592 | **VERIFICATA** |
| `vinea-marketing` | sì | espansione di `/vinea-marketing` nella trascrizione (giro 3) | bozza SEO su `robots.ts`, solo lettura | 0,1671598 | **VERIFICATA** |
| negativa | n/a | nessuna skill marketing | spiegazione di `age.ts`, solo lettura | 0,101585 | **OK** |

Le due manuali hanno richiesto tre giri, nessuno con errori API o di autenticazione:

1. **Giro 1** (tutte le nove prove, comando su stdin): `KO (non richiamata)` per entrambe ($0,2553574 e $0,2246734). Su stdin `/nome` arriva come testo libero e la CLI non lo espande.
2. **Giro 2** (comando come argomento posizionale): ancora `KO (non richiamata)` ($0,2427914 e $0,2285532). Quattro sessioni diagnostiche brevi (in tutto $0,1350118) hanno mostrato perché. Lo `stream-json` non ripete il prompt iniziale, quindi l'espansione non vi compare. La trascrizione di sessione della CLI registra invece `<command-name>/review-animations</command-name>` e un messaggio meta «Base directory for this skill: …/skills/review-animations» con il corpo della skill. Il modello ha poi letto `STANDARDS.md` della skill senza leggere `SKILL.md`.
3. **Giro 3**: il verificatore salva la sessione con un id noto, legge i soli messaggi utente della trascrizione, la cancella e richiede il marcatore di espansione in un blocco di testo. Esito `OK` per entrambe.

Nessuna trascrizione delle prove è rimasta nel profilo. Spesa stimata dell'intero collaudo ≈ $2,87, più una sonda diagnostica su stdin il cui costo non è stato registrato; nessuna prova ha superato $0,50.

## Secondo passaggio (31 ottobre 2026, storico)

Il 31 ottobre 2026, secondo passaggio, la CLI 2.1.316 riporta `loggedIn: false` in entrambi i profili: Anthropic Direct («OAuth session expired and could not be refreshed») e `vinea-coding` (credenziali del profilo senza token di accesso; OmniRoute su `127.0.0.1:20128` risponde 401 senza chiave e nel mio ambiente non esiste una chiave valida). Nessuna chiamata al modello è partita (costo 0). L'accesso è un'azione del titolare e non è stato aggirato. Lo script di prova è stato corretto prima di qualsiasi esecuzione: corrispondenza esatta del nome della skill (un nome nel testo o un nome simile non contano), prova strutturale per le skill manuali, esiti distinti per autenticazione, errore API, timeout e interferenza, strumenti ridotti a `Skill`, `Read`, `Grep`, `Glob` con `--tools`, limite di tempo e di spesa per sessione, tetto al buffer di uscita, nuova prova negativa (un task di programmazione non deve attivare le skill di marketing), esito salvato senza prompt né percorsi personali. 15 test offline del classificatore passano; l'esito reale restava allora NON VERIFICATO; è stato superato dal collaudo finale sopra.

## Rischi, costi, limitazioni

- **Rischio principale**: skill contestuali di marketing e `supabase-postgres-best-practices` possono attivarsi in contesti non voluti (la seconda dichiara «carica prima di qualsiasi SQL»). Mitigazione: precedenza di `CLAUDE.md` scritta nelle skill interne. La prova negativa (un task di codice) non ha attivato skill di marketing; è un solo caso, non una misura statistica.
- **Profili**: provato solo `vinea-coding` via OmniRoute (stima dei costi della CLI con avviso `unrecognized_model`). Anthropic Direct non è stato riprovato dopo l'OAuth scaduto del secondo passaggio.
- **Fonti**: le 29 fonti NON RISOLTE e la #103 NON LETTA restano tali; questo collaudo non le ha riaperte.
- **Conflitto noto**: i budget di durata di `review-animations` (UI sotto 300 ms) contraddicono i token Vinea (320/520 ms): le skill `vinea-design` e `vinea-review` dichiarano che i token prevalgono.
- **Contesto marketing**: `.agents/product-marketing.md` è stato redatto il 31 ottobre 2026 come **BOZZA — NON APPROVATA DAL TITOLARE**, solo con fatti del repository etichettati per stato (`[VERIFICATO]`, `[BETA]`, `[SPENTO]`, `[PIANIFICATO]`, `[IPOTESI]`, `[LEG]`), senza ricerche di mercato, testimonianze, risultati o promesse. `vinea-marketing` lo tratta come orientamento e non come fonte di claim. Finché il titolare non lo approva, l'output delle skill di marketing resta bozza.
- **Costo di contesto**: ≈1,2k token per sessione (coperti dalla cache); nessun nuovo servizio a pagamento; nessun benchmark a pagamento in questo ciclo. Il costo dei subagenti di audit non è misurato in USD.
- **Ambiente**: Python e FFmpeg non installati (bloccano UI/UX Pro Max, Claude Ads, Founder Skill, HyperFrames); Docker presente.
- **Limiti degli audit**: statici e parziali; un audit statico non equivale a un benchmark pratico. Nessun confronto prestazionale nuovo tra strumenti equivalenti.
- Nessuna modifica a `CLAUDE.md`, migration, database, OmniRoute o funzionalità applicative.

## Git

Worktree `skills-recovery-001`, branch `docs/skills-recovery-001`, da `origin/main` `a6e34ed` (PR #246 già integrata). PR, SHA di testa e stato dei check: nella PR e in `CHANGES.log`.

## Per chiudere il ciclo

1. Fatto: prova runtime nel profilo `vinea-coding`, otto skill più prova negativa OK.
2. Merge a check verdi e verifica da `origin/main` (lock, verificatore, `init` del profilo da un worktree aggiornato).
3. Separato e non bloccante per la chiusura tecnica: il titolare rivede e approva `.agents/product-marketing.md` (bozza presente, NON APPROVATA).
