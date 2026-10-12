import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import {
  AcquistiPartnerNonDisponibili,
  AcquistoNonVerificato,
} from "@/components/vinea/partner/AcquistiPartnerNonDisponibili";
import { routes } from "@/config/routes";
import { statoAcquistoDaPreventivo } from "@/lib/prezzi/classe";
import { MAX_BOTTIGLIE_PER_ORDINE, quantitaDaTesto } from "@/lib/cantina/gruppo";
import { createListingService } from "@/services/listing-service";
import { creaPreventivoService } from "@/services/preventivo-service";
import { creaLogisticaService, type PreventivoLogistica } from "@/services/logistica-service";
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
  // VP-C: una quantità dall'indirizzo vale solo se è un intero fra 1 e le
  // bottiglie disponibili (e il massimo per ordine); altrimenti 1. Il database
  // la riverifica e oggi ne accetta una sola per ordine.
  const quantita =
    quantitaDaTesto(
      ricerca.quantita ?? "",
      Math.max(1, Math.min(wine.disponibili, MAX_BOTTIGLIE_PER_ORDINE)),
    ) ?? undefined;
  // VP-D: una proposta accettata si paga al suo prezzo per bottiglia e per la
  // sua quantità; li legge il server dalla riga che il partecipante può
  // vedere, non dall'indirizzo.
  const proposta = ricerca.prop && client
    ? (
        await client
          .from("proposals")
          .select("prezzo_proposto_cents,controproposta_cents,quantita,stato")
          .eq("id", ricerca.prop)
          .maybeSingle()
      ).data
    : null;
  // Il preventivo autorevole del database decide classe, acquistabilità e
  // importi. Un indirizzo diretto, un vecchio link, un prodotto Partner con la
  // vendita chiusa o una lettura fallita non aprono un checkout che i gate
  // rifiuterebbero all'ultimo passo.
  const bottiglie = proposta?.quantita ?? quantita ?? 1;
  const prezzoProposta =
    proposta?.stato === "accettata"
      ? (proposta.controproposta_cents ?? proposta.prezzo_proposto_cents)
      : undefined;
  const preventivo = await creaPreventivoService(client).annuncio(wine.listingId ?? wine.id, {
    quantita: bottiglie,
    prezzoUnitarioCents: prezzoProposta,
  });
  // VP-E: con più bottiglie la spedizione (colli, imballaggio, trasporto) entra
  // nel totale. Il preventivo è del database; se non si legge, il checkout la
  // tratta come non configurata e non si conferma con la spedizione.
  let logistica: PreventivoLogistica | null = null;
  if (bottiglie > 1) {
    const esito = await creaLogisticaService(client).preventivo(
      wine.listingId ?? wine.id,
      bottiglie,
      prezzoProposta,
    );
    logistica = esito.ok ? esito.data : null;
  }
  const statoAcquisto = statoAcquistoDaPreventivo(preventivo);
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
  return (
    <CheckoutPageClient
      wine={wine}
      proposalId={ricerca.prop}
      quantita={quantita}
      preventivo={preventivo.ok ? preventivo.data : null}
      bottiglie={bottiglie}
      logistica={logistica}
    />
  );
};

export default Page;
