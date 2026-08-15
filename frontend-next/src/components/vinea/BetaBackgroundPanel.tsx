"use client";

import { useState } from "react";
import { ImageIcon, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";

const SCELTE = [
  { id: "ritaglio", titolo: "Solo ritaglio", nota: "Mantiene uno sfondo neutro" },
  { id: "chiaro", titolo: "Set chiaro", nota: "Fondale editoriale luminoso" },
  { id: "cantina", titolo: "Cantina", nota: "Ambientazione editoriale Vinea" },
] as const;

export const BetaBackgroundPanel = ({ haFoto }: { haFoto: boolean }) => {
  const [scelta, setScelta] = useState("ritaglio");
  const [bloccata, setBloccata] = useState(false);

  return (
    <section
      className="rounded-2xl border border-bordeaux/20 bg-bordeaux/5 p-4"
      data-testid="ai-background-panel"
    >
      <div className="flex items-start gap-2">
        <Sparkles className="mt-0.5 h-5 w-5 text-bordeaux" />
        <div>
          <h3 className="font-serif text-lg">Miglioramento sfondo con IA</h3>
          <p className="text-xs text-muted-foreground">
            Esamina il flusso futuro senza elaborare fotografie.
          </p>
        </div>
      </div>
      <RadioGroup
        value={scelta}
        onValueChange={(valore) => {
          setScelta(valore);
          setBloccata(false);
        }}
        className="mt-3 grid gap-2 sm:grid-cols-3"
      >
        {SCELTE.map((voce) => (
          <Label
            key={voce.id}
            htmlFor={`sfondo-${voce.id}`}
            className="flex cursor-pointer gap-2 rounded-xl border border-border bg-card p-3"
          >
            <RadioGroupItem id={`sfondo-${voce.id}`} value={voce.id} />
            <span>
              <span className="block text-sm font-semibold">{voce.titolo}</span>
              <span className="block text-[11px] font-normal text-muted-foreground">
                {voce.nota}
              </span>
            </span>
          </Label>
        ))}
      </RadioGroup>
      <Button
        type="button"
        variant="outline"
        disabled={!haFoto}
        onClick={() => setBloccata(true)}
        className="mt-3"
        data-testid="ai-background-action"
      >
        <ImageIcon className="h-4 w-4" /> Prepara il set fotografico IA
      </Button>
      {!haFoto ? (
        <p className="mt-2 text-xs text-muted-foreground">
          Carica almeno una fotografia per esaminare il comando.
        </p>
      ) : null}
      {bloccata ? <BetaActionNotice tipo="ia" className="mt-3" /> : null}
    </section>
  );
};
