import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import { creaPreventivoService } from "@/services/preventivo-service";
import { classeDelChiamante } from "@/lib/partner/classe-server";
import { statoAcquistoDaPreventivo } from "@/lib/prezzi/classe";
import { createSupabasePriceIntelligenceService } from "@/services/price-intelligence/supabase-price-intelligence-service";
import { caricaMetaPerVino } from "@/services/wine-meta";
import { WineMetaProvider } from "@/lib/wine-meta-context";
import { chiaveVino, componiVista } from "@/lib/price-intelligence/insights";
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
    // Può essere un annuncio inesistente oppure uno che esiste ma non è più
    // pubblico — sospeso, scaduto, ancora in bozza. I due casi non si
    // distinguono qui apposta: il titolo della scheda è ciò che finisce nei
    // risultati di ricerca e nelle anteprime dei link, e non deve confermare a
    // un estraneo che quell'annuncio esiste. Il proprietario la sua pagina la
    // vede lo stesso, con il pannello che gliene dice lo stato.
    return { title: "Annuncio non trovato — Vinea", robots: { index: false, follow: false } };
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
  //
  // `mioAnnuncio` parte anche per un visitatore anonimo, ma si ferma da sé
  // sulla sessione prima di interrogare: `anon` non ha nessun grant su
  // `public.listings`, quindi la domanda risponderebbe `42501` e non "zero
  // righe". Il dettaglio sta nel servizio, dove sta la ragione.
  const [wine, proprio, tutti] = await Promise.all([
    service.dettaglio(id),
    service.mioAnnuncio(id),
    service.elenco(),
  ]);

  // Un annuncio sospeso, scaduto o in bozza non esce più da `public_listings`.
  // Per il suo venditore la pagina deve restare raggiungibile lo stesso: è lì
  // che stanno prezzo, fotografie e descrizione, ed è da lì che si rimuove
  // dalla vendita. Per tutti gli altri resta un 404.
  const daMostrare = wine ?? proprio?.wine ?? null;
  if (!daMostrare) notFound();

  const correlati = tutti.filter((w) => w.id !== daMostrare.id).slice(0, 4);

  // Price Intelligence 1B.
  //
  // Lo storico è l'unica lettura in più che questa pagina fa: i comparabili
  // correnti escono da `tutti`, che è già in memoria perché serviva ai
  // correlati, e chiederli di nuovo al database sarebbe un viaggio pagato per
  // righe che abbiamo già. `elenco()` restituisce solo annunci attivi — il
  // filtro `stato = 'attivo'` sta dentro `public_listings` e non è un parametro
  // — quindi «attivo» qui non è un predicato da riscrivere ma una proprietà
  // della sorgente.
  //
  // Va in parallelo ai metadati del vino, che non dipendono da lui.
  const wineKey = chiaveVino(daMostrare);
  // VP-D: il preventivo autorevole dell'annuncio. Classe del venditore,
  // acquistabilità e prezzo per l'acquirente li decide il database con la
  // stessa riga e la stessa formula del checkout; un prodotto Partner con la
  // vendita chiusa, l'annuncio personale di un Partner o una lettura fallita
  // non offrono né acquisto né proposta. L'autorità restano le porte e i
  // trigger, che rifiuterebbero comunque.
  const [metaPerVino, storico, preventivo, classeVisitatore] = await Promise.all([
    // Il vino della scheda più quelli dei correlati: "Quando berlo", gli
    // abbinamenti e i distintivi delle schede correlate leggono tutti da qui.
    caricaMetaPerVino(client, [wineKey, ...correlati.map((c) => c.wineSlug ?? c.id)]),
    createSupabasePriceIntelligenceService(client).storico({
      // Lo slug e non l'UUID: `Wine` non porta `wine_id` e non deve iniziare a
      // portarlo per una lettura sola. La vista espone entrambe le colonne.
      wineSlug: wineKey,
      formato: daMostrare.formato,
    }),
    creaPreventivoService(client).annuncio(daMostrare.listingId ?? daMostrare.id),
    classeDelChiamante(client),
  ]);
  const statoAcquisto = statoAcquistoDaPreventivo(preventivo);
  // Anche una classe che non si legge toglie le azioni da collezionista: non
  // si sa se chi guarda è un privato.
  const visitatoreCommerciale = classeVisitatore.tipo !== "privato";

  // Un guasto dello storico non toglie la pagina a nessuno: il pannello lo dice
  // in un rigo e il riferimento sui comparabili, che non dipende da questa
  // lettura, resta in piedi.
  const vistaPrezzi = componiVista({
    annunciAttivi: tutti.map((w) => ({
      // L'identità dell'ANNUNCIO: è ciò che impedisce di contarlo due volte.
      chiave: w.listingId ?? w.id,
      wineKey: chiaveVino(w),
      formato: w.formato,
      prezzoCents: Math.round(w.prezzo * 100),
    })),
    wineKey,
    formato: daMostrare.formato,
    prezzoRichiestoCents: Math.round(daMostrare.prezzo * 100),
    osservazioni: storico.ok ? storico.data : [],
    storicoNonDisponibile: !storico.ok,
  });

  return (
    <WineMetaProvider metaPerVino={metaPerVino}>
      <AnnuncioDetailPageClient
        wine={daMostrare}
        correlati={correlati}
        proprio={proprio}
        vistaPrezzi={vistaPrezzi}
        statoAcquisto={statoAcquisto}
        preventivo={preventivo.ok ? preventivo.data : null}
        visitatoreCommerciale={visitatoreCommerciale}
      />
    </WineMetaProvider>
  );
}
