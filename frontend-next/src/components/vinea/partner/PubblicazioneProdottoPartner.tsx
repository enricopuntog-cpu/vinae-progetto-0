"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { Info, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { getSupabaseClient } from "@/lib/supabase/client";
import { messaggioNonAcquistabile } from "@/lib/prezzi/classe";
import {
  CONFEZIONI_ORIGINALI,
  DISCLAIMER_IMBALLAGGIO,
  DESCRIZIONE_HANDOFF,
  ETICHETTA_CONFEZIONE_ORIGINALE,
  ETICHETTA_HANDOFF,
  HANDOFF_VENDITORE,
  pubblicaConLogistica,
  type ConfezioneOriginaleTipo,
  type HandoffVenditore,
} from "@/lib/vendi/logistica-annuncio";
import { createListingService } from "@/services/listing-service";
import { SedePartnerRitiro } from "@/components/vinea/indirizzi/SedePartnerRitiro";
import type { MotivoNonAcquistabile } from "@/services/preventivo-service";

/** Motivi per cui una bozza commerciale si può pubblicare adesso. */
const PUBBLICABILE = new Set<MotivoNonAcquistabile | null>([null, "annuncio_non_attivo"]);

/**
 * VP-D: pubblicazione di un prodotto commerciale dalla sua scheda, per il
 * titolare. Il motivo viene da `listing_preventivo` (classe e vendibilità del
 * database): con `vendita_partner` spento la pubblicazione è dichiarata chiusa
 * e non c'è un pulsante che il database rifiuterebbe; con il Partner sospeso o
 * revocato lo stesso. Quando è aperta, le due dichiarazioni logistiche e la
 * pubblicazione passano dalle porte di sempre, nello stesso ordine del wizard.
 */
export function PubblicazioneProdottoPartner({
  listingId,
  motivo,
}: {
  listingId: string;
  motivo: MotivoNonAcquistabile | null;
}) {
  const router = useRouter();
  const client = getSupabaseClient();
  const servizio = useMemo(() => createListingService(client), [client]);
  const [confezione, setConfezione] = useState<ConfezioneOriginaleTipo | "">("");
  const [handoff, setHandoff] = useState<HandoffVenditore | "">("");
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  if (!PUBBLICABILE.has(motivo)) {
    return (
      <p
        role="note"
        className="mt-4 flex gap-2 rounded-2xl border border-border bg-secondary/60 p-4 text-sm"
        data-testid="pubblicazione-prodotto-chiusa"
      >
        <Info className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
        <span>
          {motivo === "partner_vendita_non_disponibile"
            ? "La pubblicazione dei prodotti Partner non è ancora aperta. La bozza resta pronta: prezzo, quantità, fotografie e descrizione si possono già curare."
            : messaggioNonAcquistabile(motivo)}
        </span>
      </p>
    );
  }

  const pubblica = async () => {
    if (!confezione || !handoff) {
      setErrore("Indica la confezione e come consegnerai i pacchi prima di pubblicare.");
      return;
    }
    setInCorso(true);
    setErrore(null);
    const esito = await pubblicaConLogistica({
      listingId,
      dichiarazione: {
        confezioneOriginaleTipo: confezione,
        confezioneOriginaleFoto: [],
        handoffVenditore: handoff,
      },
      dichiaraLogistica: servizio.dichiaraLogistica,
      pubblica: servizio.pubblica,
    });
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    router.refresh();
  };

  return (
    <section className="mt-4 space-y-3 rounded-2xl border border-border bg-card p-4 text-sm" data-testid="pubblicazione-prodotto">
      <p className="font-medium">Pubblica il prodotto</p>
      <div className="space-y-1">
        <Label htmlFor="confezione-prodotto">Come viene venduto</Label>
        <select
          id="confezione-prodotto"
          className="h-10 w-full rounded-md border border-input bg-background px-3"
          value={confezione}
          onChange={(e) => setConfezione(e.target.value as ConfezioneOriginaleTipo)}
        >
          <option value="">Scegli…</option>
          {CONFEZIONI_ORIGINALI.map((c) => (
            <option key={c} value={c}>
              {ETICHETTA_CONFEZIONE_ORIGINALE[c]}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1">
        <Label htmlFor="handoff-prodotto">Consegna dei pacchi alla rete</Label>
        <select
          id="handoff-prodotto"
          className="h-10 w-full rounded-md border border-input bg-background px-3"
          value={handoff}
          onChange={(e) => setHandoff(e.target.value as HandoffVenditore)}
        >
          <option value="">Scegli…</option>
          {HANDOFF_VENDITORE.map((h) => (
            <option key={h} value={h}>
              {ETICHETTA_HANDOFF[h]}
            </option>
          ))}
        </select>
        {handoff ? <p className="text-xs text-muted-foreground">{DESCRIZIONE_HANDOFF[handoff]}</p> : null}
        {handoff === "ritiro_domicilio" ? <SedePartnerRitiro variante="prodotto" /> : null}
      </div>
      <p className="text-xs text-muted-foreground">{DISCLAIMER_IMBALLAGGIO}</p>
      {errore ? (
        <p role="alert" className="text-destructive">
          {errore}
        </p>
      ) : null}
      <Button
        className="bg-bordeaux hover:bg-bordeaux/90"
        onClick={() => void pubblica()}
        disabled={inCorso || !confezione || !handoff}
      >
        <Send className="mr-1 h-4 w-4" aria-hidden /> {inCorso ? "Pubblicazione…" : "Pubblica"}
      </Button>
    </section>
  );
}
