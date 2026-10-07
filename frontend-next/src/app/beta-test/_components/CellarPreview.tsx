"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import {
  Box,
  CalendarClock,
  Clock,
  Eye,
  Info,
  LockKeyhole,
  Sparkles,
  Store,
  TrendingUp,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import {
  MARKET_VALIDATION_CELLAR_BOTTLES,
  MARKET_VALIDATION_CELLAR_REFERENCE_YEAR,
  MARKET_VALIDATION_CELLAR_STATUS_LABEL,
  MARKET_VALIDATION_CELLAR_STATUS_ORDER,
  MARKET_VALIDATION_CELLAR_STATUS_TEXT,
  MARKET_VALIDATION_CELLAR_THEMES,
  MARKET_VALIDATION_CELLAR_VALUE_SERIES,
  marketValidationCellarDrinkWindow,
  marketValidationCellarKpis,
  marketValidationCellarMaturityPercent,
  marketValidationCellarPhaseLabel,
  marketValidationCellarStatusCounts,
  marketValidationCellarThemeLabel,
  type MarketValidationCellarBottle,
  type MarketValidationCellarStatus,
} from "@/lib/market-validation/cellar-preview";
import { formatMarketValidationEuroCents } from "@/lib/market-validation/mv2-flow";
import { DemoBackButton } from "./DemoBackButton";

// Anteprima solo visiva: niente eventi, niente servizi, niente salvataggi.
// Filtri e dettaglio bottiglia cambiano soltanto ciò che si vede qui.

const STATUS_CLASS: Record<MarketValidationCellarStatus, string> = {
  in_vendita: "bg-bordeaux text-crema",
  privata: "bg-antracite text-crema",
  cantina_pubblica: "bg-salvia-scuro text-crema",
};

const STATUS_ICON: Record<MarketValidationCellarStatus, LucideIcon> = {
  in_vendita: Store,
  privata: LockKeyhole,
  cantina_pubblica: Eye,
};

const PHASE_CLASS: Record<MarketValidationCellarBottle["phase"], string> = {
  attesa: "bg-secondary text-antracite",
  pronto: "bg-salvia/15 text-salvia-scuro",
  ideale: "bg-bordeaux/10 text-bordeaux",
  presto: "bg-oro/20 text-antracite",
};

type Filter = MarketValidationCellarStatus | "tutte";

