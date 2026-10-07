"use client";

import { useEffect, useState } from "react";
import { Camera, Check, CheckCircle2, Sparkles, Store, Wine } from "lucide-react";
import { Button } from "@/components/ui/button";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import { formatMarketValidationEuroCents } from "@/lib/market-validation/mv2-flow";
import {
  MARKET_VALIDATION_SELL_DEMO_BOTTLES,
  MARKET_VALIDATION_SELL_DEMO_DESTINATIONS,
  MARKET_VALIDATION_SELL_DEMO_FIELDS,
  MARKET_VALIDATION_SELL_DEMO_STEPS,
  type MarketValidationSellDemoBottle,
} from "@/lib/market-validation/sell-demo";
import type { MarketValidationCellarStatus } from "@/lib/market-validation/cellar-preview";
import { DemoBackButton } from "./DemoBackButton";
import type { MarketValidationTrack } from "./types";

type Step = 0 | 1 | 2 | 3;

// Demo guidata del percorso Vendi: tutto resta in memoria in questa schermata.
// Lo step si chiude solo sulla conferma esplicita dell'ultimo passo, e solo
// dopo che `sell_completed` è stato registrato.
export function SellDemo({
  completed,
  track,
  onCompleted,
  onBack,
}: {
  completed: boolean;
  track: MarketValidationTrack;
  onCompleted: () => void;
  onBack: () => void;
}) {
  const [step, setStep] = useState<Step>(0);
  const [bottle, setBottle] = useState<MarketValidationSellDemoBottle | null>(null);
  const [aiFilled, setAiFilled] = useState(false);
  const [destination, setDestination] = useState<MarketValidationCellarStatus | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showSuccess, setShowSuccess] = useState(completed);

  useEffect(() => {
    void track("sell_started", {}, "sell_started");
  }, [track]);

  // Ogni passo riparte dall'alto: su smartphone il pulsante «Continua» sta in fondo.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [step, showSuccess]);

  const chosen = MARKET_VALIDATION_SELL_DEMO_DESTINATIONS.find((option) => option.status === destination);

  const back = () => {
    if (step === 0) {
      onBack();
      return;
    }
    setError(null);
    setStep((current) => (current - 1) as Step);
  };

  const restart = () => {
    setBottle(null);
    setAiFilled(false);
    setDestination(null);
    setError(null);
    setStep(0);
    setShowSuccess(false);
  };

  const confirm = async () => {
    if (pending || !bottle || !aiFilled || !destination) return;
    setPending(true);
    setError(null);
    const result = await track("sell_completed", {}, "sell_completed");
    setPending(false);
    if (!result.ok) {
      setError("Non siamo riusciti a registrare la simulazione. Riprova: le tue scelte restano qui.");
      return;
    }
    onCompleted();
    setShowSuccess(true);
  };

  if (showSuccess) {
    return (
      <section className="mx-auto max-w-xl space-y-5" aria-labelledby="sell-success-title">
        <DemoBackButton onBack={onBack} />
        <div className="rounded-3xl border border-salvia/40 bg-card p-6 text-center md:p-9">
          <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-salvia/15 text-salvia"><CheckCircle2 className="h-7 w-7" aria-hidden /></span>
          <p className="mt-4 text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Step 2 completato</p>
          <h1 id="sell-success-title" className="mt-2 font-serif text-3xl font-semibold">Bottiglia aggiunta</h1>
          <p className="mt-3 text-base leading-7 text-muted-foreground">
            {chosen ? `${chosen.outcome} ` : ""}Era una simulazione: nessun annuncio reale, nessuna foto caricata e nulla di salvato.
          </p>
          <Button type="button" className="mt-6 min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" onClick={onBack}>Torna al test</Button>
          <Button type="button" variant="ghost" className="mt-2 min-h-11 w-full text-base" onClick={restart}>Riprova la demo</Button>
        </div>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-2xl space-y-5" aria-labelledby="sell-title">
      <DemoBackButton onBack={back} />
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Step 2 · Demo Vendi</p>
        <h1 id="sell-title" className="mt-1 font-serif text-3xl font-semibold">Aggiungi una bottiglia</h1>
        <p className="mt-2 text-base leading-7 text-muted-foreground">
          È lo stesso percorso di Vinea, in versione dimostrativa: in pochi passaggi la bottiglia entra nella tua Cantina o va in vendita.
        </p>
      </div>

      <ol className="grid grid-cols-4 gap-2" aria-label="Passaggi della demo">
        {MARKET_VALIDATION_SELL_DEMO_STEPS.map((label, index) => (
          <li key={label} aria-current={index === step ? "step" : undefined} className="space-y-1.5">
            <span className={`block h-1.5 rounded-full ${index <= step ? "bg-bordeaux" : "bg-secondary"}`} />
            <span className={`block text-xs sm:text-sm ${index === step ? "font-semibold text-bordeaux" : "text-muted-foreground"}`}>{label}</span>
          </li>
        ))}
      </ol>

      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        {step === 0 && (
          <div className="space-y-4">
            <StepTitle icon={Camera} title="Scegli la foto della bottiglia" text="Su Vinea scatti una foto o la scegli dal telefono. Qui usi una foto d'esempio: niente viene caricato." />
            <div className="grid grid-cols-3 gap-3" role="radiogroup" aria-label="Foto d'esempio">
              {MARKET_VALIDATION_SELL_DEMO_BOTTLES.map((option) => {
                const selected = bottle?.id === option.id;
                return (
                  <button
                    key={option.id}
                    type="button"
                    role="radio"
                    aria-checked={selected}
                    onClick={() => { setBottle(option); setAiFilled(false); }}
                    className={`overflow-hidden rounded-2xl border-2 text-left transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${selected ? "border-bordeaux shadow-md" : "border-border"}`}
                  >
                    <span className="relative block aspect-[4/5] bg-secondary">
                      <WineThumbnail src={option.image} alt={`Foto d'esempio: ${option.photoLabel}`} className="h-full w-full object-cover" sizes="(max-width: 640px) 33vw, 200px" />
                      {selected && <span className="absolute right-1.5 top-1.5 grid h-6 w-6 place-items-center rounded-full bg-bordeaux text-crema"><Check className="h-4 w-4" aria-hidden /></span>}
                    </span>
                    <span className="block p-2 text-xs font-medium sm:text-sm">{option.photoLabel}</span>
                  </button>
                );
              })}
            </div>
            <ContinueButton disabled={!bottle} onClick={() => setStep(1)} />
          </div>
        )}

        {step === 1 && bottle && (
          <div className="space-y-4">
            <StepTitle icon={Sparkles} title="L'assistente AI compila per te" text="Dalla foto l'assistente propone i dati della bottiglia. Tu controlli e correggi ogni campo: non pubblica nulla da solo." />
            {aiFilled ? (
              <dl className="grid gap-2 sm:grid-cols-2" aria-live="polite">
                {MARKET_VALIDATION_SELL_DEMO_FIELDS.map(([key, label]) => (
                  <div key={key} className="rounded-xl border border-border bg-secondary/40 p-3">
                    <dt className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                      {label}
                      <span className="inline-flex items-center gap-1 rounded-full bg-oro/15 px-2 py-0.5 text-[11px] font-semibold text-antracite"><Sparkles className="h-3 w-3" aria-hidden /> Suggerito</span>
                    </dt>
                    <dd className="mt-1 text-base font-medium">{bottle.suggestion[key]}</dd>
                  </div>
                ))}
              </dl>
            ) : (
              <Button type="button" variant="outline" className="min-h-12 w-full gap-2 border-bordeaux/40 text-base text-bordeaux" onClick={() => setAiFilled(true)}>
                <Sparkles className="h-4 w-4" aria-hidden /> Compila con l&apos;assistente AI
              </Button>
            )}
            <p className="text-sm text-muted-foreground">Suggerimenti d&apos;esempio già pronti: in questa demo nessuna AI analizza la foto.</p>
            <ContinueButton disabled={!aiFilled} onClick={() => setStep(2)} />
          </div>
        )}

        {step === 2 && bottle && (
          <div className="space-y-4">
            <StepTitle icon={Store} title="Come vuoi usare questa bottiglia?" text="Puoi tenerla solo per te, mostrarla nel profilo o metterla in vendita." />
            <div className="space-y-3" role="radiogroup" aria-label="Destinazione della bottiglia">
              {MARKET_VALIDATION_SELL_DEMO_DESTINATIONS.map((option) => {
                const selected = destination === option.status;
                return (
                  <button
                    key={option.status}
                    type="button"
                    role="radio"
                    aria-checked={selected}
                    onClick={() => setDestination(option.status)}
                    className={`flex w-full items-start gap-3 rounded-2xl border-2 p-4 text-left transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${selected ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
                  >
                    <span className={`mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full border-2 ${selected ? "border-bordeaux bg-bordeaux text-crema" : "border-border"}`}>
                      {selected && <Check className="h-3 w-3" aria-hidden />}
                    </span>
                    <span>
                      <span className="block text-base font-semibold">{option.title}</span>
                      <span className="mt-0.5 block text-sm leading-6 text-muted-foreground">{option.text}</span>
                    </span>
                  </button>
                );
              })}
            </div>
            {destination === "in_vendita" && (
              <p className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm leading-6">
                Prezzo d&apos;esempio: <strong>{formatMarketValidationEuroCents(bottle.examplePriceCents)}</strong>. Su Vinea il prezzo lo decidi tu e scegli come consegnare il pacco.
              </p>
            )}
            <ContinueButton disabled={!destination} onClick={() => setStep(3)} />
          </div>
        )}

        {step === 3 && bottle && chosen && (
          <div className="space-y-4">
            <StepTitle icon={Wine} title="Riepilogo" text="Controlla e conferma: questa è l'ultima schermata della demo." />
            <div className="flex gap-4 rounded-2xl bg-secondary/50 p-3">
              <span className="relative block aspect-[4/5] w-24 shrink-0 overflow-hidden rounded-xl bg-secondary">
                <WineThumbnail src={bottle.image} alt={`${bottle.suggestion.wine}, foto d'esempio`} className="h-full w-full object-cover" sizes="96px" />
              </span>
              <div className="min-w-0">
                <p className="text-sm text-muted-foreground">{bottle.suggestion.producer}</p>
                <p className="font-serif text-xl font-semibold leading-tight">{bottle.suggestion.wine} {bottle.suggestion.vintage}</p>
                <p className="mt-1 text-sm text-muted-foreground">{bottle.suggestion.denomination} · {bottle.suggestion.format}</p>
                <p className="mt-2 inline-flex rounded-full bg-bordeaux/10 px-2.5 py-1 text-xs font-semibold text-bordeaux">{chosen.title}</p>
              </div>
            </div>
            <p className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm leading-6">
              Simulazione: confermando non viene creato alcun annuncio e nessuna bottiglia entra in una Cantina reale.
            </p>
            {error && <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">{error}</p>}
            <Button type="button" className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" disabled={pending} onClick={confirm}>
              {pending ? "Registrazione in corso…" : "Conferma la simulazione"}
            </Button>
          </div>
        )}
      </div>
    </section>
  );
}

function StepTitle({ icon: Icon, title, text }: { icon: typeof Camera; title: string; text: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><Icon className="h-5 w-5" aria-hidden /></span>
      <div>
        <h2 className="font-serif text-xl font-semibold">{title}</h2>
        <p className="mt-1 text-base leading-7 text-muted-foreground">{text}</p>
      </div>
    </div>
  );
}

function ContinueButton({ disabled, onClick }: { disabled: boolean; onClick: () => void }) {
  return (
    <Button type="button" className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" disabled={disabled} onClick={onClick}>
      Continua
    </Button>
  );
}
