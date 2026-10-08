import {
  Bot,
  Check,
  ChevronRight,
  Flag,
  Grape,
  ShoppingBag,
  Store,
  Users,
  Wine,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import {
  marketValidationCanComplete,
  marketValidationProgressPercent,
} from "@/lib/market-validation/mv2-flow";
import type { MarketValidationProgress } from "@/lib/market-validation/progress";

export type MarketValidationScreen =
  | "hub"
  | "marketplace"
  | "detail"
  | "checkout"
  | "seller"
  | "ai"
  | "club"
  | "cellar"
  | "pre-questionnaire"
  | "post-questionnaire"
  | "complete";

// Ogni card apre una schermata interna della guida: nessuna porta verso le
// pagine reali di Vinea. I due step contano per il traguardo; gli
// approfondimenti si scoprono quando si vuole.
type HubArea = {
  key: string;
  screen: MarketValidationScreen;
  icon: LucideIcon;
  title: string;
  text: string;
  done: boolean;
  badge: "Step 1" | "Step 2" | "Approfondimento";
  cta: string;
};

const CARD_CLASS =
  "group flex min-h-36 w-full flex-1 flex-col rounded-2xl border border-border bg-card p-5 text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";

export function ValidationHub({
  participantCode,
  progress,
  completing,
  completionError,
  onOpen,
  onComplete,
}: {
  participantCode: string;
  progress: MarketValidationProgress;
  completing: boolean;
  completionError: string | null;
  onOpen: (screen: MarketValidationScreen) => void;
  onComplete: () => void;
}) {
  const completed = marketValidationCanComplete(progress);
  const percent = marketValidationProgressPercent(progress);
  const stepsDone = percent / 50;
  const areas: HubArea[] = [
    {
      key: "buyer",
      screen: "marketplace",
      icon: ShoppingBag,
      title: "Acquista",
      text: "Esplora 40 annunci demo e completa un acquisto simulato.",
      done: progress.buyerCompleted,
      badge: "Step 1",
      cta: "Inizia",
    },
    {
      key: "seller",
      screen: "seller",
      icon: Store,
      title: "Vendi",
      text: "Aggiungi una bottiglia con l'aiuto dell'AI e scegli se tenerla in Cantina o metterla in vendita.",
      done: progress.sellerCompleted,
      badge: "Step 2",
      cta: "Inizia",
    },
    {
      key: "ai",
      screen: "ai",
      icon: Bot,
      title: "Anteprima AI",
      text: "Scopri dove Vinea usa l'AI e guarda un'anteprima fotografica.",
      done: progress.aiPreviewViewed,
      badge: "Approfondimento",
      cta: "Scopri",
    },
    {
      key: "club",
      screen: "club",
      icon: Users,
      title: "Club",
      text: "Scopri le community di Vinea dedicate a territori, denominazioni, produttori e passioni.",
      done: progress.clubViewed,
      badge: "Approfondimento",
      cta: "Scopri",
    },
  ];
  const nextStep = areas.find((area) => area.badge !== "Approfondimento" && !area.done);

  return (
    <section className="space-y-6" aria-labelledby="mv-hub-title">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">
              Hub tester
            </p>
            <h1 id="mv-hub-title" className="mt-2 font-serif text-3xl font-semibold md:text-4xl">
              Prova Vinea
            </h1>
          </div>
          <span className="rounded-full border border-bordeaux/20 bg-bordeaux/5 px-3 py-1 text-sm font-semibold text-bordeaux">
            Test {participantCode}
          </span>
        </div>

        <div className="mt-6 space-y-2">
          <div className="flex items-center justify-between gap-4 text-base">
            <span className="font-semibold">Step del test</span>
            <span className="text-muted-foreground">{stepsDone} di 2 completati</span>
          </div>
          <Progress value={percent} aria-label={`${stepsDone} step del test su 2 completati`} />
          <p className="text-base leading-7 text-muted-foreground">
            Completa i due step, Acquista e Vendi, per raggiungere il traguardo. AI, Club e Cantina sono approfondimenti da scoprire quando vuoi.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {areas.map((area) => (
          <button key={area.key} type="button" onClick={() => onOpen(area.screen)} className={CARD_CLASS}>
            <CardBody area={area} />
          </button>
        ))}
      </div>

      {/* Scoperta facoltativa fuori da `areas`: non è uno step del test e non
          entra nel conteggio degli step. */}
      <button
        type="button"
        onClick={() => onOpen("cellar")}
        className="group flex w-full items-start gap-4 rounded-2xl border border-border bg-card p-5 text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
          <Wine className="h-5 w-5" aria-hidden />
        </span>
        <span className="flex-1">
          <span className="flex items-start justify-between gap-3">
            <span className="font-serif text-xl font-semibold group-hover:text-bordeaux">La tua Cantina</span>
            <span className="rounded-full bg-secondary px-2.5 py-1 text-sm text-muted-foreground">Scopri</span>
          </span>
          <span className="mt-1 block text-base leading-6 text-muted-foreground">
            Organizza la tua collezione, decidi quali bottiglie mostrare o vendere e segui nel tempo il valore della Cantina.
          </span>
          <span className="mt-3 inline-flex items-center gap-1 text-base font-medium text-bordeaux">
            Scopri la Cantina <ChevronRight className="h-4 w-4" aria-hidden />
          </span>
        </span>
      </button>

      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-4 text-base leading-7 text-antracite">
        <div className="flex gap-3">
          <Grape className="mt-1 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
          <p>
            Tutto il test si svolge qui ed è una simulazione: non crea ordini,
            pagamenti, annunci o spedizioni reali. Prenditi il tempo che vuoi.
          </p>
        </div>
      </div>

      {completionError && (
        <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-base text-bordeaux">
          {completionError}
        </p>
      )}
      <Button
        type="button"
        size="lg"
        className="min-h-12 w-full gap-2 bg-bordeaux text-base hover:bg-bordeaux/90"
        disabled={!completed || completing}
        onClick={onComplete}
      >
        <Flag className="h-4 w-4" aria-hidden />
        {completing ? "Completamento in corso…" : "Raggiungi il traguardo"}
      </Button>
      <p className="text-center text-base text-muted-foreground">
        {completed
          ? "Hai completato entrambi gli step: concludi quando vuoi."
          : nextStep && `Prossimo passo: ${nextStep.badge}, ${nextStep.title}.`}
      </p>
    </section>
  );
}

function CardBody({ area }: { area: HubArea }) {
  const Icon = area.icon;
  return (
    <>
      <div className="flex items-start justify-between gap-3">
        <span className="grid h-11 w-11 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
          <Icon className="h-5 w-5" aria-hidden />
        </span>
        {area.done ? (
          <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2.5 py-1 text-sm font-semibold text-salvia">
            <Check className="h-4 w-4" aria-hidden /> Completato
          </span>
        ) : (
          <span
            className={`rounded-full px-2.5 py-1 text-sm ${
              area.badge === "Approfondimento"
                ? "bg-secondary text-muted-foreground"
                : "bg-bordeaux/10 font-semibold text-bordeaux"
            }`}
          >
            {area.badge}
          </span>
        )}
      </div>
      <h2 className="mt-4 font-serif text-xl font-semibold group-hover:text-bordeaux">{area.title}</h2>
      <p className="mt-1 text-base leading-6 text-muted-foreground">{area.text}</p>
      <span className="mt-auto inline-flex items-center gap-1 pt-3 text-base font-medium text-bordeaux">
        {area.cta} <ChevronRight className="h-4 w-4" aria-hidden />
      </span>
    </>
  );
}
