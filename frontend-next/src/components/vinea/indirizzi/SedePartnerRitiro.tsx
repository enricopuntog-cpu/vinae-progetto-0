"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Building2 } from "lucide-react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPartnerService } from "@/services/partner-service";
import type { Partner } from "@/services/types";

/** «Via Roma 1, 20121 Milano (MI)», o `null` se la sede è incompleta. */
export function rigaSedePartner(
  p: Pick<Partner, "sedeIndirizzo" | "sedeCap" | "sedeCitta" | "sedeProvincia">,
): string | null {
  if (!p.sedeIndirizzo || !p.sedeCap || !p.sedeCitta) return null;
  return `${p.sedeIndirizzo}, ${p.sedeCap} ${p.sedeCitta}${p.sedeProvincia ? ` (${p.sedeProvincia})` : ""}`;
}

/**
 * Ritiro dei prodotti dell'attività: la sede commerciale registrata del
 * Partner, letta da `partner_me` e mai copiata nella rubrica privata. Il
 * database la usa come origine dei prodotti commerciali con ritiro
 * (`private.logistica_indirizzo_origine`); qui si mostra soltanto.
 *
 * FAIL-SILENT come `PartnerCollegamento`: per chi non ha un Partner (o se la
 * lettura fallisce) non compare nulla.
 */
export function SedePartnerRitiro({ variante = "rubrica" }: { variante?: "rubrica" | "prodotto" }) {
  const [partner, setPartner] = useState<Partner | null>(null);

  useEffect(() => {
    let attivo = true;
    void creaPartnerService(getSupabaseClient())
      .mio()
      .then((esito) => {
        if (attivo && esito.ok) setPartner(esito.data);
      })
      .catch(() => undefined);
    return () => {
      attivo = false;
    };
  }, []);

  if (!partner) return null;
  const sede = rigaSedePartner(partner);

  return (
    <div
      className="flex gap-3 rounded-xl border border-border bg-secondary/50 p-3 text-sm"
      data-testid="sede-partner-ritiro"
    >
      <Building2 className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
      <div>
        <p className="font-medium">
          {variante === "prodotto" ? "Ritiro presso la sede dell'attività" : "Prodotti della tua attività"}
        </p>
        <p className="text-xs text-muted-foreground">
          {sede
            ? `Per i prodotti Partner il corriere ritira alla sede commerciale registrata: ${sede}.${
                variante === "rubrica" ? " Questa rubrica vale per le tue vendite da privato." : ""
              }`
            :"La sede commerciale registrata è incompleta: il ritiro dei prodotti Partner non è possibile finché non viene completata."}{" "}
          La sede si gestisce dall&apos;
          <Link href="/partner" className="text-bordeaux underline underline-offset-2">
            area Partner
          </Link>
          .
        </p>
      </div>
    </div>
  );
}
