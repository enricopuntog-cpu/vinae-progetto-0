#!/usr/bin/env node
// Prova runtime MANUALE delle skill di progetto (RECOVERY-001). Mai in CI.
//
// Avvia sessioni headless di Claude Code nella radice del repository, in sola
// lettura, e controlla nel flusso stream-json (1) che la skill sia elencata
// nell'evento init e (2) che sia stata richiamata con lo strumento Skill (o
// con il comando manuale). Le chiamate al modello usano l'autenticazione del
// profilo scelto: se e' scaduta le prove falliscono e il risultato e'
// NON VERIFICATO, mai OK.
//
// Uso: CLAUDE_CONFIG_DIR=<profilo> node .github/scripts/claude-skill-runtime-check.mjs [--solo nome,nome]
// Esce con 0 solo se ogni prova selezionata e' OK.

import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const LETTURA = ["Skill", "Read", "Grep", "Glob"];
const VIETATI = ["Bash", "PowerShell", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch", "Agent"];

// manuale: la skill ha disable-model-invocation e si prova con il comando /nome.
export const PROVE = [
  { skill: "copywriting", prompt: "Usa la skill copywriting per proporre UNA sola alternativa all'headline della Home in frontend-next/src/app/page-client.tsx. Solo lettura, massimo 120 parole, segnala ogni claim non supportato dal codice." },
  { skill: "seo-audit", prompt: "Usa la skill seo-audit per un audit statico minimo di frontend-next/src/app/robots.ts e frontend-next/src/lib/brand/metadata.ts. Solo lettura, massimo 150 parole, distingui osservazioni statiche da verifiche runtime non eseguite." },
  { skill: "cro", prompt: "Usa la skill cro: formula UNA ipotesi CRO per la Home (frontend-next/src/app/page-client.tsx) con metrica e prerequisiti, senza inventare risultati. Solo lettura, massimo 120 parole." },
  { skill: "product-marketing", prompt: "Usa la skill product-marketing per elencare, solo in chat e senza scrivere file, quali sezioni del contesto di prodotto si potrebbero compilare dai soli file README.md e docs/ROADMAP_V1.md. Massimo 120 parole." },
  { skill: "animation-performance", prompt: "Usa la skill animation-performance per valutare le animazioni in frontend-next/src/components/ui/dialog.tsx. Solo lettura, massimo 150 parole, con riferimenti file:riga." },
  { skill: "review-animations", manuale: true, prompt: "/review-animations frontend-next/src/components/ui/dialog.tsx" },
  { skill: "supabase-postgres-best-practices", prompt: "Rivedi dal punto di vista delle prestazioni Postgres (indici sulle chiavi esterne, policy RLS) la migrazione supabase/migrations/20261021090000_vpm_015b1_cantina_accessori.sql. Carica la skill pertinente. Solo lettura, massimo 200 parole, con file:riga." },
  { skill: "vinea-marketing", manuale: true, prompt: "/vinea-marketing seo frontend-next/src/app/robots.ts" },
];

function esegui(radice, prova) {
  return new Promise((risolvi) => {
    const args = ["-p", "--output-format", "stream-json", "--verbose", "--max-turns", "25", "--allowedTools", ...LETTURA, "--disallowedTools", ...VIETATI];
    const p = spawn(process.platform === "win32" ? "claude.cmd" : "claude", args, { cwd: radice, shell: process.platform === "win32" });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", () => {});
    p.stdin.end(prova.prompt);
    p.on("close", () => {
      const ev = out.split("\n").filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
      const init = ev.find((e) => e.type === "system" && e.subtype === "init");
      const usi = ev.filter((e) => e.type === "assistant").flatMap((e) => e.message.content.filter((b) => b.type === "tool_use"));
      const invocate = usi.filter((u) => u.name === "Skill").map((u) => u.input.skill ?? u.input.command);
      const r = ev.find((e) => e.type === "result");
      const testo = String(r?.result ?? "");
      const autenticazione = /authenticate|OAuth|login/i.test(testo) && (r?.total_cost_usd ?? 0) === 0;
      const elencata = (init?.skills ?? []).includes(prova.skill);
      // Una skill manuale puo' comparire nel flusso come comando espanso, non come tool_use.
      const invocata = invocate.some((s) => String(s).includes(prova.skill)) || (prova.manuale && ev.some((e) => JSON.stringify(e).includes(`<command-name>/${prova.skill}`) || JSON.stringify(e).includes(`"${prova.skill}"`) && e.type === "user"));
      const esito = autenticazione ? "NON VERIFICATO (autenticazione)" : !elencata ? "KO (non elencata)" : !invocata ? "KO (non richiamata)" : "OK";
      risolvi({ skill: prova.skill, esito, turni: r?.num_turns, costoStimatoUsd: r?.total_cost_usd, skillRichiamate: invocate });
    });
  });
}

const radice = process.cwd();
const solo = process.argv.includes("--solo") ? process.argv[process.argv.indexOf("--solo") + 1].split(",") : null;
const scelte = PROVE.filter((p) => !solo || solo.includes(p.skill));
const risultati = [];
for (const p of scelte) risultati.push(await esegui(radice, p));
const file = join(mkdtempSync(join(tmpdir(), "vinea-skill-runtime-")), "esito.json");
writeFileSync(file, JSON.stringify(risultati, null, 2));
for (const r of risultati) console.log(`${r.esito.padEnd(34)} ${r.skill} (turni ${r.turni ?? "-"}, richiamate: ${r.skillRichiamate.join(",") || "-"})`);
console.log(`Dettaglio: ${file}`);
process.exit(risultati.every((r) => r.esito === "OK") ? 0 : 1);
