import Link from "next/link";
import { ArrowLeft, MoreHorizontal } from "lucide-react";
import { formatEUR } from "@/lib/format";
import type { ConversationSummary } from "@/services/types";

export const ConversationHeader = ({
  conversation,
  onBack,
}: {
  conversation: ConversationSummary;
  onBack: () => void;
}) => (
  <>
    <header className="flex items-center gap-3 border-b border-border p-3">
      <button
        onClick={onBack}
        className="rounded-full p-1 hover:bg-secondary md:hidden"
        aria-label="Indietro"
      >
        <ArrowLeft className="h-4 w-4" />
      </button>
      <img
        src={conversation.counterpart.avatarUrl}
        alt=""
        className="h-10 w-10 rounded-full object-cover"
      />
      <span className="min-w-0 flex-1">
        <span className="block font-semibold">{conversation.counterpart.username}</span>
        <Link
          href={`/annuncio/${conversation.listingSlug}`}
          className="block truncate text-xs text-muted-foreground hover:underline"
        >
          {conversation.wineName} · {formatEUR(conversation.listingPriceCents / 100)}
        </Link>
      </span>
      <button
        disabled
        title="Segnalazione e blocco arrivano con la Fase 9"
        className="rounded-full p-2 opacity-40"
        aria-label="Altre azioni non disponibili"
      >
        <MoreHorizontal className="h-4 w-4" />
      </button>
    </header>
    <Link
      href={`/annuncio/${conversation.listingSlug}`}
      className="flex items-center gap-3 border-b border-border bg-crema/60 p-3 hover:bg-crema"
    >
      <img src={conversation.wineImage} alt="" className="h-12 w-9 rounded object-cover" />
      <span className="min-w-0 flex-1">
        <span className="block text-[11px] uppercase tracking-wide text-salvia">
          Annuncio collegato
        </span>
        <span className="block truncate font-serif font-semibold">{conversation.wineName}</span>
      </span>
    </Link>
  </>
);
