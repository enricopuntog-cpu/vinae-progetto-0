import Link from "next/link";
import { ExternalLink, PackageOpen, Store } from "lucide-react";
import { AcquistiPartnerNonDisponibili } from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { routes } from "@/config/routes";
import type { PartnerStato } from "@/services/types";

/**
 * La Cantina di un Partner attivo o sospeso: gestione commerciale, non
 * collezione (decisione di prodotto del Blocco B).
 *
 * Qui non ci sono apertura bottiglie, degustazioni, valore patrimoniale o
 * vista 3D: sono strumenti del collezionista privato e restano intatti nella
 * Cantina dei privati.
 *
 * Il catalogo è vuoto fino al Blocco C, ed è vuoto di proposito. Nel database
 * non esiste ancora una distinzione autorevole fra un prodotto dell'attività e
 * un annuncio personale del titolare: mostrare qui i suoi annunci — o le sue
 * bottiglie — vorrebbe dire presentare beni personali come merce
 * dell'attività. Bottiglie e annunci personali restano nel database come sono:
 * niente conversioni, niente cancellazioni, e gli annunci si gestiscono da
 * «Il mio account». Nessuna quantità o disponibilità inventata: il modello di
 * giacenze è il Blocco C.
 */
export function CantinaCommerciale({
  nomeCommerciale,
  stato,
  titolareId,
}: {
  nomeCommerciale: string | null;
  stato: PartnerStato;
  titolareId: string;
}) {
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
          Come Partner, la tua Cantina è la gestione commerciale dei prodotti dell&apos;attività.
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
          Il Partner è sospeso: la vetrina non è pubblica. I dati sono conservati.
        </p>
      ) : null}

      <AcquistiPartnerNonDisponibili />

      <section aria-labelledby="catalogo-prodotti">
        <h2 id="catalogo-prodotti" className="font-serif text-2xl font-semibold">
          Prodotti dell&apos;attività
        </h2>
        <div
          className="mt-4 rounded-3xl border border-border bg-card p-6 text-center md:p-8"
          data-testid="catalogo-commerciale-vuoto"
        >
          <PackageOpen className="mx-auto h-8 w-8 text-muted-foreground" aria-hidden />
          <p className="mt-3 font-serif text-xl">Il catalogo è in preparazione</p>
          <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
            La pubblicazione di prodotti come Partner — con quantità multiple e disponibilità —
            non è ancora aperta. Quando lo sarà, i prodotti dell&apos;attività compariranno qui e
            nella vetrina.
          </p>
        </div>
      </section>

      <p role="note" className="text-sm text-muted-foreground" data-testid="beni-personali-intatti">
        Le tue bottiglie e i tuoi annunci personali non diventano prodotti dell&apos;attività:
        restano tuoi, così come sono. Gli annunci li trovi in{" "}
        <Link href="/account" className="font-medium text-bordeaux underline">
          Il mio account
        </Link>
        .
      </p>
    </div>
  );
}
