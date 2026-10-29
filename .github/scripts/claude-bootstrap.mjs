#!/usr/bin/env node
// Bootstrap locale di Claude Code per il repository Vinea (VPM-LAB-002).
//
// Solo locale, mai in CI. Per ogni directory di configurazione indicata
// controlla la versione di Claude Code, il marketplace ufficiale e il plugin
// frontend-design rispetto a .github/scripts/claude-plugins.lock.json.
//
//   --check (default)  legge soltanto: nessuna scrittura, nessuna installazione.
//   --install          solo se manca qualcosa: aggiunge il marketplace ufficiale
//                      e installa frontend-design@claude-plugins-official con
//                      --scope project. Mai altri marketplace, mai --yes.
//
// Se il contenuto installato non coincide con il lock esce con 1 e non
// installa nulla: la deriva si risolve con una PR che aggiorna il lock.
//
// Uso:
//   node .github/scripts/claude-bootstrap.mjs [--check|--install] [--config-dir <dir>]...
// Default della directory: CLAUDE_CONFIG_DIR oppure ~/.claude.
// Per il profilo OmniRoute: --config-dir ~/.claude/profiles/vinea-coding

import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

export const VERSIONE_MINIMA = "2.1.277";
export const MESSAGGIO_DERIVA =
  "contenuto upstream cambiato: rivedere il diff e aggiornare il lock con una PR";
const PLUGIN = "frontend-design";
const FILE_CONTROLLATI = ["SKILL.md", "LICENSE.txt"];

const QUI = dirname(fileURLToPath(import.meta.url));
export const RADICE = resolve(QUI, "..", "..");
export const PERCORSO_LOCK = join(QUI, "claude-plugins.lock.json");

/** Argomenti della riga di comando. Lancia un Error su input non valido. */
export function leggiArgomenti(argv, env = process.env) {
  let modo = "check";
  const dirs = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--check") modo = "check";
    else if (a === "--install") modo = "install";
    else if (a === "--config-dir") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) throw new Error("--config-dir richiede una directory");
      dirs.push(v);
    } else throw new Error(`opzione sconosciuta: ${a}`);
  }
  if (dirs.length === 0) dirs.push(env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"));
  return { modo, dirs: dirs.map(espandiHome) };
}

function espandiHome(p) {
  return p === "~" || p.startsWith("~/") || p.startsWith("~\\") ? join(homedir(), p.slice(1)) : resolve(p);
}

/** "2.1.312 (Claude Code)" -> [2, 1, 312]; null se illeggibile. */
export function leggiVersione(testo) {
  const m = String(testo ?? "").match(/(\d+)\.(\d+)\.(\d+)/);
  return m ? m.slice(1).map(Number) : null;
}

export function versioneAlmeno(v, minima) {
  const m = leggiVersione(minima);
  for (let i = 0; i < 3; i++) if (v[i] !== m[i]) return v[i] > m[i];
  return true;
}

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

/** Esecutore reale della CLI `claude`, con la directory di configurazione nell'ambiente. */
export function eseguiClaude(args, configDir) {
  const opzioni = {
    cwd: RADICE,
    env: { ...process.env, CLAUDE_CONFIG_DIR: configDir },
    encoding: "utf8",
    timeout: 120_000,
  };
  // Su Windows la CLI e' uno shim .cmd/.ps1: serve la shell. Gli argomenti
  // sono costanti di questo script, mai input esterni; la directory di
  // configurazione passa dall'ambiente, non dalla riga di comando.
  const r =
    process.platform === "win32"
      ? spawnSync(["claude", ...args].join(" "), { ...opzioni, shell: true })
      : spawnSync("claude", args, opzioni);
  return { status: r.status ?? 1, stdout: r.stdout ?? "", stderr: r.stderr ?? (r.error?.message || "") };
}

function jsonDa(r, comando) {
  if (r.status !== 0) throw new Error(`${comando} fallito: ${r.stderr.trim() || `codice ${r.status}`}`);
  try {
    return JSON.parse(r.stdout);
  } catch {
    throw new Error(`${comando}: output JSON non valido`);
  }
}

/**
 * Copie del plugin da confrontare con il lock: quella del marketplace e quelle
 * eventualmente gia' in cache (che sono quelle caricate dalle sessioni).
 */
export function copieDelPlugin(configDir, installLocation, voce) {
  const copie = [];
  if (installLocation) copie.push(join(installLocation, ...voce.path.split("/")));
  const cache = join(configDir, "plugins", "cache", voce.marketplace, PLUGIN);
  if (existsSync(cache)) {
    for (const v of readdirSync(cache, { withFileTypes: true })) {
      if (v.isDirectory()) copie.push(join(cache, v.name));
    }
  }
  return copie;
}

