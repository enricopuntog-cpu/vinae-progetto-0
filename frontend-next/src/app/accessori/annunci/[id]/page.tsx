import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { StatoVuotoAccessori } from "@/components/vinea/accessori/AccessoriVetrina";
import { StimaSpedizioneAccessorio } from "@/components/vinea/accessori-spedizione/StimaSpedizioneAccessorio";
import { PrenotazioneAccessorio } from "@/components/vinea/ordini-accessori/PrenotazioneAccessorio";
import { accessoriLogisticaAbilitataServer, accessoriOrdiniAbilitatoServer } from "@/config/features";
import { DettaglioAnnuncioPubblico } from "@/components/vinea/accessori-vendita/AnnunciPubblici";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAnnunciAccessoriPubbliciService } from "@/services/annunci-accessori-service";

export const metadata: Metadata = {
  title: "Annuncio Accessori — Vinea",
  robots: { index: false, follow: false },
};

/**
 * Dettaglio di un annuncio Accessori pubblicato (VPM-015B3). Con le flag server
 * spente (default) è una vetrina: il prezzo è indicativo e gli acquisti non sono
 * disponibili. Con `ACCESSORI_ORDINI_ENABLED` mostra, sotto la stima di
 * spedizione, la prenotazione (VPM-015B5A): nessun pagamento, e solo se il
 * database la apre. Un annuncio non pubblicato, oscurato, ritirato o inesistente
 * risponde 404 senza distinguere i casi.
 */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const client = await getSupabaseServerClient();
  const modalita = await risolviModalitaAccessori(client);
  if (!modalita) notFound();

  const servizio = creaAnnunciAccessoriPubbliciService(client);
  const esito = await servizio.dettaglio(id);
  if (!esito.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="L'annuncio non è raggiungibile"
          messaggio="Non siamo riusciti a caricare questo annuncio. Riprova fra qualche istante."
        />
      </main>
    );
  }
  if (!esito.data) notFound();

  const foto = await servizio.urlFoto(esito.data.foto);
  let autenticato = false;
  try {
    autenticato = Boolean(client && (await client.auth.getUser()).data.user);
  } catch {
    autenticato = false;
  }

  return (
    <>
      <DettaglioAnnuncioPubblico
        annuncio={esito.data}
        immagini={foto.ok ? foto.data : {}}
        modalita={modalita}
        autenticato={autenticato}
      />
      {accessoriLogisticaAbilitataServer() ? (
        <StimaSpedizioneAccessorio annuncioId={esito.data.id} disponibili={esito.data.quantita} />
      ) : null}
      {accessoriOrdiniAbilitatoServer() ? (
        <PrenotazioneAccessorio annuncioId={esito.data.id} autenticato={autenticato} />
      ) : null}
    </>
  );
}
