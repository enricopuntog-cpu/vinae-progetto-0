"use client";

// WI-016 — le proposte al catalogo inviate dall'utente, con la revoca. Si mostra solo se ce n'è almeno una: la revoca
// resta possibile anche se le proposte vengono spente dopo l'invio. Un errore di lettura non disturba la Cantina.

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { leggiProposteMie, ritiraProposta, PROPOSTE_PER_PAGINA, type CursoreProposte, type PropostaMia } from "@/lib/cantina/proposta-catalogo";

const STATI: Record<string, string> = {
  in_revisione: "In revisione da un curatore",
  in_attesa_di_invio: "Registrata, in attesa di invio",
  non_inviata: "Non inviata",
  accolta: "Accolta",
  gia_presente: "Già presente",
  rifiutata: "Non accolta",
  ritirata: "Ritirata",
};

export function ProposteInviate({ client, utenteId }: { client: SupabaseClient; utenteId: string }) {
  return <ElencoProposte key={utenteId} client={client} />;
}

function ElencoProposte({ client }: { client: SupabaseClient }) {
  const [proposte, setProposte] = useState<PropostaMia[]>([]);
  const [pagine, setPagine] = useState<CursoreProposte[]>([]);
  const [caricamento, setCaricamento] = useState(false);
  const cursore = pagine.at(-1);
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState<number | null>(null);
  const [giro, setGiro] = useState(0);

  useEffect(() => {
    let annullato = false;
    void leggiProposteMie(client, cursore).then((r) => {
      if (annullato) return;
      if (r.ok) setProposte(r.data);
      else if (cursore) {
        setProposte([]);
        setErrore(r.error);
      }
      setCaricamento(false);
    });
    return () => {
      annullato = true;
    };
  }, [client, cursore, giro]);

  if (proposte.length === 0 && !cursore) return null;

  const cambiaPagina = (prossime: CursoreProposte[]) => {
    setCaricamento(true);
    setErrore(null);
    setPagine(prossime);
  };
  const ultima = proposte.at(-1);

  const ritira = async (id: number) => {
    setInCorso(id);
    setErrore(null);
    const r = await ritiraProposta(client, id);
    setInCorso(null);
    if (!r.ok) setErrore(r.error);
    setGiro((g) => g + 1);
  };

  return (
    <details className="rounded-2xl border border-border bg-card p-3 text-sm" data-testid="proposte-inviate">
      <summary className="cursor-pointer font-semibold">Le tue proposte al catalogo</summary>
      <p className="mt-1 text-xs text-muted-foreground">
        Sono stati inviati solo i dati del vino. Puoi ritirare una proposta finché nessuno l&apos;ha decisa.
      </p>
      <ul className="mt-2 space-y-2">
        {proposte.map((p) => (
          <li key={p.id} className="flex flex-wrap items-center justify-between gap-2">
            <span className="min-w-0 text-xs">
              <b>
                {p.produttore} — {p.nome}
              </b>
              {p.annata ? ` ${p.annata}` : ""} · {STATI[p.stato] ?? "In revisione"}
            </span>
            {p.ritirabile ? (
              <Button type="button" size="sm" variant="outline" disabled={inCorso !== null || caricamento} onClick={() => void ritira(p.id)}>
                {inCorso === p.id ? "Ritiro…" : "Ritira"}
              </Button>
            ) : null}
          </li>
        ))}
      </ul>
      {cursore || proposte.length === PROPOSTE_PER_PAGINA ? (
        <div className="mt-2 flex gap-2">
          {cursore ? (
            <Button type="button" size="sm" variant="outline" disabled={caricamento || inCorso !== null}
              onClick={() => cambiaPagina(pagine.slice(0, -1))}>
              Precedenti
            </Button>
          ) : null}
          {ultima && proposte.length === PROPOSTE_PER_PAGINA ? (
            <Button type="button" size="sm" variant="outline" disabled={caricamento || inCorso !== null}
              onClick={() => cambiaPagina([...pagine, { id: ultima.id, inviataIl: ultima.inviataIl }])}>
              Successive
            </Button>
          ) : null}
        </div>
      ) : null}
      {errore ? (
        <p role="alert" className="mt-2 text-xs text-destructive">
          {errore}
        </p>
      ) : null}
    </details>
  );
}
