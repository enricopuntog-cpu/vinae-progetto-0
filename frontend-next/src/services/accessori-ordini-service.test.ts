import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ordineValido } from "@/lib/accessori-ordini/ordine.fixture";
import { creaAccessoriOrdiniService } from "./accessori-ordini-service";

const ID = "12f50000-0000-4000-8000-0000000000a1";
const PREV = "12f50000-0000-4000-8000-0000000000b1";

type Chiamata = { nome: string; args: Record<string, unknown> };

function finto(risposta: { data?: unknown; error?: { code?: string; hint?: string } | null }) {
  const chiamate: Chiamata[] = [];
  const client = {
    rpc: async (nome: string, args: Record<string, unknown>) => {
      chiamate.push({ nome, args });
      return { data: risposta.data ?? null, error: risposta.error ?? null };
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
}

describe("creaAccessoriOrdiniService", () => {
  it("crea passando SOLO preventivo e chiave: nessun importo, quantità o venditore", async () => {
    const { client, chiamate } = finto({ data: ordineValido() });
    const r = await creaAccessoriOrdiniService(client).crea({ preventivoId: PREV, chiave: "acc-chiave-0001" });
    expect(r.ok).toBe(true);
    expect(chiamate).toEqual([
      { nome: "accessori_checkout_crea", args: { p_preventivo_id: PREV, p_chiave: "acc-chiave-0001" } },
    ]);
  });

  it("non chiama il database con identificativi o chiavi malformati", async () => {
    const { client, chiamate } = finto({ data: ordineValido() });
    const s = creaAccessoriOrdiniService(client);
    expect((await s.crea({ preventivoId: "x", chiave: "acc-chiave-0001" })).ok).toBe(false);
    expect((await s.crea({ preventivoId: PREV, chiave: "corta" })).ok).toBe(false);
    expect((await s.annulla("x")).ok).toBe(false);
    expect((await s.leggi("x")).ok).toBe(false);
    expect((await s.disponibilita("x")).ok).toBe(false);
    expect((await s.elenca("tutti" as "acquisti")).ok).toBe(false);
    expect(chiamate).toHaveLength(0);
  });

  it("una risposta incoerente non diventa un ordine", async () => {
    const { client } = finto({ data: ordineValido({ totaleAcquirenteCents: 1 }) });
    const r = await creaAccessoriOrdiniService(client).annulla(ID);
    expect(r.ok).toBe(false);
  });

  it("traduce i rifiuti del database in parole, senza dettagli tecnici", async () => {
    const casi: Array<[string, string]> = [
      ["quantita_non_disponibile", "pezzi"],
      ["prenotazione_aperta", "prenotazione"],
      ["checkout_non_attivo", "non sono ancora attive"],
      ["preventivo_scaduto", "scaduto"],
    ];
    for (const [hint, atteso] of casi) {
      const { client } = finto({ error: { code: "P0001", hint } });
      const r = await creaAccessoriOrdiniService(client).crea({ preventivoId: PREV, chiave: "acc-chiave-0001" });
      expect(r.ok).toBe(false);
      if (!r.ok) {
        expect(r.error).toContain(atteso);
        expect(r.error).not.toMatch(/accessori_|private|unique|constraint/i);
      }
    }
    const { client } = finto({ error: { code: "XX000", hint: "interno" } });
    const r = await creaAccessoriOrdiniService(client).leggi(ID);
    expect(r.ok === false && r.error).toBe("Operazione non riuscita. Riprova fra qualche istante.");
  });

  it("senza client non c'è nessuna prenotazione", async () => {
    const r = await creaAccessoriOrdiniService(null).crea({ preventivoId: PREV, chiave: "acc-chiave-0001" });
    expect(r.ok).toBe(false);
  });

  it("elenca con il ruolo e un tetto, disponibilità con il solo annuncio", async () => {
    const e = finto({ data: [ordineValido()] });
    const r = await creaAccessoriOrdiniService(e.client).elenca("acquisti");
    expect(r.ok && r.data.length).toBe(1);
    expect(e.chiamate[0]).toEqual({ nome: "accessori_ordini_elenca", args: { p_ruolo: "acquisti", p_limite: 30 } });
    const d = finto({ data: { disponibili: 2, prenotabile: true, motivo: null } });
    await creaAccessoriOrdiniService(d.client).disponibilita(ID);
    expect(d.chiamate[0]).toEqual({ nome: "accessori_disponibilita", args: { p_annuncio: ID } });
  });
});
