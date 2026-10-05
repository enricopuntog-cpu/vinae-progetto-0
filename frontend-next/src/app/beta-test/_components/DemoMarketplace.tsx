"use client";

import { useEffect, useMemo, useState } from "react";
import { Check, Heart, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import {
  MARKET_VALIDATION_PRICE_BANDS,
  type MarketValidationPriceBand,
} from "@/lib/market-validation/contract";
import {
  MARKET_VALIDATION_DEMO_LISTINGS,
  type MarketValidationDemoListing,
} from "@/lib/market-validation/demo-data";
import { formatMarketValidationEuroCents } from "@/lib/market-validation/mv2-flow";
import type { MarketValidationDemoId } from "@/lib/market-validation/progress";
import type { MarketValidationTrack } from "./types";

export function DemoMarketplace({
  favorites,
  track,
  onSelect,
  onBack,
}: {
  favorites: readonly MarketValidationDemoId[];
  track: MarketValidationTrack;
  onSelect: (listing: MarketValidationDemoListing) => void;
  onBack: () => void;
}) {
  const [query, setQuery] = useState("");
  const [band, setBand] = useState<MarketValidationPriceBand | "all">("all");

  useEffect(() => {
    void track("marketplace_viewed", {}, "marketplace_viewed");
  }, [track]);

  const listings = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("it-IT");
    return MARKET_VALIDATION_DEMO_LISTINGS.filter((listing) => {
      const matchesQuery =
        !normalized ||
        [listing.wine, listing.producer, listing.denomination]
          .join(" ")
          .toLocaleLowerCase("it-IT")
          .includes(normalized);
      return matchesQuery && (band === "all" || listing.price_band === band);
    });
  }, [band, query]);

  const select = (listing: MarketValidationDemoListing) => {
    void track(
      "demo_listing_viewed",
      {
        demo_listing_id: listing.id,
        price_cents: listing.price_cents,
        price_band: listing.price_band,
      },
      `demo_listing_viewed:${listing.id}`,
    );
    onSelect(listing);
  };

  return (
    <section className="space-y-5" aria-labelledby="marketplace-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Simulazione acquisto</p>
          <h1 id="marketplace-title" className="mt-1 font-serif text-3xl font-semibold">Marketplace demo</h1>
          <p className="mt-2 text-sm text-muted-foreground">40 annunci fittizi, nessuna bottiglia realmente in vendita.</p>
        </div>
        <Button type="button" variant="outline" className="min-h-11 shrink-0" onClick={onBack}>Hub</Button>
      </div>

      <div className="grid gap-3 rounded-2xl border border-border bg-card p-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="mv-search">Cerca vino, produttore o denominazione</Label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-muted-foreground" aria-hidden />
            <Input id="mv-search" value={query} onChange={(event) => setQuery(event.target.value)} className="min-h-11 pl-9" placeholder="Es. Barolo" />
          </div>
        </div>
        <div className="space-y-2">
          <Label htmlFor="mv-price-band">Fascia di prezzo</Label>
          <Select value={band} onValueChange={(value) => setBand(value as MarketValidationPriceBand | "all")}>
            <SelectTrigger id="mv-price-band" className="min-h-11"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tutte le fasce</SelectItem>
              {MARKET_VALIDATION_PRICE_BANDS.map((priceBand) => (
                <SelectItem key={priceBand} value={priceBand}>{priceBand} €</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <p className="text-sm text-muted-foreground" aria-live="polite">{listings.length} annunci demo</p>
      {listings.length === 0 ? (
        <div className="rounded-2xl border border-dashed p-8 text-center">
          <p className="font-medium">Nessun annuncio corrisponde ai filtri.</p>
          <Button type="button" variant="outline" className="mt-4 min-h-11" onClick={() => { setQuery(""); setBand("all"); }}>Azzera filtri</Button>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-4">
          {listings.map((listing) => {
            const favorite = favorites.includes(listing.id);
            return (
              <button
                key={listing.id}
                type="button"
                onClick={() => select(listing)}
                className="group overflow-hidden rounded-2xl border border-border bg-card text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                <div className="relative aspect-[4/5] overflow-hidden bg-secondary">
                  <WineThumbnail src={listing.image} alt={`${listing.wine}, immagine dimostrativa`} className="h-full w-full object-cover transition group-hover:scale-[1.02]" sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw" />
                  {favorite && (
                    <span className="absolute right-2 top-2 inline-flex items-center gap-1 rounded-full bg-background/95 px-2 py-1 text-[10px] font-semibold text-bordeaux shadow">
                      <Heart className="h-3 w-3 fill-current" aria-hidden /> Preferito
                    </span>
                  )}
                </div>
                <div className="p-3">
                  <p className="line-clamp-1 text-xs text-muted-foreground">{listing.producer}</p>
                  <h2 className="mt-0.5 line-clamp-2 font-serif text-base font-semibold leading-tight">{listing.wine}</h2>
                  <p className="mt-1 text-xs text-muted-foreground">{listing.vintage} · {listing.format}</p>
                  <div className="mt-3 flex items-end justify-between gap-2">
                    <span className="font-semibold text-bordeaux">{formatMarketValidationEuroCents(listing.price_cents)}</span>
                    <span className="inline-flex items-center gap-1 text-[10px] text-muted-foreground"><Check className="h-3 w-3" aria-hidden /> Demo</span>
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}
