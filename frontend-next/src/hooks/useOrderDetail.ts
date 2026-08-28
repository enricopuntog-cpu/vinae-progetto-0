"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createOrderService } from "@/services/phase7/order-service";
import { createDisputeService } from "@/services/phase7c/dispute-service";
import { createReviewService } from "@/services/phase7c/review-service";
import { createTrackingService } from "@/services/phase7c/tracking-service";
import type {
  DisputeRecord,
  EleggibilitaRecensione,
  OrderRecord,
  OrderReviewRecord,
  OrderReviewRispostaRecord,
  TrackingEventRecord,
  VoceChecklist,
} from "@/services/types";

export type DettaglioOrdine = {
  ordine: OrderRecord;
  tracking: TrackingEventRecord[];
  contestazione: DisputeRecord | null;
  recensione: OrderReviewRecord | null;
  /**
   * La replica del venditore alla recensione, se c'è. Al massimo una: il
   * database ha una UNIQUE sulla recensione.
   */
  rispostaRecensione: OrderReviewRispostaRecord | null;
  /**
   * L'ammissibilità come la calcola il server, per questo ordine. `null` per il
   * venditore — la funzione risponde sui soli ordini di chi compra — e `null`
   * anche se la lettura fallisce, che è il caso prudente: senza risposta il
   * modulo non compare.
   */
  eleggibilita: EleggibilitaRecensione | null;
  /** Chi sta guardando. Decide quale pannello compare, non quale permesso c'è. */
  ruolo: "compratore" | "venditore";
};

type Stato =
  | { fase: "caricamento" }
  | { fase: "errore"; messaggio: string }
  | { fase: "pronto"; dati: DettaglioOrdine };

/**
 * Carica un ordine e tutto ciò che gli sta intorno, e offre le transizioni.
 *
 * Il ruolo si deriva confrontando l'utente con `buyer_id`/`seller_id` **e serve
 * solo a decidere che cosa mostrare**. Chi può fare che cosa lo decidono le
 * RPC, che rileggono la riga con `auth.uid()`: nascondere un bottone non è un
 * permesso, e questo hook non finge che lo sia.
 */
export function useOrderDetail(orderId: string) {
  const client = getSupabaseClient();
  // Inizializzatore pigro invece di un setState nell'effect: il caso "Supabase
  // non configurato" è noto al primo render e scriverlo dopo sarebbe un render
  // a cascata per un fatto che non è mai cambiato.
  const [stato, setStato] = useState<Stato>(() =>
    client
      ? { fase: "caricamento" }
      : { fase: "errore", messaggio: "Connessione a Supabase non configurata." },
  );
  const [inCorso, setInCorso] = useState(false);
  const utenteId = useRef<string | null>(null);
  const ordini = createOrderService(client);
  const tracking = createTrackingService(client);
  const contestazioni = createDisputeService(client);
  const recensioni = createReviewService(client);

  const carica = useCallback(async (userId: string | null) => {
    if (!client) return;
    if (!userId) {
      setStato({ fase: "errore", messaggio: "Devi accedere per vedere questo ordine." });
      return;
    }
    utenteId.current = userId;

    const esitoOrdine = await ordini.get(orderId);
    if (!esitoOrdine.ok) {
      setStato({ fase: "errore", messaggio: esitoOrdine.error });
      return;
    }
    if (!esitoOrdine.data) {
      setStato({ fase: "errore", messaggio: "Ordine non trovato." });
      return;
    }
    const ordine = esitoOrdine.data;

    const venditore = ordine.seller_id === userId;

    const [esitoTracking, esitoDispute, esitoReview, esitoEleggibilita] = await Promise.all([
      tracking.perOrdine(orderId),
      contestazioni.perOrdine(orderId),
      recensioni.perOrdine(orderId),
      // Il venditore non la chiede nemmeno: `ordini_recensibili` risponde sui
      // soli ordini di chi compra, quindi per lui sarebbe una lettura sempre
      // vuota.
      venditore
        ? Promise.resolve(null)
        : recensioni.eleggibilita().then((e) => (e.ok ? e.data : null)),
    ]);

    const recensione = esitoReview.ok ? esitoReview.data : null;
    // La replica si legge solo se la recensione esiste: senza di essa non c'è
    // niente a cui possa essere associata.
    const esitoRisposta = recensione
      ? await recensioni.rispostaPerRecensione(recensione.id)
      : null;

    setStato({
      fase: "pronto",
      dati: {
        ordine,
        tracking: esitoTracking.ok ? esitoTracking.data : [],
        contestazione: esitoDispute.ok ? esitoDispute.data : null,
        recensione,
        rispostaRecensione: esitoRisposta?.ok ? esitoRisposta.data : null,
        eleggibilita:
          esitoEleggibilita?.find((e) => e.orderId === orderId) ?? null,
        ruolo: venditore ? "venditore" : "compratore",
      },
    });
    // Le dipendenze sono volutamente il solo `orderId`: i servizi si ricreano a
    // ogni render e metterli qui rifarebbe la fetch all'infinito.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orderId]);

  useEffect(() => {
    if (!client) return;
    let attivo = true;
    // La prima lettura sta dentro il `.then` e non nel corpo dell'effect:
    // aggiornare lo stato in modo sincrono qui innescherebbe render a cascata.
    // È la stessa forma di cellar-domain.ts e real-auth-domain.ts.
    void client.auth.getUser().then(({ data }) => {
      if (attivo) void carica(data.user?.id ?? null);
    });
    return () => {
      attivo = false;
    };
  }, [carica, client]);

  /** Ricarica su richiesta dell'interfaccia, non da un effect. */
  const ricarica = useCallback(() => carica(utenteId.current), [carica]);

  /** Esegue una transizione e ricarica. Un errore torna come messaggio, non come throw. */
  const azione = useCallback(
    async (operazione: () => Promise<{ ok: boolean; error?: string }>) => {
      setInCorso(true);
      try {
        const esito = await operazione();
        if (!esito.ok) return esito.error ?? "Operazione non riuscita.";
        await ricarica();
        return null;
      } finally {
        setInCorso(false);
      }
    },
    [ricarica],
  );

  return {
    stato,
    inCorso,
    ricarica,
    preparaSpedizione: (checklist: VoceChecklist[], foto?: string[]) =>
      azione(() => ordini.preparaSpedizione(orderId, checklist, foto)),
    segnaSpedito: (corriere: string, trackingNumber: string) =>
      azione(() => ordini.segnaSpedito(orderId, corriere, trackingNumber)),
    segnaConsegnato: () => azione(() => ordini.segnaConsegnato(orderId)),
    confermaRicezione: () => azione(() => ordini.confermaRicezione(orderId)),
    apriContestazione: (motivo: string, descrizione: string, foto: string[]) =>
      azione(() => contestazioni.apri({ orderId, motivo, descrizione, foto })),
    recensisci: (r: {
      voto: number;
      conformita: number;
      imballaggio: number;
      comunicazione: number;
      testo?: string | null;
    }) => azione(() => recensioni.invia({ orderId, ...r })),
    /**
     * La replica del venditore. Non passa la propria identità: il database
     * legge `destinatario_id` dalla recensione e rifiuta chiunque altro.
     */
    rispondiRecensione: (reviewId: string, testo: string) =>
      azione(() => recensioni.rispondi({ reviewId, testo })),
  };
}
