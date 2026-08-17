import { describe, expect, it } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { CATALOGO_AVATAR, avatarSicuro, inizialiDa } from "@/lib/profilo/avatar";

const progetto = join(import.meta.dir, "../../..");

describe("catalogo degli avatar", () => {
  it("ogni voce corrisponde a un file davvero servito da noi", () => {
    expect(CATALOGO_AVATAR.length).toBeGreaterThan(0);
    for (const voce of CATALOGO_AVATAR) {
      expect(voce.percorso.startsWith("/avatar/")).toBe(true);
      expect(existsSync(join(progetto, "public", voce.percorso))).toBe(true);
    }
  });

  it("nessun percorso punta fuori dal sito", () => {
    for (const voce of CATALOGO_AVATAR) {
      expect(voce.percorso).not.toMatch(/^https?:/);
      expect(voce.percorso).not.toStartWith("//");
    }
  });

  it("gli identificativi non si ripetono", () => {
    const id = CATALOGO_AVATAR.map((voce) => voce.id);
    expect(new Set(id).size).toBe(id.length);
  });
});

describe("convalida dell'avatar memorizzato", () => {
  it("accetta un percorso del catalogo", () => {
    expect(avatarSicuro(CATALOGO_AVATAR[0]!.percorso)).toBe(CATALOGO_AVATAR[0]!.percorso);
  });

  it("rifiuta il vuoto, che e' il default della colonna", () => {
    expect(avatarSicuro("")).toBeNull();
    expect(avatarSicuro(null)).toBeNull();
    expect(avatarSicuro(undefined)).toBeNull();
  });

  /**
   * `profiles.avatar_url` e' scrivibile dal client: un utente puo' metterci
   * qualunque stringa. Se la si disegnasse cosi' com'e', aprire quel profilo
   * significherebbe fare una richiesta al dominio scelto da un estraneo.
   */
  it("rifiuta un URL esterno anche se sembra un avatar", () => {
    for (const valore of [
      "https://i.pravatar.cc/240?img=68",
      "http://tracker.example.com/pixel.png",
      "//evil.example.com/a.svg",
      "/avatar/../../etc/passwd",
      "/avatar/inesistente.svg",
      "javascript:alert(1)",
    ]) {
      expect(avatarSicuro(valore)).toBeNull();
    }
  });
});

describe("iniziali di riserva", () => {
  it("usa due parole quando ci sono", () => {
    expect(inizialiDa("elena rossi")).toBe("ER");
    expect(inizialiDa("elena_rossi")).toBe("ER");
    expect(inizialiDa("elena.rossi")).toBe("ER");
  });

  it("con una parola sola prende due lettere", () => {
    expect(inizialiDa("elena")).toBe("EL");
  });

  it("non inventa caratteri quando non c'e' nome", () => {
    expect(inizialiDa("")).toBe("?");
    expect(inizialiDa(null)).toBe("?");
    expect(inizialiDa("   ")).toBe("?");
  });
});
