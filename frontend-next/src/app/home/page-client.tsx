"use client";

import Link from "next/link";
import {
  Search,
  PlusCircle,
  TrendingDown,
  Bell,
  Users,
  Wine as WineIcon,
  Sparkles,
} from "lucide-react";
import { wines, type Wine } from "@/data/wines";
import { communities, discussions } from "@/data/communities";
import { WineCard } from "@/components/vinea/WineCard";
import { SectionTitle, Kpi } from "@/components/vinea/Layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { formatInteger } from "@/lib/format";

/**
 * Pagina a due sorgenti, e la divisione non è arbitraria.
 *
 * Consigliati, novità dai venditori seguiti e ribassi sono marketplace:
 * arrivano da `annunci`, cioè da Supabase (Fase 6a). Valore della cantina e
 * sezione "La tua cantina" restano sui dati mock perché la Cantina non è
 * ancora un dominio migrato — vedi "Fase 6c" in docs/ROADMAP_V1.md. Preferiti,
 * seguiti, notifiche e club restano nello store mock per lo stesso motivo.
 */
export default function HomeUtentePageClient({ annunci }: { annunci: Wine[] }) {
  const { favorites, follows, notifiche, nonLette, communityFollows } = useVinea();
  const consigliati = annunci.slice(0, 4);
  const nuoviSeguiti = annunci.filter((w) => follows.has(w.venditore.nome)).slice(0, 3);
  const ribassi = annunci
    .filter((w) => favorites.has(w.id) && w.prezzoMercato && w.prezzoMercato > w.prezzo)
    .slice(0, 3);
  const attivita = discussions.slice(0, 4);
  // Cantina: ancora mock.
  const cantinaValore = wines.slice(0, 6).reduce((s, w) => s + w.prezzo, 0);
  const myCommunities = communities.filter((c) => communityFollows.has(c.slug));

  return (
    <div className="space-y-10">
      <section className="rounded-3xl bg-gradient-to-br from-bordeaux via-bordeaux to-antracite p-6 text-crema md:p-10">
        <div className="grid gap-6 md:grid-cols-[1fr_auto] md:items-end">
          <div>
            <p className="text-sm text-crema/70">Bentornata,</p>
            <h1 className="font-serif text-3xl md:text-5xl">Elena Rossi</h1>
            <p className="mt-2 text-crema/85 max-w-xl">
              Oggi ci sono {nonLette} novità per te, {ribassi.length} ribassi sui tuoi preferiti e{" "}
              {nuoviSeguiti.length} nuovi annunci dai produttori che segui.
            </p>
            <div className="relative mt-5 max-w-md">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-antracite/60" />
              <Input
                placeholder="Cerca annata, produttore, denominazione…"
                className="bg-crema pl-9 text-antracite placeholder:text-antracite/50"
              />
            </div>
          </div>
          <div className="flex flex-wrap gap-3">
            <Button asChild size="lg" className="bg-oro text-antracite hover:bg-oro/90">
              <Link href="/vendi">
                <PlusCircle className="h-4 w-4" /> Aggiungi bottiglia
              </Link>
            </Button>
            <Button
              asChild
              size="lg"
              variant="outline"
              className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
            >
              <Link href="/cantina">Apri cantina</Link>
            </Button>
          </div>
        </div>
      </section>

      <section className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="Preferiti" value={String(favorites.size)} />
        <Kpi label="Cantina" value={formatEUR(cantinaValore)} hint="Valore stimato" />
        <Kpi label="Club" value={String(communityFollows.size)} hint="che segui" />
        <Kpi label="Notifiche" value={String(nonLette)} hint="non lette" />
      </section>

      <section>
        <SectionTitle
          action={
            <Link href="/esplora" className="text-sm font-medium text-bordeaux hover:underline">
              Vedi tutto →
            </Link>
          }
        >
          <span className="inline-flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-oro" /> Consigliati per te
          </span>
        </SectionTitle>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          {consigliati.map((w) => (
            <WineCard key={w.id} wine={w} />
          ))}
        </div>
      </section>

      <section>
        <SectionTitle
          action={
            <Link href="/profilo" className="text-sm font-medium text-bordeaux hover:underline">
              Gestisci seguiti →
            </Link>
          }
        >
          Nuovi annunci dai produttori che segui
        </SectionTitle>
        {nuoviSeguiti.length === 0 ? (
          <EmptyBox testo="Segui i tuoi produttori preferiti per ricevere aggiornamenti qui." />
        ) : (
          <div className="grid gap-3 md:grid-cols-3">
            {nuoviSeguiti.map((w) => (
              <WineCard key={w.id} wine={w} variant="list" />
            ))}
          </div>
        )}
      </section>

      <section>
        <SectionTitle>
          <span className="inline-flex items-center gap-2">
            <TrendingDown className="h-5 w-5 text-salvia" /> Ribassi sui preferiti
          </span>
        </SectionTitle>
        {ribassi.length === 0 ? (
          <EmptyBox testo="Nessun ribasso sulle bottiglie che hai salvato. Ti avviseremo appena il prezzo scende." />
        ) : (
          <div className="grid gap-3 md:grid-cols-3">
            {ribassi.map((w) => (
              <Link
                key={w.id}
                href={`/annuncio/${w.id}`}
                className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3 hover:shadow-md"
              >
                <img src={w.immagini[0]} alt="" className="h-20 w-16 rounded-lg object-cover" />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-serif text-sm font-semibold">
                    {w.nome} {w.annata}
                  </p>
                  <p className="text-xs text-muted-foreground">{w.produttore}</p>
                  <p className="mt-1">
                    <span className="font-serif text-lg font-semibold text-bordeaux">
                      {formatEUR(w.prezzo)}
                    </span>{" "}
                    <span className="text-xs text-muted-foreground line-through">
                      {formatEUR(w.prezzoMercato!)}
                    </span>
                  </p>
                </div>
              </Link>
            ))}
          </div>
        )}
      </section>

      <section className="grid gap-6 md:grid-cols-2">
        <div>
          <SectionTitle
            action={
              <Link href="/community" className="text-sm font-medium text-bordeaux hover:underline">
                Vai →
              </Link>
            }
          >
            <span className="inline-flex items-center gap-2">
              <Users className="h-5 w-5" /> Attività del club
            </span>
          </SectionTitle>
          <ul className="space-y-3">
            {attivita.map((d) => {
              const c = communities.find((x) => x.slug === d.communitySlug)!;
              return (
                <li key={d.id}>
                  <Link
                    href={`/community/${d.communitySlug}`}
                    className="block rounded-2xl border border-border bg-card p-4 hover:shadow-md"
                  >
                    <p className="text-[11px] uppercase tracking-wide text-salvia">
                      {c.nome} • {d.tipo}
                    </p>
                    <p className="mt-1 font-serif text-base font-semibold">{d.titolo}</p>
                    <p className="mt-1 line-clamp-1 text-xs text-muted-foreground">{d.anteprima}</p>
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>

        <div>
          <SectionTitle
            action={
              <Link href="/notifiche" className="text-sm font-medium text-bordeaux hover:underline">
                Tutte →
              </Link>
            }
          >
            <span className="inline-flex items-center gap-2">
              <Bell className="h-5 w-5" /> Notifiche rilevanti
            </span>
          </SectionTitle>
          <ul className="space-y-2">
            {notifiche.slice(0, 5).map((n) => (
              <li
                key={n.id}
                className={`rounded-2xl border border-border p-3 ${!n.letta ? "bg-crema" : "bg-card"}`}
              >
                <div className="flex items-start gap-2">
                  {!n.letta && (
                    <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-bordeaux" />
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="text-sm">{n.testo}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {n.tempo} • {n.categoria}
                    </p>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section>
        <SectionTitle
          action={
            <Link href="/cantina" className="text-sm font-medium text-bordeaux hover:underline">
              Apri cantina →
            </Link>
          }
        >
          <span className="inline-flex items-center gap-2">
            <WineIcon className="h-5 w-5" /> La tua cantina
          </span>
        </SectionTitle>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          {wines.slice(0, 4).map((w) => (
            <WineCard key={w.id} wine={w} showSaleBadge />
          ))}
        </div>
      </section>

      {myCommunities.length > 0 && (
        <section>
          <SectionTitle>I tuoi club</SectionTitle>
          <div className="grid gap-3 md:grid-cols-3">
            {myCommunities.map((c) => (
              <Link
                key={c.slug}
                href={`/community/${c.slug}`}
                className="group relative aspect-[16/9] overflow-hidden rounded-2xl"
              >
                <img
                  src={c.cover}
                  alt=""
                  className="h-full w-full object-cover transition group-hover:scale-105"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-antracite/80 to-transparent" />
                <div className="absolute bottom-3 left-3 right-3 text-crema">
                  <p className="font-serif text-lg font-semibold">{c.nome}</p>
                  <p className="text-xs opacity-80">{formatInteger(c.membri)} membri</p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function EmptyBox({ testo }: { testo: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center text-sm text-muted-foreground">
      {testo}
    </div>
  );
}
