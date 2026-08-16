"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  ArrowLeft,
  MapPin,
  ShieldCheck,
  Star,
  Truck,
  // Alias per non collidere con il tipo di dominio Wine, come già in
  // app/home/page-client.tsx.
  Wine as WineIcon,
  ThermometerSun,
  WineOff,
  Flag,
  type LucideIcon,
} from "lucide-react";
import type { Wine } from "@/data/wines";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { DrinkWindowSection } from "@/components/vinea/DrinkWindow";
import { FoodPairingSection } from "@/components/vinea/FoodPairing";
import { TrustBadge, TrustLegend } from "@/components/vinea/TrustBadge";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { ListingContactActions } from "@/components/vinea/ListingContactActions";
import { ProposalAction } from "@/components/vinea/ProposalAction";
import { PAGAMENTI_UI_ABILITATI } from "@/config/features";

export default function AnnuncioDetailPageClient({
  wine,
  correlati,
}: {
  wine: Wine;
  correlati: Wine[];
}) {
  const router = useRouter();
  const [attiva, setAttiva] = useState(0);
  const listingId = wine.listingId ?? wine.id;

  return (
    <div className="space-y-8">
      <button
        onClick={() => router.back()}
        className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-bordeaux"
      >
        <ArrowLeft className="h-4 w-4" /> Indietro
      </button>

      <div className="grid gap-8 md:grid-cols-2">
        {/* Gallery */}
        <div>
          <div className="aspect-[4/5] overflow-hidden rounded-2xl bg-secondary">
            <img
              src={wine.immagini[attiva]}
              alt={wine.nome}
              className="h-full w-full object-cover"
            />
          </div>
          <div className="mt-3 flex gap-2">
            {wine.immagini.map((src: string, i: number) => (
              <button
                key={i}
                onClick={() => setAttiva(i)}
                className={`h-16 w-16 overflow-hidden rounded-lg border-2 ${attiva === i ? "border-bordeaux" : "border-transparent"}`}
              >
                <img src={src} alt="" className="h-full w-full object-cover" />
              </button>
            ))}
          </div>
        </div>

        {/* Info */}
        <div>
          <p className="text-xs uppercase tracking-widest text-salvia">{wine.denominazione}</p>
          <h1 className="mt-1 font-serif text-4xl leading-tight">
            {wine.nome} <span className="text-antracite/70">{wine.annata}</span>
          </h1>
          <p className="mt-1 text-lg text-muted-foreground">{wine.produttore}</p>

          {/* Trust badges: chi ha attestato cosa */}
          <div className="mt-3 flex flex-wrap gap-1.5">
            {wine.venditore.verificato && <TrustBadge source="piattaforma" size="sm" />}
            <TrustBadge source="venditore" size="sm" />
          </div>

          <div className="mt-4 flex items-baseline gap-3">
            <p className="font-serif text-4xl font-semibold text-bordeaux">
              {formatEUR(wine.prezzo)}
            </p>
            {wine.prezzoMercato && wine.prezzoMercato > wine.prezzo && (
              <p className="text-sm text-muted-foreground line-through">
                {formatEUR(wine.prezzoMercato)}
              </p>
            )}
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {wine.disponibili} {wine.disponibili === 1 ? "bottiglia disponibile" : "bottiglie disponibili"} • Formato {wine.formato}
          </p>

          <div className={`mt-6 grid gap-2 ${PAGAMENTI_UI_ABILITATI ? "grid-cols-3" : "grid-cols-1"}`}>
            {PAGAMENTI_UI_ABILITATI ? (
              <Button
                className="col-span-2 bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => router.push(`/checkout/${wine.id}`)}
              >
                Compra ora
              </Button>
            ) : null}
            <ProposalAction listingId={listingId} listingSlug={wine.id} prezzo={wine.prezzo} />
          </div>

          <ListingContactActions listingId={listingId} />
          <div className="mt-2">
            <ReportDialog
              targetType="annuncio"
              targetId={listingId}
              targetLabel={`${wine.nome} ${wine.annata} — ${wine.venditore.nome}`}
              trigger={
                <Button variant="ghost" className="text-muted-foreground hover:text-bordeaux">
                  <Flag className="h-4 w-4" /> Segnala annuncio
                </Button>
              }
            />
          </div>

          {/* Venditore */}
          <div className="mt-6 rounded-2xl border border-border bg-card p-4">
            <div className="flex items-center gap-3">
              <img
                src={wine.venditore.avatar}
                alt=""
                className="h-12 w-12 rounded-full object-cover"
              />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1 font-semibold">
                  {wine.venditore.nome}
                  {wine.venditore.verificato && <ShieldCheck className="h-4 w-4 text-salvia" />}
                </p>
                <p className="flex items-center gap-1 text-xs text-muted-foreground">
                  <MapPin className="h-3 w-3" /> {wine.venditore.citta}
                  {wine.venditore.valutazioni > 0 ? (
                    <>
                      {" • "}
                      <Star className="h-3 w-3 fill-oro text-oro" /> {wine.venditore.rating} (
                      {wine.venditore.valutazioni})
                    </>
                  ) : null}
                </p>
              </div>
            </div>
          </div>

          <div className="mt-4">
            <TrustLegend />
          </div>

          <MyBottleActions wineId={wine.wineSlug ?? wine.id} />
        </div>
      </div>

      {/* Quando berlo + abbinamenti. Indicizzati per vino, non per annuncio:
          su dati reali `id` è lo slug dell'annuncio e non troverebbe nulla. */}
      <div className="grid gap-6 lg:grid-cols-2">
        <DrinkWindowSection wineId={wine.wineSlug ?? wine.id} />
        <FoodPairingSection wineId={wine.wineSlug ?? wine.id} />
      </div>

      {/* Servizio, storia, degustazione */}
      <Tabs defaultValue="storia" className="mt-4">
        <TabsList className="bg-secondary">
          <TabsTrigger value="storia">Storia</TabsTrigger>
          <TabsTrigger value="degustazione">Degustazione</TabsTrigger>
          <TabsTrigger value="dettagli">Servizio e dettagli</TabsTrigger>
        </TabsList>
        <TabsContent value="storia" className="mt-4 rounded-2xl border border-border bg-card p-6">
          <p className="text-base leading-relaxed">{wine.storia}</p>
        </TabsContent>
        <TabsContent
          value="degustazione"
          className="mt-4 rounded-2xl border border-border bg-card p-6"
        >
          <p className="text-base leading-relaxed">{wine.degustazione}</p>
        </TabsContent>
        <TabsContent
          value="dettagli"
          className="mt-4 grid gap-3 rounded-2xl border border-border bg-card p-6 md:grid-cols-2"
        >
          <Info icon={WineIcon} label="Tipologia" value={wine.tipo} />
          <Info icon={MapPin} label="Regione" value={wine.regione} />
          <Info icon={ThermometerSun} label="Conservazione" value={wine.conservazione} />
          <Info icon={Truck} label="Condizione" value={wine.condizione} />
        </TabsContent>
      </Tabs>

      {/* Suggeriti */}
      {correlati.length > 0 && (
        <section>
          <h2 className="mb-4 font-serif text-2xl">Potrebbero interessarti</h2>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            {correlati.map((w) => (
              <Link
                key={w.id}
                href={`/annuncio/${w.id}`}
                className="group overflow-hidden rounded-xl border border-border bg-card"
              >
                <img
                  src={w.immagini[0]}
                  alt=""
                  className="aspect-square w-full object-cover transition group-hover:scale-105"
                />
                <div className="p-3">
                  <p className="truncate font-serif text-sm font-semibold">
                    {w.nome} {w.annata}
                  </p>
                  <p className="text-sm font-semibold text-bordeaux">{formatEUR(w.prezzo)}</p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function Info({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-salvia/15 text-salvia">
        <Icon className="h-4 w-4" />
      </span>
      <div>
        <p className="text-xs uppercase text-muted-foreground">{label}</p>
        <p className="text-sm">{value}</p>
      </div>
    </div>
  );
}

/**
 * Il pannello "Nella tua cantina", ora su bottiglie reali (Fase 6c-2).
 *
 * DUE CAMBIAMENTI VISIBILI, entrambi conseguenza dei dati veri e non di una
 * scelta di design:
 *
 * - Prima compariva a chiunque, anche a chi non aveva mai fatto accesso: le
 *   bottiglie erano un elenco costante uguale per tutti. Ora compare solo a chi
 *   possiede davvero quella bottiglia.
 * - Il conteggio non è più la `quantita` di una pila ma il numero delle proprie
 *   unità ancora chiuse di quel vino. Stessa domanda, stessa risposta: nel mock
 *   una riga rappresentava N bottiglie, qui N righe rappresentano N bottiglie.
 *
 * L'apertura agisce sulla prima unità ancora chiusa, che è l'equivalente esatto
 * del decremento di una pila.
 */
function MyBottleActions({ wineId }: { wineId: string }) {
  const { bottiglieCantina, openBottle, scheduleOpen } = useVinea();
  const mie = bottiglieCantina.filter((b) => b.wineVintageId === wineId);
  const [when, setWhen] = useState("");
  const [nota, setNota] = useState("");
  if (mie.length === 0) return null;

  const chiuse = mie.filter((b) => b.quantita > 0);
  // Quella su cui agiscono i comandi: la prima ancora chiusa, o comunque una.
  const bottle = chiuse[0] ?? mie[0];
  const disponibili = chiuse.length;
  const pianificata = mie.find((b) => b.plannedOpenDate)?.plannedOpenDate;

  return (
    <div className="mt-4 rounded-2xl border border-oro/40 bg-oro/10 p-4">
      <p className="text-xs uppercase tracking-wide text-oro">Nella tua cantina</p>
      <p className="mt-1 text-sm">
        {disponibili} {disponibili === 1 ? "bottiglia" : "bottiglie"} disponibili
        {pianificata ? ` · apertura pianificata ${pianificata}` : ""}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <Dialog>
          <DialogTrigger asChild>
            <Button
              size="sm"
              className="bg-bordeaux hover:bg-bordeaux/90"
              disabled={disponibili === 0}
            >
              <WineOff className="h-4 w-4" /> Apri questa bottiglia
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="font-serif text-xl">Registra apertura</DialogTitle>
            </DialogHeader>
            <p className="text-sm text-muted-foreground">
              Aggiorneremo la quantità nella tua cantina.
            </p>
            <Textarea
              placeholder="Nota di degustazione (facoltativa)"
              value={nota}
              onChange={(e) => setNota(e.target.value)}
            />
            <DialogFooter>
              <Button
                className="bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => openBottle(bottle.bottleId, nota)}
              >
                Conferma apertura
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <Dialog>
          <DialogTrigger asChild>
            <Button size="sm" variant="outline">
              Programma apertura
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="font-serif text-xl">Programma apertura</DialogTitle>
            </DialogHeader>
            <Input type="date" value={when} onChange={(e) => setWhen(e.target.value)} />
            <DialogFooter>
              <Button
                disabled={!when}
                className="bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => scheduleOpen(bottle.bottleId, when)}
              >
                Salva
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <Button asChild size="sm" variant="ghost">
          <Link href="/cantina">Sposta nella cantina</Link>
        </Button>
      </div>
    </div>
  );
}
