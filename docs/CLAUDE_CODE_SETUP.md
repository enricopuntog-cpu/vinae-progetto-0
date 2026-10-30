# Configurazione Claude Code di progetto

Ambiente Claude Code condiviso e versionato del repository Vinea (VPM-LAB-002,
disegno approvato in VPM-LAB-001B). Vale per ogni profilo di configurazione:
Anthropic Direct (`~/.claude`) e il profilo OmniRoute
(`~/.claude/profiles/vinea-coding`). La costituzione operativa resta
`CLAUDE.md`: niente qui la estende o la sostituisce.

## Cosa e' versionato

```text
.claude/settings.json                     plugin, marketplace, permessi ask/deny
.claude/agents/*.md                       6 subagenti
.claude/skills/*/SKILL.md                 7 skill (+ references/)
.github/scripts/claude-plugins.lock.json  lock di frontend-design
.github/scripts/claude-agent-guard.mjs    guardia shell dei due agenti con Bash
.github/scripts/claude-secret-guard.mjs    guardia dei file di segreti
.github/scripts/claude-setup-verify.mjs   verifica statica (CI)
.github/scripts/claude-bootstrap.mjs      bootstrap locale (mai in CI)
```

Tutto il resto di `.claude/` resta ignorato: `settings.local.json`,
`worktrees/`, `agent-memory*/`, `commands/`, `hooks/`, `plans/`, `todos/`,
credenziali, file `*.local.*`, `.env`, `*.pem`, `*.key`, e qualunque `.claude/`
annidato in una sottodirectory. La matrice esatta e' `MATRICE_GITIGNORE` in
`claude-setup-verify.mjs`.

## Agenti

| Agente | Strumenti | Uso |
|---|---|---|
| `vinea-code-reviewer` | Read, Grep, Glob | revisione statica di diff o file |
| `vinea-security-auditor` | Read, Grep, Glob | audit contro gli invarianti di `CLAUDE.md` |
| `vinea-ux-auditor` | Read, Grep, Glob | audit UX contro design system e versione servita |
| `vinea-architecture-mapper` | Read, Grep, Glob | propagazione di un cambiamento tra gli stack |
| `vinea-qa-runner` | Read, Grep, Glob, Bash | lint/typecheck/test/build su uno SHA |
| `vinea-release-verifier` | Read, Grep, Glob, Bash | verifica post-merge di `origin/main`, PR e CI |

Regole comuni, imposte dalla verifica statica:

