/**
 * Provider di imballaggio **finto**, unica implementazione della Fase 7c.
 *
 * Non fa nessuna chiamata di rete. Non nomina GEL Proximity, MBE, Nakpack né
 * alcun altro fornitore: quando gli accordi commerciali saranno chiusi, sarà
 * una fase successiva a sostituire questo file con un adapter reale dietro una
 * Edge Function, **a interfaccia invariata**.
 *
 * Due vincoli che ne governano la forma:
 *
 * 1. **I prezzi non stanno qui.** Il catalogo arriva dall'esterno, letto da
 *    `public_packaging_options`, perché il prezzo è un dato di dominio
 *    autoritativo lato server e non una costante di un componente. Questo file
 *    non contiene nemmeno un importo.
 * 2. **I punti sono deterministici.** A parità di CAP la lista è sempre la
 *    stessa, perché un test deve poter asserire un risultato e perché un elenco
 *    che cambia a ogni render non somiglia a una mappa. Le coordinate sono
 *    inventate e non corrispondono a nessun luogo reale.
 */

import type { PackagingOption, PackagingPoint, PackagingProvider } from "@/services/types";

/** Nomi di fantasia. Nessuna insegna reale, per non suggerire un accordo che non c'è. */
const NOMI_PUNTO = [
  "Enoteca del Borgo",
  "Punto Ritiro Centro",
  "Cartoleria Bertani",
  "Bar Trentuno",
  "Ferramenta Via Nuova",
  "Edicola della Stazione",
] as const;

const VIE = [
  "Via dei Tigli",
  "Corso Garibaldi",
  "Piazza San Rocco",
  "Via Mazzini",
  "Viale delle Rimembranze",
  "Via del Carmine",
] as const;

const ORARI = [
  "Lun–Ven 8:30–19:30, Sab 9:00–13:00",
  "Lun–Sab 7:00–20:00",
  "Lun–Ven 9:00–18:00",
] as const;

/**
 * Hash deterministico e stabile fra esecuzioni. Non è crittografico e non deve
 * esserlo: serve solo a far sì che lo stesso CAP produca sempre la stessa lista.
 */
const impronta = (testo: string): number => {
  let h = 2166136261;
  for (let i = 0; i < testo.length; i += 1) {
    h ^= testo.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
};

const CAP_PREDEFINITO = "20121";

/** Quanti punti restituire: fra 4 e 6, deciso dal CAP e quindi stabile. */
const quantiPunti = (seme: number): number => 4 + (seme % 3);

const puntiFinti = (cap: string | null): PackagingPoint[] => {
  const capUsato = cap && /^\d{5}$/.test(cap) ? cap : CAP_PREDEFINITO;
  const seme = impronta(capUsato);
  const quanti = quantiPunti(seme);

  return Array.from({ length: quanti }, (_, i) => {
    const s = impronta(`${capUsato}:${i}`);
    return {
      id: `fake-${capUsato}-${i + 1}`,
      nome: NOMI_PUNTO[(seme + i) % NOMI_PUNTO.length],
      indirizzo: `${VIE[(s + i) % VIE.length]}, ${1 + (s % 90)}`,
      cap: capUsato,
      // Città e provincia non sono derivabili da un CAP senza un archivio che
      // questa fase non ha. Restano vuote invece di essere inventate: un dato
      // sbagliato è peggio di un dato assente.
      citta: "",
      provincia: "",
      // Coordinate finte, in un intorno stretto e deterministico.
      lat: Number((45.4 + ((s % 1000) / 100000)).toFixed(6)),
      lon: Number((9.15 + ((s % 1700) / 100000)).toFixed(6)),
      distanzaMetri: 150 + ((s % 40) * 75),
      orari: ORARI[(s + i) % ORARI.length],
    };
  });
};

export type FakePackagingProviderOptions = {
  /**
   * Il catalogo autoritativo, letto da `public_packaging_options`. Il provider
   * non ne possiede una copia: senza catalogo non offre nulla, ed è corretto —
   * un provider che inventasse opzioni inventerebbe anche prezzi.
   */
  catalogo: PackagingOption[];
};

export const createFakePackagingProvider = (
  { catalogo }: FakePackagingProviderOptions,
): PackagingProvider => ({
  id: "fake",

  async opzioniDisponibili({ near }) {
    // `near`, `formato` e `quantita` non cambiano l'offerta di un provider
    // finto. Restano nella firma perché un fornitore vero li userà eccome, e
    // scoprirlo dopo significherebbe cambiare l'unico punto di integrazione.
    void near;
    return { ok: true, data: [...catalogo].sort((a, b) => a.codice.localeCompare(b.codice)) };
  },

  async puntiVicini({ codice, cap }) {
    const opzione = catalogo.find((o) => o.codice === codice);
    if (!opzione) {
      return { ok: false, error: "Modalità di imballaggio non disponibile." };
    }
    if (!opzione.richiedePunto) {
      return { ok: true, data: [] };
    }
    return { ok: true, data: puntiFinti(cap) };
  },

  async prenota({ codice, puntoId, riferimentoOrdine }) {
    const opzione = catalogo.find((o) => o.codice === codice);
    if (!opzione) {
      return { ok: false, error: "Modalità di imballaggio non disponibile." };
    }
    if (opzione.richiedePunto && !puntoId) {
      return { ok: false, error: "Questa modalità richiede un punto di consegna." };
    }
    // Nessun effetto, nessuna rete. Un fornitore vero emetterebbe qui un codice
    // di ritiro; questo restituisce un riferimento riconoscibile come finto.
    return {
      ok: true,
      data: { provider: "fake", prenotazioneId: `FAKE-${riferimentoOrdine}` },
    };
  },
});

/** Esportata per i test e per chi deve sapere che cosa è deterministico. */
export const __puntiFintiPerTest = puntiFinti;
