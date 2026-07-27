import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Search, Users, TrendingUp } from "lucide-react";
import { communities, discussions } from "@/data/communities";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { SectionTitle } from "@/components/vinea/Layout";
import { useVinea } from "@/lib/vinea-store";
import { wineImages } from "@/lib/wine-images";

export const Route = createFileRoute("/community/")({
  head: () => ({
    meta: [
      { title: "Club Vinea" },
      {
        name: "description",
        content:
          "Club Vinea per territorio, denominazione, produttore e tipologia. Barolo, Brunello, Champagne, Borgogna, naturali, grandi formati e Amarone.",
      },
      { property: "og:title", content: "Club — Vinea Wine Club" },
      {
        property: "og:description",
        content: "Racconti, degustazioni, confronti e sondaggi sui grandi vini.",
      },
    ],
  }),
  component: CommunityHub,
});

const territori = ["Tutti", "Piemonte", "Toscana", "Veneto", "Champagne", "Borgogna", "Italia"];
const denominazioni = [
  "Tutte",
  "Barolo DOCG",
  "Brunello di Montalcino DOCG",
  "Champagne AOC",
  "Amarone della Valpolicella DOCG",
];
const produttori = ["Tutti", "Giacomo Conterno", "Biondi-Santi", "Moët & Chandon"];
const tipologie = ["Tutte", "Rosso", "Bianco", "Bollicine"];

