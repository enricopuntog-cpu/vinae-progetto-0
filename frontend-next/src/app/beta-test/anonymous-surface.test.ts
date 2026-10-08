import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import {
  PERCORSI_MARKET_VALIDATION_ANONIMI,
  superficieMarketValidationAnonima,
} from "@/lib/market-validation/superficie-anonima";

/**
 * Il Beta Test è una superficie pubblica e isolata: chi non ha mai usato Vinea
 * deve arrivare da /beta-test a GRAZIE senza account, login o sessione Supabase
 * Auth. Bug riprodotto l'8 ottobre 2026 in produzione: un qualunque cookie di
 * sessione Supabase (anche scaduto o di un account con profilo incompleto)
 * faceva rimandare /beta-test a /completa-profilo dall'AgeGate globale, e
 * senza sessione la landing restava coperta da «Verifica dell'accesso…» finché
 * il client Auth non rispondeva. L'identità del tester è solo codice Vxxx +
 * capability anonima.
 */

const progetto = resolve(import.meta.dir, "../../..");
const leggi = (percorso: string) => readFileSync(join(progetto, percorso), "utf8");
const senzaCommenti = (sorgente: string) =>
  sorgente.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

const sorgentiBeta = () => {
  const cartella = join(progetto, "src/app/beta-test");
  const file = [
    "page.tsx",
    "page-client.tsx",
    "actions.ts",
    "use-market-validation-tracker.ts",
    ...readdirSync(join(cartella, "_components")).map((nome) => `_components/${nome}`),
  ];
  return file.map((nome) => ({ nome, codice: senzaCommenti(leggi(`src/app/beta-test/${nome}`)) }));
};

describe("superficie anonima della Market Validation", () => {
  it("vale su /beta-test e sulle sue sottorotte, non su rotte simili o admin", () => {
    expect(PERCORSI_MARKET_VALIDATION_ANONIMI).toEqual(["/beta-test"]);
    expect(superficieMarketValidationAnonima("/beta-test")).toBe(true);
    expect(superficieMarketValidationAnonima("/beta-test/qualcosa")).toBe(true);
    for (const pathname of ["/admin/beta-validation", "/beta-testing", "/beta", "/", "/cantina", "/account"]) {
      expect(superficieMarketValidationAnonima(pathname)).toBe(false);
    }
    expect(superficieMarketValidationAnonima(null)).toBe(false);
  });

  it("l'AgeGate globale non copre né reindirizza /beta-test (A, B)", () => {
    const gate = senzaCommenti(leggi("src/components/vinea/AgeGate.tsx"));
    expect(gate).toInclude("superficieMarketValidationAnonima(pathname)");
    // L'esenzione entra in `consentito`, che chiude sia il redirect a
    // /completa-profilo sia l'overlay di attesa e quello d'errore.
    expect(gate).toMatch(/const consentito =\s*percorsoConsentito\(pathname\) \|\| superficieMarketValidationAnonima\(pathname\);/);
    expect(gate).toInclude("if (authLoading || !authUser || consentito || authStatoEta !== \"da_completare\") return;");
    expect(gate.indexOf("if (consentito) return null;")).toBeLessThan(gate.indexOf("if (authLoading) {"));
  });

  it("la route e le porte non leggono identità Auth e non mandano al login (C, Q)", () => {
    for (const { nome, codice } of sorgentiBeta()) {
      expect({ nome, auth: /auth\.getUser|auth\.getSession|useVinea|authUser|redirect\(|router\.|useRouter/.test(codice) }).toEqual({ nome, auth: false });
      expect({ nome, login: /\/accedi|\/registrati|\/completa-profilo|\/account|\/cantina|\/community|\/messaggi|\/vendi|\/checkout/.test(codice) }).toEqual({ nome, login: false });
    }
  });

  it("ogni porta server MV usa il client anonimo senza cookie, mai la sessione Vinea (C, D, E, K, L)", () => {
    const actions = senzaCommenti(leggi("src/app/beta-test/actions.ts"));
    expect(actions).not.toInclude("getSupabaseServerClient");
    expect(actions).not.toInclude("@/lib/supabase/server");
    for (const nome of [
      "startQuestionnaire",
      "readQuestionnaire",
      "saveQuestionnaireAnswer",
      "finishQuestionnairePre",
      "finishQuestionnairePost",
      "startMarketValidationSession",
      "recordMarketValidationEvent",
    ]) {
      const inizio = actions.indexOf(`export async function ${nome}(`);
      expect(inizio).toBeGreaterThan(0);
      const corpo = actions.slice(inizio, actions.indexOf("\n}\n", inizio));
      expect({ nome, anonimo: corpo.includes("getSupabaseAnonServerClient()") }).toEqual({ nome, anonimo: true });
    }
    const client = senzaCommenti(leggi("src/lib/supabase/anon-server.ts"));
    expect(client).not.toMatch(/cookies|next\/headers|@supabase\/ssr/);
    expect(client).toInclude("persistSession: false");
    expect(client).toInclude("autoRefreshToken: false");
    expect(client).toInclude("NEXT_PUBLIC_SUPABASE_ANON_KEY");
    expect(client).not.toMatch(/SERVICE_ROLE/);
  });

  it("il client anonimo non porta mai un JWT utente nelle richieste", async () => {
    const { getSupabaseAnonServerClient } = await import("@/lib/supabase/anon-server");
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const chiave = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://progetto.supabase.test";
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "chiave-anon-di-prova";
    const fetchOriginale = globalThis.fetch;
    const autorizzazioni: Array<string | null> = [];
    globalThis.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
      autorizzazioni.push(new Headers(init?.headers).get("Authorization"));
      return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
    }) as typeof fetch;
    try {
      const client = getSupabaseAnonServerClient();
      expect(client).not.toBeNull();
      await client!.rpc("beta_validation_qv2_start", { p_capability: "x" });
      expect(autorizzazioni).toEqual(["Bearer chiave-anon-di-prova"]);
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "";
      expect(getSupabaseAnonServerClient()).toBeNull();
    } finally {
      globalThis.fetch = fetchOriginale;
      if (url === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL; else process.env.NEXT_PUBLIC_SUPABASE_URL = url;
      if (chiave === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY; else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = chiave;
    }
  });

  it("l'unico link verso Vinea dopo GRAZIE apre la Home pubblica in una nuova scheda", () => {
    const hrefs = sorgentiBeta().flatMap(({ nome, codice }) =>
      [...codice.matchAll(/href=\{?"([^"]+)"/g)].map((match) => `${nome}:${match[1]}`),
    );
    expect(hrefs).toEqual(["_components/ValidationComplete.tsx:/"]);
    expect(leggi("src/app/beta-test/_components/ValidationComplete.tsx")).toInclude('target="_blank"');
  });

  it("l'admin resta fuori dalla superficie anonima e richiede login + ruolo (P)", () => {
    const admin = leggi("src/app/admin/beta-validation/page.tsx");
    expect(admin).toMatch(/\/accedi/);
    expect(superficieMarketValidationAnonima("/admin/beta-validation")).toBe(false);
  });
});
