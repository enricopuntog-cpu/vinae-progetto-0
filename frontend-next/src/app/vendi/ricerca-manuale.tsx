"use client";

// WI-006A — «Cerca tra i vini di Vinea» nel passo Identificazione, per chi
// compila a mano. Usa i campi che il wizard già mostra (produttore, nome,
// annata, formato): non duplica gli input. La ricerca parte solo dal pulsante,
// l'elenco è lo stesso della fotografia, e i dati entrano nel wizard solo con
// «Usa questo vino». Scegliere «nessuno» o ignorare il blocco lascia i campi
// com'erano: nessun vino viene creato, modificato o fuso.

import { useId, useState } from "react";
import { Loader2, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useRicercaCandidati } from "@/hooks/useRicercaCandidati";
import type { CandidatoValutato, SorgenteCandidati } from "@/lib/vendi/foto-etichetta/candidati";
import type { CampiConfermati } from "@/hooks/useFotoEtichetta";
import { ElencoCandidati } from "./elenco-candidati";

export type ValoriRicerca = {
  produttore: string;
  nome: string;
  annata: string;
  formato: string;
};

type Props = {
  sorgente: SorgenteCandidati;
  valori: ValoriRicerca;
  applica: (campi: CampiConfermati, candidato: CandidatoValutato) => void;
};

const chiaveDi = (v: ValoriRicerca) =>
  [v.produttore.trim(), v.nome.trim(), v.annata.trim(), v.formato].join("|");

export function RicercaManuale({ sorgente, valori, applica }: Props) {
  const base = useId();
  const ricerca = useRicercaCandidati(sorgente);
  const [chiaveCercata, setChiaveCercata] = useState<string | null>(null);
  const [applicato, setApplicato] = useState(false);

  const chiave = chiaveDi(valori);
  // Cambiare i campi dopo una ricerca rende superato l'elenco: non va usato.
  // Dopo «Usa questo vino» sono i campi stessi a cambiare (ortografia del vino
  // scelto, annata): non è una modifica dell'utente e la conferma resta visibile.
  const superata = ricerca.fase !== "ferma" && chiaveCercata !== chiave && !applicato;
  const puoCercare = Boolean(valori.produttore.trim() || valori.nome.trim());
  const scelto = ricerca.candidati.find((c) => c.id === ricerca.selezionato) ?? null;

  const cerca = () => {
    const annata = Number.parseInt(valori.annata, 10);
    setChiaveCercata(chiave);
    setApplicato(false);
    void ricerca.cerca({
      produttore: valori.produttore,
      nome: valori.nome,
      annata: Number.isInteger(annata) ? annata : null,
      formato: valori.formato || null,
    });
  };

  return (
    <section
      className="rounded-2xl border border-border bg-card p-4"
      aria-labelledby={`${base}-titolo`}
      data-testid="ricerca-manuale"
    >
      <h3 id={`${base}-titolo`} className="font-serif text-base leading-tight">
        Cerca tra i vini di Vinea
      </h3>
      <p className="text-[11px] text-muted-foreground">
        Scrivi produttore e nome nei campi qui sotto, poi cerca: se il vino c&apos;è già puoi
        riusarne i dati. Altrimenti continua a compilare a mano.
      </p>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={!puoCercare || ricerca.fase === "in_corso"}
          onClick={cerca}
          data-testid="ricerca-manuale-cerca-btn"
        >
          {ricerca.fase === "in_corso" ? (
            <>
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> Cerco…
            </>
          ) : (
            <>
              <Search className="h-3.5 w-3.5" /> Cerca nei vini di Vinea
            </>
          )}
        </Button>
        {!puoCercare && (
          <span className="text-[11px] text-muted-foreground">
            Compila almeno il produttore o il nome.
          </span>
        )}
      </div>

      {superata && ricerca.fase !== "in_corso" && (
        <p role="status" className="mt-2 text-xs text-muted-foreground" data-testid="ricerca-manuale-superata">
          I campi sono cambiati dopo la ricerca: cerca di nuovo per vedere i vini corrispondenti.
        </p>
      )}

      {!superata && ricerca.fase === "errore" && (
        <p role="alert" className="mt-2 text-xs text-destructive" data-testid="ricerca-manuale-errore">
          {ricerca.messaggio} Puoi continuare a compilare a mano.
        </p>
      )}
      {!superata && ricerca.fase === "fatta" && ricerca.candidati.length === 0 && (
        <p className="mt-2 text-xs" data-testid="ricerca-manuale-nessuno-trovato">
          Nessun vino corrispondente su Vinea. Continua a compilare a mano: è normale per i vini
          non ancora presenti.
        </p>
      )}
      {!superata && ricerca.fase === "fatta" && ricerca.candidati.length > 0 && (
        <>
          <ElencoCandidati
            candidati={ricerca.candidati}
            sintesi={ricerca.sintesi}
            selezionato={ricerca.selezionato}
            onSeleziona={(id) => {
              ricerca.seleziona(id);
              setApplicato(false);
            }}
            nomeGruppo={`${base}-candidato`}
            prefissoTest="ricerca-manuale"
            testoNessuno="Nessuno di questi: continuo a compilare a mano"
          />
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Button
              type="button"
              size="sm"
              className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
              disabled={!scelto}
              onClick={() => {
                if (!scelto) return;
                applica(
                  {
                    produttore: valori.produttore,
                    nome: valori.nome,
                    annata: valori.annata,
                    denominazione: "",
                    formato: valori.formato,
                  },
                  scelto,
                );
                setApplicato(true);
              }}
              data-testid="ricerca-manuale-usa-btn"
            >
              Usa questo vino
            </Button>
            {applicato && (
              <span role="status" className="text-xs text-muted-foreground" data-testid="ricerca-manuale-applicato">
                Dati del vino scelto applicati ai campi. Puoi ancora modificarli.
              </span>
            )}
          </div>
        </>
      )}
    </section>
  );
}
