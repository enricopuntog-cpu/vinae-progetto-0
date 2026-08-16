"use client";

import Link from "next/link";
import { ArrowRight, Grape, Search, ShieldCheck, Sparkles } from "lucide-react";
import { WineCard } from "@/components/vinea/WineCard";
import { SectionTitle } from "@/components/vinea/Layout";
import { Button } from "@/components/ui/button";
import type { Wine } from "@/data/wines";
import { wineImages } from "@/lib/wine-images";
import { useVinea } from "@/lib/vinea-store";

const REGIONI = [
  "Piemonte",
  "Toscana",
  "Veneto",
  "Sicilia",
  "Friuli-Venezia Giulia",
  "Trentino-Alto Adige",
  "Abruzzo",
  "Emilia-Romagna",
  "Lombardia",
  "Campania",
  "Puglia",
  "Marche",
];

const Hero = ({ guest }: { guest: boolean }) => (
  <section className="relative overflow-hidden rounded-3xl bg-bordeaux text-crema hero-glow">
    <div className="absolute inset-0 opacity-35" style={{ backgroundImage: `url(${wineImages.cellar})`, backgroundSize: "cover" }} />
    <div className="absolute inset-0 bg-gradient-to-r from-bordeaux via-bordeaux/85 to-transparent" />
    <div className="relative max-w-2xl px-6 py-16 md:px-14 md:py-24">
      <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
      <h1 className="mt-4 font-serif text-4xl leading-tight md:text-6xl">
        Ogni bottiglia ha una storia. <span className="gold-shimmer">Trova la prossima.</span>
      </h1>
      <p className="mt-5 text-crema/85">Compra, vendi e cataloga vini tra appassionati italiani.</p>
      <div className="mt-8 flex flex-wrap gap-3">
        <Button asChild size="lg" className="bg-oro text-antracite hover:bg-oro/90">
          <Link href={guest ? "/registrati" : "/esplora"}>
            {guest ? "Registrati" : "Cerca bottiglie"} <ArrowRight className="h-4 w-4" />
          </Link>
        </Button>
        <Button asChild size="lg" variant="outline" className="border-crema/40 bg-transparent text-crema hover:bg-crema/10">
          <Link href={guest ? "/esplora" : "/cantina"}>{guest ? "Esplora il catalogo" : "Apri la cantina"}</Link>
        </Button>
      </div>
    </div>
  </section>
);

const TrustBar = () => (
  <section className="grid gap-4 md:grid-cols-3">
    {[
      { icon: ShieldCheck, title: "Dati dichiarati", text: "Provenienza e conservazione restano attribuite al venditore." },
      { icon: Grape, title: "Solo vino", text: "Il catalogo è dedicato esclusivamente alle bottiglie di vino." },
      { icon: Sparkles, title: "Beta trasparente", text: "Le azioni non ancora operative sono indicate prima dell'uso." },
    ].map(({ icon: Icon, title, text }) => (
      <div key={title} className="flex gap-3 rounded-2xl border border-border bg-card p-5">
        <span className="grid h-11 w-11 place-items-center rounded-full bg-salvia/15 text-salvia"><Icon className="h-5 w-5" /></span>
        <div><p className="font-serif text-lg font-semibold">{title}</p><p className="text-sm text-muted-foreground">{text}</p></div>
      </div>
    ))}
  </section>
);

const ListingGrid = ({ annunci }: { annunci: Wine[] }) => (
  <section>
    <SectionTitle action={<Link href="/esplora" className="text-sm text-bordeaux hover:underline">Vedi tutto →</Link>}>
      Annunci in evidenza
    </SectionTitle>
    {annunci.length === 0 ? (
      <p className="rounded-2xl border border-dashed p-8 text-center text-sm text-muted-foreground">Nessun annuncio pubblicato al momento.</p>
    ) : (
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">{annunci.slice(0, 4).map((wine) => <WineCard key={wine.id} wine={wine} />)}</div>
    )}
  </section>
);

const RegionGrid = () => (
  <section>
    <SectionTitle><span className="inline-flex items-center gap-2"><Search className="h-5 w-5" /> Cerca per regione</span></SectionTitle>
    <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
      {REGIONI.map((regione) => <Link key={regione} href={`/esplora?regione=${encodeURIComponent(regione)}`} className="rounded-2xl border bg-card p-4 font-serif hover:border-bordeaux">{regione}</Link>)}
    </div>
  </section>
);

const HomePageClient = ({ annunci }: { annunci: Wine[] }) => {
  const { ruolo } = useVinea();
  return (
    <div className="space-y-14">
      <Hero guest={ruolo === "guest"} />
      <TrustBar />
      <ListingGrid annunci={annunci} />
      <RegionGrid />
    </div>
  );
};

export default HomePageClient;
