// WI-016 — Authenticity Assistant, analisi delle immagini PREDISPOSTA e provata solo su fixture. Modulo PURO: nessuna
// rete, nessun caricamento, nessun modello. Nessuna pagina lo usa e l'acquisizione di fotografie reali per questa
// finalità è SPENTA: servono i diritti sulle immagini per questo scopo, una procedura con responsabilità umana e una
// decisione legale sul linguaggio. Produce segnali per una persona: l'autenticità resta «non determinabile».

import { TIPI_IMMAGINE_AMMESSI } from "@/lib/vendi/foto-etichetta/immagine";
import { estraiCampiDaTestoOcr } from "@/lib/vendi/foto-etichetta/estrazione";
import { analizzaEvidenze, type AnalisiEvidenze, type SegnaleAutenticita } from "./analisi";

/** Si accende solo con una modifica del codice, dopo le decisioni elencate qui sopra: non esiste un interruttore a caldo. */
export const ACQUISIZIONE_IMMAGINI_REALI = false;

/** Stesso tetto del bucket privato della Cantina. */
const MAX_BYTE = 5 * 1024 * 1024;
const LATO_MIN = 600;
const LATO_MAX = 12_000;
const PIXEL_MAX = 40_000_000;

export type FormatoImmagine = "jpeg" | "png" | "webp";
export type MotivoRifiuto =
  | "vuoto"
  | "troppo_grande"
  | "formato_non_ammesso"
  | "contenuto_non_corrisponde"
  | "troncata"
  | "dimensioni_non_ammesse";
export type Ispezione =
  | { ok: true; formato: FormatoImmagine; larghezza: number; altezza: number }
  | { ok: false; motivo: MotivoRifiuto };

type Misure = { larghezza: number; altezza: number } | "troncata";

const comincia = (b: Uint8Array, firma: readonly number[], da = 0): boolean => firma.every((v, i) => b[da + i] === v);
const testo = (b: Uint8Array, da: number, n: number): string => String.fromCharCode(...b.subarray(da, da + n));
const be16 = (b: Uint8Array, i: number) => (b[i]! << 8) | b[i + 1]!;
const be32 = (b: Uint8Array, i: number) => be16(b, i) * 65_536 + be16(b, i + 2);
const le24 = (b: Uint8Array, i: number) => b[i]! | (b[i + 1]! << 8) | (b[i + 2]! << 16);
const le32 = (b: Uint8Array, i: number) => le24(b, i) + b[i + 3]! * 16_777_216;

const FIRMA_PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] as const;
const CODA_PNG = [0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82] as const;

const riconosci = (b: Uint8Array): FormatoImmagine | null =>
  comincia(b, FIRMA_PNG) ? "png"
  : comincia(b, [0xff, 0xd8, 0xff]) ? "jpeg"
  : testo(b, 0, 4) === "RIFF" && testo(b, 8, 4) === "WEBP" ? "webp"
  : null;

// L'immagine deve FINIRE dove finisce il file: una coda aggiunta (file poliglotta) non passa.
const misurePng = (b: Uint8Array): Misure => {
  if (b.length < 45 || testo(b, 12, 4) !== "IHDR" || !comincia(b, CODA_PNG, b.length - CODA_PNG.length)) return "troncata";
  return { larghezza: be32(b, 16), altezza: be32(b, 20) };
};

const misureJpeg = (b: Uint8Array): Misure => {
  if (!comincia(b, [0xff, 0xd9], b.length - 2)) return "troncata";
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) return "troncata";
    const marcatore = b[i + 1]!;
    const lunghezza = be16(b, i + 2);
    // SOF0–SOF15, esclusi DHT (C4), JPG (C8) e DAC (CC)
    if (marcatore >= 0xc0 && marcatore <= 0xcf && marcatore !== 0xc4 && marcatore !== 0xc8 && marcatore !== 0xcc) {
      return { altezza: be16(b, i + 5), larghezza: be16(b, i + 7) };
    }
    if (lunghezza < 2) return "troncata";
    i += 2 + lunghezza;
  }
  return "troncata";
};

const misureWebp = (b: Uint8Array): Misure => {
  if (b.length < 30 || le32(b, 4) + 8 !== b.length) return "troncata";
  const tipo = testo(b, 12, 4);
  if (tipo === "VP8X") return { larghezza: le24(b, 24) + 1, altezza: le24(b, 27) + 1 };
  if (tipo === "VP8 " && comincia(b, [0x9d, 0x01, 0x2a], 23)) {
    return { larghezza: (b[26]! | (b[27]! << 8)) & 0x3fff, altezza: (b[28]! | (b[29]! << 8)) & 0x3fff };
  }
  if (tipo === "VP8L" && b[20] === 0x2f) {
    const n = le32(b, 21);
    return { larghezza: (n & 0x3fff) + 1, altezza: ((n >>> 14) & 0x3fff) + 1 };
  }
  return "troncata";
};

const MISURE: Record<FormatoImmagine, (b: Uint8Array) => Misure> = { png: misurePng, jpeg: misureJpeg, webp: misureWebp };

