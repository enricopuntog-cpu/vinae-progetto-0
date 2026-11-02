import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { DettaglioOrdineAccessorio } from "@/components/vinea/ordini-accessori/OrdiniAccessori";
import { PostvenditaErrore } from "@/components/vinea/ordini-accessori/PostvenditaErrore";
import { caricaFascicolo, dettaglioAccessorioDisponibile } from "@/lib/accessori-postvendita/fascicolo";
import { PostVenditaAccessorioPannello } from "@/components/vinea/ordini-accessori/PostVenditaAccessorio";
import { AZIONI_PAGAMENTO_ABILITATE, accessoriOrdiniAbilitatoServer } from "@/config/features";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";
import { creaAccessoriPostvenditaService } from "@/services/accessori-postvendita-service";

export const metadata: Metadata = {
  title: "Ordine Accessori — Vinea",
  robots: { index: false, follow: false },
};

/** Un ordine Accessori, solo alle sue due parti; chiunque altro vede 404. */
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ checkout?: string }>;
}) {
  await connection();
  const { id } = await params;
  const { checkout } = await searchParams;
  const client = await getSupabaseServerClient();
  const commercioAperto = accessoriOrdiniAbilitatoServer() && !!(await risolviModalitaAccessori(client));
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(`/accedi?${PARAMETRO_NEXT}=${encodeURIComponent(`/ordini-accessori/${id}`)}`);

  const esito = await creaAccessoriOrdiniService(client).leggi(id);
  if (!esito.ok) notFound();

  // Post-vendita (B5C): solo per un ordine incassato dal fornitore; per gli altri il pannello non compare.
  const servizioPostvendita = creaAccessoriPostvenditaService(client);
  const fascicolo = await caricaFascicolo(servizioPostvendita, id);
  // Nessun nuovo checkout: l'eccezione è solo per il post-vendita già incassato.
  // Se la lettura fallisce su un ordine pagato reale, resta il riprova, mai comandi privilegiati.
  if (!dettaglioAccessorioDisponibile(commercioAperto, fascicolo, esito.data)) notFound();

  // `checkout_attivo` nel database: se la lettura fallisce il pagamento resta chiuso (fail-closed).
  // Solo l acquirente di una prenotazione ancora aperta ha bisogno di saperlo.
  const checkoutAperto =
    esito.data.ruolo === "acquirente" && esito.data.stato === "in_attesa_pagamento"
      ? await creaAccessoriOrdiniService(client)
          .disponibilita(esito.data.annuncioId)
          .then((d) => d.ok && d.data.motivo !== "checkout_non_attivo")
      : false;

  return (
    <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-8">
      <DettaglioOrdineAccessorio
        iniziale={esito.data}
        pagamento={{
          // Solo un filtro di interfaccia: i gate autoritativi sono nella Edge Function e nel database.
          azioniAbilitate: commercioAperto && checkoutAperto && AZIONI_PAGAMENTO_ABILITATE,
          chiavePublishable: process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? null,
          // Un invito a rileggere l ordine dopo il ritorno da Stripe, mai una prova di pagamento.
          inRitorno: checkout === "ritorno",
        }}
      />
      {fascicolo.ok ? (
        <PostVenditaAccessorioPannello postvendita={fascicolo.data.postvendita} foto={fascicolo.data.foto} ruolo={esito.data.ruolo} />
      ) : <PostvenditaErrore />}
    </main>
  );
}
