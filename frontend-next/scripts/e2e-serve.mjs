#!/usr/bin/env node
// Server dell'app per la suite browser: costruisce con l'ambiente di prova
// (le NEXT_PUBLIC_* sono incorporate in fase di build) e avvia `next start`.
// Lanciato da `webServer` di playwright.config.ts, che passa l'ambiente.
//
// E2E_SKIP_BUILD=1 riusa `.next` esistente: solo per iterare, mai in CI.

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const radiceApp = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const next = path.join(radiceApp, "node_modules", "next", "dist", "bin", "next");
const porta = process.env.PORT ?? "3100";

const riusa = process.env.E2E_SKIP_BUILD === "1" && existsSync(path.join(radiceApp, ".next", "BUILD_ID"));
if (!riusa) {
  console.log("[e2e-serve] next build con l'ambiente di prova…");
  const build = spawnSync(process.execPath, [next, "build"], { cwd: radiceApp, stdio: "inherit", env: process.env });
  if (build.status !== 0) process.exit(build.status ?? 1);
} else {
  console.log("[e2e-serve] build esistente riusata (E2E_SKIP_BUILD=1).");
}

const server = spawn(process.execPath, [next, "start", "-p", porta, "-H", "127.0.0.1"], {
  cwd: radiceApp,
  stdio: "inherit",
  env: process.env,
});
for (const segnale of ["SIGINT", "SIGTERM"]) process.on(segnale, () => server.kill(segnale));
server.on("exit", (codice) => process.exit(codice ?? 0));
