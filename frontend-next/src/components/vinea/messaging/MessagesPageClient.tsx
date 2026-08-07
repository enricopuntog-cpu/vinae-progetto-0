"use client";

import { useEffect, useState } from "react";
import { ConversationList } from "@/components/vinea/messaging/ConversationList";
import { ConversationPanel } from "@/components/vinea/messaging/ConversationPanel";
import { RealtimeStatusBanner } from "@/components/vinea/notifications/RealtimeStatusBanner";
import { EmptyState, ErrorState, LoadingBlock, OfflineState, useOnline } from "@/components/vinea/States";
import { MOCK_PHASE8_USER_ID } from "@/services/phase8/mock-services";
import { usePhase8 } from "@/lib/phase8/phase8-context";
import { useVinea } from "@/lib/vinea-store";

export const MessagesPageClient = ({ initialConversationId }: { initialConversationId?: string }) => {
  const {
    conversations,
    messages,
    loading,
    messagesLoading,
    error,
    reload,
    loadMessages,
    sendMessage,
    markConversationRead,
    realtimeState,
  } = usePhase8();
  const { authUser } = useVinea();
  const online = useOnline();
  const [selectedId, setSelectedId] = useState<string | null>(initialConversationId ?? null);
  const [messageError, setMessageError] = useState<string | null>(null);
  const selected = conversations.find((row) => row.id === selectedId) ?? null;
  const selectedExists = selected !== null;
  const retryMessages = (conversationId: string) => {
    void loadMessages(conversationId).then((result) =>
      setMessageError(result.ok ? null : result.error),
    );
  };

  useEffect(() => {
    if (!selectedId || !selectedExists) return;
    let active = true;
    void loadMessages(selectedId).then((result) => {
      if (!active) return;
      if (!result.ok) {
        setMessageError(result.error);
        return;
      }
      setMessageError(null);
      void markConversationRead(selectedId, result.data[0]?.id);
    });
    return () => {
      active = false;
    };
  }, [loadMessages, markConversationRead, selectedExists, selectedId]);

  if (!online && conversations.length === 0) return <OfflineState onRetry={() => void reload()} />;
  if (loading && conversations.length === 0) return <LoadingBlock label="Caricamento conversazioni" />;
  if (error && conversations.length === 0) {
    return <ErrorState message={error} onRetry={() => void reload()} />;
  }
  if (conversations.length === 0) {
    return (
      <EmptyState
        title="Nessuna conversazione"
        message="Apri un annuncio attivo e scrivi al venditore per iniziare."
      />
    );
  }

  return (
    <div className="space-y-4">
      <header>
        <h1 className="font-serif text-3xl md:text-4xl">Messaggi</h1>
        <p className="text-sm text-muted-foreground">
          Conversazioni private collegate ai tuoi annunci e ordini.
        </p>
      </header>
      <RealtimeStatusBanner state={realtimeState} />
      <div className="grid gap-4 md:grid-cols-[300px_1fr]">
        <ConversationList
          conversations={conversations}
          selectedId={selectedId}
          onSelect={setSelectedId}
        />
        {selected ? (
          <ConversationPanel
            conversation={selected}
            messages={messages[selected.id] ?? []}
            ownUserId={authUser?.userId ?? MOCK_PHASE8_USER_ID}
            loading={messagesLoading}
            error={messageError}
            offline={!online}
            onBack={() => setSelectedId(null)}
            onRetry={() => retryMessages(selected.id)}
            onSend={sendMessage}
          />
        ) : (
          <section className="hidden min-h-[500px] flex-col items-center justify-center rounded-2xl border border-border bg-card p-8 text-center text-muted-foreground md:flex">
            <p className="font-serif text-xl">Seleziona una conversazione</p>
            <p className="text-sm">L'annuncio collegato e la cronologia appariranno qui.</p>
          </section>
        )}
      </div>
    </div>
  );
};
