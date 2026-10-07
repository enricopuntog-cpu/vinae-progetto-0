import {
  THEME_LABELS,
  phaseLabel,
  type DrinkPhase,
  type EnvTheme,
  type SaleStatus,
} from "@/data/cellar";

/**
 * Anteprima statica della Cantina dentro la guida Market Validation.
 *
 * Tutto qui è un esempio locale: nessun record viene letto o scritto, nessun
 * account è coinvolto e nessuna bottiglia entra nella Cantina reale. Le
 * etichette — stati di vendita e visibilità, finestra di bevuta, preset
 * estetici, voci della contabilità — sono quelle della Cantina vera, così il
 * tester riconosce poi le stesse parole in `/cantina`.
 *
 * La Cantina è una scoperta facoltativa: non è uno step del test, non ha un
 * evento e non entra nel conteggio «0 di 2».
 */

export const MARKET_VALIDATION_CELLAR_PREVIEW_VERSION = "mv-cellar-2026-10-07b" as const;

/**
 * Anno di riferimento fisso delle finestre di bevuta d'esempio: l'anteprima
 * non legge l'orologio, così il risultato è identico per ogni tester.
 */
export const MARKET_VALIDATION_CELLAR_REFERENCE_YEAR = 2026;

export type MarketValidationCellarStatus = Exclude<SaleStatus, "venduta">;

/**
 * Etichette mostrate al tester. «In vendita» e «Visibile nel profilo» sono le
 * parole dei badge di `/cantina`; «Solo in Cantina» è copy della demo per lo
 * stato privato, non un nome tecnico né uno stato del database.
 */
export const MARKET_VALIDATION_CELLAR_STATUS_LABEL: Record<MarketValidationCellarStatus, string> = {
  in_vendita: "In vendita",
  privata: "Solo in Cantina",
  cantina_pubblica: "Visibile nel profilo",
};

/** Che cosa significa ciascuno stato, in una riga. */
export const MARKET_VALIDATION_CELLAR_STATUS_TEXT: Record<MarketValidationCellarStatus, string> = {
  in_vendita: "È anche un annuncio del marketplace, con prezzo, spedizione e proposte.",
  privata: "La vedi soltanto tu: è il tuo archivio privato, senza prezzo obbligatorio.",
  cantina_pubblica: "Gli altri la vedono nel tuo profilo, ma non è in vendita: è la tua vetrina.",
};

export const MARKET_VALIDATION_CELLAR_STATUS_ORDER: readonly MarketValidationCellarStatus[] = [
  "in_vendita",
  "privata",
  "cantina_pubblica",
];

export type MarketValidationCellarBottle = Readonly<{
  id: `mv_cellar_${string}`;
  producer: string;
  wine: string;
  denomination: string;
  vintage: number;
  quantity: number;
  referenceValueCents: number;
  status: MarketValidationCellarStatus;
  phase: Extract<DrinkPhase, "attesa" | "pronto" | "ideale" | "presto">;
  drinkFrom: number;
  drinkTo: number;
  image: `/images/${string}`;
  plannedOpening?: string;
  example: true;
}>;

/** Produttori e vini fittizi, come gli annunci demo del percorso Acquista. */
export const MARKET_VALIDATION_CELLAR_BOTTLES: readonly MarketValidationCellarBottle[] = [
  {
    id: "mv_cellar_riserva_colle_2015",
    producer: "Tenuta del Colle",
    wine: "Riserva del Colle",
    denomination: "Barolo DOCG",
    vintage: 2015,
    quantity: 2,
    referenceValueCents: 9500,
    status: "in_vendita",
    phase: "ideale",
    drinkFrom: 2023,
    drinkTo: 2035,
    image: "/images/vinea-bottle-1.jpg",
    example: true,
  },
  {
    id: "mv_cellar_vigna_antica_2019",
    producer: "Podere Vigna Antica",
    wine: "Vigna Antica",
    denomination: "Brunello di Montalcino DOCG",
    vintage: 2019,
    quantity: 3,
    referenceValueCents: 6800,
    status: "privata",
    phase: "attesa",
    drinkFrom: 2027,
    drinkTo: 2040,
    image: "/images/vinea-bottle-2.jpg",
    example: true,
  },
  {
    id: "mv_cellar_sorgente_bianca_2022",
    producer: "Tenuta Sorgente",
    wine: "Sorgente Bianca",
    denomination: "Soave Classico DOC",
    vintage: 2022,
    quantity: 1,
    referenceValueCents: 2400,
    status: "cantina_pubblica",
    phase: "pronto",
    drinkFrom: 2024,
    drinkTo: 2028,
    image: "/images/vinea-white.jpg",
    example: true,
  },
  {
    id: "mv_cellar_bollicine_collina_2018",
    producer: "Cantina Collina Alta",
    wine: "Bollicine di Collina",
    denomination: "Franciacorta DOCG",
    vintage: 2018,
    quantity: 1,
    referenceValueCents: 4200,
    status: "privata",
    phase: "presto",
    drinkFrom: 2022,
    drinkTo: 2026,
    image: "/images/vinea-champagne.jpg",
    plannedOpening: "31 dicembre",
    example: true,
  },
  {
    id: "mv_cellar_vento_sera_2020",
    producer: "Corte del Vento",
    wine: "Vento di Sera",
    denomination: "Valpolicella Ripasso DOC",
    vintage: 2020,
    quantity: 1,
    referenceValueCents: 2550,
    status: "in_vendita",
    phase: "pronto",
    drinkFrom: 2023,
    drinkTo: 2029,
    image: "/images/vinea-label.jpg",
    example: true,
  },
  {
    id: "mv_cellar_terre_alte_2017",
    producer: "Terre Alte",
    wine: "Terre Alte Riserva",
    denomination: "Taurasi DOCG",
    vintage: 2017,
    quantity: 2,
    referenceValueCents: 5200,
    status: "cantina_pubblica",
    phase: "attesa",
    drinkFrom: 2027,
    drinkTo: 2038,
    image: "/images/vinea-capsule.jpg",
    example: true,
  },
];

