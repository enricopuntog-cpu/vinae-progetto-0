#!/usr/bin/env node
// Guardia PreToolUse di progetto contro la lettura dei file di segreti
// (VPM-LAB-002, decisione D6).
//
// Il primo livello sono le regole `deny` di `.claude/settings.json`, che il
// runtime applica agli strumenti di file. Non coprono la shell: `cat .env.local`
// o `Get-Content .env` le aggirano. Questa guardia e' il secondo livello:
// rifiuta (codice 2) Read/Grep/Glob su file di segreti e i comandi Bash o
// PowerShell che nominano un file di segreti.
//
// E' un controllo per nome, non un confine assoluto: un comando che costruisce
// il nome a runtime (codifiche, variabili, glob parziali come `.e*`) passa.
// Il limite e' dichiarato in docs/CLAUDE_CODE_SETUP.md; la difesa principale
// resta non avere segreti nei worktree degli agenti.
//
// Fail-closed: un evento illeggibile esce con 2. Nessuna rete, nessuna
// dipendenza, nessuna scrittura.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const PREFISSO = "VINEA-SECRET-GUARD";

// Nomi di file che contengono segreti. `.env.example` (e `.env.*.example`)
// resta leggibile: e' il contratto documentato delle variabili, senza valori.
const NOME_SEGRETO = [
  /^\.env$/i,
  /^\.env\.(?!.*\bexample$).+$/i,
  /^[^/\\]+\.env$/i,
  /^.+\.(pem|key|p12|pfx|jks|keystore)$/i,
  /^\.?credentials(\.json)?$/i,
  /^id_(rsa|dsa|ecdsa|ed25519)$/i,
  /^\.netrc$/i,
  /^\.pgpass$/i,
  /^hosts\.yml$/i, // gh: ~/.config/gh/hosts.yml contiene il token
];

export function nomeDiSegreto(percorso) {
  if (typeof percorso !== "string" || percorso === "") return false;
  const pulito = percorso.replace(/[\\/]+$/, "");
  const base = pulito.split(/[\\/]/).pop() ?? "";
  return NOME_SEGRETO.some((re) => re.test(base));
}

// Nella shell: un riferimento a `.env` (o `.env.qualcosa`, o `.env*`) che inizia
// a un confine (inizio, spazio, virgolette, separatore, `=`), cosi' che
// `process.env` e `import.meta.env` restino ammessi; poi gli altri nomi.
const SHELL_SEGRETO = [
  /(^|[\s'"`/\\=:(])\.env(?!\.example\b)(?:[.*?\w-]*)(?=$|[\s'"`;|&)<>,])/i,
  /(^|[\s'"`/\\=:(])[\w.-]*\.(pem|key|p12|pfx|jks|keystore)(?=$|[\s'"`;|&)<>,])/i,
  /\.?credentials\.json\b/i,
  /\bid_(rsa|dsa|ecdsa|ed25519)\b/i,
  /(^|[\s'"`/\\])\.netrc\b/i,
  /(^|[\s'"`/\\])\.pgpass\b/i,
  /gh[\\/]hosts\.yml\b/i,
  /\bgh\s+auth\s+token\b/i,
];

export function comandoNominaSegreto(comando) {
  if (typeof comando !== "string") return false;
  return SHELL_SEGRETO.some((re) => re.test(comando));
}

// Glob di Glob/Grep che puntano esplicitamente ai segreti (`**/.env*`, `*.pem`).
export function globNominaSegreto(pattern) {
  if (typeof pattern !== "string" || pattern === "") return false;
  return pattern
    .split(/[\\/]/)
    .some((parte) => /^\.env(?!\.example$)/i.test(parte) || /\.(pem|key|p12|pfx)$/i.test(parte));
}

/**
 * @returns {string|null} null se lo strumento puo' procedere.
 */
export function valutaEvento(evento) {
  if (!evento || typeof evento !== "object") return "evento dell'hook illeggibile";
  const input = evento.tool_input ?? {};
  switch (evento.tool_name) {
    case "Read":
    case "NotebookRead":
      return nomeDiSegreto(input.file_path ?? input.notebook_path)
        ? `lettura di un file di segreti: ${input.file_path ?? input.notebook_path}`
        : null;
    case "Grep":
      if (nomeDiSegreto(input.path)) return `ricerca dentro un file di segreti: ${input.path}`;
      if (globNominaSegreto(input.glob)) return `glob verso file di segreti: ${input.glob}`;
      return null;
    case "Glob":
      return globNominaSegreto(input.pattern) ? `glob verso file di segreti: ${input.pattern}` : null;
    case "Bash":
    case "PowerShell":
      return comandoNominaSegreto(input.command)
        ? "il comando nomina un file di segreti o stampa un token"
        : null;
    default:
      return null;
  }
}

function main() {
  let evento;
  try {
    evento = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    evento = null;
  }
  const motivo = valutaEvento(evento);
  if (motivo) {
    process.stderr.write(`${PREFISSO}: bloccato: ${motivo}\n`);
    process.exit(2);
  }
  process.exit(0);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
