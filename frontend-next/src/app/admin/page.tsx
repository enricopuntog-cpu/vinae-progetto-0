import type { Metadata } from "next";
import { ModerationPanelClient } from "@/components/vinea/moderation/ModerationPanelClient";

export const metadata: Metadata = {
  title: "Moderazione — Vinea",
  description: "Coda segnalazioni, controversie ordini e registro delle azioni di moderazione.",
  robots: { index: false, follow: false },
};

const Page = () => <ModerationPanelClient />;

export default Page;
