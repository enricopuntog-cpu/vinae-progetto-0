import { afterEach, describe, expect, it, vi } from "bun:test";
import { apiResponse, apiUrl, configureAccessTokenProvider, jsonRequest } from "./api-client";

const originalFetch = globalThis.fetch;

afterEach(() => {
  configureAccessTokenProvider(undefined);
  globalThis.fetch = originalFetch;
  vi.restoreAllMocks();
});

describe("apiUrl", () => {
  it("mantiene i percorsi same-origin quando non è configurato un backend esterno", () => {
    expect(apiUrl("/api/health")).toBe("/api/health");
  });

  it("rifiuta percorsi ambigui", () => {
    expect(() => apiUrl("api/health")).toThrow('deve iniziare con "/"');
  });
});

describe("apiResponse", () => {
  it("inietta il bearer token dal provider configurato", async () => {
    let capturedInit: RequestInit | undefined;
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      capturedInit = init;
      return new Response("{}", { status: 200 });
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;
    configureAccessTokenProvider(async () => "access-token");

    await apiResponse("/api/private");

    const headers = new Headers(capturedInit?.headers);
    expect(headers.get("Authorization")).toBe("Bearer access-token");
    expect(capturedInit?.credentials).toBe("omit");
  });

  it("preserva header applicativi e serializza JSON", () => {
    const init = jsonRequest(
      { quantity: 1 },
      { method: "POST", headers: { "Idempotency-Key": "checkout-1" } },
    );
    const headers = new Headers(init.headers);

    expect(headers.get("Content-Type")).toBe("application/json");
    expect(headers.get("Idempotency-Key")).toBe("checkout-1");
    expect(init.body).toBe('{"quantity":1}');
  });
});
