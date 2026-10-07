"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import {
  Camera,
  Check,
  ClipboardPen,
  MessageSquareText,
  ScanLine,
  Sparkles,
  UtensilsCrossed,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { AI_UI } from "@/config/features";
import type { SuperficieIA } from "@/lib/phase10/etichette-ia";
import { DemoBackButton } from "./DemoBackButton";
import type { MarketValidationTrack } from "./types";

type AiMode = "full" | "detail";

// Le quattro aree in cui Vinea usa l'AI: le tre superfici reali della Fase 10
// più la foto/sfondo, che è ancora in sviluppo. Qui non si chiama nessun
// provider e non c'è alcun link al sito: è una spiegazione dentro la guida.
// Per le tre superfici reali la riga di stato segue le stesse flag `AI_UI`
// che decidono se la superficie è montata su Vinea.
const AI_SURFACES: ReadonlyArray<{
  surface: SuperficieIA | "foto";
  icon: LucideIcon;
  title: string;
  text: string;
  purpose: string;
}> = [
  {
    surface: "sommelier",
    icon: MessageSquareText,
    title: "Sommelier AI",
    text: "Un assistente con cui parlare di vino: puoi fare domande, approfondire bottiglie e orientarti tra vini, caratteristiche e abbinamenti.",
    purpose: "Serve a chiedere un consiglio come faresti con un sommelier.",
  },
  {
    surface: "catalogazione",
    icon: ClipboardPen,
    title: "Assistente AI per l'annuncio",
    text: "Quando aggiungi una bottiglia, Vinea può aiutarti a compilare i dati di catalogazione suggerendo le informazioni da inserire.",
    purpose: "Serve a catalogare più in fretta: suggerisce soltanto, non pubblica nulla da solo e ogni campo resta sotto il tuo controllo.",
  },
  {
    surface: "foto",
    icon: Camera,
    title: "Foto e sfondo AI",
    text: "Aiuta a presentare meglio la bottiglia nelle foto, adattando lo sfondo al tipo di scatto.",
    purpose: "Serve ad avere annunci più curati senza un set fotografico. Guarda l'anteprima qui sotto.",
  },
  {
    surface: "abbinamento",
    icon: UtensilsCrossed,
    title: "Abbinamenti AI",
    text: "Vinea può aiutarti a scoprire possibili abbinamenti tra vino e cibo, scegliendo tra le bottiglie del catalogo.",
    purpose: "Serve a scoprire vini nuovi partendo da quello che porti in tavola.",
  },
];

function surfaceStatus(surface: SuperficieIA | "foto"): string | null {
  if (surface === "foto") return "Funzione in sviluppo";
  return AI_UI[surface] ? null : "Non ancora attiva in questa versione di Vinea";
}

const AI_RESULTS: Record<AiMode, { label: string; sourcePosition: string; src: string; alt: string }> = {
  full: {
    label: "Bottiglia intera",
    sourcePosition: "left center",
    src: "/images/market-validation/ai/mv-ai-result-full.png",
    alt: "Esempio statico del risultato con bottiglia intera",
  },
  detail: {
    label: "Primo piano / dettaglio",
    sourcePosition: "right center",
    src: "/images/market-validation/ai/mv-ai-result-detail.png",
    alt: "Esempio statico del risultato con dettaglio della bottiglia",
  },
};

