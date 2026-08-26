import type { Metadata } from "next";
import { Suspense } from "react";
import RegistratiPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Crea il tuo account — Vinea Wine Club",
  description: "Registrati a Vinea con email e password. Riservato ai maggiori di 18 anni.",
  openGraph: {
    title: "Registrazione — Vinea Wine Club",
    description: "Crea il tuo account Vinea per comprare, vendere e catalogare vino.",
  },
};

export default function Page() {
  // Suspense richiesto perché da D5 la pagina legge `?errore=` e `?next=` con
  // useSearchParams (li riporta /auth/callback quando il flusso non si
  // completa, e li propaga /accedi): senza boundary il prerender statico di
  // questa route fallisce. Stessa ragione e stessa forma di /accedi.
  return (
    <Suspense
      fallback={
        <div className="mx-auto max-w-2xl">
          <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
            <p className="text-sm text-muted-foreground">Caricamento…</p>
          </div>
        </div>
      }
    >
      <RegistratiPageClient />
    </Suspense>
  );
}