export function CellarPreview({ onBack }: { onBack: () => void }) {
  const [filter, setFilter] = useState<Filter>("tutte");
  const [selected, setSelected] = useState<MarketValidationCellarBottle | null>(null);
  const kpis = marketValidationCellarKpis();
  const drinkWindow = marketValidationCellarDrinkWindow();
  const counts = marketValidationCellarStatusCounts();
  const bottles = MARKET_VALIDATION_CELLAR_BOTTLES.filter(
    (bottle) => filter === "tutte" || bottle.status === filter,
  );

  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [selected]);

  if (selected) return <CellarBottleDetail bottle={selected} onBack={() => setSelected(null)} />;

  return (
    <section className="space-y-8" aria-labelledby="cellar-preview-title">
      <DemoBackButton onBack={onBack} />

      <div className="relative overflow-hidden rounded-3xl bg-antracite text-crema">
        <Image src="/images/vinea-crate.jpg" alt="" fill priority sizes="(max-width: 768px) 100vw, 1152px" className="object-cover opacity-45" />
        <div className="relative space-y-3 bg-gradient-to-t from-antracite via-antracite/70 to-transparent p-6 pt-24 md:p-10 md:pt-40">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-oro">Scopri · Anteprima Cantina</p>
          <h1 id="cellar-preview-title" className="font-serif text-4xl font-semibold md:text-5xl">La tua Cantina</h1>
          <p className="max-w-2xl text-base leading-7 text-crema/90 md:text-lg">
            Tutta la tua collezione in un unico posto. Ogni bottiglia ha il suo valore, la sua finestra di bevuta e la visibilità che scegli tu: privata, nel profilo o in vendita.
          </p>
        </div>
      </div>

      <p className="flex items-start gap-3 rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm leading-6 text-antracite">
        <Info className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
        <span><strong>Dati di esempio.</strong> Nessuna bottiglia reale viene aggiunta e nulla viene salvato.</span>
      </p>

      <section aria-labelledby="cellar-kpi-title">
        <h2 id="cellar-kpi-title" className="sr-only">Numeri della Cantina d&apos;esempio</h2>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <ExampleKpi label="Bottiglie" value={String(kpis.bottles)} />
          <ExampleKpi label="Valore di riferimento" value={formatMarketValidationEuroCents(kpis.referenceValueCents)} />
          <ExampleKpi label="In vendita" value={String(kpis.forSale)} />
          <ExampleKpi label="Pronte da bere" value={String(kpis.readyToDrink)} />
        </div>
      </section>

      <section aria-labelledby="cellar-bottles-title" className="space-y-4">
        <div>
          <h2 id="cellar-bottles-title" className="font-serif text-2xl font-semibold">Le tue bottiglie</h2>
          <p className="mt-1 text-base leading-7 text-muted-foreground">
            Per ogni bottiglia decidi tu: tenerla solo in Cantina, mostrarla nel profilo o metterla in vendita. Tocca una bottiglia per aprirne la scheda.
          </p>
        </div>
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1" role="group" aria-label="Filtra le bottiglie d'esempio">
          {(["tutte", ...MARKET_VALIDATION_CELLAR_STATUS_ORDER] as const).map((option) => (
            <button
              key={option}
              type="button"
              aria-pressed={filter === option}
              onClick={() => setFilter(option)}
              className={`min-h-11 shrink-0 rounded-full border px-4 text-sm font-medium transition ${filter === option ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
            >
              {option === "tutte" ? "Tutte" : MARKET_VALIDATION_CELLAR_STATUS_LABEL[option]}
              <span className="ml-1.5 opacity-70">{option === "tutte" ? MARKET_VALIDATION_CELLAR_BOTTLES.length : counts[option]}</span>
            </button>
          ))}
        </div>
        <ul className="grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3">
          {bottles.map((bottle) => (
            <li key={bottle.id} data-testid="mv-cellar-bottle">
              <button
                type="button"
                onClick={() => setSelected(bottle)}
                className="group flex h-full w-full flex-col overflow-hidden rounded-2xl border border-border bg-card text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                <span className="relative block aspect-[4/5] overflow-hidden bg-secondary">
                  <WineThumbnail src={bottle.image} alt={`${bottle.wine}, immagine dimostrativa`} className="h-full w-full object-cover transition group-hover:scale-[1.02]" sizes="(max-width: 768px) 50vw, 33vw" />
                  <StatusBadge status={bottle.status} className="absolute left-2 top-2" />
                  {bottle.quantity > 1 && (
                    <span className="absolute right-2 top-2 rounded-full bg-background/95 px-2 py-0.5 text-xs font-semibold shadow">×{bottle.quantity}</span>
                  )}
                </span>
                <span className="flex flex-1 flex-col p-3">
                  <span className="line-clamp-1 text-xs text-muted-foreground">{bottle.producer}</span>
                  <span className="mt-0.5 line-clamp-2 font-serif text-base font-semibold leading-tight">{bottle.wine} {bottle.vintage}</span>
                  <span className="mt-1 line-clamp-1 text-xs text-muted-foreground">{bottle.denomination}</span>
                  <span className={`mt-2 self-start rounded-full px-2 py-0.5 text-[11px] font-semibold ${PHASE_CLASS[bottle.phase]}`}>
                    {marketValidationCellarPhaseLabel(bottle.phase)}
                  </span>
                  <MaturityBar bottle={bottle} className="mt-auto pt-3" />
                </span>
              </button>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="cellar-visibility-title" className="space-y-3">
        <h2 id="cellar-visibility-title" className="font-serif text-2xl font-semibold">Tre modi di tenere una bottiglia</h2>
        <div className="grid gap-3 md:grid-cols-3">
          {MARKET_VALIDATION_CELLAR_STATUS_ORDER.map((status) => {
            const Icon = STATUS_ICON[status];
            return (
              <article key={status} className="rounded-2xl border border-border bg-card p-4">
                <div className="flex items-center gap-3">
                  <span className={`grid h-10 w-10 place-items-center rounded-full ${STATUS_CLASS[status]}`}><Icon className="h-5 w-5" aria-hidden /></span>
                  <div>
                    <h3 className="text-base font-semibold">{MARKET_VALIDATION_CELLAR_STATUS_LABEL[status]}</h3>
                    <p className="text-xs text-muted-foreground">{counts[status]} etichette nell&apos;esempio</p>
                  </div>
                </div>
                <p className="mt-3 text-sm leading-6 text-muted-foreground">{MARKET_VALIDATION_CELLAR_STATUS_TEXT[status]}</p>
              </article>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="cellar-value-title" className="space-y-4 rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex items-start gap-3">
          <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><TrendingUp className="h-5 w-5" aria-hidden /></span>
          <div>
            <h2 id="cellar-value-title" className="font-serif text-2xl font-semibold">Valore della Cantina nel tempo</h2>
            <p className="mt-1 text-sm font-semibold text-bordeaux">Dati di esempio, non dati di mercato.</p>
          </div>
        </div>
        <ValueChart />
        <p className="text-base leading-7 text-muted-foreground">
          Nella Cantina reale la contabilità può mostrare il valore di riferimento Vinea, il capitale noto, gli eventuali incassi trasferiti, la performance e il valore della Cantina nel tempo. La serie parte dal primo valore di riferimento osservato: nulla viene ricostruito all&apos;indietro.
        </p>
      </section>

      <section aria-labelledby="cellar-drink-title" className="space-y-3">
        <div>
          <h2 id="cellar-drink-title" className="font-serif text-2xl font-semibold">Quando berle</h2>
          <p className="mt-1 text-base leading-7 text-muted-foreground">
            La Cantina non è solo un valore: per ogni bottiglia segue la finestra di bevuta e ti ricorda che cosa aprire adesso e che cosa lasciare riposare. Nell&apos;esempio le finestre sono calcolate sull&apos;anno {MARKET_VALIDATION_CELLAR_REFERENCE_YEAR}.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <DrinkTile icon={Sparkles} title="Cosa bere adesso" count={drinkWindow.drinkNow} />
          <DrinkTile icon={Clock} title="Da bere presto" count={drinkWindow.drinkSoon} />
          <DrinkTile icon={CalendarClock} title="Da attendere" count={drinkWindow.wait} />
          <DrinkTile icon={CalendarClock} title="Aperture programmate" count={drinkWindow.plannedOpenings} />
        </div>
      </section>

      <section aria-labelledby="cellar-space-title" className="overflow-hidden rounded-3xl border border-border bg-card md:grid md:grid-cols-2">
        <div className="relative aspect-[16/10] bg-secondary md:aspect-auto">
          <Image src="/images/vinea-cellar.jpg" alt="Immagine d'esempio di una cantina arredata con scaffalature in legno" fill sizes="(max-width: 768px) 100vw, 50vw" className="object-cover" />
          <span className="absolute left-3 top-3 rounded-full bg-background/95 px-2.5 py-1 text-xs font-semibold shadow">Immagine d&apos;esempio</span>
        </div>
        <div className="space-y-3 p-5 md:p-8">
          <span className="grid h-10 w-10 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><Box className="h-5 w-5" aria-hidden /></span>
          <h2 id="cellar-space-title" className="font-serif text-2xl font-semibold">Il tuo spazio, anche in 3D</h2>
          <p className="text-base leading-7 text-muted-foreground">
            La Cantina può essere organizzata e personalizzata in base al tuo spazio: nella Cantina reale crei i tuoi ambienti, li arredi e li guardi anche in 3D.
          </p>
          <div className="flex flex-wrap gap-2" aria-label="Alcuni stili disponibili">
            {MARKET_VALIDATION_CELLAR_THEMES.map((theme) => (
              <span key={theme} className="rounded-full border border-border px-3 py-1 text-sm">{marketValidationCellarThemeLabel(theme)}</span>
            ))}
          </div>
          <p className="text-sm text-muted-foreground">In questa anteprima la vista 3D non è disponibile.</p>
        </div>
      </section>

      <Button type="button" className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" onClick={onBack}>
        Torna al test
      </Button>
    </section>
  );
}

function CellarBottleDetail({ bottle, onBack }: { bottle: MarketValidationCellarBottle; onBack: () => void }) {
  return (
    <section className="space-y-5" aria-labelledby="cellar-bottle-title">
      <DemoBackButton onBack={onBack} />
      <div className="grid overflow-hidden rounded-3xl border border-border bg-card md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
        <div className="relative aspect-[4/5] min-w-0 bg-secondary md:aspect-auto">
          <WineThumbnail src={bottle.image} alt={`${bottle.wine}, immagine dimostrativa`} className="h-full w-full object-cover" sizes="(max-width: 768px) 100vw, 45vw" />
          <StatusBadge status={bottle.status} className="absolute left-3 top-3" />
        </div>
        <div className="min-w-0 space-y-5 p-5 md:p-8">
          <div>
            <p className="text-sm text-muted-foreground">{bottle.producer}</p>
            <h1 id="cellar-bottle-title" className="mt-1 font-serif text-3xl font-semibold">{bottle.wine} {bottle.vintage}</h1>
            <p className="mt-1 text-base text-muted-foreground">{bottle.denomination}</p>
          </div>

          <dl className="grid grid-cols-2 gap-3 text-sm">
            <div className="rounded-xl bg-secondary/60 p-3">
              <dt className="text-xs text-muted-foreground">Bottiglie</dt>
              <dd className="mt-1 text-base font-medium">{bottle.quantity}</dd>
            </div>
            <div className="rounded-xl bg-secondary/60 p-3">
              <dt className="text-xs text-muted-foreground">Valore di riferimento</dt>
              <dd className="mt-1 text-base font-medium">{formatMarketValidationEuroCents(bottle.referenceValueCents)} cad.</dd>
            </div>
          </dl>

          <div className="rounded-2xl border border-border p-4">
            <p className="text-sm font-semibold">{MARKET_VALIDATION_CELLAR_STATUS_LABEL[bottle.status]}</p>
            <p className="mt-1 text-sm leading-6 text-muted-foreground">{MARKET_VALIDATION_CELLAR_STATUS_TEXT[bottle.status]}</p>
          </div>

          <div className="space-y-2 rounded-2xl border border-border p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-sm font-semibold">Finestra di bevuta</p>
              <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${PHASE_CLASS[bottle.phase]}`}>{marketValidationCellarPhaseLabel(bottle.phase)}</span>
            </div>
            <MaturityBar bottle={bottle} />
            {bottle.plannedOpening && (
              <p className="flex items-center gap-2 text-sm"><CalendarClock className="h-4 w-4 text-bordeaux" aria-hidden /> Apertura programmata: {bottle.plannedOpening}</p>
            )}
          </div>

          <p className="text-sm text-muted-foreground">Scheda d&apos;esempio: bottiglia, valore e date sono fittizi.</p>
        </div>
      </div>
    </section>
  );
}

function StatusBadge({ status, className }: { status: MarketValidationCellarStatus; className: string }) {
  const Icon = STATUS_ICON[status];
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-semibold shadow ${STATUS_CLASS[status]} ${className}`}>
      <Icon className="h-3 w-3" aria-hidden />
      {MARKET_VALIDATION_CELLAR_STATUS_LABEL[status]}
    </span>
  );
}

function MaturityBar({ bottle, className = "" }: { bottle: MarketValidationCellarBottle; className?: string }) {
  const percent = marketValidationCellarMaturityPercent(bottle);
  return (
    <span className={`block ${className}`}>
      <span
        className="relative block h-1.5 rounded-full bg-gradient-to-r from-secondary via-salvia/60 to-bordeaux/70"
        role="img"
        aria-label={`Finestra di bevuta ${bottle.drinkFrom}–${bottle.drinkTo}, oggi al ${percent}%`}
      >
        <span className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-card bg-antracite" style={{ left: `${percent}%` }} />
      </span>
      <span className="mt-1 flex justify-between text-[11px] text-muted-foreground">
        <span>{bottle.drinkFrom}</span>
        <span>{bottle.drinkTo}</span>
      </span>
    </span>
  );
}

function ExampleKpi({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-4">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 font-serif text-2xl font-semibold text-bordeaux">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">Esempio</p>
    </div>
  );
}

function DrinkTile({ icon: Icon, title, count }: { icon: LucideIcon; title: string; count: number }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-4">
      <Icon className="h-5 w-5 text-bordeaux" aria-hidden />
      <p className="mt-2 font-serif text-2xl font-semibold text-bordeaux">{count}</p>
      <p className="text-sm font-medium">{title}</p>
    </div>
  );
}

function ValueChart() {
  const values = MARKET_VALIDATION_CELLAR_VALUE_SERIES.map((point) => point.valueCents);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = Math.max(max - min, 1);
  const width = 300;
  const height = 96;
  const step = width / (values.length - 1);
  const coordinates = values.map((value, index) => [
    index * step,
    height - 8 - ((value - min) / span) * (height - 20),
  ] as const);
  const line = coordinates.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const area = `0,${height} ${line} ${width},${height}`;
  const first = MARKET_VALIDATION_CELLAR_VALUE_SERIES[0]!;
  const last = MARKET_VALIDATION_CELLAR_VALUE_SERIES[MARKET_VALIDATION_CELLAR_VALUE_SERIES.length - 1]!;
  const change = ((last.valueCents - first.valueCents) / first.valueCents) * 100;
  const description = `Esempio: valore della Cantina da ${formatMarketValidationEuroCents(first.valueCents)} a ${formatMarketValidationEuroCents(last.valueCents)} in ${values.length} mesi.`;

  return (
    <figure className="space-y-3">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-serif text-3xl font-semibold text-bordeaux">{formatMarketValidationEuroCents(last.valueCents)}</span>
        <span className="rounded-full bg-salvia/15 px-2 py-0.5 text-sm font-semibold text-salvia-scuro">
          +{change.toLocaleString("it-IT", { maximumFractionDigits: 1 })}% in {values.length} mesi
        </span>
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} className="h-28 w-full" role="img" aria-label={description} preserveAspectRatio="none">
        <polygon points={area} fill="var(--bordeaux)" opacity={0.08} />
        <polyline points={line} fill="none" stroke="var(--bordeaux)" strokeWidth={2.5} vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
      </svg>
      <figcaption className="flex justify-between text-xs text-muted-foreground">
        {MARKET_VALIDATION_CELLAR_VALUE_SERIES.map((point) => <span key={point.month}>{point.month}</span>)}
      </figcaption>
    </figure>
  );
}
