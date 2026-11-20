// WI-002 — motore OCR locale.
//
// `tesseract.js` (Apache-2.0) gira nel browser dell'utente: worker, core WASM e
// dati della lingua sono file statici di Vinea sotto `/ocr/` (copiati da
// `scripts/copia-asset-ocr.mjs`), nessuna CDN e nessuna chiamata a terzi.
//
// Il motore si carica solo quando l'utente chiede di leggere una fotografia
// (import dinamico), vive per una sola lettura e viene terminato in ogni caso,
// così non resta memoria occupata. L'interfaccia `MotoreOcr` è ciò che il resto
// del codice conosce: un altro motore può sostituirlo senza toccare il wizard.

export type RisultatoOcr = {
  testo: string;
  /** Confidenza media del motore, 0–100. Non è una probabilità di correttezza. */
  confidenza: number;
};

export type OpzioniLettura = {
  segnale?: AbortSignal;
  suProgresso?: (frazione: number) => void;
};

export interface MotoreOcr {
  riconosci(immagine: Blob | Uint8Array, opzioni?: OpzioniLettura): Promise<RisultatoOcr>;
}

export type CodiceErroreOcr = "non_disponibile" | "scaduto" | "annullato";

export class ErroreOcr extends Error {
  constructor(readonly codice: CodiceErroreOcr) {
    super(MESSAGGI_OCR[codice]);
    this.name = "ErroreOcr";
  }
}

export const MESSAGGI_OCR: Record<CodiceErroreOcr, string> = {
  non_disponibile:
    "La lettura automatica non è disponibile su questo dispositivo. Puoi compilare i campi a mano.",
  scaduto: "La lettura ha richiesto troppo tempo. Prova con una foto più nitida o compila a mano.",
  annullato: "Lettura annullata.",
};

export type PercorsiOcr = {
  workerPath?: string;
  corePath: string;
  langPath: string;
};

export const PERCORSI_OCR_BROWSER: PercorsiOcr = {
  workerPath: "/ocr/worker.min.js",
  corePath: "/ocr/core",
  langPath: "/ocr/lang",
};

/** Il sottoinsieme di `tesseract.js` che serve qui; permette di sostituirlo nei test. */
export type TesseractMinimo = {
  createWorker: (
    lingue: string,
    oem: number,
    opzioni: Record<string, unknown>,
  ) => Promise<{
    recognize: (
      immagine: Blob | Uint8Array,
    ) => Promise<{ data: { text: string; confidence: number } }>;
    terminate: () => Promise<unknown>;
  }>;
};

export type OpzioniMotoreTesseract = {
  percorsi?: PercorsiOcr;
  lingua?: string;
  timeoutMs?: number;
  /** In Node (test) il worker è quello di `tesseract.js`, non un file servito. */
  ambienteNode?: boolean;
  caricaLibreria?: () => Promise<TesseractMinimo>;
};

export const TIMEOUT_OCR_MS = 90_000;
const OEM_LSTM_ONLY = 1;

const caricaTesseractReale = async (): Promise<TesseractMinimo> => {
  const modulo = await import("tesseract.js");
  return (modulo.default ?? modulo) as unknown as TesseractMinimo;
};

export function creaMotoreTesseract(opzioni: OpzioniMotoreTesseract = {}): MotoreOcr {
  const percorsi = opzioni.percorsi ?? PERCORSI_OCR_BROWSER;
  const lingua = opzioni.lingua ?? "ita";
  const timeoutMs = opzioni.timeoutMs ?? TIMEOUT_OCR_MS;
  const carica = opzioni.caricaLibreria ?? caricaTesseractReale;

  return {
    async riconosci(immagine, { segnale, suProgresso } = {}) {
      if (segnale?.aborted) throw new ErroreOcr("annullato");

      let libreria: TesseractMinimo;
      try {
        libreria = await carica();
      } catch {
        throw new ErroreOcr("non_disponibile");
      }

      let worker: Awaited<ReturnType<TesseractMinimo["createWorker"]>> | null = null;
      let temporizzatore: ReturnType<typeof setTimeout> | undefined;
      let rimuoviAscolto: (() => void) | undefined;
      let concluso = false;
      try {
        const lettura = (async () => {
          const opzioniWorker: Record<string, unknown> = {
            corePath: percorsi.corePath,
            langPath: percorsi.langPath,
            gzip: true,
            cacheMethod: "none",
            logger: (m: { status?: string; progress?: number }) => {
              if (m.status === "recognizing text" && typeof m.progress === "number") {
                suProgresso?.(m.progress);
              }
            },
          };
          if (!opzioni.ambienteNode) {
            opzioniWorker.workerPath = percorsi.workerPath;
            // Un worker da `blob:` erediterebbe la CSP della pagina, che non
            // consente WebAssembly: va caricato dal file same-origin.
            opzioniWorker.workerBlobURL = false;
          }
          try {
            worker = await libreria.createWorker(lingua, OEM_LSTM_ONLY, opzioniWorker);
          } catch {
            throw new ErroreOcr("non_disponibile");
          }
          // Interrotta mentre il worker nasceva: lo si rilascia subito.
          if (concluso) {
            await worker.terminate().catch(() => undefined);
            worker = null;
            throw new ErroreOcr("annullato");
          }
          try {
            // Il worker di Node legge Buffer, non Blob (nel browser Blob va bene).
            const ingresso =
              opzioni.ambienteNode && immagine instanceof Blob
                ? Buffer.from(await immagine.arrayBuffer())
                : immagine;
            const { data } = await worker.recognize(ingresso);
            return {
              testo: String(data.text ?? ""),
              confidenza: Number.isFinite(data.confidence) ? data.confidence : 0,
            } satisfies RisultatoOcr;
          } catch {
            throw new ErroreOcr("non_disponibile");
          }
        })();

        const interruzione = new Promise<never>((_, rifiuta) => {
          temporizzatore = setTimeout(() => rifiuta(new ErroreOcr("scaduto")), timeoutMs);
          if (segnale) {
            const alAbort = () => rifiuta(new ErroreOcr("annullato"));
            segnale.addEventListener("abort", alAbort, { once: true });
            rimuoviAscolto = () => segnale.removeEventListener("abort", alAbort);
          }
        });

        // Se vince l'interruzione, la lettura resta appesa e fallirà da sola
        // quando il worker viene terminato: la si silenzia per non lasciare un
        // rifiuto non gestito.
        lettura.catch(() => undefined);
        return await Promise.race([lettura, interruzione]);
      } finally {
        concluso = true;
        if (temporizzatore) clearTimeout(temporizzatore);
        rimuoviAscolto?.();
        // Anche se il worker è ancora in creazione quando scatta il timeout, lo
        // si rilascia appena esiste.
        const w = worker as Awaited<ReturnType<TesseractMinimo["createWorker"]>> | null;
        // Non si attende: un worker che non risponde non deve bloccare l'interfaccia.
        if (w) void w.terminate().catch(() => undefined);
      }
    },
  };
}
