import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseClubService } from "@/services/phase12/supabase-club-service";
import CommunityDetailPageClient from "./page-client";

// Stessa forma di /annuncio/[id]: il componente server legge, decide il 404 e
// consegna il dato al client. Il `notFound()` qui sotto NON e lo stub della
// #44 - quello rispondeva 404 a qualunque slug, compresi quelli veri. Questo
// risponde 404 solo a uno slug che nel database non c'e.
//
// generateMetadata legge dal club reale attraverso ClubService: prima leggeva
// da `@/data/communities`, un file mock che nessuna pagina importa piu.

async function leggiClub(slug: string) {
  const client = await getSupabaseServerClient();
  const esito = await createSupabaseClubService(client).dettaglio(slug);
  return esito.ok ? esito.data : null;
}

// Le discussioni si leggono qui e non in un effetto del client, per la stessa
// ragione del club: e una pagina pubblica, e il primo paint deve avere il
// contenuto invece di uno scheletro. Un errore di lettura non fa 404 e non fa
// cadere la pagina - la scheda del club resta, e le discussioni sono un elenco
// vuoto: il club esiste anche quando la sua bacheca non si e potuta leggere.
async function leggiDiscussioni(slug: string) {
  const client = await getSupabaseServerClient();
  const esito = await createSupabaseClubService(client).discussioni(slug);
  return esito.ok ? esito.data : [];
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const club = await leggiClub(slug);
  if (!club) return { title: "Club non trovato — Vinea" };

  const titolo = `${club.nome} — Club Vinea`;
  return {
    title: titolo,
    description: club.descrizione,
    openGraph: { title: titolo, description: club.descrizione },
    // Nessuna immagine: 12a non ha una colonna di copertina, e un'immagine
    // generica di Vinea in una card social direbbe che il club ha una
    // copertina che non ha.
    twitter: { title: titolo, description: club.descrizione },
  };
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const club = await leggiClub(slug);
  if (!club) notFound();

  const discussioni = await leggiDiscussioni(slug);

  return <CommunityDetailPageClient iniziale={club} discussioni={discussioni} />;
}
