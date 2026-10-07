"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  CalendarClock,
  Clock,
  ExternalLink,
  Info,
  Sparkles,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  MARKET_VALIDATION_CELLAR_BOTTLES,
  MARKET_VALIDATION_CELLAR_STATUS_LABEL,
  MARKET_VALIDATION_CELLAR_THEMES,
  MARKET_VALIDATION_CELLAR_VALUE_SERIES,
  marketValidationCellarDrinkWindow,
  marketValidationCellarKpis,
  marketValidationCellarPhaseLabel,
  marketValidationCellarThemeLabel,
  type MarketValidationCellarBottle,
  type MarketValidationCellarStatus,
  type MarketValidationCellarTheme,
} from "@/lib/market-validation/cellar-preview";
import { formatMarketValidationEuroCents } from "@/lib/market-validation/mv2-flow";

// Anteprima solo visiva: niente eventi, niente servizi, niente salvataggi.
// La scelta del preset cambia soltanto l'aspetto di questo riquadro.

const STATUS_CLASS: Record<MarketValidationCellarStatus, string> = {
  in_vendita: "bg-bordeaux/15 text-bordeaux",
  privata: "bg-secondary text-antracite",
  cantina_pubblica: "bg-salvia-scuro text-crema",
};

const PHASE_CLASS: Record<MarketValidationCellarBottle["phase"], string> = {
  attesa: "bg-secondary text-antracite",
  pronto: "bg-salvia-scuro text-crema",
  ideale: "bg-bordeaux text-crema",
  presto: "bg-oro text-antracite",
};

const THEME_CLASS: Record<MarketValidationCellarTheme, { rack: string; slot: string }> = {
  moderna: { rack: "border-border bg-secondary/60", slot: "border-border bg-card" },
  classica: { rack: "border-bordeaux/20 bg-bordeaux/5", slot: "border-bordeaux/20 bg-crema" },
  rustica: { rack: "border-oro/40 bg-oro/15", slot: "border-oro/40 bg-oro/10" },
};

