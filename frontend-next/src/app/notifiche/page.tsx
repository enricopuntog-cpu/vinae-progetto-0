import type { Metadata } from "next";
import { NotificationsPageClient } from "@/components/vinea/notifications/NotificationsPageClient";

export const metadata: Metadata = {
  title: "Notifiche — Vinea",
  description: "Notifiche marketplace, community e sistema Vinea.",
  robots: { index: false, follow: false },
};

const Page = () => <NotificationsPageClient />;

export default Page;
