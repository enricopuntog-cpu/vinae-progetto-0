import type { MarketValidationPriceBand } from "./contract";

export const MARKET_VALIDATION_DEMO_DATASET_VERSION = "mv1-2026-10-03" as const;

export type MarketValidationDemoListing = Readonly<{
  id: `mv_demo_${string}`;
  producer: string;
  wine: string;
  vintage: number;
  format: "0,75 L" | "1,5 L";
  condition: "Ottima" | "Buona";
  price_cents: number;
  image: `/images/${string}`;
  price_band: MarketValidationPriceBand;
  validation_demo: true;
}>;

/**
 * Fixture versionata e non commerciale. Questi record non sono righe di
 * `public.listings`, non hanno un venditore e non possono diventare ordini.
 * MV2 estenderà lo stesso contratto senza cambiare il confine.
 */
export const MARKET_VALIDATION_DEMO_LISTINGS = [
  {
    id: "mv_demo_barbera_2019",
    producer: "Cantina esempio",
    wine: "Barbera d'Asti",
    vintage: 2019,
    format: "0,75 L",
    condition: "Ottima",
    price_cents: 2400,
    image: "/images/vinea-bottle-1.jpg",
    price_band: "15–30",
    validation_demo: true,
  },
  {
    id: "mv_demo_brunello_2017",
    producer: "Tenuta esempio",
    wine: "Brunello di Montalcino",
    vintage: 2017,
    format: "0,75 L",
    condition: "Ottima",
    price_cents: 7200,
    image: "/images/vinea-bottle-2.jpg",
    price_band: "60–100",
    validation_demo: true,
  },
  {
    id: "mv_demo_champagne_magnum",
    producer: "Maison esempio",
    wine: "Champagne Brut",
    vintage: 2015,
    format: "1,5 L",
    condition: "Buona",
    price_cents: 22500,
    image: "/images/vinea-champagne.jpg",
    price_band: "200+",
    validation_demo: true,
  },
] as const satisfies readonly MarketValidationDemoListing[];
