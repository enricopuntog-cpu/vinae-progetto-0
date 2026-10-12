import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import {
  AcquistiPartnerNonDisponibili,
  AcquistoNonVerificato,
} from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { routes } from "@/config/routes";
import { statoAcquistoDa } from "@/lib/partner/vetrina";
import { MAX_BOTTIGLIE_PER_ORDINE, quantitaDaTesto } from "@/lib/cantina/gruppo";
import { createListingService } from "@/services/listing-service";
import { creaVetrinaPartnerPubblicaService } from "@/services/partner-vetrina-service";
import CheckoutPageClient from "./page-client";

export const generateMetadata = async ({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> => {
  const { id } = await params;
  const wine = await createListingService(await getSupabaseServerClient()).dettaglio(id);
  return { title: wine ? `Checkout — ${wine.nome} | Vinea Beta` : "Checkout — Vinea Beta" };
};

const Page = async ({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ prop?: string; quantita?: string }>;
}) => {
  const [{ id }, ricerca] = await Promise.all([params, searchParams]);
  const client = await getSupabaseServerClient();
  const wine = await createListingService(client).dettaglio(id);
  if (!wine) notFound();
  // Un indirizzo diretto, un vecchio link o una proposta accettata prima
  // dell'attivazione non devono aprire un checkout che i gate del database
  // rifiuterebbero all'ultimo passo. Una verifica fallita non apre il
  // checkout: non è una disponibilità confermata.
  const statoAcquisto = statoAcquistoDa(
    wine.venditore.userId
      ? await creaVetrinaPartnerPubblicaService(client).acquistoDisponibile(wine.venditore.userId)
      : null,
  );
  if (statoAcquisto !== "disponibile") {
    return (
      <div className="mx-auto max-w-xl space-y-4 py-8">
        <h1 className="font-serif text-3xl">Checkout non disponibile</h1>
        {statoAcquisto === "partner" ? <AcquistiPartnerNonDisponibili /> : <AcquistoNonVerificato />}
        <Link href={`/annuncio/${wine.id}`} className="inline-block text-sm font-medium text-bordeaux underline">
          Torna al prodotto
        </Link>
        {wine.venditore.userId ? (
          <Link
            href={routes.profiloPubblico(wine.venditore.userId)}
            className="ml-4 inline-block text-sm font-medium text-bordeaux underline"
          >
            Vedi il venditore
          </Link>
        ) : null}
      </div>
    );
  }
  // VP-C: una quantità dall'indirizzo vale solo se è un intero fra 1 e le
  // bottiglie disponibili (e il massimo per ordine); altrimenti 1. Il database
  // la riverifica e oggi ne accetta una sola per ordine.
  const quantita =
    quantitaDaTesto(
      ricerca.quantita ?? "",
      Math.max(1, Math.min(wine.disponibili, MAX_BOTTIGLIE_PER_ORDINE)),
    ) ?? undefined;
  return <CheckoutPageClient wine={wine} proposalId={ricerca.prop} quantita={quantita} />;
};

export default Page;
