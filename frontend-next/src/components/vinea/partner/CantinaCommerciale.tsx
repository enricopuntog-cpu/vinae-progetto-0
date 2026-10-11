import Link from "next/link";
import { ExternalLink, PackageOpen, Store } from "lucide-react";
import { WineThumbnail } from "@/components/vinea/WineThumbnail";
import { AcquistiPartnerNonDisponibili } from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { routes } from "@/config/routes";
import { ETICHETTA_STATO_PRODOTTO, catalogoCommerciale } from "@/lib/partner/catalogo";
import type { AnnuncioProprietario } from "@/services/listing-service";
import type { PartnerStato } from "@/services/types";

/**
 * La Cantina di un Partner attivo o sospeso: gestione commerciale, non
 * collezione (decisione di prodotto del Blocco B).
 *
 * Qui non ci sono apertura bottiglie, degustazioni, valore patrimoniale o
 * vista 3D: sono strumenti del collezionista privato e restano intatti nella
 * Cantina dei privati. Le bottiglie personali del titolare NON vengono
 * convertite in prodotti né cancellate: restano nel database come sono e
 * tornano visibili se la classe commerciale cessa.
 *
 * I prodotti sono gli annunci che il titolare ha già. Nessuna quantità o
 * disponibilità commerciale è mostrata: il modello di giacenze arriva con il
 * Blocco C, e un numero inventato oggi sarebbe da smentire domani.
 */

function RigaProdotto({ annuncio }: { annuncio: AnnuncioProprietario }) {
  const { wine, stato } = annuncio;
  return (
    <li>
      <Link
        href={`/annuncio/${wine.id}`}
        className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3 transition-colors hover:border-bordeaux focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        data-testid="prodotto-commerciale"
      >
        <WineThumbnail
          src={wine.immagini[0]}
          alt={`${wine.nome} ${wine.annata}`}
          className="h-20 w-16 shrink-0 rounded-lg object-cover"
          sizes="64px"
        />
        <span className="min-w-0 flex-1">
          <span className="block text-xs uppercase tracking-wide text-salvia">{wine.produttore}</span>
          <span className="block truncate font-serif text-base font-semibold">
            {wine.nome} {wine.annata}
          </span>
          <span className="block text-xs text-muted-foreground">Formato {wine.formato}</span>
        </span>
        <span className="shrink-0 rounded-full border border-border px-2.5 py-1 text-xs font-medium">
          {ETICHETTA_STATO_PRODOTTO[stato]}
        </span>
      </Link>
    </li>
  );
}

export function CantinaCommerciale({
  nomeCommerciale,
  stato,
  titolareId,
  annunci,
  letturaRiuscita,
}: {
  nomeCommerciale: string | null;
  stato: PartnerStato;
  titolareId: string;
  annunci: AnnuncioProprietario[];
  letturaRiuscita: boolean;
}) {
  const { inVetrina, altri } = catalogoCommerciale(annunci);
  const sospeso = stato === "sospeso";

  return (
    <div className="space-y-8" data-testid="cantina-commerciale">
      <header className="space-y-2">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-salvia">
          Partner Vinea · Venditore professionale
        </p>
        <h1 className="font-serif text-3xl font-semibold md:text-4xl">Catalogo commerciale</h1>
        <p className="max-w-2xl text-muted-foreground">
          {nomeCommerciale ? `I prodotti di ${nomeCommerciale}. ` : ""}
          Come Partner, la tua Cantina è la gestione commerciale dei prodotti. La collezione
          personale non viene convertita in catalogo: le tue bottiglie restano conservate.
        </p>
        <div className="flex flex-wrap gap-4 pt-1 text-sm">
          {!sospeso ? (
            <Link
              href={routes.profiloPubblico(titolareId)}
              className="inline-flex items-center gap-1 font-medium text-bordeaux underline"
            >
              <Store className="h-4 w-4" aria-hidden /> Vedi la vetrina
            </Link>
          ) : null}
          <Link href="/partner" className="inline-flex items-center gap-1 font-medium text-bordeaux underline">
            <ExternalLink className="h-4 w-4" aria-hidden /> Area Partner
          </Link>
        </div>
      </header>

      {sospeso ? (
        <p role="note" className="rounded-2xl border border-border bg-muted p-4 text-sm">
          Il Partner è sospeso: la vetrina non è pubblica. Il catalogo resta consultabile e i dati
          sono conservati.
        </p>
      ) : null}

      <AcquistiPartnerNonDisponibili />

      <section aria-labelledby="catalogo-in-vetrina">
        <h2 id="catalogo-in-vetrina" className="font-serif text-2xl font-semibold">
          In vetrina
        </h2>
        {!letturaRiuscita ? (
          <p role="alert" className="mt-3 text-sm text-destructive">
            Non è stato possibile leggere il catalogo. Riprova fra poco.
          </p>
        ) : inVetrina.length > 0 ? (
          <ul className="mt-4 grid gap-3 sm:grid-cols-2">
            {inVetrina.map((a) => (
              <RigaProdotto key={a.wine.id} annuncio={a} />
            ))}
          </ul>
        ) : (
          <div
            className="mt-4 rounded-3xl border border-border bg-card p-6 text-center md:p-8"
            data-testid="catalogo-commerciale-vuoto"
          >
            <PackageOpen className="mx-auto h-8 w-8 text-muted-foreground" aria-hidden />
            <p className="mt-3 font-serif text-xl">Il catalogo è vuoto</p>
            <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
              La pubblicazione di prodotti come Partner — con quantità multiple e disponibilità —
              non è ancora aperta. Quando lo sarà, i tuoi prodotti compariranno qui e nella
              vetrina.
            </p>
          </div>
        )}
      </section>

      {letturaRiuscita && altri.length > 0 ? (
        <section aria-labelledby="catalogo-altri">
          <h2 id="catalogo-altri" className="font-serif text-2xl font-semibold">
            Non in vetrina
          </h2>
          <ul className="mt-4 grid gap-3 sm:grid-cols-2">
            {altri.map((a) => (
              <RigaProdotto key={a.wine.id} annuncio={a} />
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
