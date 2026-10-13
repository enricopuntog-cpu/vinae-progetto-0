import type { Indirizzo, IndirizzoInput } from "@/services/types";

/**
 * Rubrica degli indirizzi: regole di presentazione e controlli d'ingresso.
 *
 * L'autorità resta `public.indirizzo_salva`: Paese (solo Italia, registri
 * VP-F), proprietario, predefiniti unici e limiti li decide il database. Qui
 * si ripetono gli stessi controlli di forma della porta, con le stesse frasi,
 * solo per dire subito a chi scrive che cosa correggere; un valore che passa
 * qui e non passa lì torna comunque con il messaggio del server.
 *
 * Modulo puro: nessun client, nessun React.
 */

export type CampoIndirizzo = keyof Omit<IndirizzoInput, "predefinitoRitiro" | "predefinitoConsegna">;
export type ErroriIndirizzo = Partial<Record<CampoIndirizzo, string>>;

/** Massimo di indirizzi attivi per persona, come la porta (`troppi_indirizzi`). */
export const MAX_INDIRIZZI = 20;

export const indirizzoVuoto = (predefiniti?: Partial<IndirizzoInput>): IndirizzoInput => ({
  etichetta: "",
  destinatario: "",
  via: "",
  cap: "",
  citta: "",
  provincia: "",
  telefono: "",
  note: "",
  predefinitoRitiro: false,
  predefinitoConsegna: false,
  ...predefiniti,
});

export const daIndirizzo = (i: Indirizzo): IndirizzoInput => ({
  etichetta: i.etichetta ?? "",
  destinatario: i.destinatario,
  via: i.via,
  cap: i.cap,
  citta: i.citta,
  provincia: i.provincia,
  telefono: i.telefono ?? "",
  note: i.note ?? "",
  predefinitoRitiro: i.predefinitoRitiro,
  predefinitoConsegna: i.predefinitoConsegna,
});

const lunghezza = (v: string, min: number, max: number) => {
  const n = v.trim().length;
  return n >= min && n <= max;
};

/** Gli stessi controlli di `indirizzo_salva`, nello stesso ordine e con le stesse frasi. */
export function validaIndirizzo(dati: IndirizzoInput): ErroriIndirizzo {
  const errori: ErroriIndirizzo = {};
  if (!lunghezza(dati.destinatario, 2, 120)) errori.destinatario = "Indica il nome del destinatario.";
  if (!lunghezza(dati.via, 3, 200)) errori.via = "Indica via e numero civico.";
  if (!/^[0-9]{5}$/.test(dati.cap.trim())) errori.cap = "Il CAP deve avere 5 cifre.";
  if (!lunghezza(dati.citta, 2, 100)) errori.citta = "Indica la città.";
  if (!/^[A-Z]{2}$/.test(dati.provincia.trim().toUpperCase())) {
    errori.provincia = "La provincia è la sigla di due lettere.";
  }
  const telefono = dati.telefono.trim();
  if (telefono && !/^\+?[0-9 ]{6,20}$/.test(telefono)) {
    errori.telefono = "Il telefono contiene caratteri non validi.";
  }
  if (dati.note.length > 200) errori.note = "Le note possono avere al massimo 200 caratteri.";
  if (dati.etichetta.trim().length > 60) errori.etichetta = "L'etichetta può avere al massimo 60 caratteri.";
  return errori;
}

/** «Via Roma 1, 20121 Milano (MI)». */
export const rigaIndirizzo = (i: Pick<Indirizzo, "via" | "cap" | "citta" | "provincia">): string =>
  `${i.via}, ${i.cap} ${i.citta} (${i.provincia})`;

/** Titolo della scheda: l'etichetta scelta o il destinatario. */
export const titoloIndirizzo = (i: Pick<Indirizzo, "etichetta" | "destinatario">): string =>
  i.etichetta?.trim() || i.destinatario;

export const ritiroPredefinito = (rubrica: readonly Indirizzo[]): Indirizzo | null =>
  rubrica.find((i) => i.predefinitoRitiro) ?? null;

export const consegnaPredefinita = (rubrica: readonly Indirizzo[]): Indirizzo | null =>
  rubrica.find((i) => i.predefinitoConsegna) ?? null;

/**
 * L'indirizzo di consegna da proporre nel checkout: quello già scelto se è
 * ancora in rubrica, altrimenti il predefinito di consegna, altrimenti il
 * primo. `null` con la rubrica vuota.
 */
export function indirizzoConsegnaProposto(
  rubrica: readonly Indirizzo[],
  sceltoId: string | null,
): Indirizzo | null {
  if (sceltoId) {
    const scelto = rubrica.find((i) => i.id === sceltoId);
    if (scelto) return scelto;
  }
  return consegnaPredefinita(rubrica) ?? rubrica[0] ?? null;
}
