"use client";

import { useState } from "react";
import { Tag } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ETICHETTE_STATO_ANNUNCIO,
  annuncioAperto,
  messaggioVenditoreNonAmmesso,
} from "@/lib/accessori-vendita/annunci-accessori";
import type { AccessorioPersonale } from "@/lib/cantina-accessori/cantina-accessori";
import { euro } from "@/lib/prezzi/classe";
import { AnnuncioAccessorioDialog } from "./AnnuncioAccessorioDialog";
import { useVenditaAccessori } from "./VenditaAccessoriProvider";

/**
 * Comando di una scheda della Cantina Accessori (VPM-015B2, VPM-015B3): prepara,
 * pubblica e gestisce l'annuncio.
 *
 * Non mostra nulla se la preparazione degli annunci non è abilitata (default in
 * produzione) o se l'accessorio è archiviato. Non è un pulsante d'acquisto: dice
 * sempre lo stato dell'annuncio (anche quando Vinea è intervenuta) e apre il
 * dialogo di gestione.
 */
export function VenditaAccessorio({
  accessorio,
  commerciale = false,
}: {
  accessorio: Pick<AccessorioPersonale, "id" | "nome" | "condizione" | "quantita" | "immagini" | "archiviato">;
  /** Scorta commerciale di un Partner (VPM-015C): l'ammissione si decide per articolo (preventivo, salvataggio e pubblicazione). */
  commerciale?: boolean;
}) {
  const contesto = useVenditaAccessori();
  const [aperto, setAperto] = useState(false);

  if (!contesto?.stato?.abilitata || accessorio.archiviato) return null;

  const { stato, annunci, servizio, ricarica } = contesto;
  const annuncio = annunci.find((a) => a.cantinaId === accessorio.id && annuncioAperto(a)) ?? null;

  // `stato.venditoreAmmesso` è la risposta per gli accessori PERSONALI: per un Partner dice sempre
  // `partner_percorso_non_consentito`. Una scorta commerciale non passa da lì: ogni porta per articolo
  // (preventivo, bozza, pubblicazione) ricontrolla Partner attivo, proprietà e interruttori nel database.
  const percorsoPartner = commerciale && stato.motivo === "partner_percorso_non_consentito";
  if (!stato.venditoreAmmesso && !percorsoPartner) {
    const spiegazione = messaggioVenditoreNonAmmesso(stato.motivo);
    return spiegazione ? (
      <p className="text-xs text-muted-foreground" data-testid="vendita-accessorio-non-ammessa">
        {spiegazione}
      </p>
    ) : null;
  }

  const chiusoDaVinea = annuncio?.stato === "oscurato" || annuncio?.stato === "modifiche_richieste";
  const inVetrina = annuncio?.stato === "pubblicato" && annuncio.pubblico;

  return (
    <div className="space-y-2" data-testid="vendita-accessorio">
      {annuncio ? (
        <p className="text-xs" data-testid="vendita-accessorio-stato">
          <span
            className={`rounded-full px-2 py-0.5 ${chiusoDaVinea ? "bg-bordeaux/10 text-bordeaux" : "bg-secondary"}`}
          >
            {ETICHETTE_STATO_ANNUNCIO[annuncio.stato]} · {annuncio.quantita === 1 ? "1 pezzo" : `${annuncio.quantita} pezzi`} a{" "}
            {euro(annuncio.prezzoUnitarioCents)}
          </span>{" "}
          <span className="text-muted-foreground">
            {inVetrina
              ? "In vetrina, non acquistabile."
              : chiusoDaVinea
                ? "Vinea è intervenuta: apri l'annuncio per i dettagli."
                : "Non in vetrina."}
          </span>
        </p>
      ) : null}
      <Button type="button" size="sm" variant="outline" onClick={() => setAperto(true)}>
        <Tag aria-hidden /> {annuncio ? "Gestisci annuncio" : "Prepara annuncio"}
      </Button>
      {aperto ? (
        <AnnuncioAccessorioDialog
          accessorio={accessorio}
          annuncio={annuncio}
          servizio={servizio}
          pubblicazioneAperta={stato.pubblicazioneAperta}
          onChiudi={() => setAperto(false)}
          onCambiato={ricarica}
        />
      ) : null}
    </div>
  );
}
