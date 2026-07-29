import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import { caricaMetaPerVino } from "@/services/wine-meta";
import { WineMetaProvider } from "@/lib/wine-meta-context";
import { formatEUR } from "@/lib/format";
import AnnuncioDetailPageClient from "./page-client";

/**
 * Il segmento [id] contiene lo slug dell'annuncio, non un UUID: è la stessa
 * forma di URL di prima della migrazione (/annuncio/monfortino-2015). Il nome
 * del segmento resta `id` per non spostare il file e rompere i link esistenti.
 */
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const client = await getSupabaseServerClient();
  const wine = await createListingService(client).dettaglio(id);

  if (!wine) {
    return { title: "Annuncio non trovato — Vinea" };
  }
  const title = `${wine.nome} ${wine.annata} — ${wine.produttore} | Vinea`;
  const description = `${wine.produttore} ${wine.nome} ${wine.annata}, ${wine.regione}. In vendita a ${formatEUR(wine.prezzo)}.`;
  return {
    title,
    description,
    openGraph: {
      title,
      description,
      images: [wine.immagini[0]],
    },
    twitter: {
      images: [wine.immagini[0]],
    },
  };
}

export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const client = await getSupabaseServerClient();
  const service = createListingService(client);

  // In parallelo: la richiesta dei correlati non dipende dall'esito del
  // dettaglio, quindi non c'è motivo di metterla in coda.
  const [wine, tutti] = await Promise.all([service.dettaglio(id), service.elenco()]);

  if (!wine) notFound();

  const correlati = tutti.filter((w) => w.id !== wine.id).slice(0, 4);

  // Il vino della scheda più quelli dei correlati: "Quando berlo", gli
  // abbinamenti e i distintivi delle schede correlate leggono tutti da qui.
  const metaPerVino = await caricaMetaPerVino(client, [
    wine.wineSlug ?? wine.id,
    ...correlati.map((c) => c.wineSlug ?? c.id),
  ]);

  return (
    <WineMetaProvider metaPerVino={metaPerVino}>
      <AnnuncioDetailPageClient wine={wine} correlati={correlati} />
    </WineMetaProvider>
  );
}
