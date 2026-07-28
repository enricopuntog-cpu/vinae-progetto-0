import type { Metadata } from "next";
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
  return <AccediPageClient />;
}
