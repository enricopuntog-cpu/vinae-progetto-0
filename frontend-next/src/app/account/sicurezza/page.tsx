import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { haRuoloContinuita } from "@/lib/auth/mfa";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import VerificaDuePassaggi from "./verifica-due-passaggi";

export const metadata: Metadata = {
  title: "Sicurezza dell'accesso — Vinea",
  robots: { index: false, follow: false },
};

const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Faccount%2Fsicurezza`;

/**
 * Verifica in due passaggi per chi ha un ruolo di continuità (admin ed
 * emergency_delegate). Agli utenti normali la MFA non è offerta: non esiste
 * oggi un flusso di login che la chieda loro, e mostrarla come "attiva"
 * prometterebbe una protezione che l'app non applica.
 */
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
  if (!haRuoloContinuita(ruoli)) notFound();

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <div>
        <h1 className="font-serif text-3xl font-semibold">Sicurezza dell&apos;accesso</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Le funzioni operative protette richiedono un secondo fattore oltre alla password.
        </p>
      </div>
      <VerificaDuePassaggi mostraContinuita />
    </div>
  );
}
