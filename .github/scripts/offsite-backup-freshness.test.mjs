import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import {
  ALERT_LABEL,
  CATEGORIES,
  archiveStamp,
  backupSets,
  createB2Client,
  dailyPrefixes,
  evaluateRuns,
  runFreshnessWatch,
  staleAfterHours,
  syncAlertIssue,
} from "./offsite-backup-freshness.mjs";

const NOW = new Date("2026-09-23T20:00:00Z");
const HOUR = 3_600_000;
const ENV = {
  B2_S3_ENDPOINT: "https://s3.eu-central-003.backblazeb2.com",
  B2_BUCKET: "bucket-test",
  B2_KEY_ID: "fake-key-id-must-not-leak",
  B2_APPLICATION_KEY: "fake-application-key-must-not-leak",
  GITHUB_TOKEN: "ghs_fake_token_must_not_leak",
  GITHUB_REPOSITORY: "owner/repo",
  GITHUB_REPOSITORY_OWNER: "owner",
  GITHUB_RUN_ID: "42",
};
const SECRETS = [ENV.B2_KEY_ID, ENV.B2_APPLICATION_KEY, ENV.GITHUB_TOKEN];

const iso = (ms) => new Date(ms).toISOString();
const stampOf = (date) => date.toISOString().slice(0, 19).replaceAll(":", "-") + "Z";

/** Builds the B2 objects a real backup run leaves behind, with optional defects. */
const backupObjects = (stampDate, overrides = {}) => {
  const o = {
    archive: true,
    sidecar: true,
    header: "age-encryption.org/v1\n",
    uploadDelayMs: 3 * 60_000,
    retentionDays: 30,
    mode: "GOVERNANCE",
    metadataSha: undefined,
    ...overrides,
  };
  const month = stampDate.toISOString().slice(0, 7).replace("-", "/");
  const key = `daily/${month}/vinea-${stampOf(stampDate)}.tar.gz.age`;
  const body = Buffer.from(`${o.header}encrypted bytes for ${key}`, "latin1");
  const sha = createHash("sha256").update(body).digest("hex");
  const uploaded = stampDate.getTime() + o.uploadDelayMs;
  const retention = { Mode: o.mode, RetainUntilDate: iso(uploaded + o.retentionDays * 24 * HOUR) };
  const objects = {};
  if (o.archive) {
    objects[key] = { LastModified: iso(uploaded), body, sha: o.metadataSha ?? sha, retention };
  }
  if (o.sidecar) {
    objects[`${key}.sha256`] = {
      LastModified: iso(uploaded + 1000),
      body: Buffer.from(`${sha}  /tmp/tmp.abc/vinea-${stampOf(stampDate)}.tar.gz.age\n`),
      retention,
    };
  }
  return objects;
};

/** In-memory B2 with the same read-only surface as the real client. */
const fakeB2 = (objects, { listFails = false } = {}) => {
  const calls = [];
  const get = (key) => {
    const object = objects[key];
    if (!object) throw new Error(`NoSuchKey ${key}`);
    return object;
  };
  return {
    calls,
    list: async (prefix) => {
      calls.push(`list ${prefix}`);
      if (listFails) throw new Error(`Could not connect to the endpoint URL (${ENV.B2_APPLICATION_KEY})`);
      return Object.entries(objects)
        .filter(([key]) => key.startsWith(prefix))
        .map(([Key, object]) => ({ Key, LastModified: object.LastModified, Size: object.body.length }));
    },
    head: async (key) => {
      const object = get(key);
      return { ContentLength: object.body.length, Metadata: { sha256: object.sha } };
    },
    retention: async (key) => ({ Retention: get(key).retention }),
    getText: async (key) => get(key).body.toString("utf8"),
    getRange: async (key, start, end) => get(key).body.subarray(start, end + 1),
  };
};

const run = (overrides = {}) => ({
  id: 1,
  status: "completed",
  conclusion: "success",
  created_at: iso(NOW.getTime() - 6 * HOUR),
  html_url: "https://github.com/owner/repo/actions/runs/1",
  ...overrides,
});

const fakeGitHub = ({ state = "active", runs = [run()], open = [], failRuns = false } = {}) => {
  const actions = [];
  let nextIssue = 7;
  return {
    actions,
    workflowState: async () => state,
    backupRuns: async () => {
      if (failRuns) throw new Error("GitHub GET /actions/workflows/offsite-backup.yml/runs: HTTP 503");
      return runs;
    },
    openAlerts: async () => open,
    ensureLabel: async () => actions.push("label"),
    createIssue: async (issue) => {
      actions.push(["create", issue]);
      return { number: nextIssue++ };
    },
    updateIssue: async (number, patch) => actions.push(["update", number, patch]),
    comment: async (number, body) => actions.push(["comment", number, body]),
  };
};

