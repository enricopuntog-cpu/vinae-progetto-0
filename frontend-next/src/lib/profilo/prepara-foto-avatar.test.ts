import { describe, expect, it } from "bun:test";
import {
  DIMENSIONE_MASSIMA_FOTO_AVATAR,
  LATO_FOTO_AVATAR,
  MIME_FOTO_AVATAR,
  QUALITA_FOTO_AVATAR,
  preparaFotoAvatar,
  type DipendenzePreparazioneFoto,
} from "@/lib/profilo/prepara-foto-avatar";

const fileSorgente = (tipo = "image/jpeg", dimensione = 3) =>
  new File([new Uint8Array(dimensione)], "sorgente.jpg", { type: tipo });

const doppio = (opzioni?: {
  width?: number;
  height?: number;
  erroreDecodifica?: boolean;
  blob?: Blob;
}) => {
  let chiusa = false;
  let codifica: Parameters<DipendenzePreparazioneFoto["codifica"]>[1] | null = null;
  const dipendenze: DipendenzePreparazioneFoto = {
    async decodifica() {
      if (opzioni?.erroreDecodifica) throw new Error("contenuto non decodificabile");
      return {
        width: opzioni?.width ?? 1200,
        height: opzioni?.height ?? 800,
        close: () => {
          chiusa = true;
        },
      };
    },
    async codifica(_immagine, ricevute) {
      codifica = ricevute;
      return opzioni?.blob ?? new Blob(["pixel ricodificati"], { type: MIME_FOTO_AVATAR });
    },
  };

  return {
    dipendenze,
    codificaRicevuta: () => codifica,
    immagineChiusa: () => chiusa,
  };
};

describe("preparazione della foto profilo", () => {
  it("decodifica, ritaglia al centro e ricodifica un WebP quadrato", async () => {
    const prova = doppio({ width: 1200, height: 800 });
    const risultato = await preparaFotoAvatar(fileSorgente(), prova.dipendenze);

    expect(risultato.name).toBe("avatar.webp");
    expect(risultato.type).toBe(MIME_FOTO_AVATAR);
    expect(prova.codificaRicevuta()).toEqual({
      lato: LATO_FOTO_AVATAR,
      mime: MIME_FOTO_AVATAR,
      qualita: QUALITA_FOTO_AVATAR,
      sorgente: { x: 200, y: 0, lato: 800 },
    });
    expect(prova.immagineChiusa()).toBe(true);
  });

  it("rifiuta prima della decodifica un ingresso oltre 5 MB", async () => {
    let decodificata = false;
    const dipendenze: DipendenzePreparazioneFoto = {
      async decodifica() {
        decodificata = true;
        return { width: 1, height: 1 };
      },
      async codifica() {
        return new Blob(["x"], { type: MIME_FOTO_AVATAR });
      },
    };

    await expect(
      preparaFotoAvatar(
        fileSorgente("image/jpeg", DIMENSIONE_MASSIMA_FOTO_AVATAR + 1),
        dipendenze,
      ),
    ).rejects.toThrow("La foto supera il limite di 5 MB.");
    expect(decodificata).toBe(false);
  });

  it("rifiuta tipo dichiarato non gestito e contenuto non decodificabile", async () => {
    const nonImmagine = doppio();
    await expect(
      preparaFotoAvatar(fileSorgente("image/gif"), nonImmagine.dipendenze),
    ).rejects.toThrow("Scegli una foto JPEG, PNG o WebP valida.");

    const corrotta = doppio({ erroreDecodifica: true });
    await expect(preparaFotoAvatar(fileSorgente(), corrotta.dipendenze)).rejects.toThrow(
      "Scegli una foto JPEG, PNG o WebP valida.",
    );
  });

  it("rifiuta dimensioni invalide e una codifica che non produce WebP", async () => {
    const dimensioniInvalide = doppio({ width: 0, height: 800 });
    await expect(
      preparaFotoAvatar(fileSorgente(), dimensioniInvalide.dipendenze),
    ).rejects.toThrow("Scegli una foto JPEG, PNG o WebP valida.");
    expect(dimensioniInvalide.immagineChiusa()).toBe(true);

    const formatoErrato = doppio({ blob: new Blob(["x"], { type: "image/png" }) });
    await expect(preparaFotoAvatar(fileSorgente(), formatoErrato.dipendenze)).rejects.toThrow(
      "Non è stato possibile preparare la foto.",
    );
    expect(formatoErrato.immagineChiusa()).toBe(true);
  });
});
