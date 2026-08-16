"use client";

import { useState } from "react";
import { Handshake, PackageCheck, Truck, type LucideIcon } from "lucide-react";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";

const OPZIONI: ReadonlyArray<{ id: string; titolo: string; nota: string; icon: LucideIcon }> = [
  { id: "corriere", titolo: "Corriere assicurato", nota: "Preferenza beta", icon: Truck },
  { id: "ritiro", titolo: "Ritiro a mano", nota: "Da concordare", icon: Handshake },
  { id: "punto", titolo: "Punto Vinea", nota: "Dati locali simulati", icon: PackageCheck },
];

export const BetaDeliverySelector = () => {
  const [selezionata, setSelezionata] = useState<string | null>(null);

  return (
    <div className="space-y-3">
      <div className="grid gap-3 md:grid-cols-2">
        {OPZIONI.map(({ id, titolo, nota, icon: Icon }) => (
          <button
            key={id}
            type="button"
            aria-pressed={selezionata === id}
            onClick={() => setSelezionata(id)}
            className={`rounded-xl border p-3 text-left ${
              selezionata === id ? "border-bordeaux bg-bordeaux/5" : "border-border"
            }`}
          >
            <span className="flex items-center gap-2 font-serif text-base">
              <Icon className="h-4 w-4 text-bordeaux" /> {titolo}
            </span>
            <span className="mt-1 block text-xs text-muted-foreground">{nota}</span>
          </button>
        ))}
      </div>
      {selezionata ? <BetaActionNotice tipo="spedizione" /> : null}
    </div>
  );
};
