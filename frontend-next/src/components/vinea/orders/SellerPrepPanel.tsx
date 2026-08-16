"use client";

import { useState } from "react";
import { Camera, ClipboardCheck, Package } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { puoSpedire } from "@/lib/orders/seller-status";
import type { OrderRecord, VoceChecklist } from "@/services/types";

/** Le stesse quattro voci di frontend/, che qui vengono davvero salvate. */
const VOCI: ReadonlyArray<{ id: string; label: string }> = [
  { id: "foto_frontale", label: "Foto etichetta frontale" },
  { id: "foto_capsula", label: "Foto capsula e collo" },
  { id: "foto_livello", label: "Foto livello del vino" },
  { id: "foto_imballaggio", label: "Foto imballaggio finale" },
];

const CORRIERI = ["Corriere Vinea", "BRT", "DHL", "GLS"] as const;

type Props = {
  ordine: OrderRecord;
  inCorso: boolean;
  onPrepara: (checklist: VoceChecklist[]) => Promise<string | null>;
  onSpedisci: (corriere: string, tracking: string) => Promise<string | null>;
};

/**
 * Pannello «Prepara spedizione», lato venditore.
 *
 * Differenza dichiarata rispetto a `frontend/`: là il bottone «Genera
 * etichetta» simulava un numero di tracking e non produceva nulla. Qui la
 * preparazione è una transizione vera (`ordine_prepara_spedizione`) che salva
 * la checklist, e il numero di tracking lo inserisce il venditore — nessuna
 * etichetta viene prodotta, perché era simulazione e resta tale.
 */
export function SellerPrepPanel({ ordine, inCorso, onPrepara, onSpedisci }: Props) {
  const salvate = new Map(ordine.imballaggio_checklist.map((v) => [v.id, v.done]));
  const [spunte, setSpunte] = useState<Record<string, boolean>>(
    Object.fromEntries(VOCI.map((v) => [v.id, salvate.get(v.id) ?? false])),
  );
  const [corriere, setCorriere] = useState<string>(ordine.corriere ?? "Corriere Vinea");
  const [tracking, setTracking] = useState(ordine.tracking_number ?? "");
  const [errore, setErrore] = useState<string | null>(null);

  const complete = VOCI.every((v) => spunte[v.id]);
  const trackingValido = /^[A-Za-z0-9._-]{4,64}$/.test(tracking);

  const checklist = (): VoceChecklist[] =>
    VOCI.map((v) => ({ id: v.id, label: v.label, done: !!spunte[v.id] }));

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="mb-3 text-sm font-semibold">Prepara spedizione</p>

      <div className="space-y-4">
        {ordine.imballaggio_etichetta && (
          <div className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm">
            <Package className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" />
            <span>
              <span className="block font-medium">{ordine.imballaggio_etichetta}</span>
              <span className="block text-xs text-muted-foreground">
                Modalità dichiarata da te sull&apos;annuncio, congelata su questo ordine.
              </span>
            </span>
          </div>
        )}

        <div>
          <Label className="text-xs uppercase">Checklist fotografica</Label>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {VOCI.map((v) => (
              <label
                key={v.id}
                className="flex items-center gap-2 rounded-xl border border-border bg-secondary/40 p-2 text-sm"
              >
                <Checkbox
                  checked={!!spunte[v.id]}
                  onCheckedChange={(c) => setSpunte((s) => ({ ...s, [v.id]: !!c }))}
                />
                <Camera className="h-4 w-4 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate">{v.label}</span>
              </label>
            ))}
          </div>
        </div>

        {ordine.imballaggio_codice ? <BetaActionNotice tipo="spedizione" /> : null}

        <div className="grid gap-2 sm:grid-cols-2">
          <div>
            <Label className="text-xs uppercase">Corriere</Label>
            <Select value={corriere} onValueChange={setCorriere}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CORRIERI.map((c) => (
                  <SelectItem key={c} value={c}>
                    {c}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label className="text-xs uppercase">Numero tracking</Label>
            <Input
              value={tracking}
              onChange={(e) => setTracking(e.target.value)}
              placeholder="Es. VNA-4421-773"
            />
          </div>
        </div>

        {!complete && (
          <p className="flex items-center gap-1 text-xs text-muted-foreground">
            <ClipboardCheck className="h-3.5 w-3.5" /> Completa la checklist prima di spedire.
          </p>
        )}
        {errore && <p className="text-xs text-red-700">{errore}</p>}

        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            disabled={inCorso}
            onClick={async () => setErrore(await onPrepara(checklist()))}
          >
            Salva preparazione
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            disabled={inCorso || !complete || !trackingValido || !puoSpedire(ordine.stato)}
            onClick={async () => setErrore(await onSpedisci(corriere, tracking))}
          >
            {inCorso ? "Elaborazione…" : "Segna come spedito"}
          </Button>
        </div>
      </div>
    </section>
  );
}
