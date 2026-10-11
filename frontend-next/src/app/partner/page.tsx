import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { PartnerAreaClient } from "@/components/vinea/partner/PartnerAreaClient";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Area Partner — Vinea",
  description: "Dati dell'attività e stato della richiesta Vinea Partner.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fpartner`;

/** Pagina privata: senza sessione si va ad accedere, come `/vendite`. */
export default async function Page() {
  await connection();

  const client = await getSupabaseServerClient();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(PERCORSO_ACCESSO);

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8">
      <header>
        <h1 className="font-serif text-3xl">Vinea Partner</h1>
        <p className="text-muted-foreground">La tua attività su Vinea.</p>
      </header>
      <PartnerAreaClient />
    </div>
  );
}
