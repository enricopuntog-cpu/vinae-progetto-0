import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { leggiSelezioniCatalogo, scegliSchedaCatalogo } from "./selezione-catalogo";

const UUID = "11000000-0000-4000-8000-000000000001";

const cliente = (righe: unknown[], salvato: unknown = null) => {
  const colonne: string[] = [];
  const client = {
    rpc: async (nome: string) =>
      nome === "catalogo_canonico_disponibile" ? { data: true, error: null } : { data: salvato, error: null },
    from: () => ({
      select: async (c: string) => {
        colonne.push(c);
        return { data: righe, error: null };
      },
    }),
  };
  return { client: client as unknown as SupabaseClient, colonne };
};

describe("selezione personale della scheda del catalogo (WI-008/WI-011)", () => {
  it("legge sia i codici LWIN sia gli UUID delle schede senza LWIN, scartando i valori malformati", async () => {
    const { client, colonne } = cliente([
      { lwin7: "1010001", catalog_wine_id: null, wines: { slug: "con-lwin" } },
      { lwin7: null, catalog_wine_id: UUID, wines: [{ slug: "nativa" }] },
      { lwin7: null, catalog_wine_id: "../x", wines: { slug: "rotta" } },
    ]);
    const esito = await leggiSelezioniCatalogo(client);
    expect(esito.scelte).toEqual({ "con-lwin": "1010001", nativa: UUID });
    expect(colonne).toEqual(["lwin7, catalog_wine_id, wines!inner(slug)"]);
  });

  it("accetta come esito salvato un UUID e rifiuta un valore che non è un codice", async () => {
    expect(await scegliSchedaCatalogo(cliente([], UUID).client, "v", UUID)).toEqual({ ok: true, data: UUID });
    expect((await scegliSchedaCatalogo(cliente([], "boh").client, "v", UUID)).ok).toBe(false);
  });
});
