import { Suspense } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { AcquistiPartnerNonDisponibili } from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { partnerCommercialeDelChiamante } from "@/lib/partner/classe-server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import VendiPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Aggiungi o vendi una bottiglia — Vinea",
  description: "Cataloga la tua bottiglia in cantina o pubblicala nel marketplace Vinea.",
  openGraph: {
    title: "Vendi o cataloga — Vinea",
    description: "Un wizard guidato: catalogazione privata, cantina pubblica o vendita.",
  },
};

/**
 * Il wizard legge `?mode=sell` con `useSearchParams`, che sospende durante il
 * prerender: senza questo confine di Suspense l'intera pagina resterebbe
 * esclusa dalla generazione statica.
 */
export default async function Page() {
  // Per un Partner attivo o sospeso il wizard privato non è la strada giusta:
  // cataloga bottiglie personali e le vende come privato all'8%. La
  // pubblicazione dei prodotti Partner — quantità multiple e disponibilità —
  // dipende dal Blocco C, e il prezzo professionale dal Blocco D. Qui si dice
  // onestamente che non è ancora aperta, invece di offrire un flusso sbagliato.
  if (await partnerCommercialeDelChiamante(await getSupabaseServerClient())) {
    return (
      <div className="mx-auto max-w-2xl space-y-5 py-6" data-testid="vendi-partner-non-disponibile">
        <h1 className="font-serif text-3xl font-semibold">Pubblicazione prodotti Partner</h1>
        <p className="text-muted-foreground">
          Come Partner Vinea pubblicherai i tuoi prodotti dal catalogo commerciale, con quantità
          multiple e disponibilità. Questa funzione non è ancora aperta: il percorso per i privati
          non si usa per i prodotti di un&apos;attività.
        </p>
        <AcquistiPartnerNonDisponibili compatto />
        <div className="flex flex-wrap gap-4 text-sm">
          <Link href="/cantina" className="font-medium text-bordeaux underline">
            Vai al catalogo commerciale
          </Link>
          <Link href="/partner" className="font-medium text-bordeaux underline">
            Area Partner
          </Link>
        </div>
      </div>
    );
  }
  return (
    <Suspense fallback={null}>
      <VendiPageClient />
    </Suspense>
  );
}
