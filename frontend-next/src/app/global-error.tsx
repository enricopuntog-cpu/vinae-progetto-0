"use client";

import "./globals.css";
import { ErroreDiPagina } from "@/components/vinea/ErroreDiPagina";
import { brand } from "@/config/brand";
import { LOCALE_PREDEFINITO } from "@/lib/mercato";

/**
 * Errore del layout radice (per esempio la lettura dell'avviso incidenti):
 * sostituisce il layout, quindi porta i propri `<html>`, `<body>` e gli stili.
 * Niente provider, niente sessione: solo il marchio e la via d'uscita.
 *
 * Niente Google Fonts: provati nel browser, in questa pagina i file `latin` di
 * Cormorant e Inter finiscono in stato `error` (causa non isolata), mentre dentro
 * il layout (`error.tsx`) si caricano. Per una pagina di ultima istanza si usano i
 * caratteri di sistema già previsti dai token (`ui-serif`, `ui-sans-serif`).
 */
export default function ErroreGlobale({
  error,
  retry,
  reset,
}: {
  error: unknown;
  retry?: () => void;
  reset?: () => void;
}) {
  return (
    <html lang={LOCALE_PREDEFINITO} className="h-full antialiased">
      <head>
        <title>{`Qualcosa non ha funzionato — ${brand.nome}`}</title>
        <meta name="robots" content="noindex, nofollow" />
      </head>
      <body className="flex min-h-full flex-col">
        <main className="flex flex-1 flex-col justify-center">
          <p className="px-4 pt-8 text-center font-serif text-xl text-bordeaux">
            {brand.nome} <span className="text-sm text-muted-foreground">{brand.descrittore}</span>
          </p>
          <ErroreDiPagina errore={error} onRetry={retry ?? reset} />
        </main>
      </body>
    </html>
  );
}
