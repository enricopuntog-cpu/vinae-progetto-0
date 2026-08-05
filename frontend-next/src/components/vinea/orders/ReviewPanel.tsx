"use client";

import { useState } from "react";
import { Star } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import type { OrderReviewRecord } from "@/services/types";

function StelleInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
}) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="mt-1 flex gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button key={n} type="button" onClick={() => onChange(n)} aria-label={`${n} stelle`}>
            <Star
              className={`h-5 w-5 ${n <= value ? "fill-oro text-oro" : "text-muted-foreground"}`}
            />
          </button>
        ))}
      </div>
    </div>
  );
}

type Props = {
  esistente: OrderReviewRecord | null;
  inCorso: boolean;
  onInvia: (r: {
    voto: number;
    conformita: number;
    imballaggio: number;
    comunicazione: number;
    testo?: string | null;
  }) => Promise<string | null>;
};

/** Le stesse quattro dimensioni di `frontend/`, una recensione per ordine. */
export function ReviewPanel({ esistente, inCorso, onInvia }: Props) {
  const [voto, setVoto] = useState(esistente?.voto ?? 5);
  const [conformita, setConformita] = useState(esistente?.conformita ?? 5);
  const [imballaggio, setImballaggio] = useState(esistente?.imballaggio ?? 5);
  const [comunicazione, setComunicazione] = useState(esistente?.comunicazione ?? 5);
  const [testo, setTesto] = useState(esistente?.testo ?? "");
  const [errore, setErrore] = useState<string | null>(null);

  if (esistente) {
    return (
      <section className="rounded-2xl border border-oro/40 bg-oro/10 p-4">
        <p className="text-sm font-semibold">Recensione inviata</p>
        <div className="mt-2 flex flex-wrap gap-4 text-xs text-muted-foreground">
          <span>Generale {esistente.voto}/5</span>
          <span>Conformità {esistente.conformita}/5</span>
          <span>Imballaggio {esistente.imballaggio}/5</span>
          <span>Comunicazione {esistente.comunicazione}/5</span>
        </div>
        {esistente.testo && <p className="mt-3 text-sm italic">“{esistente.testo}”</p>}
      </section>
    );
  }

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="text-sm font-semibold">Lascia una recensione</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Aiuta la community valutando l&apos;esperienza. Si recensisce una volta sola.
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <StelleInput label="Voto generale" value={voto} onChange={setVoto} />
        <StelleInput label="Conformità descrizione" value={conformita} onChange={setConformita} />
        <StelleInput label="Imballaggio" value={imballaggio} onChange={setImballaggio} />
        <StelleInput label="Comunicazione" value={comunicazione} onChange={setComunicazione} />
      </div>
      <Textarea
        className="mt-3"
        rows={3}
        value={testo}
        onChange={(e) => setTesto(e.target.value)}
        placeholder="Un commento (facoltativo)…"
      />
      {errore && <p className="mt-2 text-xs text-red-700">{errore}</p>}
      <Button
        className="mt-3 bg-bordeaux hover:bg-bordeaux/90"
        disabled={inCorso}
        onClick={async () =>
          setErrore(
            await onInvia({ voto, conformita, imballaggio, comunicazione, testo: testo || null }),
          )
        }
      >
        {inCorso ? "Invio…" : "Pubblica recensione"}
      </Button>
    </section>
  );
}
