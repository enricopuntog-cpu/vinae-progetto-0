import type { AnnuncioProprietario, ListingStato } from "@/services/listing-service";

/**
 * Cantina del Partner = catalogo commerciale (Blocco B).
 *
 * Il catalogo NON è una seconda fonte dei prodotti: è la lettura degli
 * annunci che il titolare ha già (`listings`, letti con la sua sessione). Non
 * contiene quantità né disponibilità inventate — il modello fisico di
 * giacenze, prenotazioni e disponibilità è il Blocco C — e non converte
 * nessuna bottiglia personale in prodotto.
 */

export const ETICHETTA_STATO_PRODOTTO: Record<ListingStato, string> = {
  bozza: "Bozza",
  in_revisione: "In revisione",
  modifiche_richieste: "Modifiche richieste",
  attivo: "In vetrina",
  riservato: "Riservato",
  sospeso: "Sospeso",
  scaduto: "Scaduto",
  venduto: "Venduto",
  rifiutato: "Rifiutato",
};

/** Ciò che la vetrina pubblica mostra oggi: gli annunci attivi. */
export const presentabile = (stato: ListingStato): boolean => stato === "attivo";

export type CatalogoCommerciale = {
  inVetrina: AnnuncioProprietario[];
  altri: AnnuncioProprietario[];
};

/** Divide gli annunci del titolare fra presentati in vetrina e tutti gli altri. */
export function catalogoCommerciale(annunci: readonly AnnuncioProprietario[]): CatalogoCommerciale {
  return {
    inVetrina: annunci.filter((a) => presentabile(a.stato)),
    altri: annunci.filter((a) => !presentabile(a.stato)),
  };
}
