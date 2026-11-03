"use client";

import { ErroreDiPagina } from "@/components/vinea/ErroreDiPagina";

/** Errore di una pagina: il layout resta, la navigazione resta. `retry` riprova la sola pagina. */
export default function ErroreApplicazione({ error, retry }: { error: unknown; retry: () => void }) {
  return <ErroreDiPagina errore={error} onRetry={retry} />;
}
