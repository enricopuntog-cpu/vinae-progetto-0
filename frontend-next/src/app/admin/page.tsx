import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { ModerationPanelClient } from "@/components/vinea/moderation/ModerationPanelClient";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import { eAdminReale } from "@/lib/auth/role";
import { getSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Moderazione — Vinea",
  description: "Coda segnalazioni, controversie ordini e registro delle azioni di moderazione.",
  robots: { index: false, follow: false },
};

/** Come `/vendite`: scritto per esteso, mai dedotto dall'URL in arrivo. */
const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fadmin`;

/**
 * D10 — la guardia server dell'Area Admin.
 *
 * ## Che cosa c'era prima, e perché non bastava
 *
 * Questa route era `const Page = () => <ModerationPanelClient />`, e il
 * pannello si chiudeva da solo con `ruolo === "admin"` letto dallo store. Con
 * `NEXT_PUBLIC_DEMO_UI_ENABLED=true` quel `ruolo` è **quello scelto nel
 * selettore Guest/User/Admin**: chiunque poteva scegliere «Admin» e ottenere
 * la pagina. Non otteneva i dati — le viste `moderation_*` sono
 * `security_invoker = off` e filtrano su `user_roles`, le RPC rifiutano con
 * 42501 — ma otteneva la superficie, e una superficie di moderazione che si
 * apre a chi non è moderatore è un difetto anche quando è vuota: dice quali
 * comandi esistono, e trasforma una porta chiusa in una porta che sembra
 * rotta.
 *
 * ## Dove sta il confine
 *
 * Non qui. Il confine è `public.user_roles`, e resta l'unica ragione per cui i
 * dati non escono. Questa guardia e quella del client sono le due facce della
 * stessa comodità: rendere visibile solo a chi passerà il controllo del
 * database ciò che il database gli lascerebbe comunque leggere. La differenza
 * fra le due è che questa non passa dallo store, quindi il selettore demo non
 * la raggiunge.
 *
 * ## Le tre uscite
 *
 * - senza sessione → `/accedi?next=/admin`, come ogni altra pagina privata;
 * - con sessione ma senza il ruolo reale → `notFound()`. Non un messaggio di
 *   permesso negato: a chi non modera, l'esistenza del pannello non è un dato
 *   dovuto. Il `PermissionDeniedState` del client resta per il caso in cui il
 *   ruolo si perda mentre la pagina è già aperta;
 * - Supabase non configurato → nessuna sessione verificabile, quindi il primo
 *   ramo. Chiuso, non aperto: in CI `bun run build` gira senza variabili
 *   d'ambiente.
 *
 * Nessun `service_role` qui dentro. Il client è quello anon con i cookie della
 * richiesta, e la lettura di `user_roles` passa dalla stessa RLS
 * `user_roles_select_own` che usa il browser: la risposta è la stessa, cambia
 * solo dove viene calcolata.
 */
export default async function Page() {
  // Ferma il prerender: `redirect()` valutato in generazione statica finirebbe
  // cotto nella pagina. Stessa ragione — e stessa forma — di `/vendite`.
  await connection();

  const client = await getSupabaseServerClient();
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!client || !utente) redirect(PERCORSO_ACCESSO);

  // `select("role")` e non `select("*")`: il GRANT espone `(user_id, role)` e
  // la policy limita la lettura alla riga di `auth.uid()`. L'`eq` è esplicito
  // ma non è ciò che protegge — la policy lo è.
  const { data, error } = await client
    .from("user_roles")
    .select("role")
    .eq("user_id", utente.id);

  // Errore di lettura: si cade sul ruolo meno privilegiato, come fa
  // `auth-service.ruoliProfilo`. Un guasto non deve aprire una porta.
  const ruoli = error
    ? []
    : (data ?? [])
        .map((riga) => (riga as { role: unknown }).role)
        .filter((ruolo): ruolo is string => typeof ruolo === "string");

  if (!eAdminReale(ruoli)) notFound();

  return <ModerationPanelClient />;
}