/** Confronta una copia del plugin con il lock; restituisce le differenze. */
export function confrontaCopia(dir, voce) {
  const diff = [];
  const manifesto = join(dir, ".claude-plugin", "plugin.json");
  let versione = null;
  try {
    versione = JSON.parse(readFileSync(manifesto, "utf8")).version ?? null;
  } catch {
    diff.push("plugin.json mancante o illeggibile");
  }
  if (versione !== null && versione !== voce.version) diff.push(`versione ${versione}, lock ${voce.version}`);
  for (const f of FILE_CONTROLLATI) {
    const p = join(dir, "skills", PLUGIN, f);
    if (!existsSync(p)) diff.push(`${f} mancante`);
    else if (sha256(p) !== voce.sha256[f]) diff.push(`sha256 di ${f} diverso dal lock`);
  }
  return diff;
}

/**
 * Controlla una directory di configurazione. Nessuna scrittura.
 * @returns {{ stato: "ok" | "mancante" | "deriva" | "errore", messaggi: string[] }}
 */
export function controlla(configDir, lock, esegui = eseguiClaude) {
  const voce = lock.plugins[PLUGIN];
  const messaggi = [];
  const esito = (stato) => ({ stato, messaggi });
  try {
    const v = leggiVersione(esegui(["--version"], configDir).stdout);
    if (!v) return (messaggi.push("versione di Claude Code illeggibile"), esito("errore"));
    if (!versioneAlmeno(v, VERSIONE_MINIMA)) {
      messaggi.push(`Claude Code ${v.join(".")} < ${VERSIONE_MINIMA}: aggiornarlo prima di continuare`);
      return esito("errore");
    }
    messaggi.push(`Claude Code ${v.join(".")}`);

    const mercati = jsonDa(esegui(["plugin", "marketplace", "list", "--json"], configDir), "plugin marketplace list");
    const m = Array.isArray(mercati) ? mercati.find((x) => x?.name === voce.marketplace) : undefined;
    if (!m) return (messaggi.push(`marketplace ${voce.marketplace} assente`), esito("mancante"));
    if (m.repo !== voce.repo) {
      messaggi.push(`marketplace ${voce.marketplace} punta a ${m.repo ?? m.url ?? "?"}, lock ${voce.repo}`);
      return esito("errore");
    }

    const installati = jsonDa(esegui(["plugin", "list", "--json"], configDir), "plugin list");
    const id = `${PLUGIN}@${voce.marketplace}`;
    const inElenco = Array.isArray(installati) && installati.some((x) => x?.id === id);
    messaggi.push(inElenco ? `${id} installato` : `${id} non installato: si carica da enabledPlugins di progetto`);

    const copie = copieDelPlugin(configDir, m.installLocation, voce);
    const presenti = copie.filter((c) => existsSync(c));
    if (presenti.length === 0) return (messaggi.push(`${PLUGIN} assente dal marketplace`), esito("mancante"));
    let deriva = false;
    for (const c of presenti) {
      const diff = confrontaCopia(c, voce);
      if (diff.length > 0) {
        deriva = true;
        messaggi.push(`${c}: ${diff.join("; ")}`);
      }
    }
    if (deriva) return (messaggi.push(MESSAGGIO_DERIVA), esito("deriva"));
    messaggi.push(`${PLUGIN} ${voce.version} conforme al lock (${presenti.length} copie)`);
    return esito("ok");
  } catch (e) {
    messaggi.push(e.message);
    return esito("errore");
  }
}

/** Installa solo cio' che manca, poi ricontrolla. Mai in presenza di deriva. */
export function installa(configDir, lock, esegui = eseguiClaude) {
  const prima = controlla(configDir, lock, esegui);
  if (prima.stato !== "mancante") return prima;
  const voce = lock.plugins[PLUGIN];
  if (prima.messaggi.some((x) => x.startsWith(`marketplace ${voce.marketplace} assente`))) {
    const r = esegui(["plugin", "marketplace", "add", voce.repo], configDir);
    if (r.status !== 0) return { stato: "errore", messaggi: [...prima.messaggi, `marketplace add fallito: ${r.stderr.trim()}`] };
  }
  const intermedio = controlla(configDir, lock, esegui);
  if (intermedio.stato !== "mancante") return intermedio;
  const r = esegui(["plugin", "install", `${PLUGIN}@${voce.marketplace}`, "--scope", "project"], configDir);
  if (r.status !== 0) return { stato: "errore", messaggi: [...intermedio.messaggi, `plugin install fallito: ${r.stderr.trim()}`] };
  return controlla(configDir, lock, esegui);
}

export function main(argv = process.argv.slice(2), esegui = eseguiClaude, log = console) {
  let argomenti;
  try {
    argomenti = leggiArgomenti(argv);
  } catch (e) {
    log.error(`claude-bootstrap: ${e.message}`);
    return 2;
  }
  const lock = JSON.parse(readFileSync(PERCORSO_LOCK, "utf8"));
  let codice = 0;
  for (const dir of argomenti.dirs) {
    const r = argomenti.modo === "install" ? installa(dir, lock, esegui) : controlla(dir, lock, esegui);
    log.log(`== ${dir}: ${r.stato.toUpperCase()}`);
    for (const m of r.messaggi) log.log(`   ${m}`);
    if (r.stato === "mancante" && argomenti.modo === "check") log.log("   rieseguire con --install");
    if (r.stato !== "ok") codice = 1;
  }
  return codice;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exit(main());
}
