"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { validaIndirizzo, type CampoIndirizzo, type ErroriIndirizzo } from "@/lib/indirizzi/rubrica";
import type { Indirizzo, IndirizzoInput, Result } from "@/services/types";

const CAMPI: { id: CampoIndirizzo; label: string; facoltativo?: boolean; inputMode?: "numeric" | "tel" }[] = [
  { id: "destinatario", label: "Destinatario" },
  { id: "via", label: "Via e numero civico" },
  { id: "cap", label: "CAP", inputMode: "numeric" },
  { id: "citta", label: "Città" },
  { id: "provincia", label: "Provincia (sigla)" },
  { id: "telefono", label: "Telefono per il corriere", facoltativo: true, inputMode: "tel" },
  { id: "etichetta", label: "Etichetta (es. Casa)", facoltativo: true },
  { id: "note", label: "Note per la consegna", facoltativo: true },
];

/**
 * Modulo di un indirizzo della rubrica (nuovo o in modifica).
 *
 * Solo Italia: il Paese non si sceglie, lo assegna il database. I due
 * predefiniti si possono nascondere quando il contesto li decide (checkout:
 * consegna; vendita: ritiro).
 */
export function FormIndirizzo({
  iniziale,
  id,
  onSalva,
  onAnnulla,
  mostraPredefiniti = true,
  etichettaSalva = "Salva indirizzo",
}: {
  iniziale: IndirizzoInput;
  id: string | null;
  onSalva: (id: string | null, dati: IndirizzoInput) => Promise<Result<Indirizzo>>;
  onAnnulla?: () => void;
  mostraPredefiniti?: boolean;
  etichettaSalva?: string;
}) {
  const [dati, setDati] = useState(iniziale);
  const [errori, setErrori] = useState<ErroriIndirizzo>({});
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const prefisso = `indirizzo-${id ?? "nuovo"}`;

  const set = <K extends keyof IndirizzoInput>(campo: K, valore: IndirizzoInput[K]) => {
    setDati((correnti) => ({ ...correnti, [campo]: valore }));
    setErrori((correnti) => ({ ...correnti, [campo]: undefined }));
    setErrore(null);
  };

  const invia = async (evento: React.FormEvent) => {
    evento.preventDefault();
    if (inCorso) return;
    const trovati = validaIndirizzo(dati);
    setErrori(trovati);
    if (Object.keys(trovati).length > 0) return;
    setInCorso(true);
    const esito = await onSalva(id, dati);
    setInCorso(false);
    if (!esito.ok) setErrore(esito.error);
  };

  return (
    <form onSubmit={invia} noValidate className="space-y-3" data-testid="form-indirizzo">
      <p className="text-xs text-muted-foreground">Per ora Vinea spedisce solo in Italia.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        {CAMPI.map((c) => (
          <div key={c.id} className={c.id === "via" || c.id === "note" ? "sm:col-span-2" : undefined}>
            <Label htmlFor={`${prefisso}-${c.id}`}>
              {c.label}
              {c.facoltativo ? <span className="font-normal text-muted-foreground"> (facoltativo)</span> : null}
            </Label>
            <Input
              id={`${prefisso}-${c.id}`}
              value={dati[c.id]}
              inputMode={c.inputMode}
              maxLength={c.id === "note" ? 200 : c.id === "cap" ? 5 : c.id === "provincia" ? 2 : undefined}
              aria-invalid={errori[c.id] ? true : undefined}
              onChange={(e) => set(c.id, c.id === "provincia" ? e.target.value.toUpperCase() : e.target.value)}
            />
            {errori[c.id] ? <p className="mt-1 text-xs text-red-700">{errori[c.id]}</p> : null}
          </div>
        ))}
      </div>
      {mostraPredefiniti ? (
        <div className="space-y-2">
          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              className="mt-0.5 h-4 w-4 accent-bordeaux"
              checked={dati.predefinitoConsegna}
              onChange={(e) => set("predefinitoConsegna", e.target.checked)}
            />
            <span>Indirizzo di consegna predefinito</span>
          </label>
          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              className="mt-0.5 h-4 w-4 accent-bordeaux"
              checked={dati.predefinitoRitiro}
              onChange={(e) => set("predefinitoRitiro", e.target.checked)}
            />
            <span>
              Indirizzo di ritiro predefinito
              <span className="block text-xs text-muted-foreground">
                Usato dal corriere quando vendi con ritiro a domicilio.
              </span>
            </span>
          </label>
        </div>
      ) : null}
      {errore ? (
        <p role="alert" className="rounded-xl border border-red-500/30 bg-red-500/5 p-3 text-sm text-red-700">
          {errore}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={inCorso} className="bg-bordeaux hover:bg-bordeaux/90">
          {inCorso ? "Salvataggio…" : etichettaSalva}
        </Button>
        {onAnnulla ? (
          <Button type="button" variant="outline" onClick={onAnnulla} disabled={inCorso}>
            Annulla
          </Button>
        ) : null}
      </div>
    </form>
  );
}
