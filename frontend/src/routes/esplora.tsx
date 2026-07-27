import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import {
  Search,
  SlidersHorizontal,
  LayoutGrid,
  List,
  Loader2,
  PackageOpen,
  UtensilsCrossed,
  Sparkles,
  RefreshCw,
} from "lucide-react";
import { wines } from "@/data/wines";
import { getWineMeta } from "@/data/cellar";
import { WineCard } from "@/components/vinea/WineCard";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Slider } from "@/components/ui/slider";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
  SheetFooter,
} from "@/components/ui/sheet";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { apiJson, jsonRequest } from "@/services/api-client";
import { pairingSchema } from "@/services/api-contracts";

export const Route = createFileRoute("/esplora")({
  head: () => ({
    meta: [
      { title: "Ricerca bottiglie — Vinea" },
      {
        name: "description",
        content: "Cerca tra centinaia di vini pregiati messi in vendita da privati.",
      },
      { property: "og:title", content: "Ricerca — Vinea" },
      { property: "og:description", content: "Filtra per regione, tipo, annata e prezzo." },
    ],
  }),
  component: Esplora,
});

const regioni = [
  "Tutte",
  "Piemonte",
  "Toscana",
  "Veneto",
  "Sicilia",
  "Friuli-Venezia Giulia",
  "Trentino-Alto Adige",
  "Abruzzo",
  "Emilia-Romagna",
  "Lombardia",
  "Campania",
  "Puglia",
  "Marche",
  "Umbria",
  "Liguria",
  "Sardegna",
  "Lazio",
  "Champagne",
];
const tipi = ["Tutti", "Rosso", "Bianco", "Bollicine", "Rosato", "Dolce"];

type Mode = "testo" | "abbinamento";

