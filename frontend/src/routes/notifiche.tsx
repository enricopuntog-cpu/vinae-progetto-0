import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { useVinea } from "@/lib/vinea-store";

export const Route = createFileRoute("/notifiche")({
  head: () => ({
    meta: [
      { title: "Notifiche — Vinea" },
      { name: "description", content: "Tutte le tue notifiche marketplace, community e sistema." },
      { property: "og:title", content: "Notifiche — Vinea" },
      { property: "og:description", content: "Novità su annunci, community e sistema Vinea." },
    ],
  }),
  component: Notifiche,
});

const tabs = [
  { v: "tutte", l: "Tutte" },
  { v: "marketplace", l: "Marketplace" },
  { v: "community", l: "Club" },
  { v: "sistema", l: "Sistema" },
] as const;

function Notifiche() {
  const { notifiche, segnaLetta, segnaTutteLette, nonLette } = useVinea();
  const [tab, setTab] = useState<(typeof tabs)[number]["v"]>("tutte");
  const visibili = useMemo(
    () => (tab === "tutte" ? notifiche : notifiche.filter((n) => n.categoria === tab)),
    [tab, notifiche],
  );

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-4">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">Notifiche</h1>
          <p className="text-muted-foreground">{nonLette} non lette</p>
        </div>
        <Button variant="outline" onClick={segnaTutteLette} disabled={nonLette === 0}>
          Segna tutte come lette
        </Button>
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as typeof tab)}>
        <TabsList className="bg-secondary">
          {tabs.map((t) => (
            <TabsTrigger key={t.v} value={t.v}>
              {t.l}
            </TabsTrigger>
          ))}
        </TabsList>
        <TabsContent value={tab} className="mt-4 space-y-2">
          {visibili.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-muted-foreground">
              Nessuna notifica in questa categoria.
            </div>
          ) : (
            visibili.map((n) => (
              <button
                key={n.id}
                onClick={() => segnaLetta(n.id)}
                className={`flex w-full items-start gap-3 rounded-2xl border border-border p-4 text-left transition hover:shadow-sm ${!n.letta ? "bg-crema" : "bg-card"}`}
              >
                {!n.letta ? (
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-bordeaux" />
                ) : (
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-border" />
                )}
                <div className="min-w-0 flex-1">
                  <p className="text-sm">{n.testo}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {n.tempo} • {n.categoria}
                  </p>
                </div>
                {!n.letta && (
                  <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-[10px] font-medium text-bordeaux">
                    Nuova
                  </span>
                )}
              </button>
            ))
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}
