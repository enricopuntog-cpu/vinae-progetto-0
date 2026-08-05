import type { Metadata } from "next";
import { OrderList } from "@/components/vinea/orders/OrderList";

export const metadata: Metadata = {
  title: "Le mie vendite — Vinea",
  description: "Ordini ricevuti come venditore: nuovi, da preparare, da spedire, completati.",
  robots: { index: false, follow: false },
};

/**
 * Lo stato mostrato qui è quello **derivato** per il venditore: non esiste una
 * colonna `seller_stato`, e le nove etichette di frontend/ si ricavano dallo
 * stato dell'ordine più `preparazione_avviata_at`.
 */
export default function Page() {
  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-serif text-3xl md:text-4xl">Le mie vendite</h1>
        <p className="text-muted-foreground">Preparazione, spedizione e contestazioni.</p>
      </header>
      <OrderList lato="vendite" />
    </div>
  );
}
