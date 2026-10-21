import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { StatoVuotoAccessori } from "@/components/vinea/accessori/AccessoriVetrina";
import { AnnunciVetrina } from "@/components/vinea/accessori-vendita/AnnunciPubblici";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { LIMITE_VETRINA_ANNUNCI } from "@/lib/accessori-vendita/annunci-pubblici";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAnnunciAccessoriPubbliciService } from "@/services/annunci-accessori-service";

export const metadata: Metadata = {
  title: "Annunci Accessori — Vinea",
  description: "Gli annunci di accessori per il vino messi in vetrina dalla community. Gli acquisti non sono ancora disponibili.",
  // Beta: la sezione non è un lancio commerciale e non va indicizzata.
  robots: { index: false, follow: false },
};

const PAGINE_MASSIME = 50;

/**
 * Vetrina degli annunci Accessori pubblicati (VPM-015B3). Sola lettura: nessun
 * acquisto, nessuna prenotazione, nessun collegamento al checkout.
 *
 * Il gate decide PRIMA di qualsiasi lettura (flag spente = 404 come se la rotta
 * non esistesse). Poi il database applica i propri interruttori e la categoria:
 * con la pubblicazione spenta la lettura è vuota e la pagina mostra lo stato
 * vuoto, mai un dato.
 */
export default async function Page({ searchParams }: { searchParams: Promise<{ pagina?: string }> }) {
  const client = await getSupabaseServerClient();
  const modalita = await risolviModalitaAccessori(client);
  if (!modalita) notFound();

  const { pagina: parametro } = await searchParams;
  const pagina = Math.min(Math.max(Number.parseInt(parametro ?? "1", 10) || 1, 1), PAGINE_MASSIME);

  const servizio = creaAnnunciAccessoriPubbliciService(client);
  // Si legge un annuncio in più per sapere se esiste la pagina successiva.
  const esito = await servizio.elenco({
    limite: LIMITE_VETRINA_ANNUNCI + 1,
    offset: (pagina - 1) * LIMITE_VETRINA_ANNUNCI,
  });

  if (!esito.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="Gli annunci non sono raggiungibili"
          messaggio="Non siamo riusciti a caricare la vetrina. Riprova fra qualche istante."
        />
      </main>
    );
  }

  const annunci = esito.data.slice(0, LIMITE_VETRINA_ANNUNCI);
  // Il bucket è privato: ogni foto passa da una URL firmata a tempo, concessa solo per annunci visibili.
  const foto = await servizio.urlFoto(annunci.flatMap((a) => (a.foto[0] ? [a.foto[0]] : [])));

  return (
    <AnnunciVetrina
      annunci={annunci}
      immagini={foto.ok ? foto.data : {}}
      modalita={modalita}
      pagina={pagina}
      haAltri={esito.data.length > LIMITE_VETRINA_ANNUNCI}
    />
  );
}
