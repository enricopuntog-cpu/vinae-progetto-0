"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Camera, MessageCircle, Share2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { usePhase8 } from "@/lib/phase8/phase8-context";
import { useVinea } from "@/lib/vinea-store";

export const ListingContactActions = ({ listingId }: { listingId: string }) => {
  const router = useRouter();
  const { authUser } = useVinea();
  const { mode, openConversation, sendMessage } = usePhase8();
  const [loading, setLoading] = useState<"chat" | "foto" | null>(null);
  const [error, setError] = useState<string | null>(null);

  const open = async (requestPhotos: boolean) => {
    setLoading(requestPhotos ? "foto" : "chat");
    setError(null);
    const conversation = await openConversation({ listingId });
    if (!conversation.ok) {
      setLoading(null);
      return setError(conversation.error);
    }
    if (requestPhotos) {
      const sent = await sendMessage({
        conversationId: conversation.data,
        text: "Vorrei ricevere altre fotografie della bottiglia e dei suoi dettagli.",
        idempotencyKey: crypto.randomUUID(),
      });
      if (!sent.ok) {
        setLoading(null);
        return setError(sent.error);
      }
    }
    router.push(`/messaggi?conversation=${conversation.data}`);
  };

  return (
    <div className="mt-3 flex flex-wrap gap-2">
      {!authUser ? <Button asChild variant="ghost"><Link href="/accedi">Accedi per contattare il venditore</Link></Button> : null}
      {authUser && mode === "supabase" ? (
        <>
          <Button variant="ghost" disabled={loading !== null} onClick={() => void open(false)}><MessageCircle className="h-4 w-4" /> {loading === "chat" ? "Apertura…" : "Messaggio"}</Button>
          <Button variant="ghost" disabled={loading !== null} onClick={() => void open(true)}><Camera className="h-4 w-4" /> {loading === "foto" ? "Invio…" : "Richiedi altre foto"}</Button>
        </>
      ) : null}
      <Button variant="ghost" onClick={() => void navigator.clipboard?.writeText(window.location.href)}><Share2 className="h-4 w-4" /> Condividi</Button>
      {error ? <p role="alert" className="w-full text-sm text-destructive">{error}</p> : null}
    </div>
  );
};
