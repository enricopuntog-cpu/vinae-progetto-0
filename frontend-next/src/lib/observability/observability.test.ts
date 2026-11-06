import { describe, expect, it, spyOn } from "bun:test";
import { createClientReporter } from "./client";
import { createTechnicalEventHandler } from "./handler";
import { onRequestError } from "../../instrumentation";
import { GET } from "../../app/api/health/route";

const req = (body = "client_error", headers: Record<string, string> = {}) =>
  new Request("https://vinea.test/api/technical-events", { method: "POST", body,
    headers: { "Content-Type": "text/plain", ...headers } });

describe("OBS-01 privacy and actual logging", () => {
  it("records a synthetic error as a fixed code without inspecting error/request data", () => {
    const log = spyOn(console, "error").mockImplementation(() => {});
    try {
      onRequestError(new Error("fake@example.test token=fake-secret"), {
        path: "/accedi?token=fake-secret", method: "GET", headers: { cookie: "session=fake" },
      }, { routeType: "route" } as Parameters<typeof onRequestError>[2]);
      expect(log.mock.calls).toEqual([["[VINEA_OBS]", '{"event":"server_error","kind":"route"}']]);
    } finally { log.mockRestore(); }
  });

  it("records every permitted client event and discards all untrusted contents", async () => {
    const events: string[] = [];
    const handler = createTechnicalEventHandler((event) => events.push(event));
    for (const event of ["client_error", "client_rejection", "client_boundary"]) {
      expect((await handler(req(event))).status).toBe(204);
    }
    for (const bad of ["", "fake@example.test", '{"event":"client_error"}', "client_error\ntoken=fake"]) {
      expect((await handler(req(bad))).status).toBe(400);
    }
    expect(events).toEqual(["client_error", "client_rejection", "client_boundary"]);
  });

  it("rejects cross-origin reports and wrong media types without logging", async () => {
    const events: string[] = [];
    const handler = createTechnicalEventHandler((event) => events.push(event));
    expect((await handler(req("client_error", { origin: "https://evil.test" }))).status).toBe(403);
    expect((await handler(req("client_error", { "sec-fetch-site": "cross-site" }))).status).toBe(403);
    expect((await handler(req("client_error", { "Content-Type": "application/json" }))).status).toBe(415);
    expect(events).toEqual([]);
  });

  it("bounds streamed bodies even with a false Content-Length", async () => {
    const handler = createTechnicalEventHandler(() => { throw new Error("must not log"); });
    expect((await handler(req("x".repeat(33), { "Content-Length": "1" }))).status).toBe(413);
    expect((await handler(req("client_error", { "Content-Length": "10000" }))).status).toBe(413);
  });

  it("accepts the actual host when Next normalizes its internal URL", async () => {
    const events: string[] = [];
    const handler = createTechnicalEventHandler((event) => events.push(event));
    const request = new Request("http://localhost:3000/api/technical-events", {
      method: "POST", body: "client_error", headers: { Host: "127.0.0.1:3000",
        Origin: "http://127.0.0.1:3000", "Content-Type": "text/plain" },
    });
    expect((await handler(request)).status).toBe(204);
    expect((await handler(req("client_error", { origin: "null" }))).status).toBe(403);
    expect(events).toEqual(["client_error"]);
  });

  it("caps volume per warm instance and resumes after a minute", async () => {
    let time = 100_000;
    let count = 0;
    const handler = createTechnicalEventHandler(() => count++, () => time);
    for (let i = 0; i < 30; i++) expect((await handler(req())).status).toBe(204);
    expect((await handler(req())).status).toBe(429);
    expect(count).toBe(30);
    time += 60_000;
    expect((await handler(req())).status).toBe(204);
  });

  it("client sends only fixed codes without cookies/referrer and suppresses duplicates", async () => {
    const sent: RequestInit[] = [];
    let time = 100_000;
    const send = createClientReporter((async (url, options) => {
      expect(url).toBe("/api/technical-events");
      sent.push(options!);
      return new Response(null, { status: 204 });
    }) as typeof fetch, () => time);
    send("client_error"); send("client_error"); send("client_boundary");
    expect(sent.length).toBe(2);
    expect(sent[0].body).toBe("client_error");
    expect(sent[0].credentials).toBe("omit");
    expect(sent[0].referrerPolicy).toBe("no-referrer");
    time += 60_000;
    send("client_error");
    expect(sent.length).toBe(3);
  });

  it("monitor transport failure cannot throw or cause a reporting loop", async () => {
    const report = createClientReporter((() => { throw new Error("offline"); }) as unknown as typeof fetch);
    expect(() => report("client_error")).not.toThrow();
    const rejected = createClientReporter((async () => { throw new Error("offline"); }) as unknown as typeof fetch);
    expect(() => rejected("client_rejection")).not.toThrow();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });

  it("liveness is dynamic, uncached and exposes no configuration", async () => {
    const response = GET();
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.json()).toEqual({ status: "ok", service: "vinea-next" });
  });
});