const watch = async ({ objects = {}, b2Options, github = fakeGitHub(), env = ENV, now = NOW } = {}) => {
  const lines = [];
  const b2 = fakeB2(objects, b2Options);
  const result = await runFreshnessWatch({
    env,
    now,
    b2Factory: () => b2,
    githubFactory: () => github,
    log: (line) => lines.push(line),
  });
  return { ...result, log: lines.join("\n"), github, b2, categories: result.findings.map((f) => f.category) };
};

const hoursAgo = (h) => new Date(NOW.getTime() - h * HOUR);

test("B: backup fresco e run riuscito → PASS senza issue", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(6)) });
  assert.equal(r.ok, true, r.log);
  assert.deepEqual(r.findings, []);
  assert.match(r.log, /PASS/);
  assert.deepEqual(r.github.actions, []);
});

test("B: usa il backup completo piu recente tra piu run dello stesso giorno", async () => {
  const r = await watch({
    objects: { ...backupObjects(hoursAgo(30)), ...backupObjects(hoursAgo(18)), ...backupObjects(hoursAgo(6)) },
  });
  assert.equal(r.ok, true, r.log);
  assert.match(r.summary, /eta 6\.0 h/);
});

test("C: backup piu vecchio della soglia → FAIL BACKUP_STALE e issue aperta", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(21)), github: fakeGitHub({ runs: [run({ created_at: iso(NOW - 8 * HOUR) })] }) });
  assert.equal(r.ok, false);
  assert.deepEqual(r.categories, [CATEGORIES.STALE]);
  const [create] = r.github.actions.filter((a) => a[0] === "create");
  assert.ok(create, "issue non creata");
  assert.deepEqual(create[1].labels, [ALERT_LABEL]);
  assert.match(create[1].body, /@owner/);
  assert.match(create[1].body, /BACKUP_STALE/);
});

test("C: la soglia e 20 h: 19.9 h passa, 20.1 h fallisce", async () => {
  assert.equal((await watch({ objects: backupObjects(hoursAgo(19.9)) })).ok, true);
  assert.equal((await watch({ objects: backupObjects(hoursAgo(20.1)) })).ok, false);
});

test("C: nessun backup in B2 → FAIL BACKUP_STALE", async () => {
  const r = await watch({ objects: {} });
  assert.deepEqual(r.categories, [CATEGORIES.STALE]);
});

test("D: archivio senza sidecar → FAIL BACKUP_INCOMPLETE, non conta come fresco", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(5), { sidecar: false }) });
  assert.equal(r.ok, false);
  assert.deepEqual(r.categories.sort(), [CATEGORIES.INCOMPLETE, CATEGORIES.STALE].sort());
  assert.match(r.log, /archivio senza sidecar/);
});

test("D: archivio incompleto recente con copia valida precedente → INCOMPLETE ma eta dalla copia valida", async () => {
  const r = await watch({ objects: { ...backupObjects(hoursAgo(14)), ...backupObjects(hoursAgo(3), { sidecar: false }) } });
  assert.deepEqual(r.categories, [CATEGORIES.INCOMPLETE]);
  assert.match(r.summary, /eta 14\.0 h/);
});

test("E: sidecar senza archivio → FAIL BACKUP_INCOMPLETE", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(5), { archive: false }) });
  assert.equal(r.ok, false);
  assert.ok(r.categories.includes(CATEGORIES.INCOMPLETE));
  assert.match(r.log, /sidecar senza archivio/);
});

test("un upload in corso entro 60 minuti non genera allarmi", async () => {
  const inProgress = backupObjects(new Date(NOW.getTime() - 10 * 60_000), { sidecar: false });
  const r = await watch({ objects: { ...backupObjects(hoursAgo(12)), ...inProgress } });
  assert.equal(r.ok, true, r.log);
  assert.match(r.log, /in corso, ignorato/);
});

test("integrita: metadata, header, Object Lock e date incoerenti non contano come backup", async () => {
  const cases = [
    [{ metadataSha: "0".repeat(64) }, /SHA-256 diversi/],
    [{ header: "not-an-age-file-header\n" }, /header age assente/],
    [{ mode: "COMPLIANCE" }, /Object Lock non conforme/],
    [{ retentionDays: 7 }, /Object Lock non conforme/],
    [{ uploadDelayMs: 3 * HOUR }, /incoerente con il timestamp/],
  ];
  for (const [defect, reason] of cases) {
    const r = await watch({ objects: backupObjects(hoursAgo(5), defect) });
    assert.equal(r.ok, false, `accettato: ${JSON.stringify(defect)}`);
    assert.ok(r.categories.includes(CATEGORIES.INCOMPLETE));
    assert.match(r.log, reason);
  }
});

