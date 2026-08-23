import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
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

  // Le tre letture sono indipendenti e partono insieme, come in
  // src/app/community/page.tsx: in serie la Home aspetterebbe la somma di tre
  // andate e ritorno per mostrare cose che non si condizionano a vicenda.
  //
  // I club si leggono qui e non in un effetto del client: il primo paint deve
  // avere i club veri invece di uno scheletro, e sulla Home non si scrive
  // nulla - il follow resta dove sta, cioe in /community e nella scheda del
  // club.
  //
  // `seguito` e `mio` di public_clubs li calcola la vista con auth.uid(), che
  // sul server viene dalla sessione nei cookie: la stessa lettura serve
  // entrambe le sezioni, e per un anonimo torna semplicemente con tutti i
  // `seguito` a false.
  const [annunci, esitoClub, utente] = await Promise.all([
    createListingService(client).elenco(),
    createSupabaseClubService(client).elenco(),
    // getUser() e non getSession(): la sessione la legge dal cookie, l'utente
    // lo fa verificare al server. Serve a distinguere "non segui ancora nessun
    // club" da "non hai una sessione", che sono due vuoti diversi.
    client ? client.auth.getUser() : Promise.resolve(null),
  ]);

  return (
    <HomePageClient
      annunci={annunci}
      clubs={esitoClub.ok ? esitoClub.data : []}
      // Un errore sui club non e un errore della Home: gli annunci si leggono
      // lo stesso e la sola sezione Club lo dichiara.
      erroreClub={esitoClub.ok ? null : esitoClub.error}
      autenticato={Boolean(utente?.data.user)}
    />
  );
}
