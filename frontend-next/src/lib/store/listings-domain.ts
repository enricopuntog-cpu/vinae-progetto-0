"use client";

import { useCallback, useState } from "react";
import { toast } from "sonner";

export function useListingsDomain() {
  const [favorites, setFavorites] = useState<Set<string>>(new Set(["sassicaia-2018"]));
  const [follows, setFollows] = useState<Set<string>>(new Set(["Marco B."]));
  const [proposte, setProposte] = useState<Record<string, number>>({});

  const toggleFavorite = useCallback((id: string) => {
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
        toast("Rimosso dai preferiti");
      } else {
        next.add(id);
        toast.success("Aggiunto ai preferiti");
      }
      return next;
    });
  }, []);

  const toggleFollow = useCallback((nome: string) => {
    setFollows((prev) => {
      const next = new Set(prev);
      if (next.has(nome)) {
        next.delete(nome);
        toast(`Non segui più ${nome}`);
      } else {
        next.add(nome);
        toast.success(`Ora segui ${nome}`);
      }
      return next;
    });
  }, []);

  const proponi = useCallback((wineId: string, prezzo: number) => {
    setProposte((p) => ({ ...p, [wineId]: prezzo }));
    toast.success(`Proposta inviata: € ${prezzo.toLocaleString("it-IT")}`);
  }, []);

  const recordProposalPrice = useCallback((wineId: string, price: number) => {
    setProposte((current) => ({ ...current, [wineId]: price }));
  }, []);

  return {
    favorites,
    follows,
    proposte,
    toggleFavorite,
    toggleFollow,
    proponi,
    recordProposalPrice,
  };
}