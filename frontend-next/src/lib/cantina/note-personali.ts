/**
 * WI-005B — annotazioni personali su un vino della propria Cantina.
 *
 * Modulo puro (nessuna rete, nessun database): tipi, validazione e confronto col
 * catalogo. Ciò che qui si scrive è una DICHIARAZIONE PERSONALE dell'utente:
 * resta privata (tabella `wine_personal_notes`, RLS del solo proprietario), non
 * diventa un dato certificato e non modifica mai `public.wines`, che i vini di
 * altri utenti condividono. Non esiste una proposta di correzione del catalogo:
 * se un giorno esisterà sarà un'azione esplicita e separata.
 *
 * Limiti uguali a quelli dei vincoli della migration
 * `20261120120000_wi_005b_wine_personal_notes.sql`: la validazione client serve a
 * dare messaggi chiari, la barriera è il database.
 */

export const LIMITI_NOTA = {
  abbinamentiMax: 8,
  abbinamentoMin: 2,
  abbinamentoMax: 60,
  caliceMax: 40,
  denominazioneMax: 120,
  regioneMax: 80,
  osservazioniMax: 1000,
  temperaturaMin: 0,
  temperaturaMax: 25,
  decantazioneMax: 600,
  annataMin: 1800,
  annataMax: 2100,
} as const;

export type NotaPersonaleVino = {
  /** Abbinamenti sperimentati o suggeriti dall'utente: dichiarazioni, non verificati. */
  abbinamenti: string[];
  temperaturaC: number | null;
  decantazioneMinuti: number | null;
  calice: string;
  annataDichiarata: number | null;
  /** L'utente dichiara che il vino non ha annata. Esclude `annataDichiarata`. */
  nonMillesimato: boolean;
  denominazione: string;
  regione: string;
  osservazioni: string;
  /** ISO, solo se letta dal database. */
  aggiornataAt?: string;
};

export type CampoNota =
  | "abbinamenti"
  | "temperaturaC"
  | "decantazioneMinuti"
  | "calice"
  | "annataDichiarata"
  | "nonMillesimato"
  | "denominazione"
  | "regione"
  | "osservazioni";

/** Ciò che un modulo può consegnare: testo grezzo o già numeri, ogni campo facoltativo. */
export type InputNotaPersonale = {
  abbinamenti?: string[] | string;
  temperaturaC?: number | string | null;
  decantazioneMinuti?: number | string | null;
  calice?: string;
  annataDichiarata?: number | string | null;
  nonMillesimato?: boolean;
  denominazione?: string;
  regione?: string;
  osservazioni?: string;
};

export type EsitoValidazione =
  | { ok: true; nota: NotaPersonaleVino }
  | { ok: false; errori: Partial<Record<CampoNota, string>> };

export const notaVuota = (): NotaPersonaleVino => ({
  abbinamenti: [],
  temperaturaC: null,
  decantazioneMinuti: null,
  calice: "",
  annataDichiarata: null,
  nonMillesimato: false,
  denominazione: "",
  regione: "",
  osservazioni: "",
});

export function eNotaVuota(n: NotaPersonaleVino): boolean {
  return (
    n.abbinamenti.length === 0 &&
    n.temperaturaC === null &&
    n.decantazioneMinuti === null &&
    n.calice === "" &&
    n.annataDichiarata === null &&
    !n.nonMillesimato &&
    n.denominazione === "" &&
    n.regione === "" &&
    n.osservazioni === ""
  );
}

/** Un abbinamento per riga o separato da «;». La virgola NON separa: un piatto può contenerla. */
export function righeAbbinamenti(testo: string): string[] {
  return testo
    .split(/[\n\r;]+/)
    .map((r) => r.trim())
    .filter((r) => r !== "");
}

const CONTROLLO = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]/;
const CONTROLLO_ANCHE_A_CAPO = /[\u0000-\u001F\u007F\u0080-\u009F\u200B-\u200F\u202A-\u202E\u2066-\u2069]/;

const compatta = (s: string) => s.replace(/\s+/g, " ").trim();
const norm = (s: string) => compatta(s).toLocaleLowerCase("it-IT");

type Numero = { vuoto: true } | { vuoto: false; valore: number } | { errore: true };

function intero(v: number | string | null | undefined): Numero {
  if (v === null || v === undefined || (typeof v === "string" && v.trim() === "")) return { vuoto: true };
  const testo = typeof v === "number" ? String(v) : v.trim();
  if (!/^-?\d+$/.test(testo)) return { errore: true };
  return { vuoto: false, valore: Number(testo) };
}

