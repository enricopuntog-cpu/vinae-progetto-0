"use client";

import { ErroreDiPagina } from "@/components/vinea/ErroreDiPagina";

/**
 * Errore di una pagina: il layout resta, la navigazione resta. `retry` riprova la
 * sola pagina (Next 16.4); `reset` è il ripiego se un percorso passasse solo quello.
 */
export default function ErroreApplicazione({
  error,
  retry,
  reset,
}: {
  error: unknown;
  retry?: () => void;
  reset?: () => void;
}) {
  return <ErroreDiPagina errore={error} onRetry={retry ?? reset} />;
}
