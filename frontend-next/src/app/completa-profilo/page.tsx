import type { Metadata } from "next";
import { Suspense } from "react";
import CompletaProfiloPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Completa il profilo — Vinea Wine Club",
  description: "Conferma la tua data di nascita per completare l'accesso. Riservato ai maggiori di 18 anni.",
  robots: { index: false, follow: false },
};

export default function Page() {
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
      <CompletaProfiloPageClient />
    </Suspense>
  );
}
