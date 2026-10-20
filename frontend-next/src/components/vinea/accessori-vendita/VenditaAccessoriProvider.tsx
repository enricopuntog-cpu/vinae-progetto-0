"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { AnnuncioAccessorio, StatoVenditaAccessori } from "@/lib/accessori-vendita/annunci-accessori";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAnnunciAccessoriService } from "@/services/annunci-accessori-service";
import type { AnnunciAccessoriService } from "@/services/types";

/**
 * Stato condiviso della preparazione degli annunci Accessori (VPM-015B2).
 *
 * Carica una volta lo stato e l'elenco, così ogni scheda della Cantina non
 * interroga il database per conto proprio. Fail closed: se l'interruttore è
 * spento (default in produzione) o una lettura fallisce, lo stato resta nullo e
 * nessuna scheda mostra alcun comando.
 */

export type ContestoVenditaAccessori = {
  stato: StatoVenditaAccessori | null;
  annunci: readonly AnnuncioAccessorio[];
  servizio: AnnunciAccessoriService;
  ricarica: () => Promise<void>;
};

const Contesto = createContext<ContestoVenditaAccessori | null>(null);

export const useVenditaAccessori = (): ContestoVenditaAccessori | null => useContext(Contesto);

export function VenditaAccessoriProvider({ children }: { children: ReactNode }) {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizio = useMemo(() => creaAnnunciAccessoriService(client), [client]);
  const [stato, setStato] = useState<StatoVenditaAccessori | null>(null);
  const [annunci, setAnnunci] = useState<readonly AnnuncioAccessorio[]>([]);

  const ricarica = useCallback(async () => {
    const r = await servizio.elenco(false);
    if (r.ok) setAnnunci(r.data);
  }, [servizio]);

  useEffect(() => {
    let attivo = true;
    (async () => {
      const s = await servizio.stato();
      if (!attivo) return;
      if (!s.ok || !s.data.abilitata) {
        setStato(null);
        return;
      }
      const e = await servizio.elenco(false);
      if (!attivo) return;
      setAnnunci(e.ok ? e.data : []);
      setStato(s.data);
    })();
    return () => {
      attivo = false;
    };
  }, [servizio]);

  const valore = useMemo(
    () => ({ stato, annunci, servizio, ricarica }),
    [stato, annunci, servizio, ricarica],
  );
  return <Contesto.Provider value={valore}>{children}</Contesto.Provider>;
}
