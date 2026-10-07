"use client";

import { useEffect, useState } from "react";
import { CheckCircle2, PackageCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { MarketValidationDemoListing } from "@/lib/market-validation/demo-data";
import {
  formatMarketValidationEuroCents,
  marketValidationCheckoutTotalCents,
} from "@/lib/market-validation/mv2-flow";
import { DemoBackButton } from "./DemoBackButton";
import type { MarketValidationTrack } from "./types";

export function DemoCheckout({
  listing,
  shippingFeeCents,
  completed,
  track,
  onCompleted,
  onBack,
  onHub,
}: {
  listing: MarketValidationDemoListing;
  shippingFeeCents: number;
  completed: boolean;
  track: MarketValidationTrack;
  onCompleted: () => void;
  onBack: () => void;
  onHub: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const total = marketValidationCheckoutTotalCents(listing.price_cents, shippingFeeCents);

  useEffect(() => {
    void track(
      "shipping_cost_viewed",
      { price_cents: shippingFeeCents },
      `shipping_cost_viewed:${listing.id}`,
    );
  }, [listing.id, shippingFeeCents, track]);

  const finish = async () => {
    if (pending) return;
    setPending(true);
    setError(null);
    const result = await track(
      "checkout_beta_completed",
      {
        demo_listing_id: listing.id,
        price_cents: listing.price_cents,
        price_band: listing.price_band,
      },
      `checkout_beta_completed:${listing.id}`,
    );
    setPending(false);
    if (!result.ok) {
      setError("Non siamo riusciti a registrare la simulazione. Riprova senza perdere il riepilogo.");
      return;
    }
    onCompleted();
  };

  if (completed) {
    return (
      <section className="mx-auto max-w-xl rounded-3xl border border-salvia/40 bg-card p-6 text-center md:p-9" aria-labelledby="checkout-success-title">
        <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-salvia/15 text-salvia"><CheckCircle2 className="h-7 w-7" aria-hidden /></span>
        <h1 id="checkout-success-title" className="mt-4 font-serif text-3xl font-semibold">Acquisto simulato</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">
          Il percorso acquirente è completato. Non è stato creato alcun ordine, pagamento o piano di spedizione.
        </p>
        <Button type="button" className="mt-6 min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" onClick={onHub}>Torna al test</Button>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-xl space-y-5" aria-labelledby="checkout-title">
      <DemoBackButton onBack={onBack} />
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex items-start gap-3">
          <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><PackageCheck className="h-5 w-5" aria-hidden /></span>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Nessun pagamento</p>
            <h1 id="checkout-title" className="mt-1 font-serif text-3xl font-semibold">Checkout simulato</h1>
          </div>
        </div>

        <div className="mt-6 rounded-2xl bg-secondary/60 p-4">
          <p className="font-serif text-xl font-semibold">{listing.wine}</p>
          <p className="mt-1 text-sm text-muted-foreground">{listing.producer} · {listing.vintage}</p>
        </div>

        <dl className="mt-6 space-y-3 text-sm">
          <div className="flex justify-between gap-4"><dt>Prezzo demo</dt><dd>{formatMarketValidationEuroCents(listing.price_cents)}</dd></div>
          <div className="flex justify-between gap-4"><dt>Spedizione demo</dt><dd>{formatMarketValidationEuroCents(shippingFeeCents)}</dd></div>
          <div className="flex justify-between gap-4 border-t border-border pt-3 text-base font-semibold"><dt>Totale simulato</dt><dd className="text-bordeaux">{formatMarketValidationEuroCents(total)}</dd></div>
        </dl>

        <p className="mt-6 rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm">
          Nessun dato di pagamento viene richiesto. Il totale serve soltanto a valutare l&apos;esperienza.
        </p>
        {error && <p role="alert" className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">{error}</p>}
        <Button type="button" className="mt-5 min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" disabled={pending} onClick={finish}>
          {pending ? "Registrazione in corso…" : "Conferma acquisto simulato"}
        </Button>
      </div>
    </section>
  );
}
