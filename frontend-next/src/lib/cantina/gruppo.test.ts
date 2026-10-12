import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  FORMATI,
  FORMATO_STANDARD,
  MAX_BOTTIGLIE_PER_AGGIUNTA,
  MAX_BOTTIGLIE_PER_ORDINE,
  chiaveCantina,
  chiaveGruppo,
  etichettaBottiglie,
  formatoValido,
  nuovaChiaveIdempotenza,
  quantitaDaTesto,
  riepilogoGruppo,
  unitaVendibiliDelGruppo,
} from "@/lib/cantina/gruppo";

const radice = join(import.meta.dir, "../../../..");
const migrazione = (nome: string) => readFileSync(join(radice, "supabase/migrations", nome), "utf8");

type B = Parameters<typeof unitaVendibiliDelGruppo>[0][number];
const bottiglia = (id: string, extra: Partial<B> = {}): B => ({
  bottleId: id,
  wineVintageId: "barolo-2019",
  stato: "chiusa",
  quantita: 1,
  saleStatus: "privata",
  ...extra,
});

describe("chiave del gruppo: vino + formato", () => {
  it("il formato standard tiene lo slug del vino, quindi nessuna chiave esistente cambia", () => {
    expect(chiaveGruppo("barolo-2019", FORMATO_STANDARD)).toBe("barolo-2019");
    expect(chiaveGruppo("barolo-2019", null)).toBe("barolo-2019");
    expect(chiaveGruppo("barolo-2019", "")).toBe("barolo-2019");
  });

  it("una Magnum dello stesso vino è un gruppo diverso", () => {
    expect(chiaveGruppo("barolo-2019", "1,5 L")).toBe("barolo-2019@1-5-l");
    expect(chiaveGruppo("barolo-2019", "1,5 L")).not.toBe(chiaveGruppo("barolo-2019", "0,75 L"));
    expect(chiaveGruppo("barolo-2019", "0,375 L")).not.toBe(chiaveGruppo("barolo-2019", "3 L"));
  });

  it("annate diverse sono vini diversi e quindi chiavi diverse", () => {
    expect(chiaveGruppo("barolo-2018", "0,75 L")).not.toBe(chiaveGruppo("barolo-2019", "0,75 L"));
  });

  it("chiaveCantina preferisce il gruppo, poi lo slug, poi l'id", () => {
    expect(chiaveCantina({ gruppoCantina: "x@1-5-l", wineSlug: "x", id: "annuncio" })).toBe("x@1-5-l");
    expect(chiaveCantina({ wineSlug: "x", id: "annuncio" })).toBe("x");
    expect(chiaveCantina({ id: "annuncio" })).toBe("annuncio");
  });
});

describe("formati", () => {
  it("l'elenco coincide con il CHECK del database", () => {
    const sql = migrazione("20261012090000_vp_c_inventario_unita_lotti.sql");
    const vincolo = sql.match(/bottle_units_formato_valido check \(\s*formato in \(([\s\S]*?)\)\s*\)/);
    expect(vincolo).not.toBeNull();
    const nelDatabase = [...(vincolo?.[1] ?? "").matchAll(/'([^']+)'/g)].map((m) => m[1]);
    expect(nelDatabase).toEqual([...FORMATI]);
  });

  it("formatoValido accetta solo l'elenco chiuso", () => {
    expect(formatoValido("1,5 L")).toBe(true);
    expect(formatoValido("1.5 L")).toBe(false);
    expect(formatoValido("Magnum")).toBe(false);
  });
});

describe("quantità da un campo di testo", () => {
  it("accetta solo interi fra 1 e il massimo", () => {
    expect(quantitaDaTesto("1", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBe(1);
    expect(quantitaDaTesto(" 12 ", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBe(12);
    expect(quantitaDaTesto("120", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBe(120);
    expect(quantitaDaTesto("121", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
    expect(quantitaDaTesto("0", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
    expect(quantitaDaTesto("-3", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
    expect(quantitaDaTesto("2.5", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
    expect(quantitaDaTesto("", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
    expect(quantitaDaTesto("1e2", MAX_BOTTIGLIE_PER_AGGIUNTA)).toBeNull();
  });

  it("i limiti sono quelli delle porte", () => {
    const parte1 = migrazione("20261012090000_vp_c_inventario_unita_lotti.sql");
    const parte2 = migrazione("20261012150000_vp_c_annunci_allocazioni_ordini.sql");
    expect(parte1).toContain(`quantita between 1 and ${MAX_BOTTIGLIE_PER_AGGIUNTA}`);
    expect(parte2).toContain(`check (quantita between 1 and ${MAX_BOTTIGLIE_PER_ORDINE})`);
  });
});

describe("bottiglie vendibili di un gruppo", () => {
  it("esclude aperte, impegnate, vendute e di altri gruppi; la bottiglia di partenza viene prima", () => {
    const tutte = [
      bottiglia("a", { storageLocationId: "m-r0c0" }),
      bottiglia("b"),
      bottiglia("c", { stato: "aperta", quantita: 0 }),
      bottiglia("d", { saleStatus: "in_vendita", annuncioBloccante: { id: "l", stato: "attivo" } }),
      bottiglia("e", { saleStatus: "venduta" }),
      bottiglia("f", { wineVintageId: "barolo-2019@1-5-l" }),
      bottiglia("g", { saleStatus: "cantina_pubblica" }),
    ];
    expect(unitaVendibiliDelGruppo(tutte, "barolo-2019").map((b) => b.bottleId)).toEqual(["b", "g", "a"]);
    expect(unitaVendibiliDelGruppo(tutte, "barolo-2019", "a").map((b) => b.bottleId)).toEqual(["a", "b", "g"]);
    expect(unitaVendibiliDelGruppo(tutte, "barolo-2019@1-5-l").map((b) => b.bottleId)).toEqual(["f"]);
  });
});

describe("riepilogo di un gruppo", () => {
  it("conta righe: 12 possedute, una aperta, 5 in vendita, 2 vendute", () => {
    const righe: B[] = [];
    for (let i = 0; i < 12; i += 1) righe.push(bottiglia(`u${i}`));
    righe[0] = bottiglia("u0", { stato: "aperta", quantita: 0 });
    for (let i = 1; i <= 5; i += 1) righe[i] = bottiglia(`u${i}`, { saleStatus: "in_vendita" });
    righe.push(bottiglia("s1", { saleStatus: "venduta" }), bottiglia("s2", { saleStatus: "venduta" }));
    righe.push(bottiglia("altro", { wineVintageId: "nebbiolo-2020" }));
    expect(riepilogoGruppo(righe, "barolo-2019")).toEqual({
      totale: 14,
      chiuse: 13,
      aperte: 1,
      consumate: 0,
      inVendita: 5,
      vendute: 2,
    });
  });

  it("etichetta singolare e plurale", () => {
    expect(etichettaBottiglie(1)).toBe("1 bottiglia");
    expect(etichettaBottiglie(12)).toBe("12 bottiglie");
  });
});

describe("chiave d'idempotenza", () => {
  it("rispetta il formato delle porte ed è nuova a ogni gesto", () => {
    const a = nuovaChiaveIdempotenza("cantina");
    const b = nuovaChiaveIdempotenza("cantina");
    expect(a).toMatch(/^[A-Za-z0-9._:-]{8,128}$/);
    expect(a).not.toBe(b);
    expect(nuovaChiaveIdempotenza("con spazi e àccenti")).toMatch(/^[A-Za-z0-9._:-]{8,128}$/);
  });
});
