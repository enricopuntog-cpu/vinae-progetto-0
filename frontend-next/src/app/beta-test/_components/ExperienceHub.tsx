import {
  Bot,
  Check,
  ChevronRight,
  Circle,
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
  EXPERIENCE_AREAS,
  experienceAreasCount,
  type ExperienceAreaKey,
  type ExperienceAreasDone,
} from "@/lib/market-validation/questionnaire";
import type { MarketValidationScreen } from "./ValidationHub";

// Hub del questionario QV2: le cinque prove sono tutte obbligatorie. Lo stato
// di ogni card viene dagli eventi accettati dal server (`done`), mai dal click;
// il pulsante finale resta disabilitato finché non sono 5/5.
const AREA_UI: Record<ExperienceAreaKey, { screen: MarketValidationScreen; icon: LucideIcon; text: string }> = {
  buyer: {
    screen: "marketplace",
    icon: ShoppingBag,
    text: "Esplora gli annunci demo e completa un acquisto simulato.",
  },
  seller: {
    screen: "seller",
    icon: Store,
    text: "Aggiungi una bottiglia con l'aiuto dell'AI e scegli se tenerla in Cantina o metterla in vendita.",
  },
  ai: {
    screen: "ai",
    icon: Bot,
    text: "Scopri dove Vinea usa l'AI e guarda un'anteprima fotografica.",
  },
  club: {
    screen: "club",
    icon: Users,
    text: "Scopri le community di Vinea dedicate a territori, denominazioni, produttori e passioni.",
  },
  cellar: {
    screen: "cellar",
    icon: Wine,
    text: "Organizza la tua collezione e segui nel tempo il valore della Cantina.",
  },
};

export const EXPERIENCE_LOCKED_LABEL = "Completa le 5 prove per continuare";
export const EXPERIENCE_CONTINUE_LABEL = "CONTINUA CON LE ULTIME DOMANDE";

export function ExperienceHub({
  done,
  completing,
  completionError,
  onOpen,
  onContinue,
}: {
  done: ExperienceAreasDone;
  completing: boolean;
  completionError: string | null;
  onOpen: (screen: MarketValidationScreen) => void;
  onContinue: () => void;
}) {
  const count = experienceAreasCount(done);
  const total = EXPERIENCE_AREAS.length;
  const allDone = count === total;
  const next = EXPERIENCE_AREAS.find((area) => !done[area.key]);

  return (
    <section className="space-y-6" aria-labelledby="mv-hub-title">
      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Prova Vinea</p>
        <h1 id="mv-hub-title" className="mt-2 font-serif text-3xl font-semibold uppercase md:text-4xl">
          Prova tutte le funzioni
        </h1>
        <p className="mt-3 text-base leading-7 text-muted-foreground">
          Per completare il Beta Test esplora tutte e 5 le aree.
        </p>
        <div className="mt-5 space-y-2">
          <div className="flex items-center justify-between gap-4 text-base">
            <span className="font-semibold">Prove completate</span>
            <span className="font-semibold text-bordeaux">{count} di {total} completate</span>
          </div>
          <Progress value={(count / total) * 100} aria-label={`${count} prove su ${total} completate`} />
        </div>
      </div>

      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2" aria-label="Le cinque prove">
        {EXPERIENCE_AREAS.map((area) => {
          const ui = AREA_UI[area.key];
          const Icon = ui.icon;
          const completed = done[area.key];
          return (
            <li key={area.key} className="flex">
              <button
                type="button"
                onClick={() => onOpen(ui.screen)}
                data-area={area.key}
                data-completed={completed ? "true" : "false"}
                className={`group flex min-h-32 w-full flex-1 flex-col rounded-2xl border bg-card p-5 text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
                  completed ? "border-salvia/50" : "border-border"
                }`}
              >
                <span className="flex items-start justify-between gap-3">
                  <span className="grid h-11 w-11 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
                    <Icon className="h-5 w-5" aria-hidden />
                  </span>
                  {completed ? (
                    <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2.5 py-1 text-sm font-semibold text-salvia-scuro">
                      <Check className="h-4 w-4" aria-hidden /> Completato
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 rounded-full bg-bordeaux/10 px-2.5 py-1 text-sm font-semibold text-bordeaux">
                      <Circle className="h-3.5 w-3.5" aria-hidden /> Da provare
                    </span>
                  )}
                </span>
                <span className="mt-4 font-serif text-xl font-semibold group-hover:text-bordeaux">{area.title}</span>
                <span className="mt-1 text-base leading-6 text-muted-foreground">{ui.text}</span>
                <span className="mt-auto inline-flex items-center gap-1 pt-3 text-base font-medium text-bordeaux">
                  {completed ? "Rivedi" : "Prova"} <ChevronRight className="h-4 w-4" aria-hidden />
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-4 text-base leading-7 text-antracite">
        <div className="flex gap-3">
          <Grape className="mt-1 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
          <p>
            Tutto il test si svolge qui ed è una simulazione: non crea ordini,
            pagamenti, annunci o spedizioni reali.
          </p>
        </div>
      </div>

      {completionError && (
        <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-base text-bordeaux">
          {completionError}
        </p>
      )}
      <p className="text-center text-base text-muted-foreground" aria-live="polite">
        {allDone ? "Hai completato tutte e 5 le prove." : next && `Prossima prova: ${next.title}.`}
      </p>
      <Button
        type="button"
        size="lg"
        className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90"
        disabled={!allDone || completing}
        onClick={onContinue}
      >
        {completing ? "Un momento…" : allDone ? EXPERIENCE_CONTINUE_LABEL : EXPERIENCE_LOCKED_LABEL}
      </Button>
    </section>
  );
}
