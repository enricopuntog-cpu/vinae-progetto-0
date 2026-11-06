import assert from "node:assert/strict";
import { test } from "node:test";
import { checkLiveness, checkPayoutHeartbeat, syncAlert, run } from "./technical-heartbeat.mjs";

test("liveness sends no credentials and accepts only the expected service", async () => {
  assert.deepEqual(await checkLiveness(async (url, options) => {
    assert.equal(url, "https://vineawineclub.com/api/health");
    assert.equal(options.credentials, "omit");
    assert.equal(options.redirect, "error");
    return Response.json({ status: "ok", service: "vinea-next" });
  }), []);
  assert.deepEqual(await checkLiveness(async () => Response.json({ status: "ok" })), ["next_invalid_health"]);
});

test("upstream failures, redirects, bad JSON and long bodies cannot leak into findings", async () => {
  for (const response of [new Response("fake@example.test", { status: 500 }),
    new Response("bad JSON"), new Response("x".repeat(129))]) {
    const codes = await checkLiveness(async () => response);
    assert.equal(codes.length, 1);
    assert.ok(codes[0].startsWith("next_"));
  }
  assert.deepEqual(await checkLiveness(async () => { throw new Error("fake-secret"); }), ["next_unreachable"]);
});

const now = Date.now();
const good = { head_branch: "main", created_at: new Date(now - 3_600_000).toISOString(), status: "completed", conclusion: "success" };
test("scheduler gate is exact and missing/disabled does not alarm", () => {
  for (const enabled of [undefined, "false", "TRUE", " true"]) {
    assert.deepEqual(checkPayoutHeartbeat({ enabled }), []);
  }
  assert.deepEqual(checkPayoutHeartbeat({ enabled: "true", state: "active", runs: [good], now }), []);
  assert.deepEqual(checkPayoutHeartbeat({ enabled: "true", state: "disabled_manually", runs: [], now }), ["payout_scheduler_inactive"]);
});

test("stale/missing runs alarm even if GitHub never started a failing job", () => {
  for (const runs of [[], [{ ...good, head_branch: "other" }], [{ ...good, created_at: new Date(now - 13 * 3_600_000).toISOString() }]]) {
    assert.deepEqual(checkPayoutHeartbeat({ enabled: "true", state: "active", runs, now }), ["payout_heartbeat_stale"]);
  }
});

test("latest completed failure alarms despite an earlier successful heartbeat", () => {
  assert.deepEqual(checkPayoutHeartbeat({ enabled: "true", state: "active", now,
    runs: [good, { ...good, created_at: new Date(now).toISOString(), conclusion: "failure" }] }), ["payout_job_failed"]);
});

test("alert opens once, does not repeat notifications, and closes on recovery", async () => {
  let issues = [];
  const writes = [];
  const api = async (method, path, body) => {
    if (method === "GET") return issues;
    writes.push({ method, path, body });
    if (method === "POST") issues = [{ ...body, number: 1 }];
  };
  assert.equal(await syncAlert(api, ["next_unavailable"], "enricopuntog-cpu"), "alert");
  await syncAlert(api, ["next_unavailable"], "enricopuntog-cpu");
  assert.equal(writes.length, 1);
  assert.ok(writes[0].body.body.includes("@enricopuntog-cpu"));
  await syncAlert(api, [], "enricopuntog-cpu");
  assert.equal(writes[1].body.state, "closed");
});

test("alert rejects arbitrary text and does not edit unrelated issues", async () => {
  await assert.rejects(syncAlert(() => {}, ["fake@example.test"], "owner"), /invalid_monitor_code/);
  const writes = [];
  await syncAlert(async (method, path, body) => {
    if (method === "GET") return [{ number: 2, title: "unrelated", body: "private" }];
    writes.push(body);
  }, [], "owner");
  assert.equal(writes.length, 0);
});

test("runner observes GitHub state without ever calling payouts or Supabase", async () => {
  const calls = [];
  const code = await run({ env: { GITHUB_TOKEN: "test-only", GITHUB_REPOSITORY: "owner/repo", PAYOUTS_SCHEDULER_ENABLED: "true" },
    say: () => {}, fetchImpl: async (url) => {
      calls.push(url);
      if (url.endsWith("/api/health")) return Response.json({ status: "ok", service: "vinea-next" });
      if (url.endsWith("/payouts-auto-release.yml")) return Response.json({ state: "active" });
      if (url.includes("/runs?")) return Response.json({ workflow_runs: [good] });
      if (url.includes("/issues?")) return Response.json([]);
      throw new Error("unexpected request");
    } });
  assert.equal(code, 0);
  assert.equal(calls.length, 4);
  assert.ok(calls.every((url) => !url.includes("supabase") && !url.includes("functions/v1")));
});
