// Banco di prova delle Edge Function AI: esegue la function VERA con `Deno`, `@supabase/supabase-js` e fornitore finti.
// Nessuna rete, nessuna chiave, nessuna spesa: l'unico `fetch` ammesso è quello verso il fornitore, intercettato.
// Il lato database reale (porta per identità, budget, privilegi) è provato dalle griglie su PostgreSQL.

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const radice = join(import.meta.dir, "../../../..");
const leggiRepo = (p: string) => readFileSync(join(radice, p), "utf8");
const slash = (p: string) => p.replace(/\\/g, "/");
const fn = (p: string) => slash(join(radice, "supabase/functions", p));

export type RispostaFornitore = { stato?: number; contenuto?: string };
export type ChiamataFornitore = { model: string; system: string; prompt: string; chiavi: string[] };

export type Scenario = {
  ambiente: Record<string, string | undefined>;
  porta: Record<string, unknown> | "errore";
  /** Esiti delle prenotazioni, uno per chiamata; l'ultimo si ripete. */
  prenotazioni: string[];
  fornitore: RispostaFornitore[];
  annunci: Record<string, unknown>[];
  rpc: { nome: string; args: Record<string, unknown> }[];
  chiamate: ChiamataFornitore[];
  log: string[];
};

export const PORTA_OK = {
  esito: "consentito",
  porta_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
  max_tentativi: 1,
  modello_riserva: null,
  max_input_caratteri: 20000,
};

export const nuovoScenario = (): Scenario => ({
  ambiente: {
    AI_ENABLED: "true",
    AI_ALLOWED_ORIGINS: "http://localhost:3000",
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-test",
    OPENAI_API_KEY: "sk-FINTA-per-i-test",
  },
  porta: { ...PORTA_OK },
  prenotazioni: ["consentito"],
  fornitore: [],
  annunci: [],
  rpc: [],
  chiamate: [],
  log: [],
});

type Handler = (request: Request) => Promise<Response>;

