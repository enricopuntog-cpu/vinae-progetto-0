import type { Wine } from "@/data/wines";
import { formatEUR } from "@/lib/format";
import { stimaCheckout, type DatiCheckoutBeta } from "@/lib/beta/checkout";

const euroCents = (cents: number) => formatEUR(cents / 100);

export const CheckoutSummary = ({
  wine,
  dati,
  saldoApplicatoCents,
  importoProviderCents,
  saldoOnly,
}: {
  wine: Wine;
  dati: DatiCheckoutBeta;
  saldoApplicatoCents?: number;
  importoProviderCents?: number;
  saldoOnly?: boolean;
}) => {
  const stima = stimaCheckout(wine.prezzo, dati.imballaggioCodice);

  return (
    <aside className="space-y-4 rounded-2xl border border-border bg-card p-4 lg:sticky lg:top-24" data-testid="checkout-summary">
      <div className="flex gap-3">
        <img src={wine.immagini[0]} alt="" className="h-20 w-16 rounded-lg object-cover" />
        <div className="min-w-0">
          <p className="truncate font-serif text-lg font-semibold">{wine.nome} {wine.annata}</p>
          <p className="truncate text-xs text-muted-foreground">{wine.produttore} · {wine.formato}</p>
        </div>
      </div>
      <div className="space-y-2 text-sm">
        <Riga label="Prezzo venditore" value={euroCents(stima.prezzoCents)} />
        <Riga label="Servizio Vinea stimato" value={euroCents(stima.commissioneCents)} />
        <Riga label="Imballaggio beta" value={euroCents(stima.imballaggioCents)} />
        <Riga label="Spedizione" value="Da confermare" />
        <div className="border-t border-border pt-2">
          <Riga label="Totale stimato" value={euroCents(stima.totaleCents)} forte />
        </div>
        {saldoOnly && (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50/60 p-3 mt-2">
            <p className="text-sm font-medium text-emerald-800">Coperto dal saldo Vinea</p>
            <p className="text-xs text-emerald-700 mt-0.5">Nessun addebito sul metodo di pagamento.</p>
          </div>
        )}
        {!saldoOnly && saldoApplicatoCents !== undefined && saldoApplicatoCents > 0 && (
          <>
            <Riga label="Saldo Vinea applicato" value={`−${euroCents(saldoApplicatoCents)}`} />
            <Riga label="Resto sul metodo scelto" value={euroCents(importoProviderCents ?? 0)} forte />
          </>
        )}
      </div>
      <p className="text-xs leading-relaxed text-muted-foreground">
        Il totale vincolante sarà calcolato dal server e mostrato dal provider prima del pagamento.
        Nessun costo di spedizione o imballaggio viene promesso da questa stima beta.
      </p>
    </aside>
  );
};

const Riga = ({ label, value, forte = false }: { label: string; value: string; forte?: boolean }) => (
  <div className={`flex items-baseline justify-between gap-3 ${forte ? "font-semibold text-bordeaux" : ""}`}>
    <span>{label}</span><span className="shrink-0">{value}</span>
  </div>
);
