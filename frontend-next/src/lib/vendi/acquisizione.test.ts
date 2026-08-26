import { describe, expect, it } from "bun:test";
import {
  acquisizioneDaCampi,
  dataAcquistoPerRpc,
  prezzoAcquistoCents,
} from "@/lib/vendi/acquisizione";

describe("acquisizione manuale — prezzo", () => {
  it("mantiene un campo vuoto sconosciuto e distingue lo zero noto", () => {
    expect(prezzoAcquistoCents("")).toBeNull();
    expect(prezzoAcquistoCents("   ")).toBeNull();
    expect(prezzoAcquistoCents("0")).toBe(0);
  });

  it("converte gli euro in centesimi interi senza perdere i decimali", () => {
    expect(prezzoAcquistoCents("24.99")).toBe(2499);
    expect(prezzoAcquistoCents("24.995")).toBe(2500);
  });
});

describe("acquisizione manuale — data", () => {
  it("mantiene un campo vuoto sconosciuto", () => {
    expect(dataAcquistoPerRpc("")).toBeNull();
  });

  it("trasporta la data scelta come mezzanotte locale in un timestamp ISO", () => {
    const valore = dataAcquistoPerRpc("2024-02-03");
    expect(valore).not.toBeNull();

    const data = new Date(valore!);
    expect(Number.isNaN(data.getTime())).toBe(false);
    expect(data.getFullYear()).toBe(2024);
    expect(data.getMonth()).toBe(1);
    expect(data.getDate()).toBe(3);
    expect(data.getHours()).toBe(0);
    expect(data.getMinutes()).toBe(0);
  });

  it("compone i due fatti senza trasformare le assenze in zero", () => {
    expect(acquisizioneDaCampi({ prezzoEuro: "", data: "" })).toEqual({
      acquisitionCostCents: null,
      acquiredAt: null,
    });
    expect(acquisizioneDaCampi({ prezzoEuro: "0", data: "2024-02-03" })).toMatchObject({
      acquisitionCostCents: 0,
    });
  });
});
