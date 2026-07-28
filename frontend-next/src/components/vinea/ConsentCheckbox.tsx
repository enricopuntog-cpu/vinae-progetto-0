"use client";

import type { ReactNode } from "react";
import { Checkbox } from "@/components/ui/checkbox";

/**
 * Riga di consenso esplicito: spunta + testo, usata per i consensi
 * privacy/termini e per la dichiarazione di maggiore età.
 *
 * Estratta perché lo stesso markup era ripetuto inline in /registrati (due
 * volte) e in /completa-profilo: averlo in un posto solo evita che le tre
 * copie divergano fra loro, cosa che su un consenso conta più che su un
 * bottone qualsiasi.
 *
 * Non impone nulla sulla logica di validazione: chi la usa decide se e come
 * il consenso sblocca l'azione successiva.
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
  return (
    <label className="flex items-start gap-2 text-sm">
      <Checkbox
        checked={checked}
        onCheckedChange={(v) => onCheckedChange(v === true)}
        className="mt-0.5"
        data-testid={testId}
      />
      {icon ? (
        <span className="flex items-center gap-1">
          {icon}
          {children}
        </span>
      ) : (
        <span>{children}</span>
      )}
    </label>
  );
}
