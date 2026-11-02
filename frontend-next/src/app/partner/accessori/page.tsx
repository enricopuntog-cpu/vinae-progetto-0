import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { CantinaAccessori } from "@/components/vinea/cantina-accessori/CantinaAccessori";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Accessori nuovi — Area Partner — Vinea",
  description: "Scorte commerciali di Accessori nuovi del Vinea Partner.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fpartner%2Faccessori`;

/**
 * Scorte commerciali del Vinea Partner (VPM-015C). Pagina privata come
 * `/partner`: senza sessione si va ad accedere. Chi non è un Partner attivo (o
 * sospeso) o con la funzione Accessori spenta vede soltanto la spiegazione: la
 * sezione si nasconde da sola e ogni autorizzazione resta nel database.
 */
export default async function Page() {
  await connection();

  const client = await getSupabaseServerClient();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(PERCORSO_ACCESSO);

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8">
      <header>
        <h1 className="font-serif text-3xl">Accessori nuovi</h1>
        <p className="text-muted-foreground">
          Scorte e annunci commerciali della tua attività.{" "}
          <Link href="/partner" className="underline">
            Torna all&apos;area Partner
          </Link>
        </p>
      </header>
      <CantinaAccessori modalita="partner" />
      <p className="text-sm text-muted-foreground">
        La sezione è disponibile ai Partner attivi quando la funzione Accessori è aperta. La vendita
        ai clienti si apre solo con l&apos;approvazione di Vinea.
      </p>
    </div>
  );
}
