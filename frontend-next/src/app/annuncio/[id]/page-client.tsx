"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import {
  ArrowLeft,
  Heart,
  MapPin,
  ShieldCheck,
  Star,
  MessageCircle,
  Share2,
  Truck,
  // Alias per non collidere con il tipo di dominio Wine, come già in
  // app/home/page-client.tsx.
  Wine as WineIcon,
  ThermometerSun,
  WineOff,
  Clock,
  Camera,
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
import { toast } from "sonner";
import { DrinkWindowSection } from "@/components/vinea/DrinkWindow";
import { FoodPairingSection } from "@/components/vinea/FoodPairing";
import { TrustBadge, TrustLegend } from "@/components/vinea/TrustBadge";
import { ReportDialog } from "@/components/vinea/ReportDialog";
import { listingStatusLabel, listingStatusTone } from "@/data/moderation";

export default function AnnuncioDetailPageClient({
  wine,
  correlati,
}: {
  wine: Wine;
  correlati: Wine[];
}) {
  const router = useRouter();
  const {
    favorites,
    toggleFavorite,
    follows,
    toggleFollow,
    createProposal,
    proposals,
    listingStatus,
    richiediAltreFoto,
  } = useVinea();
  const [attiva, setAttiva] = useState(0);
  const [prezzoProposto, setPrezzoProposto] = useState(String(Math.round(wine.prezzo * 0.9)));
  const [openProp, setOpenProp] = useState(false);
  const fav = favorites.has(wine.id);
  const seguito = follows.has(wine.venditore.nome);
  const propostaAttiva = useMemo(
    () =>
      proposals.find(
        (p) => p.wineId === wine.id && ["inviata", "controproposta", "accettata"].includes(p.stato),
      ),
    [proposals, wine.id],
  );
  const stato = listingStatus[wine.id] ?? "attivo";
  const azioniBloccate =
    stato === "sospeso" || stato === "rifiutato" || stato === "venduto" || stato === "scaduto";

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
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-xs uppercase tracking-widest text-salvia">{wine.denominazione}</p>
            <span
              className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${listingStatusTone[stato]}`}
            >
              {listingStatusLabel[stato]}
            </span>
          </div>
          <h1 className="mt-1 font-serif text-4xl leading-tight">
            {wine.nome} <span className="text-antracite/70">{wine.annata}</span>
          </h1>
          <p className="mt-1 text-lg text-muted-foreground">{wine.produttore}</p>

          {/* Trust badges: chi ha attestato cosa */}
          <div className="mt-3 flex flex-wrap gap-1.5">
            {wine.venditore.verificato && <TrustBadge source="piattaforma" size="sm" />}
            <TrustBadge source="venditore" size="sm" />
            <TrustBadge source="ia" size="sm" />
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
            {wine.disponibili} bottiglie disponibili • Formato {wine.formato}
          </p>

          {azioniBloccate && (
            <div className="mt-3 rounded-xl border border-border bg-secondary/60 p-3 text-xs">
              Questo annuncio è <b>{listingStatusLabel[stato].toLowerCase()}</b>: le azioni di
              acquisto e proposta sono disabilitate.
            </div>
          )}

          {propostaAttiva && (
            <div className="mt-4 rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm">
              {propostaAttiva.stato === "inviata" && (
                <>
                  Proposta <b>{formatEUR(propostaAttiva.prezzoProposto)}</b> inviata. Scade il{" "}
                  {new Date(propostaAttiva.scadenza).toLocaleDateString("it-IT")}.
                </>
              )}
              {propostaAttiva.stato === "controproposta" && (
                <>
                  Il venditore risponde con <b>{formatEUR(propostaAttiva.controProposta!)}</b>.{" "}
                  <Link href="/messaggi" className="text-bordeaux underline">
                    Rispondi in chat
                  </Link>
                  .
                </>
              )}
              {propostaAttiva.stato === "accettata" && (
                <>
                  Proposta accettata a <b>{formatEUR(propostaAttiva.prezzoProposto)}</b>.{" "}
                  <button
                    className="text-bordeaux underline"
                    onClick={() =>
                      router.push(`/checkout/${wine.id}?prop=${propostaAttiva.id}`)
                    }
                  >
                    Vai al checkout
                  </button>
                </>
              )}
            </div>
          )}

          <div className="mt-6 grid grid-cols-3 gap-2">
            <Button
              className="col-span-2 bg-bordeaux hover:bg-bordeaux/90"
              disabled={azioniBloccate}
              onClick={() => router.push(`/checkout/${wine.id}`)}
            >
              Compra ora
            </Button>
            <Dialog open={openProp} onOpenChange={setOpenProp}>
              <DialogTrigger asChild>
                <Button
                  variant="outline"
                  disabled={
                    azioniBloccate || (!!propostaAttiva && propostaAttiva.stato !== "accettata")
                  }
                >
                  {propostaAttiva ? "Proposta attiva" : "Proponi"}
                </Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle className="font-serif text-2xl">Fai una proposta</DialogTitle>
                </DialogHeader>
                <p className="text-sm text-muted-foreground">
                  Prezzo richiesto: <b>{formatEUR(wine.prezzo)}</b>. La tua offerta resterà valida 7
                  giorni.
                </p>
                <Input
                  type="number"
                  value={prezzoProposto}
                  onChange={(e) => setPrezzoProposto(e.target.value)}
                  className="mt-4"
                />
                <p className="mt-2 inline-flex items-center gap-1 text-xs text-muted-foreground">
                  <Clock className="h-3 w-3" /> Riceverai una notifica alla risposta.
                </p>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setOpenProp(false)}>
                    Annulla
                  </Button>
                  <Button
                    className="bg-bordeaux hover:bg-bordeaux/90"
                    onClick={() => {
                      const n = Number(prezzoProposto);
                      if (!n || n <= 0) {
                        toast.error("Inserisci un prezzo valido");
                        return;
                      }
                      createProposal(wine.id, n);
                      setOpenProp(false);
                    }}
                  >
                    Invia proposta
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>

          <div className="mt-3 flex flex-wrap gap-2">
            <Button variant="ghost" onClick={() => toggleFavorite(wine.id)}>
              <Heart className={`h-4 w-4 ${fav ? "fill-bordeaux text-bordeaux" : ""}`} />{" "}
              {fav ? "Preferito" : "Salva"}
            </Button>
            <Button variant="ghost" asChild>
              <Link href="/messaggi">
                <MessageCircle className="h-4 w-4" /> Messaggio
              </Link>
            </Button>
            <Button
              variant="ghost"
              onClick={() => {
                richiediAltreFoto(wine.id, wine.venditore.nome);
                router.push("/messaggi");
              }}
            >
              <Camera className="h-4 w-4" /> Richiedi altre foto
            </Button>
            <Button
              variant="ghost"
              onClick={() => {
                navigator.clipboard?.writeText(window.location.href);
                toast("Link copiato");
              }}
            >
              <Share2 className="h-4 w-4" /> Condividi
            </Button>
            <ReportDialog
              targetType="annuncio"
              targetId={wine.id}
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
                  <MapPin className="h-3 w-3" /> {wine.venditore.citta} •{" "}
                  <Star className="h-3 w-3 fill-oro text-oro" /> {wine.venditore.rating} (
                  {wine.venditore.valutazioni})
                </p>
              </div>
              <Button
                size="sm"
                variant={seguito ? "secondary" : "outline"}
                onClick={() => toggleFollow(wine.venditore.nome)}
              >
                {seguito ? "Seguito" : "Segui"}
              </Button>
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

function MyBottleActions({ wineId }: { wineId: string }) {
  const { bottiglieCantina, openBottle, scheduleOpen } = useVinea();
  const bottle = bottiglieCantina.find((b) => b.wineVintageId === wineId);
  const [when, setWhen] = useState("");
  const [nota, setNota] = useState("");
  if (!bottle) return null;
  return (
    <div className="mt-4 rounded-2xl border border-oro/40 bg-oro/10 p-4">
      <p className="text-xs uppercase tracking-wide text-oro">Nella tua cantina</p>
      <p className="mt-1 text-sm">
        {bottle.quantita} {bottle.quantita === 1 ? "bottiglia" : "bottiglie"} disponibili
        {bottle.plannedOpenDate ? ` · apertura pianificata ${bottle.plannedOpenDate}` : ""}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <Dialog>
          <DialogTrigger asChild>
            <Button
              size="sm"
              className="bg-bordeaux hover:bg-bordeaux/90"
              disabled={bottle.quantita === 0}
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
