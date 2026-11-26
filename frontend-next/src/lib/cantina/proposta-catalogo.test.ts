import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { formatoInMl, inviaPropostaCatalogo, inviaPropostaNuovoVino,
  preparaPropostaNuovoVino,
  preparaProposta, proposteDisponibili, proposteDisponibiliPerNuovoVino } from "./proposta-catalogo";

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

  it("WI-015: nel wizard la disponibilità si chiede solo con una sessione e per un vino nuovo (anon non ha la porta: sarebbe un 401)", async () => {
    let chiamate = 0;
    const client = { rpc: async () => (chiamate++, { data: true, error: null }) } as unknown as SupabaseClient;
    expect(await proposteDisponibiliPerNuovoVino(client, { autenticato: false, daCantina: false })).toBe(false);
    expect(await proposteDisponibiliPerNuovoVino(client, { autenticato: true, daCantina: true })).toBe(false);
    expect(chiamate).toBe(0);
    expect(await proposteDisponibiliPerNuovoVino(client, { autenticato: true, daCantina: false })).toBe(true);
    expect(chiamate).toBe(1);
  });

  it("WI-015: inserimento manuale ed etichetta confermata hanno origine propria e soli dati enologici", () => {
    const campi = { produttore: " Cantina  Mare ", nome: "Vermentino", annata: "2021", regione: "Liguria", tipo: "Bianco", formato: "0,75 L" };
    expect(preparaPropostaNuovoVino(campi, false)).toEqual({
      ok: true,
      data: { origine: "manuale", dati: { produttore: "Cantina Mare", nome: "Vermentino", annata: 2021, regione: "Liguria", tipo: "Bianco", formato_ml: 750 } },
    });
    const daEtichetta = preparaPropostaNuovoVino({ ...campi, annata: "", formato: "magnum strano" }, true);
    expect(daEtichetta).toEqual({ ok: true, data: { origine: "ocr", dati: { produttore: "Cantina Mare", nome: "Vermentino", regione: "Liguria", tipo: "Bianco" } } });
    expect(preparaPropostaNuovoVino({ ...campi, nome: " " }, false).ok).toBe(false);
  });

  it("WI-015: ripete solo gli errori di rete, al massimo tre volte; una risposta del database non si ripete", async () => {
    const proposta = { origine: "manuale" as const, dati: { produttore: "P", nome: "N" } };
    const attese: number[] = [];
    const pausa = async (ms: number) => void attese.push(ms);
    let n = 0;
    const rete = { rpc: async () => { n++; if (n < 3) throw new TypeError("fetch failed"); return { data: "ricevuta", error: null }; } } as unknown as SupabaseClient;
    expect(await inviaPropostaNuovoVino(rete, proposta, { pausa })).toEqual({ ok: true, data: undefined });
    expect([n, attese]).toEqual([3, [1000, 3000]]);
    let m = 0;
    const rifiuto = { rpc: async () => { m++; return { data: null, error: { code: "P0001", message: "SEGRETO" } }; } } as unknown as SupabaseClient;
    const esito = await inviaPropostaNuovoVino(rifiuto, proposta, { pausa });
    expect([m, esito.ok, JSON.stringify(esito).includes("SEGRETO")]).toEqual([1, false, false]);
    let k = 0;
    const sempreGiu = { rpc: async () => { k++; throw new TypeError("fetch failed"); } } as unknown as SupabaseClient;
    expect((await inviaPropostaNuovoVino(sempreGiu, proposta, { pausa })).ok).toBe(false);
    expect(k).toBe(3);
  });

  it("WI-015: «non_valida» è un esito della porta (che consuma la quota), non un successo né un errore interno", async () => {
    const client = { rpc: async () => ({ data: "non_valida", error: null }) } as unknown as SupabaseClient;
    const preparata = preparaProposta(VINO, campi);
    if (!preparata.ok) throw new Error("x");
    expect(await inviaPropostaCatalogo(client, "slug-x", preparata.data)).toEqual({
      ok: false,
      error: "Controlla i dati inseriti: qualcosa non è un'informazione sul vino.",
    });
  });
});
