import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { DettaglioOrdineAccessorio } from "@/components/vinea/ordini-accessori/OrdiniAccessori";
import { accessoriOrdiniAbilitatoServer } from "@/config/features";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";

export const metadata: Metadata = {
  title: "Ordine Accessori — Vinea",
  robots: { index: false, follow: false },
};

/** Un ordine Accessori, solo alle sue due parti; chiunque altro vede 404. */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  await connection();
  const { id } = await params;
  const client = await getSupabaseServerClient();
  if (!accessoriOrdiniAbilitatoServer() || !(await risolviModalitaAccessori(client))) notFound();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(`/accedi?${PARAMETRO_NEXT}=${encodeURIComponent(`/ordini-accessori/${id}`)}`);

  const esito = await creaAccessoriOrdiniService(client).leggi(id);
  if (!esito.ok) notFound();

  return (
    <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-8">
      <DettaglioOrdineAccessorio iniziale={esito.data} />
    </main>
  );
}