- `tools` esplicito (senza, l'agente erediterebbe tutto), `model: inherit`,
  `maxTurns` e nessun `permissionMode` tra `bypassPermissions`, `auto`,
  `acceptEdits`;
- mai `Agent`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`,
  `WebSearch`; gli MCP ammessi sono solo quelli `supabase-ro` di lettura e
  oggi nessun agente ne elenca uno;
- ogni agente ha l'hook della guardia dei segreti.

I due agenti con shell girano con `isolation: worktree` e un hook PreToolUse
su Bash che invoca `claude-agent-guard.mjs --profile qa|release`. La guardia e'
una lista bianca: ammette solo i comandi elencati, interi e senza metacaratteri
di shell, ed esce con 2 e il prefisso `VINEA-GUARD` per tutto il resto. Prima di
ogni altro comando l'agente esegue il canarino
`git push --dry-run vinea-guard-canary`: se non viene bloccato con
`VINEA-GUARD`, la guardia non e' attiva e l'agente si ferma.

## Skill

| Skill | Invocazione | Scopo |
|---|---|---|
| `vinea-task` | solo manuale | avvio di un task VPM con preflight Git e scope |
| `vinea-test` | contestuale | test pertinenti dopo una modifica |
| `vinea-review` | contestuale | review di una PR o del diff corrente |
| `vinea-security` | contestuale (`paths:`) | controllo mirato su Supabase, backend, auth, pagamenti |
| `vinea-design` | contestuale (`paths:`) | frontend con brand e frontend-design |
| `vinea-skill-evaluation` | solo manuale | esito di un task VPM contro i criteri |
| `vinea-external-skill-audit` | solo manuale | audit non esecutivo di candidate esterne prima di qualsiasi installazione |

Il registro delle fonti esterne e delle decisioni è in
[`VINEA_SKILLS_REGISTRY.md`](VINEA_SKILLS_REGISTRY.md); le 119 voci storiche
non equivalgono a 119 skill installate o verificate.

Le skill non usano `allowed-tools`, hook o iniezione di shell `` !`cmd` ``,
restano sotto 300 righe e spostano il materiale lungo in `references/`.

## Plugin frontend-design e lock

`.claude/settings.json` abilita `frontend-design@claude-plugins-official` e
dichiara il marketplace ufficiale `anthropics/claude-plugins-official` con
`autoUpdate: false`. Nessun altro marketplace e' ammesso.

Il lock fissa versione, commit upstream e SHA-256 di `SKILL.md` e
`LICENSE.txt`. Il plugin si carica dalla copia del marketplace tramite
`enabledPlugins` di progetto; il bootstrap controlla anche le copie in
`plugins/cache/claude-plugins-official/frontend-design/<versione>`.

Per aggiornare il lock:

1. aggiornare il marketplace in un profilo di prova e leggere il diff upstream
   del plugin rispetto al commit nel lock;
2. se il contenuto e' accettabile, aggiornare `commit`, `version`, i due
   `sha256` e `reviewedAt` in una PR dedicata;
3. rieseguire il bootstrap in `--check` su ogni profilo.

Il bootstrap non aggiorna mai il lock e non installa sopra una deriva.

## Bootstrap locale

```bash
node .github/scripts/claude-bootstrap.mjs --check \
  --config-dir ~/.claude --config-dir ~/.claude/profiles/vinea-coding
```

- `--check` (default) legge soltanto. Senza `--config-dir` usa
  `CLAUDE_CONFIG_DIR` oppure `~/.claude`.
- `--install` agisce solo se manca qualcosa: aggiunge il marketplace ufficiale
  e installa `frontend-design@claude-plugins-official --scope project`. Mai
  `--yes`, mai altri marketplace.
- Richiede Claude Code >= 2.1.277.
- Esiti: `OK`, `MANCANTE`, `DERIVA` (contenuto diverso dal lock: rivedere il
  diff e aggiornare il lock con una PR), `ERRORE`. Esce con 0 solo se ogni
  profilo e' `OK`; con 2 su un'opzione non valida.

## Modello dei permessi

- `permissions.ask`: `claude plugin *`, `claude mcp *`, `npm install -g *`
  (Bash e PowerShell), `winget *`.
- `permissions.deny`: `Read(.env)`, `Read(.env.*)`, `Read(!.env.example)`,
  `Read(*.pem)`, `Read(*.key)`.
- Vietati nel file di progetto: `hooks`, `env`, `permissions.allow`,
  `defaultMode`, `apiKeyHelper`, `mcpServers`. Le liste allow restano locali in
  `settings.local.json`, che non e' versionato.
- La guardia dei segreti e' il secondo livello, solo dentro i sei agenti (il
  file di progetto non puo' dichiarare `hooks`): rifiuta Read/Grep/Glob su file
  di segreti e i comandi Bash/PowerShell che li nominano. La sessione
  principale e' coperta dalle sole regole `deny`.

## CI

Il passo `Claude Code setup` del job `continuity-scripts` esegue
`node --check` sui tre script, i test delle due guardie, della verifica e del
bootstrap (con una CLI finta), poi `claude-setup-verify.mjs`. Il bootstrap
reale non gira mai in CI.

## Limiti noti

- Le regole `Bash(...)` e `deny` non sono un confine di sicurezza: il confine
  degli agenti con shell e' la guardia a lista bianca. La guardia dei segreti
  controlla i nomi, non i contenuti: un nome costruito a runtime la aggira. La
  difesa principale resta non avere segreti nei worktree degli agenti.
- La negazione `Read(!.env.example)` non e' documentata come sintassi
  supportata. Effetto misurato il 29 ottobre 2026 in sessioni nuove
  (Claude Code 2.1.312, profilo `vinea-coding`, `claude -p`): `.env` della
  radice e `frontend-next/.env.local` finti negati, `frontend-next/.env.example`
  letto; senza le impostazioni di progetto (`--setting-sources user`) lo stesso
  `.env` viene letto. Le regole valgono solo per sessioni avviate dopo che il
  file e' presente nel worktree.
- Gli `hooks` nel frontmatter degli agenti si caricano solo se la cartella e'
  considerata attendibile dal file di configurazione globale del profilo. Con
  `CLAUDE_CONFIG_DIR=~/.claude` (configurazione `~/.claude/.claude.json`, senza
  il progetto) il canarino di `vinea-qa-runner` non e' stato bloccato e
  l'agente si e' fermato con `GUARDIA NON ATTIVA`; sul profilo `vinea-coding`,
  che ha il checkout fra i progetti attendibili, e' stato bloccato. La causa
  (attendibilita') e' un'ipotesi non verificata; il canarino ha comunque
  fermato l'agente prima di ogni altro comando.
- Il 30 ottobre 2026 `frontend-design` 1.1.1 e' stato installato nel profilo
  `vinea-coding` con `claude plugin install ... --scope project` per il worktree
  `skills-ciclo-1`: `claude plugin list --json` lo mostra abilitato, il bootstrap
  `--check` conferma due copie conformi al lock e una nuova sessione `claude -p`
  lo elenca come `frontend-design:frontend-design`. Una copia nel marketplace
  da sola non prova l'installazione; caricamento interattivo e altri worktree
  restano da verificare separatamente.
- Le skill con `paths` (`vinea-design`, `vinea-security`) compaiono solo dopo
  che la sessione ha letto un file nei percorsi dichiarati; `vinea-task` e
  `vinea-skill-evaluation` non sono visibili al modello (solo manuali).
- I worktree creati da una base precedente a questa configurazione non hanno
  `.claude/agents` ne' `.claude/skills`: vanno ricreati da `origin/main`
  aggiornato.
- Il canarino prova che la guardia e' attiva in quella sessione, non che lo
  resti se il file della guardia cambia durante la sessione.
