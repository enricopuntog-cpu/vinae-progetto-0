import { createFileRoute, Link } from "@tanstack/react-router";
import { XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/payment/cancel")({
  head: () => ({
    meta: [{ title: "Pagamento annullato — Vinea" }, { name: "robots", content: "noindex" }],
  }),
  component: PaymentCancel,
});

function PaymentCancel() {
  return (
    <div
      className="mx-auto grid max-w-lg place-items-center gap-4 rounded-3xl border border-border bg-card p-8 text-center"
      data-testid="payment-cancel-page"
    >
      <div className="grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
        <XCircle className="h-8 w-8" />
      </div>
      <h1 className="font-serif text-3xl" data-testid="payment-cancel-title">
        Pagamento annullato
      </h1>
      <p className="text-sm text-muted-foreground">
        Nessun addebito è stato effettuato. Puoi tornare al checkout per riprovare o continuare a
        esplorare la collezione.
      </p>
      <div className="flex flex-wrap justify-center gap-2">
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link to="/esplora">Continua a esplorare</Link>
        </Button>
        <Button asChild variant="outline">
          <Link to="/acquisti">I miei acquisti</Link>
        </Button>
      </div>
      <p className="mt-4 text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
        Stripe test mode
      </p>
    </div>
  );
}
