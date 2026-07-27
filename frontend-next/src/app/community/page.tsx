import type { Metadata } from "next";
import CommunityHubPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Club Vinea",
  description:
    "Club Vinea per territorio, denominazione, produttore e tipologia. Barolo, Brunello, Champagne, Borgogna, naturali, grandi formati e Amarone.",
  openGraph: {
    title: "Club — Vinea Wine Club",
    description: "Racconti, degustazioni, confronti e sondaggi sui grandi vini.",
  },
};

export default function Page() {
  return <CommunityHubPageClient />;
}
