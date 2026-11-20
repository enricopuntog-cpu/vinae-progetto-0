// WI-002 — validazione e preparazione della fotografia dell'etichetta.
//
// La fotografia di riconoscimento è temporanea: vive in memoria nel browser,
// non viene caricata né pubblicata (vedi `pipeline.ts`). Qui si decide solo se
// è un'immagine che vale la pena di leggere e la si riduce a una dimensione
// che l'OCR gestisce senza consumare la memoria di un telefono.

export const TIPI_IMMAGINE_AMMESSI = ["image/jpeg", "image/png", "image/webp"] as const;
/** Tetto sul file scelto: una foto da fotocamera moderna sta sotto. */
export const MAX_BYTE_IMMAGINE = 10 * 1024 * 1024;
/** Lato massimo dell'immagine passata all'OCR. */
export const LATO_MAX_OCR = 1600;
/** Oltre questo numero di pixel non si prova nemmeno a decodificare. */
export const MAX_PIXEL_IMMAGINE = 64_000_000;

export type CodiceErroreImmagine =
  | "file_vuoto"
  | "tipo_non_supportato"
  | "troppo_grande"
  | "illeggibile";

export type EsitoValidazione =
  | { ok: true }
  | { ok: false; codice: CodiceErroreImmagine; messaggio: string };

export const MESSAGGI_IMMAGINE: Record<CodiceErroreImmagine, string> = {
  file_vuoto: "Il file è vuoto. Scegli un'altra fotografia.",
  tipo_non_supportato: "Formato non supportato. Usa una fotografia JPEG, PNG o WebP.",
  troppo_grande: "La fotografia è troppo grande (massimo 10 MB). Riducila o scattane un'altra.",
  illeggibile: "Non riesco ad aprire questa immagine. Prova con un'altra fotografia.",
};

export class ImmagineNonUtilizzabile extends Error {
  constructor(readonly codice: CodiceErroreImmagine) {
    super(MESSAGGI_IMMAGINE[codice]);
    this.name = "ImmagineNonUtilizzabile";
  }
}

export function validaFileImmagine(file: { type: string; size: number }): EsitoValidazione {
  if (file.size <= 0) {
    return { ok: false, codice: "file_vuoto", messaggio: MESSAGGI_IMMAGINE.file_vuoto };
  }
  if (!(TIPI_IMMAGINE_AMMESSI as readonly string[]).includes(file.type)) {
    return {
      ok: false,
      codice: "tipo_non_supportato",
      messaggio: MESSAGGI_IMMAGINE.tipo_non_supportato,
    };
  }
  if (file.size > MAX_BYTE_IMMAGINE) {
    return { ok: false, codice: "troppo_grande", messaggio: MESSAGGI_IMMAGINE.troppo_grande };
  }
  return { ok: true };
}

/** Dimensioni ridotte al lato massimo, senza mai ingrandire. */
export function dimensioniRidotte(
  larghezza: number,
  altezza: number,
  latoMax: number = LATO_MAX_OCR,
): { larghezza: number; altezza: number } {
  if (!(larghezza > 0) || !(altezza > 0)) throw new ImmagineNonUtilizzabile("illeggibile");
  const fattore = Math.min(1, latoMax / Math.max(larghezza, altezza));
  return {
    larghezza: Math.max(1, Math.round(larghezza * fattore)),
    altezza: Math.max(1, Math.round(altezza * fattore)),
  };
}

/**
 * Decodifica l'immagine, la orienta come la vede l'utente, la porta in scala di
 * grigi con un po' di contrasto e la ridimensiona. Solo browser: usa
 * `createImageBitmap` e un canvas. Qualunque fallimento diventa
 * `ImmagineNonUtilizzabile("illeggibile")`, mai il messaggio del browser.
 */
export async function preparaImmaginePerOcr(file: Blob): Promise<Blob> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    throw new ImmagineNonUtilizzabile("illeggibile");
  }
  try {
    if (bitmap.width * bitmap.height > MAX_PIXEL_IMMAGINE) {
      throw new ImmagineNonUtilizzabile("troppo_grande");
    }
    const { larghezza, altezza } = dimensioniRidotte(bitmap.width, bitmap.height);
    const canvas = document.createElement("canvas");
    canvas.width = larghezza;
    canvas.height = altezza;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new ImmagineNonUtilizzabile("illeggibile");
    // Safari ignora `filter`: in quel caso l'OCR legge l'immagine a colori.
    ctx.filter = "grayscale(1) contrast(1.15)";
    ctx.drawImage(bitmap, 0, 0, larghezza, altezza);
    const blob = await new Promise<Blob | null>((risolvi) =>
      canvas.toBlob(risolvi, "image/png"),
    );
    // Libera subito il buffer del canvas.
    canvas.width = 0;
    canvas.height = 0;
    if (!blob) throw new ImmagineNonUtilizzabile("illeggibile");
    return blob;
  } finally {
    bitmap.close();
  }
}
