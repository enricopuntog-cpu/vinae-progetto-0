import {
  Bot,
  Check,
  ChevronRight,
  Grape,
  ShoppingBag,
  Store,
  Users,
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
  | "complete";

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
  const areas = [
    {
      screen: "marketplace" as const,
      icon: ShoppingBag,
      title: "Acquista",
      text: "Esplora 40 annunci demo e completa un checkout simulato.",
      done: progress.buyerCompleted,
      required: true,
    },
    {
      screen: "seller" as const,
      icon: Store,
      title: "Vendi",
      text: "Simula la pubblicazione locale di una bottiglia.",
      done: progress.sellerCompleted,
      required: true,
    },
    {
      screen: "ai" as const,
      icon: Bot,
      title: "Anteprima AI",
      text: "Guarda un esempio statico di elaborazione fotografica.",
      done: progress.aiPreviewViewed,
      required: false,
    },
    {
      screen: "club" as const,
      icon: Users,
      title: "Anteprima Club",
      text: "Scopri come potrebbero essere organizzate le community.",
      done: progress.clubViewed,
      required: false,
    },
  ];

  return (
    <section className="space-y-6" aria-labelledby="mv-hub-title">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">
              Hub tester
            </p>
            <h1 id="mv-hub-title" className="mt-2 font-serif text-3xl font-semibold md:text-4xl">
              Prova Vinea
            </h1>
          </div>
          <span className="rounded-full border border-bordeaux/20 bg-bordeaux/5 px-3 py-1 text-xs font-semibold text-bordeaux">
            Test {participantCode}
          </span>
        </div>

        <div className="mt-6 space-y-2">
          <div className="flex items-center justify-between gap-4 text-sm">
            <span className="font-medium">Percorsi obbligatori</span>
            <span className="text-muted-foreground">{percent / 50} di 2 completati</span>
          </div>
          <Progress value={percent} aria-label={`${percent}% del test obbligatorio completato`} />
          <p className="text-xs text-muted-foreground">
            Acquisto e vendita sono obbligatori. AI e Club sono facoltativi.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {areas.map(({ screen, icon: Icon, title, text, done, required }) => (
          <button
            key={screen}
            type="button"
            onClick={() => onOpen(screen)}
            className="group min-h-36 rounded-2xl border border-border bg-card p-5 text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <div className="flex items-start justify-between gap-3">
              <span className="grid h-11 w-11 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
                <Icon className="h-5 w-5" aria-hidden />
              </span>
              {done ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2.5 py-1 text-xs font-semibold text-salvia">
                  <Check className="h-3.5 w-3.5" aria-hidden /> Completato
                </span>
              ) : (
                <span className="rounded-full bg-secondary px-2.5 py-1 text-xs text-muted-foreground">
                  {required ? "Obbligatorio" : "Facoltativo"}
                </span>
              )}
            </div>
            <h2 className="mt-4 font-serif text-xl font-semibold group-hover:text-bordeaux">{title}</h2>
            <p className="mt-1 text-sm leading-5 text-muted-foreground">{text}</p>
            <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-bordeaux">
              Apri <ChevronRight className="h-4 w-4" aria-hidden />
            </span>
          </button>
        ))}
      </div>

      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm text-antracite">
        <div className="flex gap-3">
          <Grape className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
          <p>
            È tutto simulato: non viene creato alcun annuncio, ordine, pagamento o
            piano di spedizione. Le foto scelte restano nel browser e non vengono caricate.
          </p>
        </div>
      </div>

      {completionError && (
        <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">
          {completionError}
        </p>
      )}
      <Button
        type="button"
        size="lg"
        className="min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90"
        disabled={!completed || completing}
        onClick={onComplete}
      >
        {completing ? "Completamento in corso…" : "Completa il test"}
      </Button>
      {!completed && (
        <p className="text-center text-xs text-muted-foreground">
          Completa prima le simulazioni di acquisto e vendita.
        </p>
      )}
    </section>
  );
}
