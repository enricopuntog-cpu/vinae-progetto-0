"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { Button } from "@/components/ui/button";

export function PostvenditaErrore() {
  const router = useRouter();
  const [inCorso, startTransition] = useTransition();
  return <section className="mt-6 space-y-3">
    <p role="alert">Non è stato possibile caricare il post-vendita. Riprova fra qualche istante.</p>
    <Button disabled={inCorso} onClick={() => startTransition(() => router.refresh())}>
      {inCorso ? "Caricamento…" : "Riprova post-vendita"}
    </Button>
  </section>;
}
