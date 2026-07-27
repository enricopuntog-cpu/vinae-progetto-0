"use client";

import { useMemo, useState } from "react";
import { Info, Sparkles, Pencil, Bell } from "lucide-react";
import {
  computeDrinkPhase,
  phaseLabel,
  phaseShort,
  phaseColor,
  sourceLabel,
  DRINK_WINDOW_DISCLAIMER,
  getWineMeta,
  type DrinkPhase,
  type WineVintageMeta,
} from "@/data/cellar";
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
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { useVinea } from "@/lib/vinea-store";

const PHASES: DrinkPhase[] = ["attesa", "quasi", "pronto", "ideale", "presto"];

export function DrinkBadge({ wineId, className = "" }: { wineId: string; className?: string }) {
  const { drinkWindowOverrides } = useVinea();
  const base = getWineMeta(wineId);
  const meta = mergeMeta(base, drinkWindowOverrides[wineId]);
  const phase = computeDrinkPhase(meta);
  if (phase === "none") return null;
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold ${phaseColor[phase]} ${className}`}
    >
      <Sparkles className="h-2.5 w-2.5" /> {phaseShort[phase]}
    </span>
  );
}

export function DrinkWindowSection({ wineId }: { wineId: string }) {
  const { drinkWindowOverrides } = useVinea();
  const base = getWineMeta(wineId);
  const meta = mergeMeta(base, drinkWindowOverrides[wineId]);
  const phase = computeDrinkPhase(meta);
  const year = new Date().getFullYear();

  return (
    <section className="rounded-2xl border border-border bg-card p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Quando berlo</p>
          <p className="mt-1 font-serif text-2xl">
            {meta.drinkWindowStart && meta.drinkWindowEnd ? (
              <>
                Finestra{" "}
                <b>
                  {meta.drinkWindowStart}–{meta.drinkWindowEnd}
                </b>
              </>
            ) : (
              "Finestra non disponibile"
            )}
          </p>
          {meta.peakStart && meta.peakEnd && (
            <p className="text-sm text-muted-foreground">
              Momento ideale:{" "}
              <b>
                {meta.peakStart}–{meta.peakEnd}
              </b>
            </p>
          )}
        </div>
        <div className="flex flex-col items-end gap-2">
          <span
            className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold ${phaseColor[phase]}`}
          >
            {phaseLabel[phase]}
          </span>
          <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
            {sourceLabel[meta.source]} · Fiducia {meta.confidence}
          </span>
        </div>
      </div>

      {phase !== "none" && (
        <div className="mt-5">
          <PhaseTimeline current={phase} />
          <p className="mt-2 text-center text-xs text-muted-foreground">Anno corrente: {year}</p>
        </div>
      )}

      <div className="mt-4 flex items-start gap-2 rounded-xl bg-secondary/60 p-3 text-xs text-muted-foreground">
        <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
        <span>{DRINK_WINDOW_DISCLAIMER}</span>
      </div>

      <div className="mt-4 flex flex-wrap gap-2">
        <PersonalizeDialog wineId={wineId} meta={meta} />
        <Button
          size="sm"
          variant="outline"
          onClick={() => toast.success("Ti ricorderemo quando questa bottiglia sarà pronta.")}
        >
          <Bell className="h-3.5 w-3.5" /> Ricordamelo
        </Button>
      </div>
    </section>
  );
}

