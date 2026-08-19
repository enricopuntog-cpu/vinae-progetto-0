"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { MapPin, ShieldCheck, Tag, EyeOff, Wine as WineIcon } from "lucide-react";
import type { Wine } from "@/data/wines";
import type { StatoBottiglia } from "@/data/cellar";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { DrinkBadge } from "@/components/vinea/DrinkWindow";
import { SafeImage } from "@/components/vinea/States";
import { badgeStatoBottiglia } from "@/lib/cantina/badge-stato";

const DetailLink = ({
  href,
  className,
  testId,
  children,
}: {
  href: string | null;
  className: string;
  testId: string;
  children: ReactNode;
}) =>
  href ? (
    <Link href={href} data-testid={testId} className={className}>
      {children}
    </Link>
  ) : (
    <div data-testid={testId} className={className}>
      {children}
    </div>
  );

export function WineCard({
  wine,
  variant = "grid",
  showSaleBadge = false,
  hidePriceIfPrivate = false,
  statoBottiglia,
}: {
  wine: Wine;
  variant?: "grid" | "list";
  showSaleBadge?: boolean;
  hidePriceIfPrivate?: boolean;
  /**
   * Lo stato della bottiglia che questa scheda rappresenta, quando ce n'è una.
   *
   * Assente ovunque tranne che in Cantina, ed è giusto così: su `/esplora` e
   * sulla scheda di un annuncio si guarda il vino di qualcun altro, e lo stato
   * della propria bottiglia lì non vuol dire niente. Per la stessa ragione non
   * è un campo di `Wine`, che è la forma del catalogo e non della cantina.
   */
  statoBottiglia?: StatoBottiglia;
}) {
  const { inVendita, prezzoNascosto } = useVinea();
  const cellarKey = wine.wineSlug ?? wine.id;
  const sale = showSaleBadge && inVendita.has(cellarKey);
  const priceHidden = hidePriceIfPrivate && prezzoNascosto.has(cellarKey);
  const priceUnavailable = wine.detailHref === null && wine.prezzo === 0;
  const detailHref =
    wine.detailHref === undefined ? `/annuncio/${wine.id}` : wine.detailHref;
  // La regola di quale stato meriti un badge sta nel modulo, non qui: è là che
  // ha dei test, ed è là che la condizione di non costruirne uno per
  // `consumata` è scritta una volta sola.
  const badgeStato = badgeStatoBottiglia(statoBottiglia);

  if (variant === "list") {
    return (
      <DetailLink
        href={detailHref}
        testId={`wine-card-list-${wine.id}`}
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
          {/* In basso e non in alto a destra: qui la foto è 80×96 px, e due
              pastiglie affiancate in cima non ci starebbero. */}
          {badgeStato && (
            <span
              className={`absolute bottom-1 left-1 inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-semibold shadow ${badgeStato.classi}`}
              data-testid="wine-card-badge-aperta"
            >
              <WineIcon className="h-2.5 w-2.5" /> {badgeStato.testo}
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
            ) : priceUnavailable ? (
              <p className="text-xs text-muted-foreground">Nessun prezzo</p>
            ) : (
              <p className="font-serif text-lg font-semibold text-bordeaux">
                {formatEUR(wine.prezzo)}
              </p>
            )}
            <span className="text-[10px] text-muted-foreground">{wine.condizione}</span>
          </div>
        </div>
      </DetailLink>
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
      <div className="absolute left-3 top-12 z-10">
        {/* I metadati della finestra di bevuta sono indicizzati per vino, non
            per annuncio: su dati reali `id` è lo slug dell'annuncio e
            servirebbe a nulla. Vedi il commento su Wine.wineSlug. */}
        <DrinkBadge wineId={wine.wineSlug ?? wine.id} />
      </div>
      {/* L'angolo opposto a «In vendita» (left-3 top-3) e alla finestra di
          bevuta (left-3 top-12): una posizione fissa, così il badge non si
          sposta a seconda di quali vicini abbia quel giorno. */}
      {badgeStato && (
        <span
          className={`absolute right-3 top-3 z-10 inline-flex items-center gap-1 rounded-full px-2 py-1 text-[10px] font-semibold shadow ${badgeStato.classi}`}
          data-testid="wine-card-badge-aperta"
        >
          <WineIcon className="h-3 w-3" /> {badgeStato.testo}
        </span>
      )}
      <DetailLink
        href={detailHref}
        testId={`wine-card-link-${wine.id}`}
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
              ) : priceUnavailable ? (
                <p className="text-xs text-muted-foreground">Nessun prezzo</p>
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
      </DetailLink>
    </div>
  );
}
