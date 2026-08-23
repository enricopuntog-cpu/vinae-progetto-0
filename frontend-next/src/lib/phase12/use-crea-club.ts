"use client";

// Stessa forma di `use-club-follow`: il comando e `null` quando Supabase non e
// configurato, invece di esistere e non fare niente.

import { useCallback, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
import { creaClub, type BozzaClub } from "@/lib/phase12/crea-club";
import type { Club } from "@/services/types";

export type CreaClubState = {
  // Restituisce il club creato, o null se qualcosa e fallito: l'errore sta in
  // `error`, come nelle altre due azioni dei club.
  crea: ((bozza: BozzaClub) => Promise<Club | null>) | null;
  inCorso: boolean;
  error: string | null;
};

export const useCreaClub = (): CreaClubState => {
  const client = getSupabaseClient();
  const service = useMemo(() => createSupabaseClubService(client), [client]);
  const [inCorso, setInCorso] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const esegui = useCallback(
    async (bozza: BozzaClub): Promise<Club | null> => {
      setInCorso(true);
      setError(null);
      const esito = await creaClub(bozza, service);
      setInCorso(false);
      if (!esito.ok) {
        setError(esito.error);
        return null;
      }
      return esito.data;
    },
    [service],
  );

  return { crea: client ? esegui : null, inCorso, error };
};