function CommunityHub() {
  const { communityFollows, toggleCommunityFollow } = useVinea();
  const [q, setQ] = useState("");
  const [terr, setTerr] = useState("Tutti");
  const [den, setDen] = useState("Tutte");
  const [prod, setProd] = useState("Tutti");
  const [tip, setTip] = useState("Tutte");

  const filtered = useMemo(
    () =>
      communities.filter((c) => {
        if (
          q &&
          !c.nome.toLowerCase().includes(q.toLowerCase()) &&
          !c.descrizione.toLowerCase().includes(q.toLowerCase())
        )
          return false;
        if (terr !== "Tutti" && c.territorio !== terr) return false;
        if (den !== "Tutte" && c.denominazione !== den) return false;
        if (prod !== "Tutti" && c.produttore !== prod) return false;
        if (tip !== "Tutte" && c.tipologia !== tip) return false;
        return true;
      }),
    [q, terr, den, prod, tip],
  );

  const seguite = communities.filter((c) => communityFollows.has(c.slug));
  const consigliate = communities.filter((c) => !communityFollows.has(c.slug)).slice(0, 4);
  const popolari = [...discussions].sort((a, b) => b.mi_piace - a.mi_piace).slice(0, 4);

  return (
    <div className="space-y-10">
      <section className="relative overflow-hidden rounded-3xl bg-antracite text-crema hero-glow">
        <div
          className="absolute inset-0 opacity-40 animate-ken-burns"
          style={{
            backgroundImage: `url(${wineImages.glasses})`,
            backgroundSize: "cover",
            backgroundPosition: "center",
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-r from-antracite via-antracite/80 to-transparent" />
        <div className="hero-grain" aria-hidden />
        <div className="relative flex flex-col gap-4 p-6 md:flex-row md:items-end md:justify-between md:p-10">
          <div className="animate-fade-up">
            <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
            <h1 className="mt-1 font-serif text-3xl md:text-5xl">
              I <span className="gold-shimmer">Club</span> di Vinea
            </h1>
            <p className="mt-2 max-w-xl text-sm md:text-base text-crema/85">
              Trova la tua tribù di appassionati: territori, denominazioni, produttori e tipologie.
            </p>
          </div>
          <div
            className="relative w-full md:w-80 animate-fade-up"
            style={{ animationDelay: "120ms" }}
          >
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Cerca club…"
              className="pl-9 bg-card text-antracite"
            />
          </div>
        </div>
      </section>

      <section className="rounded-2xl border border-border bg-card p-4">
        <p className="mb-3 flex items-center gap-2 text-xs uppercase tracking-wide text-muted-foreground">
          Filtri
        </p>
        <div className="grid gap-3 md:grid-cols-4">
          <SelectRow label="Territorio" value={terr} onChange={setTerr} options={territori} />
          <SelectRow label="Denominazione" value={den} onChange={setDen} options={denominazioni} />
          <SelectRow label="Produttore" value={prod} onChange={setProd} options={produttori} />
          <SelectRow label="Tipologia" value={tip} onChange={setTip} options={tipologie} />
        </div>
      </section>

      {seguite.length > 0 && (
        <section>
          <SectionTitle>Club che segui</SectionTitle>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {seguite.map((c) => (
              <CommunityCard
                key={c.slug}
                c={c}
                followed
                onToggle={() => toggleCommunityFollow(c.slug)}
              />
            ))}
          </div>
        </section>
      )}

      <Tabs defaultValue="tutte">
        <TabsList className="bg-secondary">
          <TabsTrigger value="tutte">Tutti ({filtered.length})</TabsTrigger>
          <TabsTrigger value="consigliate">Consigliati</TabsTrigger>
          <TabsTrigger value="discussioni">Discussioni del club</TabsTrigger>
          <TabsTrigger value="popolari">Post popolari</TabsTrigger>
        </TabsList>

        <TabsContent value="tutte" className="mt-4">
          {filtered.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground">
              Nessun club con questi filtri.
            </div>
          ) : (
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
              {filtered.map((c) => (
                <CommunityCard
                  key={c.slug}
                  c={c}
                  followed={communityFollows.has(c.slug)}
                  onToggle={() => toggleCommunityFollow(c.slug)}
                />
              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="consigliate" className="mt-4">
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {consigliate.map((c) => (
              <CommunityCard
                key={c.slug}
                c={c}
                followed={false}
                onToggle={() => toggleCommunityFollow(c.slug)}
              />
            ))}
          </div>
        </TabsContent>

        <TabsContent value="discussioni" className="mt-4 space-y-3">
          {discussions.slice(0, 8).map((d) => (
            <DiscussionRow key={d.id} d={d} />
          ))}
        </TabsContent>

        <TabsContent value="popolari" className="mt-4 space-y-3">
          {popolari.map((d) => (
            <DiscussionRow key={d.id} d={d} />
          ))}
        </TabsContent>
      </Tabs>
    </div>
  );
}

function SelectRow({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: string[];
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-[11px] uppercase tracking-wide text-muted-foreground">
        {label}
      </span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
      >
        {options.map((o) => (
          <option key={o}>{o}</option>
        ))}
      </select>
    </label>
  );
}

function CommunityCard({
  c,
  followed,
  onToggle,
}: {
  c: (typeof communities)[number];
  followed: boolean;
  onToggle: () => void;
}) {
  return (
    <article className="group overflow-hidden rounded-2xl border border-border bg-card card-lift perf-card">
      <Link to="/community/$slug" params={{ slug: c.slug }} className="block">
        <div className="img-sheen relative aspect-[16/9] overflow-hidden">
          <img
            src={c.cover}
            alt=""
            loading="lazy"
            decoding="async"
            className="h-full w-full object-cover img-reveal group-hover:scale-110"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-antracite/75 via-antracite/25 to-transparent" />
          <span className="absolute left-3 top-3 rounded-full bg-crema/90 px-2 py-0.5 text-[10px] font-medium text-antracite">
            {c.categoria}
          </span>
        </div>
      </Link>
      <div className="p-4">
        <Link to="/community/$slug" params={{ slug: c.slug }}>
          <h3 className="font-serif text-lg font-semibold">{c.nome}</h3>
        </Link>
        <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{c.descrizione}</p>
        <div className="mt-3 flex items-center justify-between">
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <Users className="h-3.5 w-3.5" /> {c.membri.toLocaleString("it-IT")} •{" "}
            <TrendingUp className="h-3.5 w-3.5" /> {c.attivi} attivi
          </p>
          <Button
            size="sm"
            variant={followed ? "outline" : "default"}
            onClick={onToggle}
            className={followed ? "" : "bg-bordeaux hover:bg-bordeaux/90"}
          >
            {followed ? "Segui già" : "Segui club"}
          </Button>
        </div>
      </div>
    </article>
  );
}

function DiscussionRow({ d }: { d: (typeof discussions)[number] }) {
  const c = communities.find((x) => x.slug === d.communitySlug)!;
  return (
    <Link
      to="/community/$slug"
      params={{ slug: d.communitySlug }}
      className="flex gap-3 rounded-2xl border border-border bg-card p-4 hover:shadow-md"
    >
      <img src={d.avatar} alt="" className="h-10 w-10 shrink-0 rounded-full" />
      <div className="min-w-0 flex-1">
        <p className="text-[11px] uppercase tracking-wide text-salvia">
          {c.nome} • {d.tipo}
          {d.tipo === "annuncio" ? " marketplace" : ""}
        </p>
        <p className="font-serif text-base font-semibold">{d.titolo}</p>
        <p className="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{d.anteprima}</p>
        <p className="mt-1 text-xs text-muted-foreground">
          di {d.autore} • {d.tempo} • {d.risposte} risposte • ♥ {d.mi_piace}
        </p>
      </div>
    </Link>
  );
}
