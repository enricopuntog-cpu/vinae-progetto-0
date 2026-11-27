"use client";

// WI-016 — richiesta di verifica di una bottiglia propria. Il proprietario dice che cosa legge sull'etichetta e quali
// evidenze ha; il modulo puro ne ricava SEGNALI e li mostra prima dell'invio. Nessuna foto viene caricata o inviata,
// nessun esito di autenticità esiste. Compare solo con le richieste accese (spente di default).

import { useId, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { analizzaEvidenze, ETICHETTE_SEGNALE, type Evidenze } from "@/lib/autenticita/analisi";
import { codiceErrore } from "@/lib/errore-per-log";

type Risposta = "si" | "no" | "";
const booleano = (r: Risposta): boolean | null => (r === "si" ? true : r === "no" ? false : null);

export function RichiestaVerificaBottiglia({
  client,
  bottleUnitId,
  produttore,
  annata,
}: {
  client: SupabaseClient;
  bottleUnitId: string;
  produttore: string;
  annata: number | null;
}) {
  const base = useId();
  const [aperta, setAperta] = useState(false);
  const [produttoreLetto, setProduttoreLetto] = useState("");
  const [annataLetta, setAnnataLetta] = useState("");
  const [documento, setDocumento] = useState<Risposta>("");
  const [foto, setFoto] = useState<Risposta>("");
  const [condizioni, setCondizioni] = useState(false);
  const [consenso, setConsenso] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  const [esito, setEsito] = useState<string | null>(null);
  const [errore, setErrore] = useState<string | null>(null);

  if (!aperta) {
    return (
      <Button type="button" size="sm" variant="ghost" className="text-xs" onClick={() => setAperta(true)} data-testid="verifica-apri">
        Richiedi una verifica
      </Button>
    );
  }
  if (esito) {
    return (
      <p role="status" className="text-xs text-muted-foreground">
        {esito}
      </p>
    );
  }

  const anno = /^[0-9]{4}$/.test(annataLetta.trim()) ? Number(annataLetta.trim()) : null;
  const evidenze: Evidenze = {
    dichiarato: { produttore, annata },
    etichetta: { produttore: produttoreLetto, annata: anno },
    documentoAcquisto: booleano(documento),
    fotoNitida: booleano(foto),
    condizioniDubbie: condizioni,
  };
  const analisi = analizzaEvidenze(evidenze);

  const invia = async () => {
    setInCorso(true);
    setErrore(null);
    try {
      const { data, error } = await client.rpc("cellar_verifica_autenticita_richiedi", {
        p_bottle_unit_id: bottleUnitId,
        p_anomalie: analisi.segnali,
        p_consenso: true,
      });
      if (error || (data !== "ricevuta" && data !== "gia_aperta")) {
        setErrore("Non è stato possibile inviare la richiesta. Riprova più tardi.");
      } else {
        setEsito(
          data === "gia_aperta"
            ? "Per questa bottiglia c'è già una verifica aperta."
            : "Richiesta ricevuta. Una persona la esaminerà: non è un giudizio sull'autenticità.",
        );
      }
    } catch (e) {
      console.error("[verifica-bottiglia] invio non riuscito:", codiceErrore(e));
      setErrore("Non è stato possibile inviare la richiesta. Riprova più tardi.");
    }
    setInCorso(false);
  };

  const scelta = (etichetta: string, valore: Risposta, cambia: (v: Risposta) => void, nome: string) => (
    <fieldset className="text-xs">
      <legend>{etichetta}</legend>
      <div className="flex gap-3">
        {(
          [
            ["si", "Sì"],
            ["no", "No"],
            ["", "Non lo so"],
          ] as [Risposta, string][]
        ).map(([v, t]) => (
          <label key={v || "ns"} className="flex items-center gap-1">
            <input type="radio" name={`${base}-${nome}`} checked={valore === v} onChange={() => cambia(v)} /> {t}
          </label>
        ))}
      </div>
    </fieldset>
  );

  return (
    <form
      className="w-full space-y-2 rounded-xl border border-border bg-card p-3 text-xs"
      data-testid="verifica-bottiglia"
      onSubmit={(e) => {
        e.preventDefault();
        if (consenso && analisi.segnali.length > 0 && !inCorso) void invia();
      }}
    >
      <p className="font-semibold">Verifica di questa bottiglia</p>
      <div>
        <Label htmlFor={`${base}-produttore`} className="text-[11px]">
          Produttore che leggi sull&apos;etichetta (facoltativo)
        </Label>
        <Input id={`${base}-produttore`} value={produttoreLetto} maxLength={160} onChange={(e) => setProduttoreLetto(e.target.value)} className="h-8 text-xs" />
      </div>
      <div>
        <Label htmlFor={`${base}-annata`} className="text-[11px]">
          Annata che leggi sull&apos;etichetta (facoltativa)
        </Label>
        <Input id={`${base}-annata`} value={annataLetta} maxLength={4} inputMode="numeric" onChange={(e) => setAnnataLetta(e.target.value)} className="h-8 text-xs" />
      </div>
      {scelta("Hai un documento di acquisto?", documento, setDocumento, "documento")}
      {scelta("Hai foto nitide dell'etichetta e della capsula?", foto, setFoto, "foto")}
      <label className="flex items-center gap-2">
        <input type="checkbox" checked={condizioni} onChange={(e) => setCondizioni(e.target.checked)} />
        Livello, capsula o etichetta mi sembrano da controllare
      </label>
      <div role="status" className="rounded-lg bg-muted/40 p-2">
        {analisi.segnali.length === 0 ? (
          <p>Nessun segnale da verificare con le informazioni indicate.</p>
        ) : (
          <ul className="list-disc pl-4">
            {analisi.segnali.map((s) => (
              <li key={s}>{ETICHETTE_SEGNALE[s]}</li>
            ))}
          </ul>
        )}
        <p className="mt-1 text-muted-foreground">Autenticità: non determinabile. {analisi.autenticita.motivo}</p>
      </div>
      <label className="flex items-start gap-2">
        <input type="checkbox" className="mt-0.5" checked={consenso} onChange={(e) => setConsenso(e.target.checked)} />
        <span>Acconsento a inviare questi soli segnali a Vinea per una verifica. Foto, note e prezzi non vengono inviati.</span>
      </label>
      <div className="flex gap-2">
        <Button type="submit" size="sm" className="rounded-full bg-bordeaux hover:bg-bordeaux/90" disabled={!consenso || analisi.segnali.length === 0 || inCorso}>
          {inCorso ? "Invio…" : "Invia la richiesta"}
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
