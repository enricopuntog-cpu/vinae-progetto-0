import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import HomePageClient from "./page-client";

export const metadata: Metadata = {
  title: "Vinea — Ogni bottiglia ha una storia",
  description: "Il marketplace sociale italiano per il vino tra privati.",
  openGraph: {
    title: "Vinea — Marketplace sociale del vino",
    description: "Compra, vendi e scopri vini pregiati tra privati appassionati.",
  },
};

export default async function Page() {
  const client = await getSupabaseServerClient();
  const annunci = await createListingService(client).elenco();

  return <HomePageClient annunci={annunci} />;
}
