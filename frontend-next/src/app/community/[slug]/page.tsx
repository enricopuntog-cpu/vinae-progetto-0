import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { communities } from "@/data/communities";
import CommunityDetailPageClient from "./page-client";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const c = communities.find((x) => x.slug === slug);
  const t = c ? `${c.nome} — Club Vinea` : "Club Vinea";
  return {
    title: t,
    description: c?.descrizione ?? "Club Vinea Wine Club",
    openGraph: {
      title: t,
      description: c?.descrizione ?? "Club Vinea Wine Club",
      images: c ? [c.cover] : undefined,
    },
    twitter: c
      ? {
          images: [c.cover],
        }
      : undefined,
  };
}

export default async function Page({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const c = communities.find((x) => x.slug === slug);
  if (!c) notFound();

  return <CommunityDetailPageClient slug={slug} />;
}
