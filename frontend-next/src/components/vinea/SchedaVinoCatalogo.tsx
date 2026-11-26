// WI-008 — la scheda autonoma di un vino del catalogo, anche senza annunci. Mostra solo ciò che la fonte fornisce e
// dichiara il resto come mancante: nessuna foto, prezzo, annata o recensione. Non riusa `WineIntelligenceCard` di
// proposito: quella parte da un vino Vinea e completa con valori generici «stimati», che qui sarebbero inventati.
// Nessun annuncio viene accostato per somiglianza di nome: servirebbe un collegamento canonico, oggi inesistente.

import Link from "next/link";
import { ChiediAlSommelier } from "@/components/vinea/ChiediAlSommelier";
import { contestoRicercaDaCandidato } from "@/lib/phase10/sommelier-contesto-ui";
import type { SchedaCanonica } from "@/lib/wine-intelligence/scheda-canonica";

const ETICHETTA_TERRITORIO: Record<string, string> = {
  region: "Regione",
  subregion: "Sottoregione",
  site: "Sito",
  country: "Paese",
};

export function SchedaVinoCatalogo({ scheda, codiceRichiesto }: { scheda: SchedaCanonica; codiceRichiesto: string }) {
  const territorio =
    scheda.territorio && scheda.territorio !== scheda.paese
      ? { etichetta: ETICHETTA_TERRITORIO[scheda.territorioTipo ?? ""] ?? "Territorio", valore: scheda.territorio }
      : null;
  const campi: { etichetta: string; valore: string | null }[] = [
    { etichetta: "Paese", valore: scheda.paese },
    ...(territorio ? [territorio] : [{ etichetta: "Territorio", valore: null }]),
    { etichetta: "Denominazione", valore: scheda.denominazione },
    { etichetta: "Tipologia (come nella fonte)", valore: scheda.tipo },
    { etichetta: "Colore (come nella fonte)", valore: scheda.colore },
  ];
  const mancanti = [
    ...campi.filter((c) => !c.valore).map((c) => c.etichetta),
    "Annata",
    "Formato",
    "Vitigni",
    "Prezzo",
    "Fotografie",
    "Note e recensioni",
  ];
  const domanda = contestoRicercaDaCandidato({
    produttore: scheda.produttore,
    nome: scheda.nome,
    canonico: { lwin7: scheda.lwin7 },
  });
  return (
    <article className="mx-auto max-w-2xl space-y-4 p-4" data-testid="scheda-catalogo">
      <header>
        <p className="text-[11px] uppercase tracking-[0.2em] text-muted-foreground">Scheda del catalogo</p>
        <h1 className="font-serif text-2xl leading-tight">{scheda.nome}</h1>
        <p className="text-sm">
          {scheda.produttore} <span className="text-muted-foreground">· LWIN {scheda.lwin7}</span>
        </p>
        {codiceRichiesto !== scheda.lwin7 ? (
          <p className="text-xs text-muted-foreground" data-testid="scheda-catalogo-risolto">
            Il codice richiesto ({codiceRichiesto}) è confluito in questa scheda.
          </p>
        ) : null}
      </header>

      <dl className="grid gap-2 rounded-2xl border border-border bg-card p-4 text-sm sm:grid-cols-2">
        {campi
          .filter((c) => c.valore)
          .map((c) => (
            <div key={c.etichetta}>
              <dt className="text-[11px] text-muted-foreground">{c.etichetta}</dt>
              <dd>{c.valore}</dd>
            </div>
          ))}
      </dl>

      <section className="text-xs text-muted-foreground" data-testid="scheda-catalogo-mancanti">
        <h2 className="font-semibold text-antracite">Informazioni non disponibili</h2>
        <p>{mancanti.join(", ")}.</p>
      </section>

      <section className="text-xs text-muted-foreground" data-testid="scheda-catalogo-annunci">
        <h2 className="font-semibold text-antracite">Annunci</h2>
        <p>
          Nessun annuncio è collegato a questa scheda. Un nome uguale non basta a collegarlo.{" "}
          <Link href="/esplora" className="underline">
            Vai al mercato
          </Link>
          .
        </p>
      </section>

      {domanda ? (
        <ChiediAlSommelier contesto={domanda} etichetta="Chiedi al Sommelier" testId="scheda-catalogo-sommelier" />
      ) : null}

      <footer className="border-t border-border pt-3 text-[11px] text-muted-foreground">
        <p>
          Fonte: {[scheda.fonteNome, scheda.licenza].filter(Boolean).join(" — ") || "non dichiarata"}.
        </p>
        {scheda.attribuzione ? <p>{scheda.attribuzione}</p> : null}
      </footer>
    </article>
  );
}
