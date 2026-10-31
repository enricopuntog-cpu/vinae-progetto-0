# Handoff PM — AI Skills Lab, RECOVERY-001

31 ottobre 2026. Matrice di assegnazione delle skill ai reparti Vinea. Distingue le **competenze operative** (nel repository, caricate dal profilo) dalle **candidate** (rinviate, bloccate, scartate). È una matrice di decisioni, non un'autorizzazione ad attivare funzionalità. Prove e limiti: `VINEA_SKILLS_RECOVERY_REPORT.md`; registro: `VINEA_SKILLS_REGISTRY.md`. Nulla è pubblicato né inviato al PM da questa sessione: il passaggio è del titolare.

Avvertenza trasversale: **nessuna delle nuove skill ha una prova di invocazione** (login CLI scaduto). «Operativa» qui significa presente, integra e caricata dal profilo `vinea-coding`.

| Reparto | Competenze operative | Candidate (stato) | Decisione / prerequisito |
|---|---|---|---|
| DEV | `supabase-postgres-best-practices`; `vinea-task`/`vinea-review` instradano verso di essa | gstack, Ruflo (scartate); Vercel agent-skills (rinviata: manca un file di licenza) | Eseguire la prova di invocazione; per Vercel serve un LICENSE nel repository upstream |
| ARCHITETTURA | `vinea-architecture-mapper` (esistente) | Archify (rinviata: lettura integrale del CLI e trial senza rete) | Decidere se servono diagrammi condivisibili oltre alla mappa testuale |
| DESIGN / UX | `frontend-design`, `vinea-design`, `review-animations`, `animation-performance` | UI/UX Pro Max (rinviata: Python assente, palette vino in conflitto), Taste/Impeccable (scartate), Magic MCP (scartata) | I token di movimento Vinea prevalgono sui budget generici; decisione del titolare su una eventuale versione solo-dati di UI/UX Pro Max |
| SECURITY | `vinea-security`, `vinea-security-auditor`, `vinea-external-skill-audit` | Strix (bloccata), SkillSpector (solo laboratorio), InRegola (non verificata) | Strix richiede chiave LLM autorizzata, rete Docker interna, istanza con dati fittizi e decisione su budget e telemetria; mai contro produzione |
| QA / BETA | `vinea-test`, `vinea-qa-runner`; `/review-animations` per il movimento | Playwright CLI (rinviata), test con utenti sintetici (#118, non risolta), checklist rete/sessione/pagamento/cancellazione (#55) | Assegnare un task E2E con owner; gli scenari di #55 sono casi di test da implementare |
| MARKETING | `/vinea-marketing`, `copywriting`, `seo-audit`, `cro`, `product-marketing` | altre Marketing Skills, Stop Slop, Humanizer (rinviate); Claude Ads (rinviata); Scrapling, Agent-Reach (scartate); servizi video/social (non pertinenti) | Approvare `.agents/product-marketing.md` (da creare) prima di usare le bozze; nessuna indicizzazione di `/accessori`; revisione umana di ogni testo |
| PRODUCT | `cro` (ipotesi senza baseline), `product-marketing` | «Tribunale» (#112, non risolta), Founder Skill (rinviata) | Le simulazioni non sono validazione di mercato; decidere esperimenti e KPI separatamente |
| LOGISTICA | — | #76 (packaging) e #24 (vendita di vino online) non sono strumenti | Tema per chat logistica/legale, non per skill |
| FINANZA | — | Founder Skill, prompt di #43 (non strumenti), hosting «$0/mese» (#113, non dimostrato) | Nessuna adozione; usare i numeri reali del Business Plan |
| LEGALE | `vinea-marketing` impone `REVISIONE LEG OBBLIGATORIA` sui contenuti per alcolici | — | Parere su pubblicità e vendita a distanza di alcolici; licenza Remotion (organico Vinea) |
| PRODUTTIVITÀ / COSTI | prompt caching nativa (hit 94,3%) | ccusage (rinviata), Context Mode (scartata), Context Engineering (scartata) | Nessuna modifica a OmniRoute; ottenere costo reale per finestra comparabile prima di un A/B |
| LAB | guida ufficiale Anthropic (standard), `claude-skill-runtime-check.mjs` | find-skills (scartata) | Rinnovare il login CLI e rieseguire la prova di invocazione |

## Decisioni e input richiesti al titolare

1. Rinnovare l'accesso della CLI (`claude` interattivo) per sbloccare la prova di invocazione e la chiusura del ciclo.
2. Approvare o correggere il contesto di prodotto di `.agents/product-marketing.md` (bozza presente, marcata «NON APPROVATA DAL TITOLARE»: le sezioni «Claim ancora da approvare» e «Questioni legali» sono divieti finché non decide il titolare).
3. Fornire gli elenchi/link delle 29 fonti NON RISOLTE che interessano (priorità: #2, #55, #109, #112, #118) o confermare che restano chiuse.
4. Decidere su Strix (budget, chiave LLM, rete isolata) e su UI/UX Pro Max solo-dati.
5. Chiarire l'organico di Vinea per la licenza Remotion, se i video diventano un task.
