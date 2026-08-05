import type { Metadata } from "next";
import OrdineDetailPageClient from "./page-client";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  return {
    title: `Ordine ${id} — Vinea`,
    description: "Timeline, spedizione e stato dell'ordine.",
    robots: { index: false, follow: false },
  };
}

/**
 * L'ordine è privato: non c'è nulla da rendere sul server, perché non c'è nulla
 * da mostrare a chi non ha una sessione. Ordine, timeline, contestazione e
 * recensione arrivano dal browser con la sessione dell'utente, la stessa scelta
 * già fatta per la Cantina.
 */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <OrdineDetailPageClient orderId={id} />;
}
