import { describe, expect, it } from "bun:test";
import { eUuidValido, fotoDirettaAmmessa } from "./foto-riusabile";

const SUPABASE = "https://progetto.supabase.co";

describe("fotoDirettaAmmessa", () => {
  it("ammette le illustrazioni nostre e i file del nostro Storage", () => {
    expect(fotoDirettaAmmessa("/images/vinea-cellar.jpg", SUPABASE)).toBe(true);
    expect(fotoDirettaAmmessa(`${SUPABASE}/storage/v1/object/public/a/b.webp`, SUPABASE)).toBe(true);
  });

  it("rifiuta ogni altro indirizzo, anche quelli che sembrano relativi", () => {
    for (const origine of [
      "https://evil.example/x.jpg",
      "http://progetto.supabase.co/x.jpg",
      "https://progetto.supabase.co.evil.example/x.jpg",
      "//evil.example/x.jpg",
      "/\\evil.example/x.jpg",
      "/images//evil.example/x.jpg",
      "/images/../api/x",
      "/api/public/x",
      "javascript:alert(1)",
    ]) {
      expect(fotoDirettaAmmessa(origine, SUPABASE)).toBe(false);
    }
  });

  it("senza URL di Supabase nessun indirizzo assoluto passa", () => {
    expect(fotoDirettaAmmessa(`${SUPABASE}/x.webp`, undefined)).toBe(false);
  });
});

describe("eUuidValido", () => {
  it("accetta solo un UUID", () => {
    expect(eUuidValido("7f3c2a10-1b2c-4d3e-8f90-0a1b2c3d4e5f")).toBe(true);
    for (const v of ["", "1", "7f3c2a10-1b2c-4d3e-8f90-0a1b2c3d4e5f,x", "x' or 1=1"]) expect(eUuidValido(v)).toBe(false);
  });
});
