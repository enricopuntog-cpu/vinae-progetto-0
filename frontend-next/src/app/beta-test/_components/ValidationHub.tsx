import Link from "next/link";
import type { ReactNode } from "react";
import {
  Bot,
  Check,
  ChevronRight,
  ExternalLink,
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
  | "ai"
  | "cellar"
  | "complete";

// Vendi e Club non hanno una copia dentro il test: la card apre la vera
// superficie di Vinea in una nuova scheda, così questa guida resta aperta.
type HubArea = {
  key: string;
  icon: LucideIcon;
  title: string;
  text: string;
  note?: string;
  done: boolean;
  required: boolean;
  cta: string;
} & (
  | { kind: "screen"; screen: MarketValidationScreen }
  | { kind: "real"; href: "/vendi" | "/community"; onOpen: () => void }
);

const CARD_CLASS =
  "group flex min-h-36 flex-1 flex-col rounded-2xl border border-border bg-card p-5 text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";

export function ValidationHub({
  participantCode,
  progress,
  completing,
  completionError,
  sellerOpened,
  sellerConfirming,
  sellerError,
  onOpen,
  onSellerOpen,
  onSellerConfirm,
  onClubOpen,
  onComplete,
}: {
  participantCode: string;
  progress: MarketValidationProgress;
  completing: boolean;
  completionError: string | null;
  sellerOpened: boolean;
  sellerConfirming: boolean;
  sellerError: string | null;
  onOpen: (screen: MarketValidationScreen) => void;
  onSellerOpen: () => void;
  onSellerConfirm: () => void;
  onClubOpen: () => void;
  onComplete: () => void;
}) {
  const completed = marketValidationCanComplete(progress);
  const percent = marketValidationProgressPercent(progress);
  const areas: HubArea[] = [
    {
      key: "buyer",
      kind: "screen",
      screen: "marketplace",
      icon: ShoppingBag,
      title: "Acquista",
      text: "Esplora 40 annunci demo e completa un checkout simulato.",
      done: progress.buyerCompleted,
      required: true,
      cta: "Apri",
    },
    {
      key: "seller",
      kind: "real",
      href: "/vendi",
      onOpen: onSellerOpen,
      icon: Store,
      title: "Vendi",
      text: "Prova il vero percorso di Vinea per aggiungere una bottiglia alla cantina o metterla in vendita.",
      note: "Apre la vera funzione di Vinea in una nuova scheda: per alcune azioni può servirti un account. Non serve pubblicare un annuncio per completare il test.",
      done: progress.sellerCompleted,
      required: true,
      cta: "Prova la vendita",
    },
    {
      key: "ai",
      kind: "screen",
      screen: "ai",
      icon: Bot,
      title: "Anteprima AI",
      text: "Scopri come Vinea usa l'AI e guarda un'anteprima fotografica.",
      done: progress.aiPreviewViewed,
      required: false,
      cta: "Apri",
    },
    {
      key: "club",
      kind: "real",
      href: "/community",
      onOpen: onClubOpen,
      icon: Users,
      title: "Club",
      text: "Scopri le community di Vinea: trova Club dedicati a territori, denominazioni, produttori e passioni.",
      note: "Leggi le discussioni; con un account puoi seguire i Club e crearne di nuovi. I Club aperti accolgono subito, quelli chiusi su approvazione.",
      done: progress.clubViewed,
      required: false,
      cta: "Esplora i Club",
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
        {areas.map((area) => (
          <div key={area.key} className="flex flex-col gap-2">
            {area.kind === "screen" ? (
              <button type="button" onClick={() => onOpen(area.screen)} className={CARD_CLASS}>
                <CardBody area={area} icon={<ChevronRight className="h-4 w-4" aria-hidden />} />
              </button>
            ) : (
              <Link
                href={area.href}
                target="_blank"
                rel="noopener noreferrer"
                onClick={area.onOpen}
                className={CARD_CLASS}
              >
                <CardBody area={area} icon={<ExternalLink className="h-4 w-4" aria-hidden />} />
                <span className="sr-only"> (si apre in una nuova scheda)</span>
              </Link>
            )}
            {area.key === "seller" && sellerOpened && !progress.sellerCompleted && (
              <div
                role="group"
                aria-labelledby="mv-seller-confirm-title"
                className="space-y-3 rounded-2xl border border-bordeaux/20 bg-bordeaux/5 p-4"
              >
                <p id="mv-seller-confirm-title" className="text-sm font-semibold">
                  Hai provato il percorso di vendita?
                </p>
                <Button
                  type="button"
                  className="min-h-11 w-full bg-bordeaux hover:bg-bordeaux/90"
                  disabled={sellerConfirming}
                  onClick={onSellerConfirm}
                >
                  {sellerConfirming ? "Registrazione in corso…" : "Sì, l'ho provato"}
                </Button>
                {sellerError && (
                  <p role="alert" className="text-sm text-bordeaux">
                    {sellerError}
                  </p>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Scoperta facoltativa fuori da `areas`: non è un percorso del test e
          non entra nel conteggio dei percorsi obbligatori. */}
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
            <span className="rounded-full bg-secondary px-2.5 py-1 text-xs text-muted-foreground">Scopri</span>
          </span>
          <span className="mt-1 block text-sm leading-5 text-muted-foreground">
            Organizza la tua collezione, decidi quali bottiglie mostrare o vendere e segui nel tempo il valore della Cantina.
          </span>
          <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-bordeaux">
            Scopri la Cantina <ChevronRight className="h-4 w-4" aria-hidden />
          </span>
        </span>
      </button>

      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm text-antracite">
        <div className="flex gap-3">
          <Grape className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
          <p>
            Il percorso di acquisto è simulato e non crea ordini o pagamenti. Alcune
            sezioni della guida aprono le vere funzioni di Vinea: non è necessario
            pubblicare un annuncio reale per completare il test.
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
          Completa prima i percorsi di acquisto e vendita.
        </p>
      )}
    </section>
  );
}

function CardBody({ area, icon }: { area: HubArea; icon: ReactNode }) {
  const Icon = area.icon;
  return (
    <>
      <div className="flex items-start justify-between gap-3">
        <span className="grid h-11 w-11 place-items-center rounded-full bg-bordeaux/10 text-bordeaux">
          <Icon className="h-5 w-5" aria-hidden />
        </span>
        {area.done ? (
          <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2.5 py-1 text-xs font-semibold text-salvia">
            <Check className="h-3.5 w-3.5" aria-hidden /> Completato
          </span>
        ) : (
          <span className="rounded-full bg-secondary px-2.5 py-1 text-xs text-muted-foreground">
            {area.required ? "Obbligatorio" : "Facoltativo"}
          </span>
        )}
      </div>
      <h2 className="mt-4 font-serif text-xl font-semibold group-hover:text-bordeaux">{area.title}</h2>
      <p className="mt-1 text-sm leading-5 text-muted-foreground">{area.text}</p>
      {area.note && <p className="mt-2 text-xs leading-5 text-muted-foreground">{area.note}</p>}
      <span className="mt-auto inline-flex items-center gap-1 pt-3 text-sm font-medium text-bordeaux">
        {area.cta} {icon}
      </span>
    </>
  );
}
