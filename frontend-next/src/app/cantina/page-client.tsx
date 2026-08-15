"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import dynamic from "next/dynamic";
import {
  LayoutGrid,
  List,
  TrendingUp,
  PlusCircle,
  Tag,
  Palette,
  Eye,
  EyeOff,
  Pencil,
  Info,
  CalendarClock,
  Clock,
  Sparkles,
  Search,
  Box,
  Layers,
  Ruler,
  Loader2,
} from "lucide-react";
import type { Wine } from "@/data/wines";
import { WineCard } from "@/components/vinea/WineCard";
import { Kpi } from "@/components/vinea/Layout";
import { formatEUR, useVinea, type SfondoCantina } from "@/lib/vinea-store";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { wineImages } from "@/lib/wine-images";
import {
  SHAPE_LABELS,
  THEME_LABELS,
  type EnvShape,
  type EnvTheme,
  type StorageSlot,
} from "@/data/cellar";
import { FindWineFromCellar } from "@/components/vinea/FoodPairing";
import { WineMetaProvider } from "@/lib/wine-meta-context";
import { slotsDaModuli } from "@/services/cellar-service";
import { useCellarOverview, useEnvironmentConfigurator } from "@/hooks/useCellar";

/**
 * /cantina portata da frontend/src/routes/cantina.tsx (1027 righe).
 *
 * Le differenze rispetto all'originale, tutte conseguenza dei dati reali e
 * nessuna di design:
 *
 * - **Serve una sessione.** In `frontend/` la cantina è un elenco costante
 *   uguale per tutti, visibile anche da sloggati. Una cantina vera appartiene a
 *   qualcuno.
 * - **"Metti in vendita" non è più un interruttore.** Nel mock accendeva un
 *   flag in memoria; qui mettere in vendita significa creare un annuncio, che è
 *   lavoro del wizard `/vendi`. Il pulsante ci porta, con la bottiglia scelta.
 *   Lo stato "In vendita" resta mostrato, ma derivato dagli annunci attivi.
 * - **La vista 3D si carica con `next/dynamic`** invece di `ClientOnly` +
 *   `React.lazy`: è l'equivalente App Router dello stesso rinvio, e il chunk
 *   Three.js resta fuori dal bundle finché non si sceglie la vista 3D.
 * - **Il valore stimato usa il prezzo dell'annuncio** di ogni bottiglia: in
 *   `wines` un prezzo non esiste, appartiene a `listings`.
 */
export default function CantinaPageClient() {
  const { metaPerVino } = useVinea();
  return (
    <WineMetaProvider metaPerVino={metaPerVino}>
      <Cantina />
    </WineMetaProvider>
  );
}

// Il chunk Three.js resta fuori dal bundle iniziale e dal render sul server:
// `ssr: false` è l'equivalente del `import.meta.env.SSR` di frontend/.
const LazyCellar3D = dynamic(() => import("@/components/vinea/Cellar3D"), {
  ssr: false,
  loading: () => (
    <div className="grid h-full place-items-center text-crema/70">Carico la vista 3D…</div>
  ),
});

const SFONDI: { key: SfondoCantina; nome: string; url: string }[] = [
  { key: "moderna", nome: "Moderna", url: wineImages.cellar },
  { key: "rustica", nome: "Rustica", url: wineImages.vineyard },
  { key: "pietra", nome: "Pietra", url: wineImages.bottle2 },
  { key: "premium", nome: "Premium", url: wineImages.champagne },
  { key: "casse", nome: "Parete di casse", url: wineImages.crate },
];

const ANDAMENTO = [8200, 8450, 8700, 8600, 8900, 9250, 9400, 9350, 9600, 9800, 10150, 10420];
const MESI = ["Ago", "Set", "Ott", "Nov", "Dic", "Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug"];

