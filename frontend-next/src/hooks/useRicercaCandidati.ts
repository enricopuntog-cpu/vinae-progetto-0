"use client";

// WI-006A — stato di una ricerca di vini candidati, condiviso dal percorso
// fotografico (WI-002) e dalla ricerca manuale del wizard. Una responsabilità:
// chiedere alla sorgente, tenere l'esito e la scelta dell'utente. Non scrive
// nel wizard: la conferma resta di chi usa l'hook.

import { useCallback, useRef, useState } from "react";
import type {
  CandidatoValutato,
  DomandaCandidati,
  SintesiRicerca,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { cercaCorrispondenze } from "@/lib/vendi/foto-etichetta/pipeline";

export type FaseRicerca = "ferma" | "in_corso" | "fatta" | "errore";

export function useRicercaCandidati(sorgente: SorgenteCandidati) {
  const [fase, setFase] = useState<FaseRicerca>("ferma");
  const [candidati, setCandidati] = useState<CandidatoValutato[]>([]);
  const [sintesi, setSintesi] = useState<SintesiRicerca | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [selezionato, setSelezionato] = useState<string | null>(null);
  // Una risposta arrivata dopo un'altra richiesta o un azzeramento non conta.
  const generazione = useRef(0);

  const azzera = useCallback(() => {
    generazione.current++;
    setFase("ferma");
    setCandidati([]);
    setSintesi(null);
    setMessaggio(null);
    setSelezionato(null);
  }, []);

  const cerca = useCallback(
    async (domanda: DomandaCandidati) => {
      const mia = ++generazione.current;
      setFase("in_corso");
      setMessaggio(null);
      setSelezionato(null);
      const esito = await cercaCorrispondenze(domanda, sorgente).catch(() => ({
        ok: false as const,
        messaggio: "Ricerca non riuscita.",
      }));
      if (mia !== generazione.current) return;
      if (!esito.ok) {
        setFase("errore");
        setCandidati([]);
        setSintesi(null);
        setMessaggio(esito.messaggio);
        return;
      }
      setCandidati(esito.candidati);
      setSintesi(esito.sintesi);
      setFase("fatta");
    },
    [sorgente],
  );

  const seleziona = useCallback((id: string | null) => setSelezionato(id), []);

  return { fase, candidati, sintesi, messaggio, selezionato, cerca, azzera, seleziona };
}

export type StatoRicercaCandidati = ReturnType<typeof useRicercaCandidati>;
