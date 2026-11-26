import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { formatoInMl, inviaPropostaCatalogo, preparaProposta, proposteDisponibili } from "./proposta-catalogo";

const VINO = { produttore: "Cantina Aurelia", nome: "Rosso del Faro", annata: 2019, regione: "Liguria", denominazione: "IGT", tipo: "Rosso", formato: "0,75 L" };
const campi = { produttore: VINO.produttore, nome: VINO.nome, annata: "2019", regione: "Liguria", denominazione: "IGT" };

describe("WI-011 — proposta esplicita al catalogo", () => {
  it("manda solo i dati enologici ammessi; nulla di privato ha un posto", () => {
    const esito = preparaProposta({ ...VINO, note: "PRIVATA", prezzo: 99 } as never, campi);
    if (!esito.ok) throw new Error(esito.error);
    expect(esito.data.origine).toBe("cantina");
    expect(esito.data.dati).toEqual({ produttore: "Cantina Aurelia", nome: "Rosso del Faro", annata: 2019, regione: "Liguria", denominazione: "IGT", tipo: "Rosso", formato_ml: 750 });
  });

  it("un campo modificato rende la proposta una correzione", () => {
    const esito = preparaProposta(VINO, { ...campi, regione: "Toscana" });
    expect(esito.ok && esito.data.origine).toBe("correzione");
  });

  it("annata vuota resta assente (mai inventata); annata impossibile rifiutata", () => {
    const vuota = preparaProposta(VINO, { ...campi, annata: " " });
    expect(vuota.ok && "annata" in vuota.data.dati).toBe(false);
    expect(preparaProposta(VINO, { ...campi, annata: "19" }).ok).toBe(false);
    expect(preparaProposta(VINO, { ...campi, produttore: " " }).ok).toBe(false);
  });

  it("il formato si legge solo se riconosciuto", () => {
    expect([formatoInMl("0,75 L"), formatoInMl("1,5 L"), formatoInMl("375 ml"), formatoInMl("75cl"), formatoInMl("Magnum")]).toEqual([750, 1500, 375, 750, null]);
  });

  it("disponibilità fail-closed: solo true esatto", async () => {
    const con = (data: unknown, error: unknown = null) => ({ rpc: async () => ({ data, error }) }) as unknown as SupabaseClient;
    expect(await proposteDisponibili(con(true))).toBe(true);
    expect(await proposteDisponibili(con("true"))).toBe(false);
    expect(await proposteDisponibili(con(true, { code: "x" }))).toBe(false);
    expect(await proposteDisponibili(null)).toBe(false);
  });

  it("invia il consenso esplicito e non riporta messaggi interni", async () => {
    const chiamate: unknown[] = [];
    const client = { rpc: async (n: string, a: unknown) => (chiamate.push([n, a]), { data: "ricevuta", error: null }) } as unknown as SupabaseClient;
    const preparata = preparaProposta(VINO, campi);
    if (!preparata.ok) throw new Error("x");
    expect((await inviaPropostaCatalogo(client, "slug-x", preparata.data)).ok).toBe(true);
    expect(chiamate).toEqual([["catalogo_proponi", { p_origine: "cantina", p_dati: preparata.data.dati, p_consenso: true, p_wine_slug: "slug-x" }]]);
    const rotto = { rpc: async () => ({ data: null, error: { code: "XX000", message: "SEGRETO" } }) } as unknown as SupabaseClient;
    const esito = await inviaPropostaCatalogo(rotto, "slug-x", preparata.data);
    expect(esito.ok).toBe(false);
    expect(JSON.stringify(esito)).not.toContain("SEGRETO");
  });
});
