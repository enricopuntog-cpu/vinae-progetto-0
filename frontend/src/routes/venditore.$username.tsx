import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { ShieldCheck, MapPin, Star, Clock, Users, MessageCircle, ArrowLeft } from "lucide-react";
import { sellerByUsername, annunciDelVenditore } from "@/data/extra";
import { communities } from "@/data/communities";
import { WineCard } from "@/components/vinea/WineCard";
import { Button } from "@/components/ui/button";
import { Kpi } from "@/components/vinea/Layout";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { useVinea } from "@/lib/vinea-store";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { formatInteger } from "@/lib/format";

export const Route = createFileRoute("/venditore/$username")({
  loader: ({ params }) => {
    const seller = sellerByUsername(params.username);
    if (!seller) throw notFound();
    return { seller };
  },
  head: ({ loaderData }) => {
    const s = loaderData?.seller;
    const t = s ? `${s.nome} — Vinea` : "Venditore — Vinea";
    return {
      meta: [
        { title: t },
        { name: "description", content: s?.bio ?? "Profilo pubblico venditore Vinea" },
        { property: "og:title", content: t },
        { property: "og:description", content: s?.bio ?? "Profilo pubblico venditore Vinea" },
        ...(s
          ? [
              { property: "og:image", content: s.avatar },
              { name: "twitter:image", content: s.avatar },
            ]
          : []),
      ],
    };
  },
  notFoundComponent: () => (
    <div className="rounded-2xl border border-border bg-card p-10 text-center">
      <p className="font-serif text-2xl">Venditore non trovato</p>
      <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
        <Link to="/esplora">Ricerca</Link>
      </Button>
    </div>
  ),
  component: VenditorePublic,
});

function VenditorePublic() {
  const { seller } = Route.useLoaderData();
  const { follows, toggleFollow } = useVinea();
  const seguito = follows.has(seller.nome);
  const annunci = annunciDelVenditore(seller.nome);
  const seguiteCom = communities.filter((c) => seller.communities.includes(c.slug));

  return (
    <div className="space-y-8">
      <Link
        to="/esplora"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Ricerca
      </Link>

      <header className="rounded-3xl border border-border bg-card p-6 md:p-8">
        <div className="flex flex-col items-start gap-5 md:flex-row md:items-center">
          <img
            src={seller.avatar}
            alt=""
            className="h-24 w-24 rounded-full object-cover ring-4 ring-oro/30"
          />
          <div className="min-w-0 flex-1">
            <p className="flex flex-wrap items-center gap-2 font-serif text-3xl">
              {seller.nome}
              {seller.verificato && (
                <span className="inline-flex items-center gap-1 rounded-full bg-salvia/15 px-2 py-0.5 text-xs text-salvia">
                  <ShieldCheck className="h-3.5 w-3.5" /> Identità verificata
                </span>
              )}
            </p>
            <p className="mt-0.5 text-sm text-muted-foreground">
              @{seller.username} • membro dal {seller.membroDal}
            </p>
            <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
              <span className="flex items-center gap-1">
                <MapPin className="h-3.5 w-3.5" /> {seller.provincia}
              </span>
              <span>•</span>
              <span className="flex items-center gap-1">
                <Star className="h-3.5 w-3.5 fill-oro text-oro" /> {seller.rating} (
                {seller.valutazioni})
              </span>
              <span>•</span>
              <span className="flex items-center gap-1">
                <Clock className="h-3.5 w-3.5" /> Risponde in {seller.tempoRisposta}
              </span>
            </p>
            <p className="mt-3 max-w-xl text-sm">{seller.bio}</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              variant={seguito ? "outline" : "default"}
              className={seguito ? "" : "bg-bordeaux hover:bg-bordeaux/90"}
              onClick={() => toggleFollow(seller.nome)}
            >
              <Users className="h-4 w-4" /> {seguito ? "Seguito" : "Segui"}
            </Button>
            <Button asChild variant="outline">
              <Link to="/messaggi">
                <MessageCircle className="h-4 w-4" /> Contatta
              </Link>
            </Button>
            <ReportDialog
              targetType="profilo"
              targetId={seller.username}
              targetLabel={`Profilo @${seller.username}`}
            />
          </div>
        </div>
      </header>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="Annunci" value={String(annunci.length)} />
        <Kpi label="Vendite" value={String(seller.vendite)} />
        <Kpi label="Acquisti" value={String(seller.acquisti)} />
        <Kpi label="Follower" value={String(seller.follower)} />
      </div>

      <Tabs defaultValue="annunci">
        <TabsList className="bg-secondary">
          <TabsTrigger value="annunci">Annunci</TabsTrigger>
          <TabsTrigger value="cantina">Cantina pubblica</TabsTrigger>
          <TabsTrigger value="community">Club</TabsTrigger>
          <TabsTrigger value="recensioni">Recensioni</TabsTrigger>
        </TabsList>

        <TabsContent value="annunci" className="mt-4">
          {annunci.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground">
              Nessun annuncio attivo.
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
              {annunci.map((w) => (
                <WineCard key={w.id} wine={w} showSaleBadge />
              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="cantina" className="mt-4">
          <p className="mb-3 text-sm text-muted-foreground">
            Selezione visibile pubblicamente dal collezionista.
          </p>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
            {annunci.map((w) => (
              <WineCard key={w.id} wine={w} showSaleBadge hidePriceIfPrivate />
            ))}
          </div>
        </TabsContent>

        <TabsContent value="community" className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          {seguiteCom.length === 0 ? (
            <p className="text-sm text-muted-foreground">Non ha ancora dichiarato club pubblici.</p>
          ) : (
            seguiteCom.map((c) => (
              <Link
                key={c.slug}
                to="/community/$slug"
                params={{ slug: c.slug }}
                className="flex gap-3 rounded-2xl border border-border bg-card p-3 hover:shadow-md"
              >
                <img src={c.cover} alt="" className="h-16 w-24 rounded-lg object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="font-serif font-semibold">{c.nome}</p>
                  <p className="text-xs text-muted-foreground">{formatInteger(c.membri)} membri</p>
                </div>
              </Link>
            ))
          )}
        </TabsContent>

        <TabsContent value="recensioni" className="mt-4 space-y-3">
          {[
            { a: "Elena R.", s: "Comunicazione impeccabile. Bottiglia arrivata perfetta.", r: 5 },
            { a: "Luca P.", s: "Prezzo giusto, imballaggio da manuale.", r: 5 },
            { a: "Chiara V.", s: "Tutto ok, consigliato.", r: 4 },
          ].map((r, i) => (
            <div key={i} className="rounded-2xl border border-border bg-card p-4">
              <div className="flex items-center justify-between">
                <p className="font-semibold">{r.a}</p>
                <div className="flex">
                  {Array.from({ length: r.r }).map((_, k) => (
                    <Star key={k} className="h-4 w-4 fill-oro text-oro" />
                  ))}
                </div>
              </div>
              <p className="mt-1 text-sm">{r.s}</p>
            </div>
          ))}
        </TabsContent>
      </Tabs>
    </div>
  );
}
