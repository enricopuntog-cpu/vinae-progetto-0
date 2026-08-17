import type { Metadata } from "next";
import AccountPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Il tuo profilo — Vinea Wine Club",
  description:
    "Modifica nome utente, presentazione, città, livello di esperienza e avatar del tuo profilo Vinea.",
  robots: { index: false, follow: false },
};

export default function Page() {
  return <AccountPageClient />;
}
