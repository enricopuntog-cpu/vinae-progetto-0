"use client";

import { useEffect, useRef } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { reportClientEvent } from "@/lib/observability/client";

/**
 * Pagina di errore dell'applicazione (VPM-018-UX-A11Y-01, GAP-005): corpo comune
 * di `app/error.tsx` (dentro il layout) e `app/global-error.tsx` (al posto del
 * layout). Mostra solo testo fisso: né il messaggio né la traccia dell'errore
 * arrivano mai in pagina, perché possono contenere dettagli interni. Nel registro
 * del browser finisce soltanto l'impronta (`digest`) con cui il team ritrova
 * l'errore nei log del server.
 */

/** Impronta del server, se c'è; mai il messaggio. */
export const impronta = (errore: unknown): string => {
  if (typeof errore === "object" && errore !== null && "digest" in errore) {
    const { digest } = errore as { digest?: unknown };
    if (typeof digest === "string" && /^[\w-]{1,64}$/.test(digest)) return digest;
  }
  return "n/d";
};

export function ErroreDiPagina({ errore, onRetry }: { errore: unknown; onRetry?: () => void }) {
  const titolo = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    // Una sola volta per errore: nessun ciclo di rendering.
    console.error("[vinea] errore di pagina, impronta:", impronta(errore));
    reportClientEvent("client_boundary");
  }, [errore]);

  useEffect(() => {
    // La pagina è stata sostituita: chi usa tastiera o lettore di schermo riparte dal titolo.
    // È l'unico annuncio (niente `role="alert"`, che farebbe leggere il testo due volte).
    titolo.current?.focus();
  }, []);

  return (
    <div
      className="mx-auto flex min-h-[50vh] w-full max-w-lg flex-col items-center justify-center px-4 py-12 text-center"
    >
      <div className="mb-3 grid h-12 w-12 place-items-center rounded-full bg-bordeaux/5 text-bordeaux">
        <AlertTriangle className="h-5 w-5" aria-hidden="true" />
      </div>
      {/* `outline-none`: il titolo riceve il fuoco solo da codice (tabIndex -1), non è un controllo. */}
      <h1 ref={titolo} tabIndex={-1} className="font-serif text-2xl font-semibold outline-none">
        Qualcosa non ha funzionato
      </h1>
      <p className="mt-2 text-sm text-muted-foreground">
        Si è verificato un problema inatteso. Riprova tra un istante: se si ripresenta, torna alla
        home e riparti da lì.
      </p>
      <div className="mt-4 flex flex-wrap justify-center gap-2">
        {onRetry ? (
          <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={onRetry}>
            <RefreshCw className="h-4 w-4" aria-hidden="true" /> Riprova
          </Button>
        ) : null}
        <Button asChild variant="outline">
          {/* Un link normale, non `next/link`: ricarica da zero e non dipende dal router rotto. */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/">Torna alla home</a>
        </Button>
      </div>
    </div>
  );
}
