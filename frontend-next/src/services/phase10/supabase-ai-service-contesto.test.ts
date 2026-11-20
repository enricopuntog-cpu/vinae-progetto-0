import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";

/**
 * WI-004 — l'adapter della chat manda il contesto richiesto e nient'altro.
 * Nessuna rete: `fetch` è sostituito e registra corpo e intestazioni.
 */

const ANNUNCIO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

const client = (token: string | null) =>
  ({ auth: { getSession: async () => ({ data: { session: token ? { access_token: token } : null } }) } }) as unknown as SupabaseClient;

const realFetch = globalThis.fetch;
const urlPrima = process.env.NEXT_PUBLIC_SUPABASE_URL;
let chiamate: { url: string; init: RequestInit }[];
let risposta: () => Response;

const sse = (...eventi: Record<string, unknown>[]) =>
  new Response(eventi.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""), { status: 200 });

beforeEach(() => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
  chiamate = [];
  risposta = () => sse({ delta: "ok" }, { done: true });
  globalThis.fetch = (async (url: unknown, init?: RequestInit) => {
    chiamate.push({ url: String(url), init: init ?? {} });
    return risposta();
  }) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
  if (urlPrima === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
  else process.env.NEXT_PUBLIC_SUPABASE_URL = urlPrima;
});

const corpo = () => JSON.parse(String(chiamate[0].init.body)) as Record<string, unknown>;

describe("sommelierChat con contesto", () => {
  it("senza contesto il corpo è identico a prima: session_id e message, nessun'altra chiave", async () => {
    await createSupabaseAiService(client("tok")).sommelierChat({ sessionId: "s-1234", messaggio: "ciao" }, () => {});
    expect(corpo()).toEqual({ session_id: "s-1234", message: "ciao" });
    expect("contesto" in corpo()).toBe(false);
  });

  it("vino: manda tipo e annuncio_id (nome del contratto del server), niente altro", async () => {
    await createSupabaseAiService(client("tok")).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "vino", annuncioId: ANNUNCIO } },
      () => {},
    );
    expect(corpo().contesto).toEqual({ tipo: "vino", annuncio_id: ANNUNCIO });
  });

  it("Cantina: manda il solo consenso esplicito; il proprietario non è mai nel corpo", async () => {
    await createSupabaseAiService(client("tok")).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "cantina", consenso: true } },
      () => {},
    );
    expect(corpo().contesto).toEqual({ tipo: "cantina", consenso: true });
    expect(JSON.stringify(corpo())).not.toMatch(/owner|user_id|userId/i);
  });

  it("l'identità viaggia solo nel bearer del token della sessione", async () => {
    await createSupabaseAiService(client("tok-di-A")).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "cantina", consenso: true } },
      () => {},
    );
    expect(new Headers(chiamate[0].init.headers).get("authorization")).toBe("Bearer tok-di-A");
  });

  it("senza sessione non parte nessuna richiesta, contesto o no", async () => {
    const esito = await createSupabaseAiService(client(null)).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "cantina", consenso: true } },
      () => {},
    );
    expect(esito.ok).toBe(false);
    expect(chiamate).toHaveLength(0);
  });

  it("il rifiuto del server (consenso richiesto) arriva come messaggio, non come risposta del Sommelier", async () => {
    risposta = () =>
      new Response(JSON.stringify({ error: "Serve il tuo consenso esplicito per usare la tua Cantina.", code: "consenso_richiesto" }), { status: 400 });
    const esito = await createSupabaseAiService(client("tok")).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "cantina", consenso: true } },
      () => {},
    );
    expect(esito.ok).toBe(false);
    if (!esito.ok) expect(esito.error).toContain("consenso");
  });

  it("lo streaming è invariato con il contesto: i frammenti arrivano in ordine e la chiusura è riconosciuta", async () => {
    risposta = () => sse({ delta: "Ciao " }, { delta: "mondo" }, { done: true });
    const visti: string[] = [];
    const esito = await createSupabaseAiService(client("tok")).sommelierChat(
      { sessionId: "s-1234", messaggio: "ciao", contesto: { tipo: "vino", annuncioId: ANNUNCIO } },
      (d) => visti.push(d),
    );
    expect(visti).toEqual(["Ciao ", "mondo"]);
    expect(esito).toEqual({ ok: true, data: { testo: "Ciao mondo", troncato: false } });
  });
});
