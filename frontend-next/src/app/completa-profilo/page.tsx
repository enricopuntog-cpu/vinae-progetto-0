import type { Metadata } from "next";
import CompletaProfiloPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Completa il profilo — Vinea Wine Club",
  description: "Conferma la tua data di nascita per completare l'accesso. Riservato ai maggiori di 18 anni.",
  robots: { index: false, follow: false },
};

export default function Page() {
  return <CompletaProfiloPageClient />;
}
