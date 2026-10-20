import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { AccessoriAdminClient } from "@/components/vinea/accessori/AccessoriAdminClient";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { eAdminReale } from "@/lib/auth/role";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Accessori — Admin",
  description: "Catalogo Beta degli accessori: categorie, schede e bozze.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fadmin%2Faccessori`;

/**
 * Stessa guardia server di `/admin` e `/admin/partner`: il ruolo reale da
 * `public.user_roles`, mai dal selettore demo, e questa pagina NON dipende
 * dalle flag degli Accessori (l'admin deve poter lavorare con la sezione
 * spenta). Il confine resta il database: ogni porta `accessori_admin_*`
 * ricontrolla il ruolo da sé.
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

  return <AccessoriAdminClient />;
}
