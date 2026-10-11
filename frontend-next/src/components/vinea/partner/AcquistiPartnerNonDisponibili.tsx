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
            per ora non è possibile acquistare né inviare proposte.
          </p>
        )}
      </div>
    </div>
  );
}

/**
 * Lo stato da mostrare quando la disponibilità dell'acquisto non si è potuta
 * verificare: né «Compra ora» né proposta, finché non si rilegge la pagina.
 */
export function AcquistoNonVerificato({ className = "" }: { className?: string }) {
  return (
    <div
      role="alert"
      className={`flex gap-3 rounded-2xl border border-border bg-secondary/60 p-4 text-sm ${className}`}
      data-testid="acquisto-non-verificato"
    >
      <Info className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
      <p>Non è stato possibile verificare la disponibilità dell&apos;acquisto. Riprova fra poco.</p>
    </div>
  );
}
