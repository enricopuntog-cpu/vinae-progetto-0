import type { Metadata } from "next";
import { MessagesPageClient } from "@/components/vinea/messaging/MessagesPageClient";

export const metadata: Metadata = {
  title: "Messaggi — Vinea",
  description: "Le tue conversazioni private con acquirenti e venditori Vinea.",
  robots: { index: false, follow: false },
};

const Page = async ({
  searchParams,
}: {
  searchParams: Promise<{ conversation?: string }>;
}) => {
  const { conversation } = await searchParams;
  return <MessagesPageClient initialConversationId={conversation} />;
};

export default Page;
