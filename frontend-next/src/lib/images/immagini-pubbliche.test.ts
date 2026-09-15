import { describe, expect, it } from "bun:test";
import { immaginePubblicaOttimizzabile } from "./immagini-pubbliche";

const progetto = "https://vinea-test.supabase.co";
describe("confine delle immagini ottimizzabili", () => {
  it("accetta asset locali e foto pubbliche dello stesso progetto", () => {
    expect(immaginePubblicaOttimizzabile("/images/vinea-cellar.jpg")).toBeTrue();
    expect(immaginePubblicaOttimizzabile(`${progetto}/storage/v1/object/public/annunci/u/foto.jpg`, progetto)).toBeTrue();
  });
  it("esclude immagini private, firmate e bucket diversi", () => {
    for (const percorso of [
      "/storage/v1/object/sign/annunci/u/foto.jpg?token=segreto",
      "/storage/v1/object/authenticated/annunci/u/foto.jpg",
      "/storage/v1/object/public/qualifiche/u/foto.jpg",
      "/storage/v1/object/public/annunci/u/foto.jpg?token=segreto",
    ]) expect(immaginePubblicaOttimizzabile(progetto + percorso, progetto)).toBeFalse();
  });
  it("rifiuta origini ingannevoli, percorsi arbitrari e configurazioni mancanti", () => {
    for (const src of [
      "https://vinea-test.supabase.co.attacker.test/storage/v1/object/public/annunci/foto.jpg",
      "http://vinea-test.supabase.co/storage/v1/object/public/annunci/foto.jpg",
      "https://user:password@vinea-test.supabase.co/storage/v1/object/public/annunci/foto.jpg",
      "/images/../privato.jpg", "//attacker.test/foto.jpg", "blob:foto", "/api/foto",
    ]) expect(immaginePubblicaOttimizzabile(src, progetto)).toBeFalse();
    expect(immaginePubblicaOttimizzabile(progetto + "/storage/v1/object/public/annunci/foto.jpg")).toBeFalse();
  });
});
