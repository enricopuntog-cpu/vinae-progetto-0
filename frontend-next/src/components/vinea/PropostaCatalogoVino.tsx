"use client";

// WI-011 — sotto la scheda di un vino in Cantina: proposta ESPLICITA dei dati enologici al catalogo condiviso.
// Compare solo con le proposte accese (spente di default). Nessuna casella preselezionata: senza consenso non si invia.

import { useId, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  inviaPropostaCatalogo,
  preparaProposta,
  type CampiProposta,
  type VinoPerProposta,
} from "@/lib/cantina/proposta-catalogo";

const CAMPI: { chiave: keyof CampiProposta; etichetta: string; massimo: number }[] = [
  { chiave: "produttore", etichetta: "Produttore", massimo: 160 },
  { chiave: "nome", etichetta: "Nome del vino", massimo: 200 },
  { chiave: "annata", etichetta: "Annata (vuota se non la conosci)", massimo: 4 },
  { chiave: "regione", etichetta: "Regione", massimo: 80 },
  { chiave: "denominazione", etichetta: "Denominazione", massimo: 160 },
];

export function PropostaCatalogoVino({
  client,
  wineSlug,
  vino,
}: {
  client: SupabaseClient;
  wineSlug: string;
  vino: VinoPerProposta;
}) {
  const prefisso = `proposta-${wineSlug}`;
  const base = useId();
  const [aperta, setAperta] = useState(false);
  const [consenso, setConsenso] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  const [inviata, setInviata] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  const [campi, setCampi] = useState<CampiProposta>(() => ({
    produttore: vino.produttore,
    nome: vino.nome,
    annata: vino.annata ? String(vino.annata) : "",
    regione: vino.regione,
    denominazione: vino.denominazione,
  }));

  if (inviata) {
    return (
      <p className="text-xs text-muted-foreground" role="status" data-testid={`${prefisso}-inviata`}>
        Proposta ricevuta. Un curatore la rivedrà prima che il catalogo cambi.
      </p>
    );
  }
  if (!aperta) {
    return (
      <Button
        type="button"
        size="sm"
        variant="ghost"
        className="text-xs"
        onClick={() => setAperta(true)}
        data-testid={`${prefisso}-apri`}
      >
        Proponi al catalogo Vinea
      </Button>
    );
  }

  const invia = async () => {
    const preparata = preparaProposta(vino, campi);
    if (!preparata.ok) {
      setErrore(preparata.error);
      return;
    }
    setInCorso(true);
    setErrore(null);
    const esito = await inviaPropostaCatalogo(client, wineSlug, preparata.data);
    setInCorso(false);
    if (esito.ok) setInviata(true);
    else setErrore(esito.error);
  };

  return (
    <form
      className="space-y-2 rounded-xl border border-border bg-card p-2 text-xs"
      data-testid={prefisso}
      onSubmit={(e) => {
        e.preventDefault();
        if (consenso && !inCorso) void invia();
      }}
    >
      <p className="font-semibold">Proponi questo vino al catalogo Vinea</p>
      {CAMPI.map((c) => (
        <div key={c.chiave}>
          <Label htmlFor={`${base}-${c.chiave}`} className="text-[11px]">
            {c.etichetta}
          </Label>
          <Input
            id={`${base}-${c.chiave}`}
            value={campi[c.chiave]}
            maxLength={c.massimo}
            inputMode={c.chiave === "annata" ? "numeric" : undefined}
            onChange={(e) => setCampi((p) => ({ ...p, [c.chiave]: e.target.value }))}
            className="h-8 text-xs"
          />
        </div>
      ))}
      <label className="flex items-start gap-2">
        <input
          type="checkbox"
          className="mt-0.5"
          checked={consenso}
          onChange={(e) => setConsenso(e.target.checked)}
          data-testid={`${prefisso}-consenso`}
        />
        <span>
          Acconsento a inviare questi soli dati del vino per il catalogo condiviso di Vinea. Note, foto, prezzi e posizione
          della bottiglia non vengono inviati.
        </span>
      </label>
      <div className="flex gap-2">
        <Button
          type="submit"
          size="sm"
          className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
          disabled={!consenso || inCorso}
          data-testid={`${prefisso}-invia`}
        >
          {inCorso ? "Invio…" : "Invia la proposta"}
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={() => setAperta(false)}>
          Annulla
        </Button>
      </div>
      {errore ? (
        <p role="alert" className="text-destructive">
          {errore}
        </p>
      ) : null}
    </form>
  );
}
