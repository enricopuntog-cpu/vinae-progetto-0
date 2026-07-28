import type { Metadata } from "next";
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
  return <RegistratiPageClient />;
}
