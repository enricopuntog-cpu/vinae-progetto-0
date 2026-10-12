import Link from "next/link";
import { ExternalLink, PackageOpen, Store } from "lucide-react";
import { AcquistiPartnerNonDisponibili } from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { AggiungiScortePartner } from "@/components/vinea/partner/AggiungiScortePartner";
import { CreaProdottoPartner } from "@/components/vinea/partner/CreaProdottoPartner";
import { ProdottiPartner } from "@/components/vinea/partner/ProdottiPartner";
import { routes } from "@/config/routes";
import type { GruppoScorte } from "@/services/partner-scorte-service";
import type { ProdottoPartner } from "@/services/preventivo-service";
import type { PartnerStato, Result } from "@/services/types";

/**
 * La Cantina di un Partner attivo o sospeso: gestione commerciale, non
 * collezione (decisione di prodotto del Blocco B).
 *
 * Qui non ci sono apertura bottiglie, degustazioni, stime economiche o vista
 * 3D: sono strumenti del collezionista privato e restano intatti nella Cantina
 * dei privati.
 *
 * VP-C: le scorte dell'attività sono righe dello stesso inventario della
 * Cantina, ma commerciali e legate al Partner; si leggono solo quelle
 * (`creaScortePartnerService`), raggruppate per vino e formato. Le bottiglie e
 * gli annunci personali del titolare non compaiono qui e non si convertono.
 * VP-D: dalle scorte libere nascono i prodotti (bozze commerciali) e il
 * catalogo li elenca con il prezzo per l'acquirente calcolato dal database;
 * la pubblicazione resta chiusa finché `vendita_partner` è spento.
 */
export function CantinaCommerciale({
  nomeCommerciale,
  stato,
  titolareId,
  scorte,
  libere,
  prodotti,
  venditaPartner,
}: {
  nomeCommerciale: string | null;
  stato: PartnerStato;
  titolareId: string;
  scorte: Result<GruppoScorte[]>;
  /** VP-D: unità libere per gruppo (chiave del gruppo); `null` se non verificate. */
  libere: Record<string, string[]> | null;
  prodotti: Result<ProdottoPartner[]>;
  /** Specchio dell'interruttore `vendita_partner`; `null` se non letto. */
  venditaPartner: boolean | null;
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
          Il Partner è sospeso: la vetrina non è pubblica e non si aggiungono scorte. Dati e scorte
          sono conservati.
        </p>
      ) : null}

      {venditaPartner !== true ? <AcquistiPartnerNonDisponibili /> : null}

      <section aria-labelledby="scorte-attivita" className="space-y-4">
        <h2 id="scorte-attivita" className="font-serif text-2xl font-semibold">
          Scorte dell&apos;attività
        </h2>
        {!scorte.ok ? (
          <p role="status" className="rounded-2xl border border-dashed border-border bg-card p-4 text-sm">
            {scorte.error}
          </p>
        ) : scorte.data.length === 0 ? (
          <div
            className="rounded-3xl border border-border bg-card p-6 text-center md:p-8"
            data-testid="scorte-vuote"
          >
            <PackageOpen className="mx-auto h-8 w-8 text-muted-foreground" aria-hidden />
            <p className="mt-3 font-serif text-xl">Nessuna scorta registrata</p>
            <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
              Registra i vini dell&apos;attività con formato e numero di unità. Restano separati dalle
              tue bottiglie personali.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-border rounded-3xl border border-border bg-card" data-testid="elenco-scorte">
            {scorte.data.map((g) => (
              <li key={g.chiave} className="flex flex-wrap items-baseline justify-between gap-2 p-4">
                <div className="min-w-0">
                  <p className="text-xs uppercase tracking-wide text-salvia">{g.produttore}</p>
                  <p className="font-serif font-semibold">
                    {g.nome} {g.annata}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {g.tipo} · {g.regione} · {g.formato}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-2">
                  <p className="text-sm font-medium">
                    {g.quantita} {g.quantita === 1 ? "unità" : "unità"} in scorta
                  </p>
                  {!sospeso ? (
                    <CreaProdottoPartner gruppo={g} libere={libere ? (libere[g.chiave] ?? []) : null} />
                  ) : null}
                </div>
              </li>
            ))}
          </ul>
        )}
        {!sospeso ? <AggiungiScortePartner /> : null}
      </section>

      <ProdottiPartner prodotti={prodotti} venditaPartner={venditaPartner} />

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
