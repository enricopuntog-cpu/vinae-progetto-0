import type { Metadata } from "next";
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
  return <DegustazionePageClient bottleId={bottleId} />;
}
