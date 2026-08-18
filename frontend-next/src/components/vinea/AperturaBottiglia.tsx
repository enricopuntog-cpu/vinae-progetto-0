"use client";

import { useEffect, useMemo, useReducer, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { WineOff, Info } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createListingService } from "@/services/listing-service";
import { percorsoApertura } from "@/lib/cantina/apertura";
import {
  STATO_INIZIALE,
  riduttoreApertura,
  versoDegustazione,
} from "@/lib/cantina/macchina-apertura";
import { AVVISO_RIMOZIONE_IRREVERSIBILE, EFFETTO_RIMOZIONE } from "@/lib/annunci/rimozione";
import type { CellarBottle } from "@/data/cellar";

/**
 * Il comando «apri» di una bottiglia, con le conferme che prima non c'erano.
 *
 * Fino a oggi premere «Apri questa bottiglia» su una bottiglia in vendita
 * significava ricevere l'eccezione di `bottiglia_apri` — un messaggio corretto,
 * ma arrivato *dopo* il gesto e senza una via d'uscita. Qui la strada si decide
 * prima, e nessuno dei due passi è automatico: rimuovere l'annuncio e aprire la
 * bottiglia sono due azioni distinte e chiedono due conferme distinte.
 *
 * ## Perché due dialoghi e non uno con due caselle
 *
 * Sono irreversibili in modi diversi e in momenti diversi. La rimozione avviene
 * **subito**, alla prima conferma, e non si disfa; l'apertura avviene più tardi,
 * sulla schermata di degustazione, dopo che il commento è stato scritto. Un
 * dialogo solo lascerebbe credere che o succede tutto o non succede niente,
 * mentre è possibilissimo rimuovere l'annuncio e poi cambiare idea sull'apertura
 * — e in quel caso l'annuncio resta rimosso. Il primo dialogo lo dice.
 *
 * ## Perché lo stato sta in un riduttore e non in tre booleani
 *
 * Perché «non si apre senza conferma esplicita» è la proprietà che conta, e in
 * questo repository non c'è modo di montare un componente React in un test.
 * `macchina-apertura.ts` la rende verificabile — compreso l'annullamento a metà
 * di ciascuno dei due dialoghi — e questo componente la usa davvero, invece di
 * riprodurne il comportamento a fianco.
 */
