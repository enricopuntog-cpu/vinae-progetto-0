import type { Metadata } from "next";
import { MyReportsPageClient } from "@/components/vinea/moderation/MyReportsPageClient";

export const metadata: Metadata = {
  title: "Le mie segnalazioni — Vinea",
  description: "Stato e storia delle segnalazioni inviate.",
  robots: { index: false, follow: false },
};

const Page = () => <MyReportsPageClient />;

export default Page;
