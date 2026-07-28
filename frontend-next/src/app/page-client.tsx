"use client";

import Link from "next/link";
import { ArrowRight, Sparkles, ShieldCheck, Grape, Heart, Bell } from "lucide-react";
import { communityPosts, type Wine } from "@/data/wines";
import { WineCard } from "@/components/vinea/WineCard";
import { SectionTitle } from "@/components/vinea/Layout";
import { Button } from "@/components/ui/button";
import { wineImages } from "@/lib/wine-images";
import { useVinea } from "@/lib/vinea-store";

const REGIONI = [
  { r: "Piemonte", n: 128, img: wineImages.cellar },
  { r: "Toscana", n: 342, img: wineImages.vineyard },
  { r: "Veneto", n: 87, img: wineImages.bottle2 },
  { r: "Sicilia", n: 54, img: wineImages.crate },
  { r: "Friuli-Venezia Giulia", n: 41, img: wineImages.white },
  { r: "Trentino-Alto Adige", n: 63, img: wineImages.vineyard },
  { r: "Abruzzo", n: 38, img: wineImages.bottle1 },
  { r: "Emilia-Romagna", n: 72, img: wineImages.crate },
  { r: "Lombardia", n: 96, img: wineImages.champagne },
  { r: "Campania", n: 44, img: wineImages.cellar },
  { r: "Puglia", n: 58, img: wineImages.vineyard },
  { r: "Marche", n: 33, img: wineImages.label },
  { r: "Umbria", n: 27, img: wineImages.bottle2 },
  { r: "Liguria", n: 19, img: wineImages.glasses },
  { r: "Sardegna", n: 36, img: wineImages.vineyard },
  { r: "Lazio", n: 41, img: wineImages.cellar },
];

