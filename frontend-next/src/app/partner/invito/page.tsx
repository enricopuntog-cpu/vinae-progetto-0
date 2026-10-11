import type { Metadata } from "next";
import { PartnerInvitoClient } from "@/components/vinea/partner/PartnerInvitoClient";

export const metadata: Metadata = {
  title: "Invito Partner — Vinea",
  description: "Accettazione di un invito Vinea Partner.",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

/** Il token è nel frammento: lo legge solo il client, mai il server. */
export default function Page() {
  return (
    <div className="px-4 py-8">
      <PartnerInvitoClient />
    </div>
  );
}
