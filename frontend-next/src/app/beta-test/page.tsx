import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import {
  MARKET_VALIDATION_UI_ABILITATA,
  marketValidationAbilitataServer,
  marketValidationQuestionnaireV2AbilitatoServer,
} from "@/config/features";
import { marketValidationShippingFeeCents } from "@/lib/market-validation/config";
import BetaTestPageClient from "./page-client";
import LegacyBetaTestPageClient from "./page-client-legacy";

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

  const shippingFeeCents = marketValidationShippingFeeCents();
  return marketValidationQuestionnaireV2AbilitatoServer()
    ? <BetaTestPageClient shippingFeeCents={shippingFeeCents} />
    : <LegacyBetaTestPageClient shippingFeeCents={shippingFeeCents} />;
}
