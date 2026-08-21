import { describe, expect, it } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import {
  BUCKET_AVATAR_PROFILI,
  CATALOGO_AVATAR,
  avatarSicuro,
  inizialiDa,
  percorsoAvatarPersonale,
  riferimentoAvatarSicuro,
} from "@/lib/profilo/avatar";

const progetto = join(import.meta.dir, "../../..");
const PROPRIETARIO = "11111111-1111-4111-8111-111111111111";
const ALTRO_UTENTE = "22222222-2222-4222-8222-222222222222";
const OGGETTO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const FOTO_PROPRIA = `${PROPRIETARIO}/${OGGETTO}.webp`;

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
  it("accetta una foto Vinea soltanto per il profilo proprietario", () => {
    expect(percorsoAvatarPersonale(FOTO_PROPRIA, PROPRIETARIO)).toBe(FOTO_PROPRIA);
    expect(riferimentoAvatarSicuro(FOTO_PROPRIA, PROPRIETARIO)).toBe(FOTO_PROPRIA);
    expect(avatarSicuro(FOTO_PROPRIA, PROPRIETARIO, "https://vinea.supabase.co/path")).toBe(
      `https://vinea.supabase.co/storage/v1/object/public/${BUCKET_AVATAR_PROFILI}/${FOTO_PROPRIA}`,
    );
  });

  it("rifiuta la foto dichiarata da un altro profilo", () => {
    expect(percorsoAvatarPersonale(FOTO_PROPRIA, ALTRO_UTENTE)).toBeNull();
    expect(riferimentoAvatarSicuro(FOTO_PROPRIA, ALTRO_UTENTE)).toBeNull();
    expect(avatarSicuro(FOTO_PROPRIA, ALTRO_UTENTE, "https://vinea.supabase.co")).toBeNull();
  });

  it("rifiuta URL esterni, traversal e percorsi personali non canonici", () => {
    for (const valore of [
      "https://i.pravatar.cc/240?img=68",
      "http://tracker.example.com/pixel.png",
      "//evil.example.com/a.svg",
      "/avatar/../../etc/passwd",
      "/avatar/inesistente.svg",
      "javascript:alert(1)",
      `${PROPRIETARIO}/../${OGGETTO}.webp`,
      `${PROPRIETARIO}/${OGGETTO}.png`,
      `${PROPRIETARIO}/${OGGETTO}.webp/altro`,
    ]) {
      expect(avatarSicuro(valore, PROPRIETARIO, "https://vinea.supabase.co")).toBeNull();
    }
  });

  it("non ricompone una foto con una base Storage non HTTP(S)", () => {
    expect(avatarSicuro(FOTO_PROPRIA, PROPRIETARIO, "javascript:alert(1)")).toBeNull();
    expect(avatarSicuro(FOTO_PROPRIA, PROPRIETARIO, "non-un-url")).toBeNull();
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
