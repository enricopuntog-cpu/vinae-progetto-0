import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import { creaWineRegionsService } from "@/services/wine-regions-service";
import { caricaMetaPerVino } from "@/services/wine-meta";
import { WineMetaProvider } from "@/lib/wine-meta-context";
import EsploraPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Ricerca bottiglie — Vinea",
  description: "Cerca tra centinaia di vini pregiati messi in vendita da privati.",
  openGraph: {
    title: "Ricerca — Vinea",
    description: "Filtra per regione, tipo, annata e prezzo.",
  },
};

/**
 * Gli annunci si caricano qui, sul server, e non nel componente client.
 *
 * Il filtro invece resta dov'era: in memoria, lato client. In frontend/ i
 * filtri reagiscono a ogni battuta senza latenza, e spostarli sul database
 * significherebbe una richiesta per carattere digitato — un comportamento
 * diverso da quello attuale, che questa fase non deve introdurre. Lo schema è
 * comunque già indicizzato per filtrare server-side (indice GIN trigram su
 * produttore+nome, indici su regione, tipo, annata, prezzo): quando il
 * catalogo sarà abbastanza grande da rendere insostenibile il caricamento
 * completo, il passaggio non richiederà una migrazione.
 */
const Page = async ({
  searchParams,
}: {
  searchParams: Promise<{ regione?: string }>;
}) => {
  const { regione } = await searchParams;
  const client = await getSupabaseServerClient();
  const listingService = createListingService(client);
  const wineRegionsService = creaWineRegionsService(client);

  // Le due letture sono indipendenti e partono insieme. Un guasto inatteso del
  // registro non deve respingere anche gli annunci: il filtro Regione diventa
  // indisponibile, mentre catalogo e ricerca ordinaria restano utilizzabili.
  const annunciPromise = listingService.elenco();
  const regioniPromise = wineRegionsService.elenco().catch((errore: unknown) => {
    console.error("[esplora] lettura regioni fallita:", errore);
    return { ok: false as const, error: "Regioni temporaneamente non disponibili." };
  });
  const [annunci, esitoRegioni] = await Promise.all([annunciPromise, regioniPromise]);

  // Finestra di bevuta e abbinamenti stanno su `wines` dalla Fase 6c-1. Si
  // caricano qui e non nei componenti: `DrinkBadge` compare su ogni scheda, e
  // una lettura per scheda significherebbe una cascata di richieste e un
  // distintivo che appare a pagina già disegnata.
  const metaPerVino = await caricaMetaPerVino(
    client,
    annunci.map((a) => a.wineSlug ?? a.id),
  );

  return (
    <WineMetaProvider metaPerVino={metaPerVino}>
      <EsploraPageClient
        annunci={annunci}
        initialRegion={regione}
        regioniCanoniche={esitoRegioni.ok && esitoRegioni.data.length > 0 ? esitoRegioni.data : null}
      />
    </WineMetaProvider>
  );
};

export default Page;
