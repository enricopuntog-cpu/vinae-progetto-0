"use client";

// Fase 12b - le azioni client sui contenuti di un club.
//
// Stessa forma di use-club-follow.ts, e per le stesse ragioni. La LETTURA
// dell'elenco non passa di qui: i post li legge il componente server e li
// consegna come prop, che e cio che evita uno scheletro al primo paint su una
// pagina pubblica e toglie di mezzo l'effetto di caricamento insieme alla
// classe di difetti che 10c ha pagato (marcatore in stato, cleanup che annulla
// la richiesta appena partita).
//
// Le risposte fanno eccezione e si leggono qui, ma solo su richiesta: sono
// dietro un "mostra le risposte", quindi non esistono al primo paint e
// caricarle tutte in anticipo vorrebbe dire leggere l'intero club per mostrarne
// una parte. La lettura e comandata da un clic, non da un effetto - che e
// esattamente la differenza che 10c aveva individuato.
//
// I comandi sono `null` quando Supabase non e configurato: il comando non
// esiste, invece di esistere e non fare niente. Un pulsante che accetta il clic
// e non scrive e peggio di un pulsante spento.

import { useCallback, useMemo, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
import type { ClubPost, ClubPostRisposta, NuovoClubPost } from "@/services/types";

export type ClubPostsState = {
  disponibile: boolean;
  // Lo slug del post o del comando in corso, per spegnere il solo pulsante che
  // sta lavorando invece dell'intera pagina.
  inCorso: string | null;
  error: string | null;
  azzeraErrore: () => void;
  pubblica: ((input: NuovoClubPost) => Promise<ClubPost | null>) | null;
  rispondi: ((postId: string, corpo: string) => Promise<ClubPostRisposta | null>) | null;
  cambiaLike: ((post: ClubPost) => Promise<ClubPost | null>) | null;
  leggiRisposte: (postId: string) => Promise<ClubPostRisposta[] | null>;
};

export const useClubPosts = (): ClubPostsState => {
  const client = getSupabaseClient();
  const service = useMemo(() => createSupabaseClubService(client), [client]);
  const [inCorso, setInCorso] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const azzeraErrore = useCallback(() => setError(null), []);

  const pubblica = useCallback(
    async (input: NuovoClubPost): Promise<ClubPost | null> => {
      setInCorso("nuovo");
      setError(null);
      const esito = await service.creaDiscussione(input);
      setInCorso(null);
      if (!esito.ok) {
        setError(esito.error);
        return null;
      }
      return esito.data;
    },
    [service],
  );

  const rispondi = useCallback(
    async (postId: string, corpo: string): Promise<ClubPostRisposta | null> => {
      setInCorso(postId);
      setError(null);
      const esito = await service.creaRisposta(postId, corpo);
      setInCorso(null);
      if (!esito.ok) {
        setError(esito.error);
        return null;
      }
      return esito.data;
    },
    [service],
  );

  const cambiaLike = useCallback(
    async (post: ClubPost): Promise<ClubPost | null> => {
      setInCorso(post.id);
      setError(null);
      // Lo stato desiderato si ricava dal post che il chiamante ha in mano, non
      // da un booleano separato: due fonti per la stessa cosa divergono al
      // primo doppio clic. Stessa scelta di useClubFollow.
      const esito = post.piaciuto
        ? await service.togliLike(post.id)
        : await service.mettiLike(post.id);
      setInCorso(null);
      if (!esito.ok) {
        setError(esito.error);
        return null;
      }
      return esito.data;
    },
    [service],
  );

  const leggiRisposte = useCallback(
    async (postId: string): Promise<ClubPostRisposta[] | null> => {
      const esito = await service.risposte(postId);
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
    inCorso,
    error,
    azzeraErrore,
    pubblica: client ? pubblica : null,
    rispondi: client ? rispondi : null,
    cambiaLike: client ? cambiaLike : null,
    leggiRisposte,
  };
};
