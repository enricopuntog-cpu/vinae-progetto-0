"use client";

import { useEffect } from "react";
import { Globe2, LockKeyhole, MessagesSquare, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { MarketValidationTrack } from "./types";

const CLUBS = [
  { name: "Circolo dei Nebbioli", type: "Aperto", text: "Degustazioni e territori del Piemonte.", icon: Globe2 },
  { name: "Bolle d'Italia", type: "Tematico", text: "Metodo classico, territori e abbinamenti.", icon: MessagesSquare },
  { name: "Collezionisti in cantina", type: "Chiuso", text: "Confronto riservato su conservazione e annate.", icon: LockKeyhole },
  { name: "Vigne vulcaniche", type: "Aperto", text: "Etna, Vesuvio e altre espressioni minerali.", icon: Users },
] as const;

export function ClubPreview({ track, onViewed, onBack }: { track: MarketValidationTrack; onViewed: () => void; onBack: () => void }) {
  useEffect(() => {
    let active = true;
    void track("club_viewed", {}, "club_viewed").then((result) => {
      if (active && result.ok) onViewed();
    });
    return () => { active = false; };
  }, [onViewed, track]);

  return (
    <section className="space-y-5" aria-labelledby="club-title">
      <div>
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Anteprima statica · sola lettura</p>
        <h1 id="club-title" className="mt-1 font-serif text-3xl font-semibold">Club e community</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">Esempi di spazi per interessi condivisi. In questo test non puoi iscriverti, pubblicare, seguire o modificare Club.</p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        {CLUBS.map(({ name, type, text, icon: Icon }) => (
          <article key={name} className="rounded-2xl border border-border bg-card p-5">
            <div className="flex items-start justify-between gap-3">
              <span className="grid h-11 w-11 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><Icon className="h-5 w-5" aria-hidden /></span>
              <span className="rounded-full bg-secondary px-2.5 py-1 text-xs font-medium">{type}</span>
            </div>
            <h2 className="mt-4 font-serif text-xl font-semibold">{name}</h2>
            <p className="mt-1 text-sm leading-5 text-muted-foreground">{text}</p>
          </article>
        ))}
      </div>
      <p className="rounded-xl border border-oro/40 bg-oro/10 p-4 text-sm">Questa è una preview: nessun servizio Club viene chiamato e nessun dato viene scritto.</p>
      <Button type="button" size="lg" className="min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" onClick={onBack}>Torna al test</Button>
    </section>
  );
}
