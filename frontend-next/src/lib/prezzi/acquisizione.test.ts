import { describe, expect, it } from "bun:test";
import { accettaOsservazione, raccogliOsservazioni, type FonteOsservazioni } from "./acquisizione";
import { valutaPrezzo } from "./valutazione";

// Fixture di fantasia: nessuna transazione, ordine o persona reale.
const grezza = (id: string, o: Record<string, unknown> = {}) => ({
  id, tipo: "realizzato", centesimi: 5000, valuta: "eur", osservatoIl: "2026-09-01T00:00:00Z", fonte: "fixture",
  vinoId: "vino-prova", annata: 2018, formatoMl: 750, condizione: null, ...o,
});
type FonteContata = FonteOsservazioni & { letture: number };
const fonte = (righe: unknown[], o: Partial<FonteOsservazioni> = {}): FonteContata => {
  const f: FonteContata = { nome: "fixture", autorizzata: true, finalita: "prova automatica", letture: 0, leggi: async (): Promise<unknown[]> => (f.letture++, righe), ...o };
  return f;
};

describe("WI-015 — acquisizione delle osservazioni di prezzo (contratto, spenta per difetto)", () => {
  it("spenta: non legge nessuna fonte", async () => {
    const f = fonte([grezza("1")]);
    for (const attiva of [undefined, false, "true" as unknown as boolean]) {
      expect(await raccogliOsservazioni([f], { attiva })).toEqual({ esito: "disattivata" });
    }
    expect(f.letture).toBe(0);
  });

  it("accesa: una fonte non autorizzata o senza finalità dichiarata non viene letta", async () => {
    const no = fonte([grezza("1")], { autorizzata: false });
    const senza = fonte([grezza("2")], { finalita: " " });
    expect(await raccogliOsservazioni([no, senza], { attiva: true })).toEqual({ esito: "raccolte", osservazioni: [], scartate: 0, fontiEscluse: 2 });
    expect(no.letture + senza.letture).toBe(0);
  });

  it("l'elenco dei campi è chiuso: dati di persone o di ordini fanno scartare la riga, non si ripuliscono", () => {
    expect(accettaOsservazione(grezza("1"), "fixture")).not.toBeNull();
    for (const extra of [{ acquirente: "x" }, { venditoreId: "y" }, { email: "a@b.test" }, { ordineId: "z" }, { indirizzo: "via" }]) {
      expect(accettaOsservazione({ ...grezza("1"), ...extra }, "fixture")).toBeNull();
    }
    for (const rotto of [{ tipo: "stimato" }, { centesimi: 10.5 }, { centesimi: 0 }, { valuta: "EURO" }, { fonte: "altra" }, { id: "" }, { annata: "2018" }]) {
      expect(accettaOsservazione(grezza("1", rotto), "fixture")).toBeNull();
    }
  });

  it("dal contratto alla valutazione: i richiesti restano separati e sotto soglia non c'è stima", async () => {
    const righe = [...[1, 2, 3, 4].map((n) => grezza(`r${n}`)), grezza("q1", { tipo: "richiesto", centesimi: 99000 }), { ...grezza("x"), compratore: "no" }];
    const r = await raccogliOsservazioni([fonte(righe)], { attiva: true });
    if (r.esito !== "raccolte") throw new Error("attesa raccolta");
    expect([r.osservazioni.length, r.scartate]).toEqual([5, 1]);
    const v = valutaPrezzo({ vinoId: "vino-prova", annata: 2018, formatoMl: 750, valuta: "eur" }, r.osservazioni, new Date("2026-11-26T00:00:00Z"));
    expect([v.esito, v.comparabili, v.richiestiConsiderati]).toEqual(["dati_insufficienti", 4, 1]);
  });
});
