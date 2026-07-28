"use client";

import { useMemo, useState } from "react";
import { Search, SlidersHorizontal, LayoutGrid, List, PackageOpen, UtensilsCrossed } from "lucide-react";
import type { Wine } from "@/data/wines";
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

export default function EsploraPageClient({ annunci }: { annunci: Wine[] }) {
  const [mode, setMode] = useState<Mode>("testo");
  const [q, setQ] = useState("");
  const [regione, setRegione] = useState("Tutte");
  const [tipo, setTipo] = useState("Tutti");
  const [prezzo, setPrezzo] = useState<[number, number]>([0, 1500]);
  const [sort, setSort] = useState("recenti");
  const [view, setView] = useState<"grid" | "list">("grid");

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    let r = annunci.filter((w) => {
      if (regione !== "Tutte" && w.regione !== regione) return false;
      if (tipo !== "Tutti" && w.tipo !== tipo) return false;
      if (w.prezzo < prezzo[0] || w.prezzo > prezzo[1]) return false;
      if (term) {
        if (mode === "testo") {
          if (!`${w.produttore} ${w.nome}`.toLowerCase().includes(term)) return false;
        } else {
          // I metadati di abbinamento sono indicizzati per vino, non per
          // annuncio: su dati reali `id` è lo slug dell'annuncio.
          const meta = getWineMeta(w.wineSlug ?? w.id);
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
  }, [annunci, q, mode, regione, tipo, prezzo, sort]);

  const reset = () => {
    setQ("");
    setRegione("Tutte");
    setTipo("Tutti");
    setPrezzo([0, 1500]);
  };

  // Catalogo vuoto e ricerca senza risultati sono due situazioni diverse:
  // suggerire "rimuovi qualche filtro" a chi non ne ha impostato nessuno
  // manderebbe a cercare un errore che non ha commesso.
  const catalogoVuoto = annunci.length === 0;

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

      {filtered.length === 0 ? (
        <div className="grid place-items-center gap-3 rounded-2xl border border-dashed border-border bg-card py-20 text-center">
          <PackageOpen className="h-10 w-10 text-muted-foreground" />
          {catalogoVuoto ? (
            <div>
              <p className="font-serif text-xl">Ancora nessuna bottiglia in vendita</p>
              <p className="text-sm text-muted-foreground">
                Appena qualcuno pubblicherà un annuncio, lo troverai qui.
              </p>
            </div>
          ) : (
            <>
              <div>
                <p className="font-serif text-xl">Nessuna bottiglia trovata</p>
                <p className="text-sm text-muted-foreground">Prova a rimuovere qualche filtro.</p>
              </div>
              <Button onClick={reset} variant="outline">
                Azzera filtri
              </Button>
            </>
          )}
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
