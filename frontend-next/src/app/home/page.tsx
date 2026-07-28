import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
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

export default async function Page() {
  const client = await getSupabaseServerClient();
  const annunci = await createListingService(client).elenco();

  return <HomeUtentePageClient annunci={annunci} />;
}
