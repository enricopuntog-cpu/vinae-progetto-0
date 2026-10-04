import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import {
  MARKET_VALIDATION_UI_ABILITATA,
  marketValidationAbilitataServer,
} from "@/config/features";
import BetaTestPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Prova Vinea",
  description: "Porta di ingresso al programma Market Validation di Vinea Wine Club.",
  robots: { index: false, follow: false },
};

export default async function Page() {
  await connection();
  if (!MARKET_VALIDATION_UI_ABILITATA || !marketValidationAbilitataServer()) {
    notFound();
  }

  return <BetaTestPageClient />;
}
