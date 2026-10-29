#!/usr/bin/env node
// Guardia PreToolUse a lista bianca per i due subagenti Vinea con shell
// (VPM-LAB-002): `vinea-qa-runner` (profilo `qa`) e `vinea-release-verifier`
// (profilo `release`).
//
// Le regole `Bash(...)` dei permessi non sono un confine di sicurezza
// (`git -C . push`, `sh -c '...'` le aggirano). Il confine e' questa guardia:
// riceve dall'hook il JSON dello strumento su stdin e ammette SOLO i comandi
// elencati qui sotto, interi, senza metacaratteri della shell. Tutto il resto
// esce con codice 2 (Claude Code blocca lo strumento) e un messaggio che
// comincia con `VINEA-GUARD`, che il canarino degli agenti riconosce.
//
// Fail-closed: JSON illeggibile, profilo sconosciuto, strumento shell diverso da
// Bash o comando vuoto -> codice 2. L'hook nel frontmatter aggiunge `|| exit 2`,
// cosi' anche uno script mancante blocca invece di lasciar passare.
//
// Nessuna rete, nessuna dipendenza, nessuna scrittura.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const PREFISSO = "VINEA-GUARD";

// Solo caratteri innocui: niente `; & | $ ` > < ( ) * ? [ ] { } ' " \ #`,
// niente a capo. Gli spazi separano gli argomenti.
const CARATTERI_AMMESSI = /^[A-Za-z0-9 ._/:=@^~+,%-]+$/;

const SHA = /^[0-9a-f]{7,40}$/;
const REF = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const DIR_FRONTEND = new Set(["frontend", "frontend-next"]);
const SCRIPT_BUN = new Set(["lint", "typecheck", "test", "build"]);
const SCRIPT_TEST = /^\.github\/scripts\/[A-Za-z0-9._-]+\.test\.mjs$/;
const PATH_PYTEST = /^tests(\/[A-Za-z0-9._-]+)*\/?(::[A-Za-z0-9_]+)*$/;

// Opzioni di git che scrivono file, leggono fuori dal repository o cambiano la
// configurazione: vietate anche sui sottocomandi di lettura.
const OPZIONI_GIT_VIETATE = [
  /^--output(=|$)/,
  /^--no-index$/,
  /^--ext-diff$/,
  /^--exec(=|$)/,
  /^--upload-pack(=|$)/,
  /^--receive-pack(=|$)/,
  /^--git-dir(=|$)/,
  /^--work-tree(=|$)/,
];

const GIT_LETTURA = new Set(["status", "diff", "log", "show", "rev-parse"]);

function argomentiGitDiLettura(argomenti) {
  for (const a of argomenti) {
    if (OPZIONI_GIT_VIETATE.some((re) => re.test(a))) {
      return `opzione git non ammessa: ${a}`;
    }
  }
  return null;
}

// Comandi comuni ai due profili: git in sola lettura, fetch da origin e
// checkout staccato di uno SHA (o di origin/main) nel worktree isolato.
function regolaGit(token) {
  const [, sotto, ...resto] = token;
  if (!sotto || sotto.startsWith("-")) {
    return "git richiede il sottocomando come primo argomento (nessuna opzione globale come -C o -c)";
  }
  if (GIT_LETTURA.has(sotto)) {
    return argomentiGitDiLettura(resto);
  }
  if (sotto === "fetch") {
    if (resto[0] !== "origin") return "git fetch ammesso solo da origin";
    if (resto.length === 1) return null;
    if (resto.length === 2 && REF.test(resto[1])) return null;
    return "git fetch ammette solo `git fetch origin [ref]`";
  }
  if (sotto === "checkout") {
    if (
      resto.length === 2 &&
      resto[0] === "--detach" &&
      (SHA.test(resto[1]) || resto[1] === "origin/main")
    ) {
      return null;
    }
    return "git checkout ammesso solo come `git checkout --detach <sha|origin/main>`";
  }
  return `sottocomando git non ammesso: ${sotto}`;
}

