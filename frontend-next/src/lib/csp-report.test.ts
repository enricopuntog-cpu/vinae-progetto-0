import { describe, expect, it } from "bun:test";
import { createCspReportHandler, sanitizeCspReports } from "./csp-report";

const body = { "csp-report": {
  "effective-directive": "img-src",
  "blocked-uri": "https://pijnmcllmfgjmgsvtcej.supabase.co/storage/private?token=secret",
  "document-uri": "https://vineawineclub.com/auth/callback?code=secret",
  "script-sample": "private content",
} };
const request = (value = JSON.stringify(body), headers: Record<string, string> = {}) =>
  new Request("https://vineawineclub.com/api/security/csp-report", {
    method: "POST", headers: { "content-type": "application/csp-report", ...headers }, body: value,
  });

describe("CSP report collection", () => {
  it("discards all URLs, tokens, snippets and arbitrary fields", () => {
    expect(sanitizeCspReports(body)).toEqual([{ directive: "img-src", resource: "supabase" }]);
  });
  it("accepts the Reporting API shape", () => {
    expect(sanitizeCspReports([{ type: "csp-violation", body: {
      effectiveDirective: "script-src-elem", blockedURL: "inline",
    } }])).toEqual([{ directive: "script-src-elem", resource: "inline" }]);
  });
  it("does not log attacker text as a directive or resource", () => {
    expect(sanitizeCspReports({ "csp-report": { "effective-directive": "secret" } })).toEqual([]);
    expect(sanitizeCspReports({ "csp-report": {
      "effective-directive": "connect-src", "blocked-uri": "https://secret.evil.test/private",
    } })).toEqual([{ directive: "connect-src", resource: "external" }]);
  });
  it("limits a batch to ten entries", () => {
    expect(sanitizeCspReports(Array(100).fill(body))).toHaveLength(10);
  });
  it("ignores malformed and unrelated reports", () => {
    for (const value of [null, "text", [], {}, { type: "deprecation", body: {} }]) {
      expect(sanitizeCspReports(value)).toEqual([]);
    }
  });
  it("collects without using a session and disables caching", async () => {
    const logged: unknown[] = [];
    const response = await createCspReportHandler((r) => logged.push(r))(request());
    expect(response.status).toBe(204);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(JSON.stringify(logged)).not.toContain("secret");
  });
  it("rejects cross-site browser reports", async () => {
    expect((await createCspReportHandler(() => { throw new Error("not called"); })(
      request(undefined, { "sec-fetch-site": "cross-site" }),
    )).status).toBe(403);
  });
  it("rejects a simple HTML form submission", async () => {
    expect((await createCspReportHandler(() => {})(request("x=y", {
      "content-type": "application/x-www-form-urlencoded",
    }))).status).toBe(415);
  });
  it("rejects oversized bodies even without Content-Length", async () => {
    expect((await createCspReportHandler(() => {})(request(" ".repeat(16_385)))).status).toBe(400);
  });
  it("rejects invalid JSON without logging it", async () => {
    const logged: unknown[] = [];
    expect((await createCspReportHandler((r) => logged.push(r))(request("{secret"))).status).toBe(400);
    expect(logged).toEqual([]);
  });
  it("bounds log submissions per instance and reopens the next minute", async () => {
    let time = 100_000;
    const handler = createCspReportHandler(() => {}, () => time);
    for (let i = 0; i < 30; i++) expect((await handler(request())).status).toBe(204);
    expect((await handler(request())).status).toBe(429);
    time += 60_000;
    expect((await handler(request())).status).toBe(204);
  });
});