export default function HomePageClient({ annunci }: { annunci: Wine[] }) {
  const { favorites, follows, ruolo } = useVinea();
  // Vetrina e preferiti sono marketplace: annunci reali da Supabase. Il resto
  // della pagina (post community, conteggi per regione) resta mock.
  const scelti = annunci.slice(0, 4);
  const preferiti = annunci.filter((w) => favorites.has(w.id)).slice(0, 4);
  const isGuest = ruolo === "guest";

  return (
    <div className="space-y-16">
      {/* Hero */}
      <section
        className="relative overflow-hidden rounded-3xl bg-bordeaux text-crema hero-glow"
        data-testid="home-hero"
      >
        <div
          className="absolute inset-0 opacity-35 animate-ken-burns"
          style={{
            backgroundImage: `url(${wineImages.cellar})`,
            backgroundSize: "cover",
            backgroundPosition: "center",
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-r from-bordeaux via-bordeaux/85 to-transparent" />
        <div className="hero-grain" aria-hidden />
        <div className="relative px-6 py-16 md:px-14 md:py-24 max-w-2xl">
          <span
            className="inline-flex items-center gap-1.5 rounded-full bg-crema/15 px-3 py-1 text-xs font-medium animate-fade-up"
            style={{ animationDelay: "40ms" }}
          >
            <Sparkles className="h-3.5 w-3.5 text-oro" /> Vinea Wine Club — il wine club degli
            appassionati italiani
          </span>
          <h1
            className="mt-4 font-serif text-4xl leading-[1.05] md:text-6xl animate-fade-up"
            style={{ animationDelay: "120ms" }}
          >
            Ogni bottiglia
            <br />
            ha una storia.
            <br />
            <span className="gold-shimmer">Trova la prossima.</span>
          </h1>
          <p
            className="mt-5 max-w-lg text-base text-crema/85 md:text-lg animate-fade-up"
            style={{ animationDelay: "200ms" }}
          >
            Compra, vendi e cataloga vini all'interno di un club italiano dedicato agli
            appassionati.
          </p>
          <div
            className="mt-8 flex flex-wrap gap-3 animate-fade-up"
            style={{ animationDelay: "280ms" }}
          >
            {isGuest ? (
              <>
                <Button
                  asChild
                  size="lg"
                  className="bg-oro text-antracite hover:bg-oro/90"
                  data-testid="hero-cta-register"
                >
                  <Link href="/registrati">
                    Registrati <ArrowRight className="ml-1 h-4 w-4" />
                  </Link>
                </Button>
                <Button
                  asChild
                  size="lg"
                  variant="outline"
                  className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
                  data-testid="hero-cta-explore-guest"
                >
                  <Link href="/esplora">Esplora come ospite</Link>
                </Button>
              </>
            ) : (
              <>
                <Button
                  asChild
                  size="lg"
                  className="bg-oro text-antracite hover:bg-oro/90"
                  data-testid="hero-cta-search"
                >
                  <Link href="/esplora">
                    Cerca bottiglie <ArrowRight className="ml-1 h-4 w-4" />
                  </Link>
                </Button>
                <Button
                  asChild
                  size="lg"
                  variant="outline"
                  className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
                  data-testid="hero-cta-cellar"
                >
                  <Link href="/cantina">Crea la tua cantina</Link>
                </Button>
              </>
            )}
          </div>
        </div>
      </section>

      {isGuest && (
        <section className="rounded-3xl border border-oro/40 bg-oro/10 p-5 md:p-6">
          <div className="flex flex-col items-start gap-4 md:flex-row md:items-center md:justify-between">
            <div className="min-w-0">
              <p className="font-serif text-xl md:text-2xl">Vuoi provare tutte le funzioni?</p>
              <p className="mt-1 text-sm text-antracite/80">
                Registrati in modalità demo per accedere a cantina, preferiti, messaggi e vendita.
              </p>
            </div>
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href="/onboarding">Inizia l'onboarding</Link>
            </Button>
          </div>
        </section>
      )}

      {/* trust bar */}
      <section className="grid gap-4 md:grid-cols-3">
        {[
          { icon: ShieldCheck, t: "Venditori verificati", d: "Identità e provenienza controllate" },
          {
            icon: Grape,
            t: "Solo bottiglie con storia",
            d: "Ogni annuncio racconta la sua origine",
          },
          { icon: Sparkles, t: "Un club di appassionati", d: "Consigli, degustazioni, verticali" },
        ].map((x, i) => (
          <div
            key={x.t}
            className="flex gap-3 rounded-2xl border border-border bg-card p-5 card-lift perf-card animate-fade-up"
            style={{ animationDelay: `${i * 80 + 120}ms` }}
          >
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-salvia/15 text-salvia">
              <x.icon className="h-5 w-5" />
            </span>
            <div>
              <p className="font-serif text-lg font-semibold">{x.t}</p>
              <p className="text-sm text-muted-foreground">{x.d}</p>
            </div>
          </div>
        ))}
      </section>

      {/* Scelti per te */}
      <section>
        <SectionTitle
          action={
            <Link href="/esplora" className="text-sm font-medium text-bordeaux hover:underline">
              Vedi tutto →
            </Link>
          }
        >
          <span className="inline-flex items-center gap-2">
            Scelti per te questa settimana
            <span className="rounded-full bg-oro/20 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider text-antracite">
              Selezione intelligente
            </span>
          </span>
        </SectionTitle>
        <p className="mb-4 -mt-2 text-sm text-muted-foreground">
          Una selezione basata sui tuoi preferiti, sui club che segui e sulle attività recenti.
        </p>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          {scelti.map((w) => (
            <WineCard key={w.id} wine={w} showSaleBadge />
          ))}
        </div>
      </section>

      {/* Regioni: horizontal scroll on mobile, grid on desktop */}
      <section className="cv-auto">
        <SectionTitle
          action={
            <Link href="/esplora" className="text-sm font-medium text-bordeaux hover:underline">
              Vedi tutte →
            </Link>
          }
        >
          Cerca per regione
        </SectionTitle>
        <div className="-mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-2 md:hidden">
          {REGIONI.map((x) => (
            <Link
              key={x.r}
              href="/esplora"
              className="group relative aspect-[4/3] w-40 shrink-0 snap-start overflow-hidden rounded-2xl card-lift"
            >
              <img
                src={x.img}
                alt={x.r}
                loading="lazy"
                decoding="async"
                className="h-full w-full object-cover img-reveal group-hover:scale-110"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-antracite/85 via-antracite/30 to-transparent" />
              <div className="absolute bottom-2 left-2 text-crema">
                <p className="font-serif text-base font-semibold leading-tight">{x.r}</p>
                <p className="text-[10px] opacity-80">{x.n} bottiglie</p>
              </div>
            </Link>
          ))}
        </div>
        <div className="hidden grid-cols-4 gap-3 md:grid">
          {REGIONI.slice(0, 12).map((x) => (
            <Link
              key={x.r}
              href="/esplora"
              className="group relative aspect-[4/3] overflow-hidden rounded-2xl card-lift img-sheen"
            >
              <img
                src={x.img}
                alt={x.r}
                loading="lazy"
                decoding="async"
                className="h-full w-full object-cover img-reveal group-hover:scale-110"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-antracite/85 via-antracite/30 to-transparent" />
              <div className="absolute bottom-3 left-3 text-crema">
                <p className="font-serif text-xl font-semibold">{x.r}</p>
                <p className="text-xs opacity-80">{x.n} bottiglie</p>
              </div>
            </Link>
          ))}
        </div>
      </section>

      {/* I tuoi preferiti */}
      <section>
        <SectionTitle
          action={
            <Link href="/profilo" className="text-sm font-medium text-bordeaux hover:underline">
              Gestisci →
            </Link>
          }
        >
          <span className="inline-flex items-center gap-2">
            <Heart className="h-5 w-5 text-bordeaux" /> I tuoi preferiti
          </span>
        </SectionTitle>
        {preferiti.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-8 text-center text-sm text-muted-foreground">
            Non hai ancora salvato bottiglie. Tocca il cuore per aggiungerle qui.
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            {preferiti.map((w) => (
              <WineCard key={w.id} wine={w} showSaleBadge />
            ))}
          </div>
        )}
      </section>

      {/* Notizie dai seguiti */}
      <section className="cv-auto">
        <SectionTitle
          action={
            <Link href="/community" className="text-sm font-medium text-bordeaux hover:underline">
              Apri i club →
            </Link>
          }
        >
          <span className="inline-flex items-center gap-2">
            <Bell className="h-5 w-5" /> Notizie dai seguiti
          </span>
        </SectionTitle>
        <ul className="grid gap-3 md:grid-cols-2">
          {[
            {
              chi: "Marco B.",
              ruolo: "Venditore seguito",
              t: `Ha pubblicato un nuovo annuncio: Barolo Monfortino 2015`,
              tempo: "1 ora fa",
              link: "/annuncio/$id",
              id: "monfortino-2015",
            },
            {
              chi: "Sofia R.",
              ruolo: "Membro del club Brunello",
              t: "Ha condiviso una nota di degustazione su Biondi-Santi 2016",
              tempo: "3 ore fa",
              link: "/community/$slug",
              id: "brunello",
            },
            {
              chi: "Antinori",
              ruolo: "Produttore seguito",
              t: "Aggiornamento cantina: nuova annata Tignanello disponibile",
              tempo: "ieri",
              link: "/annuncio/$id",
              id: "tignanello-2019",
            },
            {
              chi: "Andrea C.",
              ruolo: "Utente del club Barolo",
              t: "Nuovo post nel club Barolo & Barbaresco: 'Cannubi vs Brunate'",
              tempo: "ieri",
              link: "/community/$slug",
              id: "barolo-barbaresco",
            },
          ].map((n, i) => (
            <li key={i}>
              {n.link === "/annuncio/$id" ? (
                <Link
                  href={`/annuncio/${n.id}`}
                  className="block rounded-2xl border border-border bg-card p-4 hover:shadow-md"
                >
                  <p className="text-[11px] uppercase tracking-wide text-salvia">
                    {n.ruolo} • {n.tempo}
                  </p>
                  <p className="mt-1 font-serif text-base font-semibold">{n.chi}</p>
                  <p className="mt-0.5 text-sm text-muted-foreground">{n.t}</p>
                </Link>
              ) : (
                <Link
                  href={`/community/${n.id}`}
                  className="block rounded-2xl border border-border bg-card p-4 hover:shadow-md"
                >
                  <p className="text-[11px] uppercase tracking-wide text-salvia">
                    {n.ruolo} • {n.tempo}
                  </p>
                  <p className="mt-1 font-serif text-base font-semibold">{n.chi}</p>
                  <p className="mt-0.5 text-sm text-muted-foreground">{n.t}</p>
                </Link>
              )}
            </li>
          ))}
        </ul>
        {follows.size === 0 && (
          <p className="mt-3 text-xs text-muted-foreground">
            Segui produttori, venditori e club per personalizzare questa sezione.
          </p>
        )}
      </section>

      {/* Club teaser */}
      <section className="cv-auto">
        <SectionTitle
          action={
            <Link href="/community" className="text-sm font-medium text-bordeaux hover:underline">
              Scopri i club →
            </Link>
          }
        >
          Attività del club
        </SectionTitle>
        <div className="grid gap-4 md:grid-cols-3">
          {communityPosts.map((p, i) => (
            <article
              key={p.id}
              className="group overflow-hidden rounded-2xl border border-border bg-card card-lift perf-card animate-fade-up"
              style={{ animationDelay: `${i * 80}ms` }}
            >
              <div className="img-sheen aspect-[16/10] overflow-hidden">
                <img
                  src={p.immagine}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="h-full w-full object-cover img-reveal group-hover:scale-105"
                />
              </div>
              <div className="p-4">
                <div className="flex items-center gap-2">
                  <img
                    src={p.avatar}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    className="h-8 w-8 rounded-full"
                  />
                  <div>
                    <p className="text-sm font-semibold">{p.autore}</p>
                    <p className="text-xs text-muted-foreground">{p.tempo}</p>
                  </div>
                </div>
                <p className="mt-3 line-clamp-3 text-sm">{p.testo}</p>
              </div>
            </article>
          ))}
        </div>
      </section>

      <footer className="border-t border-border pt-8 pb-4 text-center text-xs text-muted-foreground">
        <p className="font-serif text-lg text-bordeaux">Vinea</p>
        <p className="mt-0.5 text-[10px] uppercase tracking-[0.35em] text-oro">Wine Club</p>
        <p className="mt-2">Il wine club degli appassionati italiani.</p>
      </footer>
    </div>
  );
}