function Esplora() {
  const [mode, setMode] = useState<Mode>("testo");
  const [q, setQ] = useState("");
  const [regione, setRegione] = useState("Tutte");
  const [tipo, setTipo] = useState("Tutti");
  const [prezzo, setPrezzo] = useState<[number, number]>([0, 1500]);
  const [sort, setSort] = useState("recenti");
  const [view, setView] = useState<"grid" | "list">("grid");
  const [loading] = useState(false);

  // AI pairing state
  const [aiPicks, setAiPicks] = useState<{ wine_id: string; reasoning: string }[]>([]);
  const [aiIntro, setAiIntro] = useState("");
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiForQuery, setAiForQuery] = useState<string>("");

  async function askAI() {
    const query = q.trim();
    if (!query) return;
    setAiLoading(true);
    setAiError(null);
    setAiForQuery(query);
    try {
      const catalog = wines.map((w) => ({
        id: w.id,
        label: `${w.produttore} — ${w.nome} ${w.annata} (${w.denominazione ?? ""}, ${w.regione}) — ${w.tipo}`,
      }));
      const data = await apiJson(
        "/api/ai/pairing",
        pairingSchema,
        jsonRequest({ query, catalog }, { method: "POST" }),
      );
      setAiPicks(data.picks);
      setAiIntro(data.intro);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Errore imprevisto";
      setAiError(msg);
      setAiPicks([]);
    } finally {
      setAiLoading(false);
    }
  }

  // Reset AI results when the query changes / mode changes
  useEffect(() => {
    if (mode !== "abbinamento" || q.trim() !== aiForQuery) {
      setAiPicks([]);
      setAiIntro("");
      setAiError(null);
    }
  }, [mode, q, aiForQuery]);

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    let r = wines.filter((w) => {
      if (regione !== "Tutte" && w.regione !== regione) return false;
      if (tipo !== "Tutti" && w.tipo !== tipo) return false;
      if (w.prezzo < prezzo[0] || w.prezzo > prezzo[1]) return false;
      if (term) {
        if (mode === "testo") {
          if (!`${w.produttore} ${w.nome}`.toLowerCase().includes(term)) return false;
        } else {
          const meta = getWineMeta(w.id);
          const ok = meta.foodPairings.some(
            (p) =>
              p.piatto.toLowerCase().includes(term) ||
              p.categoria.toLowerCase().includes(term) ||
              p.keywords.some((k) => term.includes(k) || k.includes(term)),
          );
          if (!ok) return false;
        }
      }
      return true;
    });
    if (sort === "prezzo-asc") r = [...r].sort((a, b) => a.prezzo - b.prezzo);
    if (sort === "prezzo-desc") r = [...r].sort((a, b) => b.prezzo - a.prezzo);
    if (sort === "annata") r = [...r].sort((a, b) => a.annata - b.annata);
    return r;
  }, [q, mode, regione, tipo, prezzo, sort]);

  const reset = () => {
    setQ("");
    setRegione("Tutte");
    setTipo("Tutti");
    setPrezzo([0, 1500]);
  };

  const suggerimenti = [
    "Brasato",
    "Ostriche",
    "Risotto ai funghi",
    "Pesce crudo",
    "Formaggi stagionati",
    "Selvaggina",
    "Aperitivo",
    "Dolci",
  ];

  return (
    <div className="space-y-6" data-testid="esplora-page">
      <div>
        <h1 className="font-serif text-3xl font-semibold md:text-4xl">Ricerca</h1>
        <p className="text-muted-foreground">
          Trova la bottiglia giusta tra i nostri collezionisti.
        </p>
      </div>

      <div className="flex flex-col gap-3 md:flex-row md:items-center">
        <div className="relative flex-1">
          {mode === "abbinamento" ? (
            <UtensilsCrossed className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-bordeaux" />
          ) : (
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          )}
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            data-testid="esplora-search-input"
            placeholder={
              mode === "abbinamento"
                ? "Cosa stai preparando? es. brasato, ostriche, risotto…"
                : "Cerca produttore, denominazione, annata…"
            }
            className="pl-10 h-11 rounded-full bg-card"
          />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Select value={mode} onValueChange={(v) => setMode(v as Mode)}>
            <SelectTrigger
              className="h-11 w-full min-w-0 rounded-full bg-card sm:w-[190px]"
              aria-label="Modalità di ricerca"
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="testo">Ricerca per testo</SelectItem>
              <SelectItem value="abbinamento">Per abbinamento cibo</SelectItem>
            </SelectContent>
          </Select>
          <Select value={sort} onValueChange={setSort}>
            <SelectTrigger
              className="h-11 w-[calc(50%-0.5rem)] min-w-0 rounded-full bg-card sm:w-[170px]"
              aria-label="Ordinamento risultati"
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="recenti">Più recenti</SelectItem>
              <SelectItem value="prezzo-asc">Prezzo crescente</SelectItem>
              <SelectItem value="prezzo-desc">Prezzo decrescente</SelectItem>
              <SelectItem value="annata">Annata</SelectItem>
            </SelectContent>
          </Select>

          <Sheet>
            <SheetTrigger asChild>
              <Button
                variant="outline"
                className="h-11 flex-1 rounded-full sm:flex-none"
                data-testid="esplora-filters-btn"
              >
                <SlidersHorizontal className="h-4 w-4" /> Filtri
              </Button>
            </SheetTrigger>

            <SheetContent side="right">
              <SheetHeader>
                <SheetTitle className="font-serif text-2xl">Filtri</SheetTitle>
              </SheetHeader>
              <div className="mt-6 space-y-6 px-4">
                <div>
                  <p className="mb-2 text-sm font-medium">Regione</p>
                  <div className="flex flex-wrap gap-2">
                    {regioni.map((r) => (
                      <button
                        key={r}
                        onClick={() => setRegione(r)}
                        className={`rounded-full border px-3 py-1 text-xs ${regione === r ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
                      >
                        {r}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <p className="mb-2 text-sm font-medium">Tipologia</p>
                  <div className="flex flex-wrap gap-2">
                    {tipi.map((t) => (
                      <button
                        key={t}
                        onClick={() => setTipo(t)}
                        className={`rounded-full border px-3 py-1 text-xs ${tipo === t ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
                      >
                        {t}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <p className="mb-2 text-sm font-medium">Fascia di prezzo</p>
                  <Slider
                    min={0}
                    max={1500}
                    step={10}
                    value={prezzo}
                    onValueChange={(v) => setPrezzo([v[0], v[1]] as [number, number])}
                  />
                  <p className="mt-2 text-xs text-muted-foreground">
                    € {prezzo[0]} — € {prezzo[1]}
                  </p>
                </div>
              </div>
              <SheetFooter className="mt-6 px-4">
                <Button variant="outline" onClick={reset}>
                  Azzera
                </Button>
              </SheetFooter>
            </SheetContent>
          </Sheet>

          <div
            className="hidden rounded-full border border-border bg-card p-1 md:flex"
            data-testid="esplora-view-toggle"
          >
            <button
              onClick={() => setView("grid")}
              data-testid="esplora-view-grid"
              className={`grid h-9 w-9 place-items-center rounded-full ${view === "grid" ? "bg-bordeaux text-crema" : ""}`}
              aria-label="Griglia"
            >
              <LayoutGrid className="h-4 w-4" />
            </button>
            <button
              onClick={() => setView("list")}
              data-testid="esplora-view-list"
              className={`grid h-9 w-9 place-items-center rounded-full ${view === "list" ? "bg-bordeaux text-crema" : ""}`}
              aria-label="Lista"
            >
              <List className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>

      {mode === "abbinamento" && (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="mr-1 text-xs text-muted-foreground">Suggerimenti:</span>
            {suggerimenti.map((s) => {
              const active = q.toLowerCase() === s.toLowerCase();
              return (
                <button
                  key={s}
                  onClick={() => setQ(s.toLowerCase())}
                  className={`rounded-full border px-2.5 py-1 text-[11px] ${active ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card hover:bg-secondary"}`}
                >
                  {s}
                </button>
              );
            })}
          </div>
          {q.trim() && (
            <div
              className="rounded-2xl border border-bordeaux/20 bg-gradient-to-br from-bordeaux/5 via-oro/10 to-transparent p-4"
              data-testid="ai-pairing-panel"
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="grid h-9 w-9 place-items-center rounded-full bg-bordeaux text-crema">
                    <Sparkles className="h-4 w-4 text-oro" />
                  </span>
                  <div>
                    <p className="font-serif text-lg leading-tight">
                      Sommelier <span className="gold-shimmer">AI</span>
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      Chiedi 3 abbinamenti dal catalogo in un attimo
                    </p>
                  </div>
                </div>
                <Button
                  data-testid="ai-pairing-ask-btn"
                  size="sm"
                  onClick={askAI}
                  disabled={aiLoading || !q.trim()}
                  className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
                >
                  {aiLoading ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Analisi…
                    </>
                  ) : aiPicks.length ? (
                    <>
                      <RefreshCw className="h-3.5 w-3.5" /> Rigenera
                    </>
                  ) : (
                    <>
                      <Sparkles className="h-3.5 w-3.5" /> Chiedi al sommelier
                    </>
                  )}
                </Button>
              </div>

              {aiError && (
                <p
                  className="mt-3 rounded-xl bg-destructive/10 px-3 py-2 text-xs text-destructive"
                  data-testid="ai-pairing-error"
                >
                  {aiError}
                </p>
              )}

              {aiPicks.length > 0 && (
                <div className="mt-4 space-y-3" data-testid="ai-pairing-results">
                  {aiIntro && <p className="text-sm italic text-antracite/85">{aiIntro}</p>}
                  <div className="grid gap-3 md:grid-cols-3">
                    {aiPicks.map((p, idx) => {
                      const w = wines.find((x) => x.id === p.wine_id);
                      if (!w) return null;
                      return (
                        <div
                          key={p.wine_id}
                          className="rounded-xl border border-border bg-card p-3 card-lift"
                          data-testid={`ai-pairing-pick-${idx}`}
                        >
                          <div className="flex gap-3">
                            <span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-oro text-[10px] font-bold text-antracite">
                              {idx + 1}
                            </span>
                            <div className="min-w-0 flex-1">
                              <p className="font-serif text-sm font-semibold leading-tight">
                                {w.produttore}
                              </p>
                              <p className="truncate text-xs text-muted-foreground">
                                {w.nome} {w.annata}
                              </p>
                            </div>
                          </div>
                          <p className="mt-2 text-xs leading-relaxed text-antracite/85">
                            {p.reasoning}
                          </p>
                          <a
                            href={`/annuncio/${w.id}`}
                            data-testid={`ai-pairing-pick-link-${idx}`}
                            className="mt-2 inline-flex text-xs font-semibold text-bordeaux hover:underline"
                          >
                            Vedi annuncio →
                          </a>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 text-xs">
        <Badge variant="secondary">{filtered.length} risultati</Badge>
        {mode === "abbinamento" && q.trim() && (
          <Badge className="bg-bordeaux text-crema">
            <UtensilsCrossed className="mr-1 h-3 w-3" /> Abbinamento: {q}
          </Badge>
        )}
        {regione !== "Tutte" && <Badge className="bg-salvia text-crema">{regione}</Badge>}
        {tipo !== "Tutti" && <Badge className="bg-salvia text-crema">{tipo}</Badge>}
      </div>

      {loading ? (
        <div className="grid place-items-center py-20 text-muted-foreground">
          <Loader2 className="h-6 w-6 animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="grid place-items-center gap-3 rounded-2xl border border-dashed border-border bg-card py-20 text-center">
          <PackageOpen className="h-10 w-10 text-muted-foreground" />
          <div>
            <p className="font-serif text-xl">Nessuna bottiglia trovata</p>
            <p className="text-sm text-muted-foreground">Prova a rimuovere qualche filtro.</p>
          </div>
          <Button onClick={reset} variant="outline">
            Azzera filtri
          </Button>
        </div>
      ) : view === "grid" ? (
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
          {filtered.map((w) => (
            <WineCard key={w.id} wine={w} />
          ))}
        </div>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {filtered.map((w) => (
            <WineCard key={w.id} wine={w} variant="list" />
          ))}
        </div>
      )}
    </div>
  );
}
