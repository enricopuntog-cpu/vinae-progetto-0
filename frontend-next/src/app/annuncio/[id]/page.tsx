import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { wines } from "@/data/wines";
import { formatEUR } from "@/lib/format";
import AnnuncioDetailPageClient from "./page-client";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const wine = wines.find((w) => w.id === id);
  if (!wine) {
    return { title: "Annuncio non trovato — Vinea" };
  }
  const title = `${wine.nome} ${wine.annata} — ${wine.produttore} | Vinea`;
  const description = `${wine.produttore} ${wine.nome} ${wine.annata}, ${wine.regione}. In vendita a ${formatEUR(wine.prezzo)}.`;
  return {
    title,
    description,
    openGraph: {
      title,
      description,
      images: [wine.immagini[0]],
    },
    twitter: {
      images: [wine.immagini[0]],
    },
  };
}

export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const wine = wines.find((w) => w.id === id);
  if (!wine) notFound();

  return <AnnuncioDetailPageClient wineId={id} />;
}
