#!/usr/bin/env node
// Backup freshness watch. Answers one question from primary evidence: how old is
// the newest complete backup that really exists in B2? A green GitHub run is not
// enough; the archive, its sidecar, the metadata hash, the age header and the
// Object Lock retention are all checked. It also reads the backup workflow runs
// so the alert can say whether the backup failed, never started or is just old.
// Every error fails closed. B2 access is read only by construction: the client
// accepts only list, head, retention and get operations.
// Usage: node .github/scripts/offsite-backup-freshness.mjs
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export const DEFAULT_STALE_AFTER_HOURS = 20;
export const PENDING_GRACE_MINUTES = 60;
export const ALERT_LABEL = "backup-freshness-alert";
export const BACKUP_WORKFLOW_FILE = "offsite-backup.yml";
const HOUR = 3_600_000;
const MINUTE = 60_000;
const DAILY_RETENTION_DAYS = 30;
const MAX_SETS_TO_INSPECT = 10;
const AGE_HEADER = "age-encryption.org/v1\n";
const ARCHIVE_KEY =
  /^daily\/(\d{4})\/(\d{2})\/vinea-(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})Z\.tar\.gz\.age$/;
const ENDPOINT = /^https:\/\/s3\.([a-z]{2}-[a-z]+-[0-9]{3})\.backblazeb2\.com$/;
const B2_READ_OPERATIONS = new Set(["list-objects-v2", "head-object", "get-object-retention", "get-object"]);

export const CATEGORIES = {
  RUN_FAILED: "BACKUP_RUN_FAILED",
  NOT_STARTED: "BACKUP_NOT_STARTED",
  STALE: "BACKUP_STALE",
  INCOMPLETE: "BACKUP_INCOMPLETE",
  CHECK_ERROR: "CHECK_ERROR",
};

const finding = (category, message) => ({ category, message });
const hours = (ms) => (ms / HOUR).toFixed(1);

/** Returns the stale threshold in hours; a manual override may only tighten it. */
export const staleAfterHours = (raw) => {
  const text = String(raw ?? "").trim();
  if (text === "") return DEFAULT_STALE_AFTER_HOURS;
  const value = Number(text);
  if (!Number.isFinite(value) || value <= 0 || value > DEFAULT_STALE_AFTER_HOURS) {
    throw new Error(`Soglia non valida: deve essere 0 < ore <= ${DEFAULT_STALE_AFTER_HOURS}`);
  }
  return value;
};

