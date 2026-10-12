import { describe, expect, it } from "bun:test";
import {
  formatImportoMinimo,
  isCodicePaese,
  isCodiceValuta,
  isLocale,
  LOCALE_PREDEFINITO,
  paeseConsentito,
  parseConfigurazioneMercato,
  tagIntl,
} from "@/lib/mercato";

const RISPOSTA_ITALIA = {
  paesePredefinito: "IT",
  valutaPredefinita: "eur",
  paesi: [
    {
      codice: "IT",
      registrazioneCommerciale: true,
      vendita: true,
      acquisto: true,
      spedizioneOrigine: true,
      spedizioneDestinazione: true,
    },
  ],
  valute: [{ codice: "eur", cifreDecimali: 2 }],
};

describe("locale", () => {
  it("italiano predefinito, inglese solo dichiarato", () => {
    expect(LOCALE_PREDEFINITO).toBe("it");
    expect(tagIntl()).toBe("it-IT");
    expect(tagIntl("en")).toBe("en-GB");
    expect(isLocale("en")).toBeTrue();
    expect(isLocale("fr")).toBeFalse();
    expect(isLocale(undefined)).toBeFalse();
  });
});

describe("codici ISO", () => {
  it("Paese alpha-2 maiuscolo e valuta minuscola come nel database", () => {
    expect(isCodicePaese("IT")).toBeTrue();
    expect(isCodicePaese("it")).toBeFalse();
    expect(isCodicePaese("ITA")).toBeFalse();
    expect(isCodiceValuta("eur")).toBeTrue();
    expect(isCodiceValuta("EUR")).toBeFalse();
    expect(isCodiceValuta("eu")).toBeFalse();
  });
});

describe("formatImportoMinimo", () => {
  it("formatta i centesimi in euro come il resto del sito", () => {
    expect(formatImportoMinimo(123456)).toBe(
      new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(1234.56),
    );
    expect(formatImportoMinimo(5)).toBe(
      new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(0.05),
    );
  });

  it("prende le cifre decimali dalla valuta", () => {
    expect(formatImportoMinimo(1500, "jpy", "en")).toBe(
      new Intl.NumberFormat("en-GB", { style: "currency", currency: "JPY" }).format(1500),
    );
  });

  it("rifiuta importi non interi e codici non validi", () => {
    expect(() => formatImportoMinimo(10.5)).toThrow(RangeError);
    expect(() => formatImportoMinimo(Number.NaN)).toThrow(RangeError);
    expect(() => formatImportoMinimo(100, "EUR")).toThrow(RangeError);
  });
});

describe("parseConfigurazioneMercato", () => {
  it("legge la configurazione italiana del database", () => {
    const config = parseConfigurazioneMercato(RISPOSTA_ITALIA);
    expect(config).toEqual(RISPOSTA_ITALIA);
    expect(paeseConsentito(config, "IT", "acquisto")).toBeTrue();
    expect(paeseConsentito(config, "FR", "acquisto")).toBeFalse();
  });

  it("nessuna configurazione leggibile → nessun Paese consentito", () => {
    expect(paeseConsentito(null, "IT", "vendita")).toBeFalse();
  });

  it("rifiuta risposte incoerenti", () => {
    expect(parseConfigurazioneMercato(null)).toBeNull();
    expect(parseConfigurazioneMercato([])).toBeNull();
    expect(parseConfigurazioneMercato({ ...RISPOSTA_ITALIA, paesePredefinito: "it" })).toBeNull();
    expect(parseConfigurazioneMercato({ ...RISPOSTA_ITALIA, valutaPredefinita: "EUR" })).toBeNull();
    expect(
      parseConfigurazioneMercato({
        ...RISPOSTA_ITALIA,
        paesi: [{ ...RISPOSTA_ITALIA.paesi[0], vendita: "true" }],
      }),
    ).toBeNull();
    expect(
      parseConfigurazioneMercato({ ...RISPOSTA_ITALIA, valute: [{ codice: "eur", cifreDecimali: 2.5 }] }),
    ).toBeNull();
    expect(parseConfigurazioneMercato({ ...RISPOSTA_ITALIA, paesi: {} })).toBeNull();
  });
});
