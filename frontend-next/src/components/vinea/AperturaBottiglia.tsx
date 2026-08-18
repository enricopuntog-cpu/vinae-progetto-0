"use client";

import { useMemo, useState } from "react";
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

  const [rimozioneAperta, setRimozioneAperta] = useState(false);
  const [aperturaAperta, setAperturaAperta] = useState(false);
  const [bloccoAperto, setBloccoAperto] = useState(false);
  const [inCorso, setInCorso] = useState(false);

  const giaAperta = bottiglia.quantita === 0;

  /** Il primo gesto: sceglie con quale conversazione cominciare. */
  const premuto = () => {
    if (percorso.tipo === "bloccato") return setBloccoAperto(true);
    if (percorso.tipo === "rimuovi-poi-apri") return setRimozioneAperta(true);
    return setAperturaAperta(true);
  };

  /**
   * Prima conferma. Rimuove davvero l'annuncio, e solo dopo apre la seconda:
   * se `listing_sospendi` fallisce non si prosegue, perché `bottiglia_apri`
   * rifiuterebbe comunque e la seconda conferma sarebbe una domanda a vuoto.
   */
  const confermaRimozione = async () => {
    if (percorso.tipo !== "rimuovi-poi-apri") return;
    setInCorso(true);
    try {
      const esito = await listingService.sospendi(percorso.listingId);
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      toast.success("Annuncio rimosso dalla vendita");
      setRimozioneAperta(false);
      setAperturaAperta(true);
    } finally {
      setInCorso(false);
    }
  };

  /**
   * Seconda conferma. Non apre la bottiglia: porta alla schermata che raccoglie
   * il commento di degustazione, ed è lì che `bottiglia_apri` viene chiamata.
   * Chi abbandona quella schermata lascia la bottiglia chiusa — il che è il
   * comportamento giusto, ma è anche il motivo per cui la rimozione dell'annuncio
   * va annunciata come definitiva già al primo dialogo.
   */
  const confermaApertura = () => {
    setAperturaAperta(false);
    router.push(`/cantina/${bottiglia.bottleId}/degustazione`);
  };

  // In Cantina i comandi di una scheda sono pastiglie piccole; sulla pagina
  // dell'annuncio sono pulsanti pieni. Stesso comportamento, due vestiti: un
  // pulsante di taglia diversa dai suoi vicini si legge come un'altra cosa.
  const pastiglia =
    "inline-flex items-center gap-1 rounded-full border border-border bg-card px-2.5 py-1 text-[11px] font-medium transition hover:border-bordeaux";

  if (giaAperta) {
    const vaiAllaDegustazione = () =>
      router.push(`/cantina/${bottiglia.bottleId}/degustazione`);
    return variante === "compatto" ? (
      <button className={pastiglia} onClick={vaiAllaDegustazione} data-testid="vedi-degustazione">
        <WineOff className="h-3 w-3" /> Degustata
      </button>
    ) : (
      <Button variant="outline" size="sm" onClick={vaiAllaDegustazione}>
        <WineOff className="mr-1 h-4 w-4" /> Vedi la degustazione
      </Button>
    );
  }

  return (
    <>
      {variante === "compatto" ? (
        <button className={pastiglia} onClick={premuto} data-testid="apri-bottiglia">
          <WineOff className="h-3 w-3" /> Apri
        </button>
      ) : (
        <Button
          size="sm"
          className="bg-bordeaux hover:bg-bordeaux/90"
          onClick={premuto}
          data-testid="apri-bottiglia"
        >
          <WineOff className="mr-1 h-4 w-4" /> Apri questa bottiglia
        </Button>
      )}

      {/* --- Strada chiusa: si spiega, non si promette ---------------------- */}
      <Dialog open={bloccoAperto} onOpenChange={setBloccoAperto}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Non puoi aprire questa bottiglia adesso</DialogTitle>
            <DialogDescription>
              {percorso.tipo === "bloccato" ? percorso.spiegazione : null}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setBloccoAperto(false)}>
              Ho capito
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Prima conferma: la rimozione dell'annuncio --------------------- */}
      <Dialog open={rimozioneAperta} onOpenChange={setRimozioneAperta}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confermi la rimozione dell&apos;annuncio?</DialogTitle>
            <DialogDescription>
              {nomeVino} è in vendita, e una bottiglia in vendita non si può aprire. Per aprirla
              va prima tolta dal mercato. {EFFETTO_RIMOZIONE}
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
            <Button variant="ghost" onClick={() => setRimozioneAperta(false)} disabled={inCorso}>
              Annulla
            </Button>
            <Button onClick={confermaRimozione} disabled={inCorso} data-testid="conferma-rimozione">
              {inCorso ? "Rimozione…" : "Rimuovi dalla vendita"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Seconda conferma: l'apertura ----------------------------------- */}
      <Dialog open={aperturaAperta} onOpenChange={setAperturaAperta}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confermi l&apos;apertura della bottiglia?</DialogTitle>
            <DialogDescription>
              {nomeVino} uscirà dalle bottiglie disponibili della tua cantina e non ci tornerà:
              una bottiglia aperta non si richiude.
              <span className="mt-2 block">
                Nella schermata successiva potrai scrivere com&apos;era — e la bottiglia verrà
                registrata come degustata solo quando confermerai lì.
              </span>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setAperturaAperta(false)} disabled={inCorso}>
              Annulla
            </Button>
            <Button
              className="bg-bordeaux hover:bg-bordeaux/90"
              onClick={confermaApertura}
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