export async function caricaFunzione(nome: "ai-pairing" | "ai-catalogo", attuale: () => Scenario) {
  const dir = mkdtempSync(join(tmpdir(), `vinea-wi016-${nome}-`));
  const stub = join(dir, "supabase-stub.ts");
  writeFileSync(stub, "export const createClient = () => (globalThis as any).__fakeAi;\n");
  const gate = join(dir, "ai-gate.ts");
  writeFileSync(
    gate,
    leggiRepo("supabase/functions/_shared/ai-gate.ts")
      .replace('"@supabase/supabase-js"', JSON.stringify(slash(stub)))
      .replace('"./ai-cors.ts"', JSON.stringify(fn("_shared/ai-cors.ts")))
      .replace('"./ai-provider.ts"', JSON.stringify(fn("_shared/ai-provider.ts")))
      .replace('"./ai-sicurezza.ts"', JSON.stringify(fn("_shared/ai-sicurezza.ts"))),
  );
  const sorgente = leggiRepo(`supabase/functions/${nome}/index.ts`)
    .replace('"../_shared/ai-provider.ts"', JSON.stringify(fn("_shared/ai-provider.ts")))
    .replace('"../_shared/ai-sicurezza.ts"', JSON.stringify(fn("_shared/ai-sicurezza.ts")))
    .replace('"../_shared/ai-gate.ts"', JSON.stringify(slash(gate)));
  if (sorgente.includes('"../_shared/')) throw new Error("import relativi non riscritti");
  const copia = join(dir, "index.ts");
  writeFileSync(copia, sorgente);

  let handler: Handler | undefined;
  const globale = globalThis as unknown as { Deno?: unknown; __fakeAi?: unknown };
  const finto = {
    auth: { getUser: async () => ({ data: { user: { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" } }, error: null }) },
    from: (tabella: string) => {
      const api = {
        select: () => api,
        eq: () => api,
        order: () => api,
        limit: () => Promise.resolve({ data: tabella === "public_listings" ? attuale().annunci : [], error: null }),
        maybeSingle: () => Promise.resolve({ data: { stato_utente: "attivo" }, error: null }),
      };
      return api;
    },
    rpc: async (rpc: string, args: Record<string, unknown>) => {
      const s = attuale();
      s.rpc.push({ nome: rpc, args });
      if (rpc === "ai_porta_apri") {
        return s.porta === "errore" ? { data: null, error: { code: "PGRST202", message: "SEGRETO-DI-DB" } } : { data: s.porta, error: null };
      }
      if (rpc === "ai_budget_prenota") {
        const i = s.rpc.filter((r) => r.nome === "ai_budget_prenota").length - 1;
        const esito = s.prenotazioni[Math.min(i, s.prenotazioni.length - 1)];
        return { data: esito === "consentito" ? { esito, richiesta_id: `richiesta-${i + 1}` } : { esito }, error: null };
      }
      if (["rate_limit_consume", "ai_porta_chiudi", "ai_segnala", "ai_budget_esito", "ai_budget_consuntivo"].includes(rpc)) {
        return { data: null, error: null };
      }
      throw new Error(`RPC non prevista: ${rpc}`);
    },
  };

  const fetchFinto = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (!url.startsWith("https://api.openai.com/")) throw new Error("rete non consentita nei test");
    const s = attuale();
    const corpo = JSON.parse(String(init?.body ?? "{}")) as { model: string; messages: { role: string; content: string }[] };
    s.chiamate.push({
      model: corpo.model,
      system: corpo.messages.find((m) => m.role === "system")?.content ?? "",
      prompt: corpo.messages.find((m) => m.role === "user")?.content ?? "",
      chiavi: Object.keys(corpo).sort(),
    });
    const risposta = s.fornitore[Math.min(s.chiamate.length - 1, s.fornitore.length - 1)] ?? {};
    if ((risposta.stato ?? 200) !== 200) return new Response("boom", { status: risposta.stato });
    return new Response(
      JSON.stringify({ choices: [{ message: { content: risposta.contenuto ?? "{}" } }], usage: { prompt_tokens: 10, completion_tokens: 5 } }),
      { status: 200 },
    );
  }) as typeof fetch;

  const prima = { Deno: globale.Deno, fetch: globalThis.fetch };
  globale.__fakeAi = finto;
  globale.Deno = { env: { get: (n: string) => attuale().ambiente[n] }, serve: (h: Handler) => (handler = h) };
  await import(copia);
  globale.Deno = prima.Deno;

  return {
    async chiama(corpo: unknown, intestazioni: Record<string, string> = {}): Promise<Response> {
      const s = attuale();
      const salvati = { Deno: globale.Deno, fetch: globalThis.fetch, error: console.error, __fakeAi: globale.__fakeAi };
      globale.__fakeAi = finto;
      globale.Deno = { env: { get: (n: string) => s.ambiente[n] }, serve: () => {} };
      globalThis.fetch = fetchFinto;
      console.error = (...a: unknown[]) => void s.log.push(a.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" "));
      try {
        return await handler!(
          new Request(`https://edge.test/functions/v1/${nome}`, {
            method: "POST",
            headers: { origin: "http://localhost:3000", authorization: "Bearer token", "content-type": "application/json", ...intestazioni },
            body: typeof corpo === "string" ? corpo : JSON.stringify(corpo),
          }),
        );
      } finally {
        globale.Deno = salvati.Deno;
        globalThis.fetch = salvati.fetch;
        console.error = salvati.error;
        globale.__fakeAi = salvati.__fakeAi;
      }
    },
    chiudi: () => rmSync(dir, { recursive: true, force: true }),
  };
}

export const nomi = (s: Scenario) => s.rpc.map((r) => r.nome);
export const di = (s: Scenario, nome: string) => s.rpc.filter((r) => r.nome === nome).map((r) => r.args);
