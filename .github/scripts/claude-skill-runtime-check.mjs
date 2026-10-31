#!/usr/bin/env node
// Prova runtime MANUALE delle skill di progetto (RECOVERY-001). Mai in CI.
//
// Avvia sessioni headless di Claude Code nella radice del repository, in sola
// lettura, e classifica ogni prova in uno di questi esiti:
//   OK                               la skill e' elencata nell'evento init ED e' stata richiamata
//   KO (non elencata)                la skill non e' nell'evento init
//   KO (non richiamata)              elencata, ma il modello non l'ha usata
//   KO (errore API)                  la chiamata e' fallita per un motivo diverso dall'autenticazione
//   KO (interferenza)                prova negativa: una skill di marketing e' partita su un task di codice
//   KO (timeout)                     la sessione ha superato il tempo massimo
//   NON VERIFICATO (autenticazione)  il login del profilo e' scaduto o assente: nessun task e' partito
//
// Una skill e' "richiamata" solo con prova strutturale nel flusso stream-json:
// uno strumento Skill con nome ESATTO, oppure (per le skill manuali) l'espansione
// del comando con la cartella base della skill. Il solo nome nel testo non basta.
//
// Strumenti: solo Skill, Read, Grep, Glob (--tools). Niente Bash, scrittura, rete
// o sub-agenti. Ogni sessione ha un tempo massimo e un tetto di spesa. L'esito
// salvato contiene solo nome del profilo, versione della CLI, modello, esito e
// costo: niente prompt completi, percorsi personali o credenziali.
//
// Uso: CLAUDE_CONFIG_DIR=<profilo> node .github/scripts/claude-skill-runtime-check.mjs
//        [--solo nome,nome] [--out file.json] [--timeout-s 240] [--budget-usd 1]
// Esce con 0 solo se ogni prova selezionata e' OK.

import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

export const STRUMENTI = ["Skill", "Read", "Grep", "Glob"];
export const MAX_BYTE_USCITA = 4 * 1024 * 1024;
export const SKILL_MARKETING = ["copywriting", "seo-audit", "cro", "product-marketing", "vinea-marketing"];

// manuale: la skill ha disable-model-invocation e si prova con il comando /nome.
// negativa: nessuna delle skill elencate deve essere richiamata.
export const PROVE = [
  { skill: "copywriting", prompt: "Usa la skill copywriting per proporre UNA sola alternativa all'headline della Home in frontend-next/src/app/page-client.tsx. Solo lettura, massimo 120 parole, segnala ogni claim non supportato dal codice." },
  { skill: "seo-audit", prompt: "Usa la skill seo-audit per un audit statico minimo di frontend-next/src/app/robots.ts e frontend-next/src/lib/brand/metadata.ts. Solo lettura, massimo 150 parole, distingui osservazioni statiche da verifiche runtime non eseguite." },
  { skill: "cro", prompt: "Usa la skill cro: formula UNA ipotesi CRO per la Home (frontend-next/src/app/page-client.tsx) con metrica e prerequisiti, senza inventare risultati. Solo lettura, massimo 120 parole." },
  { skill: "product-marketing", prompt: "Usa la skill product-marketing per elencare, solo in chat e senza scrivere file, quali sezioni del contesto di prodotto si potrebbero compilare dai soli file README.md e docs/ROADMAP_V1.md. Massimo 120 parole." },
  { skill: "animation-performance", prompt: "Usa la skill animation-performance per valutare le animazioni in frontend-next/src/components/ui/dialog.tsx. Solo lettura, massimo 150 parole, con riferimenti file:riga." },
  { skill: "review-animations", manuale: true, prompt: "/review-animations frontend-next/src/components/ui/dialog.tsx" },
  { skill: "supabase-postgres-best-practices", prompt: "Rivedi dal punto di vista delle prestazioni Postgres (indici sulle chiavi esterne, policy RLS) la migrazione supabase/migrations/20261021090000_vpm_015b1_cantina_accessori.sql. Carica la skill pertinente. Solo lettura, massimo 200 parole, con file:riga." },
  { skill: "vinea-marketing", manuale: true, prompt: "/vinea-marketing seo frontend-next/src/app/robots.ts" },
  { skill: "negativo", negativa: true, vietate: SKILL_MARKETING, prompt: "Spiega in massimo 80 parole cosa fa la funzione che calcola l'eta' in frontend-next/src/lib/age.ts e se il file ha un test. Solo lettura." },
];

// Estrae gli eventi JSON da una stringa stream-json, ignorando le righe non JSON.
export function eventi(testo) {
  return String(testo).split("\n").filter(Boolean).flatMap((l) => {
    try { return [JSON.parse(l)]; } catch { return []; }
  });
}

function blocchi(e) {
  const c = e?.message?.content;
  return Array.isArray(c) ? c : typeof c === "string" ? [{ type: "text", text: c }] : [];
}

// Nomi delle skill richiamate con lo strumento Skill (nome esatto, con o senza prefisso plugin).
export function skillRichiamate(ev) {
  return ev
    .filter((e) => e.type === "assistant")
    .flatMap((e) => blocchi(e).filter((b) => b.type === "tool_use" && b.name === "Skill"))
    .map((u) => String(u.input?.skill ?? u.input?.command ?? ""))
    .filter(Boolean);
}

export function stessoNome(richiamata, nome) {
  return richiamata === nome || richiamata.endsWith(`:${nome}`) || richiamata === `/${nome}`;
}