export function StaticAiPreview({
  interested,
  track,
  onViewed,
  onInterest,
  onBack,
}: {
  interested: boolean;
  track: MarketValidationTrack;
  onViewed: () => void;
  onInterest: () => void;
  onBack: () => void;
}) {
  const [mode, setMode] = useState<AiMode>("full");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const result = AI_RESULTS[mode];

  useEffect(() => {
    let active = true;
    void track("ai_preview_viewed", {}, "ai_preview_viewed").then((response) => {
      if (active && response.ok) onViewed();
    });
    return () => { active = false; };
  }, [onViewed, track]);

  const interest = async () => {
    if (pending || interested) return;
    setPending(true);
    setError(null);
    const response = await track("ai_interest_clicked", {}, "ai_interest_clicked");
    setPending(false);
    if (!response.ok) {
      setError("Non siamo riusciti a registrare il tuo interesse. Puoi riprovare.");
      return;
    }
    onInterest();
  };

  return (
    <section className="space-y-6" aria-labelledby="ai-title">
      <DemoBackButton onBack={onBack} />
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Approfondimento · Anteprima AI</p>
        <h1 id="ai-title" className="mt-1 font-serif text-3xl font-semibold md:text-4xl">Vinea AI</h1>
        <p className="mt-2 max-w-2xl text-base leading-7 text-muted-foreground">L&apos;intelligenza artificiale in Vinea supporta diverse parti dell&apos;esperienza. Ecco dove la trovi e a cosa serve.</p>
      </div>

      <section className="space-y-3" aria-labelledby="ai-surfaces-title">
        <h2 id="ai-surfaces-title" className="font-serif text-2xl font-semibold">Come Vinea usa l&apos;AI</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {AI_SURFACES.map(({ surface, icon: Icon, title, text, purpose }) => {
            const status = surfaceStatus(surface);
            return (
              <article key={surface} className="flex gap-3 rounded-2xl border border-border bg-card p-4">
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><Icon className="h-5 w-5" aria-hidden /></span>
                <div>
                  <h3 className="font-serif text-lg font-semibold">{title}</h3>
                  <p className="mt-1 text-base leading-7 text-muted-foreground">{text}</p>
                  <p className="mt-2 text-sm leading-6"><strong className="font-semibold text-bordeaux">A cosa serve.</strong> {purpose}</p>
                  {status && <p className="mt-2 inline-flex rounded-full border border-oro/40 bg-oro/10 px-2.5 py-0.5 text-xs font-semibold text-antracite">{status}</p>}
                </div>
              </article>
            );
          })}
        </div>
      </section>

      <section className="space-y-5" aria-labelledby="ai-photo-title">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Foto e presentazione</p>
          <h2 id="ai-photo-title" className="mt-1 font-serif text-2xl font-semibold">Anteprima foto AI</h2>
          <p className="mt-2 inline-flex rounded-full border border-oro/40 bg-oro/10 px-3 py-1 text-xs font-semibold text-antracite">Anteprima di una funzione in sviluppo</p>
          <p className="mt-2 max-w-2xl text-base leading-7 text-muted-foreground">Una funzione in sviluppo pensata per aiutare a presentare meglio la bottiglia nelle foto, adattando lo sfondo al tipo di scatto.</p>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">Le immagini sono esempi approvati e già pronti: questa schermata non analizza foto, non chiama provider AI e non salva nulla.</p>
        </div>

        <div className="grid gap-5 rounded-3xl border border-border bg-card p-5 md:grid-cols-2 md:p-8">
          <div className="space-y-3">
            <div className="flex items-center gap-2"><ScanLine className="h-5 w-5 text-bordeaux" aria-hidden /><h3 className="font-serif text-xl font-semibold">Sorgente</h3></div>
            <div
              role="img"
              aria-label={`Ritaglio statico sorgente: ${result.label}`}
              className="aspect-[4/3] overflow-hidden rounded-2xl border border-border bg-cover bg-no-repeat"
              style={{
                backgroundImage: "url('/images/market-validation/ai/mv-ai-background-source.jpg')",
                backgroundPosition: result.sourcePosition,
                backgroundSize: "200% 100%",
              }}
            />
            <p className="text-xs text-muted-foreground">Ritaglio dimostrativo: {result.label.toLocaleLowerCase("it-IT")}.</p>
          </div>
          <div className="space-y-3">
            <div className="flex items-center gap-2"><Sparkles className="h-5 w-5 text-bordeaux" aria-hidden /><h3 className="font-serif text-xl font-semibold">Risultato statico</h3></div>
            <div className="relative aspect-[4/5] overflow-hidden rounded-2xl border border-border bg-secondary">
              <Image key={result.src} src={result.src} alt={result.alt} fill sizes="(max-width: 768px) 100vw, 50vw" className="object-cover" />
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3" role="group" aria-label="Vista dell'esempio">
          {(Object.keys(AI_RESULTS) as AiMode[]).map((key) => (
            <Button key={key} type="button" variant={mode === key ? "default" : "outline"} className={`min-h-12 whitespace-normal ${mode === key ? "bg-bordeaux hover:bg-bordeaux/90" : ""}`} aria-pressed={mode === key} onClick={() => setMode(key)}>{AI_RESULTS[key].label}</Button>
          ))}
        </div>

        {interested ? (
          <p role="status" className="flex items-center gap-2 rounded-xl border border-salvia/40 bg-salvia/10 p-4 text-sm text-salvia"><Check className="h-5 w-5" aria-hidden /> Grazie, il tuo interesse è stato registrato.</p>
        ) : (
          <Button type="button" size="lg" className="min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" disabled={pending} onClick={interest}>{pending ? "Registrazione in corso…" : "Mi interessa questa funzione"}</Button>
        )}
        {error && <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">{error}</p>}
      </section>

      <Button type="button" variant="outline" className="min-h-12 w-full text-base" onClick={onBack}>Torna al test</Button>
    </section>
  );
}
