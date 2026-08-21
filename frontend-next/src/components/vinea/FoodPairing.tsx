"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { UtensilsCrossed, ThermometerSun, Wine as WineIcon, Timer, Search } from "lucide-react";
import { type PairingLevel, computeDrinkPhase } from "@/data/cellar";
import { useCercaMeta, useWineMeta } from "@/lib/wine-meta-context";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { useVinea } from "@/lib/vinea-store";

const LEVEL: Record<PairingLevel, string> = {
  ideale: "bg-bordeaux text-crema",
  ottimo: "bg-salvia/25 text-salvia",
  possibile: "bg-secondary text-antracite",
};

export function FoodPairingSection({ wineId }: { wineId: string }) {
  const meta = useWineMeta(wineId);

  return (
    <section className="rounded-2xl border border-border bg-card p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Cosa abbinare</p>
          <p className="mt-1 font-serif text-2xl">Abbinamenti gastronomici</p>
        </div>
        <CookingQueryDialog wineId={wineId} />
      </div>

      <div className="grid gap-3 md:grid-cols-2">
        {meta.foodPairings.map((p) => (
          <div
            key={p.piatto}
            className="flex items-start gap-3 rounded-xl border border-border bg-secondary/30 p-3"
          >
            <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-crema text-lg">
              {p.emoji}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="truncate font-semibold">{p.piatto}</p>
                <span
                  className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold capitalize ${LEVEL[p.livello]}`}
                >
                  {p.livello}
                </span>
              </div>
              <p className="text-xs text-muted-foreground">{p.categoria}</p>
              <p className="mt-1 text-xs">{p.note}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat icon={ThermometerSun} label="Temperatura" value={meta.servingTemperature} />
        <Stat
          icon={Timer}
          label="Decantazione"
          value={meta.decantingMinutes ? `${meta.decantingMinutes} min` : "Non necessaria"}
        />
        <Stat icon={WineIcon} label="Calice" value={meta.glassType} />
        <Stat icon={UtensilsCrossed} label="Occasione" value={meta.occasione ?? "Cena"} />
      </div>
    </section>
  );
}

function Stat({ icon: Icon, label, value }: { icon: typeof Search; label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border bg-card p-3">
      <p className="flex items-center gap-1 text-[10px] uppercase tracking-wide text-muted-foreground">
        <Icon className="h-3 w-3" /> {label}
      </p>
      <p className="mt-1 text-sm font-medium">{value}</p>
    </div>
  );
}

function CookingQueryDialog({ wineId }: { wineId: string }) {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const meta = useWineMeta(wineId);
  const risultato = useMemo(() => {
    if (!q.trim()) return null;
    const norm = q.toLowerCase();
    const match = meta.foodPairings.find(
      (p) => p.keywords.some((k) => norm.includes(k)) || p.piatto.toLowerCase().includes(norm),
    );
    return match ? { ok: true as const, match } : { ok: false as const };
  }, [q, meta]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          <UtensilsCrossed className="h-3.5 w-3.5" /> Cosa stai preparando?
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">Verifica abbinamento</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          Scrivi il piatto: ti diremo se questa bottiglia è adatta.
        </p>
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="es. brasato, ostriche, ragù…"
        />
        {risultato &&
          (risultato.ok ? (
            <div className="rounded-xl border border-salvia/40 bg-salvia/10 p-3 text-sm">
              <p className="font-semibold text-salvia">
                Questo vino è adatto ({risultato.match.livello}).
              </p>
              <p className="mt-1 text-xs text-muted-foreground">{risultato.match.note}</p>
            </div>
          ) : (
            <div className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm">
              <p className="font-semibold">Valuta una bottiglia diversa dalla tua cantina.</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Non troviamo un abbinamento forte con questo vino.
              </p>
            </div>
          ))}
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Chiudi
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// Trova un vino della cantina compatibile con un piatto
export function FindWineFromCellar() {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const { bottiglieCantina, viniCantina, prezzoNascosto } = useVinea();
  const cercaMeta = useCercaMeta();

  const risultati = useMemo(() => {
    if (!q.trim()) return [];
    const norm = q.toLowerCase();
    return bottiglieCantina
      .map((b) => {
        // I vini della cantina arrivano dal database insieme alle bottiglie
        // (Fase 6c-2), non più dal catalogo mock: l'indice è lo slug del vino.
        const wine = viniCantina.find((w) => (w.wineSlug ?? w.id) === b.wineVintageId);
        if (!wine) return null;
        const meta = cercaMeta(b.wineVintageId);
        const phase = computeDrinkPhase(meta);
        const match = meta.foodPairings.find(
          (p) => p.keywords.some((k) => norm.includes(k)) || p.piatto.toLowerCase().includes(norm),
        );
        if (!match) return null;
        // priorità: pronte + non riservate + con quantità
        const priority =
          (phase === "ideale"
            ? 100
            : phase === "pronto"
              ? 80
              : phase === "presto"
                ? 60
                : phase === "quasi"
                  ? 40
                  : 10) +
          (b.saleStatus !== "in_vendita" && !prezzoNascosto.has(wine.id) ? 15 : 0) +
          (b.quantita > 0 ? 5 : -100) +
          (match.livello === "ideale" ? 20 : match.livello === "ottimo" ? 10 : 0);
        return { wine, bottle: b, match, phase, priority };
      })
      .filter((x): x is NonNullable<typeof x> => !!x)
      .sort((a, b) => b.priority - a.priority)
      .slice(0, 5);
  }, [q, bottiglieCantina, viniCantina, prezzoNascosto, cercaMeta]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="text-foreground">
          <Search className="h-3.5 w-3.5" /> Ricerca per abbinamento cibo–vino
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">Cosa stai per cucinare?</DialogTitle>
        </DialogHeader>
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="es. bistecca, risotto ai funghi…"
        />
        <div className="space-y-2">
          {risultati.length === 0 && q.trim() && (
            <p className="text-sm text-muted-foreground">
              Nessuna bottiglia della cantina sembra particolarmente adatta.
            </p>
          )}
          {risultati.map((r) => (
            <Link
              key={r.bottle.bottleId}
              href={`/annuncio/${r.wine.id}`}
              onClick={() => setOpen(false)}
              className="flex items-center gap-3 rounded-xl border border-border p-2 hover:bg-secondary/40"
            >
              <img src={r.wine.immagini[0]} alt="" className="h-14 w-11 rounded object-cover" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-serif text-sm font-semibold">
                  {r.wine.nome} {r.wine.annata}
                </p>
                <p className="text-xs text-muted-foreground">
                  Consigliato per: {r.match.piatto} — {r.match.livello}
                </p>
              </div>
            </Link>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
