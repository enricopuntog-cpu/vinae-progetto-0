import type { Metadata } from "next";
import { CantinaCommerciale } from "@/components/vinea/partner/CantinaCommerciale";
import { ClasseNonVerificata } from "@/components/vinea/partner/ClasseNonVerificata";
import { classeDelChiamante } from "@/lib/partner/classe-server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaScortePartnerService } from "@/services/partner-scorte-service";
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
 * La cantina è privata: per un privato non c'è nulla da caricare sul server,
 * perché non c'è nulla da mostrare a chi non ha una sessione. Bottiglie,
 * ambienti e moduli arrivano dallo store (`cellar-domain.ts`), che li legge dal
 * browser con la sessione dell'utente — la stessa scelta già fatta per
 * l'autenticazione in Fase 5a, e l'unica che lascia una sola fonte di verità
 * anche per la scheda annuncio e la ricerca per abbinamento, che leggono le
 * stesse bottiglie.
 *
 * L'unica domanda che si fa al server è la classe (Blocco B Partner): per il
 * titolare di un Partner attivo o sospeso la Cantina è il catalogo
 * commerciale, non la collezione. La decide `partner_me()`; per tutti gli altri
 * — anonimi compresi — la pagina resta quella di sempre. Se la classe non si
 * legge, la pagina non indovina.
 */
export default async function Page() {
  const client = await getSupabaseServerClient();
  const classe = await classeDelChiamante(client);
  if (classe.tipo === "privato") return <CantinaPageClient />;
  if (classe.tipo === "errore") return <ClasseNonVerificata titolo="La mia cantina" riprova="/cantina" />;

  const { partner, titolareId } = classe;
  // VP-C: solo le scorte commerciali del titolare, mai le sue bottiglie
  // personali; la lettura è sul server con la sua sessione.
  const scorte = await creaScortePartnerService(client).elenco();
  return (
    <div className="mx-auto max-w-5xl">
      <CantinaCommerciale
        nomeCommerciale={partner.nomeCommerciale}
        stato={partner.stato}
        titolareId={titolareId}
        scorte={scorte}
      />
    </div>
  );
}
