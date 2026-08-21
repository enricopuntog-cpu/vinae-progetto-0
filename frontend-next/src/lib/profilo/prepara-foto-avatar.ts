export const DIMENSIONE_MASSIMA_FOTO_AVATAR = 5 * 1024 * 1024;
export const LATO_FOTO_AVATAR = 512;
export const MIME_FOTO_AVATAR = "image/webp";
export const QUALITA_FOTO_AVATAR = 0.86;

const MIME_INGRESSO = new Set(["image/jpeg", "image/png", "image/webp"]);
const ERRORE_TIPO = "Scegli una foto JPEG, PNG o WebP valida.";

export type ImmagineDecodificata = {
  width: number;
  height: number;
  close?: () => void;
};

export type DipendenzePreparazioneFoto = {
  decodifica(file: File): Promise<ImmagineDecodificata>;
  codifica(
    immagine: ImmagineDecodificata,
    opzioni: {
      lato: number;
      mime: typeof MIME_FOTO_AVATAR;
      qualita: number;
      sorgente: { x: number; y: number; lato: number };
    },
  ): Promise<Blob>;
};

const dipendenzeBrowser: DipendenzePreparazioneFoto = {
  async decodifica(file) {
    return createImageBitmap(file);
  },
  async codifica(immagine, opzioni) {
    const canvas = document.createElement("canvas");
    canvas.width = opzioni.lato;
    canvas.height = opzioni.lato;
    const contesto = canvas.getContext("2d");
    if (!contesto) throw new Error("Canvas non disponibile.");

    contesto.drawImage(
      immagine as CanvasImageSource,
      opzioni.sorgente.x,
      opzioni.sorgente.y,
      opzioni.sorgente.lato,
      opzioni.sorgente.lato,
      0,
      0,
      opzioni.lato,
      opzioni.lato,
    );

    return new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (blob) => (blob ? resolve(blob) : reject(new Error("Codifica non riuscita."))),
        opzioni.mime,
        opzioni.qualita,
      );
    });
  },
};

/**
 * Decodifica pixel reali, esegue un ritaglio centrale quadrato e li codifica in
 * un WebP nuovo. Poiché i byte originali non vengono copiati, EXIF, GPS e altri
 * metadati del file sorgente non possono sopravvivere nel risultato.
 */
export async function preparaFotoAvatar(
  file: File,
  dipendenze: DipendenzePreparazioneFoto = dipendenzeBrowser,
): Promise<File> {
  if (file.size > DIMENSIONE_MASSIMA_FOTO_AVATAR) {
    throw new Error("La foto supera il limite di 5 MB.");
  }
  if (!MIME_INGRESSO.has(file.type)) throw new Error(ERRORE_TIPO);

  let immagine: ImmagineDecodificata;
  try {
    immagine = await dipendenze.decodifica(file);
  } catch {
    throw new Error(ERRORE_TIPO);
  }

  try {
    if (!Number.isFinite(immagine.width) || !Number.isFinite(immagine.height)) {
      throw new Error(ERRORE_TIPO);
    }
    const latoSorgente = Math.min(immagine.width, immagine.height);
    if (latoSorgente < 1) throw new Error(ERRORE_TIPO);

    const blob = await dipendenze.codifica(immagine, {
      lato: LATO_FOTO_AVATAR,
      mime: MIME_FOTO_AVATAR,
      qualita: QUALITA_FOTO_AVATAR,
      sorgente: {
        x: (immagine.width - latoSorgente) / 2,
        y: (immagine.height - latoSorgente) / 2,
        lato: latoSorgente,
      },
    });
    if (blob.type !== MIME_FOTO_AVATAR || blob.size === 0) {
      throw new Error("Non è stato possibile preparare la foto.");
    }

    return new File([blob], "avatar.webp", { type: MIME_FOTO_AVATAR });
  } finally {
    immagine.close?.();
  }
}
