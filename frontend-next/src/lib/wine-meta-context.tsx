"use client";

import { createContext, useCallback, useContext, type ReactNode } from "react";
import { getWineMeta, type WineVintageMeta } from "@/data/cellar";

/**
 * Sorgente dei metadati di bevuta per l'albero sottostante.
 *
 * Esiste perché `DrinkBadge`, `DrinkWindowSection` e `FoodPairingSection`
 * ricevono soltanto un `wineId` e cercavano il resto in una tabella costante.
 * Dalla 6c-2 quella tabella sta su `wines`, ma la firma dei componenti non
 * cambia: cambia solo da dove pesca la ricerca. Un contesto invece di una prop
 * evita di far attraversare i metadati a `WineCard`, che li usa senza saperlo
 * tramite `DrinkBadge`.
 *
 * SENZA PROVIDER SI COMPORTA COME PRIMA. Le pagine ancora su dati mock
 * (`/home`, `/community/[slug]`) mostrano vini di `src/data/wines.ts`, i cui id
 * stanno nella tabella mock: lì `getWineMeta` è la risposta giusta, e
 * montare il provider ovunque significherebbe una query su ogni pagina, anche
 * su quelle statiche. Assenza di provider = comportamento invariato.
 */
const Ctx = createContext<Record<string, WineVintageMeta> | null>(null);

export function WineMetaProvider({
  metaPerVino,
  children,
}: {
  metaPerVino: Record<string, WineVintageMeta>;
  children: ReactNode;
}) {
  return <Ctx.Provider value={metaPerVino}>{children}</Ctx.Provider>;
}

/**
 * Ricerca riutilizzabile, per chi deve leggere i metadati di molti vini dentro
 * un `useMemo` — dove un hook per vino non è chiamabile.
 */
export function useCercaMeta(): (wineId: string) => WineVintageMeta {
  const mappa = useContext(Ctx);
  return useCallback((wineId: string) => mappa?.[wineId] ?? getWineMeta(wineId), [mappa]);
}

/** Metadati di un vino solo. */
export function useWineMeta(wineId: string): WineVintageMeta {
  const mappa = useContext(Ctx);
  return mappa?.[wineId] ?? getWineMeta(wineId);
}
