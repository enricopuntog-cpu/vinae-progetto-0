import { Link } from "@tanstack/react-router";
import { Heart, MapPin, ShieldCheck, Tag, EyeOff } from "lucide-react";
import type { Wine } from "@/data/wines";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { DrinkBadge } from "@/components/vinea/DrinkWindow";
import { listingStatusLabel, listingStatusTone } from "@/data/moderation";
import { SafeImage } from "@/components/vinea/States";

export function WineCard({
  wine,
  variant = "grid",
  showSaleBadge = false,
  hidePriceIfPrivate = false,
}: {
  wine: Wine;
  variant?: "grid" | "list";
  showSaleBadge?: boolean;
  hidePriceIfPrivate?: boolean;
}) {
  const { favorites, toggleFavorite, inVendita, prezzoNascosto, listingStatus } = useVinea();
  const fav = favorites.has(wine.id);
  const sale = showSaleBadge && inVendita.has(wine.id);
  const priceHidden = hidePriceIfPrivate && prezzoNascosto.has(wine.id);
  const stato = listingStatus[wine.id];
  const mostraStato = stato && stato !== "attivo";

  if (variant === "list") {
    return (
      <Link
        to="/annuncio/$id"
        params={{ id: wine.id }}
        data-testid={`wine-card-list-${wine.id}`}
        className="flex gap-3 rounded-2xl border border-border bg-card p-3 card-lift perf-card"
      >
        <div className="relative">
          <SafeImage
            src={wine.immagini[0]}
            alt={wine.nome}
            className="h-24 w-20 flex-shrink-0 rounded-lg object-cover"
            fallbackLabel="Foto non disponibile"
          />
          {sale && (
            <span className="absolute left-1 top-1 rounded-full bg-bordeaux px-1.5 py-0.5 text-[9px] font-semibold text-crema shadow">
              In vendita
            </span>
          )}
        </div>
        <div className="flex min-w-0 flex-1 flex-col">
          <p className="text-xs uppercase tracking-wide text-salvia">{wine.produttore}</p>
          <p className="truncate font-serif text-base font-semibold">
            {wine.nome} {wine.annata}
          </p>
          <p className="mt-0.5 flex items-center gap-1 truncate text-xs text-muted-foreground">
            <MapPin className="h-3 w-3" /> {wine.venditore.citta}
          </p>
          <div className="mt-auto flex items-baseline justify-between">
            {priceHidden ? (
              <p className="flex items-center gap-1 text-xs text-muted-foreground">
                <EyeOff className="h-3 w-3" /> Prezzo riservato
              </p>
            ) : (
              <p className="font-serif text-lg font-semibold text-bordeaux">
                {formatEUR(wine.prezzo)}
              </p>
            )}
            <span className="text-[10px] text-muted-foreground">{wine.condizione}</span>
          </div>
        </div>
      </Link>
    );
  }

  return (
    <div
      className="group relative overflow-hidden rounded-2xl border border-border bg-card card-lift perf-card cv-card"
      data-testid={`wine-card-${wine.id}`}
    >
      {sale && (
        <span
          className="absolute left-3 top-3 z-10 inline-flex items-center gap-1 rounded-full bg-bordeaux px-2 py-1 text-[10px] font-semibold text-crema shadow"
          data-testid="wine-card-badge-sale"
        >
          <Tag className="h-3 w-3" /> In vendita
        </span>
      )}
      {mostraStato && (
        <span
          className={`absolute right-3 bottom-3 z-10 rounded-full px-2 py-0.5 text-[10px] font-semibold shadow ${listingStatusTone[stato!]}`}
          data-testid="wine-card-status"
        >
          {listingStatusLabel[stato!]}
        </span>
      )}
      <div className="absolute left-3 top-12 z-10">
        <DrinkBadge wineId={wine.id} />
      </div>
      <button
        onClick={(e) => {
          e.preventDefault();
          toggleFavorite(wine.id);
        }}
        aria-label={fav ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti"}
        data-testid={`wine-card-favorite-${wine.id}`}
        className="absolute right-3 top-3 z-10 grid h-9 w-9 place-items-center rounded-full bg-crema/90 backdrop-blur transition-transform duration-200 hover:scale-110 active:scale-95"
      >
        <Heart
          className={`h-4 w-4 transition-colors ${fav ? "fill-bordeaux text-bordeaux" : "text-antracite"}`}
        />
      </button>
      <Link
        to="/annuncio/$id"
        params={{ id: wine.id }}
        data-testid={`wine-card-link-${wine.id}`}
        className="block"
      >
        <div className="img-sheen aspect-[4/5] overflow-hidden bg-secondary">
          <SafeImage
            src={wine.immagini[0]}
            alt={`${wine.nome} ${wine.annata}`}
            className="h-full w-full object-cover img-reveal group-hover:scale-110"
            fallbackLabel="Foto non disponibile"
          />
        </div>
        <div className="p-4">
          <p className="text-[11px] uppercase tracking-wider text-salvia">{wine.produttore}</p>
          <h3 className="mt-1 line-clamp-2 font-serif text-lg font-semibold leading-tight">
            {wine.nome} <span className="text-antracite/70">{wine.annata}</span>
          </h3>
          <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
            <MapPin className="h-3 w-3" /> {wine.venditore.citta}
            {wine.venditore.verificato && (
              <span className="ml-1 inline-flex items-center gap-0.5 rounded-full bg-salvia/15 px-1.5 py-0.5 text-[10px] text-salvia">
                <ShieldCheck className="h-2.5 w-2.5" /> Verificato
              </span>
            )}
          </p>
          <div className="mt-3 flex items-baseline justify-between">
            <div>
              {priceHidden ? (
                <p className="flex items-center gap-1 font-serif text-sm text-muted-foreground">
                  <EyeOff className="h-3.5 w-3.5" /> Prezzo riservato
                </p>
              ) : (
                <>
                  <p className="font-serif text-xl font-semibold text-bordeaux">
                    {formatEUR(wine.prezzo)}
                  </p>
                  {wine.prezzoMercato && wine.prezzoMercato > wine.prezzo && (
                    <p className="text-xs text-muted-foreground line-through">
                      {formatEUR(wine.prezzoMercato)}
                    </p>
                  )}
                </>
              )}
            </div>
            <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-medium">
              {wine.tipo}
            </span>
          </div>
        </div>
      </Link>
    </div>
  );
}
