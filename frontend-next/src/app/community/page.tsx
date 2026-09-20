import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { CLUB_UI_ABILITATA } from "@/config/features";
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
  if (!CLUB_UI_ABILITATA) notFound();
  const client = await getSupabaseServerClient();
  const servizio = createSupabaseClubService(client);
  // Le discussioni partono insieme ai club, ma non bloccano il tab iniziale.
  // La Promise resta nella singola richiesta: nessuna cache fra utenti.
  const discussioni = servizio.discussioni().then(
    (esito) => esito.ok ? esito.data : [],
    () => [],
  );
  const [esito, utente] = await Promise.all([
    servizio.elenco(),
    // getUser() e non getSession(): la sessione la legge dal cookie, l'utente
    // lo fa verificare al server. E la stessa scelta di src/app/vendi/actions.ts.
    // Senza client configurato non c'e utente, e il modulo non si monta.
    client ? client.auth.getUser() : Promise.resolve(null),
  ]);

  return (
    <CommunityHubPageClient
      iniziali={esito.ok ? esito.data : []}
      erroreLettura={esito.ok ? null : esito.error}
      // Un errore qui non e un errore della pagina: i club si leggono lo
      // stesso, e i due tab mostrano il proprio vuoto.
      discussioni={discussioni}
      autenticato={Boolean(utente?.data.user)}
    />
  );
}
