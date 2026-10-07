"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import {
  Compass,
  DoorOpen,
  Info,
  LockKeyhole,
  MessagesSquare,
  PlusCircle,
  ScrollText,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  MARKET_VALIDATION_CLUB_DEMO_ACCESS_LABEL,
  MARKET_VALIDATION_CLUB_DEMO_POST_LABEL,
  MARKET_VALIDATION_CLUB_DEMOS,
  type MarketValidationClubDemo,
} from "@/lib/market-validation/club-demo";
import { DemoBackButton } from "./DemoBackButton";
import type { MarketValidationTrack } from "./types";

const HOW_IT_WORKS: ReadonlyArray<{ icon: LucideIcon; title: string; text: string }> = [
  {
    icon: Compass,
    title: "Uno spazio per ogni interesse",
    text: "Un Club può essere dedicato a un territorio, a una denominazione, a un produttore o a una passione.",
  },
  {
    icon: DoorOpen,
    title: "Aperti o su approvazione",
    text: "Nei Club aperti entri subito. In quelli su approvazione invii una richiesta che i gestori del Club valutano.",
  },
  {
    icon: MessagesSquare,
    title: "Discussioni verticali",
    text: "Domande, degustazioni, consigli e confronti tra persone che amano lo stesso vino.",
  },
  {
    icon: PlusCircle,
    title: "Puoi crearne uno",
    text: "Proponi un Club con nome, descrizione, regole e copertina: diventa pubblico dopo la revisione di Vinea.",
  },
];

