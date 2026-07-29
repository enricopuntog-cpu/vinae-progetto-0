import type { Metadata } from "next";
import CantinaPageClient from "./page-client";

export const metadata: Metadata = {
  title: "La mia cantina — Vinea",
  description: "Le tue bottiglie, il tuo patrimonio enologico.",
  openGraph: {
    title: "La mia cantina — Vinea",
    description: "Gestisci la tua collezione personale con dashboard, vista 3D e abbinamenti.",
  },
};

/**
 * La cantina è privata: non c'è nulla da caricare sul server, perché non c'è
 * nulla da mostrare a chi non ha una sessione. Bottiglie, ambienti e moduli
 * arrivano dallo store (`cellar-domain.ts`), che li legge dal browser con la
 * sessione dell'utente — la stessa scelta già fatta per l'autenticazione in
 * Fase 5a, e l'unica che lascia una sola fonte di verità anche per la scheda
 * annuncio e la ricerca per abbinamento, che leggono le stesse bottiglie.
 */
export default function Page() {
  return <CantinaPageClient />;
}
