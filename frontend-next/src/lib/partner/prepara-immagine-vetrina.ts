/**
 * Preparazione delle immagini della vetrina Partner, nel browser.
 *
 * Ogni file viene decodificato e RICODIFICATO in WebP alle misure del suo
 * ruolo prima di lasciare il dispositivo: ciò che arriva allo Storage è
 * un'immagine disegnata da noi, senza metadati EXIF (posizione GPS compresa)
 * e leggera per lo smartphone. Il bucket `partner-vetrine` accetta comunque
 * solo `image/webp` fino a 2 MB: questa è cortesia, la regola è lì.
 *
 * Stessa forma di `lib/profilo/prepara-foto-avatar.ts`, con le dipendenze del
 * browser iniettabili perché i test non hanno un canvas.
 */

export type RuoloImmagineVetrina = "logo" | "copertina" | "foto";

export const MIME_IMMAGINE_VETRINA = "image/webp";
/** Limite del bucket. */
export const DIMENSIONE_MASSIMA_USCITA = 2 * 1024 * 1024;
/** Limite d'ingresso: una foto di smartphone recente sta sotto questa soglia. */
export const DIMENSIONE_MASSIMA_INGRESSO = 15 * 1024 * 1024;

const MIME_INGRESSO = new Set(["image/jpeg", "image/png", "image/webp"]);
const ERRORE_TIPO = "Scegli un'immagine JPEG, PNG o WebP valida.";
const QUALITA = [0.86, 0.76, 0.66] as const;

/**
 * Misure di uscita per ruolo. Logo quadrato, copertina 16:9 ritagliata al
 * centro; le foto non si ritagliano, si riducono entro il lato lungo.
 */
export const MISURE_VETRINA: Record<
  RuoloImmagineVetrina,
  { larghezza: number; altezza: number; ritaglio: boolean }
> = {
  logo: { larghezza: 512, altezza: 512, ritaglio: true },
  copertina: { larghezza: 1600, altezza: 900, ritaglio: true },
  foto: { larghezza: 1600, altezza: 1600, ritaglio: false },
};

export type ImmagineDecodificata = { width: number; height: number; close?: () => void };

export type Riquadro = { x: number; y: number; larghezza: number; altezza: number };

export type DipendenzeImmagineVetrina = {
  decodifica(file: File): Promise<ImmagineDecodificata>;
  codifica(
    immagine: ImmagineDecodificata,
    opzioni: { sorgente: Riquadro; larghezza: number; altezza: number; qualita: number },
  ): Promise<Blob>;
};

const dipendenzeBrowser: DipendenzeImmagineVetrina = {
  async decodifica(file) {
    return createImageBitmap(file);
  },
  async codifica(immagine, { sorgente, larghezza, altezza, qualita }) {
    const canvas = document.createElement("canvas");
    canvas.width = larghezza;
    canvas.height = altezza;
    const contesto = canvas.getContext("2d");
    if (!contesto) throw new Error("Canvas non disponibile.");
    contesto.drawImage(
      immagine as CanvasImageSource,
      sorgente.x,
      sorgente.y,
      sorgente.larghezza,
      sorgente.altezza,
      0,
      0,
      larghezza,
      altezza,
    );
    return new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (blob) => (blob ? resolve(blob) : reject(new Error("Codifica non riuscita."))),
        MIME_IMMAGINE_VETRINA,
        qualita,
      );
    });
  },
};

/**
 * Riquadro sorgente e misure di uscita. Mai un ingrandimento: un'immagine più
 * piccola del bersaglio resta alle sue misure (per il ritaglio, alla
 * proporzione del bersaglio).
 */
export function geometriaVetrina(
  ruolo: RuoloImmagineVetrina,
  larghezzaOrig: number,
  altezzaOrig: number,
): { sorgente: Riquadro; larghezza: number; altezza: number } {
  const m = MISURE_VETRINA[ruolo];
  if (m.ritaglio) {
    const proporzione = m.larghezza / m.altezza;
    let w = larghezzaOrig;
    let h = Math.round(w / proporzione);
    if (h > altezzaOrig) {
      h = altezzaOrig;
      w = Math.round(h * proporzione);
    }
    const scala = Math.min(1, m.larghezza / w);
    return {
      sorgente: {
        x: Math.round((larghezzaOrig - w) / 2),
        y: Math.round((altezzaOrig - h) / 2),
        larghezza: w,
        altezza: h,
      },
      larghezza: Math.max(1, Math.round(w * scala)),
      altezza: Math.max(1, Math.round(h * scala)),
    };
  }
  const scala = Math.min(1, m.larghezza / Math.max(larghezzaOrig, altezzaOrig));
  return {
    sorgente: { x: 0, y: 0, larghezza: larghezzaOrig, altezza: altezzaOrig },
    larghezza: Math.max(1, Math.round(larghezzaOrig * scala)),
    altezza: Math.max(1, Math.round(altezzaOrig * scala)),
  };
}

export async function preparaImmagineVetrina(
  file: File,
  ruolo: RuoloImmagineVetrina,
  dipendenze: DipendenzeImmagineVetrina = dipendenzeBrowser,
): Promise<Blob> {
  if (file.size > DIMENSIONE_MASSIMA_INGRESSO) {
    throw new Error("L'immagine supera il limite di 15 MB.");
  }
  if (!MIME_INGRESSO.has(file.type)) throw new Error(ERRORE_TIPO);

  let immagine: ImmagineDecodificata;
  try {
    immagine = await dipendenze.decodifica(file);
  } catch {
    throw new Error(ERRORE_TIPO);
  }

  try {
    if (
      !Number.isFinite(immagine.width) ||
      !Number.isFinite(immagine.height) ||
      immagine.width < 1 ||
      immagine.height < 1
    ) {
      throw new Error(ERRORE_TIPO);
    }
    const geometria = geometriaVetrina(ruolo, immagine.width, immagine.height);
    for (const qualita of QUALITA) {
      const blob = await dipendenze.codifica(immagine, { ...geometria, qualita });
      if (blob.type !== MIME_IMMAGINE_VETRINA || blob.size === 0) {
        throw new Error("Non è stato possibile preparare l'immagine.");
      }
      if (blob.size <= DIMENSIONE_MASSIMA_USCITA) return blob;
    }
    throw new Error("L'immagine resta troppo pesante anche compressa. Prova con un'altra.");
  } finally {
    immagine.close?.();
  }
}
