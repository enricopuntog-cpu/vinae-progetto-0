import Link from "next/link";
import { ImageOff } from "lucide-react";
import { ETICHETTE_CONDIZIONE } from "@/lib/accessori/accessori";
import {
  etichettaCategoria,
  type AccessorioPubblico,
} from "@/lib/cantina-accessori/cantina-accessori";

/**
 * «Accessori della cantina» nel profilo pubblico e nella Cantina pubblica
 * (VPM-015B1).
 *
 * Componente SENZA stato e senza azioni: mostra solo ciò che il proprietario ha
 * scelto di esporre, nella forma a elenco chiuso restituita dal database. Nessun
 * prezzo, nessun pulsante di acquisto o di proposta, nessuna nota privata: gli
 * accessori esposti non sono in vendita. Senza accessori esposti (o con gli
 * interruttori spenti, che il database traduce in un elenco vuoto) non rende
 * NIENTE: né un titolo né un segnaposto, perché un blocco «vuoto» racconterebbe
 * la funzione o la scelta di una persona.
 */
export function AccessoriCantinaPubblici({
  accessori,
  url,
  collegamento,
}: {
  accessori: readonly AccessorioPubblico[];
  /** URL FIRMATE (il bucket e privato), indicizzate per percorso. Mancante = segnaposto. */
  url: Readonly<Record<string, string>>;
  /** Se presente, il link «Tutta la cantina» per chi vede solo un'anteprima. */
  collegamento?: { href: string; etichetta: string };
}) {
  if (accessori.length === 0) return null;
  return (
    <section aria-labelledby="accessori-cantina-titolo" data-testid="accessori-cantina-pubblici">
      <div className="mb-4 flex items-end justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">Cantina</p>
          <h2 id="accessori-cantina-titolo" className="mt-1 font-serif text-2xl font-semibold md:text-3xl">
            Accessori della cantina
          </h2>
        </div>
        {collegamento ? (
          <Link href={collegamento.href} className="shrink-0 text-sm font-medium text-bordeaux underline">
            {collegamento.etichetta}
          </Link>
        ) : null}
      </div>
      <ul className="grid gap-3 sm:grid-cols-2">
        {accessori.map((a) => {
          const foto = a.immagini[0] ? url[a.immagini[0]] : undefined;
          return (
            <li
              key={a.id}
              data-testid="accessorio-cantina-pubblico"
              className="flex min-w-0 flex-col overflow-hidden rounded-2xl border border-border bg-card"
            >
              <div className="aspect-[4/3] w-full overflow-hidden bg-secondary/40">
                {foto ? (
                  /* eslint-disable-next-line @next/next/no-img-element -- WebP gia ridotta al caricamento, URL firmata a tempo. */
                  <img src={foto} alt={a.nome} loading="lazy" className="h-full w-full object-cover" />
                ) : (
                  <div className="flex h-full w-full items-center justify-center text-antracite/40">
                    <ImageOff className="h-8 w-8" aria-hidden />
                  </div>
                )}
              </div>
              <div className="flex flex-1 flex-col gap-1 p-4">
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-salvia">
                  {etichettaCategoria(a)}
                </p>
                <h3 className="break-words font-serif text-lg font-semibold leading-snug">{a.nome}</h3>
                <p className="text-sm text-muted-foreground">
                  {ETICHETTE_CONDIZIONE[a.condizione]} · {a.quantita === 1 ? "1 pezzo" : `${a.quantita} pezzi`}
                  {a.marchio ? ` · ${a.marchio}` : ""}
                </p>
                {a.descrizione ? (
                  <p className="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-muted-foreground">
                    {a.descrizione}
                  </p>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
