import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { MarketValidationAdminClient } from "@/components/vinea/market-validation/MarketValidationAdminClient";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { eAdminReale } from "@/lib/auth/role";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Market Validation — Vinea",
  description: "Analytics aggregate e pseudonime del test Market Validation.",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO =
  `/accedi?${PARAMETRO_NEXT}=%2Fadmin%2Fbeta-validation`;

export default async function Page() {
  await connection();

  const client = await getSupabaseServerClient();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(PERCORSO_ACCESSO);

  const { data, error } = await client
    .from("user_roles")
    .select("role")
    .eq("user_id", utente.id);

  const ruoli = error
    ? []
    : (data ?? [])
        .map((riga) => (riga as { role: unknown }).role)
        .filter((ruolo): ruolo is string => typeof ruolo === "string");

  if (!eAdminReale(ruoli)) notFound();

  return <MarketValidationAdminClient />;
}
