import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { AccessoriPostvenditaAdmin } from "@/components/vinea/ordini-accessori/AccessoriPostvenditaAdmin";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { eAdminReale } from "@/lib/auth/role";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriPostvenditaService } from "@/services/accessori-postvendita-service";

export const metadata: Metadata = {
  title: "Post-vendita Accessori — Admin",
  description: "Contestazioni, rimborsi e resi degli ordini Accessori.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fadmin%2Faccessori-postvendita`;

/**
 * Stessa guardia server di `/admin/accessori`: il ruolo reale da
 * `public.user_roles` e nessuna dipendenza dalle flag, perche gli obblighi
 * economici gia esistenti (un rimborso dovuto) devono restare gestibili anche a
 * sezione spenta. Il confine resta il database: ogni porta ricontrolla il ruolo.
 */
export default async function Page() {
  await connection();
  const client = await getSupabaseServerClient();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(PERCORSO_ACCESSO);

  const { data, error } = await client.from("user_roles").select("role").eq("user_id", utente.id);
  const ruoli = error
    ? []
    : (data ?? [])
        .map((riga) => (riga as { role: unknown }).role)
        .filter((ruolo): ruolo is string => typeof ruolo === "string");
  if (!eAdminReale(ruoli)) notFound();

  const servizio = creaAccessoriPostvenditaService(client);
  const [elenco, orfani, dovuti] = await Promise.all([
    servizio.adminElenco(),
    servizio.adminIntentiOrfani(),
    servizio.adminRimborsiDovuti(),
  ]);
  if (!elenco.ok) notFound();

  return (
    <main id="contenuto-principale" className="mx-auto max-w-4xl px-4 py-8">
      <h1 className="font-display text-2xl">Post-vendita Accessori</h1>
      <div className="mt-6">
        <AccessoriPostvenditaAdmin iniziale={elenco.data} pagamenti={{ orfani, dovuti }} />
      </div>
    </main>
  );
}
