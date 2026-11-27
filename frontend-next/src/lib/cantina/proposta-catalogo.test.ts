import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  formatoInMl,
  inviaPropostaCatalogo,
  leggiProposteMie,
  messaggioEsitoProposta,
  origineConsenso,
  preparaProposta,
  proposteDisponibili,
  proposteDisponibiliPerNuovoVino,
  ritiraProposta,
} from "./proposta-catalogo";

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

  it("WI-016: il consenso viaggia con la creazione; l'origine distingue manuale ed etichetta confermata", () => {
    expect(origineConsenso(false)).toBe("manuale");
    expect(origineConsenso(true)).toBe("ocr");
  });

  it("WI-016: ogni esito della porta ha un messaggio onesto; ricevuta e assente non aggiungono rumore", () => {
    expect(messaggioEsitoProposta("ricevuta")).toBeNull();
    expect(messaggioEsitoProposta(undefined)).toBeNull();
    expect(messaggioEsitoProposta("in_sospeso")).toContain("più tardi");
    expect(messaggioEsitoProposta("limite")).toContain("limite giornaliero");
    for (const esito of ["non_attiva", "non_valida", "non_registrata"] as const) {
      expect(messaggioEsitoProposta(esito)).toContain("La bottiglia è in Cantina");
    }
  });

  it("WI-016: le proprie proposte si leggono con elenco chiuso di stati e si ritirano dalla stessa porta (id negativo)", async () => {
    const chiamate: unknown[] = [];
    const client = {
      rpc: async (n: string, a: unknown) => {
        chiamate.push([n, a]);
        if (n === "catalogo_proposte_mie") {
          return {
            data: [
              { id: -4, produttore: "P", nome: "Sospesa", annata: null, stato: "in_attesa_di_invio", inviata_il: "2026-11-27T00:00:00Z" },
              { id: 9, produttore: "P", nome: "Aperta", annata: 2019, stato: "in_revisione", inviata_il: "2026-11-26T00:00:00Z" },
              { id: 7, produttore: "P", nome: "Chiusa", annata: 2018, stato: "accolta", inviata_il: "2026-11-25T00:00:00Z" },
              { id: "x", produttore: 1, nome: null },
            ],
            error: null,
          };
        }
        return { data: true, error: null };
      },
    } as unknown as SupabaseClient;
    const lette = await leggiProposteMie(client);
    if (!lette.ok) throw new Error(lette.error);
    expect(lette.data.map((p) => [p.id, p.stato, p.ritirabile])).toEqual([
      [-4, "in_attesa_di_invio", true],
      [9, "in_revisione", true],
      [7, "accolta", false],
    ]);
    expect((await ritiraProposta(client, -4)).ok).toBe(true);
    expect(chiamate.at(-1)).toEqual(["catalogo_proposta_ritira", { p_id: -4 }]);
  });

  it("WI-016: revoca non più possibile o errore: messaggio generico, nessun dettaglio interno", async () => {
    const gia = { rpc: async () => ({ data: false, error: null }) } as unknown as SupabaseClient;
    expect((await ritiraProposta(gia, 9)).ok).toBe(false);
    const rotto = { rpc: async () => ({ data: null, error: { code: "XX000", message: "SEGRETO" } }) } as unknown as SupabaseClient;
    expect(JSON.stringify(await leggiProposteMie(rotto))).not.toContain("SEGRETO");
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