test("F: B2 non raggiungibile → FAIL CHECK_ERROR, mai PASS", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(1)), b2Options: { listFails: true } });
  assert.equal(r.ok, false);
  assert.deepEqual(r.categories, [CATEGORIES.CHECK_ERROR]);
  assert.match(r.log, /B2 non verificabile/);
});

test("F: endpoint o configurazione B2 errati → FAIL prima di qualunque chiamata", async () => {
  for (const env of [
    { ...ENV, B2_S3_ENDPOINT: "https://s3.eu-central-003.backblazeb2.com.evil.example" },
    { ...ENV, B2_S3_ENDPOINT: "http://s3.eu-central-003.backblazeb2.com" },
    { ...ENV, B2_BUCKET: "" },
    { ...ENV, B2_APPLICATION_KEY: "" },
  ]) {
    let calls = 0;
    const exec = async () => {
      calls += 1;
      return "{}";
    };
    const lines = [];
    const result = await runFreshnessWatch({
      env,
      now: NOW,
      b2Factory: (options) => createB2Client({ ...options, execFileImpl: exec }),
      githubFactory: () => fakeGitHub(),
      log: (line) => lines.push(line),
    });
    assert.equal(result.ok, false);
    assert.ok(result.findings.some((f) => f.category === CATEGORIES.CHECK_ERROR));
    assert.equal(calls, 0);
  }
});

test("F: il client B2 reale rifiuta operazioni di scrittura e propaga gli errori della CLI", async () => {
  const seen = [];
  const exec = async (file, args, options) => {
    seen.push({ file, args, env: options.env });
    const error = new Error("Command failed");
    error.stderr = `Could not connect to the endpoint URL; key ${ENV.B2_KEY_ID} secret ${ENV.B2_APPLICATION_KEY}\n`;
    throw error;
  };
  const redactSecrets = (text) => SECRETS.reduce((out, s) => out.split(s).join("***"), text);
  const b2 = createB2Client({ env: ENV, execFileImpl: exec, redact: redactSecrets });
  await assert.rejects(b2.list("daily/2026/09/"), (error) => {
    assert.match(error.message, /B2 list-objects-v2 non riuscito/);
    for (const secret of SECRETS) assert.ok(!error.message.includes(secret));
    return true;
  });
  const [{ file, args, env }] = seen;
  assert.equal(file, "aws");
  assert.deepEqual(args.slice(0, 2), ["s3api", "list-objects-v2"]);
  for (const secret of SECRETS) assert.ok(!args.join(" ").includes(secret), "secret negli argomenti");
  assert.equal(env.AWS_REGION, "eu-central-003");
  assert.equal(env.GITHUB_TOKEN, undefined, "token GitHub passato alla CLI B2");
  assert.equal(Object.keys(b2).some((name) => /put|delete|copy/i.test(name)), false);
});

test("G: nessun secret nei log, anche quando B2 e GitHub falliscono", async () => {
  const github = fakeGitHub({ failRuns: true });
  const r = await watch({ objects: {}, b2Options: { listFails: true }, github });
  assert.equal(r.ok, false);
  for (const secret of SECRETS) {
    assert.ok(!r.log.includes(secret), `secret nei log: ${secret.slice(0, 8)}...`);
    assert.ok(!JSON.stringify(r.findings).includes(secret));
    assert.ok(!JSON.stringify(github.actions).includes(secret));
  }
});

test("run fallito → BACKUP_RUN_FAILED anche se B2 e ancora fresco", async () => {
  const github = fakeGitHub({ runs: [run({ conclusion: "failure", created_at: iso(NOW - HOUR) }), run()] });
  const r = await watch({ objects: backupObjects(hoursAgo(6)), github });
  assert.deepEqual(r.categories, [CATEGORIES.RUN_FAILED]);
});

test("backup mai partito: nessun run recente, run saltato o workflow disattivato", () => {
  const staleAfterMs = 20 * HOUR;
  const categories = (input) => evaluateRuns({ now: NOW, staleAfterMs, ...input }).map((f) => f.category);
  assert.deepEqual(categories({ workflowState: "active", runs: [run()] }), []);
  assert.deepEqual(categories({ workflowState: "active", runs: [] }), [CATEGORIES.NOT_STARTED]);
  assert.deepEqual(
    categories({ workflowState: "active", runs: [run({ created_at: iso(NOW - 21 * HOUR) })] }),
    [CATEGORIES.NOT_STARTED],
  );
  assert.deepEqual(categories({ workflowState: "active", runs: [run({ conclusion: "skipped" })] }), [
    CATEGORIES.NOT_STARTED,
  ]);
  assert.deepEqual(categories({ workflowState: "disabled_inactivity", runs: [run()] }), [CATEGORIES.NOT_STARTED]);
  // Un run in corso non nasconde il fallimento dell'ultimo run concluso.
  assert.deepEqual(
    categories({
      workflowState: "active",
      runs: [run({ status: "in_progress", conclusion: null, created_at: iso(NOW - 60_000) }), run({ conclusion: "timed_out" })],
    }),
    [CATEGORIES.RUN_FAILED],
  );
});

