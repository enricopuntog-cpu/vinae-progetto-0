"use client";

import { Heart, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import type { MarketValidationDemoListing } from "@/lib/market-validation/demo-data";
import { formatMarketValidationEuroCents } from "@/lib/market-validation/mv2-flow";
import type { MarketValidationTrack } from "./types";

export function DemoListingDetail({
  listing,
  favorite,
  track,
  onToggleFavorite,
  onCheckout,
  onBack,
}: {
  listing: MarketValidationDemoListing;
  favorite: boolean;
  track: MarketValidationTrack;
  onToggleFavorite: (id: MarketValidationDemoListing["id"]) => void;
  onCheckout: () => void;
  onBack: () => void;
}) {
  const metadata = {
    demo_listing_id: listing.id,
    price_cents: listing.price_cents,
    price_band: listing.price_band,
  } as const;

  const toggleFavorite = () => {
    onToggleFavorite(listing.id);
    if (!favorite) {
      void track("favorite_added", metadata, `favorite_added:${listing.id}`);
    }
  };

  const startCheckout = () => {
    void track("checkout_started", metadata, `checkout_started:${listing.id}`);
    onCheckout();
  };

  return (
    <section className="space-y-5" aria-labelledby="listing-title">
      <Button type="button" variant="outline" className="min-h-11" onClick={onBack}>← Torna agli annunci</Button>
      <div className="grid overflow-hidden rounded-3xl border border-border bg-card md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
        <div className="aspect-[4/5] min-w-0 bg-secondary md:aspect-auto">
          <WineThumbnail src={listing.image} alt={`${listing.wine}, immagine dimostrativa`} className="h-full w-full object-cover" sizes="(max-width: 768px) 100vw, 45vw" />
        </div>
        <div className="min-w-0 p-5 md:p-8">
          <p className="text-sm text-muted-foreground">{listing.producer}</p>
          <h1 id="listing-title" className="mt-1 font-serif text-3xl font-semibold">{listing.wine}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{listing.denomination}</p>
          <p className="mt-5 text-3xl font-semibold text-bordeaux">{formatMarketValidationEuroCents(listing.price_cents)}</p>

          <dl className="mt-6 grid grid-cols-2 gap-3 text-sm">
            {[
              ["Annata", listing.vintage],
              ["Formato", listing.format],
              ["Condizione", listing.condition],
              ["Fascia", `${listing.price_band} €`],
            ].map(([label, value]) => (
              <div key={label} className="rounded-xl bg-secondary/60 p-3">
                <dt className="text-xs text-muted-foreground">{label}</dt>
                <dd className="mt-1 font-medium">{value}</dd>
              </div>
            ))}
          </dl>

          <div className="mt-6 flex items-start gap-2 rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
            <p>Annuncio esclusivamente dimostrativo: nessun venditore e nessuna disponibilità reale.</p>
          </div>

          <div className="mt-6 grid gap-3 sm:grid-cols-2">
            <Button type="button" variant="outline" className="min-h-12" aria-pressed={favorite} onClick={toggleFavorite}>
              <Heart className={favorite ? "fill-current text-bordeaux" : ""} aria-hidden />
              {favorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti"}
            </Button>
            <Button type="button" className="min-h-12 bg-bordeaux hover:bg-bordeaux/90" onClick={startCheckout}>Simula acquisto</Button>
          </div>
        </div>
      </div>
    </section>
  );
}
