#!/usr/bin/env node
// Verifica statica della configurazione Claude Code di progetto (VPM-LAB-002).
//
// Controlla .claude/agents/, .claude/skills/, .claude/settings.json, il lock dei
// plugin, le due guardie PreToolUse e la matrice di .gitignore secondo il
// disegno approvato in VPM-LAB-001B (§3.5). Esce con 1 se trova errori.
//
// Nessuna rete, nessuna dipendenza, nessuna scrittura. L'unico processo
// esterno e' `git check-ignore --no-index` per la matrice di .gitignore.
//
// Uso: node .github/scripts/claude-setup-verify.mjs [radice-del-repository]

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

export const AGENTI_ATTESI = [
  "vinea-code-reviewer",
  "vinea-security-auditor",
  "vinea-ux-auditor",
  "vinea-architecture-mapper",
  "vinea-qa-runner",
  "vinea-release-verifier",
];
export const SKILL_ATTESE = [
  "vinea-task",
  "vinea-test",
  "vinea-review",
  "vinea-security",
  "vinea-design",
  "vinea-skill-evaluation",
];
// Skill che solo l'utente puo' avviare (VPM-LAB-001B §2.4).
const SKILL_MANUALI = new Set(["vinea-task", "vinea-skill-evaluation"]);
// Agenti con shell e profilo della guardia che devono usare.
const PROFILO_SHELL = { "vinea-qa-runner": "qa", "vinea-release-verifier": "release" };