export function validaNotaPersonale(input: InputNotaPersonale): EsitoValidazione {
  const errori: Partial<Record<CampoNota, string>> = {};

  const grezzi = Array.isArray(input.abbinamenti)
    ? input.abbinamenti
    : righeAbbinamenti(input.abbinamenti ?? "");
  const visti = new Set<string>();
  const abbinamenti: string[] = [];
  for (const g of grezzi) {
    const p = compatta(g);
    if (p === "") continue;
    if (CONTROLLO_ANCHE_A_CAPO.test(p)) {
      errori.abbinamenti = "Un abbinamento contiene caratteri non ammessi.";
      continue;
    }
    if (p.length < LIMITI_NOTA.abbinamentoMin || p.length > LIMITI_NOTA.abbinamentoMax) {
      errori.abbinamenti = `Ogni abbinamento deve avere da ${LIMITI_NOTA.abbinamentoMin} a ${LIMITI_NOTA.abbinamentoMax} caratteri.`;
      continue;
    }
    const k = norm(p);
    if (visti.has(k)) continue;
    visti.add(k);
    abbinamenti.push(p);
  }
  if (abbinamenti.length > LIMITI_NOTA.abbinamentiMax) {
    errori.abbinamenti = `Indica al massimo ${LIMITI_NOTA.abbinamentiMax} abbinamenti.`;
  }

  const num = (
    campo: CampoNota,
    v: number | string | null | undefined,
    min: number,
    max: number,
    messaggio: string,
  ): number | null => {
    const n = intero(v);
    if ("errore" in n) {
      errori[campo] = messaggio;
      return null;
    }
    if (n.vuoto) return null;
    if (n.valore < min || n.valore > max) {
      errori[campo] = messaggio;
      return null;
    }
    return n.valore;
  };

  const temperaturaC = num(
    "temperaturaC",
    input.temperaturaC,
    LIMITI_NOTA.temperaturaMin,
    LIMITI_NOTA.temperaturaMax,
    `La temperatura è un numero intero di gradi da ${LIMITI_NOTA.temperaturaMin} a ${LIMITI_NOTA.temperaturaMax}.`,
  );
  const decantazioneMinuti = num(
    "decantazioneMinuti",
    input.decantazioneMinuti,
    0,
    LIMITI_NOTA.decantazioneMax,
    `La decantazione è un numero intero di minuti da 0 a ${LIMITI_NOTA.decantazioneMax}.`,
  );
  const annataDichiarata = num(
    "annataDichiarata",
    input.annataDichiarata,
    LIMITI_NOTA.annataMin,
    LIMITI_NOTA.annataMax,
    `L'annata è un anno da ${LIMITI_NOTA.annataMin} a ${LIMITI_NOTA.annataMax}.`,
  );
  const nonMillesimato = input.nonMillesimato === true;
  if (nonMillesimato && annataDichiarata !== null) {
    errori.annataDichiarata = "Scegli: o indichi un'annata o dichiari il vino non millesimato.";
  }

  const testoBreve = (campo: CampoNota, v: string | undefined, max: number, etichetta: string): string => {
    const t = compatta(v ?? "");
    if (CONTROLLO_ANCHE_A_CAPO.test(t)) {
      errori[campo] = `${etichetta}: caratteri non ammessi.`;
      return "";
    }
    if (t.length > max) {
      errori[campo] = `${etichetta}: al massimo ${max} caratteri.`;
      return "";
    }
    return t;
  };
  const calice = testoBreve("calice", input.calice, LIMITI_NOTA.caliceMax, "Calice");
  const denominazione = testoBreve("denominazione", input.denominazione, LIMITI_NOTA.denominazioneMax, "Denominazione");
  const regione = testoBreve("regione", input.regione, LIMITI_NOTA.regioneMax, "Regione");

  // Le osservazioni ammettono l'a capo e il tab, ma non gli altri caratteri di controllo.
  const osservRaw = (input.osservazioni ?? "").replace(/\r\n?/g, "\n").trim();
  let osservazioni = osservRaw;
  if (CONTROLLO.test(osservRaw)) {
    errori.osservazioni = "Le osservazioni contengono caratteri non ammessi.";
    osservazioni = "";
  } else if (osservRaw.length > LIMITI_NOTA.osservazioniMax) {
    errori.osservazioni = `Le osservazioni possono avere al massimo ${LIMITI_NOTA.osservazioniMax} caratteri.`;
    osservazioni = "";
  }

  if (Object.keys(errori).length > 0) return { ok: false, errori };
  return {
    ok: true,
    nota: {
      abbinamenti,
      temperaturaC,
      decantazioneMinuti,
      calice,
      annataDichiarata,
      nonMillesimato,
      denominazione,
      regione,
      osservazioni,
    },
  };
}

export type Conflitto = {
  campo: "annata" | "regione" | "denominazione";
  /** Ciò che l'utente ha dichiarato. */
  personale: string;
  /** Ciò che il database Vinea riporta. */
  catalogo: string;
};

/**
 * Dove una dichiarazione personale e il catalogo dicono cose diverse. Non decide
 * chi abbia ragione: il catalogo resta com'è, la dichiarazione resta tua, e la
 * scheda li mostra entrambi con la loro origine.
 */
export function confrontaConCatalogo(
  nota: NotaPersonaleVino,
  catalogo: { annata: number; regione: string; denominazione: string },
): Conflitto[] {
  const out: Conflitto[] = [];
  const annataCatalogo = Number.isFinite(catalogo.annata) && catalogo.annata > 0 ? catalogo.annata : null;
  if (annataCatalogo !== null) {
    if (nota.nonMillesimato) {
      out.push({ campo: "annata", personale: "non millesimato", catalogo: String(annataCatalogo) });
    } else if (nota.annataDichiarata !== null && nota.annataDichiarata !== annataCatalogo) {
      out.push({ campo: "annata", personale: String(nota.annataDichiarata), catalogo: String(annataCatalogo) });
    }
  }
  const testo = (campo: "regione" | "denominazione") => {
    const p = nota[campo];
    const c = catalogo[campo];
    if (p !== "" && norm(c) !== "" && norm(p) !== norm(c)) out.push({ campo, personale: p, catalogo: c });
  };
  testo("regione");
  testo("denominazione");
  return out;
}
