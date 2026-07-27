import { describe, expect, test } from "bun:test";
import { formatEUR, formatInteger } from "./format";

describe("format deterministico SSR", () => {
  test("formatta migliaia e valuta senza dipendere da Intl", () => {
    expect(formatInteger(1180)).toBe("1.180");
    expect(formatEUR(1180)).toBe("1.180\u00a0€");
  });

  test("gestisce arrotondamento e segno", () => {
    expect(formatInteger(1250.6)).toBe("1.251");
    expect(formatEUR(-12)).toBe("-12\u00a0€");
  });
});
