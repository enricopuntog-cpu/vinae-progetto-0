import type { MarketValidationCellarStatus } from "./cellar-preview";

/**
 * Demo interna del percorso Vendi dentro la guida Market Validation.
 *
 * Ricalca i passaggi del vero `/vendi` — foto, catalogazione con l'assistente
 * AI, scelta fra Cantina privata, profilo e vendita, riepilogo — senza aprire
 * il sito: nessun account, nessun upload, nessun annuncio, nessun salvataggio.
 * Bottiglie e «suggerimenti AI» sono fixture statiche: nessun provider viene
 * chiamato. Le tre destinazioni usano le stesse parole delle opzioni di `/vendi`.
 */

export const MARKET_VALIDATION_SELL_DEMO_VERSION = "mv-sell-demo-2026-10-07" as const;

export type MarketValidationSellDemoBottle = Readonly<{
  id: `mv_sell_${string}`;
  image: `/images/${string}`;
  photoLabel: string;
  /** Campi che l'assistente AI d'esempio propone: il tester li vede, non li scrive. */
  suggestion: Readonly<{
    producer: string;
    wine: string;
    denomination: string;
    vintage: number;
    region: string;
    format: "0,75 L" | "1,5 L";
  }>;
  examplePriceCents: number;
  example: true;
}>;

/** Produttori e vini fittizi, come gli annunci demo del percorso Acquista. */
export const MARKET_VALIDATION_SELL_DEMO_BOTTLES: readonly MarketValidationSellDemoBottle[] = [
  {
    id: "mv_sell_vigna_mattino_2019",
    image: "/images/vinea-bottle-2.jpg",
    photoLabel: "Rosso in cantina",
    suggestion: {
      producer: "Podere Colle Chiaro",
      wine: "Vigna del Mattino",
      denomination: "Langhe Nebbiolo DOC",
      vintage: 2019,
      region: "Piemonte",
      format: "0,75 L",
    },
    examplePriceCents: 4800,
    example: true,
  },
  {
    id: "mv_sell_sorgente_bianca_2022",
    image: "/images/vinea-white.jpg",
    photoLabel: "Bianco fresco",
    suggestion: {
      producer: "Tenuta Sorgente",
      wine: "Sorgente Bianca",
      denomination: "Soave Classico DOC",
      vintage: 2022,
      region: "Veneto",
      format: "0,75 L",
    },
    examplePriceCents: 2400,
    example: true,
  },
  {
    id: "mv_sell_bollicine_collina_2018",
    image: "/images/vinea-champagne.jpg",
    photoLabel: "Metodo classico",
    suggestion: {
      producer: "Cantina Collina Alta",
      wine: "Bollicine di Collina",
      denomination: "Franciacorta DOCG",
      vintage: 2018,
      region: "Lombardia",
      format: "0,75 L",
    },
    examplePriceCents: 4200,
    example: true,
  },
];

export const MARKET_VALIDATION_SELL_DEMO_FIELDS = [
  ["producer", "Produttore"],
  ["wine", "Nome / Etichetta"],
  ["denomination", "Denominazione"],
  ["vintage", "Annata"],
  ["region", "Regione"],
  ["format", "Formato"],
] as const satisfies ReadonlyArray<
  readonly [keyof MarketValidationSellDemoBottle["suggestion"], string]
>;

/** Le tre scelte di `/vendi`, con le stesse etichette e descrizioni. */
export const MARKET_VALIDATION_SELL_DEMO_DESTINATIONS: ReadonlyArray<
  Readonly<{
    status: MarketValidationCellarStatus;
    title: string;
    text: string;
    outcome: string;
  }>
> = [
  {
    status: "privata",
    title: "Aggiungi alla cantina privata",
    text: "Solo tu la vedi. Nessun prezzo obbligatorio.",
    outcome: "La bottiglia entra nella tua Cantina privata: la vedi solo tu.",
  },
  {
    status: "cantina_pubblica",
    title: "Mostra nella cantina pubblica",
    text: "Appare sul tuo profilo, senza essere in vendita.",
    outcome: "La bottiglia compare nel tuo profilo, senza essere in vendita.",
  },
  {
    status: "in_vendita",
    title: "Pubblica in vendita",
    text: "Attivi prezzo, spedizione e proposte.",
    outcome: "La bottiglia diventa un annuncio con prezzo, spedizione e proposte.",
  },
];

export const MARKET_VALIDATION_SELL_DEMO_STEPS = [
  "Foto",
  "Assistente AI",
  "Destinazione",
  "Riepilogo",
] as const;
