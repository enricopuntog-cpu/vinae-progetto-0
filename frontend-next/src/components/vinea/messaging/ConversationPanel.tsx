"use client";

import { WifiOff } from "lucide-react";
import { ConversationHeader } from "@/components/vinea/messaging/ConversationHeader";
import { MessageBubble } from "@/components/vinea/messaging/MessageBubble";
import { MessageComposer } from "@/components/vinea/messaging/MessageComposer";
import { ErrorState, LoadingBlock } from "@/components/vinea/States";
import type {
  ConversationSummary,
  Message,
  Result,
  SendMessageInput,
} from "@/services/types";

export const ConversationPanel = ({
  conversation,
  messages,
  ownUserId,
  loading,
  error,
  offline,
  onBack,
  onRetry,
  onSend,
}: {
  conversation: ConversationSummary;
  messages: Message[];
  ownUserId: string;
  loading: boolean;
  error: string | null;
  offline: boolean;
  onBack: () => void;
  onRetry: () => void;
  onSend: (input: SendMessageInput) => Promise<Result<Message>>;
}) => (
  <section className="flex min-h-[500px] flex-col rounded-2xl border border-border bg-card">
    <ConversationHeader conversation={conversation} onBack={onBack} />
    {offline && (
      <p className="flex items-center justify-center gap-2 bg-oro/10 px-3 py-2 text-xs">
        <WifiOff className="h-3.5 w-3.5" /> Offline: puoi leggere i dati già caricati.
      </p>
    )}
    {!conversation.writable && (
      <p className="bg-secondary px-3 py-2 text-center text-xs text-muted-foreground">
        Annuncio e ordine conclusi: la cronologia resta disponibile in sola lettura.
      </p>
    )}
    <div className="flex-1 space-y-3 overflow-y-auto p-4">
      {loading ? (
        <LoadingBlock label="Caricamento messaggi" />
      ) : error ? (
        <ErrorState message={error} onRetry={onRetry} home={false} />
      ) : messages.length === 0 ? (
        <p className="py-10 text-center text-sm text-muted-foreground">
          Nessun messaggio. Inizia la conversazione.
        </p>
      ) : (
        [...messages].reverse().map((message) => (
          <MessageBubble key={message.id} message={message} ownUserId={ownUserId} />
        ))
      )}
    </div>
    <MessageComposer
      key={conversation.id}
      conversationId={conversation.id}
      disabled={offline || !conversation.writable}
      onSend={onSend}
    />
  </section>
);
