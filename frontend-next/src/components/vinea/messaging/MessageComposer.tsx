"use client";

import { useRef, useState } from "react";
import { Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { Message, Result, SendMessageInput } from "@/services/types";

const newKey = (): string => crypto.randomUUID();

export const MessageComposer = ({
  conversationId,
  disabled,
  onSend,
}: {
  conversationId: string;
  disabled: boolean;
  onSend: (input: SendMessageInput) => Promise<Result<Message>>;
}) => {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const idempotencyKey = useRef(newKey());

  const submit = async () => {
    if (disabled || busy || !text.trim()) return;
    setBusy(true);
    const result = await onSend({
      conversationId,
      text,
      idempotencyKey: idempotencyKey.current,
    });
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setText("");
    setError(null);
    idempotencyKey.current = newKey();
  };

  return (
    <div className="border-t border-border p-3">
      {error && (
        <p role="alert" className="mb-2 text-xs text-bordeaux">
          {error} Il nuovo tentativo usera la stessa chiave sicura.
        </p>
      )}
      <div className="flex gap-2">
        <Input
          value={text}
          maxLength={2000}
          disabled={disabled || busy}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) void submit();
          }}
          placeholder={disabled ? "Conversazione in sola lettura" : "Scrivi un messaggio…"}
        />
        <Button
          aria-label="Invia messaggio"
          className="bg-bordeaux hover:bg-bordeaux/90"
          disabled={disabled || busy || !text.trim()}
          onClick={() => void submit()}
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
};
