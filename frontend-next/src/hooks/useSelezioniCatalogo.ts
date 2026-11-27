"use client";

// WI-008 — le scelte di scheda del catalogo dell'utente, lette una volta per elenco della Cantina. Un cambio di utente
// azzera subito: le scelte di uno non restano a schermo per un altro.

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { NESSUNA_SELEZIONE, leggiSelezioniCatalogo, type SelezioniCatalogo } from "@/lib/cantina/selezione-catalogo";
import { proposteDisponibili } from "@/lib/cantina/proposta-catalogo";

export function useSelezioniCatalogo(utenteId: string | null) {
  const client = useMemo(() => getSupabaseClient(), []);
  const [letto, setLetto] = useState<{ utente: string; stato: SelezioniCatalogo } | null>(null);
  // WI-011: proposte al catalogo, spente di default; una lettura sola per elenco.
  const [proposte, setProposte] = useState<string | null>(null);
  // WI-016: richieste di verifica di una bottiglia, spente di default.
  const [verifiche, setVerifiche] = useState<string | null>(null);

  useEffect(() => {
    if (!client || !utenteId) return;
    let annullato = false;
    void leggiSelezioniCatalogo(client).then((stato) => {
      if (!annullato) setLetto({ utente: utenteId, stato });
    });
    void proposteDisponibili(client).then((attive) => {
      if (!annullato) setProposte(attive ? utenteId : null);
    });
    // fail-closed: solo un `true` esatto mostra il comando
    void Promise.resolve(client.rpc("cellar_verifica_autenticita_disponibile")).then(
      ({ data, error }) => {
        if (!annullato) setVerifiche(!error && data === true ? utenteId : null);
      },
      () => {},
    );
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
  return {
    client,
    stato,
    cambia,
    proposteAttive: utenteId !== null && proposte === utenteId,
    verificheAttive: utenteId !== null && verifiche === utenteId,
  };
}
