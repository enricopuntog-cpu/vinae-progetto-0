"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaIndirizziService } from "@/services/indirizzi-service";
import type { Indirizzo, IndirizzoInput, Result } from "@/services/types";

/**
 * Stato della rubrica del chiamante, unico per pannello, checkout e vendita.
 *
 * Dopo ogni scrittura si rilegge la rubrica dal database invece di correggerla
 * a mano: la porta toglie il predefinito agli altri indirizzi, e la sola copia
 * attendibile di quell'effetto è la lettura successiva.
 */
export function useRubrica() {
  const service = useMemo(() => creaIndirizziService(getSupabaseClient()), []);
  const [indirizzi, setIndirizzi] = useState<Indirizzo[] | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [caricamento, setCaricamento] = useState(true);

  const ricarica = useCallback(async () => {
    setCaricamento(true);
    const esito = await service.miei();
    setCaricamento(false);
    if (esito.ok) {
      setIndirizzi(esito.data);
      setErrore(null);
    } else {
      setErrore(esito.error);
    }
    return esito;
  }, [service]);

  useEffect(() => {
    let attivo = true;
    void service.miei().then((esito) => {
      if (!attivo) return;
      setCaricamento(false);
      if (esito.ok) setIndirizzi(esito.data);
      else setErrore(esito.error);
    });
    return () => {
      attivo = false;
    };
  }, [service]);

  const salva = useCallback(
    async (id: string | null, dati: IndirizzoInput): Promise<Result<Indirizzo>> => {
      const esito = await service.salva(id, dati);
      if (esito.ok) await ricarica();
      return esito;
    },
    [service, ricarica],
  );

  const archivia = useCallback(
    async (id: string): Promise<Result<void>> => {
      const esito = await service.archivia(id);
      if (esito.ok) await ricarica();
      return esito;
    },
    [service, ricarica],
  );

  return { indirizzi, errore, caricamento, salva, archivia, ricarica, service };
}
