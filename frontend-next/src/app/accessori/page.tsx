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
  description: "Il catalogo Beta degli accessori per il vino: apertura, calici, decanter e altro.",
  // Beta: la sezione non e un lancio commerciale e non va indicizzata.
  robots: { index: false, follow: false },
};

/**
 * Indice degli Accessori (VPM-015A).
 *
 * Il gate decide PRIMA di qualsiasi lettura: senza anteprima admin e senza le
 * flag pubbliche accese la risposta e 404, come se la route non esistesse. Poi
 * il database applica il proprio interruttore: con la flag server accesa ma
 * l'interruttore spento le letture tornano vuote e la pagina mostra lo stato
 * vuoto, mai un dato.
 */
export default async function Page() {
  const client = await getSupabaseServerClient();
  const modalita = await risolviModalitaAccessori(client);
  if (!modalita) notFound();

  const anteprima = modalita === "anteprima";
  const servizio = creaAccessoriLetturaService(client);
  const [categorie, schede] = await Promise.all([
    servizio.categorie(anteprima),
    servizio.elenco(null, anteprima),
  ]);

  if (!categorie.ok || !schede.ok) {
    return (
      <main id="contenuto-principale" className="mx-auto max-w-3xl px-4 py-12">
        <StatoVuotoAccessori
          titolo="Gli accessori non sono raggiungibili"
          messaggio="Non siamo riusciti a caricare il catalogo. Riprova fra qualche istante."
        />
      </main>
    );
  }

  return (
    <AccessoriVetrina
      titolo="Accessori per il vino"
      introduzione="Cavatappi, calici, decanter e tutto ciò che accompagna una bottiglia, dal momento in cui la apri a quello in cui la conservi."
      categorie={categorie.data}
      schede={schede.data}
      corrente={null}
      modalita={modalita}
      vuoto={{
        titolo: "Il catalogo si sta preparando",
        messaggio:
          "Stiamo selezionando i primi accessori. Torna presto: ti faremo trovare solo ciò che vale la pena avere accanto a una buona bottiglia.",
      }}
    />
  );
}
