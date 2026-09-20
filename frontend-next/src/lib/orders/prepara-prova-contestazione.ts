export const DIMENSIONE_MASSIMA_PROVA = 5 * 1024 * 1024;
export const LATO_MASSIMO_PROVA = 1600;
export const MIME_PROVA = "image/webp";
export const MIME_PROVA_INGRESSO = ["image/jpeg", "image/png", "image/webp"] as const;

type DecodedImage = { width: number; height: number; close?: () => void };
export type EvidenceImageDeps = {
  decode(file: File): Promise<DecodedImage>;
  encode(image: DecodedImage, width: number, height: number): Promise<Blob>;
};

const browserDeps: EvidenceImageDeps = {
  decode: (file) => createImageBitmap(file),
  encode: async (image, width, height) => {
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Canvas non disponibile.");
    context.drawImage(image as CanvasImageSource, 0, 0, width, height);
    return new Promise((resolve, reject) => {
      canvas.toBlob(
        (blob) => (blob ? resolve(blob) : reject(new Error("Codifica non riuscita."))),
        MIME_PROVA,
        0.86,
      );
    });
  },
};

export async function preparaProvaContestazione(
  file: File,
  deps: EvidenceImageDeps = browserDeps,
): Promise<File> {
  if (file.size === 0 || file.size > DIMENSIONE_MASSIMA_PROVA) {
    throw new Error("Ogni fotografia deve essere compresa entro 5 MB.");
  }
  if (!MIME_PROVA_INGRESSO.includes(file.type as (typeof MIME_PROVA_INGRESSO)[number])) {
    throw new Error("Scegli fotografie JPEG, PNG o WebP valide.");
  }

  let image: DecodedImage;
  try {
    image = await deps.decode(file);
  } catch {
    throw new Error("Scegli fotografie JPEG, PNG o WebP valide.");
  }

  try {
    if (image.width < 1 || image.height < 1) throw new Error("Immagine non valida.");
    const scale = Math.min(1, LATO_MASSIMO_PROVA / Math.max(image.width, image.height));
    const width = Math.max(1, Math.round(image.width * scale));
    const height = Math.max(1, Math.round(image.height * scale));
    const blob = await deps.encode(image, width, height);
    if (blob.size === 0 || blob.type !== MIME_PROVA) throw new Error("Codifica non riuscita.");
    // Il ridisegno e la ricodifica eliminano EXIF, GPS e metadati del file sorgente.
    return new File([blob], "prova.webp", { type: MIME_PROVA });
  } finally {
    image.close?.();
  }
}
