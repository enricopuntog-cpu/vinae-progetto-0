import { createFileRoute, Link } from "@tanstack/react-router";
import {
  Settings,
  ShieldCheck,
  Star,
  MapPin,
  Wine as WineIcon,
  Heart,
  Store,
  ShoppingBag,
  Tag,
  MessageCircle,
  Bell,
  BadgeCheck,
  ScrollText,
  ArrowRight,
  RefreshCw,
  CheckCircle2,
  Flag,
} from "lucide-react";
import { wines } from "@/data/wines";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { WineCard } from "@/components/vinea/WineCard";
import { Kpi } from "@/components/vinea/Layout";
import {
  EmailBadge,
  AgeBadge,
  IdentityBadge,
  SellerBadge,
} from "@/components/vinea/VerificationBadges";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { wineImages } from "@/lib/wine-images";
import { toast } from "sonner";

export const Route = createFileRoute("/profilo")({
  head: () => ({
    meta: [
      { title: "Il mio profilo — Vinea" },
      { name: "description", content: "La tua identità di collezionista Vinea." },
      { property: "og:title", content: "Profilo — Vinea" },
      {
        property: "og:description",
        content: "Cantina, annunci, acquisti, vendite, preferiti, messaggi, notifiche, recensioni.",
      },
    ],
  }),
  component: Profilo,
});

const scorciatoie = [
  { to: "/cantina", label: "Cantina", icon: WineIcon },
  { to: "/profilo?tab=vendita", label: "Annunci", icon: Tag },
  { to: "/acquisti", label: "Acquisti", icon: ShoppingBag },
  { to: "/vendite", label: "Vendite", icon: Store },
  { to: "/profilo?tab=preferiti", label: "Preferiti", icon: Heart },
  { to: "/messaggi", label: "Messaggi", icon: MessageCircle },
  { to: "/notifiche", label: "Notifiche", icon: Bell },
  { to: "/segnalazioni", label: "Segnalazioni", icon: Flag },
] as const;

