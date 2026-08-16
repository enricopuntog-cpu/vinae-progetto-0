import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { createListingService } from "@/services/listing-service";
import CheckoutPageClient from "./page-client";

export const generateMetadata = async ({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> => {
  const { id } = await params;
  const wine = await createListingService(await getSupabaseServerClient()).dettaglio(id);
  return { title: wine ? `Checkout — ${wine.nome} | Vinea Beta` : "Checkout — Vinea Beta" };
};

const Page = async ({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ prop?: string }>;
}) => {
  const [{ id }, ricerca] = await Promise.all([params, searchParams]);
  const wine = await createListingService(await getSupabaseServerClient()).dettaglio(id);
  if (!wine) notFound();
  return <CheckoutPageClient wine={wine} proposalId={ricerca.prop} />;
};

export default Page;