/** Parses the UTC instant encoded in a daily archive key; null if the key is foreign. */
export const archiveStamp = (key) => {
  const m = ARCHIVE_KEY.exec(key);
  if (!m) return null;
  const [, pathYear, pathMonth, y, mo, d, h, mi, s] = m;
  if (pathYear !== y || pathMonth !== mo) return null;
  const date = new Date(`${y}-${mo}-${d}T${h}:${mi}:${s}Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 19) !== `${y}-${mo}-${d}T${h}:${mi}:${s}`) {
    return null;
  }
  return date;
};

/** The current and previous UTC month prefixes of the daily tier. */
export const dailyPrefixes = (now) => {
  const current = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const previous = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const prefix = (d) => `daily/${d.getUTCFullYear()}/${String(d.getUTCMonth() + 1).padStart(2, "0")}/`;
  return [prefix(current), prefix(previous)];
};

/** Groups listed objects into backup sets (archive + sidecar), newest first. */
export const backupSets = (objects) => {
  const sets = new Map();
  for (const object of objects) {
    const isSidecar = object.Key.endsWith(".sha256");
    const base = isSidecar ? object.Key.slice(0, -".sha256".length) : object.Key;
    const stamp = archiveStamp(base);
    if (!stamp) continue;
    const set = sets.get(base) ?? { key: base, stamp };
    set[isSidecar ? "sidecar" : "archive"] = object;
    sets.set(base, set);
  }
  return [...sets.values()].sort((a, b) => b.stamp - a.stamp);
};

/** Validates one backup set against B2; returns null when complete, else the reason. */
export const inspectSet = async (b2, set, now) => {
  if (!set.archive) return "sidecar senza archivio";
  if (!set.sidecar) return "archivio senza sidecar";
  if (set.stamp.getTime() > now.getTime() + 5 * MINUTE) return "timestamp nel futuro";
  const uploadedAt = Date.parse(set.archive.LastModified);
  if (
    !Number.isFinite(uploadedAt) ||
    uploadedAt < set.stamp.getTime() - 5 * MINUTE ||
    uploadedAt > set.stamp.getTime() + 60 * MINUTE
  ) {
    return "data di caricamento incoerente con il timestamp del nome";
  }
  if (!(Number(set.archive.Size) > 0)) return "archivio vuoto";

  const head = await b2.head(set.key);
  const sha = head?.Metadata?.sha256 ?? "";
  if (!/^[0-9a-f]{64}$/.test(sha)) return "metadata sha256 assente o non valido";
  if (Number(head.ContentLength) !== Number(set.archive.Size)) return "dimensione archivio incoerente";

  const sidecar = await b2.getText(`${set.key}.sha256`, 4096);
  const m = /^([0-9a-f]{64}) [ *](\S+)\n?$/.exec(sidecar);
  if (!m) return "sidecar non valido";
  if (m[1] !== sha) return "sidecar e metadata con SHA-256 diversi";
  if (m[2].split("/").pop() !== set.key.split("/").pop()) return "sidecar riferito a un altro archivio";

  const minimumRetention = uploadedAt + DAILY_RETENTION_DAYS * 24 * HOUR - HOUR;
  for (const key of [set.key, `${set.key}.sha256`]) {
    const retention = (await b2.retention(key))?.Retention ?? {};
    const until = Date.parse(retention.RetainUntilDate ?? "");
    if (retention.Mode !== "GOVERNANCE" || !Number.isFinite(until) || until < minimumRetention) {
      return `Object Lock non conforme su ${key.endsWith(".sha256") ? "sidecar" : "archivio"}`;
    }
  }

  const header = await b2.getRange(set.key, 0, AGE_HEADER.length - 1);
  if (header.toString("latin1") !== AGE_HEADER) return "header age assente";
  return null;
};

/** Finds the newest complete backup in B2 and reports stale or incomplete sets. */
export const evaluateB2 = async ({ b2, now, staleAfterMs }) => {
  const findings = [];
  const pending = [];
  const objects = [];
  for (const prefix of dailyPrefixes(now)) objects.push(...(await b2.list(prefix)));

  let latest = null;
  let inspected = 0;
  for (const set of backupSets(objects)) {
    if (inspected++ >= MAX_SETS_TO_INSPECT) break;
    const problem = await inspectSet(b2, set, now);
    if (!problem) {
      latest = set;
      break;
    }
    const lastWrite = Math.max(
      ...[set.archive, set.sidecar].filter(Boolean).map((o) => Date.parse(o.LastModified) || 0),
    );
    if (now.getTime() - lastWrite < PENDING_GRACE_MINUTES * MINUTE) {
      pending.push(`${set.key}: ${problem}`);
      continue;
    }
    if (!findings.some((f) => f.category === CATEGORIES.INCOMPLETE)) {
      findings.push(finding(CATEGORIES.INCOMPLETE, `Backup piu recente incompleto: ${set.key} (${problem}).`));
    }
  }

  if (!latest) {
    findings.push(finding(CATEGORIES.STALE, "Nessun backup completo e verificabile in B2 negli ultimi due mesi."));
    return { findings, latest: null, ageMs: null, pending };
  }
  const ageMs = now.getTime() - latest.stamp.getTime();
  if (ageMs > staleAfterMs) {
    findings.push(
      finding(
        CATEGORIES.STALE,
        `Ultimo backup completo in B2 vecchio di ${hours(ageMs)} h (soglia ${hours(staleAfterMs)} h): ${latest.key}.`,
      ),
    );
  }
  return { findings, latest, ageMs, pending };
};

/** Classifies the backup workflow state and runs: failed, never started or skipped. */
export const evaluateRuns = ({ workflowState, runs, now, staleAfterMs }) => {
  const findings = [];
  if (workflowState !== "active") {
    findings.push(
      finding(CATEGORIES.NOT_STARTED, `Workflow di backup in stato "${workflowState}": le esecuzioni programmate non partono.`),
    );
  }
  const sorted = [...runs].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  const newest = sorted[0];
  if (!newest) {
    findings.push(finding(CATEGORIES.NOT_STARTED, "Nessun run del workflow di backup trovato."));
    return findings;
  }
  const sinceNewest = now.getTime() - Date.parse(newest.created_at);
  if (!(sinceNewest <= staleAfterMs)) {
    findings.push(
      finding(CATEGORIES.NOT_STARTED, `Nessun run di backup avviato da ${hours(sinceNewest)} h (soglia ${hours(staleAfterMs)} h).`),
    );
  }
  const completed = sorted.find((run) => run.status === "completed");
  if (completed?.conclusion === "skipped") {
    findings.push(
      finding(
        CATEGORIES.NOT_STARTED,
        `Ultimo run di backup saltato (${completed.html_url}): verificare BACKUP_OFFSITE_ENABLED.`,
      ),
    );
  } else if (completed && completed.conclusion !== "success") {
    findings.push(
      finding(CATEGORIES.RUN_FAILED, `Ultimo run di backup concluso con "${completed.conclusion}": ${completed.html_url}`),
    );
  }
  return findings;
};

/** Replaces every configured secret value, so no error path can print one. */
export const redactor = (env) => {
  const secrets = ["B2_KEY_ID", "B2_APPLICATION_KEY", "GITHUB_TOKEN"]
    .map((name) => env[name])
    .filter((value) => typeof value === "string" && value.length >= 4);
  return (text) => secrets.reduce((out, secret) => out.split(secret).join("***"), String(text));
};

const execFileAsync = (file, args, options) =>
  new Promise((resolve, reject) => {
    execFile(file, args, options, (error, stdout, stderr) => {
      if (error) {
        error.stderr = stderr;
        reject(error);
      } else {
        resolve(stdout);
      }
    });
  });

/** Read-only B2 client over the AWS CLI; refuses any operation outside the allowlist. */
export const createB2Client = ({ env, execFileImpl = execFileAsync, redact = (t) => t }) => {
  const region = ENDPOINT.exec(env.B2_S3_ENDPOINT ?? "")?.[1];
  if (!region) throw new Error("B2_S3_ENDPOINT non valido: usare https://s3.<regione>.backblazeb2.com");
  if (!env.B2_BUCKET || !env.B2_KEY_ID || !env.B2_APPLICATION_KEY) {
    throw new Error("Configurazione B2 incompleta per il controllo di freschezza");
  }
  const childEnv = {
    PATH: env.PATH ?? process.env.PATH,
    HOME: env.HOME ?? process.env.HOME ?? tmpdir(),
    AWS_ACCESS_KEY_ID: env.B2_KEY_ID,
    AWS_SECRET_ACCESS_KEY: env.B2_APPLICATION_KEY,
    AWS_REGION: region,
    AWS_DEFAULT_REGION: region,
    AWS_MAX_ATTEMPTS: "3",
    AWS_PAGER: "",
  };

  const call = async (operation, args) => {
    if (!B2_READ_OPERATIONS.has(operation)) throw new Error(`Operazione B2 non ammessa: ${operation}`);
    try {
      return await execFileImpl(
        "aws",
        [
          "s3api", operation,
          "--endpoint-url", env.B2_S3_ENDPOINT,
          "--bucket", env.B2_BUCKET,
          "--cli-connect-timeout", "10",
          "--cli-read-timeout", "30",
          "--output", "json",
          ...args,
        ],
        { env: childEnv, timeout: 120_000, maxBuffer: 16 * 1024 * 1024 },
      );
    } catch (error) {
      const detail = String(error.stderr || error.message || "").trim().split("\n").pop();
      throw new Error(`B2 ${operation} non riuscito: ${redact(detail)}`);
    }
  };

  const download = async (key, extraArgs, maxBytes) => {
    const dir = await mkdtemp(join(tmpdir(), "backup-freshness-"));
    try {
      const file = join(dir, "object");
      await call("get-object", ["--key", key, ...extraArgs, file]);
      const bytes = await readFile(file);
      if (bytes.length > maxBytes) throw new Error(`Oggetto B2 inatteso oltre ${maxBytes} byte: ${key}`);
      return bytes;
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  };

  return {
    list: async (prefix) => JSON.parse((await call("list-objects-v2", ["--prefix", prefix])) || "{}").Contents ?? [],
    head: async (key) => JSON.parse(await call("head-object", ["--key", key])),
    retention: async (key) => JSON.parse(await call("get-object-retention", ["--key", key])),
    getText: async (key, maxBytes) => (await download(key, [], maxBytes)).toString("utf8"),
    getRange: async (key, start, end) => download(key, ["--range", `bytes=${start}-${end}`], end - start + 1),
  };
};

/** Minimal GitHub REST client for workflow runs and the alert issue. */
export const createGitHubClient = ({ env, fetchImpl = fetch }) => {
  if (!env.GITHUB_TOKEN || !/^[\w.-]+\/[\w.-]+$/.test(env.GITHUB_REPOSITORY ?? "")) {
    throw new Error("GITHUB_TOKEN o GITHUB_REPOSITORY assenti");
  }
  const base = `${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${env.GITHUB_REPOSITORY}`;
  const request = async (method, path, body) => {
    const response = await fetchImpl(`${base}${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) throw new Error(`GitHub ${method} ${path.split("?")[0]}: HTTP ${response.status}`);
    return response.status === 204 ? null : response.json();
  };
  return {
    workflowState: async () => (await request("GET", `/actions/workflows/${BACKUP_WORKFLOW_FILE}`)).state,
    backupRuns: async () =>
      (await request("GET", `/actions/workflows/${BACKUP_WORKFLOW_FILE}/runs?per_page=20`)).workflow_runs ?? [],
    openAlerts: async () => request("GET", `/issues?state=open&labels=${ALERT_LABEL}&per_page=10`),
    ensureLabel: async () => {
      try {
        await request("GET", `/labels/${ALERT_LABEL}`);
      } catch {
        await request("POST", "/labels", {
          name: ALERT_LABEL,
          color: "b60205",
          description: "Allarme automatico freschezza backup offsite",
        });
      }
    },
    createIssue: async (issue) => request("POST", "/issues", issue),
    updateIssue: async (number, patch) => request("PATCH", `/issues/${number}`, patch),
    comment: async (number, body) => request("POST", `/issues/${number}/comments`, { body }),
  };
};

const SIGNATURE = /<!-- backup-freshness:(\S*) -->/;
export const signatureOf = (findings) => [...new Set(findings.map((f) => f.category))].sort().join(",");

const findingsText = (findings) => findings.map((f) => `- **${f.category}**: ${f.message}`).join("\n");

/** Opens, updates or closes the single alert issue; comments only when the categories change. */
export const syncAlertIssue = async ({ github, findings, owner, runUrl, drill, summary }) => {
  const open = (await github.openAlerts()).filter((issue) => !issue.pull_request);
  const current = open[0];
  if (findings.length === 0) {
    if (!current) return "nessun allarme aperto";
    await github.comment(current.number, `Rientrato. ${summary}\n\nControllo: ${runUrl}`);
    await github.updateIssue(current.number, { state: "closed", state_reason: "completed" });
    return `allarme #${current.number} chiuso`;
  }
  const signature = signatureOf(findings);
  const body = [
    `<!-- backup-freshness:${signature} -->`,
    `@${owner} il controllo di freschezza del backup offsite ha rilevato:`,
    "",
    findingsText(findings),
    "",
    drill ? `Prova manuale con soglia ridotta: ${drill}.` : "",
    `Controllo: ${runUrl}`,
    "",
    "Procedura: docs/CONTINUITY_AND_BACKUP_RUNBOOK.md, sezione \"Freschezza del backup\".",
  ].join("\n");
  if (!current) {
    await github.ensureLabel();
    const created = await github.createIssue({
      title: `Allarme backup offsite: ${signature}`,
      body,
      labels: [ALERT_LABEL],
    });
    return `allarme #${created.number} aperto`;
  }
  const previous = SIGNATURE.exec(current.body ?? "")?.[1];
  if (previous === signature) return `allarme #${current.number} gia aperto, invariato`;
  await github.updateIssue(current.number, { title: `Allarme backup offsite: ${signature}`, body });
  await github.comment(current.number, `Categorie cambiate: ${signature}\n\n${findingsText(findings)}\n\nControllo: ${runUrl}`);
  return `allarme #${current.number} aggiornato`;
};

/** Runs the whole watch; resolves with the findings, never throws. */
export const runFreshnessWatch = async ({
  env = process.env,
  now = new Date(),
  b2Factory = createB2Client,
  githubFactory = createGitHubClient,
  log = console.log,
} = {}) => {
  const redact = redactor(env);
  const say = (line) => log(redact(line));
  const findings = [];
  let staleAfterMs = DEFAULT_STALE_AFTER_HOURS * HOUR;
  let drill = "";
  try {
    const threshold = staleAfterHours(env.FRESHNESS_STALE_AFTER_HOURS);
    staleAfterMs = threshold * HOUR;
    if (threshold !== DEFAULT_STALE_AFTER_HOURS) drill = `${threshold} h invece di ${DEFAULT_STALE_AFTER_HOURS} h`;
  } catch (error) {
    findings.push(finding(CATEGORIES.CHECK_ERROR, error.message));
  }

  let summary = "Nessun backup completo verificato.";
  try {
    const b2 = b2Factory({ env, redact });
    const result = await evaluateB2({ b2, now, staleAfterMs });
    findings.push(...result.findings);
    for (const item of result.pending) say(`[backup-freshness] in corso, ignorato: ${item}`);
    if (result.latest) {
      summary = `Ultimo backup completo: ${result.latest.key}, eta ${hours(result.ageMs)} h.`;
    }
  } catch (error) {
    findings.push(finding(CATEGORIES.CHECK_ERROR, `B2 non verificabile: ${error.message}`));
  }

  let github = null;
  try {
    github = githubFactory({ env });
    const [workflowState, runs] = await Promise.all([github.workflowState(), github.backupRuns()]);
    findings.push(...evaluateRuns({ workflowState, runs, now, staleAfterMs }));
  } catch (error) {
    findings.push(finding(CATEGORIES.CHECK_ERROR, `Run GitHub non verificabili: ${error.message}`));
  }

  // Il repository e pubblico: i messaggi finiscono nei log e nell'issue.
  for (const f of findings) f.message = redact(f.message);
  say(`[backup-freshness] ${summary} Soglia ${hours(staleAfterMs)} h.`);
  for (const f of findings) say(`::error::${f.category}: ${f.message}`);

  if (github) {
    try {
      const runUrl = `${env.GITHUB_SERVER_URL ?? "https://github.com"}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID ?? ""}`;
      const outcome = await syncAlertIssue({
        github,
        findings,
        owner: env.GITHUB_REPOSITORY_OWNER ?? env.GITHUB_REPOSITORY.split("/")[0],
        runUrl,
        drill,
        summary,
      });
      say(`[backup-freshness] issue: ${outcome}`);
    } catch (error) {
      say(`::error::Allarme issue non aggiornato: ${error.message}`);
      findings.push(finding(CATEGORIES.CHECK_ERROR, "Issue di allarme non aggiornata."));
    }
  }

  say(findings.length === 0 ? "[backup-freshness] PASS" : `[backup-freshness] FAIL ${signatureOf(findings)}`);
  return { ok: findings.length === 0, findings, summary };
};

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  runFreshnessWatch().then(({ ok }) => {
    process.exitCode = ok ? 0 : 1;
  });
}