function Cantina() {
  const {
    authUser,
    authLoading,
    cantinaLoading,
    sfondoCantina,
    setSfondoCantina,
    regionePref,
    tipologiaPref,
    setPreferenze,
    inVendita,
    prezzoNascosto,
    togglePrezzoNascosto,
    bottiglieCantina,
    viniCantina,
    ambienti,
    moduli,
    drinkWindowOverrides,
    reduceMotion,
    setReduceMotion,
  } = useVinea();

  const {
    mie,
    idealiOra,
    daBerePresto,
    daAttendere,
    aperture,
    totBottiglie,
    valore,
    totSlot,
    occSlot,
    nonCollocate,
    usoPct,
  } = useCellarOverview({
    bottiglieCantina,
    viniCantina,
    ambienti,
    moduli,
    drinkWindowOverrides,
  });

  const [view, setView] = useState<"grid" | "list" | "3d">("grid");
  const [threeDRequested, setThreeDRequested] = useState(false);

  const selectView = (nextView: "grid" | "list" | "3d") => {
    if (nextView === "3d") setThreeDRequested(true);
    setView(nextView);
  };

  const variazione = ((ANDAMENTO[ANDAMENTO.length - 1] - ANDAMENTO[0]) / ANDAMENTO[0]) * 100;
  const sfondoUrl = SFONDI.find((s) => s.key === sfondoCantina)!.url;

  /** La prima bottiglia di un vino: è quella che i comandi per vino prendono. */
  const bottigliaDelVino = (wine: Wine) =>
    bottiglieCantina.find((b) => b.wineVintageId === (wine.wineSlug ?? wine.id));

  if (authLoading || cantinaLoading) {
    return (
      <div className="mx-auto max-w-lg py-16 text-center text-sm text-muted-foreground">
        <Loader2 className="mx-auto h-6 w-6 animate-spin text-bordeaux" />
        <p className="mt-3">Carico la tua cantina…</p>
      </div>
    );
  }

  // Una cantina è di qualcuno: senza sessione non c'è nulla da mostrare.
  if (!authUser) {
    return (
      <div className="mx-auto max-w-lg space-y-4 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
          <Box className="h-8 w-8 text-bordeaux" />
        </div>
        <h1 className="font-serif text-2xl md:text-3xl">Accedi per vedere la tua cantina</h1>
        <p className="text-sm text-muted-foreground">
          Le bottiglie, gli ambienti e le posizioni sono tuoi: servono un account e una sessione
          aperta.
        </p>
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link href="/registrati">Crea un account</Link>
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header con sfondo */}
      <section className="relative overflow-hidden rounded-3xl border border-border hero-glow">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={sfondoUrl}
          alt=""
          className="absolute inset-0 h-full w-full object-cover animate-ken-burns"
          fetchPriority="high"
          decoding="async"
        />
        <div className="absolute inset-0 bg-gradient-to-r from-antracite/85 via-antracite/60 to-antracite/30" />
        <div className="hero-grain" aria-hidden />
        <div className="relative flex flex-col gap-4 p-6 text-crema md:flex-row md:items-end md:justify-between md:p-8">
          <div className="animate-fade-up">
            <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
            <h1 className="mt-1 font-serif text-3xl md:text-4xl">
              La <span className="gold-shimmer">mia cantina</span>
            </h1>
            <p className="text-crema/85">Il tuo patrimonio in bottiglia, sempre a portata di mano.</p>
          </div>
          <div className="flex flex-wrap gap-2 animate-fade-up" style={{ animationDelay: "120ms" }}>
            <Button asChild className="bg-oro text-antracite hover:bg-oro/90">
              <Link href="/vendi?mode=catalog">
                <PlusCircle className="h-4 w-4" /> Aggiungi bottiglia
              </Link>
            </Button>
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link href="/vendi?mode=sell">
                <Tag className="h-4 w-4" /> Metti in vendita
              </Link>
            </Button>
            <FindWineFromCellar />
            <SfondoDialog attivo={sfondoCantina} setAttivo={setSfondoCantina} />
          </div>
        </div>
      </section>

      {/* KPI + capacità */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="Bottiglie" value={String(totBottiglie)} />
        <Kpi label="Valore stimato" value={formatEUR(valore)} hint="Prezzi di mercato" />
        <Kpi
          label="Capacità utilizzata"
          value={`${usoPct}%`}
          hint={`${occSlot}/${totSlot} posti`}
        />
        <Kpi
          label="Salute cantina"
          value={saluteCantina(usoPct, nonCollocate.length)}
          hint="Indicatore orientativo locale"
        />
      </div>

      {/* Preferenze */}
      <PreferenzeCantina regione={regionePref} tipologia={tipologiaPref} onSave={setPreferenze} />

      {/* Bottiglie: 3 viste */}
      <Tabs defaultValue="tutte">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <TabsList className="bg-secondary">
            <TabsTrigger value="tutte">Tutte</TabsTrigger>
            <TabsTrigger value="pronte">Pronte da bere</TabsTrigger>
            <TabsTrigger value="vendita">In vendita</TabsTrigger>
            <TabsTrigger value="attesa">Da attendere</TabsTrigger>
          </TabsList>
          <div className="flex items-center gap-2">
            <ConfiguratorDialog />
            <div
              role="tablist"
              aria-label="Vista bottiglie"
              className="flex rounded-full border border-border bg-card p-1"
            >
              <ViewBtn active={view === "grid"} onClick={() => selectView("grid")} label="Griglia">
                <LayoutGrid className="h-4 w-4" />
              </ViewBtn>
              <ViewBtn active={view === "list"} onClick={() => selectView("list")} label="Elenco">
                <List className="h-4 w-4" />
              </ViewBtn>
              <ViewBtn active={view === "3d"} onClick={() => selectView("3d")} label="3D">
                <Box className="h-4 w-4" />
              </ViewBtn>
            </div>
          </div>
        </div>

        <TabsContent value="tutte" className="mt-4">
          {view === "3d" && threeDRequested ? (
            <View3D />
          ) : (
            <BottiglieView
              wines={mie}
              view={view === "3d" ? "grid" : view}
              inVendita={inVendita}
              prezzoNascosto={prezzoNascosto}
              togglePrezzo={togglePrezzoNascosto}
              bottigliaDelVino={bottigliaDelVino}
            />
          )}
        </TabsContent>
        <TabsContent value="pronte" className="mt-4">
          <BottiglieView
            wines={idealiOra.map((x) => x.wine)}
            view={view === "3d" ? "grid" : view}
            inVendita={inVendita}
            prezzoNascosto={prezzoNascosto}
            togglePrezzo={togglePrezzoNascosto}
            bottigliaDelVino={bottigliaDelVino}
          />
        </TabsContent>
        <TabsContent value="vendita" className="mt-4">
          <BottiglieView
            wines={mie.filter((w) => inVendita.has(w.wineSlug ?? w.id))}
            view={view === "3d" ? "grid" : view}
            inVendita={inVendita}
            prezzoNascosto={prezzoNascosto}
            togglePrezzo={togglePrezzoNascosto}
            bottigliaDelVino={bottigliaDelVino}
          />
        </TabsContent>
        <TabsContent value="attesa" className="mt-4">
          <BottiglieView
            wines={daAttendere.map((x) => x.wine)}
            view={view === "3d" ? "grid" : view}
            inVendita={inVendita}
            prezzoNascosto={prezzoNascosto}
            togglePrezzo={togglePrezzoNascosto}
            bottigliaDelVino={bottigliaDelVino}
          />
        </TabsContent>
      </Tabs>

      {/* Andamento valore — sotto alle bottiglie in vendita */}
      <section className="rounded-2xl border border-border bg-card p-5">
        <div className="mb-3 flex items-start justify-between gap-3">
          <div>
            <p className="text-xs uppercase tracking-wide text-muted-foreground">
              Andamento del valore della cantina
            </p>
            <p className="mt-1 font-serif text-3xl font-semibold text-bordeaux">
              {formatEUR(ANDAMENTO[ANDAMENTO.length - 1])}
            </p>
            <p className="mt-0.5 flex items-center gap-1 text-sm text-salvia">
              <TrendingUp className="h-4 w-4" /> +{variazione.toFixed(1)}% negli ultimi 12 mesi
            </p>
          </div>
          <span className="flex max-w-[220px] items-start gap-1 text-[10px] text-muted-foreground">
            <Info className="mt-0.5 h-3 w-3 shrink-0" />
            Stima indicativa basata sulle bottiglie catalogate; non è una valutazione garantita.
          </span>
        </div>
        <Sparkline values={ANDAMENTO} labels={MESI} />
      </section>

      {/* Dashboard drink-window (icone) */}
      <section className="grid gap-3 md:grid-cols-4">
        <DashCard
          title="Cosa bere adesso"
          count={idealiOra.length}
          icon={Sparkles}
          tone="bordeaux"
          hint="Bottiglie pronte oggi"
        />
        <DashCard
          title="Da bere presto"
          count={daBerePresto.length}
          icon={Clock}
          tone="oro"
          hint="Entro pochi anni"
        />
        <DashCard
          title="Da attendere"
          count={daAttendere.length}
          icon={CalendarClock}
          tone="salvia"
          hint="Ancora in evoluzione"
        />
        <DashCard
          title="Aperture programmate"
          count={aperture.length}
          icon={CalendarClock}
          tone="antracite"
          hint="Data pianificata"
        />
      </section>

      {/* Cosa bere adesso — carosello in fondo */}
      {idealiOra.length > 0 && (
        <section>
          <div className="mb-3 flex items-end justify-between">
            <div>
              <p className="text-xs uppercase tracking-wide text-muted-foreground">
                Selezione della cantina
              </p>
              <h2 className="font-serif text-2xl">Cosa bere adesso</h2>
            </div>
          </div>
          <div className="flex gap-3 overflow-x-auto pb-2 md:grid md:grid-cols-4 md:overflow-visible">
            {idealiOra.slice(0, 6).map(({ wine }) => (
              <div key={wine.id} className="w-52 shrink-0 md:w-auto">
                <WineCard wine={wine} showSaleBadge hidePriceIfPrivate />
              </div>
            ))}
          </div>
        </section>
      )}

      <label className="flex items-center gap-2 text-xs text-muted-foreground">
        <input
          type="checkbox"
          checked={reduceMotion}
          onChange={(e) => setReduceMotion(e.target.checked)}
        />
        Riduci animazioni (disattiva l&apos;auto-rotazione della vista 3D)
      </label>
    </div>
  );
}

function saluteCantina(usoPct: number, noLoc: number): string {
  if (noLoc > 3) return "Attenzione";
  if (usoPct > 85) return "Piena";
  if (usoPct > 40) return "Ottima";
  return "Spaziosa";
}

function DashCard({
  title,
  count,
  icon: Icon,
  tone,
  hint,
}: {
  title: string;
  count: number;
  icon: typeof Sparkles;
  tone: "bordeaux" | "oro" | "salvia" | "antracite";
  hint: string;
}) {
  const toneClass = {
    bordeaux: "bg-bordeaux text-crema",
    oro: "bg-oro/20 text-antracite",
    salvia: "bg-salvia/20 text-antracite",
    antracite: "bg-antracite text-crema",
  }[tone];
  return (
    <div className={`rounded-2xl p-4 ${toneClass}`}>
      <div className="flex items-center gap-2 text-xs uppercase tracking-wide opacity-80">
        <Icon className="h-3.5 w-3.5" /> {title}
      </div>
      <p className="mt-1 font-serif text-3xl font-semibold">{count}</p>
      <p className="text-xs opacity-75">{hint}</p>
    </div>
  );
}

function ViewBtn({
  active,
  onClick,
  label,
  children,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      aria-label={`Vista ${label}`}
      aria-pressed={active}
      data-testid={`cantina-view-${label.toLowerCase()}`}
      className={`grid h-8 w-8 place-items-center rounded-full transition ${active ? "bg-bordeaux text-crema" : ""}`}
    >
      {children}
    </button>
  );
}

function View3D() {
  const { ambienti, moduli, bottiglieCantina, viniCantina, reduceMotion, moveBottle } = useVinea();
  const [envId, setEnvId] = useState(ambienti[0]?.id ?? "");
  const [selected, setSelected] = useState<StorageSlot | null>(null);
  const [highlight, setHighlight] = useState<string | undefined>();
  const [q, setQ] = useState("");

  // Le posizioni libere non hanno riga nel database (scelta di 6c-1): si
  // ricavano dalla geometria dei moduli, esattamente come faceva `makeSlots()`
  // sui moduli mock.
  const slots = useMemo(
    () => slotsDaModuli(moduli, bottiglieCantina),
    [moduli, bottiglieCantina],
  );

  const nonCollocate = useMemo(
    () => bottiglieCantina.filter((b) => !b.storageLocationId),
    [bottiglieCantina],
  );

  const vinoDi = useMemo(() => {
    const m = new Map<string, Wine>();
    for (const w of viniCantina) m.set(w.wineSlug ?? w.id, w);
    return m;
  }, [viniCantina]);

  const risultati = useMemo(() => {
    if (!q.trim()) return [];
    const norm = q.toLowerCase();
    return bottiglieCantina
      .map((b) => {
        const w = vinoDi.get(b.wineVintageId);
        if (!w) return null;
        const match =
          w.nome.toLowerCase().includes(norm) ||
          w.produttore.toLowerCase().includes(norm) ||
          w.regione.toLowerCase().includes(norm) ||
          w.denominazione.toLowerCase().includes(norm) ||
          String(w.annata).includes(norm);
        if (!match) return null;
        return { wine: w, bottle: b };
      })
      .filter((x): x is { wine: Wine; bottle: (typeof bottiglieCantina)[number] } => !!x)
      .slice(0, 5);
  }, [q, bottiglieCantina, vinoDi]);

  const selBottle = selected?.bottleId
    ? bottiglieCantina.find((x) => x.bottleId === selected.bottleId)
    : undefined;
  const selWine = selBottle ? vinoDi.get(selBottle.wineVintageId) : undefined;
  const selModulo = selected ? moduli.find((m) => m.id === selected.moduleId) : undefined;

  const localizza = (b: (typeof bottiglieCantina)[number]) => {
    if (!b.storageLocationId) return;
    const slot = slots.find((s) => s.id === b.storageLocationId);
    if (!slot) return;
    const mod = moduli.find((m) => m.id === slot.moduleId);
    if (mod && mod.environmentId !== envId) setEnvId(mod.environmentId);
    setHighlight(slot.id);
    setSelected(slot);
    setQ("");
  };

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
      <div className="relative aspect-square overflow-hidden rounded-2xl border border-border bg-antracite md:aspect-video">
        {ambienti.length === 0 ? (
          <div className="grid h-full place-items-center p-6 text-center text-sm text-crema/80">
            Non hai ancora un ambiente. Creane uno con &laquo;Configura cantina&raquo; per vedere la
            tua cantina in 3D.
          </div>
        ) : (
          <LazyCellar3D
            environments={ambienti}
            modules={moduli}
            slots={slots}
            bottiglie={bottiglieCantina}
            wines={viniCantina}
            activeEnvId={envId}
            onSelectSlot={(s) => {
              setSelected(s);
              if (s) setHighlight(s.id);
            }}
            highlightedSlotId={highlight}
            reduceMotion={reduceMotion}
          />
        )}
        {ambienti.length > 1 && (
          <div className="absolute left-3 top-3 rounded-full bg-antracite/70 p-1 text-xs text-crema">
            {ambienti.map((e) => (
              <button
                key={e.id}
                onClick={() => setEnvId(e.id)}
                className={`rounded-full px-3 py-1 ${envId === e.id ? "bg-bordeaux text-crema" : "text-crema/80"}`}
              >
                {e.name}
              </button>
            ))}
          </div>
        )}
      </div>

      <aside className="space-y-4">
        <div>
          <Label className="text-xs uppercase tracking-wide text-muted-foreground">
            Cerca una bottiglia nella cantina
          </Label>
          <div className="relative mt-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Produttore, vino, annata…"
              className="pl-10"
            />
          </div>
          {risultati.length > 0 && (
            <ul className="mt-2 space-y-1">
              {risultati.map((r) => (
                <li key={r.bottle.bottleId}>
                  <button
                    onClick={() => localizza(r.bottle)}
                    className="flex w-full items-center gap-2 rounded-lg border border-border bg-card p-2 text-left text-xs hover:bg-secondary/40"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={r.wine.immagini[0]} alt="" className="h-10 w-8 rounded object-cover" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-semibold">
                        {r.wine.nome} {r.wine.annata}
                      </p>
                      <p className="text-muted-foreground">{r.wine.produttore}</p>
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="rounded-xl border border-border bg-card p-3 text-xs">
          <p className="font-semibold">Filtri rapidi</p>
          <div className="mt-2 flex flex-wrap gap-1 text-[11px] text-muted-foreground">
            <span className="rounded-full bg-salvia/20 px-2 py-0.5">Pronte da bere</span>
            <span className="rounded-full bg-bordeaux/15 px-2 py-0.5 text-bordeaux">In vendita</span>
            <span className="rounded-full bg-antracite/10 px-2 py-0.5">Prezzo riservato</span>
            <span className="rounded-full bg-oro/25 px-2 py-0.5">Bere presto</span>
          </div>
        </div>

        {/*
          Bottiglie senza posizione.

          UNICA DEVIAZIONE DI QUESTA FASE, e non è un comando nuovo: è lo stesso
          "Sposta" che `frontend/` ha già, reso raggiungibile. Nei dati mock ogni
          bottiglia nasce con uno `storageLocationId`, quindi non esiste una
          bottiglia da collocare e il comando si raggiunge solo cliccando una
          bottiglia già nella scena. Su dati veri nessuna bottiglia nasce
          collocata — `listing_crea` non assegna posizioni — e senza questo
          elenco la prima collocazione non sarebbe raggiungibile da nessuna
          parte, cioè `cellar_posiziona` resterebbe una funzione senza porta.
          L'elenco esisteva già come dato: `nonCollocate` alimenta il KPI
          "Salute cantina" anche in `frontend/`.
        */}
        {nonCollocate.length > 0 && ambienti.length > 0 && (
          <div className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-xs">
            <p className="font-semibold text-antracite">
              Da collocare ({nonCollocate.length})
            </p>
            <ul className="mt-2 space-y-1">
              {nonCollocate.slice(0, 8).map((b) => {
                const w = vinoDi.get(b.wineVintageId);
                return (
                  <li key={b.bottleId} className="flex items-center justify-between gap-2">
                    <span className="min-w-0 flex-1 truncate">
                      {w ? `${w.nome} ${w.annata}` : b.wineVintageId}
                    </span>
                    <MoveBottleButton
                      bottleId={b.bottleId}
                      etichetta="Colloca"
                      slots={slots}
                      moduli={moduli}
                      onMove={async (nuovo) => {
                        const esito = await moveBottle(b.bottleId, nuovo);
                        if (esito.ok) setHighlight(nuovo);
                        return esito.ok;
                      }}
                    />
                  </li>
                );
              })}
            </ul>
          </div>
        )}

        {selected && selWine ? (
          <div className="rounded-xl border border-border bg-card p-3">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
              Bottiglia selezionata
            </p>
            <p className="font-serif text-lg">
              {selWine.nome} {selWine.annata}
            </p>
            <p className="text-xs text-muted-foreground">
              {selWine.produttore} · {selWine.regione}
            </p>
            <p className="mt-2 text-xs">
              {/* Con id reali il modulo è un UUID: si mostra l'etichetta, che è
                  ciò che l'utente ha scritto e riconosce. */}
              Posizione: modulo <b>{selModulo?.label ?? selected.moduleId}</b> · riga{" "}
              {selected.row + 1}, colonna {selected.column + 1}
            </p>
            <div className="mt-3 flex flex-wrap gap-2">
              <Button asChild size="sm" className="bg-bordeaux hover:bg-bordeaux/90">
                <Link href={`/annuncio/${selWine.id}`}>Apri scheda</Link>
              </Button>
              <MoveBottleButton
                bottleId={selected.bottleId!}
                slots={slots}
                moduli={moduli}
                onMove={async (nuovo) => {
                  const esito = await moveBottle(selected.bottleId!, nuovo);
                  if (esito.ok) setHighlight(nuovo);
                  return esito.ok;
                }}
              />
            </div>
          </div>
        ) : selected ? (
          <div className="rounded-xl border border-dashed border-border bg-card p-3 text-xs text-muted-foreground">
            Slot libero — modulo {selModulo?.label ?? selected.moduleId}, riga {selected.row + 1},
            colonna {selected.column + 1}.
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-border bg-card p-3 text-xs text-muted-foreground">
            Clicca su una bottiglia nella scena 3D per vederne i dettagli.
          </div>
        )}
      </aside>
    </div>
  );
}

function MoveBottleButton({
  slots,
  moduli,
  onMove,
  etichetta = "Sposta",
}: {
  bottleId: string;
  slots: StorageSlot[];
  moduli: { id: string; label: string }[];
  onMove: (slotId: string) => Promise<boolean>;
  etichetta?: string;
}) {
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<string>("");
  const [inCorso, setInCorso] = useState(false);
  const liberi = slots.filter((s) => !s.bottleId);
  const etichettaModulo = (moduleId: string) =>
    moduli.find((m) => m.id === moduleId)?.label ?? moduleId;

  const conferma = async () => {
    setInCorso(true);
    const ok = await onMove(target);
    setInCorso(false);
    if (ok) setOpen(false);
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          {etichetta}
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="font-serif text-xl">{etichetta} bottiglia</DialogTitle>
        </DialogHeader>
        <Label>Nuova posizione</Label>
        <Select value={target} onValueChange={setTarget}>
          <SelectTrigger>
            <SelectValue placeholder="Seleziona uno slot libero" />
          </SelectTrigger>
          <SelectContent>
            {liberi.slice(0, 30).map((s) => (
              <SelectItem key={s.id} value={s.id}>
                {etichettaModulo(s.moduleId)} · r{s.row + 1} c{s.column + 1}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Annulla
          </Button>
          <Button
            disabled={!target || inCorso}
            className="bg-bordeaux hover:bg-bordeaux/90"
            onClick={conferma}
          >
            Conferma
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function BottiglieView({
  wines: list,
  view,
  inVendita,
  prezzoNascosto,
  togglePrezzo,
  bottigliaDelVino,
}: {
  wines: Wine[];
  view: "grid" | "list";
  inVendita: Set<string>;
  prezzoNascosto: Set<string>;
  togglePrezzo: (id: string) => Promise<unknown>;
  bottigliaDelVino: (w: Wine) => { bottleId: string } | undefined;
}) {
  if (list.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center text-sm text-muted-foreground">
        Nessuna bottiglia in questo filtro.
      </div>
    );
  }
  return (
    <div
      className={
        view === "grid"
          ? "grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4"
          : "grid gap-3 md:grid-cols-2"
      }
    >
      {list.map((w) => {
        const slug = w.wineSlug ?? w.id;
        const venduta = inVendita.has(slug);
        const bottiglia = bottigliaDelVino(w);
        return (
          <div key={w.id} className="space-y-2">
            <WineCard
              wine={w}
              variant={view === "list" ? "list" : "grid"}
              showSaleBadge
              hidePriceIfPrivate
            />
            <div className="flex flex-wrap gap-2">
              {/* Nel mock questo era un interruttore su un insieme in memoria.
                  Mettere in vendita significa creare un annuncio: è il lavoro
                  del wizard, e ci si arriva con la bottiglia già scelta. Chi è
                  già in vendita ha un annuncio da aprire. */}
              <Link
                href={
                  venduta
                    ? `/annuncio/${w.id}`
                    : `/vendi?mode=sell${bottiglia ? `&bottiglia=${bottiglia.bottleId}` : ""}`
                }
                className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[11px] font-medium transition ${
                  venduta ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"
                }`}
              >
                <Tag className="h-3 w-3" /> {venduta ? "In vendita" : "Metti in vendita"}
              </Link>
              <button
                onClick={() => void togglePrezzo(slug)}
                className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[11px] font-medium transition ${
                  prezzoNascosto.has(slug)
                    ? "border-antracite bg-antracite text-crema"
                    : "border-border bg-card"
                }`}
              >
                {prezzoNascosto.has(slug) ? (
                  <EyeOff className="h-3 w-3" />
                ) : (
                  <Eye className="h-3 w-3" />
                )}
                {prezzoNascosto.has(slug) ? "Prezzo riservato" : "Prezzo visibile"}
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function PreferenzeCantina({
  regione,
  tipologia,
  onSave,
}: {
  regione: string;
  tipologia: string;
  onSave: (r: string, t: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [r, setR] = useState(regione);
  const [t, setT] = useState(tipologia);
  const regioni = ["Toscana", "Piemonte", "Veneto", "Sicilia", "Lombardia", "Champagne"];
  const tipi = [
    "Rossi strutturati",
    "Rossi eleganti",
    "Bianchi minerali",
    "Champagne",
    "Bollicine italiane",
    "Dolci",
  ];
  return (
    <section className="rounded-2xl border border-border bg-card p-5">
      <div className="mb-4 flex items-center justify-between gap-3">
        <p className="text-xs uppercase tracking-wide text-muted-foreground">Le tue preferenze</p>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" variant="outline">
              <Pencil className="h-3.5 w-3.5" /> Modifica preferenze
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="font-serif text-2xl">Preferenze cantina</DialogTitle>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label className="mb-1 block text-xs uppercase tracking-wide">
                  Regione preferita
                </Label>
                <div className="flex flex-wrap gap-2">
                  {regioni.map((x) => (
                    <button
                      key={x}
                      onClick={() => setR(x)}
                      className={`rounded-full border px-3 py-1 text-xs ${r === x ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
                    >
                      {x}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <Label className="mb-1 block text-xs uppercase tracking-wide">
                  Tipologia preferita
                </Label>
                <div className="flex flex-wrap gap-2">
                  {tipi.map((x) => (
                    <button
                      key={x}
                      onClick={() => setT(x)}
                      className={`rounded-full border px-3 py-1 text-xs ${t === x ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
                    >
                      {x}
                    </button>
                  ))}
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setOpen(false)}>
                Annulla
              </Button>
              <Button
                className="bg-bordeaux hover:bg-bordeaux/90"
                onClick={() => {
                  onSave(r, t);
                  setOpen(false);
                }}
              >
                Salva
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <div className="rounded-xl border border-border bg-secondary/40 p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
            Regione preferita
          </p>
          <p className="mt-1 font-serif text-2xl">{regione}</p>
        </div>
        <div className="rounded-xl border border-border bg-secondary/40 p-4">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
            Tipologia preferita
          </p>
          <p className="mt-1 font-serif text-2xl">{tipologia}</p>
        </div>
      </div>
    </section>
  );
}

function SfondoDialog({
  attivo,
  setAttivo,
}: {
  attivo: SfondoCantina;
  setAttivo: (s: SfondoCantina) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="outline"
          className="border-crema/40 bg-transparent text-crema hover:bg-crema/10"
        >
          <Palette className="h-4 w-4" /> Personalizza
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">Sfondo della cantina</DialogTitle>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
          {SFONDI.map((s) => (
            <button
              key={s.key}
              onClick={() => {
                setAttivo(s.key);
                setOpen(false);
              }}
              className={`group relative aspect-[4/3] overflow-hidden rounded-xl border-2 ${attivo === s.key ? "border-bordeaux" : "border-transparent"}`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s.url} alt={s.nome} className="h-full w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-antracite/80 to-transparent" />
              <p className="absolute bottom-2 left-2 font-serif text-sm text-crema">{s.nome}</p>
            </button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function ConfiguratorDialog() {
  const { creaAmbiente } = useVinea();
  const [open, setOpen] = useState(false);
  const {
    name,
    setName,
    shape,
    setShape,
    theme,
    setTheme,
    rows,
    setRows,
    cols,
    setCols,
    capacitaStimata,
    inCorso,
    salva,
  } = useEnvironmentConfigurator({ creaAmbiente });

  const salvaEChiudi = async () => {
    const esito = await salva();
    if (esito.ok) setOpen(false);
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Layers className="h-3.5 w-3.5" /> Configura cantina
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">Configura la cantina</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <Label>Nome ambiente</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div>
            <Label className="mb-1 block">Forma</Label>
            <div className="grid grid-cols-2 gap-2 md:grid-cols-3">
              {(Object.keys(SHAPE_LABELS) as EnvShape[]).map((k) => (
                <button
                  key={k}
                  onClick={() => setShape(k)}
                  className={`rounded-xl border p-3 text-left text-xs ${shape === k ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
                >
                  <p className="font-semibold">{SHAPE_LABELS[k]}</p>
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="flex items-center gap-1">
                <Ruler className="h-3 w-3" /> Ripiani
              </Label>
              <Input
                type="number"
                value={rows}
                onChange={(e) => setRows(Math.max(1, Number(e.target.value)))}
              />
            </div>
            <div>
              <Label className="flex items-center gap-1">
                <Ruler className="h-3 w-3" /> Colonne
              </Label>
              <Input
                type="number"
                value={cols}
                onChange={(e) => setCols(Math.max(1, Number(e.target.value)))}
              />
            </div>
          </div>
          <div>
            <Label className="mb-1 block">Preset estetico</Label>
            <div className="flex flex-wrap gap-2">
              {(Object.keys(THEME_LABELS) as EnvTheme[]).map((k) => (
                <button
                  key={k}
                  onClick={() => setTheme(k)}
                  className={`rounded-full border px-3 py-1 text-xs ${theme === k ? "border-bordeaux bg-bordeaux text-crema" : "border-border"}`}
                >
                  {THEME_LABELS[k]}
                </button>
              ))}
            </div>
          </div>
          <p className="rounded-lg bg-secondary/50 p-2 text-[11px] text-muted-foreground">
            Capacità stimata: <b>{capacitaStimata}</b> posti. Le posizioni delle bottiglie esistenti
            non vengono modificate.
          </p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Annulla
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            disabled={inCorso}
            onClick={salvaEChiudi}
          >
            Crea ambiente
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Sparkline({ values, labels }: { values: number[]; labels: string[] }) {
  const W = 800,
    H = 140,
    P = 20;
  const min = Math.min(...values),
    max = Math.max(...values);
  const range = max - min || 1;
  const stepX = (W - P * 2) / (values.length - 1);
  const points = values.map(
    (v, i) => [P + i * stepX, H - P - ((v - min) / range) * (H - P * 2)] as const,
  );
  const path = points
    .map(([x, y], i) => `${i === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`)
    .join(" ");
  const area = `${path} L${points[points.length - 1][0]},${H - P} L${points[0][0]},${H - P} Z`;
  const cur = values[values.length - 1];
  const descr = `Valore stimato: minimo ${formatEUR(min)}, massimo ${formatEUR(max)}, valore attuale ${formatEUR(cur)} su ${values.length} mesi.`;

  return (
    <div className="w-full">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-32 w-full md:h-40"
        preserveAspectRatio="none"
        role="img"
        aria-label={`Andamento del valore della cantina. ${descr}`}
      >
        <title>Andamento del valore della cantina</title>
        <desc>{descr}</desc>
        <defs>
          <linearGradient id="cantina-grad" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="hsl(345 55% 27%)" stopOpacity="0.35" />
            <stop offset="100%" stopColor="hsl(345 55% 27%)" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d={area} fill="url(#cantina-grad)" />
        <path
          d={path}
          fill="none"
          stroke="hsl(345 55% 27%)"
          strokeWidth="2.5"
          strokeLinejoin="round"
          strokeLinecap="round"
        />
        {points.map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r={i === points.length - 1 ? 4 : 2.5} fill="hsl(345 55% 27%)" />
        ))}
      </svg>
      <p className="sr-only">{descr}</p>
      <div
        className="mt-1 flex justify-between px-4 text-[10px] text-muted-foreground"
        aria-hidden="true"
      >
        {labels.map((m, i) => (
          <span key={i} className={i % 2 === 0 ? "" : "hidden md:inline"}>
            {m}
          </span>
        ))}
      </div>
    </div>
  );
}
