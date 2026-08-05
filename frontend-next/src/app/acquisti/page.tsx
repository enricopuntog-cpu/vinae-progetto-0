import type { Metadata } from "next";
import { OrderList } from "@/components/vinea/orders/OrderList";

export const metadata: Metadata = {
  title: "I miei acquisti — Vinea",
  description: "Storico ordini di acquisto Vinea con stato, tracking e recensione.",
  robots: { index: false, follow: false },
};

/**
 * Privata come la Cantina: senza sessione non c'è nulla da rendere sul server.
 * Gli ordini arrivano dal browser, filtrati da RLS su `buyer_id`.
 */
export default function Page() {
  return (
    <div className="space-y-6">
      <header>
        <h1 className="font-serif text-3xl md:text-4xl">I miei acquisti</h1>
        <p className="text-muted-foreground">Segui i tuoi ordini in ogni fase.</p>
      </header>
      <OrderList lato="acquisti" />
    </div>
  );
}
