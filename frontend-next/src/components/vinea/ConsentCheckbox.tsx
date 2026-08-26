"use client";

import { useId, type ReactNode } from "react";
import { Checkbox } from "@/components/ui/checkbox";

/**
 * Riga di consenso esplicito: spunta + testo, usata per i consensi
 * privacy/termini e per la dichiarazione di maggiore età.
 *
 * Il testo descrive la spunta tramite `aria-labelledby`, ma non è un `<label>`
 * che contiene i link: seguire Termini o Privacy non può quindi cambiare lo
 * stato del consenso.
 */
export function ConsentCheckbox({
  checked,
  onCheckedChange,
  children,
  icon,
  testId,
}: {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  children: ReactNode;
  /** Icona opzionale mostrata prima del testo (es. lo scudo per l'età). */
  icon?: ReactNode;
  testId?: string;
}) {
  const idTesto = useId();

  return (
    <div className="flex items-start gap-2 text-sm">
      <Checkbox
        checked={checked}
        onCheckedChange={(v) => onCheckedChange(v === true)}
        className="mt-0.5"
        data-testid={testId}
        aria-labelledby={idTesto}
      />
      <span id={idTesto} className={icon ? "flex items-center gap-1" : undefined}>
        {icon}
        {children}
      </span>
    </div>
  );
}
