import { pathToFileURL } from "node:url";

const TITLE = "[OBS-01] Technical heartbeat";
const MARKER = "<!-- vinea-obs-01 -->";
const HOURS = 60 * 60 * 1000;

export async function checkLiveness(fetchImpl = fetch) {
  try {
    const response = await fetchImpl("https://vineawineclub.com/api/health", {
      redirect: "error", credentials: "omit", cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
    // Never publish a response body: an intermediary might return sensitive HTML.
    if (response.status !== 200) { await response.body?.cancel(); return ["next_unavailable"]; }
    const reader = response.body?.getReader();
    if (!reader) return ["next_invalid_health"];
    let text = "";
    let bytes = 0;
    try {
      const decoder = new TextDecoder();
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        bytes += chunk.value.byteLength;
        if (bytes > 128) { await reader.cancel(); return ["next_invalid_health"]; }
        text += decoder.decode(chunk.value, { stream: true });
      }
      text += decoder.decode();
      const body = JSON.parse(text);
      return body?.status === "ok" && body?.service === "vinea-next" ? [] : ["next_invalid_health"];
    } finally { reader.releaseLock(); }
  } catch { return ["next_unreachable"]; }
}

/** Observe runs only. Never call a payment function or read its payload/logs. */
export function checkPayoutHeartbeat({ enabled, state, runs, now = Date.now() }) {
  if (enabled !== "true") return [];
  if (state !== "active") return ["payout_scheduler_inactive"];
  const main = runs.filter((run) => run.head_branch === "main")
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  const completed = main.find((run) => run.status === "completed");
  const successful = main.find((run) => run.conclusion === "success");
  const findings = [];
  if (completed && completed.conclusion !== "success") findings.push("payout_job_failed");
  const age = now - Date.parse(successful?.created_at ?? "");
  // 6h schedule plus 6h tolerance for GitHub scheduling delays observed in this repo.
  if (!Number.isFinite(age) || age < 0 || age > 12 * HOURS) findings.push("payout_heartbeat_stale");
  return findings;
}

const ALLOWED = new Set([
  "next_unavailable", "next_invalid_health", "next_unreachable",
  "payout_scheduler_inactive", "payout_job_failed", "payout_heartbeat_stale",
  "github_monitor_unavailable",
]);

export async function syncAlert(api, findings, owner) {
  // This issue is public: strictly allowlisted codes, no upstream strings or URLs.
  if (findings.some((code) => !ALLOWED.has(code))) throw new Error("invalid_monitor_code");
  const codes = [...new Set(findings)].sort();
  const issues = (await api("GET", "/issues?state=open&creator=github-actions%5Bbot%5D&per_page=100"))
    .filter((issue) => !issue.pull_request && issue.title === TITLE && issue.body?.includes(MARKER));
  if (!codes.length) {
    for (const issue of issues) await api("PATCH", `/issues/${issue.number}`, { state: "closed", state_reason: "completed" });
    return "healthy";
  }
  const mention = /^[A-Za-z0-9-]{1,39}$/.test(owner) ? `@${owner}` : "Repository owner";
  const body = `${MARKER}\n${mention}: controllo tecnico da verificare.\n\n${codes.map((code) => `- ${code}`).join("\n")}\n\nRunbook: docs/VPM_022C_OBS_01.md. Nessun payload utente in questa issue.`;
  if (!issues.length) await api("POST", "/issues", { title: TITLE, body });
  else if (issues[0].body !== body) await api("PATCH", `/issues/${issues[0].number}`, { body });
  return "alert";
}

export function createApi(env, fetchImpl = fetch) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(env.GITHUB_REPOSITORY ?? "") || !env.GITHUB_TOKEN) {
    throw new Error("github_monitor_configuration");
  }
  return async (method, path, body) => {
    const response = await fetchImpl(`https://api.github.com/repos/${env.GITHUB_REPOSITORY}${path}`, {
      method, redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { Authorization: `Bearer ${env.GITHUB_TOKEN}`, Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!response.ok) throw new Error("github_monitor_unavailable");
    return response.status === 204 ? null : response.json();
  };
}

export async function run({ env = process.env, fetchImpl = fetch, say = console.log } = {}) {
  const findings = await checkLiveness(fetchImpl);
  const api = createApi(env, fetchImpl);
  if (env.PAYOUTS_SCHEDULER_ENABLED === "true") {
    try {
      const state = await api("GET", "/actions/workflows/payouts-auto-release.yml");
      const data = await api("GET", "/actions/workflows/payouts-auto-release.yml/runs?branch=main&per_page=30");
      findings.push(...checkPayoutHeartbeat({ enabled: "true", state: state.state, runs: data.workflow_runs }));
    } catch { findings.push("github_monitor_unavailable"); }
  }
  const outcome = await syncAlert(api, findings, env.GITHUB_REPOSITORY.split("/")[0]);
  say(`[VINEA_OBS] heartbeat=${outcome} codes=${findings.join(",") || "none"}`);
  return findings.length ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().then((code) => { process.exitCode = code; }).catch(() => {
    console.error("[VINEA_OBS] github_monitor_unavailable");
    process.exitCode = 1;
  });
}
