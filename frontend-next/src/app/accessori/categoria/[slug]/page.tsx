import type { Metadata } from "next";
import { notFound } from "next/navigation";
import {
  AccessoriVetrina,
  StatoVuotoAccessori,
} from "@/components/vinea/accessori/AccessoriVetrina";
import { risolviModalitaAccessori } from "@/lib/accessori/gate";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { creaAccessoriLetturaService } from "@/services/accessori-service";

export const metadata: Metadata = {
  title: "Accessori per il vino — Vinea",
  robots: { index: false, follow: false },
};

/**
 * Una categoria (o sottocategoria) di accessori. Una categoria che non esiste,
 * o non e visibile a chi la chiede, risponde 404: stesso esito di uno slug
 * inventato, per non rivelare cio che il pubblico non puo vedere.
 */
export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const client = await getSupabaseServerClient();
  const modalita = await risolviModalitaAccessori(client);
  if (!modalita) notFound();

  const anteprima = modalita === "anteprima";
  const servizio = creaAccessoriLetturaService(client);
  const categorie = await servizio.categorie(anteprima);
  if (!categorie.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="Gli accessori non sono raggiungibili"
          messaggio="Non siamo riusciti a caricare il catalogo. Riprova fra qualche istante."
        />
      </main>
    );
  }
  const categoria = categorie.data.find((c) => c.slug === slug);
  if (!categoria) notFound();

  const schede = await servizio.elenco(slug, anteprima);
  if (!schede.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="Gli accessori non sono raggiungibili"
          messaggio="Non siamo riusciti a caricare questa categoria. Riprova fra qualche istante."
        />
      </main>
    );
  }

  return (
    <AccessoriVetrina
      titolo={categoria.nome}
      introduzione={categoria.descrizione || "Una selezione di accessori per il vino."}
      categorie={categorie.data}
      schede={schede.data}
      corrente={categoria.slug}
      modalita={modalita}
      vuoto={{
        titolo: "Nessun accessorio in questa categoria, per ora",
        messaggio:
          "Non abbiamo ancora pubblicato nulla qui. Guarda le altre categorie: il catalogo cresce con calma.",
      }}
    />
  );
}
