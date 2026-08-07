"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import type { Phase8ContextValue } from "@/lib/phase8/phase8-context";
import { useVinea } from "@/lib/vinea-store";
import { createMockPhase8Services } from "@/services/phase8/mock-services";
import { createPhase8RealtimeManager } from "@/services/phase8/realtime";
import { createSupabaseMessagingService } from "@/services/phase8/supabase-messaging-service";
import { createSupabaseNotificationService } from "@/services/phase8/supabase-notification-service";
import type {
  ConversationSummary,
  Message,
  Notification,
  OpenConversationInput,
  RealtimeState,
  Result,
  SendMessageInput,
} from "@/services/types";

export const usePhase8Controller = (): Phase8ContextValue => {
  const { authUser } = useVinea();
  const authUserId = authUser?.userId;
  const client = getSupabaseClient();
  const [mock] = useState(createMockPhase8Services);
  const services = useMemo(
    () =>
      client
        ? {
            messaging: createSupabaseMessagingService(client),
            notifications: createSupabaseNotificationService(client),
          }
        : mock,
    [client, mock],
  );
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [messages, setMessages] = useState<Record<string, Message[]>>({});
  const [loading, setLoading] = useState(true);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [online, setOnline] = useState(() =>
    typeof navigator === "undefined" ? true : navigator.onLine,
  );
  const [realtimeState, setRealtimeState] = useState<RealtimeState>("idle");
  const epoch = useRef(0);

  const reload = useCallback(async (showLoading = true) => {
    const requestEpoch = epoch.current;
    if (showLoading) setLoading(true);
    const [conversationResult, notificationResult] = await Promise.all([
      services.messaging.conversazioni(),
      services.notifications.elenco(),
    ]);
    if (requestEpoch !== epoch.current) return;
    if (!conversationResult.ok) {
      setError(conversationResult.error);
    } else if (!notificationResult.ok) {
      setError(notificationResult.error);
    } else {
      setConversations(conversationResult.data.items);
      setNotifications(notificationResult.data.items);
      setError(null);
    }
    if (showLoading) setLoading(false);
  }, [services]);

  useEffect(() => {
    const requestEpoch = ++epoch.current;
    queueMicrotask(() => {
      if (requestEpoch !== epoch.current) return;
      setConversations([]);
      setNotifications([]);
      setMessages({});
      setMessagesLoading(false);
      if (client && !authUserId) {
        setLoading(false);
        return;
      }
      void reload();
    });
    return () => {
      if (requestEpoch === epoch.current) epoch.current += 1;
    };
  }, [authUserId, client, reload]);

  useEffect(() => {
    const updateOnline = () => setOnline(navigator.onLine);
    window.addEventListener("online", updateOnline);
    window.addEventListener("offline", updateOnline);
    return () => {
      window.removeEventListener("online", updateOnline);
      window.removeEventListener("offline", updateOnline);
    };
  }, []);

  const loadMessages = useCallback(
    async (conversationId: string): Promise<Result<Message[]>> => {
      const requestEpoch = epoch.current;
      setMessagesLoading(true);
      const result = await services.messaging.messaggi(conversationId);
      if (requestEpoch !== epoch.current) {
        return { ok: false, error: "La sessione e cambiata durante il caricamento." };
      }
      setMessagesLoading(false);
      if (!result.ok) return result;
      setMessages((current) => ({ ...current, [conversationId]: result.data.items }));
      return { ok: true, data: result.data.items };
    },
    [services],
  );

  const conversationKey = useMemo(
    () => conversations.map((row) => row.id).sort().join(","),
    [conversations],
  );

  useEffect(() => {
    if (!client || !authUserId || !online) return;

    const requestEpoch = epoch.current;
    const isCurrent = () => requestEpoch === epoch.current;
    const conversationIds = conversationKey ? conversationKey.split(",") : [];
    const manager = createPhase8RealtimeManager(client, {
      userId: authUserId,
      conversationIds,
      onMessage: async (conversationId) => {
        if (!isCurrent()) return;
        await Promise.all([loadMessages(conversationId), reload(false)]);
      },
      onNotifications: async () => {
        if (isCurrent()) await reload(false);
      },
      onCatchUp: async () => {
        if (!isCurrent()) return;
        await Promise.all([
          reload(false),
          ...conversationIds.map((conversationId) => loadMessages(conversationId)),
        ]);
      },
      onState: (state) => {
        if (isCurrent()) setRealtimeState(state);
      },
    });
    void manager.start();
    return () => void manager.stop();
  }, [authUserId, client, conversationKey, loadMessages, online, reload]);

  const effectiveRealtimeState: RealtimeState =
    !client || !authUserId ? "idle" : !online ? "offline" : realtimeState;

  const openConversation = useCallback(
    async (input: OpenConversationInput): Promise<Result<string>> => {
      const result = await services.messaging.apri(input);
      if (!result.ok) return result;
      await reload();
      return { ok: true, data: result.data.conversationId };
    },
    [reload, services],
  );

  const sendMessage = useCallback(
    async (input: SendMessageInput): Promise<Result<Message>> => {
      const result = await services.messaging.invia(input);
      if (!result.ok) return result;
      setMessages((current) => {
        const rows = current[input.conversationId] ?? [];
        return rows.some((row) => row.id === result.data.id)
          ? current
          : { ...current, [input.conversationId]: [result.data, ...rows] };
      });
      await reload();
      return result;
    },
    [reload, services],
  );

  const markConversationRead = useCallback(
    async (conversationId: string, messageId?: string) => {
      const result = await services.messaging.segnaLetti(conversationId, messageId);
      if (result.ok) {
        setConversations((rows) =>
          rows.map((row) => (row.id === conversationId ? { ...row, unreadCount: 0 } : row)),
        );
      }
      return result;
    },
    [services],
  );

  const markNotificationRead = useCallback(
    async (id: string) => {
      const result = await services.notifications.segnaLetta(id);
      if (result.ok) {
        const readAt = new Date().toISOString();
        setNotifications((rows) =>
          rows.map((row) => (row.id === id ? { ...row, readAt: row.readAt ?? readAt } : row)),
        );
      }
      return result;
    },
    [services],
  );

  const markAllNotificationsRead = useCallback(async () => {
    const result = await services.notifications.segnaTutteLette();
    if (result.ok) {
      const readAt = new Date().toISOString();
      setNotifications((rows) => rows.map((row) => ({ ...row, readAt: row.readAt ?? readAt })));
    }
    return result;
  }, [services]);

  return useMemo(
    () => ({
      mode: client ? "supabase" : "mock",
      conversations,
      notifications,
      messages,
      loading,
      messagesLoading,
      error,
      unreadCount: notifications.filter((row) => row.readAt === null).length,
      messageUnreadCount: conversations.reduce((sum, row) => sum + row.unreadCount, 0),
      realtimeState: effectiveRealtimeState,
      reload,
      loadMessages,
      openConversation,
      sendMessage,
      markConversationRead,
      markNotificationRead,
      markAllNotificationsRead,
    }),
    [
      client,
      conversations,
      error,
      loadMessages,
      loading,
      markAllNotificationsRead,
      markConversationRead,
      markNotificationRead,
      messages,
      messagesLoading,
      notifications,
      openConversation,
      reload,
      effectiveRealtimeState,
      sendMessage,
    ],
  );
};
