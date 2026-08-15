"use client";

import { useCallback, useMemo, useState } from "react";
import Link from "next/link";
import {
  Search,
  SlidersHorizontal,
  LayoutGrid,
  List,
  Loader2,
  PackageOpen,
  RefreshCw,
  Sparkles,
  UtensilsCrossed,
} from "lucide-react";
import type { Wine } from "@/data/wines";
import { useCercaMeta } from "@/lib/wine-meta-context";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createSupabaseAiService } from "@/services/phase10/supabase-ai-service";
import { risolviScelte, type SceltaRisolta } from "@/lib/phase10/abbinamento";
import { AiTransparencyLabel } from "@/components/vinea/AiTransparencyLabel";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { AI_UI, AZIONI_IA_ABILITATE } from "@/config/features";
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
  const abbinamentoAttivo = AI_UI.abbinamento && mode === "abbinamento";
  const [q, setQ] = useState("");
  const [regione, setRegione] = useState("Tutte");
  const [tipo, setTipo] = useState("Tutti");
  const [prezzo, setPrezzo] = useState<[number, number]>([0, 1500]);
  const [sort, setSort] = useState("recenti");
  const [view, setView] = useState<"grid" | "list">("grid");
  const cercaMeta = useCercaMeta();

  // Abbinamento AI (10c). Il filtro per parola chiave qui sopra resta: è quello
  // che risponde mentre si digita, senza rete e senza costo. Il pannello è un
  // secondo strumento sulla stessa domanda, e si aziona solo se richiesto —
  // com'è in `frontend/`, dove nessuna battuta parte da sola.
  const aiService = useMemo(
    () =>
      AI_UI.abbinamento && AZIONI_IA_ABILITATE
        ? createSupabaseAiService(getSupabaseClient())
        : null,
    [],
  );
  const [aiScelte, setAiScelte] = useState<SceltaRisolta[]>([]);
  const [aiIntro, setAiIntro] = useState("");
  const [aiInCorso, setAiInCorso] = useState(false);
  const [aiErrore, setAiErrore] = useState<string | null>(null);
  const [aiPerQuery, setAiPerQuery] = useState("");
  const [aiBloccata, setAiBloccata] = useState(false);

  const aggiornaQuery = (valore: string) => {
    setQ(valore);
    setAiBloccata(false);
    setAiErrore(null);
  };

  const chiediAbbinamento = useCallback(async () => {
    const query = q.trim();
    if (!query || aiInCorso) return;
    if (!AZIONI_IA_ABILITATE || !aiService) {
      setAiBloccata(true);
      setAiErrore(null);
      return;
    }
    setAiInCorso(true);
    setAiBloccata(false);
    setAiErrore(null);
    setAiPerQuery(query);
    try {
      // Nessun catalogo nel corpo: con la decisione 7.8 lo risolve la function
      // da `public_listings`. È la differenza dichiarata rispetto a
      // `frontend/src/routes/esplora.tsx:101-110`, che manda diciotto voci di
      // un file statico e fa ragionare il modello su dati finti.
      const esito = await aiService.abbinamento(query);
      if (esito.ok) {
        setAiIntro(esito.data.intro);
        setAiScelte(risolviScelte(esito.data.scelte, annunci));
      } else {
        setAiErrore(esito.error);
        setAiScelte([]);
      }
    } finally {
      setAiInCorso(false);
    }
  }, [aiInCorso, aiService, annunci, q]);

  // I risultati valgono per la domanda che li ha prodotti: cambiata quella, o
  // uscita la modalità abbinamento, non si mostrano più.
  //
  // `frontend/` lo ottiene con un effetto che azzera tre stati
  // (`frontend/src/routes/esplora.tsx:122-129`). Qui la stessa cosa è una
  // derivazione, e non per gusto: la regola `set-state-in-effect` della
  // configurazione ESLint di Next 16 rifiuta un `setState` sincrono dentro un
  // effetto, e ha ragione — quell'effetto fa un secondo render a ogni battuta
  // digitata per cancellare qualcosa che si può semplicemente non disegnare.
  const risultatiValidi = abbinamentoAttivo && q.trim() === aiPerQuery;

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    let r = annunci.filter((w) => {
      if (regione !== "Tutte" && w.regione !== regione) return false;
      if (tipo !== "Tutti" && w.tipo !== tipo) return false;
      if (w.prezzo < prezzo[0] || w.prezzo > prezzo[1]) return false;
      if (term) {
        if (!abbinamentoAttivo) {
          if (!`${w.produttore} ${w.nome}`.toLowerCase().includes(term)) return false;
        } else {
          // I metadati di abbinamento sono indicizzati per vino, non per
          // annuncio: su dati reali `id` è lo slug dell'annuncio.
          const meta = cercaMeta(w.wineSlug ?? w.id);
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
  }, [annunci, q, abbinamentoAttivo, regione, tipo, prezzo, sort, cercaMeta]);

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
          {abbinamentoAttivo ? (
            <UtensilsCrossed className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-bordeaux" />
          ) : (
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          )}
          <Input
            value={q}
            onChange={(e) => aggiornaQuery(e.target.value)}
            data-testid="esplora-search-input"
            placeholder={
              abbinamentoAttivo
                ? "Cosa stai preparando? es. brasato, ostriche, risotto…"
                : "Cerca produttore, denominazione, annata…"
            }
            className="pl-10 h-11 rounded-full bg-card"
          />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {AI_UI.abbinamento && (
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
          )}
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

      {abbinamentoAttivo && (
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="mr-1 text-xs text-muted-foreground">Suggerimenti:</span>
          {suggerimenti.map((s) => {
            const active = q.toLowerCase() === s.toLowerCase();
            return (
              <button
                key={s}
                onClick={() => aggiornaQuery(s.toLowerCase())}
                className={`rounded-full border px-2.5 py-1 text-[11px] ${active ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card hover:bg-secondary"}`}
              >
                {s}
              </button>
            );
          })}
        </div>
      )}

      {abbinamentoAttivo && q.trim() && (
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
                <AiTransparencyLabel superficie="abbinamento" />
              </div>
            </div>
            <Button
              data-testid="ai-pairing-ask-btn"
              size="sm"
              onClick={() => void chiediAbbinamento()}
              disabled={aiInCorso || !q.trim()}
              className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
            >
              {aiInCorso ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> Analisi…
                </>
              ) : risultatiValidi && aiScelte.length ? (
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

          {aiBloccata && <BetaActionNotice tipo="ia" className="mt-3" />}

          {risultatiValidi && aiErrore && (
            <p
              className="mt-3 rounded-xl bg-destructive/10 px-3 py-2 text-xs text-destructive"
              data-testid="ai-pairing-error"
            >
              {aiErrore}
            </p>
          )}

          {risultatiValidi && aiScelte.length > 0 && (
            <div className="mt-4 space-y-3" data-testid="ai-pairing-results">
              {aiIntro && <p className="text-sm italic text-antracite/85">{aiIntro}</p>}
              <div className="grid gap-3 md:grid-cols-3">
                {aiScelte.map((scelta, indice) => (
                  <div
                    key={scelta.annuncio.id}
                    className="rounded-xl border border-border bg-card p-3 card-lift"
                    data-testid={`ai-pairing-pick-${indice}`}
                  >
                    <div className="flex gap-3">
                      <span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-oro text-[10px] font-bold text-antracite">
                        {indice + 1}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="font-serif text-sm font-semibold leading-tight">
                          {scelta.annuncio.produttore}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                          {scelta.annuncio.nome} {scelta.annuncio.annata}
                        </p>
                      </div>
                    </div>
                    <p className="mt-2 text-xs leading-relaxed text-antracite/85">
                      {scelta.motivazione}
                    </p>
                    <Link
                      href={scelta.annuncio.detailHref ?? `/annuncio/${scelta.annuncio.id}`}
                      data-testid={`ai-pairing-pick-link-${indice}`}
                      className="mt-2 inline-flex text-xs font-semibold text-bordeaux hover:underline"
                    >
                      Vedi annuncio →
                    </Link>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 text-xs">
        <Badge variant="secondary">{filtered.length} risultati</Badge>
        {abbinamentoAttivo && q.trim() && (
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
