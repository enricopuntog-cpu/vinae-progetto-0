#!/usr/bin/env node
// Test unitari per claude-secret-guard.mjs (VPM-LAB-002, D6).
// Solo nomi di file sintetici: nessun file reale viene letto.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { nomeDiSegreto, comandoNominaSegreto, globNominaSegreto, valutaEvento } from "./claude-secret-guard.mjs";

test("file di segreti riconosciuti, anche annidati e con percorsi Windows", () => {
  for (const p of [
    ".env",
    ".env.local",
    "frontend-next/.env.local",
    "./frontend-next/.env.production.local",
    "C:\\repo\\backend\\.env",
    "../altro/.env.test",
    "certs/server.pem",
    "deploy.key",
    "store.p12",
    "credentials.json",
    ".credentials.json",
    "~/.ssh/id_ed25519",
    ".netrc",
    "~/.config/gh/hosts.yml",
    "prod.env",
  ]) {
    assert.equal(nomeDiSegreto(p), true, p);
  }
});

test("nomi simili ma non segreti restano leggibili", () => {
  for (const p of [
    ".env.example",
    "frontend-next/.env.example",
    ".env.production.example",
    "docs/ENVIRONMENT.md",
    "src/env.ts",
    "environment.txt",
    "keyboard.tsx",
    "monkey.ts",
    "README.md",
    "",
  ]) {
    assert.equal(nomeDiSegreto(p), false, p);
  }
});

test("shell: comandi che nominano segreti rifiutati", () => {
  for (const c of [
    "cat .env",
    "cat frontend-next/.env.local",
    "Get-Content .\\backend\\.env",
    "type \".env.production\"",
    "cp .env /tmp/x",
    "grep KEY .env*",
    "openssl x509 -in server.pem",
    "cat ~/.config/gh/hosts.yml",
    "gh auth token",
    "cat ~/.netrc",
  ]) {
    assert.equal(comandoNominaSegreto(c), true, c);
  }
});

test("shell: process.env, import.meta.env e .env.example ammessi", () => {
  for (const c of [
    "node -e \"console.log(process.env.HOME)\"",
    "grep -r import.meta.env src",
    "cat frontend-next/.env.example",
    "git status",
    "bun --cwd frontend run test",
  ]) {
    assert.equal(comandoNominaSegreto(c), false, c);
  }
});

test("glob verso segreti rifiutati, glob generici ammessi", () => {
  assert.equal(globNominaSegreto("**/.env*"), true);
  assert.equal(globNominaSegreto("frontend-next/.env.local"), true);
  assert.equal(globNominaSegreto("**/*.pem"), true);
  assert.equal(globNominaSegreto("**/.env.example"), false);
  assert.equal(globNominaSegreto("**/*.ts"), false);
  assert.equal(globNominaSegreto(undefined), false);
});

test("evento: Read, Grep, Glob e Bash valutati; altri strumenti ammessi", () => {
  assert.notEqual(valutaEvento({ tool_name: "Read", tool_input: { file_path: "a/.env.local" } }), null);
  assert.equal(valutaEvento({ tool_name: "Read", tool_input: { file_path: "a/.env.example" } }), null);
  assert.notEqual(valutaEvento({ tool_name: "Grep", tool_input: { pattern: "KEY", path: ".env" } }), null);
  assert.notEqual(valutaEvento({ tool_name: "Grep", tool_input: { pattern: "KEY", glob: "**/.env*" } }), null);
  assert.equal(valutaEvento({ tool_name: "Grep", tool_input: { pattern: "KEY", path: "src" } }), null);
  assert.notEqual(valutaEvento({ tool_name: "Glob", tool_input: { pattern: "**/*.key" } }), null);
  assert.notEqual(valutaEvento({ tool_name: "Bash", tool_input: { command: "cat .env" } }), null);
  assert.equal(valutaEvento({ tool_name: "Edit", tool_input: { file_path: "src/a.ts" } }), null);
});

test("evento illeggibile rifiutato (fail-closed)", () => {
  assert.notEqual(valutaEvento(null), null);
  assert.notEqual(valutaEvento("x"), null);
});

const SCRIPT = fileURLToPath(new URL("./claude-secret-guard.mjs", import.meta.url));

test("cli: codice 2 e prefisso VINEA-SECRET-GUARD", () => {
  const r = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify({ tool_name: "Read", tool_input: { file_path: "frontend-next/.env.local" } }),
    encoding: "utf8",
  });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /^VINEA-SECRET-GUARD: bloccato/);
  const ok = spawnSync(process.execPath, [SCRIPT], {
    input: JSON.stringify({ tool_name: "Read", tool_input: { file_path: "README.md" } }),
    encoding: "utf8",
  });
  assert.equal(ok.status, 0);
  assert.equal(spawnSync(process.execPath, [SCRIPT], { input: "{rotto", encoding: "utf8" }).status, 2);
});
