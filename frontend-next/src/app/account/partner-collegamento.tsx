"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Building2 } from "lucide-react";
import { ETICHETTA_STATO_PARTNER } from "@/lib/partner/partner";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaPartnerService } from "@/services/partner-service";
import type { Partner } from "@/services/types";

/**
 * Accesso all'area Partner da /account, solo per chi ha un Partner.
 *
 * FAIL-SILENT: per i privati `partner_me` risponde `null` e qui non compare
 * nulla; un errore di lettura non mostra niente e non tocca il resto della
 * pagina. È l'unico punto in cui il programma Partner tocca /account.
 */
export default function PartnerCollegamento() {
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

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border bg-card p-5 md:p-6">
      <div className="flex items-center gap-3">
        <Building2 className="size-6" aria-hidden />
        <div>
          <p className="font-medium">Vinea Partner</p>
          <p className="text-sm text-muted-foreground">
            {partner.nomeCommerciale ?? "La tua attività"} · {ETICHETTA_STATO_PARTNER[partner.stato]}
          </p>
        </div>
      </div>
      <Link href="/partner" className="text-bordeaux underline underline-offset-2">
        Apri l&apos;area Partner
      </Link>
    </div>
  );
}
