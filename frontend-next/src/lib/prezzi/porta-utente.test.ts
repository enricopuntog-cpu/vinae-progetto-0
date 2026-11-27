import { describe, expect, it } from "bun:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { leggiStimaUtente, stimaUtenteDisponibile } from "./porta-utente";

const ADESSO = new Date("2026-11-27T00:00:00Z");
const SOGGETTO = { vinoId: "v1", annata: 2019, formatoMl: 750, valuta: "eur" };

const client = (risposta: unknown, chiamate: unknown[] = []) =>
  ({
    rpc: async (nome: string, argomenti: unknown) => {
      chiamate.push([nome, argomenti]);
      if (risposta instanceof Error) throw risposta;
      return risposta as { data: unknown; error: unknown };
    },
  }) as unknown as SupabaseClient;

const riga = (i: number, tipo: "richiesto" | "realizzato", centesimi: number) => ({
  id: `o${i}`, tipo, centesimi, valuta: "eur", osservatoIl: "2026-10-01T00:00:00Z", fonte: "vinea_interno",
  vinoId: "v1", annata: 2019, formatoMl: 750, condizione: null,
});

describe("WI-016 — stima per scheda e Cantina, spenta per difetto", () => {
  it("disponibile solo con il booleano vero della porta: errore, forma inattesa o assenza di client la spengono", async () => {
    expect(await stimaUtenteDisponibile(client({ data: { abilitata: true }, error: null }))).toBe(true);
    for (const risposta of [
      { data: { abilitata: false }, error: null },
      { data: { abilitata: "true" }, error: null },
      { data: null, error: { code: "PGRST202" } },
      new Error("rete"),
    ]) {
      expect(await stimaUtenteDisponibile(client(risposta))).toBe(false);
    }
    expect(await stimaUtenteDisponibile(null)).toBe(false);
  });

  it("porta spenta: nessuna stima", async () => {
    expect(await leggiStimaUtente(client({ data: { abilitata: false }, error: null }), "slug", "0,75 L", ADESSO))
      .toEqual({ ok: true, data: { stato: "spenta" } });
  });

  it("solo le vendite concluse entrano nella stima; i prezzi richiesti si contano a parte", async () => {
    const chiamate: unknown[] = [];
    const osservazioni = [
      ...[100, 200, 300, 400, 500].map((c, i) => riga(i, "realizzato", c * 100)),
      ...[10, 11].map((i) => riga(i, "richiesto", 99_999_00)),
    ];
    const esito = await leggiStimaUtente(
      client({ data: { abilitata: true, soggetto: SOGGETTO, osservazioni }, error: null }, chiamate),
      "barolo-x", "0,75 L", ADESSO,
    );
    expect(chiamate).toEqual([["prezzi_vino_osservazioni", { p_wine_slug: "barolo-x", p_formato: "0,75 L" }]]);
    expect(esito.ok && esito.data.stato === "valutata" && esito.data.valutazione).toMatchObject({
      esito: "stima", medianaCents: 30_000, comparabili: 5, richiestiConsiderati: 2,
    });
  });

  it("sotto la soglia o senza soggetto la risposta è «dati insufficienti»: nessun prezzo inventato", async () => {
    for (const data of [
      { abilitata: true, soggetto: SOGGETTO, osservazioni: [riga(1, "realizzato", 5000), riga(2, "richiesto", 5000)] },
      { abilitata: true, soggetto: null, osservazioni: [] },
    ]) {
      const esito = await leggiStimaUtente(client({ data, error: null }), "x", "0,75 L", ADESSO);
      expect(esito.ok && esito.data.stato === "valutata" && esito.data.valutazione.esito).toBe("dati_insufficienti");
      expect(JSON.stringify(esito)).not.toContain("medianaCents");
    }
  });

  it("un errore della porta resta un errore, senza dettagli interni", async () => {
    const esito = await leggiStimaUtente(client({ data: null, error: { code: "XX000", message: "SEGRETO" } }), "x", "0,75 L", ADESSO);
    expect(esito).toEqual({ ok: false, error: "La stima non è disponibile in questo momento." });
  });
});
