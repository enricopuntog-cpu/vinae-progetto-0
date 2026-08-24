/**
 * Smart Sell Price — il prezzo suggerito del passo Prezzo di /vendi.
 *
 * QUESTO FILE NON CONTIENE UN ALGORITMO. È una composizione.
 *
 * La soglia, la mediana, il filtro vino/formato, la deduplica per annuncio e la
 * fascia di copertura vivono tutte in `./insights`, dove la 1B le ha decise e
 * dove sono testate. Qui si importano e si mettono in fila. Se domani la 1B
 * cambia la soglia o passa a un'altra statistica, /vendi cambia con lei senza
 * che nessuno tocchi questo file: è l'unica proprietà che vale la pena
 * difendere, e si difende non riscrivendo niente di ciò che sta di là.
 *
 * TRE COSE CHE QUESTO MODULO NON FA:
 *
 *   * non legge lo storico. Il suggerimento nasce dai comparabili ASKING
 *     correnti e basta — le vendite non hanno un canale per entrare qui, e
 *     l'assenza di un parametro `osservazioni` è il modo in cui la regola è
 *     imposta invece che ricordata;
 *   * non produce un numero sotto soglia. Sotto tre comparabili non esce un
 *     suggerimento più prudente: non esce un suggerimento;
 *   * non compila niente. Restituisce un valore; chi lo mette nel campo prezzo
 *     è un gesto dell'utente, non una conseguenza di questa funzione.
 *
 * Il nome che l'interfaccia deve usare è «prezzo suggerito Vinea»: non
 * quotazione, non valore reale, non prezzo garantito, non AI price. È la
 * mediana di ciò che si sta chiedendo adesso su Vinea per lo stesso vino nello
 * stesso formato — nient'altro, e va detto così.
 */

import type { Wine } from "@/data/wines";
import type { Result } from "@/services/types";
import {
  chiaveVino,
  comparabiliAttivi,
  copertura,
  riferimentoRichieste,
  SOGLIA_COMPARABILI,
  type AnnuncioComparabile,
  type Copertura,
} from "./insights";

/**
 * Gli stati possibili del suggerimento, e sono tre perché tre sono le cose
 * diverse che si possono dire.
 *
 * `non_disponibile` non è `insufficiente` con zero comparabili: «non ho potuto
 * chiedere» e «ho chiesto e non ce ne sono» sono affermazioni diverse, e
 * confonderle significherebbe dire a un venditore che il suo vino non ha
 * mercato quando in realtà è caduta una lettura.
 */
export type SmartSellPrice =
  | { stato: "non_disponibile" }
  | { stato: "insufficiente"; comparabili: number; soglia: number }
  | {
      stato: "suggerito";
      comparabili: number;
      soglia: number;
      /** La mediana della 1B. Non arrotondata, non corretta, non pesata. */
      medianaCents: number;
      minimoCents: number;
      massimoCents: number;
      copertura: Copertura;
    };

/**
 * Da annuncio pubblico attivo a candidato al confronto.
 *
 * Stessa riduzione che `/annuncio/[id]` fa per il pannello 1B, compresa la
 * `chiave`: l'identità dell'ANNUNCIO (`listingId`), non quella del vino, perché
 * è ciò su cui `comparabiliAttivi` deduplica.
 */
export const annuncioComparabile = (w: Wine): AnnuncioComparabile => ({
  chiave: w.listingId ?? w.id,
  wineKey: chiaveVino(w),
  formato: w.formato,
  prezzoCents: Math.round(w.prezzo * 100),
});

/**
 * Traduce la lettura degli annunci nello stato corretto del suggerimento.
 *
 * Il ramo fallito resta `non_disponibile`: non raggiunge `smartSellPrice` e non
 * può quindi diventare falsamente «0 comparabili». Il dettaglio dell'errore non
 * viene copiato nello stato destinato all'interfaccia.
 */
export const smartSellPriceDaLettura = (input: {
  esito: Result<Wine[]>;
  wineKey: string;
  formato: string;
}): SmartSellPrice => {
  if (!input.esito.ok) return { stato: "non_disponibile" };

  return smartSellPrice({
    annunciAttivi: input.esito.data.map(annuncioComparabile),
    wineKey: input.wineKey,
    formato: input.formato,
  });
};

/**
 * Il suggerimento per una bottiglia che sta per essere messa in vendita.
 *
 * `annunciAttivi` arriva dall'esito riuscito di
 * `ListingService.elencoConEsito()`, che legge `public_listings` — dove il filtro
 * `stato = 'attivo'` è dentro la vista e non un parametro. «Attivo» qui non è un
 * predicato da riscrivere: è una proprietà della sorgente, e l'unico modo di
 * sbagliarlo sarebbe allargare la sorgente.
 *
 * La bottiglia che si sta vendendo non è ancora un annuncio, quindi non entra
 * nel proprio campione. Un *altro* annuncio attivo dello stesso venditore sì:
 * è la stessa scelta della 1B sulla pagina annuncio, dove il campione è «ciò
 * che è pubblicato», non «ciò che hanno pubblicato gli altri».
 */
export const smartSellPrice = (input: {
  annunciAttivi: readonly AnnuncioComparabile[];
  wineKey: string;
  formato: string;
}): SmartSellPrice => {
  const comparabili = comparabiliAttivi(input.annunciAttivi, {
    wineKey: input.wineKey,
    formato: input.formato,
  });

  const riferimento = riferimentoRichieste(comparabili);

  if (!riferimento.disponibile) {
    return {
      stato: "insufficiente",
      comparabili: riferimento.comparabili,
      soglia: SOGLIA_COMPARABILI,
    };
  }

  return {
    stato: "suggerito",
    comparabili: riferimento.comparabili,
    soglia: SOGLIA_COMPARABILI,
    medianaCents: riferimento.medianaCents,
    minimoCents: riferimento.minimoCents,
    massimoCents: riferimento.massimoCents,
    copertura: copertura(riferimento.comparabili),
  };
};
