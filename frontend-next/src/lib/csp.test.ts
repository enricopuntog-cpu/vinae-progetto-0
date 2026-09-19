import { describe, expect, it } from "bun:test";
import { NextRequest } from "next/server";
import { buildPageCsp } from "./csp";
import { proxy } from "../proxy";

const nonce = Buffer.from("a-test-nonce-with-enough-entropy").toString("base64");
describe("CSP enforcing delle pagine", () => {
  it("blocca script inline non autorizzati, handler HTML ed eval in produzione", () => {
    const csp = buildPageCsp(nonce);
    const script = csp.split("; ").find(x => x.startsWith("script-src "))!;
    expect(script).toContain(`'nonce-${nonce}'`);
    expect(script).toContain("'strict-dynamic'");
    expect(script).not.toContain("'unsafe-inline'");
    expect(script).not.toContain("'unsafe-eval'");
    expect(csp).toContain("script-src-attr 'none'");
  });
  it("ammette REST, Storage e Realtime della sola origine configurata", () => {
    const csp = buildPageCsp(nonce, "https://preview.supabase.co");
    expect(csp).toContain("connect-src 'self' https://preview.supabase.co wss://preview.supabase.co;");
    expect(csp).not.toContain("pijnmcllmfgjmgsvtcej");
    expect(csp).not.toContain("pravatar");
  });
  it("rifiuta nonce e configurazioni che potrebbero iniettare direttive", () => {
    for (const bad of ["' unsafe-inline", "\r\nx: y", "short"]) expect(() => buildPageCsp(bad)).toThrow();
    for (const url of ["https://x.test/path", "https://user:pass@x.test", "http://remote.test", "https://x.test/?q=1", "javascript:alert(1)"]) {
      expect(() => buildPageCsp(nonce, url)).toThrow();
    }
  });
  it("supporta backend locale esplicito e limita eval al solo sviluppo", () => {
    expect(buildPageCsp(nonce, "http://127.0.0.1:54321", true)).toContain("ws://127.0.0.1:54321");
    expect(buildPageCsp(nonce, undefined, true)).toContain("'unsafe-eval'");
  });
  it("sostituisce header client, cambia nonce a ogni richiesta e vieta cache HTML", () => {
    const request = new NextRequest("https://vineawineclub.com/account", {
      headers: { "x-nonce": "attacker", "Content-Security-Policy": "script-src * 'unsafe-inline'" },
    });
    const first = proxy(request);
    const second = proxy(request);
    const policy = first.headers.get("Content-Security-Policy")!;
    expect(policy).not.toContain("attacker");
    expect(policy).not.toEqual(second.headers.get("Content-Security-Policy"));
    expect(first.headers.get("x-middleware-request-content-security-policy")).toBe(policy);
    expect(policy).toContain(first.headers.get("x-middleware-request-x-nonce")!);
    expect(first.headers.get("Cache-Control")).toBe("private, no-store");
    expect(first.headers.get("Netlify-CDN-Cache-Control")).toBe("no-store");
  });
});
