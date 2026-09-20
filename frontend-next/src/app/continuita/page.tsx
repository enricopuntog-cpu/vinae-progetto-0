import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { IncidentNoticeAdmin } from "@/components/vinea/moderation/IncidentNoticeAdmin";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Continuità operativa — Vinea",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fcontinuita`;

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
  if (!ruoli.some((ruolo) => ruolo === "admin" || ruolo === "emergency_delegate")) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <div>
        <h1 className="font-serif text-3xl font-semibold">Continuità operativa</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Pubblica o ritira il solo avviso globale. Ogni modifica viene registrata.
        </p>
      </div>
      <IncidentNoticeAdmin />
    </div>
  );
}