test("GitHub non verificabile → FAIL CHECK_ERROR", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(6)), github: fakeGitHub({ failRuns: true }) });
  assert.deepEqual(r.categories, [CATEGORIES.CHECK_ERROR]);
});

test("la soglia manuale puo solo restringere", () => {
  assert.equal(staleAfterHours(""), 20);
  assert.equal(staleAfterHours(undefined), 20);
  assert.equal(staleAfterHours("0.1"), 0.1);
  assert.equal(staleAfterHours("20"), 20);
  for (const bad of ["0", "-1", "20.5", "26", "abc", "Infinity"]) assert.throws(() => staleAfterHours(bad));
});

test("prova manuale con soglia ridotta: FAIL segnalato come prova", async () => {
  const r = await watch({ objects: backupObjects(hoursAgo(6)), env: { ...ENV, FRESHNESS_STALE_AFTER_HOURS: "0.1" } });
  assert.equal(r.ok, false);
  assert.ok(r.categories.includes(CATEGORIES.STALE));
  const [create] = r.github.actions.filter((a) => a[0] === "create");
  assert.match(create[1].body, /Prova manuale con soglia ridotta: 0\.1 h/);
});

test("issue: nessun duplicato, commento solo al cambio di categorie, chiusura al rientro", async () => {
  const stale = [{ category: CATEGORIES.STALE, message: "vecchio" }];
  const openIssue = { number: 3, body: "<!-- backup-freshness:BACKUP_STALE -->\n..." };
  const base = { owner: "owner", runUrl: "u", drill: "", summary: "s" };

  const same = fakeGitHub({ open: [openIssue] });
  assert.match(await syncAlertIssue({ github: same, findings: stale, ...base }), /invariato/);
  assert.deepEqual(same.actions, []);

  const changed = fakeGitHub({ open: [openIssue] });
  await syncAlertIssue({
    github: changed,
    findings: [...stale, { category: CATEGORIES.RUN_FAILED, message: "fallito" }],
    ...base,
  });
  assert.deepEqual(changed.actions.map((a) => a[0]), ["update", "comment"]);

  const recovered = fakeGitHub({ open: [openIssue] });
  assert.match(await syncAlertIssue({ github: recovered, findings: [], ...base }), /chiuso/);
  assert.deepEqual(recovered.actions.map((a) => a[0]), ["comment", "update"]);
  assert.equal(recovered.actions[1][2].state, "closed");

  const quiet = fakeGitHub();
  assert.match(await syncAlertIssue({ github: quiet, findings: [], ...base }), /nessun allarme/);
  assert.deepEqual(quiet.actions, []);
});

test("chiavi: timestamp, prefissi mensili e raggruppamento", () => {
  assert.equal(
    archiveStamp("daily/2026/09/vinea-2026-09-23T07-50-01Z.tar.gz.age").toISOString(),
    "2026-09-23T07:50:01.000Z",
  );
  for (const key of [
    "daily/2026/08/vinea-2026-09-23T07-50-01Z.tar.gz.age",
    "weekly/2026/09/vinea-2026-09-23T07-50-01Z.tar.gz.age",
    "daily/2026/02/vinea-2026-02-30T07-50-01Z.tar.gz.age",
    "daily/2026/09/vinea-2026-09-23T07-50-01Z.tar.gz",
  ]) {
    assert.equal(archiveStamp(key), null, key);
  }
  assert.deepEqual(dailyPrefixes(new Date("2026-01-03T00:00:00Z")), ["daily/2026/01/", "daily/2025/12/"]);
  const sets = backupSets([
    { Key: "daily/2026/09/vinea-2026-09-22T07-50-01Z.tar.gz.age" },
    { Key: "daily/2026/09/vinea-2026-09-23T07-50-01Z.tar.gz.age.sha256" },
    { Key: "daily/2026/09/vinea-2026-09-23T07-50-01Z.tar.gz.age" },
    { Key: "daily/2026/09/unrelated.txt" },
  ]);
  assert.equal(sets.length, 2);
  assert.ok(sets[0].archive && sets[0].sidecar);
  assert.ok(sets[1].archive && !sets[1].sidecar);
});
