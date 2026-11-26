"use client";

// WI-008 — in Cantina, sotto la scheda di un vino: la scheda del catalogo che il PROPRIETARIO dice di intendere.
// Riusa la sorgente canonica, l'hook di ricerca e l'elenco dei candidati del wizard: niente preselezioni, gli omonimi
// restano distinti, la scelta entra solo con la conferma. Con il catalogo non disponibile e nessuna scelta salvata il
// componente non mostra nulla. Non tocca note, finestre di consumo, consigli o dati della bottiglia.

import { useId, useMemo, useState } from "react";
import Link from "next/link";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { ElencoCandidati } from "@/app/vendi/elenco-candidati";
import { ChiediAlSommelier } from "@/components/vinea/ChiediAlSommelier";
import { useRicercaCandidati } from "@/hooks/useRicercaCandidati";
import { rimuoviSchedaCatalogo, scegliSchedaCatalogo } from "@/lib/cantina/selezione-catalogo";
import { contestoRicercaDaCandidato } from "@/lib/phase10/sommelier-contesto-ui";
import { sorgenteCanonica } from "@/lib/vendi/ricerca-vini/canonico";
import { LWIN7 } from "@/lib/wine-intelligence/codice-scheda";

type Props = {
  client: SupabaseClient;
  wineSlug: string;
  produttore: string;
  nome: string;
  disponibile: boolean;
  scelta: string | null;
  onCambio: (codice: string | null) => void;
};

export function SelezioneCatalogoVino({ client, wineSlug, produttore, nome, disponibile, scelta, onCambio }: Props) {
  const sorgente = useMemo(() => sorgenteCanonica(client), [client]);
  const ricerca = useRicercaCandidati(sorgente);
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  const prefisso = `catalogo-${wineSlug}`;
  // Lo stesso vino può avere due schede (formati diversi): i radio non devono finire nello stesso gruppo.
  const gruppo = useId();
  const selezionato = ricerca.candidati.find((c) => c.id === ricerca.selezionato) ?? null;

  if (!scelta && !disponibile) return null;

  const conferma = async () => {
    const codice = selezionato?.canonico?.codice;
    if (!codice) return;
    setInCorso(true);
    setErrore(null);
    const esito = await scegliSchedaCatalogo(client, wineSlug, codice);
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    ricerca.azzera();
    onCambio(esito.data);
  };

  const rimuovi = async () => {
    setInCorso(true);
    setErrore(null);
    const esito = await rimuoviSchedaCatalogo(client, wineSlug);
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    onCambio(null);
  };

  const domanda = scelta ? contestoRicercaDaCandidato({ produttore, nome, canonico: { codice: scelta } }) : null;

  return (
    <div className="rounded-xl border border-border bg-card p-2 text-xs" data-testid={prefisso}>
      {scelta ? (
        <>
          <p>
            <span className="font-semibold">
              {LWIN7.test(scelta) ? `Scheda del catalogo scelta da te: LWIN ${scelta}.` : "Scheda del catalogo Vinea scelta da te."}
            </span>{" "}
            <span className="text-muted-foreground">
              È una tua indicazione, visibile solo a te: non è una verifica di Vinea e non modifica i dati del vino.
            </span>
          </p>
          <div className="mt-1.5 flex flex-wrap gap-2">
            {disponibile ? (
              <Link href={`/vino-catalogo/${scelta}`} prefetch={false} className="self-center underline" data-testid={`${prefisso}-scheda`}>
                Apri la scheda
              </Link>
            ) : null}
            {domanda && disponibile ? (
              <ChiediAlSommelier contesto={domanda} etichetta="Chiedi al Sommelier" testId={`${prefisso}-sommelier`} />
            ) : null}
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={inCorso}
              onClick={() => void rimuovi()}
              data-testid={`${prefisso}-rimuovi`}
            >
              Rimuovi il collegamento
            </Button>
          </div>
        </>
      ) : (
        <>
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={ricerca.fase === "in_corso"}
            onClick={() => {
              setErrore(null);
              void ricerca.cerca({ produttore, nome, annata: null, formato: null });
            }}
            data-testid={`${prefisso}-cerca`}
          >
            {ricerca.fase === "in_corso" ? "Cerco…" : "Cerca la scheda nel catalogo"}
          </Button>
          {ricerca.fase === "errore" ? (
            <p role="alert" className="mt-1.5 text-destructive">
              {ricerca.messaggio}
            </p>
          ) : null}
          {ricerca.fase === "fatta" && ricerca.candidati.length === 0 ? (
            <p className="mt-1.5 text-muted-foreground" data-testid={`${prefisso}-nessuna`}>
              Nessuna scheda del catalogo corrisponde a questo vino.
            </p>
          ) : null}
          {ricerca.fase === "fatta" && ricerca.candidati.length > 0 ? (
            <>
              <ElencoCandidati
                candidati={ricerca.candidati}
                sintesi={ricerca.sintesi}
                selezionato={ricerca.selezionato}
                onSeleziona={ricerca.seleziona}
                nomeGruppo={`${gruppo}-candidato`}
                prefissoTest={prefisso}
                testoNessuno="Nessuna di queste: non collego nulla"
              />
              <Button
                type="button"
                size="sm"
                className="mt-2 rounded-full bg-bordeaux hover:bg-bordeaux/90"
                disabled={!selezionato || inCorso}
                onClick={() => void conferma()}
                data-testid={`${prefisso}-conferma`}
              >
                È questo il mio vino
              </Button>
            </>
          ) : null}
        </>
      )}
      {errore ? (
        <p role="alert" className="mt-1.5 text-destructive">
          {errore}
        </p>
      ) : null}
    </div>
  );
}
