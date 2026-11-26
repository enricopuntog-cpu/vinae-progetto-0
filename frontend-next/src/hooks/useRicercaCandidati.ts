"use client";

// WI-006A — stato di una ricerca di vini candidati, condiviso dal percorso
// fotografico (WI-002) e dalla ricerca manuale del wizard. Una responsabilità:
// chiedere alla sorgente, tenere l'esito e la scelta dell'utente. Non scrive
// nel wizard: la conferma resta di chi usa l'hook.

import { useCallback, useRef, useState } from "react";
import type {
  CandidatoValutato,
  CatalogoIncompleto,
  DomandaCandidati,
  SintesiRicerca,
  SorgenteCandidati,
} from "@/lib/vendi/foto-etichetta/candidati";
import { cercaCorrispondenze } from "@/lib/vendi/foto-etichetta/pipeline";
import { ATTESA_CATALOGO_RIPROVA_MS } from "@/lib/vendi/ricerca-vini/canonico";

export type FaseRicerca = "ferma" | "in_corso" | "fatta" | "errore";

export function useRicercaCandidati(sorgente: SorgenteCandidati) {
  const [fase, setFase] = useState<FaseRicerca>("ferma");
  const [candidati, setCandidati] = useState<CandidatoValutato[]>([]);
  const [sintesi, setSintesi] = useState<SintesiRicerca | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [selezionato, setSelezionato] = useState<string | null>(null);
  // WI-009: i risultati sono solo quelli della fonte principale, e l elenco deve dirlo.
  const [catalogoIncompleto, setCatalogoIncompleto] = useState<CatalogoIncompleto | null>(null);
  const ultima = useRef<DomandaCandidati | null>(null);
  // Una risposta arrivata dopo un'altra richiesta o un azzeramento non conta.
  const generazione = useRef(0);

  const azzera = useCallback(() => {
    generazione.current++;
    setFase("ferma");
    setCandidati([]);
    setSintesi(null);
    setMessaggio(null);
    setSelezionato(null);
    setCatalogoIncompleto(null);
    ultima.current = null;
  }, []);

  const esegui = useCallback(
    async (domanda: DomandaCandidati, attesaCatalogoMs?: number) => {
      const mia = ++generazione.current;
      ultima.current = domanda;
      let incompleto: CatalogoIncompleto | null = null;
      setCatalogoIncompleto(null);
      setFase("in_corso");
      setMessaggio(null);
      setSelezionato(null);
      const esito = await cercaCorrispondenze(domanda, sorgente, {
        ...(attesaCatalogoMs ? { attesaCatalogoMs } : {}),
        onCatalogoIncompleto: (motivo) => {
          incompleto = motivo;
        },
      }).catch(() => ({
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
      setCatalogoIncompleto(incompleto);
      setFase("fatta");
    },
    [sorgente],
  );

  const cerca = useCallback((domanda: DomandaCandidati) => esegui(domanda), [esegui]);
  /** La stessa domanda con un attesa del catalogo più lunga: parte solo su richiesta dell utente. */
  const riprovaCatalogo = useCallback(
    () => (ultima.current ? esegui(ultima.current, ATTESA_CATALOGO_RIPROVA_MS) : Promise.resolve()),
    [esegui],
  );

  const seleziona = useCallback((id: string | null) => setSelezionato(id), []);

  return { fase, candidati, sintesi, messaggio, selezionato, catalogoIncompleto, cerca, riprovaCatalogo, azzera, seleziona };
}

export type StatoRicercaCandidati = ReturnType<typeof useRicercaCandidati>;