export function CellarPreview({ onBack }: { onBack: () => void }) {
  const [theme, setTheme] = useState<MarketValidationCellarTheme>("moderna");
  const kpis = marketValidationCellarKpis();
  const drinkWindow = marketValidationCellarDrinkWindow();
  const filledSlots = kpis.bottles;

  // La card sta in fondo all'hub: senza questo su smartphone l'anteprima si
  // aprirebbe a metà pagina.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, []);

  return (
    <section className="space-y-5" aria-labelledby="cellar-preview-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Anteprima</p>
          <h1 id="cellar-preview-title" className="mt-1 font-serif text-3xl font-semibold">La tua Cantina</h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
            Organizza la tua collezione, decidi quali bottiglie mostrare o vendere e segui nel tempo il valore della Cantina.
          </p>
        </div>
        <Button type="button" variant="outline" className="min-h-11 shrink-0" onClick={onBack}>Hub</Button>
      </div>

      <div className="flex items-start gap-3 rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm text-antracite">
        <Info className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
        <p>
          <strong>Dati di esempio.</strong> Nessuna bottiglia reale viene aggiunta e nulla viene salvato.
        </p>
      </div>

      <section aria-labelledby="cellar-kpi-title" className="space-y-2">
        <h2 id="cellar-kpi-title" className="sr-only">Numeri della Cantina d&apos;esempio</h2>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <ExampleKpi label="Bottiglie" value={String(kpis.bottles)} />
          <ExampleKpi label="Valore di riferimento" value={formatMarketValidationEuroCents(kpis.referenceValueCents)} />
          <ExampleKpi label="In vendita" value={String(kpis.forSale)} />
          <ExampleKpi label="Pronte da bere" value={String(kpis.readyToDrink)} />
        </div>
      </section>

      <section aria-labelledby="cellar-bottles-title" className="space-y-3">
        <div>
          <h2 id="cellar-bottles-title" className="font-serif text-xl font-semibold">Le bottiglie</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Per ogni bottiglia decidi tu: tenerla solo in Cantina, mostrarla nel profilo o metterla in vendita.
          </p>
        </div>
        <ul className="grid gap-3 md:grid-cols-2">
          {MARKET_VALIDATION_CELLAR_BOTTLES.map((bottle) => (
            <li key={bottle.id} className="rounded-2xl border border-border bg-card p-4" data-testid="mv-cellar-bottle">
              <p className="text-xs text-muted-foreground">{bottle.producer}</p>
              <h3 className="font-serif text-lg font-semibold">{bottle.wine} {bottle.vintage}</h3>
              <p className="text-sm text-muted-foreground">
                {bottle.denomination} · {bottle.quantity} {bottle.quantity === 1 ? "bottiglia" : "bottiglie"}
              </p>
              <div className="mt-3 flex flex-wrap gap-2 text-[11px] font-semibold">
                <span className={`rounded-full px-2.5 py-1 ${STATUS_CLASS[bottle.status]}`}>
                  {MARKET_VALIDATION_CELLAR_STATUS_LABEL[bottle.status]}
                </span>
                <span className={`rounded-full px-2.5 py-1 ${PHASE_CLASS[bottle.phase]}`}>
                  {marketValidationCellarPhaseLabel(bottle.phase)}
                </span>
                {bottle.plannedOpening && (
                  <span className="rounded-full border border-border px-2.5 py-1 text-antracite">
                    Apertura programmata: {bottle.plannedOpening}
                  </span>
                )}
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="cellar-space-title" className="space-y-3 rounded-2xl border border-border bg-card p-4 md:p-6">
        <div>
          <h2 id="cellar-space-title" className="font-serif text-xl font-semibold">Il tuo spazio</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            La Cantina può essere organizzata e personalizzata in base al tuo spazio: nella Cantina reale crei i tuoi ambienti e li guardi anche in 3D.
          </p>
        </div>
        <div className="flex flex-wrap gap-2" role="group" aria-label="Preset estetico d'esempio">
          {MARKET_VALIDATION_CELLAR_THEMES.map((option) => (
            <button
              key={option}
              type="button"
              aria-pressed={theme === option}
              onClick={() => setTheme(option)}
              className={`min-h-11 rounded-full border px-4 text-sm ${theme === option ? "border-bordeaux bg-bordeaux text-crema" : "border-border"}`}
            >
              {marketValidationCellarThemeLabel(option)}
            </button>
          ))}
        </div>
        <div
          className={`grid grid-cols-8 gap-1.5 rounded-xl border p-3 ${THEME_CLASS[theme].rack}`}
          aria-hidden
          data-testid="mv-cellar-rack"
        >
          {Array.from({ length: 16 }, (_, index) => (
            <span
              key={index}
              className={`aspect-square rounded-full border ${index < filledSlots ? "border-bordeaux/40 bg-bordeaux/70" : THEME_CLASS[theme].slot}`}
            />
          ))}
        </div>
        <p className="text-xs text-muted-foreground">La scelta cambia solo questa anteprima e non viene salvata.</p>
      </section>

      <section aria-labelledby="cellar-value-title" className="space-y-3 rounded-2xl border border-border bg-card p-4 md:p-6">
        <div>
          <h2 id="cellar-value-title" className="font-serif text-xl font-semibold">Valore della Cantina nel tempo</h2>
          <p className="mt-1 text-xs font-semibold text-bordeaux">Dati di esempio, non dati di mercato.</p>
        </div>
        <ValueSparkline />
        <p className="text-sm text-muted-foreground">
          Nella Cantina reale la contabilità può mostrare il valore di riferimento Vinea, il capitale noto, gli eventuali incassi trasferiti, la performance e il valore della Cantina nel tempo. La serie parte dal primo valore di riferimento osservato: nulla viene ricostruito all&apos;indietro.
        </p>
      </section>

      <section aria-labelledby="cellar-drink-title" className="space-y-3">
        <div>
          <h2 id="cellar-drink-title" className="font-serif text-xl font-semibold">Quando berle</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            La Cantina non è solo un valore: ti ricorda che cosa aprire adesso e che cosa lasciare riposare.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <DrinkTile icon={Sparkles} title="Cosa bere adesso" count={drinkWindow.drinkNow} />
          <DrinkTile icon={Clock} title="Da bere presto" count={drinkWindow.drinkSoon} />
          <DrinkTile icon={CalendarClock} title="Da attendere" count={drinkWindow.wait} />
          <DrinkTile icon={CalendarClock} title="Aperture programmate" count={drinkWindow.plannedOpenings} />
        </div>
      </section>

      <div className="space-y-3 rounded-2xl border border-bordeaux/20 bg-bordeaux/5 p-4">
        <p className="text-sm">Per utilizzare la tua Cantina personale serve un account Vinea.</p>
        <Link
          href="/cantina"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex min-h-11 items-center gap-1 text-sm font-medium text-bordeaux hover:underline"
        >
          Apri la vera Cantina <ExternalLink className="h-4 w-4" aria-hidden /><span className="sr-only"> (si apre in una nuova scheda)</span>
        </Link>
      </div>

      <Button type="button" variant="outline" className="min-h-12 w-full" onClick={onBack}>
        Torna all&apos;hub
      </Button>
    </section>
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

function ValueSparkline() {
  const values = MARKET_VALIDATION_CELLAR_VALUE_SERIES.map((point) => point.valueCents);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = Math.max(max - min, 1);
  const width = 240;
  const height = 64;
  const step = width / (values.length - 1);
  const points = values
    .map((value, index) => `${(index * step).toFixed(1)},${(height - 6 - ((value - min) / span) * (height - 12)).toFixed(1)}`)
    .join(" ");
  const first = MARKET_VALIDATION_CELLAR_VALUE_SERIES[0]!;
  const last = MARKET_VALIDATION_CELLAR_VALUE_SERIES[MARKET_VALIDATION_CELLAR_VALUE_SERIES.length - 1]!;
  const description = `Esempio: valore della Cantina da ${formatMarketValidationEuroCents(first.valueCents)} a ${formatMarketValidationEuroCents(last.valueCents)} in ${values.length} mesi.`;

  return (
    <figure className="space-y-2">
      <svg viewBox={`0 0 ${width} ${height}`} className="h-20 w-full" role="img" aria-label={description} preserveAspectRatio="none">
        <polyline points={points} fill="none" stroke="var(--bordeaux)" strokeWidth={2} vectorEffect="non-scaling-stroke" />
      </svg>
      <figcaption className="flex justify-between text-xs text-muted-foreground">
        <span>{first.month} · {formatMarketValidationEuroCents(first.valueCents)}</span>
        <span>{last.month} · {formatMarketValidationEuroCents(last.valueCents)}</span>
      </figcaption>
    </figure>
  );
}
