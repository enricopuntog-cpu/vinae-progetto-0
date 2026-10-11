import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { partnerCommercialeDelChiamante } from "@/lib/partner/classe-server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import DegustazionePageClient from "./page-client";

/**
 * Come la Cantina, questa pagina non carica niente sul server: la bottiglia è
 * privata e la sua riga la legge il browser con la sessione dell'utente, dallo
 * stesso store che alimenta `/cantina`. Caricarla qui vorrebbe dire una seconda
 * fonte di verità sulla stessa riga.
 *
 * `noindex` non è prudenza: il segmento è un UUID di `bottle_units` e la pagina
 * parla di cosa qualcuno ha bevuto e cosa ne ha pensato. Non è materiale da
 * motore di ricerca nemmeno se l'indirizzo trapelasse.
 */
export const metadata: Metadata = {
  title: "Degustazione — Vinea",
  description: "La bottiglia che hai aperto e le tue impressioni.",
  robots: { index: false, follow: false },
};

export default async function Page({ params }: { params: Promise<{ bottleId: string }> }) {
  const { bottleId } = await params;
  // Per un Partner attivo o sospeso la Cantina è il catalogo commerciale: la
  // degustazione personale non è fra i suoi strumenti (Blocco B). Le bottiglie
  // e le note restano nel database, intatte.
  if (await partnerCommercialeDelChiamante(await getSupabaseServerClient())) redirect("/cantina");
  return <DegustazionePageClient bottleId={bottleId} />;
}
