# Uso delle skill — Ciclo 2 e RECOVERY-001

31 ottobre 2026. Guida operativa alle skill del progetto: cosa si può invocare davvero, come, e con quali limiti. Leggere prima `CLAUDE.md` e `CHANGES.log`. Questa guida non concede permessi né accesso a dati, reti o ambienti di produzione. Stato di ogni skill in `VINEA_SKILLS_REGISTRY.md`; motivi delle esclusioni in `VINEA_SKILLS_CANDIDATES.md`.

## Prima di contare su una skill

Le skill di progetto vivono in `.claude/skills/` e si caricano nel **worktree o profilo effettivo**. Verifica l'elenco con una sessione headless e leggi l'evento `init`; nel profilo `vinea-coding` risultano caricate le sette skill di terzi, `vinea-marketing` e il plugin `frontend-design`. Il profilo di default della sessione desktop non carica `frontend-design`. `vinea-design` e `vinea-security` si attivano solo quando i file aperti corrispondono ai loro `paths:`.

La prova di **invocazione** nel profilo `vinea-coding` (31 ottobre 2026) ha confermato **tutte e otto le nuove skill** e la prova negativa. Le sei contestuali sono richiamate dal modello con lo strumento `Skill`; le due manuali (`review-animations`, `vinea-marketing`) si avviano solo con il comando `/nome`. In headless il comando funziona **solo come argomento posizionale** di `claude -p` (`claude -p "/review-animations <file>"`): passato su stdin arriva come testo libero e non viene espanso. Una risposta pertinente non è prova di invocazione. Dettagli e costi nel rapporto RECOVERY-001. Per ripetere il controllo da una shell che ha già il profilo OmniRoute configurato, senza inserire token negli argomenti:

    node .github/scripts/claude-skill-runtime-check.mjs --budget-usd 0.5

Lo script lancia dieci sessioni headless (nove skill più una prova negativa; `--solo vinea-browser-qa` prova la sola skill browser, VPM-LAB-003, non ancora verificata nel profilo) con i soli strumenti `Skill`, `Read`, `Grep`, `Glob`, ciascuna con limite di tempo (240 s per impostazione predefinita) e tetto di spesa **non superiore a 0,50 USD per prova** (`--budget-usd` può solo abbassarlo). Una skill è OK solo se è elencata nell'evento `init` **e** richiamata con prova strutturale; il nome nel testo non basta. Per le contestuali la prova è lo strumento `Skill` con nome esatto nel flusso `stream-json`. Per le manuali lo script passa il comando come argomento posizionale (forma ristretta, sicura per la shell) e salva la sessione con un id noto: il flusso non ripete il prompt iniziale, mentre la trascrizione della CLI registra l'espansione (`<command-name>/nome</command-name>` e il corpo della skill). Lo script legge i soli messaggi utente della trascrizione e poi la **cancella**. Esiti: `OK`, `KO (non elencata | non richiamata | errore API | limite | timeout | interferenza)`, `NON VERIFICATO (autenticazione | non avviata)`. Il JSON (`--out file.json`) non salva prompt, risposte, stderr o credenziali. Non è un controllo di CI. In una sessione interattiva i comandi si usano normalmente (`/review-animations <file>`, `/vinea-marketing <area> <file>`).

Profili: la sessione corrente `vinea-coding` ha permesso una chiamata headless reale via OmniRoute (CLI 2.1.316, `success`), senza rinnovo né copia di credenziali. `claude auth status` non sostituisce la chiamata al modello. Il vecchio fallimento del profilo Anthropic Direct (OAuth scaduto nel secondo passaggio) è una misura storica, **non** una prova di compatibilità attuale: per Direct occorre una sessione autenticata separata; non trasferire le variabili OmniRoute in Direct.

## Comandi e attivazioni

| Voce | Come si usa | Quando |
|---|---|---|
| `/vinea-task VPM-ID …` | manuale | avvio di un task con preflight e instradamento verso le altre skill |
| `/vinea-test`, `/vinea-review`, `/vinea-security`, `/vinea-design` | contestuali | test, review, sicurezza, frontend; ora instradano anche verso le skill di terzi |
| `/vinea-external-skill-audit <percorso>` | manuale | audit non esecutivo di una candidata prima di una PR di adozione |
| `/vinea-marketing copy\|seo\|cro\|contesto …` | manuale | bozze di marketing con le regole Vinea; mai pubblicazioni |
| `/vinea-browser-qa [smoke\|completa\|-g <caso>\|esplora]` | contestuale | suite browser Playwright su stack Supabase isolato; per ogni modifica frontend significativa; guida in `E2E_BROWSER.md` |
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
