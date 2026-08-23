/**
 * Preparazione della cover di un club, gemella di `lib/profilo/prepara-foto-avatar`.
 *
 * Due sole differenze rispetto all'avatar, entrambe dovute alla forma: il
 * ritaglio e panoramico invece che quadrato, e la destinazione e larga invece
 * che a lato singolo. Tutto il resto e identico di proposito: decodifica reale,
 * ridisegno su canvas, ricodifica WebP. Poiche i byte originali non vengono mai
 * copiati, EXIF, GPS e ogni altro metadato del file sorgente non possono
 * sopravvivere nel risultato.
 *
 * Non esiste un editor di ritaglio manuale: la cover si ritaglia al centro.
 */

export const DIMENSIONE_MASSIMA_COVER_CLUB = 5 * 1024 * 1024;
export const LARGHEZZA_COVER_CLUB = 1200;
export const ALTEZZA_COVER_CLUB = 400;
export const MIME_COVER_CLUB = "image/webp";
export const QUALITA_COVER_CLUB = 0.86;

const PROPORZIONE_COVER = LARGHEZZA_COVER_CLUB / ALTEZZA_COVER_CLUB;

// Esportato perche l'attributo `accept` del campo file deve dire esattamente
// cio che questa funzione accetta: due elenchi scritti a mano si scollano, e il
// modo in cui si nota e un utente che sceglie un file e riceve un rifiuto dopo.
// Non e un controllo di sicurezza - `file.type` lo dichiara il browser - ma il
// contenuto viene comunque decodificato davvero prima di essere ricodificato.
export const MIME_INGRESSO = ["image/jpeg", "image/png", "image/webp"] as const;
const MIME_AMMESSI = new Set<string>(MIME_INGRESSO);
const ERRORE_TIPO = "Scegli un'immagine JPEG, PNG o WebP valida.";
const ERRORE_PRESET = "Non e stato possibile usare questa cover predefinita.";

export type ImmagineDecodificata = {
  width: number;
  height: number;
  close?: () => void;
};

export type DipendenzePreparazioneCover = {
  decodifica(file: File): Promise<ImmagineDecodificata>;
  /**
   * Carica un preset servito da `public/club-covers/`. E una porta separata da
   * `decodifica` perche i preset sono SVG: `createImageBitmap` su un blob SVG
   * non e supportato ovunque, mentre un `<img>` con dimensioni intrinseche
   * esplicite lo e. L'URL non arriva mai dall'utente: e uno dei percorsi in
   * PRESET_COVER_CLUB.
   */
  decodificaUrl(url: string): Promise<ImmagineDecodificata>;
  codifica(
    immagine: ImmagineDecodificata,
    opzioni: {
      larghezza: number;
      altezza: number;
      mime: typeof MIME_COVER_CLUB;
      qualita: number;
      sorgente: { x: number; y: number; larghezza: number; altezza: number };
    },
  ): Promise<Blob>;
};

const dipendenzeBrowser: DipendenzePreparazioneCover = {
  async decodifica(file) {
    return createImageBitmap(file);
  },
  async decodificaUrl(url) {
    return new Promise<ImmagineDecodificata>((resolve, reject) => {
      const immagine = new Image();
      immagine.decoding = "async";
      immagine.onload = () =>
        resolve(
          Object.assign(immagine, {
            width: immagine.naturalWidth || LARGHEZZA_COVER_CLUB,
            height: immagine.naturalHeight || ALTEZZA_COVER_CLUB,
          }),
        );
      immagine.onerror = () => reject(new Error("Cover predefinita non disponibile."));
      immagine.src = url;
    });
  },
  async codifica(immagine, opzioni) {
    const canvas = document.createElement("canvas");
    canvas.width = opzioni.larghezza;
    canvas.height = opzioni.altezza;
    const contesto = canvas.getContext("2d");
    if (!contesto) throw new Error("Canvas non disponibile.");

    contesto.drawImage(
      immagine as CanvasImageSource,
      opzioni.sorgente.x,
      opzioni.sorgente.y,
      opzioni.sorgente.larghezza,
      opzioni.sorgente.altezza,
      0,
      0,
      opzioni.larghezza,
      opzioni.altezza,
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
 * Ritaglio centrale con la proporzione della cover: si prende la fascia piu
 * ampia che ci sta dentro l'immagine e la si porta a 1200x400.
 */
function ritaglioCentrale(larghezza: number, altezza: number) {
  const proporzione = larghezza / altezza;
  if (proporzione > PROPORZIONE_COVER) {
    // Sorgente piu panoramica della cover: si taglia sui lati.
    const larghezzaUtile = altezza * PROPORZIONE_COVER;
    return {
      x: (larghezza - larghezzaUtile) / 2,
      y: 0,
      larghezza: larghezzaUtile,
      altezza,
    };
  }
  // Sorgente piu alta: si taglia sopra e sotto.
  const altezzaUtile = larghezza / PROPORZIONE_COVER;
  return {
    x: 0,
    y: (altezza - altezzaUtile) / 2,
    larghezza,
    altezza: altezzaUtile,
  };
}

/** Ritaglia, ricodifica e impacchetta. Comune a cover custom e preset. */
async function disegnaCover(
  immagine: ImmagineDecodificata,
  dipendenze: DipendenzePreparazioneCover,
  erroreDecodifica: string,
): Promise<File> {
  try {
    if (!Number.isFinite(immagine.width) || !Number.isFinite(immagine.height)) {
      throw new Error(erroreDecodifica);
    }
    if (immagine.width < 1 || immagine.height < 1) throw new Error(erroreDecodifica);

    const blob = await dipendenze.codifica(immagine, {
      larghezza: LARGHEZZA_COVER_CLUB,
      altezza: ALTEZZA_COVER_CLUB,
      mime: MIME_COVER_CLUB,
      qualita: QUALITA_COVER_CLUB,
      sorgente: ritaglioCentrale(immagine.width, immagine.height),
    });
    if (blob.type !== MIME_COVER_CLUB || blob.size === 0) {
      throw new Error("Non e stato possibile preparare la cover.");
    }

    return new File([blob], "cover.webp", { type: MIME_COVER_CLUB });
  } finally {
    immagine.close?.();
  }
}

export async function preparaCoverClub(
  file: File,
  dipendenze: DipendenzePreparazioneCover = dipendenzeBrowser,
): Promise<File> {
  if (file.size > DIMENSIONE_MASSIMA_COVER_CLUB) {
    throw new Error("L'immagine supera il limite di 5 MB.");
  }
  if (!MIME_AMMESSI.has(file.type)) throw new Error(ERRORE_TIPO);

  let immagine: ImmagineDecodificata;
  try {
    immagine = await dipendenze.decodifica(file);
  } catch {
    throw new Error(ERRORE_TIPO);
  }

  return disegnaCover(immagine, dipendenze, ERRORE_TIPO);
}

/**
 * Un preset Vinea diventa un WebP identico a una cover caricata a mano: nel
 * database esiste un solo formato di riferimento (`<uid>/<uuid>.webp`), e il
 * CHECK `clubs_cover_image_vinea_check` non ammette percorsi di asset statici.
 */
export async function preparaCoverPreset(
  percorso: string,
  dipendenze: DipendenzePreparazioneCover = dipendenzeBrowser,
): Promise<File> {
  let immagine: ImmagineDecodificata;
  try {
    immagine = await dipendenze.decodificaUrl(percorso);
  } catch {
    throw new Error(ERRORE_PRESET);
  }

  return disegnaCover(immagine, dipendenze, ERRORE_PRESET);
}
