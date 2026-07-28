import { Suspense } from "react";
import type { Metadata } from "next";
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
export default function Page() {
  return (
    <Suspense fallback={null}>
      <VendiPageClient />
    </Suspense>
  );
}
