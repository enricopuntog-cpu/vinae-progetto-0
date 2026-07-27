"use client";

import type { ReactNode } from "react";
import { VineaProvider } from "@/lib/vinea-store";

export function Providers({ children }: { children: ReactNode }) {
  return <VineaProvider>{children}</VineaProvider>;
}
