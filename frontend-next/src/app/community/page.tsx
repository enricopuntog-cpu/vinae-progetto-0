import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
import CommunityHubPageClient from "./page-client";

// La #44 aveva ridotto questa pagina a `notFound()` per togliere dalla beta
// pubblica una community fatta di dati finti. Il 12a la riporta con dati reali,
// che e la ragione per cui quello stub esisteva.
//
// `robots` non e dichiarato qui di proposito: l'app resta noindex, nofollow per
// decisione della #44 e il valore vive una volta sola in src/app/layout.tsx.
// Ridichiararlo qui creerebbe un secondo posto da cambiare il giorno in cui la
// beta esce dal noindex, ed e cosi che i due si scollano.
export const metadata: Metadata = {
  title: "Club Vinea",
  description:
    "I Club Vinea per territorio, denominazione, produttore e tipologia: leggi le schede e segui quelli che ti interessano.",
  openGraph: {
    title: "Club — Vinea Wine Club",
    description: "I club di Vinea per territorio, denominazione, produttore e tipologia.",
  },
};

export default async function Page() {
  const client = await getSupabaseServerClient();
  // La lettura sta qui e non in un effetto del client: e una pagina pubblica,
  // e il primo paint deve avere i club invece di uno scheletro. Il follow
  // resta client, perche e l'unica cosa che scrive.
  const esito = await createSupabaseClubService(client).elenco();

  return (
    <CommunityHubPageClient
      iniziali={esito.ok ? esito.data : []}
      erroreLettura={esito.ok ? null : esito.error}
    />
  );
}
