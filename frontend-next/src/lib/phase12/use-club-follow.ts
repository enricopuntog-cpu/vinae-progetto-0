"use client";

// Fase 12a - la sola azione client dei club: seguire e smettere di seguire.
//
// La lettura non passa di qui. I club li legge il componente server e li
// consegna come prop, come fa /annuncio/[id] con l'annuncio: e cio che evita
// uno scheletro al primo paint su una pagina pubblica, e toglie di mezzo
// l'effetto di caricamento insieme alla classe di difetti che 10c ha pagato
// (marcatore in stato, cleanup che annulla la richiesta appena partita).
//
// `cambiaFollow` e null quando Supabase non e configurato: il comando non
// esiste, invece di esistere e non fare niente. Un pulsante che accetta il
// clic e non scrive e peggio di un pulsante spento.

import { useCallback, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
import type { Club } from "@/services/types";

export type ClubFollowState = {
  disponibile: boolean;
  // Restituisce il club riletto dal server, o null se la scrittura e fallita.
  // Il chiamante decide cosa farne: la pagina elenco sostituisce una riga, la
  // pagina di dettaglio sostituisce il club intero.
  cambiaFollow: ((club: Club) => Promise<Club | null>) | null;
  inCorso: string | null;
  error: string | null;
};

export const useClubFollow = (): ClubFollowState => {
  const client = getSupabaseClient();
  const service = useMemo(() => createSupabaseClubService(client), [client]);
  const [inCorso, setInCorso] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const cambiaFollow = useCallback(
    async (club: Club): Promise<Club | null> => {
      setInCorso(club.slug);
      setError(null);
      // Lo stato desiderato si ricava dal club che il chiamante ha in mano, non
      // da un booleano separato: due fonti per la stessa cosa divergono al
      // primo doppio clic.
      const esito = club.seguito
        ? await service.smettiSegui(club.slug)
        : await service.segui(club.slug);
      setInCorso(null);
      if (!esito.ok) {
        setError(esito.error);
        return null;
      }
      return esito.data;
    },
    [service],
  );

  return {
    disponibile: Boolean(client),
    cambiaFollow: client ? cambiaFollow : null,
    inCorso,
    error,
  };
};
