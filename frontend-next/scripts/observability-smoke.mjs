// Isolated runtime proof. No Supabase stack or provider credentials; never a remote target.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const root = fileURLToPath(new URL("../", import.meta.url));
process.chdir(root);
assert.ok(existsSync(resolve(root, "src/instrumentation.ts")), "Run from frontend-next");
assert.ok(!readdirSync(root).some((name) => /^\.env(?:\..+)?$/.test(name) && name !== ".env.example"), "Use a worktree without environment files");
const fixture = resolve(root, "src/app/obs-synthetic-local");
assert.ok(!existsSync(fixture), "Never overwrite an existing route");
const reserve = createServer();
await new Promise((ok) => reserve.listen(0, "127.0.0.1", ok));
const port = reserve.address().port;
await new Promise((ok) => reserve.close(ok));
const origin = `http://127.0.0.1:${port}`;
const records = [];
const reports = [];
let output = "";
let server;
let browser;
let evidence;
const started = Date.now();
try {
  mkdirSync(resolve(fixture, "api"), { recursive: true });
  writeFileSync(resolve(fixture, "api/route.ts"), 'export function GET() { throw new Error("VINEA_OBS_SYNTHETIC"); }\n');
  writeFileSync(resolve(fixture, "page.tsx"), 'export default function Page(): never { throw new Error("VINEA_OBS_SYNTHETIC"); }\n');
  // Closed env: do not inherit any real app/Stripe/Supabase credentials from the shell.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    /^(?:PATH|PATHEXT|SYSTEMROOT|WINDIR|COMSPEC|TEMP|TMP|USERPROFILE|APPDATA|LOCALAPPDATA|HOME)$/i.test(key)));
  Object.assign(env, { NODE_ENV: "development", NEXT_TELEMETRY_DISABLED: "1",
    NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:59999", NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-only-local",
    PAYMENTS_ENABLED: "false", AI_ENABLED: "false" });
  server = spawn("node", ["node_modules/next/dist/bin/next", "dev", "--hostname", "127.0.0.1", "--port", String(port)],
    { cwd: root, env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  for (const stream of [server.stdout, server.stderr]) stream.on("data", (data) => { output += data.toString(); });
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`${origin}/api/health`, { signal: AbortSignal.timeout(1000) })).ok) break; } catch { /* startup */ }
    if (attempt > 120 || server.exitCode !== null) throw new Error("local_server_start_failed");
    await new Promise((ok) => setTimeout(ok, 500));
  }
  assert.equal((await fetch(`${origin}/obs-synthetic-local/api`)).status, 500);
  const edge = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
  browser = await chromium.launch({ headless: true,
    ...(process.platform === "win32" && existsSync(edge) ? { executablePath: edge } : {}) });
  const context = await browser.newContext();
  // Every browser request outside this isolated Next process is blocked.
  await context.route("**/*", (route) => route.request().url().startsWith(`${origin}/`) ? route.continue() : route.abort());
  await context.addCookies([{ name: "obs-test-cookie", value: "synthetic", url: origin, httpOnly: true }]);
  const page = await context.newPage();
  page.on("request", (request) => {
    if (new URL(request.url()).pathname === "/api/technical-events") {
      reports.push({ body: request.postData(), headers: request.headers() });
    }
  });
  await page.goto(`${origin}/accedi`, { waitUntil: "networkidle" });
  const delivered = page.waitForResponse((response) =>
    response.url().endsWith("/api/technical-events") && response.status() === 204);
  await page.evaluate(() => {
    setTimeout(() => { throw new Error("VINEA_OBS_SYNTHETIC"); }, 0);
    setTimeout(() => { void Promise.reject(new Error("VINEA_OBS_SYNTHETIC")); }, 0);
  });
  await delivered;
  await page.goto(`${origin}/obs-synthetic-local`, { waitUntil: "networkidle" });
  await page.getByRole("heading", { name: "Qualcosa non ha funzionato" }).waitFor();
  for (let attempt = 0; attempt < 30 && !reports.some((report) => report.body === "client_boundary"); attempt++) {
    await new Promise((ok) => setTimeout(ok, 100));
  }
  for (const report of reports) {
    assert.ok(["client_error", "client_rejection", "client_boundary"].includes(report.body));
    assert.equal(report.headers.cookie, undefined);
    assert.equal(report.headers.authorization, undefined);
    assert.equal(report.headers.referer, undefined);
  }
  for (const event of ["client_error", "client_rejection", "client_boundary"]) {
    assert.ok(reports.some((report) => report.body === event), `Missing ${event}`);
  }
  for (const match of output.matchAll(/\[VINEA_OBS\]\s+(\{[^\r\n]+\})/g)) records.push(JSON.parse(match[1]));
  assert.ok(records.some((record) => record.event === "server_error" && record.kind === "route"));
  for (const event of ["client_error", "client_rejection", "client_boundary"]) assert.ok(records.some((record) => record.event === event));
  evidence = { isolated: true, externalBrowserRequestsBlocked: true, records,
    noCookieAuthorizationOrReferrer: true, elapsedMs: Date.now() - started };
} finally {
  try {
    await browser?.close();
    if (server?.pid && server.exitCode === null) {
      if (process.platform === "win32") {
        const killed = spawnSync("taskkill", ["/PID", String(server.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
        assert.equal(killed.status, 0, "Could not stop the owned local process tree");
      }
      else server.kill("SIGTERM");
    }
  } finally {
    // Only the exact new fixture path checked above, never an existing user route.
    assert.equal(fixture, resolve(root, "src/app/obs-synthetic-local"));
    rmSync(fixture, { recursive: true, force: true });
    // Generated dev validators still reference the removed routes and break tsc.
    const generatedTypes = resolve(root, ".next/dev/types");
    assert.ok(generatedTypes.startsWith(resolve(root, ".next") + sep));
    rmSync(generatedTypes, { recursive: true, force: true });
  }
}
evidence.fixtureRemoved = !existsSync(fixture);
mkdirSync("e2e/artifacts", { recursive: true });
writeFileSync("e2e/artifacts/obs-01-runtime.json", JSON.stringify(evidence, null, 2));
console.log(JSON.stringify(evidence));
// Standalone proof: do not wait for Node's HTTP keepalive pool after cleanup.
process.exit(0);
