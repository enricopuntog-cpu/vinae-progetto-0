"use client";

// WI-016 — stima dalle vendite concluse, per la scheda del vino e per la Cantina. SPENTA per difetto: senza il sì della
// porta del database il comando non compare. La stima si chiede con un gesto, non a ogni scheda dell'elenco.

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { leggiStimaUtente, stimaUtenteDisponibile, type EsitoStimaUtente } from "@/lib/prezzi/porta-utente";

/** Una domanda sola, e solo con una sessione: la porta non è eseguibile da un visitatore. */
export function useStimaDisponibile(client: SupabaseClient | null): boolean {
  const [disponibile, setDisponibile] = useState(false);
  useEffect(() => {
    if (!client) return;
    let annullato = false;
    void client.auth.getSession().then(async ({ data }) => {
      const attiva = data.session ? await stimaUtenteDisponibile(client) : false;
      if (!annullato) setDisponibile(attiva);
    });
    return () => {
      annullato = true;
    };
  }, [client]);
  return disponibile;
}

const euro = (centesimi: number) => (centesimi / 100).toLocaleString("it-IT", { style: "currency", currency: "EUR" });

export function EsitoStima({ esito }: { esito: EsitoStimaUtente }) {
  if (esito.stato === "spenta") return null;
  const v = esito.valutazione;
  return (
    <div role="status" className="rounded-xl border border-border bg-card p-3 text-xs">
      {v.esito === "stima" ? (
        <p>
          Vendite concluse comparabili: mediana <b>{euro(v.medianaCents)}</b> (metà fra {euro(v.quartileBassoCents)} e{" "}
          {euro(v.quartileAltoCents)}), {v.comparabili} vendite, incertezza {v.incertezza}.
        </p>
      ) : (
        <p>
          Dati insufficienti: {v.comparabili} vendite concluse comparabili. Non mostriamo un prezzo quando non ci sono
          abbastanza vendite.
        </p>
      )}
      <p className="mt-1 text-muted-foreground">
        I prezzi richiesti negli annunci non sono vendite e non entrano nel calcolo. Non è una perizia né un&apos;offerta.
      </p>
    </div>
  );
}

export function StimaPrezzoVino({
  client,
  disponibile,
  wineSlug,
  formato,
}: {
  client: SupabaseClient | null;
  disponibile: boolean;
  wineSlug: string;
  formato: string;
}) {
  // la chiave lega l'esito al vino mostrato: cambiando scheda la stima di prima non resta a schermo
  const chiave = `${wineSlug}|${formato}`;
  const [letta, setLetta] = useState<{ chiave: string; esito: EsitoStimaUtente | null; errore: string | null } | null>(null);
  const [inCorso, setInCorso] = useState(false);
  if (!client || !disponibile) return null;
  const mostrata = letta?.chiave === chiave ? letta : null;

  const chiedi = async () => {
    setInCorso(true);
    const r = await leggiStimaUtente(client, wineSlug, formato, new Date());
    setLetta({ chiave, esito: r.ok ? r.data : null, errore: r.ok ? null : r.error });
    setInCorso(false);
  };

  return (
    <div className="space-y-2" data-testid="stima-prezzo">
      <Button type="button" size="sm" variant="outline" disabled={inCorso} onClick={() => void chiedi()}>
        {inCorso ? "Calcolo…" : "Stima dalle vendite concluse"}
      </Button>
      {mostrata?.esito ? <EsitoStima esito={mostrata.esito} /> : null}
      {mostrata?.errore ? (
        <p role="alert" className="text-xs text-destructive">
          {mostrata.errore}
        </p>
      ) : null}
    </div>
  );
}
