import { Info } from "lucide-react";
import {
  etichettaClasse,
  messaggioNonAcquistabile,
  spiegazionePrezzo,
} from "@/lib/prezzi/classe";
import type { MotivoNonAcquistabile, PreventivoEconomico } from "@/services/preventivo-service";
import type { ClasseVenditore } from "@/services/types";

/**
 * VP-D: il prezzo scomposto come lo calcola il database, per la classe che il
 * database attribuisce al venditore. Prezzo per bottiglia, subtotale, servizio
 * Vinea e totale stimato sono righe distinte; imballaggio e spedizione restano
 * fuori. Senza preventivo dice che il prezzo non è disponibile: nessun numero
 * ricavato in altro modo.
 *
 * `vista = "venditore"` parla al venditore («ricevi»), altrimenti
 * all'acquirente.
 */
export function PrezzoPerAcquirente({
  preventivo,
  classe,
  motivo = null,
  vista = "acquirente",
  className = "",
}: {
  preventivo: PreventivoEconomico | null;
  classe: ClasseVenditore | null;
  motivo?: MotivoNonAcquistabile | null;
  vista?: "acquirente" | "venditore";
  className?: string;
}) {
  if (!preventivo) {
    return (
      <p
        role="status"
        className={`rounded-2xl border border-dashed border-border bg-card p-3 text-sm text-muted-foreground ${className}`}
        data-testid="prezzo-non-disponibile"
      >
        {messaggioNonAcquistabile(motivo)}
      </p>
    );
  }
  const s = spiegazionePrezzo(preventivo);
  const venditore = vista === "venditore";
  return (
    <div
      className={`space-y-2 rounded-2xl border border-border bg-card p-4 text-sm ${className}`}
      data-testid="prezzo-per-acquirente"
      data-classe={preventivo.classe}
    >
      {classe ? (
        <p className="text-xs font-semibold uppercase tracking-wide text-salvia">{etichettaClasse(classe)}</p>
      ) : null}
      <Riga
        label={
          venditore
            ? "Ricevi"
            : preventivo.quantita > 1
              ? "Prezzo del venditore"
              : "Prezzo per bottiglia"
        }
        valore={s.ricevi}
      />
      <Riga label="Servizio Vinea" valore={s.servizio} />
      <div className="border-t border-border pt-2">
        <Riga
          label={venditore ? "L'acquirente paga" : "Totale stimato"}
          valore={s.totale}
          forte
        />
      </div>
      <p className="flex gap-2 text-xs leading-relaxed text-muted-foreground">
        <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
        <span>
          {s.composizione} Imballaggio e spedizione sono a parte. Il totale vincolante lo calcola il
          server alla conferma dell&apos;ordine.
        </span>
      </p>
    </div>
  );
}

const Riga = ({ label, valore, forte = false }: { label: string; valore: string; forte?: boolean }) => (
  <div className={`flex items-baseline justify-between gap-3 ${forte ? "font-semibold text-bordeaux" : ""}`}>
    <span>{label}</span>
    <span className="shrink-0 tabular-nums">{valore}</span>
  </div>
);
