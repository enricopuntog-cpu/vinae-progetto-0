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
 * La Cantina è una scoperta facoltativa: non è un percorso del test, non ha
 * un evento e non entra nel conteggio «0 di 2».
 */

export const MARKET_VALIDATION_CELLAR_PREVIEW_VERSION = "mv-cellar-2026-10-07" as const;

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
    plannedOpening: "31 dicembre",
    example: true,
  },
];

export const marketValidationCellarPhaseLabel = (
  phase: MarketValidationCellarBottle["phase"],
): string => phaseLabel[phase];

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
  { month: "mag", valueCents: 41200 },
  { month: "giu", valueCents: 42000 },
  { month: "lug", valueCents: 43100 },
  { month: "ago", valueCents: 42600 },
  { month: "set", valueCents: 44800 },
  { month: "ott", valueCents: marketValidationCellarKpis().referenceValueCents },
];

/** Tre preset estetici reali del configuratore; cambiano solo l'anteprima. */
export const MARKET_VALIDATION_CELLAR_THEMES = ["moderna", "classica", "rustica"] as const satisfies
  readonly EnvTheme[];

export type MarketValidationCellarTheme = (typeof MARKET_VALIDATION_CELLAR_THEMES)[number];

export const marketValidationCellarThemeLabel = (theme: MarketValidationCellarTheme): string =>
  THEME_LABELS[theme];
