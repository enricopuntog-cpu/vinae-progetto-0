#!/usr/bin/env node
// Stack Supabase locale ed effimero per la suite browser (VPM-LAB-003).
//
//   bun run e2e:stack up      avvia lo stack con le migrazioni del checkout
//   bun run e2e:stack status  stato dei container (senza stampare le chiavi)
//   bun run e2e:stack down    ferma e DISTRUGGE lo stack locale (--no-backup)
//
// Stessa CLI fissata e stessi servizi del gate `supabase-db-regression.yml`.
// Mai un progetto ospitato: la CLI lavora solo sui container Docker locali.

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const VERSIONE_CLI = "2.117.0";
const ESCLUSI = "realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor";
const RADICE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

const supabase = (args) =>
  spawnSync("npx", ["--yes", `supabase@${VERSIONE_CLI}`, ...args], {
    cwd: RADICE,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, SUPABASE_INTERNAL_IMAGE_REGISTRY: process.env.SUPABASE_INTERNAL_IMAGE_REGISTRY ?? "public.ecr.aws" },
  });

const dockerPronto = () =>
  spawnSync("docker", ["info"], { stdio: "ignore", shell: process.platform === "win32" }).status === 0;

const comando = process.argv[2];

if (comando === "up") {
  if (!dockerPronto()) {
    console.error("Docker non è in esecuzione: avviare Docker Desktop e riprovare. Senza stack isolato i casi sono NON VERIFICATI.");
    process.exit(2);
  }
  // L'output di `supabase start` contiene le chiavi dello stack: non lo mostriamo.
  const esito = spawnSync("npx", ["--yes", `supabase@${VERSIONE_CLI}`, "start", "--exclude", ESCLUSI], {
    cwd: RADICE,
    encoding: "utf8",
    shell: process.platform === "win32",
    env: { ...process.env, SUPABASE_INTERNAL_IMAGE_REGISTRY: process.env.SUPABASE_INTERNAL_IMAGE_REGISTRY ?? "public.ecr.aws" },
  });
  if (esito.status !== 0) {
    const filtrato = `${esito.stdout}\n${esito.stderr}`
      .split(/\r?\n/)
      .filter((r) => !/key|secret|jwt|token|password|postgres(ql)?:\/\//i.test(r))
      .slice(-20)
      .join("\n");
    console.error(filtrato);
    console.error("Stack non avviato.");
    process.exit(esito.status ?? 1);
  }
  console.log("Stack locale avviato con le migrazioni del checkout.");
} else if (comando === "down") {
  process.exit(supabase(["stop", "--no-backup"]).status ?? 1);
} else if (comando === "status") {
  const esito = spawnSync("docker", ["ps", "--filter", "name=supabase_", "--format", "{{.Names}} {{.Status}}"], {
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  console.log(esito.stdout.trim() || "Nessun container supabase_* in esecuzione.");
} else {
  console.error("Uso: bun run e2e:stack up|status|down");
  process.exit(2);
}