function Profilo() {
  const {
    favorites,
    follows,
    nonLette,
    ruolo,
    profilo,
    emailStatus,
    ageStatus,
    identityStatus,
    sellerStatus,
    profileCompletion,
    verifyEmail,
    resetOnboarding,
  } = useVinea();
  const preferiti = wines.filter((w) => favorites.has(w.id));
  const inVendita = wines.slice(0, 3);
  const acquisti = wines.slice(3, 6);
  const vendite = wines.slice(0, 4);

  if (ruolo === "guest") {
    return (
      <div className="mx-auto max-w-lg space-y-4 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
          <ShieldCheck className="h-8 w-8 text-bordeaux" />
        </div>
        <h1 className="font-serif text-2xl md:text-3xl">Crea il tuo account demo</h1>
        <p className="text-sm text-muted-foreground">
          Stai navigando come ospite. Registrati per accedere a cantina, preferiti, messaggi e
          vendita.
        </p>
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link to="/onboarding">Inizia l'onboarding</Link>
        </Button>
        <p className="text-xs text-muted-foreground">
          Modalità demo — nessun dato reale viene raccolto.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-8" data-testid="profile-page">
      {/* Hero cinematografica del profilo */}
      <section
        className="relative overflow-hidden rounded-3xl border border-border hero-glow"
        data-testid="profile-hero"
      >
        <img
          src={wineImages.vineyard}
          alt=""
          className="absolute inset-0 h-full w-full object-cover animate-ken-burns"
          fetchPriority="high"
          decoding="async"
        />
        <div className="absolute inset-0 bg-gradient-to-r from-antracite/90 via-antracite/70 to-antracite/40" />
        <div className="hero-grain" aria-hidden />
        <div className="relative flex flex-col items-start gap-5 p-5 text-crema md:flex-row md:items-center md:p-8">
          <img
            src={profilo.avatarUrl}
            alt=""
            loading="lazy"
            decoding="async"
            data-testid="profile-avatar"
            className="h-20 w-20 shrink-0 rounded-full object-cover ring-4 ring-oro/40 md:h-24 md:w-24 animate-fade-up"
          />
          <div className="min-w-0 flex-1 animate-fade-up" style={{ animationDelay: "60ms" }}>
            <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
            <p className="mt-1 flex flex-wrap items-center gap-2 font-serif text-3xl md:text-4xl">
              <span className="break-words">
                {profilo.username === "elena_r" ? (
                  <>
                    Elena <span className="gold-shimmer">Rossi</span>
                  </>
                ) : (
                  <span className="gold-shimmer">{profilo.username}</span>
                )}
              </span>
              {identityStatus === "verificata" && (
                <ShieldCheck className="h-6 w-6 shrink-0 text-oro" />
              )}
            </p>
            <p className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-crema/85">
              <span className="flex items-center gap-1">
                <MapPin className="h-3.5 w-3.5" /> {profilo.citta || "—"}
              </span>
              <span className="hidden sm:inline">•</span>
              <span className="flex items-center gap-1">
                <Star className="h-3.5 w-3.5 fill-oro text-oro" /> 4.9 (58)
              </span>
              <span className="hidden sm:inline">•</span>
              <span>Membro dal 2024</span>
            </p>
            <p className="mt-3 max-w-xl text-sm text-crema/90">{profilo.bio}</p>
            <div className="mt-3 flex flex-wrap gap-1.5" data-testid="profile-badges">
              <EmailBadge status={emailStatus} />
              <AgeBadge status={ageStatus} />
              <IdentityBadge status={identityStatus} />
              <SellerBadge status={sellerStatus} />
            </div>
          </div>
          <div
            className="grid w-full grid-cols-1 gap-2 sm:grid-cols-3 md:w-auto md:flex md:flex-col animate-fade-up"
            style={{ animationDelay: "120ms" }}
          >
            <Button
              data-testid="profile-btn-settings"
              variant="outline"
              className="min-w-0 border-crema/40 bg-transparent text-crema hover:bg-crema/10"
              onClick={() => toast("Impostazioni account (demo)")}
            >
              <Settings className="h-4 w-4" /> <span className="truncate">Impostazioni</span>
            </Button>
            <Button
              data-testid="profile-btn-verify"
              asChild
              variant="outline"
              className="min-w-0 border-crema/40 bg-transparent text-crema hover:bg-crema/10"
            >
              <Link to="/verifica-venditore">
                <BadgeCheck className="h-4 w-4" /> <span className="truncate">Verifica</span>
              </Link>
            </Button>
            <Button
              data-testid="profile-btn-sell"
              asChild
              className="min-w-0 bg-oro text-antracite hover:bg-oro/90"
            >
              <Link to="/vendi">Vendi</Link>
            </Button>
          </div>
        </div>

        {profileCompletion.perc < 100 && (
          <div
            className="relative m-5 mt-0 rounded-2xl border border-crema/20 bg-antracite/60 p-4 text-crema backdrop-blur md:m-8 md:mt-0"
            data-testid="profile-completion-card"
          >
            <div className="flex items-center justify-between gap-3">
              <p className="text-sm font-medium">Completamento profilo</p>
              <span
                className="rounded-full bg-oro/20 px-2 py-0.5 text-xs font-semibold text-oro"
                data-testid="profile-completion-pct"
              >
                {profileCompletion.perc}%
              </span>
            </div>
            <Progress value={profileCompletion.perc} className="mt-2 h-1.5" />
            <ul className="mt-3 grid gap-1.5 sm:grid-cols-2">
              {profileCompletion.items.map((i) => (
                <li key={i.label} className="flex items-center gap-2 text-sm">
                  {i.done ? (
                    <CheckCircle2 className="h-4 w-4 shrink-0 text-oro" />
                  ) : (
                    <span className="grid h-4 w-4 shrink-0 place-items-center rounded-full border border-crema/40 text-[9px] text-crema/60">
                      ·
                    </span>
                  )}
                  {i.done ? (
                    <span className="min-w-0 truncate text-crema/90">{i.label}</span>
                  ) : (
                    <a href={i.to} className="min-w-0 truncate text-oro hover:underline">
                      {i.label}
                    </a>
                  )}
                </li>
              ))}
            </ul>
            <div className="mt-3 flex flex-wrap gap-2">
              {emailStatus !== "verificata" && (
                <Button
                  data-testid="profile-btn-verify-email"
                  size="sm"
                  variant="outline"
                  onClick={verifyEmail}
                  className="border-crema/30 bg-transparent text-xs text-crema hover:bg-crema/10"
                >
                  <RefreshCw className="h-3 w-3" /> Verifica email (demo)
                </Button>
              )}
              {identityStatus === "non_avviata" && (
                <Button asChild size="sm" className="bg-oro text-antracite text-xs hover:bg-oro/90">
                  <Link to="/verifica-venditore">Verifica identità</Link>
                </Button>
              )}
              <Button
                data-testid="profile-btn-reset-onboarding"
                size="sm"
                variant="ghost"
                className="text-xs text-crema/70 hover:bg-crema/10 hover:text-crema"
                onClick={resetOnboarding}
              >
                Reimposta onboarding
              </Button>
            </div>
          </div>
        )}
      </section>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="In vendita" value={String(inVendita.length)} />
        <Kpi label="In cantina" value={String(wines.slice(0, 6).length)} />
        <Kpi label="Preferiti" value={String(preferiti.length)} />
        <Kpi label="Seguiti" value={String(follows.size)} />
      </div>

      <section>
        <p className="mb-3 text-xs uppercase tracking-wide text-muted-foreground">Accessi rapidi</p>
        <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
          {scorciatoie.map((s) => (
            <a
              key={s.label}
              href={s.to}
              className="flex min-w-0 items-center gap-2 rounded-2xl border border-border bg-card p-3 hover:shadow-md sm:gap-3"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-secondary text-bordeaux sm:h-10 sm:w-10">
                <s.icon className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1 truncate text-sm font-medium">{s.label}</span>
              {s.label === "Notifiche" && nonLette > 0 && (
                <span className="shrink-0 rounded-full bg-bordeaux px-1.5 py-0.5 text-[10px] text-crema">
                  {nonLette}
                </span>
              )}
              <ArrowRight className="hidden h-4 w-4 shrink-0 text-muted-foreground sm:block" />
            </a>
          ))}
        </div>
      </section>

      <Tabs defaultValue="vendita">
        <div className="-mx-4 tab-scroll overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList className="inline-flex w-max min-w-full bg-secondary">
            <TabsTrigger value="vendita">
              <Tag className="h-4 w-4" /> Annunci
            </TabsTrigger>
            <TabsTrigger value="acquisti">
              <ShoppingBag className="h-4 w-4" /> Acquisti
            </TabsTrigger>
            <TabsTrigger value="vendite">
              <Store className="h-4 w-4" /> Vendite
            </TabsTrigger>
            <TabsTrigger value="preferiti">
              <Heart className="h-4 w-4" /> Preferiti
            </TabsTrigger>
            <TabsTrigger value="cantina">
              <WineIcon className="h-4 w-4" /> Cantina
            </TabsTrigger>
            <TabsTrigger value="recensioni">
              <Star className="h-4 w-4" /> Recensioni
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent
          value="vendita"
          className="mt-4 grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4"
        >
          {inVendita.map((w) => (
            <WineCard key={w.id} wine={w} />
          ))}
        </TabsContent>

        <TabsContent value="acquisti" className="mt-4 space-y-2">
          {acquisti.map((w) => (
            <div
              key={w.id}
              className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3"
            >
              <img src={w.immagini[0]} alt="" className="h-16 w-12 rounded object-cover" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-serif font-semibold">
                  {w.nome} {w.annata}
                </p>
                <p className="text-xs text-muted-foreground">
                  Acquistato da {w.venditore.nome} • {formatEUR(w.prezzo)}
                </p>
              </div>
              <span className="rounded-full bg-salvia/15 px-2 py-0.5 text-[10px] text-salvia">
                Consegnato
              </span>
            </div>
          ))}
        </TabsContent>

        <TabsContent value="vendite" className="mt-4 space-y-2">
          {vendite.map((w) => (
            <div
              key={w.id}
              className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3"
            >
              <img src={w.immagini[0]} alt="" className="h-16 w-12 rounded object-cover" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-serif font-semibold">
                  {w.nome} {w.annata}
                </p>
                <p className="text-xs text-muted-foreground">
                  Vendita chiusa • {formatEUR(w.prezzo)}
                </p>
              </div>
              <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px]">Spedito</span>
            </div>
          ))}
        </TabsContent>

        <TabsContent value="preferiti" className="mt-4">
          {preferiti.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
              <p className="font-serif text-xl">Nessun preferito ancora</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Salva le bottiglie che ti incuriosiscono.
              </p>
              <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
                <Link to="/esplora">Ricerca</Link>
              </Button>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
              {preferiti.map((w) => (
                <WineCard key={w.id} wine={w} />
              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="cantina" className="mt-4">
          <Link to="/cantina" className="mb-3 inline-block text-sm text-bordeaux hover:underline">
            Apri gestione completa →
          </Link>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
            {wines.slice(0, 6).map((w) => (
              <WineCard key={w.id} wine={w} />
            ))}
          </div>
        </TabsContent>

        <TabsContent value="recensioni" className="mt-4 space-y-3">
          {[
            { a: "Marco B.", s: "Bottiglia impeccabile, imballaggio perfetto. Consigliata.", r: 5 },
            { a: "Sofia R.", s: "Comunicazione rapida e cortese. Grazie!", r: 5 },
            { a: "Luca P.", s: "Tutto come descritto, spedizione veloce.", r: 4 },
          ].map((rev, i) => (
            <div key={i} className="rounded-2xl border border-border bg-card p-4">
              <div className="flex items-center justify-between">
                <p className="font-semibold">{rev.a}</p>
                <div className="flex">
                  {Array.from({ length: rev.r }).map((_, k) => (
                    <Star key={k} className="h-4 w-4 fill-oro text-oro" />
                  ))}
                </div>
              </div>
              <p className="mt-1 text-sm">{rev.s}</p>
            </div>
          ))}
        </TabsContent>
      </Tabs>

      <div className="flex items-center gap-2 rounded-2xl border border-border bg-card p-4 text-sm text-muted-foreground">
        <ScrollText className="h-4 w-4" />
        Valore stimato della cantina:{" "}
        <b className="text-bordeaux">
          {formatEUR(wines.slice(0, 6).reduce((s, w) => s + w.prezzo * w.disponibili, 0))}
        </b>
      </div>
    </div>
  );
}
