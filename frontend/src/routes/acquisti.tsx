import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { ShoppingBag, ArrowRight, Filter } from "lucide-react";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { colorBuyerStatus, labelBuyerStatus, type BuyerOrderStatus } from "@/data/orders";
import { wines } from "@/data/wines";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/acquisti")({
  head: () => ({
    meta: [
      { title: "I miei acquisti — Vinea" },
      {
        name: "description",
        content: "Storico ordini di acquisto Vinea con stato, tracking e recensione.",
      },
      { property: "og:title", content: "I miei acquisti — Vinea Wine Club" },
      {
        property: "og:description",
        content: "Segui i tuoi ordini in ogni fase, dalla conferma al completamento.",
      },
    ],
  }),
  component: Acquisti,
});

const tabs: { v: "tutti" | BuyerOrderStatus; l: string }[] = [
  { v: "tutti", l: "Tutti" },
  { v: "in_attesa_pagamento", l: "In attesa" },
  { v: "pagato", l: "Pagati" },
  { v: "in_preparazione", l: "In preparazione" },
  { v: "spedito", l: "Spediti" },
  { v: "consegnato", l: "Consegnati" },
  { v: "completato", l: "Completati" },
  { v: "contestato", l: "Contestati" },
  { v: "rimborsato", l: "Rimborsati" },
];

function Acquisti() {
  const { orders } = useVinea();
  const [tab, setTab] = useState<(typeof tabs)[number]["v"]>("tutti");

  const filtered = useMemo(() => {
    if (tab === "tutti") return orders;
    return orders.filter((o) => o.buyerStatus === tab);
  }, [orders, tab]);

  return (
    <div className="space-y-6">
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-4 sm:flex sm:justify-between">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">I miei acquisti</h1>
          <p className="text-muted-foreground">{orders.length} ordini totali</p>
        </div>
        <Button asChild variant="outline">
          <Link to="/esplora">Cerca bottiglie</Link>
        </Button>
      </header>

      <Tabs value={tab} onValueChange={(v) => setTab(v as typeof tab)}>
        <div className="-mx-4 tab-scroll overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList className="inline-flex w-max min-w-full bg-secondary">
            {tabs.map((t) => (
              <TabsTrigger key={t.v} value={t.v}>
                {t.l}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>

        <TabsContent value={tab} className="mt-4">
          {filtered.length === 0 ? (
            <EmptyState />
          ) : (
            <ul className="space-y-2">
              {filtered.map((o) => {
                const wine = wines.find((w) => w.id === o.wineId);
                return (
                  <li key={o.id}>
                    <Link
                      to="/ordine/$id"
                      params={{ id: o.id }}
                      className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl border border-border bg-card p-3 transition hover:shadow-sm"
                    >
                      {wine && (
                        <img
                          src={wine.immagini[0]}
                          alt=""
                          className="h-16 w-12 shrink-0 rounded object-cover"
                        />
                      )}
                      <div className="min-w-0">
                        <p className="truncate font-serif font-semibold">
                          {wine ? `${wine.nome} ${wine.annata}` : o.wineId}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                          {o.id} · da {o.seller.nome} ·{" "}
                          {new Date(o.createdAt).toLocaleDateString("it-IT")}
                        </p>
                        <p className="text-xs text-bordeaux">{formatEUR(o.totale)}</p>
                      </div>
                      <div className="flex flex-col items-end gap-1">
                        <span
                          className={`whitespace-nowrap rounded-full px-2 py-0.5 text-[10px] font-semibold ${colorBuyerStatus(o.buyerStatus)}`}
                        >
                          {labelBuyerStatus(o.buyerStatus)}
                        </span>
                        <ArrowRight className="h-4 w-4 text-muted-foreground" />
                      </div>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
      <ShoppingBag className="mx-auto h-8 w-8 text-muted-foreground" />
      <p className="mt-2 font-serif text-xl">Nessun ordine in questa categoria</p>
      <p className="mt-1 text-sm text-muted-foreground">
        Trova la tua prossima bottiglia nella Ricerca.
      </p>
      <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
        <Link to="/esplora">Vai alla Ricerca</Link>
      </Button>
    </div>
  );
}
