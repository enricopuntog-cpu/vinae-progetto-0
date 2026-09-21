import { describe, expect, it } from "bun:test";
import {
  LATO_MASSIMO_PROVA,
  MIME_PROVA,
  preparaProvaContestazione,
  type EvidenceImageDeps,
} from "./prepara-prova-contestazione";

describe("preparaProvaContestazione", () => {
  it("ridimensiona e ricodifica in WebP senza copiare i byte originali", async () => {
    let dimensions: number[] = [];
    const deps: EvidenceImageDeps = {
      decode: async () => ({ width: 3200, height: 1600 }),
      encode: async (_image, width, height) => {
        dimensions = [width, height];
        return new Blob(["ricodificata"], { type: MIME_PROVA });
      },
    };
    const result = await preparaProvaContestazione(
      new File(["originale-con-exif"], "foto.jpg", { type: "image/jpeg" }),
      deps,
    );
    expect(dimensions).toEqual([LATO_MASSIMO_PROVA, 800]);
    expect(result.type).toBe(MIME_PROVA);
    expect(await result.text()).toBe("ricodificata");
  });

  it("rifiuta formati non immagine", async () => {
    await expect(
      preparaProvaContestazione(new File(["x"], "prova.svg", { type: "image/svg+xml" })),
    ).rejects.toThrow("JPEG, PNG o WebP");
  });
});
