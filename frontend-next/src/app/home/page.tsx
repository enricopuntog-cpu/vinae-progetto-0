import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import HomeUtentePageClient from "./page-client";

export const metadata: Metadata = {
  title: "La tua home — Vinea",
  description: "La tua home personale su Vinea: cantina, annunci e notifiche reali.",
  openGraph: {
    title: "Home utente — Vinea",
    description: "Cantina, annunci e notifiche collegati al tuo profilo.",
  },
};

const Page = async () => {
  const client = await getSupabaseServerClient();
  const annunci = await createListingService(client).elenco();

  return <HomeUtentePageClient annunci={annunci} />;
};

export default Page;
