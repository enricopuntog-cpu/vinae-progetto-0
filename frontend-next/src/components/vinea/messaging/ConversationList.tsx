"use client";

import { formatPhase8Time } from "@/lib/phase8/format";
import { AvatarPersona } from "@/components/vinea/AvatarPersona";
import type { ConversationSummary } from "@/services/types";

export const ConversationList = ({
  conversations,
  selectedId,
  onSelect,
}: {
  conversations: ConversationSummary[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}) => (
  <aside
    className={`overflow-hidden rounded-2xl border border-border bg-card ${selectedId ? "hidden md:block" : ""}`}
  >
    <ul>
      {conversations.map((conversation) => (
        <li key={conversation.id}>
          <button
            onClick={() => onSelect(conversation.id)}
            className={`flex w-full items-center gap-3 border-b border-border p-3 text-left last:border-0 ${selectedId === conversation.id ? "bg-secondary" : ""}`}
          >
            {/* Stessa foundation dell'intestazione, così la stessa persona non
                ha due facce diverse a due centimetri di distanza. Qui non c'è
                nessun link al profilo di proposito: questa riga è un bottone, e
                il suo mestiere è scegliere la conversazione. L'ingresso al
                profilo sta nell'intestazione, dove non deve annidarsi dentro un
                comando. */}
            <AvatarPersona
              avatarUrl={conversation.counterpart.avatarUrl}
              proprietarioId={conversation.counterpart.userId}
              className="h-10 w-10"
            />
            <span className="min-w-0 flex-1">
              <span className="flex items-center justify-between gap-2">
                <span className="truncate text-sm font-semibold">
                  {conversation.counterpart.username}
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {formatPhase8Time(conversation.activityAt)}
                </span>
              </span>
              <span className="block truncate text-xs text-muted-foreground">
                {conversation.lastMessagePreview ?? conversation.wineName}
              </span>
            </span>
            {conversation.unreadCount > 0 && (
              <span className="grid h-5 min-w-5 place-items-center rounded-full bg-bordeaux px-1 text-[10px] text-crema">
                {conversation.unreadCount}
              </span>
            )}
          </button>
        </li>
      ))}
    </ul>
  </aside>
);
