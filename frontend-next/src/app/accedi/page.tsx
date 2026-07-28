import type { Metadata } from "next";
import { Suspense } from "react";
import AccediPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Accedi — Vinea Wine Club",
  description: "Accedi a Vinea con email e password, oppure ricevi un link di accesso via email.",
  openGraph: {
    title: "Accesso — Vinea Wine Club",
    description: "Entra nel tuo account Vinea.",
  },
};

export default function Page() {
  // Suspense richiesto perché la pagina legge `?errore=` con useSearchParams
  // (lo riporta /auth/callback quando il flusso OAuth non si completa): senza
  // boundary il prerender statico di questa route fallisce.
  return (
    <Suspense
      fallback={
        <div className="mx-auto max-w-md">
          <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
            <p className="text-sm text-muted-foreground">Caricamento…</p>
          </div>
        </div>
      }
    >
      <AccediPageClient />
    </Suspense>
  );
}
