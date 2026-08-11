// Fase 10c — dagli identificativi proposti dall'AI agli annunci da mostrare.
//
// In `frontend/` la risoluzione è `wines.find((x) => x.id === p.wine_id)`
// (`frontend/src/routes/esplora.tsx:397`), dove `wines` è il file statico che
// il browser aveva appena mandato al modello: l'identificativo tornava sempre,
// perché il client stava cercando qualcosa che aveva scritto lui.
//
// Con la decisione 7.8 il catalogo lo risolve il server da `public_listings`
// (`supabase/functions/ai-pairing/index.ts`), quindi l'identificativo proposto
// è la **chiave primaria dell'annuncio**, non lo slug. Nel frontend `Wine.id`
// è invece lo slug (`frontend-next/src/services/listing-service.ts:154`) e
// l'UUID sta in `Wine.listingId` (`:155`): la coppia `listingId ?? id` è
// l'idioma già usato altrove per questa stessa distinzione
// (`frontend-next/src/app/annuncio/[id]/page-client.tsx:257`).
//
// Un identificativo che non trova l'annuncio viene lasciato cadere invece di
// generare una scheda vuota. Non dovrebbe succedere — `scelteValide` nella
// function scarta già tutto ciò che non è nel catalogo che ha letto lei — ma
// fra quella lettura e questa pagina passa il tempo di una richiesta, e un
// annuncio può essere stato ritirato nel mezzo.

import type { Wine } from "@/data/wines";
import type { AbbinamentoScelta } from "@/services/types";

export type SceltaRisolta = {
  annuncio: Wine;
  motivazione: string;
};

export const risolviScelte = (
  scelte: readonly AbbinamentoScelta[],
  annunci: readonly Wine[],
): SceltaRisolta[] => {
  const perIdentificativo = new Map<string, Wine>();
  for (const annuncio of annunci) {
    perIdentificativo.set(annuncio.listingId ?? annuncio.id, annuncio);
    // Anche lo slug, così la risoluzione regge se un giorno la function
    // proponesse quello: costa una voce di mappa e toglie un modo di rompersi.
    if (!perIdentificativo.has(annuncio.id)) perIdentificativo.set(annuncio.id, annuncio);
  }

  const risolte: SceltaRisolta[] = [];
  const viste = new Set<string>();
  for (const scelta of scelte) {
    const annuncio = perIdentificativo.get(scelta.annuncioId);
    if (!annuncio || viste.has(annuncio.id)) continue;
    viste.add(annuncio.id);
    risolte.push({ annuncio, motivazione: scelta.motivazione });
  }
  return risolte;
};