function regolaQa(token) {
  const [cmd, ...arg] = token;
  if (cmd === "git") return regolaGit(token);
  if (cmd === "bun") {
    // bun --cwd <frontend|frontend-next> install --frozen-lockfile
    // bun --cwd <frontend|frontend-next> run <lint|typecheck|test|build>
    if (arg[0] !== "--cwd" || !DIR_FRONTEND.has(arg[1])) {
      return "bun ammesso solo con `--cwd frontend` o `--cwd frontend-next`";
    }
    const azione = arg.slice(2);
    if (azione.length === 2 && azione[0] === "install" && azione[1] === "--frozen-lockfile") {
      return null;
    }
    if (azione.length === 2 && azione[0] === "run" && SCRIPT_BUN.has(azione[1])) {
      return null;
    }
    return "bun ammette solo `install --frozen-lockfile` e `run lint|typecheck|test|build`";
  }
  if (cmd === "python") {
    const forma = arg.join(" ");
    if (forma === "-m compileall -q ." || forma === "-m ruff check .") return null;
    if (arg[0] === "-m" && arg[1] === "pytest") {
      for (const a of arg.slice(2)) {
        if (a === "-q" || a === "-x") continue;
        if (PATH_PYTEST.test(a) && !a.split(/\/|::/).includes("..")) continue;
        return `argomento pytest non ammesso: ${a}`;
      }
      return null;
    }
    return "python ammette solo `-m compileall -q .`, `-m ruff check .` e `-m pytest [-q] [-x] [tests/...]`";
  }
  if (cmd === "node") {
    if (arg[0] === "--test" && arg.length > 1 && arg.slice(1).every((a) => SCRIPT_TEST.test(a))) {
      return null;
    }
    return "node ammesso solo come `node --test .github/scripts/<nome>.test.mjs`";
  }
  if (cmd === "cd") {
    if (arg.length === 1 && ["frontend", "frontend-next", "backend", ".."].includes(arg[0])) {
      return null;
    }
    return "cd ammesso solo verso frontend, frontend-next, backend o ..";
  }
  return `comando non ammesso: ${cmd}`;
}

const GH_PR = new Set(["view", "checks", "diff", "list"]);
const GH_RUN = new Set(["view", "list"]);
const OPZIONI_GH_API_VIETATE = /^(-X|--method|-f|-F|--field|--raw-field|--input|-H|--header)(=|$)/;

function regolaRelease(token) {
  const [cmd, sotto, ...resto] = token;
  if (cmd === "git") return regolaGit(token);
  if (cmd === "gh") {
    if (sotto === "pr") {
      return GH_PR.has(resto[0]) ? null : `gh pr ${resto[0] ?? ""} non ammesso`;
    }
    if (sotto === "run") {
      return GH_RUN.has(resto[0]) ? null : `gh run ${resto[0] ?? ""} non ammesso`;
    }
    if (sotto === "api") {
      const percorso = resto[0] ?? "";
      if (!/^\/?repos\//.test(percorso)) {
        return "gh api ammesso solo su percorsi repos/... (niente graphql)";
      }
      for (const a of resto.slice(1)) {
        if (OPZIONI_GH_API_VIETATE.test(a) || /^-[A-Za-z]*[XfFH]/.test(a) && !a.startsWith("--")) {
          return `gh api ammesso solo in GET: opzione ${a} vietata`;
        }
      }
      return null;
    }
    return `gh ${sotto ?? ""} non ammesso`;
  }
  return `comando non ammesso: ${cmd}`;
}

const PROFILI = { qa: regolaQa, release: regolaRelease };

/**
 * Decide se un comando shell e' ammesso dal profilo.
 * @returns {string|null} null se ammesso, altrimenti il motivo del rifiuto.
 */
export function valuta(profilo, comando) {
  const regola = PROFILI[profilo];
  if (!regola) return `profilo sconosciuto: ${profilo}`;
  if (typeof comando !== "string" || comando.trim() === "") return "comando vuoto";
  if (!CARATTERI_AMMESSI.test(comando)) {
    return "metacarattere della shell o carattere non ammesso nel comando";
  }
  const token = comando.trim().split(/ +/);
  return regola(token);
}

/**
 * Decide sull'intero evento PreToolUse.
 * @returns {string|null} null se lo strumento puo' procedere.
 */
export function valutaEvento(profilo, evento) {
  if (!evento || typeof evento !== "object") return "evento dell'hook illeggibile";
  const strumento = evento.tool_name;
  if (strumento === "Bash") return valuta(profilo, evento.tool_input?.command);
  if (strumento === "PowerShell") return "PowerShell non e' ammesso per questo agente";
  if (!PROFILI[profilo]) return `profilo sconosciuto: ${profilo}`;
  return null;
}

function profiloDaArgv(argv) {
  const i = argv.indexOf("--profile");
  return i >= 0 ? argv[i + 1] : undefined;
}

function main() {
  const profilo = profiloDaArgv(process.argv.slice(2));
  let evento;
  try {
    evento = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    evento = null;
  }
  const motivo = valutaEvento(profilo, evento);
  if (motivo) {
    process.stderr.write(`${PREFISSO}: bloccato (profilo ${profilo ?? "assente"}): ${motivo}\n`);
    process.exit(2);
  }
  process.exit(0);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