// Demo statica e interna: nessun servizio Club, nessuna iscrizione, nessun
// post o follow. Si registra soltanto `club_viewed` all'apertura.
export function ClubDemo({
  track,
  onViewed,
  onBack,
}: {
  track: MarketValidationTrack;
  onViewed: () => void;
  onBack: () => void;
}) {
  const [selected, setSelected] = useState<MarketValidationClubDemo | null>(null);

  useEffect(() => {
    let active = true;
    void track("club_viewed", {}, "club_viewed").then((result) => {
      if (active && result.ok) onViewed();
    });
    return () => { active = false; };
  }, [onViewed, track]);

  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [selected]);

  if (selected) return <ClubDemoDetail club={selected} onBack={() => setSelected(null)} />;

  return (
    <section className="space-y-6" aria-labelledby="club-title">
      <DemoBackButton onBack={onBack} />
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Approfondimento · Demo Club</p>
        <h1 id="club-title" className="mt-1 font-serif text-3xl font-semibold md:text-4xl">I Club di Vinea</h1>
        <p className="mt-2 max-w-2xl text-base leading-7 text-muted-foreground">
          I Club sono community dedicate: piccoli spazi dove chi ama lo stesso vino si ritrova per parlarne, scambiarsi consigli e scoprire bottiglie nuove.
        </p>
      </div>

      <section aria-labelledby="club-how-title" className="space-y-3">
        <h2 id="club-how-title" className="font-serif text-2xl font-semibold">Come funzionano</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {HOW_IT_WORKS.map(({ icon: Icon, title, text }) => (
            <article key={title} className="flex gap-3 rounded-2xl border border-border bg-card p-4">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-bordeaux/10 text-bordeaux"><Icon className="h-5 w-5" aria-hidden /></span>
              <div>
                <h3 className="text-base font-semibold">{title}</h3>
                <p className="mt-1 text-sm leading-6 text-muted-foreground">{text}</p>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section aria-labelledby="club-examples-title" className="space-y-3">
        <div>
          <h2 id="club-examples-title" className="font-serif text-2xl font-semibold">Esempi di Club</h2>
          <p className="mt-1 text-base text-muted-foreground">Tocca un Club per vedere come si presenta.</p>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {MARKET_VALIDATION_CLUB_DEMOS.map((club) => (
            <button
              key={club.id}
              type="button"
              onClick={() => setSelected(club)}
              className="group overflow-hidden rounded-2xl border border-border bg-card text-left shadow-sm transition hover:border-bordeaux/30 hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <span className="relative block h-24 bg-secondary">
                <Image src={club.cover} alt="" fill unoptimized className="object-cover" />
              </span>
              <span className="block p-4">
                <span className="flex flex-wrap gap-2">
                  <span className="rounded-full bg-secondary px-2.5 py-1 text-xs font-semibold text-antracite">{club.axis}</span>
                  <AccessBadge club={club} />
                  <ExampleBadge />
                </span>
                <span className="mt-3 block font-serif text-xl font-semibold group-hover:text-bordeaux">{club.name}</span>
                <span className="mt-1 block text-sm leading-6 text-muted-foreground">{club.description}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <DemoNotice />
      <Button type="button" size="lg" className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" onClick={onBack}>Torna al test</Button>
    </section>
  );
}

function ClubDemoDetail({ club, onBack }: { club: MarketValidationClubDemo; onBack: () => void }) {
  return (
    <section className="space-y-5" aria-labelledby="club-detail-title">
      <DemoBackButton onBack={onBack} />
      <div className="overflow-hidden rounded-3xl border border-border bg-card">
        <div className="relative h-32 bg-secondary md:h-44">
          <Image src={club.cover} alt="" fill unoptimized className="object-cover" />
        </div>
        <div className="space-y-5 p-5 md:p-8">
          <div>
            <div className="flex flex-wrap gap-2">
              <span className="rounded-full bg-secondary px-2.5 py-1 text-xs font-semibold text-antracite">{club.axis} · {club.focus}</span>
              <AccessBadge club={club} />
              <ExampleBadge />
            </div>
            <h1 id="club-detail-title" className="mt-3 font-serif text-3xl font-semibold">{club.name}</h1>
            <p className="mt-2 text-base leading-7 text-muted-foreground">{club.description}</p>
          </div>

          <p className="flex items-start gap-2 rounded-xl bg-secondary/60 p-3 text-sm leading-6">
            {club.access === "aperto"
              ? <><DoorOpen className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden /> Club aperto: chi lo trova può entrare subito e partecipare.</>
              : <><LockKeyhole className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden /> Club su approvazione: invii una richiesta di ingresso e i gestori del Club la valutano.</>}
          </p>

          <div>
            <h2 className="flex items-center gap-2 font-serif text-xl font-semibold"><ScrollText className="h-5 w-5 text-bordeaux" aria-hidden /> Regole del Club</h2>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-base leading-7">
              {club.rules.map((rule) => <li key={rule}>{rule}</li>)}
            </ul>
          </div>

          <div>
            <h2 className="flex items-center gap-2 font-serif text-xl font-semibold"><MessagesSquare className="h-5 w-5 text-bordeaux" aria-hidden /> Discussioni d&apos;esempio</h2>
            <ul className="mt-3 space-y-2">
              {club.posts.map((post) => (
                <li key={post.title} className="rounded-xl border border-border p-3">
                  <span className="text-xs font-semibold uppercase tracking-wide text-bordeaux">{MARKET_VALIDATION_CLUB_DEMO_POST_LABEL[post.kind]}</span>
                  <p className="mt-1 text-base font-medium">{post.title}</p>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
      <DemoNotice />
    </section>
  );
}

function AccessBadge({ club }: { club: MarketValidationClubDemo }) {
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold ${club.access === "aperto" ? "bg-salvia/15 text-salvia" : "bg-oro/15 text-antracite"}`}>
      {club.access === "aperto" ? <DoorOpen className="h-3.5 w-3.5" aria-hidden /> : <LockKeyhole className="h-3.5 w-3.5" aria-hidden />}
      {MARKET_VALIDATION_CLUB_DEMO_ACCESS_LABEL[club.access]}
    </span>
  );
}

function DemoNotice() {
  return (
    <p className="flex items-start gap-3 rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm leading-6 text-antracite">
      <Info className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
      Club e discussioni sono esempi: in questa demo non ti iscrivi, non pubblichi e non segui nessun Club.
    </p>
  );
}

function ExampleBadge() {
  return (
    <span className="rounded-full border border-dashed border-oro/60 px-2.5 py-1 text-xs font-semibold text-antracite" data-testid="club-demo-example">
      Esempio
    </span>
  );
}