const STRUMENTI_VIETATI = ["Agent", "PowerShell", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch"];
const MCP_LETTURA = new Set([
  "mcp__supabase-ro__list_migrations",
  "mcp__supabase-ro__list_tables",
  "mcp__supabase-ro__get_advisors",
  "mcp__supabase-ro__list_edge_functions",
  "mcp__supabase-ro__get_edge_function",
  "mcp__supabase-ro__execute_sql",
]);
const MODI_PERICOLOSI = new Set(["bypassPermissions", "auto", "acceptEdits"]);

// Contenuti che non devono mai finire nei file versionati di .claude/.
const CONTENUTI_VIETATI = [
  [/localhost:20128/i, "endpoint locale di OmniRoute"],
  [/[A-Za-z]:[\\/]+Users[\\/]/, "percorso personale Windows"],
  [/(^|[\s"'(])\/(Users|home)\/[A-Za-z0-9._-]+/, "percorso personale Unix"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "chiave privata"],
  [/\b(sk|rk)_(live|test)_[A-Za-z0-9]{8,}/, "chiave Stripe"],
  [/\bsk-(ant-)?[A-Za-z0-9_-]{20,}/, "chiave API"],
  [/\bgh[pousr]_[A-Za-z0-9]{20,}/, "token GitHub"],
  [/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/, "JWT"],
];

// Matrice di .gitignore (VPM-LAB-001B §3.1): true = deve essere ignorato.
export const MATRICE_GITIGNORE = [
  [".claude/agents/vinea-code-reviewer.md", false],
  [".claude/skills/vinea-task/SKILL.md", false],
  [".claude/skills/vinea-design/references/brand.md", false],
  [".claude/settings.json", false],
  ["CLAUDE.md", false],
  [".claude/settings.local.json", true],
  [".claude/launch.json", true],
  [".claude/worktrees/x/.claude/agents/a.md", true],
  [".claude/agent-memory/a.md", true],
  [".claude/agent-memory-local/a.md", true],
  [".claude/commands/a.md", true],
  [".claude/hooks/a.mjs", true],
  [".claude/plans/a.md", true],
  [".claude/todos/a.json", true],
  [".claude/.credentials.json", true],
  [".claude/skills/x/settings.local.json", true],
  [".claude/agents/x.local.md", true],
  [".claude/skills/x/.env", true],
  [".claude/skills/x/server.key", true],
  [".claude/skills/x/cert.pem", true],
  ["frontend-next/.claude/settings.json", true],
  ["backend/sub/.claude/agents/a.md", true],
];

/** Frontmatter YAML minimale: chiavi di primo livello e blocco grezzo. */
export function leggiFrontmatter(testo) {
  const m = testo.replace(/^﻿/, "").match(/^---\r?\n([\s\S]*?)\r?\n---(\r?\n|$)/);
  if (!m) return null;
  const blocco = m[1].replace(/\r/g, "");
  const chiavi = {};
  const duplicati = [];
  for (const riga of blocco.split("\n")) {
    const c = riga.match(/^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/);
    if (!c) continue;
    if (c[1] in chiavi) duplicati.push(c[1]);
    chiavi[c[1]] = c[2].trim().replace(/^["']|["']$/g, "");
  }
  return { blocco, chiavi, duplicati };
}

/** `Read, Grep` oppure `[Read, Grep]` -> ["Read", "Grep"]. */
export function elencoStrumenti(valore) {
  if (!valore) return [];
  return valore
    .replace(/^\[|\]$/g, "")
    .split(",")
    .map((s) => s.trim().replace(/^["']|["']$/g, ""))
    .filter(Boolean);
}

function fileRicorsivi(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const voce of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, voce.name);
    if (voce.isDirectory()) out.push(...fileRicorsivi(p));
    else if (voce.isFile()) out.push(p);
  }
  return out;
}

/**
 * Esegue tutti i controlli sulla radice indicata.
 * @param {string} root
 * @param {{ gitignore?: boolean }} [opzioni]
 * @returns {{ errori: string[], avvisi: string[] }}
 */
export function verifica(root, opzioni = {}) {
  const errori = [];
  const avvisi = [];
  const err = (m) => errori.push(m);
  const leggi = (rel) => readFileSync(join(root, rel), "utf8");
  const esiste = (rel) => existsSync(join(root, rel));
  const json = (rel) => {
    try {
      return JSON.parse(leggi(rel));
    } catch (e) {
      err(`${rel}: JSON non valido (${e.message})`);
      return null;
    }
  };

  // --- Lock dei plugin -----------------------------------------------------
  const LOCK = ".github/scripts/claude-plugins.lock.json";
  let lock = null;
  if (!esiste(LOCK)) err(`${LOCK}: mancante`);
  else lock = json(LOCK);
  const fd = lock?.plugins?.["frontend-design"];
  if (lock && !fd) err(`${LOCK}: frontend-design assente`);
  if (fd) {
    for (const k of ["marketplace", "repo", "path", "commit", "version", "sha256", "reviewedAt"]) {
      if (!(k in fd)) err(`${LOCK}: frontend-design senza chiave ${k}`);
    }
    if (fd.commit && !/^[0-9a-f]{40}$/.test(fd.commit)) err(`${LOCK}: commit non e' uno SHA completo`);
    for (const f of ["SKILL.md", "LICENSE.txt"]) {
      if (!/^[0-9a-f]{64}$/.test(fd.sha256?.[f] ?? "")) err(`${LOCK}: sha256 di ${f} mancante o non valido`);
    }
  }

  // --- Agenti --------------------------------------------------------------
  const DIR_AGENTI = ".claude/agents";
  const agenti = esiste(DIR_AGENTI)
    ? readdirSync(join(root, DIR_AGENTI)).filter((f) => f.endsWith(".md")).map((f) => f.slice(0, -3))
    : [];
  for (const a of AGENTI_ATTESI) if (!agenti.includes(a)) err(`agente mancante: ${a}`);
  for (const a of agenti) if (!AGENTI_ATTESI.includes(a)) err(`agente non previsto: ${a}`);
  for (const nome of agenti) {
    const rel = `${DIR_AGENTI}/${nome}.md`;
    const fm = leggiFrontmatter(leggi(rel));
    if (!fm) {
      err(`${rel}: frontmatter mancante`);
      continue;
    }
    const { chiavi, blocco } = fm;
    // Una chiave ripetuta nasconderebbe il primo valore a chi rilegge il file.
    for (const k of fm.duplicati) err(`${rel}: chiave ${k} ripetuta`);
    if (chiavi.name !== nome) err(`${rel}: name deve essere "${nome}"`);
    if (!chiavi.description) err(`${rel}: description mancante`);
    if (chiavi.model !== "inherit") err(`${rel}: model deve essere inherit`);
    if (!/^\d+$/.test(chiavi.maxTurns ?? "")) err(`${rel}: maxTurns mancante`);
    if (MODI_PERICOLOSI.has(chiavi.permissionMode)) err(`${rel}: permissionMode ${chiavi.permissionMode} vietato`);
    if (!("tools" in chiavi)) err(`${rel}: tools esplicito obbligatorio (senza, l'agente eredita tutto)`);
    const tools = elencoStrumenti(chiavi.tools);
    for (const t of tools) {
      if (STRUMENTI_VIETATI.includes(t)) err(`${rel}: strumento vietato in tools: ${t}`);
      if (t.startsWith("mcp__") && !MCP_LETTURA.has(t)) err(`${rel}: MCP non ammesso: ${t}`);
    }
    const urlMcp = blocco.match(/https?:\/\/\S+/g) ?? [];
    for (const u of urlMcp) {
      if (/mcp/i.test(u) && !/read_only=true/.test(u)) err(`${rel}: URL MCP senza read_only=true`);
    }
    const profilo = PROFILO_SHELL[nome];
    const haShell = tools.includes("Bash");
    if (haShell && !profilo) err(`${rel}: Bash ammesso solo per qa-runner e release-verifier`);
    if (profilo) {
      if (!haShell) err(`${rel}: deve elencare Bash in tools`);
      if (chiavi.isolation !== "worktree") err(`${rel}: isolation: worktree obbligatorio`);
      const guardia = new RegExp(
        `^hooks:[\\s\\S]*PreToolUse:[\\s\\S]*matcher:\\s*["']?[^\\n]*\\bBash\\b[\\s\\S]*claude-agent-guard\\.mjs" --profile ${profilo} \\|\\| exit 2`,
        "m",
      );
      if (!guardia.test(blocco)) err(`${rel}: hook PreToolUse della guardia (profilo ${profilo}) mancante`);
      const corpo = leggi(rel).slice(blocco.length);
      if (!corpo.includes("git push --dry-run vinea-guard-canary")) err(`${rel}: canarino mancante`);
    }
    if (!/claude-secret-guard\.mjs" \|\| exit 2/.test(blocco)) err(`${rel}: hook della guardia dei segreti mancante`);
  }

  // --- Skill ---------------------------------------------------------------
  const DIR_SKILL = ".claude/skills";
  const skill = esiste(DIR_SKILL)
    ? readdirSync(join(root, DIR_SKILL), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
    : [];
  for (const s of SKILL_ATTESE) if (!skill.includes(s)) err(`skill mancante: ${s}`);
  for (const s of skill) if (!SKILL_ATTESE.includes(s)) err(`skill non prevista: ${s}`);
  for (const s of skill) {
    const rel = `${DIR_SKILL}/${s}/SKILL.md`;
    if (!esiste(rel)) {
      err(`${rel}: mancante`);
      continue;
    }
    const testo = leggi(rel);
    const fm = leggiFrontmatter(testo);
    if (!fm) {
      err(`${rel}: frontmatter mancante`);
      continue;
    }
    const { chiavi } = fm;
    for (const k of fm.duplicati) err(`${rel}: chiave ${k} ripetuta`);
    if (chiavi.name !== s) err(`${rel}: name deve essere "${s}"`);
    if (!chiavi.description) err(`${rel}: description mancante`);
    if ("allowed-tools" in chiavi) err(`${rel}: allowed-tools vietato (il trust non lo protegge)`);
    if ("hooks" in chiavi) err(`${rel}: hooks vietati nelle skill`);
    for (const k of Object.keys(chiavi)) {
      if (/[A-Z]/.test(k)) err(`${rel}: chiave ${k} non riconosciuta (usare la forma kebab-case)`);
    }
    const manuale = chiavi["disable-model-invocation"] === "true";
    if (SKILL_MANUALI.has(s) && !manuale) err(`${rel}: disable-model-invocation: true obbligatorio`);
    if (!SKILL_MANUALI.has(s) && manuale) avvisi.push(`${rel}: skill contestuale resa manuale`);
    // Iniezione dinamica: "!" seguito da un comando tra backtick.
    if (/!`[^`]+`/.test(testo)) err(`${rel}: iniezione dinamica di shell vietata`);
    if (testo.split("\n").length > 300) err(`${rel}: oltre 300 righe, spostare in references/`);
  }

  // --- settings.json di progetto -------------------------------------------
  const SETTINGS = ".claude/settings.json";
  const cfg = esiste(SETTINGS) ? json(SETTINGS) : (err(`${SETTINGS}: mancante`), null);
  if (cfg) {
    for (const k of ["hooks", "env", "allow", "defaultMode", "apiKeyHelper", "mcpServers"]) {
      if (k in cfg) err(`${SETTINGS}: chiave ${k} vietata`);
    }
    if (cfg.permissions?.allow !== undefined) err(`${SETTINGS}: permissions.allow vietato`);
    if (cfg.permissions?.defaultMode !== undefined) err(`${SETTINGS}: permissions.defaultMode vietato`);
    for (const id of Object.keys(cfg.enabledPlugins ?? {})) {
      const [plugin, mkt] = id.split("@");
      if (!lock?.plugins?.[plugin] || lock.plugins[plugin].marketplace !== mkt) {
        err(`${SETTINGS}: plugin ${id} abilitato ma assente dal lock`);
      }
    }
    if (cfg.enabledPlugins?.["frontend-design@claude-plugins-official"] !== true) {
      err(`${SETTINGS}: frontend-design@claude-plugins-official non abilitato`);
    }
    for (const [nome, m] of Object.entries(cfg.extraKnownMarketplaces ?? {})) {
      if (m.autoUpdate !== false) err(`${SETTINGS}: marketplace ${nome} senza autoUpdate: false`);
      if (nome === "claude-plugins-official" && m.source?.repo !== fd?.repo) {
        err(`${SETTINGS}: repository del marketplace diverso dal lock`);
      }
    }
    const deny = cfg.permissions?.deny ?? [];
    for (const r of ["Read(.env)", "Read(.env.*)", "Read(*.pem)", "Read(*.key)"]) {
      if (!deny.includes(r)) err(`${SETTINGS}: permissions.deny senza ${r}`);
    }
    const ask = cfg.permissions?.ask ?? [];
    for (const r of ["Bash(claude plugin *)", "PowerShell(claude plugin *)", "Bash(claude mcp *)", "PowerShell(claude mcp *)"]) {
      if (!ask.includes(r)) err(`${SETTINGS}: permissions.ask senza ${r}`);
    }
  }

  // --- Guardie -------------------------------------------------------------
  for (const [rel, prefisso] of [
    [".github/scripts/claude-agent-guard.mjs", "VINEA-GUARD"],
    [".github/scripts/claude-secret-guard.mjs", "VINEA-SECRET-GUARD"],
  ]) {
    if (!esiste(rel)) err(`${rel}: mancante`);
    else if (!leggi(rel).includes(`"${prefisso}"`)) err(`${rel}: prefisso ${prefisso} assente`);
    const test = rel.replace(/\.mjs$/, ".test.mjs");
    if (!esiste(test)) err(`${test}: mancante`);
  }

  // --- Contenuti versionati di .claude/ ------------------------------------
  const daScansionare = [...fileRicorsivi(join(root, ".claude/agents")), ...fileRicorsivi(join(root, ".claude/skills"))];
  if (esiste(SETTINGS)) daScansionare.push(join(root, SETTINGS));
  for (const p of daScansionare) {
    const rel = relative(root, p).replace(/\\/g, "/");
    if (statSync(p).size > 256 * 1024) {
      err(`${rel}: file troppo grande per un asset di configurazione`);
      continue;
    }
    const testo = readFileSync(p, "utf8");
    for (const [re, cosa] of CONTENUTI_VIETATI) if (re.test(testo)) err(`${rel}: contiene ${cosa}`);
  }

  // --- .gitignore ----------------------------------------------------------
  if (opzioni.gitignore !== false) {
    for (const [percorso, ignorato] of MATRICE_GITIGNORE) {
      const r = spawnSync("git", ["check-ignore", "--no-index", "-q", percorso], { cwd: root });
      if (r.status !== 0 && r.status !== 1) {
        err(`.gitignore: git check-ignore non eseguibile (${r.error?.message ?? r.status})`);
        break;
      }
      if ((r.status === 0) !== ignorato) {
        err(`.gitignore: ${percorso} dovrebbe essere ${ignorato ? "ignorato" : "versionabile"}`);
      }
    }
  }

  return { errori, avvisi };
}

function main() {
  const root = process.argv[2] ?? process.cwd();
  const { errori, avvisi } = verifica(root);
  for (const a of avvisi) console.warn(`AVVISO: ${a}`);
  for (const e of errori) console.error(`ERRORE: ${e}`);
  if (errori.length > 0) {
    console.error(`claude-setup-verify: ${errori.length} errori`);
    process.exit(1);
  }
  console.log(
    `claude-setup-verify: OK (${AGENTI_ATTESI.length} agenti, ${SKILL_ATTESE.length} skill, ` +
      `${MATRICE_GITIGNORE.length} casi .gitignore, ${avvisi.length} avvisi)`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
