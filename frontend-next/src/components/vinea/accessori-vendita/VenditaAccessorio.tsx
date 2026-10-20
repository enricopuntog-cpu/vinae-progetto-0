"use client";

import { useState } from "react";
import { Tag } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ETICHETTE_STATO_ANNUNCIO,
  messaggioVenditoreNonAmmesso,
} from "@/lib/accessori-vendita/annunci-accessori";
import type { AccessorioPersonale } from "@/lib/cantina-accessori/cantina-accessori";
import { euro } from "@/lib/prezzi/classe";
import { AnnuncioAccessorioDialog } from "./AnnuncioAccessorioDialog";
import { useVenditaAccessori } from "./VenditaAccessoriProvider";

/**
 * Comando «Prepara vendita» di una scheda della Cantina Accessori (VPM-015B2).
 *
 * Non mostra nulla se la preparazione degli annunci non è abilitata (default in
 * produzione) o se l'accessorio è archiviato. Non è un pulsante d'acquisto e
 * non pubblica niente: apre la preparazione di una bozza.
 */
export function VenditaAccessorio({
  accessorio,
}: {
  accessorio: Pick<AccessorioPersonale, "id" | "nome" | "condizione" | "quantita" | "immagini" | "archiviato">;
}) {
  const contesto = useVenditaAccessori();
  const [aperto, setAperto] = useState(false);

  if (!contesto?.stato?.abilitata || accessorio.archiviato) return null;

  const { stato, annunci, servizio, ricarica } = contesto;
  const annuncio = annunci.find((a) => a.cantinaId === accessorio.id && a.stato !== "ritirato") ?? null;

  if (!stato.venditoreAmmesso) {
    const spiegazione = messaggioVenditoreNonAmmesso(stato.motivo);
    return spiegazione ? (
      <p className="text-xs text-muted-foreground" data-testid="vendita-accessorio-non-ammessa">
        {spiegazione}
      </p>
    ) : null;
  }

  return (
    <div className="space-y-2" data-testid="vendita-accessorio">
      {annuncio ? (
        <p className="text-xs" data-testid="vendita-accessorio-stato">
          <span className="rounded-full bg-secondary px-2 py-0.5">
            {ETICHETTE_STATO_ANNUNCIO[annuncio.stato]} · {annuncio.quantita === 1 ? "1 pezzo" : `${annuncio.quantita} pezzi`} a{" "}
            {euro(annuncio.prezzoUnitarioCents)}
          </span>{" "}
          <span className="text-muted-foreground">Non in vendita.</span>
        </p>
      ) : null}
      <Button type="button" size="sm" variant="outline" onClick={() => setAperto(true)}>
        <Tag aria-hidden /> {annuncio ? "Gestisci annuncio" : "Prepara vendita"}
      </Button>
      {aperto ? (
        <AnnuncioAccessorioDialog
          accessorio={accessorio}
          annuncio={annuncio}
          servizio={servizio}
          onChiudi={() => setAperto(false)}
          onCambiato={ricarica}
        />
      ) : null}
    </div>
  );
}
