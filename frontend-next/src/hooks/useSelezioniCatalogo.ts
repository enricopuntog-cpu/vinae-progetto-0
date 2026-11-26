"use client";

// WI-008 — le scelte di scheda del catalogo dell'utente, lette una volta per elenco della Cantina. Un cambio di utente
// azzera subito: le scelte di uno non restano a schermo per un altro.

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { NESSUNA_SELEZIONE, leggiSelezioniCatalogo, type SelezioniCatalogo } from "@/lib/cantina/selezione-catalogo";

export function useSelezioniCatalogo(utenteId: string | null) {
  const client = useMemo(() => getSupabaseClient(), []);
  const [letto, setLetto] = useState<{ utente: string; stato: SelezioniCatalogo } | null>(null);

  useEffect(() => {
    if (!client || !utenteId) return;
    let annullato = false;
    void leggiSelezioniCatalogo(client).then((stato) => {
      if (!annullato) setLetto({ utente: utenteId, stato });
    });
    return () => {
      annullato = true;
    };
  }, [client, utenteId]);

  const cambia = useCallback((wineSlug: string, lwin7: string | null) => {
    setLetto((precedente) => {
      if (!precedente) return precedente;
      const scelte = { ...precedente.stato.scelte };
      if (lwin7) scelte[wineSlug] = lwin7;
      else delete scelte[wineSlug];
      return { ...precedente, stato: { ...precedente.stato, scelte } };
    });
  }, []);

  const stato = letto && letto.utente === utenteId ? letto.stato : NESSUNA_SELEZIONE;
  return { client, stato, cambia };
}
