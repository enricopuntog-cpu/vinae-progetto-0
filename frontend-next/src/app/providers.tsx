"use client";

import type { ReactNode } from "react";
import { Phase8Provider } from "@/lib/phase8/phase8-context";
import { VineaProvider } from "@/lib/vinea-store";
import { AgeGate } from "@/components/vinea/AgeGate";

export function Providers({ children }: { children: ReactNode }) {
  return (
    <VineaProvider>
      <Phase8Provider>
        {/* Rimanda a /completa-profilo chi ha una sessione ma nessuna data di
            nascita dichiarata: il caso del primo accesso via Google/Facebook. */}
        <AgeGate />
        {children}
      </Phase8Provider>
    </VineaProvider>
  );
}