/** Formato e dimensioni letti dal CONTENUTO; il tipo dichiarato deve coincidere. Non decodifica i pixel. */
export function ispezionaImmagine(byte: Uint8Array, mimeDichiarato: string): Ispezione {
  const no = (motivo: MotivoRifiuto): Ispezione => ({ ok: false, motivo });
  if (byte.length === 0) return no("vuoto");
  if (byte.length > MAX_BYTE) return no("troppo_grande");
  if (!(TIPI_IMMAGINE_AMMESSI as readonly string[]).includes(mimeDichiarato)) return no("formato_non_ammesso");
  const formato = riconosci(byte);
  if (!formato || `image/${formato}` !== mimeDichiarato) return no("contenuto_non_corrisponde");
  const misure = MISURE[formato](byte);
  if (misure === "troncata") return no("troncata");
  const { larghezza, altezza } = misure;
  if (
    Math.min(larghezza, altezza) < LATO_MIN ||
    Math.max(larghezza, altezza) > LATO_MAX ||
    larghezza * altezza > PIXEL_MAX
  ) {
    return no("dimensioni_non_ammesse");
  }
  return { ok: true, formato, larghezza, altezza };
}

export type PixelGrigi = { larghezza: number; altezza: number; grigi: Uint8Array };
export type MotivoQualita = "sfocata" | "troppo_scura" | "troppo_chiara" | "non_misurabile";

// Soglie di partenza, tarate sulle sole fixture: prima di un uso su fotografie vere vanno misurate su un campione autorizzato.
const NITIDEZZA_MIN = 100;
const LUMINOSITA_MIN = 40;
const LUMINOSITA_MAX = 225;

/** Nitidezza (varianza del laplaciano) ed esposizione media su un'immagine in scala di grigi già ridotta. */
export function misuraQualita({ larghezza, altezza, grigi }: PixelGrigi): { sufficiente: boolean; motivi: MotivoQualita[] } {
  if (larghezza < 3 || altezza < 3 || grigi.length !== larghezza * altezza) {
    return { sufficiente: false, motivi: ["non_misurabile"] };
  }
  let somma = 0;
  for (const v of grigi) somma += v;
  const media = somma / grigi.length;
  let s = 0;
  let q = 0;
  let n = 0;
  for (let y = 1; y < altezza - 1; y++) {
    for (let x = 1; x < larghezza - 1; x++) {
      const i = y * larghezza + x;
      const l = 4 * grigi[i]! - grigi[i - 1]! - grigi[i + 1]! - grigi[i - larghezza]! - grigi[i + larghezza]!;
      s += l;
      q += l * l;
      n++;
    }
  }
  const nitidezza = q / n - (s / n) ** 2;
  const motivi: MotivoQualita[] = [];
  if (media < LUMINOSITA_MIN) motivi.push("troppo_scura");
  else if (media > LUMINOSITA_MAX) motivi.push("troppo_chiara");
  if (nitidezza < NITIDEZZA_MIN && motivi.length === 0) motivi.push("sfocata");
  return { sufficiente: motivi.length === 0, motivi };
}

/** Confronto fra il testo letto dall'OCR (estrazione WI-002) e ciò che il proprietario dichiara. */
export function coerenzaEtichetta(testoOcr: string, dichiarato: { produttore: string; annata: number | null }): AnalisiEvidenze {
  const letto = estraiCampiDaTestoOcr(testoOcr);
  return analizzaEvidenze({
    dichiarato,
    etichetta: { produttore: letto.produttore ?? "", annata: letto.annata },
    documentoAcquisto: null,
    fotoNitida: null,
    condizioniDubbie: false,
  });
}

export type AnalisiImmagini =
  | { stato: "acquisizione_disattivata" }
  | { stato: "file_rifiutato"; motivo: MotivoRifiuto }
  | { stato: "analizzata"; segnali: SegnaleAutenticita[]; qualita: MotivoQualita[]; autenticita: "non_determinabile" };

export function analizzaImmaginiDiProva(i: {
  origine: "fixture" | "utente";
  byte: Uint8Array;
  mime: string;
  pixel: PixelGrigi;
  testoOcr: string;
  dichiarato: { produttore: string; annata: number | null };
}): AnalisiImmagini {
  if (i.origine !== "fixture" && !ACQUISIZIONE_IMMAGINI_REALI) return { stato: "acquisizione_disattivata" };
  const ispezione = ispezionaImmagine(i.byte, i.mime);
  if (!ispezione.ok) return { stato: "file_rifiutato", motivo: ispezione.motivo };
  const qualita = misuraQualita(i.pixel);
  const coerenza = coerenzaEtichetta(i.testoOcr, i.dichiarato);
  return {
    stato: "analizzata",
    segnali: [...coerenza.segnali, ...(qualita.sufficiente ? [] : (["qualita_foto_insufficiente"] as const))],
    qualita: qualita.motivi,
    autenticita: "non_determinabile",
  };
}
