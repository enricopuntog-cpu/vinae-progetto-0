import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { StatoVuotoAccessori } from "@/components/vinea/accessori/AccessoriVetrina";
import { DettaglioAccessorio } from "@/components/vinea/accessori/DettaglioAccessorio";
import { ETICHETTE_STATO } from "@/lib/accessori/accessori";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriLetturaService } from "@/services/accessori-service";

export const metadata: Metadata = {
  title: "Accessori per il vino — Vinea",
  robots: { index: false, follow: false },
};

/**
 * Dettaglio di una scheda. Nessuna azione di acquisto: la scheda non ha
 * prezzo ne disponibilita, e da qui non parte nessun percorso verso checkout,
 * proposte, ordini o pagamenti. Una scheda in bozza, archiviata o inesistente
 * risponde 404 al pubblico; la bozza e visibile solo all'admin in anteprima.
 */
export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const client = await getSupabaseServerClient();
  const modalita = await risolviModalitaAccessori(client);
  if (!modalita) notFound();

  const esito = await creaAccessoriLetturaService(client).dettaglio(slug, modalita === "anteprima");
  if (!esito.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="La scheda non è raggiungibile"
          messaggio="Non siamo riusciti a caricare questo accessorio. Riprova fra qualche istante."
        />
      </main>
    );
  }
  if (!esito.data) notFound();

  const foto = await creaAccessoriLetturaService(client).urlImmagini(esito.data.immagini);

  return (
    <DettaglioAccessorio
      immagini={foto.ok ? foto.data : {}}
      scheda={esito.data}
      modalita={modalita}
      stato={esito.data.stato ? ETICHETTE_STATO[esito.data.stato] : null}
    />
  );
}
