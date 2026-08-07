import { formatPhase8Time } from "@/lib/phase8/format";
import type { Message } from "@/services/types";

export const MessageBubble = ({ message, ownUserId }: { message: Message; ownUserId: string }) => {
  if (message.kind === "system") {
    return (
      <div className="flex justify-center">
        <span className="rounded-full bg-secondary px-3 py-1 text-[11px] text-muted-foreground">
          {message.body} · {formatPhase8Time(message.createdAt)}
        </span>
      </div>
    );
  }

  const mine = message.senderId === ownUserId;
  return (
    <div className={`flex ${mine ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[75%] rounded-2xl px-4 py-2 text-sm ${mine ? "bg-bordeaux text-crema" : "bg-secondary"}`}
      >
        {message.body}
        <span className="ml-2 text-[10px] opacity-60">
          {formatPhase8Time(message.createdAt)}
        </span>
      </div>
    </div>
  );
};
