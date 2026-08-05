"use client";

import { AlertTriangle, CheckCircle2, Clock, Info, Truck } from "lucide-react";
import type { TrackingEventRecord, TrackingEventTipo } from "@/services/types";

const sfondo = (t: TrackingEventTipo): string => {
  switch (t) {
    case "spedizione":
      return "bg-blue-500/15 text-blue-700";
    case "consegna":
      return "bg-salvia/20 text-salvia";
    case "problema":
      return "bg-red-500/15 text-red-700";
    case "sistema":
      return "bg-bordeaux/10 text-bordeaux";
    default:
      return "bg-secondary text-antracite";
  }
};

const icona = (t: TrackingEventTipo) => {
  switch (t) {
    case "spedizione":
      return <Truck className="h-2.5 w-2.5" />;
    case "consegna":
      return <CheckCircle2 className="h-2.5 w-2.5" />;
    case "problema":
      return <AlertTriangle className="h-2.5 w-2.5" />;
    case "sistema":
      return <Info className="h-2.5 w-2.5" />;
    default:
      return <Clock className="h-2.5 w-2.5" />;
  }
};

/**
 * La timeline dell'ordine. Legge `tracking_events` e non `order_events`: la
 * seconda è audit forense con payload interni, questa è testo scritto per
 * essere letto da chi ha comprato o venduto.
 */
export function OrderTimeline({ eventi }: { eventi: TrackingEventRecord[] }) {
  if (eventi.length === 0) {
    return <p className="text-sm text-muted-foreground">Nessun evento ancora registrato.</p>;
  }

  return (
    <ol className="relative ml-2 space-y-4 border-l border-border pl-5">
      {eventi.map((e) => (
        <li key={e.id} className="relative">
          <span
            className={`absolute -left-[26px] top-1 grid h-4 w-4 place-items-center rounded-full ${sfondo(e.tipo)}`}
          >
            {icona(e.tipo)}
          </span>
          <p className="text-sm font-semibold">{e.titolo}</p>
          {e.descrizione && <p className="text-xs text-muted-foreground">{e.descrizione}</p>}
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {new Date(e.created_at).toLocaleString("it-IT", {
              day: "2-digit",
              month: "short",
              hour: "2-digit",
              minute: "2-digit",
            })}
            {e.luogo ? ` · ${e.luogo}` : ""}
          </p>
        </li>
      ))}
    </ol>
  );
}
