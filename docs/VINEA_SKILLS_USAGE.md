# Uso delle skill — Ciclo 2 e RECOVERY-001

31 ottobre 2026. Guida operativa alle skill del progetto: cosa si può invocare davvero, come, e con quali limiti. Leggere prima `CLAUDE.md` e `CHANGES.log`. Questa guida non concede permessi né accesso a dati, reti o ambienti di produzione. Stato di ogni skill in `VINEA_SKILLS_REGISTRY.md`; motivi delle esclusioni in `VINEA_SKILLS_CANDIDATES.md`.

## Prima di contare su una skill

Le skill di progetto vivono in `.claude/skills/` e si caricano nel **worktree o profilo effettivo**. Verifica l'elenco con una sessione headless e leggi l'evento `init`; nel profilo `vinea-coding` risultano caricate le sette skill di terzi, `vinea-marketing` e il plugin `frontend-design`. Il profilo di default della sessione desktop non carica `frontend-design`. `vinea-design` e `vinea-security` si attivano solo quando i file aperti corrispondono ai loro `paths:`.

La prova di **invocazione** delle nuove skill è NON VERIFICATA (login CLI scaduto). Dopo aver rinnovato l'accesso:

    CLAUDE_CONFIG_DIR=<profilo vinea-coding> node .github/scripts/claude-skill-runtime-check.mjs

Lo script lancia otto sessioni headless in sola lettura (circa 0,3–0,5 USD stimati ciascuna), controlla che la skill sia elencata e richiamata, e dichiara `NON VERIFICATO` se l'autenticazione fallisce. Non è un controllo di CI.

## Comandi e attivazioni

| Voce | Come si usa | Quando |
|---|---|---|
| `/vinea-task VPM-ID …` | manuale | avvio di un task con preflight e instradamento verso le altre skill |
| `/vinea-test`, `/vinea-review`, `/vinea-security`, `/vinea-design` | contestuali | test, review, sicurezza, frontend; ora instradano anche verso le skill di terzi |
| `/vinea-external-skill-audit <percorso>` | manuale | audit non esecutivo di una candidata prima di una PR di adozione |
| `/vinea-marketing copy\|seo\|cro\|contesto …` | manuale | bozze di marketing con le regole Vinea; mai pubblicazioni |
| `/review-animations <file o diff>` | manuale | revisione di transizioni e animazioni, sola lettura |
| `animation-performance` | contestuale | fluidità, proprietà composite, frame budget |
| `supabase-postgres-best-practices` | contestuale | SQL, indici, RLS e prestazioni, migrazioni |
| `copywriting`, `seo-audit`, `cro`, `product-marketing` | contestuali (o via `/vinea-marketing`) | richieste di copy, SEO, CRO e contesto di prodotto |

## Esempi per i task

- **Frontend con animazioni:** «Per la modifica già ammessa usa `/vinea-design`; poi `/review-animations` sui file toccati. I token di movimento Vinea (`--dur-med` 320 ms, `--dur-slow` 520 ms) prevalgono sui budget generici.»
- **Migrazione SQL:** «Rivedi la migrazione per indici sulle chiavi esterne e prestazioni delle policy RLS con `supabase-postgres-best-practices`; gli invarianti di sicurezza sono quelli di `CLAUDE.md` e non si riproducono gli esempi di ruoli o password dei riferimenti.»
- **Copy:** «`/vinea-marketing copy` sulla Home: massimo tre varianti, ogni claim non provato nel repository marcato `CLAIM DA PROVARE`; nulla viene pubblicato o scritto nel prodotto.»
- **SEO:** «`/vinea-marketing seo` sui file indicati: osservazioni statiche separate da crawl e indicizzazione non eseguiti; nessuna proposta di indicizzare route dietro gate.»
- **CRO:** «`/vinea-marketing cro`: ipotesi, metrica e prerequisiti; niente conversioni o risultati inventati.»
- **Candidata esterna:** «`/vinea-external-skill-audit <percorso>`; poi eventuale scansione SkillSpector `--no-llm` in laboratorio (credenziali rimosse, rete bloccata) e riesame a mano dei rilievi; solo dopo, una PR che aggiunge la skill byte-identica e la sua voce nel lock.»

## Come aggiungere o aggiornare una skill di terzi

1. Audit con `/vinea-external-skill-audit` su un clone al commit fisso; licenza da un file `LICENSE`, non dal solo frontmatter.
2. Scansione SkillSpector `--no-llm` e riesame manuale di ogni rilievo (un punteggio non è una prova).
3. Copia byte-identica dai blob git di quel commit (fine riga LF), con `LICENSE`; esclusi test e fixture dell'upstream.
4. Voce nel lock `.github/scripts/claude-skills.lock.json` (repo, commit completo, licenza, SHA-256 di ogni file, scanner, riesame, `invocation`).
5. Se serve un instradamento, modifica una skill `vinea-*`; mai file di terzi.
6. `node .github/scripts/claude-setup-verify.mjs` e `node --test .github/scripts/claude-setup-verify.test.mjs`; PR dedicata con CI verde.

Regole del verificatore: nessun `allowed-tools`, `hooks` o iniezione di shell; SKILL.md fino a 600 righe per le esterne, 300 per le interne; nessun percorso personale o segreto; file e SHA devono coincidere col lock.

## Standard di scrittura (guida ufficiale Anthropic, fonte #114)

Si applicano alle skill interne: svolgere il lavoro con Claude prima di trasformarlo in skill; descrizione mirata, perché decide quando parte; esempi; file principale breve con il resto in `references/` aperto solo quando serve; una sessione scrive la skill, un'altra la prova sul lavoro vero.

## Cache e costi

La cache dei prompt è nativa e già attiva (hit rate registrato 94,3% su Claude nel Ciclo 2). Per non romperla: non cambiare modello a metà sessione, non riscrivere `CLAUDE.md` durante il lavoro, preferire skill con descrizione breve o manuali. Le sei skill contestuali aggiunte pesano ≈1,2k token di descrizioni. Non si adottano cache semantiche (Context Mode scartato): potrebbero restituire stati Git, CI o test obsoleti. Nessuna impostazione OmniRoute è stata modificata. `ccusage` è rinviato; la fonte di costo autorevole resta l'SQLite di OmniRoute.

## Regole operative

Un audit statico non autorizza un'installazione. Non installare strumenti con licenze non chiarite, hook rischiosi, MCP nuovi, accessi a credenziali o costi. Non importare export Instagram privati, account o DM. Test offensivi solo contro istanze locali isolate, mai contro produzione o sistemi di terzi (Strix è bloccato). Nessuna pubblicazione di bozze di marketing.
