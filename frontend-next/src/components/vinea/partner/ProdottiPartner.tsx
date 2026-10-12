import Link from "next/link";
import { PackageOpen } from "lucide-react";
import { formatEUR } from "@/lib/format";
import { messaggioNonAcquistabile } from "@/lib/prezzi/classe";
import type { ProdottoPartner } from "@/services/preventivo-service";
import type { Result } from "@/services/types";

const STATI: Record<string, string> = {
  bozza: "Bozza",
  in_revisione: "In revisione",
  modifiche_richieste: "Modifiche richieste",
  attivo: "In vendita",
  riservato: "Tutte prenotate",
  sospeso: "Rimosso dalla vendita",
  scaduto: "Scaduto",
  venduto: "Venduto",
  rifiutato: "Rifiutato",
};

const euro = (cents: number) => formatEUR(cents / 100);

/**
 * VP-D: il catalogo commerciale del titolare, da `prodotti_partner_miei`.
 * Ogni numero è un conteggio di bottiglie fatto dal database; il prezzo per
 * l'acquirente è il preventivo Partner per una bottiglia. La gestione (foto,
 * descrizione, quantità, pubblicazione, rimozione) sta sulla scheda del
 * prodotto, la stessa degli annunci.
 */
export function ProdottiPartner({
  prodotti,
  venditaPartner,
}: {
  prodotti: Result<ProdottoPartner[]>;
  /** Specchio dell'interruttore; `null` se non letto. */
  venditaPartner: boolean | null;
}) {
  return (
    <section aria-labelledby="catalogo-prodotti" className="space-y-4" data-testid="prodotti-partner">
      <h2 id="catalogo-prodotti" className="font-serif text-2xl font-semibold">
        Prodotti
      </h2>
      {venditaPartner !== true ? (
        <p role="note" className="rounded-2xl border border-border bg-secondary/60 p-4 text-sm" data-testid="pubblicazione-chiusa">
          La pubblicazione dei prodotti Partner non è ancora aperta: puoi preparare le bozze, con
          prezzo, quantità, fotografie e descrizione. Nulla è visibile o acquistabile finché Vinea
          non apre la vendita professionale.
        </p>
      ) : null}
      {!prodotti.ok ? (
        <p role="status" className="rounded-2xl border border-dashed border-border bg-card p-4 text-sm">
          {prodotti.error}
        </p>
      ) : prodotti.data.length === 0 ? (
        <div
          className="rounded-3xl border border-border bg-card p-6 text-center md:p-8"
          data-testid="catalogo-commerciale-vuoto"
        >
          <PackageOpen className="mx-auto h-8 w-8 text-muted-foreground" aria-hidden />
          <p className="mt-3 font-serif text-xl">Nessun prodotto</p>
          <p className="mx-auto mt-2 max-w-md text-sm text-muted-foreground">
            Crea un prodotto dalle scorte qui sopra: scegli quante bottiglie offrire e quanto vuoi
            ricevere per ognuna.
          </p>
        </div>
      ) : (
        <ul className="divide-y divide-border rounded-3xl border border-border bg-card" data-testid="elenco-prodotti">
          {prodotti.data.map((p) => (
            <li key={p.listingId} className="flex flex-wrap items-start justify-between gap-3 p-4">
              <div className="min-w-0 space-y-1">
                <p className="text-xs uppercase tracking-wide text-salvia">{p.produttore}</p>
                <p className="font-serif font-semibold">
                  {p.nome} {p.annata} <span className="text-sm font-normal text-muted-foreground">· {p.formato}</span>
                </p>
                <p className="text-xs text-muted-foreground">
                  {STATI[p.stato] ?? p.stato} · {p.offerte} in vendita · {p.disponibili} disponibili ·{" "}
                  {p.riservate} prenotate · {p.vendute} vendute
                </p>
                <p className="text-sm">
                  Ricevi <b>{euro(p.prezzoCents)}</b> per bottiglia
                  {p.preventivoUnitario ? (
                    <>
                      {" "}· l&apos;acquirente paga <b>{euro(p.preventivoUnitario.totaleCents)}</b>
                    </>
                  ) : null}
                </p>
                {!p.vendibile && p.motivo && p.motivo !== "partner_vendita_non_disponibile" ? (
                  <p className="text-xs text-muted-foreground">{messaggioNonAcquistabile(p.motivo)}</p>
                ) : null}
              </div>
              <Link
                href={`/annuncio/${p.slug}`}
                className="shrink-0 text-sm font-medium text-bordeaux underline"
              >
                Gestisci
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
