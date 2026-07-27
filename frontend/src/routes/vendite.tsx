import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Store, ArrowRight } from "lucide-react";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { labelSellerStatus, type SellerOrderStatus } from "@/data/orders";
import { wines } from "@/data/wines";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/vendite")({
  head: () => ({
    meta: [
      { title: "Le mie vendite — Vinea" },
      {
        name: "description",
        content: "Ordini ricevuti come venditore: nuovi, da preparare, da spedire, completati.",
      },
      { property: "og:title", content: "Le mie vendite — Vinea Wine Club" },
      {
        property: "og:description",
        content: "Gestisci preparazione, spedizione e contestazioni degli ordini in vendita.",
      },
    ],
  }),
  component: Vendite,
});

const tabs: { v: "tutti" | SellerOrderStatus; l: string }[] = [
  { v: "tutti", l: "Tutti" },
  { v: "nuovo", l: "Nuovi" },
  { v: "da_preparare", l: "Da preparare" },
  { v: "da_spedire", l: "Da spedire" },
  { v: "spedito", l: "Spediti" },
  { v: "consegnato", l: "Consegnati" },
  { v: "completato", l: "Completati" },
  { v: "contestato", l: "Contestati" },
];

function badgeColor(s: SellerOrderStatus): string {
  switch (s) {
    case "nuovo":
      return "bg-oro/20 text-oro";
    case "da_preparare":
    case "da_spedire":
      return "bg-secondary text-antracite";
    case "spedito":
      return "bg-blue-500/10 text-blue-700";
    case "consegnato":
      return "bg-salvia/15 text-salvia";
    case "completato":
      return "bg-bordeaux/10 text-bordeaux";
    case "contestato":
      return "bg-red-500/10 text-red-700";
    case "rimborsato":
      return "bg-oro/20 text-oro";
    case "annullato":
      return "bg-muted text-muted-foreground";
  }
}

function Vendite() {
  const { sales } = useVinea();
  const [tab, setTab] = useState<(typeof tabs)[number]["v"]>("tutti");

  const filtered = useMemo(
    () => (tab === "tutti" ? sales : sales.filter((o) => o.sellerStatus === tab)),
    [sales, tab],
  );

  return (
    <div className="space-y-6">
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-4 sm:flex sm:justify-between">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">Le mie vendite</h1>
          <p className="text-muted-foreground">{sales.length} ordini ricevuti</p>
        </div>
        <Button asChild variant="outline">
          <Link to="/vendi">Nuovo annuncio</Link>
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
            <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
              <Store className="mx-auto h-8 w-8 text-muted-foreground" />
              <p className="mt-2 font-serif text-xl">Nessuna vendita in questa categoria</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Metti in vendita una bottiglia dalla tua cantina.
              </p>
              <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
                <Link to="/vendi">Vendi ora</Link>
              </Button>
            </div>
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
                          {o.id} · a {o.buyer.nome} ·{" "}
                          {new Date(o.createdAt).toLocaleDateString("it-IT")}
                        </p>
                        <p className="text-xs text-bordeaux">{formatEUR(o.totale)}</p>
                      </div>
                      <div className="flex flex-col items-end gap-1">
                        <span
                          className={`whitespace-nowrap rounded-full px-2 py-0.5 text-[10px] font-semibold ${badgeColor(o.sellerStatus)}`}
                        >
                          {labelSellerStatus(o.sellerStatus)}
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
