import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import nextConfig from "../../next.config";
import { BASE_SECURITY_POLICY, CONTENT_SECURITY_POLICY, SECURITY_HEADERS } from "./security-headers";

// Le regole `[[headers]]` di netlify.toml coprono i file statici; headers() di
// Next.js copre le pagine. Le due copie devono restare identiche.
function headerNetlify(percorso: string): Map<string, string> {
  const toml = readFileSync(join(import.meta.dir, "..", "..", "..", "netlify.toml"), "utf8");
  const valori = new Map<string, string>();
  let corrente: string | null = null;
  for (const riga of toml.split(/\r?\n/)) {
    if (/^\[\[headers\]\]/.test(riga)) corrente = null;
    const regola = /^\s+for = "(.*)"\s*$/.exec(riga);
    if (regola) corrente = regola[1];
    const m = /^\s+([A-Za-z-]+) = "(.*)"\s*$/.exec(riga);
    if (m && !regola && corrente === percorso) valori.set(m[1], m[2].replace(/\\"/g, '"'));
  }
  return valori;
}

describe("header di sicurezza", () => {
  it("netlify.toml e next.config portano gli stessi valori", () => {
    const netlify = headerNetlify("/*");
    for (const { key, value } of SECURITY_HEADERS) {
      expect(netlify.get(key)).toBe(value);
    }
  });

  it("solo gli asset del marchio sono incorporabili da altre origini", () => {
    // Il logo delle email si carica dentro il client di posta, non dal sito.
    const marchio = headerNetlify("/brand/*");
    expect(marchio.get("Cross-Origin-Resource-Policy")).toBe("cross-origin");
    expect(marchio.get("Cache-Control")).toStartWith("public");
    expect([...marchio.keys()].sort()).toEqual(["Cache-Control", "Cross-Origin-Resource-Policy"]);
    expect(headerNetlify("/*").get("Cross-Origin-Resource-Policy")).toBe("same-origin");
  });

  it("headers() di Next.js applica l'elenco a ogni percorso", async () => {
    const regole = await nextConfig.headers!();
    const tutte = regole.find((r) => r.source === "/:path*");
    expect(tutte).toBeDefined();
    for (const header of SECURITY_HEADERS) {
      expect(tutte!.headers).toContainEqual(header);
    }
  });

  it("raccoglie la policy completa e applica la protezione di base", () => {
    const chiavi = SECURITY_HEADERS.map((h) => h.key);
    expect(chiavi).toContain("Content-Security-Policy-Report-Only");
    expect(SECURITY_HEADERS).toContainEqual({ key: "Content-Security-Policy", value: BASE_SECURITY_POLICY });
    expect(BASE_SECURITY_POLICY).toContain("object-src 'none'");
    expect(CONTENT_SECURITY_POLICY).toContain("report-uri /api/security/csp-report");
  });

  it("connect-src ammette Supabase sia in https sia in wss", () => {
    const connect = CONTENT_SECURITY_POLICY.split("; ").find((d) => d.startsWith("connect-src"));
    expect(connect).toContain("https://pijnmcllmfgjmgsvtcej.supabase.co");
    expect(connect).toContain("wss://pijnmcllmfgjmgsvtcej.supabase.co");
  });

  it("img-src non invia visitatori a servizi avatar dimostrativi", () => {
    const images = CONTENT_SECURITY_POLICY.split("; ").find((d) => d.startsWith("img-src"));
    expect(images).toContain("https://pijnmcllmfgjmgsvtcej.supabase.co");
    expect(images).not.toContain("pravatar");
  });

  it("il sito non è incorniciabile e non dichiara il framework", () => {
    expect(SECURITY_HEADERS).toContainEqual({ key: "X-Frame-Options", value: "DENY" });
    expect(CONTENT_SECURITY_POLICY).toContain("frame-ancestors 'none'");
    expect(nextConfig.poweredByHeader).toBe(false);
  });
});
