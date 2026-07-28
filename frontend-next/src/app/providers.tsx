"use client";

import type { ReactNode } from "react";
import { VineaProvider } from "@/lib/vinea-store";
import { AgeGate } from "@/components/vinea/AgeGate";

export function Providers({ children }: { children: ReactNode }) {
  return (
    <VineaProvider>
      {/* Rimanda a /completa-profilo chi ha una sessione ma nessuna data di
          nascita dichiarata: il caso del primo accesso via Google/Facebook. */}
      <AgeGate />
      {children}
    </VineaProvider>
  );
}
