import Link from "next/link";
import type { VenditoreAnnuncio } from "@/lib/partner-accessori/partner-accessori";

/**
 * Distingue un Accessorio NUOVO venduto da un Vinea Partner (operatore
 * professionale) da un articolo personale di un privato (VPM-015C). Il dato
 * arriva dal database (`accessori_venditore_pubblico`); per un privato non
 * viene mai mostrata l'identità.
 */
export function BadgeVenditoreAccessorio({ venditore }: { venditore: VenditoreAnnuncio }) {
  if (venditore.classe === "partner") {
    return (
      <p
        data-testid="venditore-partner"
        className="mx-auto mb-4 max-w-3xl rounded-lg border border-salvia/40 bg-salvia/10 px-4 py-3 text-sm"
      >
        <strong>Articolo nuovo · Venditore professionale Vinea Partner.</strong>{" "}
        <Link href={`/profilo/${venditore.titolareId}`} className="underline">
          Vedi la vetrina del Partner
        </Link>
      </p>
    );
  }
  return (
    <p
      data-testid="venditore-privato"
      className="mx-auto mb-4 max-w-3xl rounded-lg border border-border bg-secondary/40 px-4 py-3 text-sm"
    >
      <strong>Articolo personale di un privato.</strong> Non è un venditore professionale.
    </p>
  );
}