export const marketValidationCellarPhaseLabel = (
  phase: MarketValidationCellarBottle["phase"],
): string => phaseLabel[phase];

/**
 * Posizione dell'anno di riferimento dentro la finestra di bevuta, da 0 a 100:
 * 0 prima dell'apertura della finestra, 100 alla sua chiusura o oltre.
 */
export function marketValidationCellarMaturityPercent(
  bottle: Pick<MarketValidationCellarBottle, "drinkFrom" | "drinkTo">,
  year: number = MARKET_VALIDATION_CELLAR_REFERENCE_YEAR,
): number {
  const span = bottle.drinkTo - bottle.drinkFrom;
  if (span <= 0) return year >= bottle.drinkTo ? 100 : 0;
  const ratio = (year - bottle.drinkFrom) / span;
  return Math.round(Math.min(1, Math.max(0, ratio)) * 100);
}

const READY_PHASES = new Set<DrinkPhase>(["pronto", "ideale"]);

export type MarketValidationCellarKpis = Readonly<{
  bottles: number;
  referenceValueCents: number;
  forSale: number;
  readyToDrink: number;
}>;

/** I KPI dell'esempio derivano dalle bottiglie dell'esempio, non da un altro numero. */
export function marketValidationCellarKpis(
  bottles: readonly MarketValidationCellarBottle[] = MARKET_VALIDATION_CELLAR_BOTTLES,
): MarketValidationCellarKpis {
  return bottles.reduce<MarketValidationCellarKpis>(
    (totals, bottle) => ({
      bottles: totals.bottles + bottle.quantity,
      referenceValueCents:
        totals.referenceValueCents + bottle.quantity * bottle.referenceValueCents,
      forSale: totals.forSale + (bottle.status === "in_vendita" ? bottle.quantity : 0),
      readyToDrink: totals.readyToDrink + (READY_PHASES.has(bottle.phase) ? bottle.quantity : 0),
    }),
    { bottles: 0, referenceValueCents: 0, forSale: 0, readyToDrink: 0 },
  );
}

/** Quante etichette d'esempio ci sono per ciascuno stato di visibilità. */
export function marketValidationCellarStatusCounts(
  bottles: readonly MarketValidationCellarBottle[] = MARKET_VALIDATION_CELLAR_BOTTLES,
): Record<MarketValidationCellarStatus, number> {
  return {
    in_vendita: bottles.filter((bottle) => bottle.status === "in_vendita").length,
    privata: bottles.filter((bottle) => bottle.status === "privata").length,
    cantina_pubblica: bottles.filter((bottle) => bottle.status === "cantina_pubblica").length,
  };
}

export type MarketValidationCellarDrinkWindow = Readonly<{
  drinkNow: number;
  drinkSoon: number;
  wait: number;
  plannedOpenings: number;
}>;

/** Gli stessi quattro riquadri della Cantina reale, contati sull'esempio. */
export function marketValidationCellarDrinkWindow(
  bottles: readonly MarketValidationCellarBottle[] = MARKET_VALIDATION_CELLAR_BOTTLES,
): MarketValidationCellarDrinkWindow {
  return {
    drinkNow: bottles.filter((bottle) => READY_PHASES.has(bottle.phase)).length,
    drinkSoon: bottles.filter((bottle) => bottle.phase === "presto").length,
    wait: bottles.filter((bottle) => bottle.phase === "attesa").length,
    plannedOpenings: bottles.filter((bottle) => bottle.plannedOpening).length,
  };
}

/**
 * Serie d'esempio del valore della Cantina: è il valore di riferimento della
 * Cantina d'esempio, non il prezzo di una singola bottiglia né un dato di
 * mercato. L'ultimo punto coincide con il KPI dell'esempio.
 */
export const MARKET_VALIDATION_CELLAR_VALUE_SERIES: ReadonlyArray<
  Readonly<{ month: string; valueCents: number }>
> = [
  { month: "mag", valueCents: 52100 },
  { month: "giu", valueCents: 53000 },
  { month: "lug", valueCents: 54600 },
  { month: "ago", valueCents: 54100 },
  { month: "set", valueCents: 56800 },
  { month: "ott", valueCents: marketValidationCellarKpis().referenceValueCents },
];

/** Tre preset estetici reali del configuratore, citati nella sezione 3D. */
export const MARKET_VALIDATION_CELLAR_THEMES = ["moderna", "classica", "rustica"] as const satisfies
  readonly EnvTheme[];

export type MarketValidationCellarTheme = (typeof MARKET_VALIDATION_CELLAR_THEMES)[number];

export const marketValidationCellarThemeLabel = (theme: MarketValidationCellarTheme): string =>
  THEME_LABELS[theme];