function PhaseTimeline({ current }: { current: DrinkPhase }) {
  const activeIdx = PHASES.indexOf(current) === -1 ? 2 : PHASES.indexOf(current);
  return (
    <ol className="grid grid-cols-5 gap-1" aria-label="Fasi di consumo">
      {PHASES.map((p, i) => {
        const active = i === activeIdx;
        const passed = i < activeIdx;
        return (
          <li key={p} className="flex flex-col items-center gap-1">
            <span
              className={`h-1.5 w-full rounded-full ${
                active ? "bg-bordeaux" : passed ? "bg-oro" : "bg-secondary"
              }`}
            />
            <span
              className={`text-center text-[10px] leading-tight ${active ? "font-semibold text-bordeaux" : "text-muted-foreground"}`}
            >
              {p === "attesa"
                ? "Troppo giovane"
                : p === "quasi"
                  ? "Quasi pronto"
                  : p === "pronto"
                    ? "Pronto"
                    : p === "ideale"
                      ? "Ideale"
                      : "Bere presto"}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

function PersonalizeDialog({ wineId, meta }: { wineId: string; meta: WineVintageMeta }) {
  const { setDrinkWindowOverride } = useVinea();
  const [open, setOpen] = useState(false);
  const [s, setS] = useState(String(meta.drinkWindowStart ?? ""));
  const [e, setE] = useState(String(meta.drinkWindowEnd ?? ""));
  const [ps, setPs] = useState(String(meta.peakStart ?? ""));
  const [pe, setPe] = useState(String(meta.peakEnd ?? ""));
  const [pref, setPref] = useState<"giovane" | "equilibrato" | "evoluto">("equilibrato");
  const [nota, setNota] = useState("");

  const salva = () => {
    setDrinkWindowOverride(wineId, {
      drinkWindowStart: s ? Number(s) : undefined,
      drinkWindowEnd: e ? Number(e) : undefined,
      peakStart: ps ? Number(ps) : undefined,
      peakEnd: pe ? Number(pe) : undefined,
      preferenza: pref,
      nota: nota || undefined,
    });
    toast.success("Finestra personalizzata salvata");
    setOpen(false);
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" className="bg-bordeaux hover:bg-bordeaux/90">
          <Pencil className="h-3.5 w-3.5" /> Personalizza finestra
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">
            Personalizza finestra di consumo
          </DialogTitle>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Inizio</Label>
              <Input type="number" value={s} onChange={(x) => setS(x.target.value)} />
            </div>
            <div>
              <Label>Fine</Label>
              <Input type="number" value={e} onChange={(x) => setE(x.target.value)} />
            </div>
            <div>
              <Label>Picco inizio</Label>
              <Input type="number" value={ps} onChange={(x) => setPs(x.target.value)} />
            </div>
            <div>
              <Label>Picco fine</Label>
              <Input type="number" value={pe} onChange={(x) => setPe(x.target.value)} />
            </div>
          </div>
          <div>
            <Label className="mb-1 block">Preferenza personale</Label>
            <div className="flex gap-2">
              {(["giovane", "equilibrato", "evoluto"] as const).map((k) => (
                <button
                  key={k}
                  onClick={() => setPref(k)}
                  className={`rounded-full border px-3 py-1 text-xs capitalize ${pref === k ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
                >
                  {k}
                </button>
              ))}
            </div>
          </div>
          <div>
            <Label>Nota privata</Label>
            <Textarea
              rows={3}
              value={nota}
              onChange={(x) => setNota(x.target.value)}
              placeholder="Es. da aprire per l'anniversario."
            />
          </div>
          <p className="text-[11px] text-muted-foreground">
            Il tuo override resta separato dal dato editoriale.
          </p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Annulla
          </Button>
          <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={salva}>
            Salva
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function mergeMeta(
  base: WineVintageMeta,
  override?: {
    drinkWindowStart?: number;
    drinkWindowEnd?: number;
    peakStart?: number;
    peakEnd?: number;
  },
): WineVintageMeta {
  if (!override) return base;
  return {
    ...base,
    source: "personal",
    confidence: "alta",
    drinkWindowStart: override.drinkWindowStart ?? base.drinkWindowStart,
    drinkWindowEnd: override.drinkWindowEnd ?? base.drinkWindowEnd,
    peakStart: override.peakStart ?? base.peakStart,
    peakEnd: override.peakEnd ?? base.peakEnd,
  };
}

export function useWinePhase(wineId: string) {
  const { drinkWindowOverrides } = useVinea();
  return useMemo(() => {
    const meta = mergeMeta(getWineMeta(wineId), drinkWindowOverrides[wineId]);
    return { meta, phase: computeDrinkPhase(meta) };
  }, [wineId, drinkWindowOverrides]);
}