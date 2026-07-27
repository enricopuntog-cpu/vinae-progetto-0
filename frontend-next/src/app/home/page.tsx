import type { Metadata } from "next";
import HomeUtentePageClient from "./page-client";

export const metadata: Metadata = {
  title: "Buongiorno, Elena — Vinea",
  description:
    "La tua home personale su Vinea: consigli, novità dai produttori seguiti, ribassi e attività.",
  openGraph: {
    title: "Home utente — Vinea",
    description: "Bottiglie consigliate, ribassi sui preferiti e attività community.",
  },
};

export default function Page() {
  return <HomeUtentePageClient />;
}
