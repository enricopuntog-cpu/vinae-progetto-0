import type { Metadata } from "next";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
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
export default async function Page() {
  const client = await getSupabaseServerClient();
  const annunci = await createListingService(client).elenco();

  return <EsploraPageClient annunci={annunci} />;
}
