import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SchedaVinoCatalogo } from "@/components/vinea/SchedaVinoCatalogo";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { leggiSchedaCanonica } from "@/lib/wine-intelligence/scheda-canonica";

/**
 * WI-008 — scheda autonoma di un vino del catalogo canonico. Solo per utenti autenticati e mai indicizzata: niente
 * metadati dal catalogo (il titolo non conferma a un estraneo che il codice esiste), nessuna sitemap. A catalogo
 * spento ogni codice risponde 404, come un codice inesistente.
 */
export const metadata: Metadata = {
  title: "Scheda del catalogo — Vinea",
  robots: { index: false, follow: false },
};

export default async function Page({ params }: { params: Promise<{ lwin7: string }> }) {
  const { lwin7 } = await params;
  const esito = await leggiSchedaCanonica(await getSupabaseServerClient(), lwin7);
  if (esito.stato === "trovata") return <SchedaVinoCatalogo scheda={esito.scheda} codiceRichiesto={lwin7} />;
  if (esito.stato === "assente") notFound();
  if (esito.stato === "accesso") {
    // `lwin7` qui è già sette cifre (altrimenti l'esito è «assente»): il percorso di rientro è relativo e chiuso.
    const rientro = new URLSearchParams({ [PARAMETRO_NEXT]: `/vino-catalogo/${lwin7}` }).toString();
    return (
      <div className="mx-auto max-w-2xl p-6 text-sm" data-testid="scheda-catalogo-accesso">
        <p>La scheda del catalogo è riservata agli utenti registrati.</p>
        <Link href={`/accedi?${rientro}`} className="underline">
          Accedi
        </Link>
      </div>
    );
  }
  return (
    <p className="mx-auto max-w-2xl p-6 text-sm" role="alert" data-testid="scheda-catalogo-non-disponibile">
      La scheda non è disponibile in questo momento. Riprova tra poco.
    </p>
  );
}
