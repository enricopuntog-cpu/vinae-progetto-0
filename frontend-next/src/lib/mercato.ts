/**
 * Predisposizione internazionale (VP-F): forma di lingue, Paesi e valute.
 *
 * Qui non si decide nulla: quali Paesi e valute sono abilitati lo dice il
 * database (`public.mercato_configurazione`), e i gate su ordini, proposte e
 * annunci rifiutano il resto. Oggi l'unico mercato è l'Italia in euro e
 * l'interfaccia è in italiano; l'inglese è solo dichiarato come locale futura.
 */

export const LOCALI_SUPPORTATI = ["it", "en"] as const;
export type Locale = (typeof LOCALI_SUPPORTATI)[number];
export const LOCALE_PREDEFINITO: Locale = "it";

const TAG_INTL: Record<Locale, string> = { it: "it-IT", en: "en-GB" };

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALI_SUPPORTATI as readonly string[]).includes(value);
}

export function tagIntl(locale: Locale = LOCALE_PREDEFINITO): string {
  return TAG_INTL[locale];
}

/** ISO 3166-1 alpha-2, maiuscolo come nel database. */
export const PAESE_PREDEFINITO = "IT";
/** ISO 4217 nella forma minuscola di `orders.currency`/`payments.currency`. */
export const VALUTA_PREDEFINITA = "eur";

export function isCodicePaese(value: unknown): value is string {
  return typeof value === "string" && /^[A-Z]{2}$/.test(value);
}

export function isCodiceValuta(value: unknown): value is string {
  return typeof value === "string" && /^[a-z]{3}$/.test(value);
}

/**
 * Formatta un importo espresso in unità minime (centesimi per l'euro). Le
 * cifre decimali vengono dalla valuta, non da una costante.
 */
export function formatImportoMinimo(
  importo: number,
  valuta: string = VALUTA_PREDEFINITA,
  locale: Locale = LOCALE_PREDEFINITO,
): string {
  if (!Number.isSafeInteger(importo)) {
    throw new RangeError("L'importo deve essere un intero in unità minime.");
  }
  if (!isCodiceValuta(valuta)) {
    throw new RangeError("Codice valuta non valido.");
  }
  const formato = new Intl.NumberFormat(tagIntl(locale), {
    style: "currency",
    currency: valuta.toUpperCase(),
  });
  const cifre = formato.resolvedOptions().maximumFractionDigits ?? 2;
  return formato.format(importo / 10 ** cifre);
}

export type UsiPaese = {
  registrazioneCommerciale: boolean;
  vendita: boolean;
  acquisto: boolean;
  spedizioneOrigine: boolean;
  spedizioneDestinazione: boolean;
};

export type ConfigurazioneMercato = {
  paesePredefinito: string;
  valutaPredefinita: string;
  paesi: Array<{ codice: string } & UsiPaese>;
  valute: Array<{ codice: string; cifreDecimali: number }>;
};

const CHIAVI_USI: Array<keyof UsiPaese> = [
  "registrazioneCommerciale",
  "vendita",
  "acquisto",
  "spedizioneOrigine",
  "spedizioneDestinazione",
];

function isOggetto(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Lettura rigida della risposta di `mercato_configurazione`: incoerente → null. */
export function parseConfigurazioneMercato(raw: unknown): ConfigurazioneMercato | null {
  if (!isOggetto(raw)) return null;
  const { paesePredefinito, valutaPredefinita, paesi, valute } = raw;
  if (!isCodicePaese(paesePredefinito) || !isCodiceValuta(valutaPredefinita)) return null;
  if (!Array.isArray(paesi) || !Array.isArray(valute)) return null;

  const paesiLetti: ConfigurazioneMercato["paesi"] = [];
  for (const p of paesi) {
    if (!isOggetto(p) || !isCodicePaese(p.codice)) return null;
    if (!CHIAVI_USI.every((k) => typeof p[k] === "boolean")) return null;
    paesiLetti.push({
      codice: p.codice,
      registrazioneCommerciale: p.registrazioneCommerciale as boolean,
      vendita: p.vendita as boolean,
      acquisto: p.acquisto as boolean,
      spedizioneOrigine: p.spedizioneOrigine as boolean,
      spedizioneDestinazione: p.spedizioneDestinazione as boolean,
    });
  }

  const valuteLette: ConfigurazioneMercato["valute"] = [];
  for (const v of valute) {
    if (!isOggetto(v) || !isCodiceValuta(v.codice)) return null;
    const cifre = v.cifreDecimali;
    if (typeof cifre !== "number" || !Number.isInteger(cifre) || cifre < 0 || cifre > 3) return null;
    valuteLette.push({ codice: v.codice, cifreDecimali: cifre });
  }

  return {
    paesePredefinito,
    valutaPredefinita,
    paesi: paesiLetti,
    valute: valuteLette,
  };
}

/** Un uso è consentito solo se la configurazione lo dichiara; altrimenti no. */
export function paeseConsentito(
  config: ConfigurazioneMercato | null,
  codice: string,
  uso: keyof UsiPaese,
): boolean {
  return config?.paesi.some((p) => p.codice === codice && p[uso]) ?? false;
}
