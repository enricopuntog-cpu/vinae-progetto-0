import { Info } from "lucide-react";

/**
 * Lo stato da mostrare dove un acquisto da un Partner sarebbe altrimenti
 * possibile. Il checkout professionale non esiste ancora: i gate del database
 * su ordini e proposte lo rifiuterebbero, e un pulsante che porta a un rifiuto
 * è peggio di un pulsante assente.
 */
export function AcquistiPartnerNonDisponibili({
  className = "",
  compatto = false,
}: {
  className?: string;
  compatto?: boolean;
}) {
  return (
    <div
      role="note"
      className={`flex gap-3 rounded-2xl border border-border bg-secondary/60 p-4 text-sm ${className}`}
      data-testid="acquisti-partner-non-disponibili"
    >
      <Info className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
      <div>
        <p className="font-medium">Acquisti da Partner non ancora disponibili</p>
        {compatto ? null : (
          <p className="mt-1 text-muted-foreground">
            Questo è un venditore professionale Vinea. La vendita dei Partner aprirà più avanti:
            per ora puoi conoscere l&apos;attività e scriverle con la messaggistica Vinea.
          </p>
        )}
      </div>
    </div>
  );
}
