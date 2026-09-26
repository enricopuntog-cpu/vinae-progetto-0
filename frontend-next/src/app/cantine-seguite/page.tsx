import type { Metadata } from "next";
import { CantineSeguitePageClient } from "@/app/cantine-seguite/page-client";

/**
 * «Le mie Cantine»: l'elenco delle Cantine che io seguo.
 *
 * Fuori dagli indici, come le altre pagine private: `cantine_seguite_page` non
 * accetta l'identificativo di nessuno e risponde solo per `auth.uid()`, quindi
 * questo indirizzo non ha una versione pubblica da far trovare — un crawler ci
 * troverebbe soltanto l'invito ad accedere.
 *
 * Non c'è `redirect()` verso l'accesso: chi arriva senza sessione riceve un
 * invito dentro la pagina, come in `/account`. La differenza conta perché questo
 * indirizzo è il bersaglio di un `next`, e un redirect renderebbe più difficile
 * riconoscere dove si era diretti.
 */
export const metadata: Metadata = {
  title: "Le mie Cantine — Vinea",
  description: "Le Cantine che segui.",
  robots: { index: false, follow: false },
};

const Page = () => <CantineSeguitePageClient />;

export default Page;
