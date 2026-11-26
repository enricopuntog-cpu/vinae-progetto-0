import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { CatalogoAdminClient } from "@/components/vinea/catalogo-admin/CatalogoAdminClient";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { eAdminReale } from "@/lib/auth/role";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Catalogo vini — Admin",
  description: "Catalogo dei vini: proposte, identità, annate, fonti e storico.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fadmin%2Fcatalogo`;

/**
 * WI-012 — stessa guardia server delle altre pagine admin: ruolo reale da `public.user_roles`, mai dal selettore
 * demo. Il confine resta il database: ogni porta `catalogo_admin_*` ricontrolla il ruolo.
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

  return <CatalogoAdminClient />;
}