// Per una skill manuale il comando slash viene espanso in un messaggio utente che
// riporta la cartella base della skill o il nome del comando.
export function espansioneComando(ev, nome) {
  const marcatori = [`<command-name>/${nome}</command-name>`, `skills/${nome}`, `skills\\${nome}`];
  return ev
    .filter((e) => e.type === "user")
    .flatMap((e) => blocchi(e))
    .some((b) => {
      const t = typeof b.text === "string" ? b.text : typeof b.content === "string" ? b.content : "";
      return marcatori.some((m) => t.includes(m));
    });
}

export function classifica(prova, ev, uscitaForzata = null) {
  const init = ev.find((e) => e.type === "system" && e.subtype === "init");
  const r = ev.find((e) => e.type === "result");
  const richiamate = skillRichiamate(ev);
  const base = {
    skill: prova.skill,
    turni: r?.num_turns ?? null,
    costoStimatoUsd: r?.total_cost_usd ?? null,
    skillRichiamate: richiamate,
    elencata: (init?.skills ?? []).some((s) => stessoNome(String(s), prova.skill)),
  };
  if (uscitaForzata === "timeout") return { ...base, esito: "KO (timeout)" };
  const testo = String(r?.result ?? "");
  const nessunaChiamata = !r || ((r.total_cost_usd ?? 0) === 0 && (r.usage?.output_tokens ?? 0) === 0);
  const autenticazione = nessunaChiamata && (
    /authenticat|OAuth|not logged in|log ?in|unauthori[sz]ed|\b401\b/i.test(testo) ||
    r?.terminal_reason === "api_error" || r?.is_error === true || !init
  );
  if (autenticazione) return { ...base, esito: "NON VERIFICATO (autenticazione)" };
  if (r?.is_error) return { ...base, esito: "KO (errore API)" };
  if (prova.negativa) {
    const partite = richiamate.filter((s) => prova.vietate.some((v) => stessoNome(s, v)));
    return { ...base, esito: partite.length ? "KO (interferenza)" : "OK", skillVietateRichiamate: partite };
  }
  if (!base.elencata) return { ...base, esito: "KO (non elencata)" };
  const invocata = richiamate.some((s) => stessoNome(s, prova.skill)) || (prova.manuale === true && espansioneComando(ev, prova.skill));
  return { ...base, esito: invocata ? "OK" : "KO (non richiamata)" };
}

// Su Windows claude e' uno shim .cmd che richiede la shell; gli argomenti sono costanti
// del file (il prompt passa da stdin), quindi la riga di comando e' composta qui.
function lancia(args, cwd) {
  if (process.platform !== "win32") return spawn("claude", args, { cwd });
  return spawn(["claude.cmd", ...args].join(" "), { cwd, shell: true, windowsHide: true });
}

function esegui(radice, prova, { timeoutS, budgetUsd }) {
  return new Promise((risolvi) => {
    const args = [
      "-p", "--output-format", "stream-json", "--verbose",
      "--max-turns", "25", "--max-budget-usd", String(budgetUsd),
      "--tools", STRUMENTI.join(","), "--strict-mcp-config", "--no-session-persistence",
    ];
    const p = lancia(args, radice);
    let out = "";
    let troncata = false;
    let forzata = null;
    p.stdout.on("data", (d) => {
      if (out.length < MAX_BYTE_USCITA) out += d;
      else troncata = true;
    });
    p.stderr.on("data", () => {});
    p.stdin.end(prova.prompt);
    const t = setTimeout(() => {
      forzata = "timeout";
      if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(p.pid), "/T", "/F"]);
      else p.kill("SIGKILL");
    }, timeoutS * 1000);
    p.on("close", () => {
      clearTimeout(t);
      risolvi({ ...classifica(prova, eventi(out), forzata), uscitaTroncata: troncata });
    });
  });
}

function versioneCli() {
  const r = process.platform === "win32"
    ? spawnSync("claude.cmd --version", { shell: true, encoding: "utf8" })
    : spawnSync("claude", ["--version"], { encoding: "utf8" });
  return String(r.stdout ?? "").trim() || "sconosciuta";
}

function opzione(nome, predefinito) {
  const i = process.argv.indexOf(nome);
  return i >= 0 ? process.argv[i + 1] : predefinito;
}

async function main() {
  const radice = process.cwd();
  const solo = opzione("--solo") ? opzione("--solo").split(",") : null;
  const scelte = PROVE.filter((p) => !solo || solo.includes(p.skill));
  const timeoutS = Number(opzione("--timeout-s", 240));
  const budgetUsd = Number(opzione("--budget-usd", 1));
  const risultati = [];
  for (const p of scelte) risultati.push(await esegui(radice, p, { timeoutS, budgetUsd }));
  const profilo = process.env.CLAUDE_CONFIG_DIR ? basename(process.env.CLAUDE_CONFIG_DIR.replace(/[\\/]+$/, "")) : "predefinito (Anthropic Direct)";
  const rapporto = {
    data: new Date().toISOString(),
    profilo,
    cli: versioneCli(),
    strumenti: STRUMENTI,
    risultati,
  };
  const file = opzione("--out") ?? join(mkdtempSync(join(tmpdir(), "vinea-skill-runtime-")), "esito.json");
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(rapporto, null, 2));
  for (const r of risultati) {
    console.log(`${r.esito.padEnd(34)} ${r.skill} (turni ${r.turni ?? "-"}, costo ${r.costoStimatoUsd ?? "-"}, richiamate: ${r.skillRichiamate.join(",") || "-"})`);
  }
  console.log(`Profilo: ${profilo} | CLI ${rapporto.cli}\nDettaglio: ${file}`);
  process.exit(risultati.every((r) => r.esito === "OK") ? 0 : 1);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) await main();
