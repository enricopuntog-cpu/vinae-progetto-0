"use client";

import { formatPhase8Time } from "@/lib/phase8/format";
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
            <img
              src={conversation.counterpart.avatarUrl}
              alt=""
              className="h-10 w-10 rounded-full object-cover"
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
