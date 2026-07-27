"use client";

import Link from "next/link";
import { notFound } from "next/navigation";
import { useMemo, useState } from "react";
import {
  Users,
  ShieldCheck,
  MessageSquare,
  ArrowLeft,
  Wine as WineIcon,
  Megaphone,
} from "lucide-react";
import { communities, communityMembriMock, discussions, type PostTipo } from "@/data/communities";
import { wines } from "@/data/wines";
import { Button } from "@/components/ui/button";
import { WineCard } from "@/components/vinea/WineCard";
import { useVinea } from "@/lib/vinea-store";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { toast } from "sonner";
import { formatInteger } from "@/lib/format";

const tipoLabel: Record<PostTipo, string> = {
  discussione: "Discussione",
  domanda: "Domanda",
  degustazione: "Nota di degustazione",
  confronto: "Confronto",
  consiglio: "Consiglio",
  sondaggio: "Sondaggio",
  annuncio: "Annuncio marketplace",
};

export default function CommunityDetailPageClient({ slug }: { slug: string }) {
  const c = communities.find((x) => x.slug === slug);
  if (!c) notFound();

  const { communityFollows, toggleCommunityFollow } = useVinea();
  const followed = communityFollows.has(c.slug);
  const membri = useMemo(() => communityMembriMock(c.slug), [c.slug]);
  const posts = discussions.filter((d) => d.communitySlug === c.slug);
  const linked = wines.filter((w) => c.wineIds.includes(w.id));
  const [filter, setFilter] = useState<"tutti" | PostTipo>("tutti");
  const visibili = filter === "tutti" ? posts : posts.filter((p) => p.tipo === filter);

  return (
    <div className="space-y-8">
      <Link
        href="/community"
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Scopri altri club
      </Link>

      <section className="relative overflow-hidden rounded-3xl">
        <img src={c.cover} alt="" className="absolute inset-0 h-full w-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-t from-antracite/85 via-antracite/40 to-antracite/20" />
        <div className="relative flex flex-col gap-4 p-6 text-crema md:p-10">
          <span className="w-fit rounded-full bg-crema/20 px-3 py-1 text-xs">
            Club • {c.categoria}
          </span>
          <h1 className="font-serif text-3xl md:text-5xl">{c.nome}</h1>
          <p className="max-w-2xl text-crema/85">{c.descrizione}</p>
          <div className="flex flex-wrap items-center gap-4 text-sm">
            <span className="flex items-center gap-1">
              <Users className="h-4 w-4" /> {formatInteger(c.membri)} membri
            </span>
            <span>•</span>
            <span>{c.attivi} attivi oggi</span>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              onClick={() => toggleCommunityFollow(c.slug)}
              className={
                followed
                  ? "bg-crema text-antracite hover:bg-crema/90"
                  : "bg-oro text-antracite hover:bg-oro/90"
              }
            >
              {followed ? "Segui già" : "Segui club"}
            </Button>
            <Button
              variant="outline"
              className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
              onClick={() => toast("Editor post del club (demo)")}
            >
              <MessageSquare className="h-4 w-4" /> Crea un post
            </Button>
            <Button
              asChild
              variant="outline"
              className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
            >
              <Link href="/community">Scopri altri club</Link>
            </Button>
          </div>
        </div>
      </section>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <div className="flex flex-wrap gap-2">
            <Chip active={filter === "tutti"} onClick={() => setFilter("tutti")}>
              Tutti
            </Chip>
            {(Object.keys(tipoLabel) as PostTipo[]).map((t) => (
              <Chip key={t} active={filter === t} onClick={() => setFilter(t)}>
                {tipoLabel[t]}
              </Chip>
            ))}
          </div>

          {visibili.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground">
              Nessun post di questo tipo, per ora.
            </div>
          ) : (
            <ul className="space-y-3">
              {visibili.map((d) => {
                const wine = d.wineId ? wines.find((w) => w.id === d.wineId) : undefined;
                return (
                  <li key={d.id} className="rounded-2xl border border-border bg-card p-4">
                    <div className="flex items-center gap-3">
                      <img src={d.avatar} alt="" className="h-9 w-9 rounded-full" />
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold">
                          {d.autore}{" "}
                          <span className="font-normal text-muted-foreground">• {d.tempo}</span>
                        </p>
                        <p className="text-[11px] uppercase tracking-wide text-salvia">
                          {tipoLabel[d.tipo]}
                          {d.tipo === "annuncio" && (
                            <span className="ml-1 rounded-full bg-oro/25 px-1.5 py-0.5 text-[10px] text-antracite">
                              Annuncio marketplace
                            </span>
                          )}
                        </p>
                      </div>
                    </div>
                    <p className="mt-3 font-serif text-lg font-semibold">{d.titolo}</p>
                    <p className="mt-1 text-sm text-muted-foreground">{d.anteprima}</p>
                    {wine && (
                      <Link
                        href={`/annuncio/${wine.id}`}
                        className="mt-3 flex items-center gap-3 rounded-xl border border-border p-3 hover:bg-secondary"
                      >
                        <img
                          src={wine.immagini[0]}
                          alt=""
                          className="h-14 w-10 rounded object-cover"
                        />
                        <div className="min-w-0 flex-1">
                          <p className="text-[11px] uppercase text-salvia">Bottiglia collegata</p>
                          <p className="truncate font-serif font-semibold">
                            {wine.nome} {wine.annata}
                          </p>
                        </div>
                        <Megaphone className="h-4 w-4 text-bordeaux" />
                      </Link>
                    )}
                    <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                      <p className="text-xs text-muted-foreground">
                        {d.risposte} risposte • ♥ {d.mi_piace}
                      </p>
                      <ReportDialog
                        targetType="post"
                        targetId={d.id}
                        targetLabel={`${d.titolo} — ${d.autore}`}
                        clubSlug={c.slug}
                        variant="icon"
                      />
                    </div>
                  </li>
                );
              })}
            </ul>
          )}

          {linked.length > 0 && (
            <section>
              <h3 className="mb-3 flex items-center gap-2 font-serif text-xl">
                <WineIcon className="h-5 w-5 text-bordeaux" /> Bottiglie collegate
              </h3>
              <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
                {linked.map((w) => (
                  <WineCard key={w.id} wine={w} />
                ))}
              </div>
            </section>
          )}
        </div>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-border bg-card p-4">
            <p className="font-serif text-lg font-semibold">Moderatori</p>
            <ul className="mt-3 space-y-2">
              {c.moderatori.map((m: { nome: string; avatar: string }) => (
                <li key={m.nome} className="flex items-center gap-2 text-sm">
                  <img src={m.avatar} alt="" className="h-8 w-8 rounded-full" />
                  <span className="flex-1">{m.nome}</span>
                  <ShieldCheck className="h-4 w-4 text-salvia" />
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-2xl border border-border bg-card p-4">
            <p className="font-serif text-lg font-semibold">Regole</p>
            <ol className="mt-2 list-decimal space-y-1 pl-4 text-sm">
              {c.regole.map((r: string) => (
                <li key={r}>{r}</li>
              ))}
            </ol>
          </div>

          <div className="rounded-2xl border border-border bg-card p-4">
            <p className="font-serif text-lg font-semibold">Utenti attivi</p>
            <div className="mt-3 flex flex-wrap gap-2">
              {membri.map((m: { nome: string; avatar: string }) => (
                <div
                  key={m.nome}
                  className="flex items-center gap-1.5 rounded-full bg-secondary px-2 py-1 text-xs"
                >
                  <img src={m.avatar} alt="" className="h-5 w-5 rounded-full" />
                  {m.nome}
                </div>
              ))}
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}

function Chip({
  children,
  active,
  onClick,
}: {
  children: React.ReactNode;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`rounded-full border px-3 py-1 text-xs font-medium transition ${active ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card hover:bg-secondary"}`}
    >
      {children}
    </button>
  );
}
