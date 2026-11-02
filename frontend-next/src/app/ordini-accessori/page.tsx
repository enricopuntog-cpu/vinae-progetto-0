import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { ElencoOrdiniAccessori } from "@/components/vinea/ordini-accessori/OrdiniAccessori";
import { accessoriOrdiniAbilitatoServer } from "@/config/features";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";

export const metadata: Metadata = {
  title: "Ordini Accessori — Vinea",
  robots: { index: false, follow: false },
};

/** Prenotazioni e ordini Accessori dell'utente, come acquirente e come venditore. */
export default async function Page() {
  await connection();
  const client = await getSupabaseServerClient();
  if (!accessoriOrdiniAbilitatoServer() || !(await risolviModalitaAccessori(client))) notFound();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(`/accedi?${PARAMETRO_NEXT}=%2Fordini-accessori`);

  const servizio = creaAccessoriOrdiniService(client);
  const [acquisti, vendite] = await Promise.all([servizio.elenca("acquisti"), servizio.elenca("vendite")]);

  return (
    <main id="contenuto-principale" className="mx-auto max-w-3xl space-y-8 px-4 py-8">
      <header>
        <h1 className="font-serif text-3xl">Ordini Accessori</h1>
        <p className="text-muted-foreground">
          Le prenotazioni non sono pagamenti: finché il pagamento non è attivo non viene addebitato nulla.
        </p>
      </header>
      {acquisti.ok ? (
        <ElencoOrdiniAccessori titolo="I tuoi acquisti" ordini={acquisti.data} vuoto="Non hai ancora prenotato nulla." />
      ) : (
        <p role="alert">{acquisti.error}</p>
      )}
      {vendite.ok ? (
        <ElencoOrdiniAccessori titolo="Le tue vendite" ordini={vendite.data} vuoto="Nessuna vendita per ora." />
      ) : (
        <p role="alert">{vendite.error}</p>
      )}
    </main>
  );
}
