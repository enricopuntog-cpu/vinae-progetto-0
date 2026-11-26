import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { chiamaCatalogoAdmin, messaggioCatalogo, serviziCatalogoAdmin } from "./catalogo-admin";

const registra = (data: unknown = {}, error: unknown = null) => {
  const chiamate: [string, unknown][] = [];
  const client = {
    rpc: async (nome: string, args?: unknown) => {
      chiamate.push([nome, args]);
      return { data, error };
    },
  } as unknown as SupabaseClient;
  return { client, chiamate };
};

describe("WI-012 — pannello del catalogo: solo le porte di amministrazione", () => {
  it("legge con paginazione lato server, mai scaricando il catalogo", async () => {
    const { client, chiamate } = registra({ totale: 0, oltre: false, righe: [] });
    await serviziCatalogoAdmin(client).vini({ testo: "barolo", stato: "", origine: "manual", pagina: 3 });
    expect(chiamate).toEqual([
      ["catalogo_admin_vini", { p_testo: "barolo", p_stato: null, p_origine: "manual", p_pagina: 3, p_per_pagina: 20 }],
    ]);
  });

  it("ogni scrittura passa dalle due porte con nota e senza accesso diretto alle tabelle", async () => {
    const { client, chiamate } = registra({ id: "x" });
    const s = serviziCatalogoAdmin(client);
    await s.azione("pubblica", { wine_id: "w" }, "motivo");
    await s.decidiProposta(7, "rifiuta", {}, "non è un vino");
    expect(chiamate).toEqual([
      ["catalogo_admin_azione", { p_azione: "pubblica", p_dati: { wine_id: "w" }, p_nota: "motivo" }],
      ["catalogo_admin_proposta_decidi", { p_id: 7, p_decisione: "rifiuta", p_dati: {}, p_nota: "non è un vino" }],
    ]);
  });

  it("il modulo non usa `from(` né lo schema catalog", () => {
    const sorgente = readFileSync(join(import.meta.dir, "catalogo-admin.ts"), "utf8");
    expect(sorgente).not.toMatch(/\.from\(|\.schema\(/);
  });

  it("i messaggi delle porte arrivano all'amministratore; gli errori interni no", () => {
    expect(messaggioCatalogo({ code: "P0002", message: "catalog: vino nativo inesistente" })).toBe("Vino nativo inesistente");
    expect(messaggioCatalogo({ code: "23505", message: "Esiste già un vino canonico con lo stesso nome." })).toBe(
      "Esiste già un vino canonico con lo stesso nome.",
    );
    expect(messaggioCatalogo({ code: "23505", message: 'duplicate key value violates unique constraint "wines_lwin7_key"' })).toBe(
      "Esiste già un elemento uguale.",
    );
    expect(messaggioCatalogo({ code: "23514", message: 'violates check constraint "x"' })).toBe("I dati non rispettano le regole del catalogo.");
    expect(messaggioCatalogo({ code: "42501", message: "x" })).toBe("Operazione non autorizzata.");
    expect(messaggioCatalogo({ code: "XX000", message: "SEGRETO" })).toBe("Operazione non riuscita. Riprova.");
  });

  it("WI-015: aggiornamento LWIN in sola lettura e omonimia dichiarata con motivo, tramite le porte", async () => {
    const { client, chiamate } = registra({});
    const s = serviziCatalogoAdmin(client);
    await s.aggiornamento();
    await s.distingui("w", "1234567", "produttori omonimi");
    expect(chiamate).toEqual([
      ["catalogo_admin_aggiornamento", undefined],
      ["catalogo_admin_distingui_lwin", { p_wine_id: "w", p_lwin7: "1234567", p_nota: "produttori omonimi" }],
    ]);
    expect(messaggioCatalogo({ code: "55P03", message: "catalog: una promozione è in corso: riprova al termine del lotto" })).toBe(
      "Una promozione è in corso: riprova al termine del lotto",
    );
  });

  it("un'eccezione di rete diventa un errore leggibile", async () => {
    const client = { rpc: async () => Promise.reject(new Error("SEGRETO")) } as unknown as SupabaseClient;
    const esito = await chiamaCatalogoAdmin(client, "catalogo_admin_riepilogo");
    expect(esito).toEqual({ ok: false, error: "Operazione non riuscita. Riprova." });
  });
});
