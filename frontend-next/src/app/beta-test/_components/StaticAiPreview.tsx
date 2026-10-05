"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { Check, ScanLine, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { MarketValidationTrack } from "./types";

type AiMode = "full" | "detail";

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
    <section className="space-y-5" aria-labelledby="ai-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Esempio statico · in sviluppo</p>
          <h1 id="ai-title" className="mt-1 font-serif text-3xl font-semibold">Anteprima fotografica AI</h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">Questa schermata mostra immagini approvate e già pronte. Non analizza foto, non chiama provider AI e non salva nulla.</p>
        </div>
        <Button type="button" variant="outline" className="min-h-11 shrink-0" onClick={onBack}>Hub</Button>
      </div>

      <div className="grid gap-5 rounded-3xl border border-border bg-card p-5 md:grid-cols-2 md:p-8">
        <div className="space-y-3">
          <div className="flex items-center gap-2"><ScanLine className="h-5 w-5 text-bordeaux" aria-hidden /><h2 className="font-serif text-xl font-semibold">Sorgente</h2></div>
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
          <div className="flex items-center gap-2"><Sparkles className="h-5 w-5 text-bordeaux" aria-hidden /><h2 className="font-serif text-xl font-semibold">Risultato statico</h2></div>
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
  );
}
