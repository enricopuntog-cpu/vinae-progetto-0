import Link from "next/link";
import { ArrowLeft, ImageOff } from "lucide-react";
import {
  ETICHETTE_CONDIZIONE,
  percorsiAccessori,
  urlImmagineAccessorio,
  type SchedaAccessorio,
} from "@/lib/accessori/accessori";
import type { ModalitaAccessori } from "@/lib/accessori/gate";
import { AvvisoBetaAccessori, BannerAnteprimaAccessori } from "./AccessoriVetrina";

const etichettaAttributo = (chiave: string): string => {
  const testo = chiave.replace(/_/g, " ");
  return testo.charAt(0).toUpperCase() + testo.slice(1);
};

/**
 * Pagina dettaglio di una scheda (VPM-015A). Nessuna azione di acquisto: non
 * c'è prezzo, non c'è disponibilità e non c'è un percorso verso checkout,
 * ordini o pagamenti.
 */
export function DettaglioAccessorio({
  scheda,
  modalita,
  stato,
}: {
  scheda: SchedaAccessorio;
  modalita: ModalitaAccessori;
  /** Solo in anteprima: «Bozza» ecc., per non scambiarla con una scheda pubblica. */
  stato?: string | null;
}) {
  const immagini = scheda.immagini
    .map((p) => urlImmagineAccessorio(p))
    .filter((u): u is string => u !== null);
  const attributi = Object.entries(scheda.attributi);
  const { categoria } = scheda;

  return (
    <main id="contenuto-principale" className="mx-auto max-w-5xl px-4 py-8 md:py-12">
      {modalita === "anteprima" ? <BannerAnteprimaAccessori /> : null}

      <nav aria-label="Percorso" className="mb-5 flex flex-wrap items-center gap-1 text-sm text-antracite/70">
        <Link href={percorsiAccessori.indice} className="inline-flex items-center gap-1 hover:text-bordeaux">
          <ArrowLeft className="h-4 w-4" aria-hidden /> Accessori
        </Link>
        {categoria.genitoreSlug && categoria.genitoreNome ? (
          <>
            <span aria-hidden>/</span>
            <Link href={percorsiAccessori.categoria(categoria.genitoreSlug)} className="hover:text-bordeaux">
              {categoria.genitoreNome}
            </Link>
          </>
        ) : null}
        <span aria-hidden>/</span>
        <Link href={percorsiAccessori.categoria(categoria.slug)} className="hover:text-bordeaux">
          {categoria.nome}
        </Link>
      </nav>

      <article className="grid gap-8 md:grid-cols-2">
        <div className="space-y-3">
          <div className="aspect-square w-full overflow-hidden rounded-2xl border border-border bg-secondary/40">
            {immagini[0] ? (
              /* eslint-disable-next-line @next/next/no-img-element -- immagine WebP gia ridotta dal caricamento admin. */
              <img src={immagini[0]} alt={scheda.nome} className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-antracite/40">
                <ImageOff className="h-10 w-10" aria-label="Immagine non disponibile" />
              </div>
            )}
          </div>
          {immagini.length > 1 ? (
            <ul className="grid grid-cols-4 gap-2" aria-label="Altre immagini">
              {immagini.slice(1).map((url) => (
                <li key={url} className="aspect-square overflow-hidden rounded-lg border border-border">
                  {/* eslint-disable-next-line @next/next/no-img-element -- vedi sopra. */}
                  <img src={url} alt={`${scheda.nome}, dettaglio`} loading="lazy" className="h-full w-full object-cover" />
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        <div className="space-y-5">
          <header>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
              {categoria.nome}
            </p>
            <h1 className="mt-1 font-serif text-3xl font-semibold leading-tight text-antracite">
              {scheda.nome}
            </h1>
            {scheda.marchio ? <p className="mt-1 text-antracite/75">{scheda.marchio}</p> : null}
            <div className="mt-3 flex flex-wrap gap-2 text-xs">
              <span className="rounded-full bg-secondary px-2.5 py-1 text-antracite/80">
                {ETICHETTE_CONDIZIONE[scheda.condizione]}
              </span>
              {stato && stato !== "Pubblicato" ? (
                <span className="rounded-full bg-oro/20 px-2.5 py-1 font-medium text-antracite">
                  {stato}
                </span>
              ) : null}
            </div>
          </header>

          {scheda.descrizione ? (
            <p className="whitespace-pre-line leading-relaxed text-antracite/85">{scheda.descrizione}</p>
          ) : null}

          {attributi.length > 0 ? (
            <section aria-labelledby="accessorio-caratteristiche">
              <h2 id="accessorio-caratteristiche" className="font-serif text-lg font-semibold text-antracite">
                Caratteristiche
              </h2>
              <dl className="mt-2 divide-y divide-border rounded-xl border border-border bg-card">
                {attributi.map(([chiave, valore]) => (
                  <div key={chiave} className="flex justify-between gap-4 px-4 py-2.5 text-sm">
                    <dt className="text-antracite/70">{etichettaAttributo(chiave)}</dt>
                    <dd className="text-right font-medium text-antracite">{valore}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ) : null}

          <AvvisoBetaAccessori />
        </div>
      </article>
    </main>
  );
}
