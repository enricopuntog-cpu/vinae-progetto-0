"use client";

// WI-012 — pezzi condivisi del pannello catalogo: lettura con ricarica, campi e conferme.

import { useCallback, useEffect, useId, useState, type ReactNode } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import type { Result } from "@/services/types";

/** Legge con `carica` ogni volta che cambia `chiave`; le risposte superate vengono scartate. */
export function useLettura<T>(carica: () => Promise<Result<T>>, chiave: string) {
  const [giro, setGiro] = useState(0);
  const richiesta = `${chiave}#${giro}`;
  const [letto, setLetto] = useState<{ richiesta: string; esito: Result<T> } | null>(null);
  useEffect(() => {
    let annullato = false;
    void carica().then((esito) => {
      if (!annullato) setLetto({ richiesta, esito });
    });
    return () => {
      annullato = true;
    };
    // `carica` cambia a ogni render: la richiesta è identificata da `chiave` e dal giro.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [richiesta]);
  const ricarica = useCallback(() => setGiro((g) => g + 1), []);
  const attuale = letto?.richiesta === richiesta ? letto.esito : null;
  return { esito: attuale, ricarica };
}

export function Letto<T>({
  esito,
  ricarica,
  children,
}: {
  esito: Result<T> | null;
  ricarica: () => void;
  children: (dati: T) => ReactNode;
}) {
  if (!esito) return <LoadingBlock />;
  if (!esito.ok) return <ErrorState description={esito.error} onRetry={ricarica} />;
  return <>{children(esito.data)}</>;
}

export function Campo({
  etichetta,
  valore,
  onCambio,
  massimo = 200,
  numerico = false,
}: {
  etichetta: string;
  valore: string;
  onCambio: (v: string) => void;
  massimo?: number;
  numerico?: boolean;
}) {
  const id = useId();
  return (
    <div className="min-w-0">
      <Label htmlFor={id} className="text-xs">
        {etichetta}
      </Label>
      <Input
        id={id}
        value={valore}
        maxLength={massimo}
        inputMode={numerico ? "numeric" : undefined}
        onChange={(e) => onCambio(e.target.value)}
        className="h-9"
      />
    </div>
  );
}

export function Scelta({
  etichetta,
  valore,
  onCambio,
  opzioni,
}: {
  etichetta: string;
  valore: string;
  onCambio: (v: string) => void;
  opzioni: [string, string][];
}) {
  const id = useId();
  return (
    <div className="min-w-0">
      <Label htmlFor={id} className="text-xs">
        {etichetta}
      </Label>
      <select
        id={id}
        value={valore}
        onChange={(e) => onCambio(e.target.value)}
        className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm"
      >
        {opzioni.map(([v, t]) => (
          <option key={v} value={v}>
            {t}
          </option>
        ))}
      </select>
    </div>
  );
}

export function Esito({ errore, messaggio }: { errore: string | null; messaggio?: string | null }) {
  if (errore) {
    return (
      <p role="alert" className="text-sm text-destructive">
        {errore}
      </p>
    );
  }
  return messaggio ? (
    <p role="status" className="text-sm text-salvia-scuro">
      {messaggio}
    </p>
  ) : null;
}

export const testoValore = (v: unknown): string => (v === null || v === undefined ? "—" : typeof v === "string" ? v : JSON.stringify(v));

export const data = (iso: string | null | undefined): string => (iso ? new Date(iso).toLocaleString("it-IT") : "—");
