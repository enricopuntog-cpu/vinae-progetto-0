# Handoff PM — AI Skills Lab, RECOVERY-001

31 ottobre 2026. Matrice di assegnazione delle skill ai reparti Vinea. Distingue le **competenze operative** (nel repository, caricate dal profilo) dalle **candidate** (rinviate, bloccate, scartate). È una matrice di decisioni, non un'autorizzazione ad attivare funzionalità. Prove e limiti: `VINEA_SKILLS_RECOVERY_REPORT.md`; registro: `VINEA_SKILLS_REGISTRY.md`. Nulla è pubblicato né inviato al PM da questa sessione: il passaggio è del titolare.

Avvertenza trasversale (collaudo finale 31 ottobre 2026): **tutte e otto le nuove skill hanno prova strutturale di invocazione nel profilo `vinea-coding`** (sei contestuali con lo strumento `Skill`, le due manuali `review-animations` e `vinea-marketing` con l'espansione del comando), e la prova negativa è OK. Anthropic Direct non è stato riprovato dopo il precedente OAuth scaduto. Le bozze marketing restano non pubblicabili senza approvazione editoriale/LEG.

| Reparto | Competenze operative | Candidate (stato) | Decisione / prerequisito |
|---|---|---|---|
| DEV | `supabase-postgres-best-practices` (invocazione provata); `vinea-task`/`vinea-review` instradano verso di essa; `vinea-browser-qa` per i controlli nel browser | gstack, Ruflo (scartate); Vercel agent-skills (rinviata: nessun file LICENSE nell'intero albero upstream, riverificato il 31 ottobre 2026) | Per Vercel serve un LICENSE nel repository upstream; non importare finché manca |
| ARCHITETTURA | `vinea-architecture-mapper` (esistente) | Archify (rinviata: lettura integrale del CLI e trial senza rete) | Decidere se servono diagrammi condivisibili oltre alla mappa testuale |
| DESIGN / UX | `frontend-design`, `vinea-design`, `review-animations`, `animation-performance` | UI/UX Pro Max (rinviata: Python assente, palette vino in conflitto), Taste/Impeccable (scartate), Magic MCP (scartata) | I token di movimento Vinea prevalgono sui budget generici; decisione del titolare su una eventuale versione solo-dati di UI/UX Pro Max |
| SECURITY | `vinea-security`, `vinea-security-auditor`, `vinea-external-skill-audit` | Strix (bloccata), SkillSpector (solo laboratorio), InRegola (non verificata) | Strix richiede chiave LLM autorizzata, rete Docker interna, istanza con dati fittizi e decisione su budget e telemetria; mai contro produzione |
| QA / BETA | `vinea-test`, `vinea-qa-runner`; **`vinea-browser-qa` + suite Playwright Test 1.64.1 in `frontend-next/e2e/` (VPM-LAB-003: 33 casi, Chromium, 375 px, WebKit, stack isolato)**; `/review-animations` per il movimento | Playwright CLI (rinviata: nessun beneficio dimostrato rispetto alla suite), test con utenti sintetici (#118, non risolta), checklist rete/sessione/pagamento/cancellazione (#55) | Gli scenari di #55 sono casi da aggiungere alla suite (`e2e/`); lo smoke gira nel workflow `E2E browser` (non required); prova dal profilo `vinea-coding` ancora da fare dalla shell del titolare |
| MARKETING | `/vinea-marketing` (manuale, invocazione provata), `copywriting`, `seo-audit`, `cro`, `product-marketing` (invocate e provate) | altre Marketing Skills, Stop Slop, Humanizer (rinviate); Claude Ads (rinviata); Scrapling, Agent-Reach (scartate); servizi video/social (non pertinenti) | `.agents/product-marketing.md` esiste ed è BOZZA — NON APPROVATA DAL TITOLARE; futura approvazione separata, non blocca i test tecnici; nessuna indicizzazione di `/accessori`; revisione umana di ogni testo |
| PRODUCT | `cro` (ipotesi senza baseline), `product-marketing` | «Tribunale» (#112, non risolta), Founder Skill (rinviata) | Le simulazioni non sono validazione di mercato; decidere esperimenti e KPI separatamente |
| LOGISTICA | — | #76 (packaging) e #24 (vendita di vino online) non sono strumenti | Tema per chat logistica/legale, non per skill |
| FINANZA | — | Founder Skill, prompt di #43 (non strumenti), hosting «$0/mese» (#113, non dimostrato) | Nessuna adozione; usare i numeri reali del Business Plan |
| LEGALE | `vinea-marketing` impone `REVISIONE LEG OBBLIGATORIA` sui contenuti per alcolici | — | Parere su pubblicità e vendita a distanza di alcolici; licenza Remotion (organico Vinea) |
| PRODUTTIVITÀ / COSTI | prompt caching nativa (hit 94,3%) | ccusage (rinviata), Context Mode (scartata), Context Engineering (scartata) | Nessuna modifica a OmniRoute; ottenere costo reale per finestra comparabile prima di un A/B |
| LAB | guida ufficiale Anthropic (standard), `claude-skill-runtime-check.mjs` | find-skills (scartata) | OmniRoute funziona; in headless i comandi manuali vanno passati come argomento posizionale di `claude -p`, mai su stdin |

## Decisioni e input richiesti al titolare

1. Se serve l'uso col profilo Anthropic Direct, autenticare quella sessione separatamente e ripetere `claude-skill-runtime-check.mjs` (non provato in questo ciclo).
2. Approvare o correggere in una decisione editoriale separata `.agents/product-marketing.md` (bozza presente, marcata «NON APPROVATA DAL TITOLARE»: le sezioni «Claim ancora da approvare» e «Questioni legali» sono divieti finché non decide il titolare).
3. Fornire gli elenchi/link delle 29 fonti NON RISOLTE che interessano (priorità: #2, #55, #109, #112, #118) o confermare che restano chiuse.
4. Decidere su Strix (budget, chiave LLM, rete isolata) e su UI/UX Pro Max solo-dati.
5. Chiarire l'organico di Vinea per la licenza Remotion, se i video diventano un task.