export function AperturaBottiglia({
  bottiglia,
  nomeVino,
  variante = "pieno",
}: {
  bottiglia: CellarBottle;
  nomeVino: string;
  variante?: "pieno" | "compatto";
}) {
  const router = useRouter();
  const listingService = useMemo(() => createListingService(getSupabaseClient()), []);
  const percorso = useMemo(
    () => percorsoApertura(bottiglia.annuncioBloccante),
    [bottiglia.annuncioBloccante],
  );

  const [stato, dispatch] = useReducer(riduttoreApertura, STATO_INIZIALE);
  const [inCorso, setInCorso] = useState(false);

  const giaAperta = bottiglia.quantita === 0;
  const destinazione = `/cantina/${bottiglia.bottleId}/degustazione`;

  // La navigazione è l'effetto dello stato terminale, non di un click: è ciò
  // che tiene il test della macchina aderente a quello che il componente fa.
  useEffect(() => {
    if (versoDegustazione(stato)) router.push(destinazione);
  }, [stato, router, destinazione]);

  /**
   * Prima conferma. Rimuove davvero l'annuncio, e solo se riesce si passa alla
   * seconda: se `listing_sospendi` rifiuta, `bottiglia_apri` rifiuterebbe
   * comunque e la seconda domanda sarebbe una domanda a vuoto.
   */
  const confermaRimozione = async () => {
    if (percorso.tipo !== "rimuovi-poi-apri") return;
    setInCorso(true);
    try {
      const esito = await listingService.sospendi(percorso.listingId);
      if (!esito.ok) {
        toast.error(esito.error);
        dispatch({ tipo: "rimozione-fallita" });
        return;
      }
      toast.success("Annuncio rimosso dalla vendita");
      dispatch({ tipo: "rimozione-riuscita" });
    } finally {
      setInCorso(false);
    }
  };

  // In Cantina i comandi di una scheda sono pastiglie piccole; sulla pagina
  // dell'annuncio sono pulsanti pieni. Stesso comportamento, due vestiti: un
  // pulsante di taglia diversa dai suoi vicini si legge come un'altra cosa.
  const pastiglia =
    "inline-flex items-center gap-1 rounded-full border border-border bg-card px-2.5 py-1 text-[11px] font-medium transition hover:border-bordeaux";

  if (giaAperta) {
    return variante === "compatto" ? (
      <button
        className={pastiglia}
        onClick={() => router.push(destinazione)}
        data-testid="vedi-degustazione"
      >
        <WineOff className="h-3 w-3" /> Degustata
      </button>
    ) : (
      <Button variant="outline" size="sm" onClick={() => router.push(destinazione)}>
        <WineOff className="mr-1 h-4 w-4" /> Vedi la degustazione
      </Button>
    );
  }

  const premi = () => dispatch({ tipo: "premi", percorso });
  // Un dialogo si chiude anche con Esc o cliccando fuori: per la macchina è lo
  // stesso annullamento del pulsante «Annulla», e deve esserlo davvero, o si
  // resterebbe in uno stato che l'utente crede chiuso.
  const chiudi = (aperto: boolean) => {
    if (!aperto) dispatch({ tipo: "annulla" });
  };

  return (
    <>
      {variante === "compatto" ? (
        <button className={pastiglia} onClick={premi} data-testid="apri-bottiglia">
          <WineOff className="h-3 w-3" /> Apri
        </button>
      ) : (
        <Button
          size="sm"
          className="bg-bordeaux hover:bg-bordeaux/90"
          onClick={premi}
          data-testid="apri-bottiglia"
        >
          <WineOff className="mr-1 h-4 w-4" /> Apri questa bottiglia
        </Button>
      )}

      {/* --- Strada chiusa: si spiega, non si promette ---------------------- */}
      <Dialog open={stato.fase === "bloccato"} onOpenChange={chiudi}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Non puoi aprire questa bottiglia adesso</DialogTitle>
            <DialogDescription>
              {percorso.tipo === "bloccato" ? percorso.spiegazione : null}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => dispatch({ tipo: "annulla" })}>
              Ho capito
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Prima conferma: la rimozione dell'annuncio --------------------- */}
      <Dialog open={stato.fase === "rimozione"} onOpenChange={chiudi}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confermi la rimozione dell&apos;annuncio?</DialogTitle>
            <DialogDescription>
              {nomeVino} è in vendita, e una bottiglia in vendita non si può aprire. Per aprirla va
              prima tolta dal mercato. {EFFETTO_RIMOZIONE}
              <strong className="mt-2 block font-medium text-foreground">
                {AVVISO_RIMOZIONE_IRREVERSIBILE}
              </strong>
              <span className="mt-2 block">
                Dopo questo passo ti chiederemo una seconda conferma per l&apos;apertura: se
                cambierai idea lì, la bottiglia resterà chiusa ma l&apos;annuncio resterà rimosso.
              </span>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="ghost"
              onClick={() => dispatch({ tipo: "annulla" })}
              disabled={inCorso}
            >
              Annulla
            </Button>
            <Button onClick={confermaRimozione} disabled={inCorso} data-testid="conferma-rimozione">
              {inCorso ? "Rimozione…" : "Rimuovi dalla vendita"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Seconda conferma: l'apertura ----------------------------------- */}
      <Dialog open={stato.fase === "apertura"} onOpenChange={chiudi}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confermi l&apos;apertura della bottiglia?</DialogTitle>
            <DialogDescription>
              {nomeVino} uscirà dalle bottiglie disponibili della tua cantina e non ci tornerà: una
              bottiglia aperta non si richiude.
              <span className="mt-2 block">
                Nella schermata successiva potrai scrivere com&apos;era — e la bottiglia verrà
                registrata come degustata solo quando confermerai lì.
              </span>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => dispatch({ tipo: "annulla" })}>
              Annulla
            </Button>
            <Button
              className="bg-bordeaux hover:bg-bordeaux/90"
              onClick={() => dispatch({ tipo: "conferma-apertura" })}
              data-testid="conferma-apertura"
            >
              Sì, la sto aprendo
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* In Cantina la pastiglia sta in una riga di altre pastiglie: una nota
          sotto spezzerebbe la fila. Lì il motivo lo dà il dialogo. */}
      {percorso.tipo === "bloccato" && variante === "pieno" ? (
        <p className="mt-2 flex gap-1.5 text-xs text-muted-foreground">
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>Impegnata in un annuncio</span>
        </p>
      ) : null}
    </>
  );
}
