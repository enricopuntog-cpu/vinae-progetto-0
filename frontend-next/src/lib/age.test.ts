import { describe, expect, it } from "bun:test";
import { isMaggiorenne } from "@/lib/age";

const oggi = new Date("2026-08-26T12:00:00Z");

describe("isMaggiorenne", () => {
  it("rifiuta una data di nascita assente o non interpretabile", () => {
    expect(isMaggiorenne("", oggi)).toBeFalse();
    expect(isMaggiorenne("non-una-data", oggi)).toBeFalse();
  });

  it("rifiuta una data futura", () => {
    expect(isMaggiorenne("2027-08-26", oggi)).toBeFalse();
  });

  it("rifiuta chi non ha ancora compiuto 18 anni", () => {
    expect(isMaggiorenne("2008-08-27", oggi)).toBeFalse();
  });

  it("accetta chi compie esattamente 18 anni oggi", () => {
    expect(isMaggiorenne("2008-08-26", oggi)).toBeTrue();
  });
});
