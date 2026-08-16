"use client";

import { createContext, useContext, type ReactNode } from "react";
import { usePhase8Controller } from "@/lib/phase8/use-phase8-controller";
import type {
  ConversationSummary,
  Message,
  Notification,
  OpenConversationInput,
  RealtimeState,
  Result,
  SendMessageInput,
} from "@/services/types";

export type Phase8ContextValue = {
  mode: "supabase" | "unavailable";
  conversations: ConversationSummary[];
  notifications: Notification[];
  messages: Record<string, Message[]>;
  loading: boolean;
  messagesLoading: boolean;
  error: string | null;
  unreadCount: number;
  messageUnreadCount: number;
  realtimeState: RealtimeState;
  reload: () => Promise<void>;
  loadMessages: (conversationId: string) => Promise<Result<Message[]>>;
  openConversation: (input: OpenConversationInput) => Promise<Result<string>>;
  sendMessage: (input: SendMessageInput) => Promise<Result<Message>>;
  markConversationRead: (conversationId: string, messageId?: string) => Promise<Result<void>>;
  markNotificationRead: (id: string) => Promise<Result<void>>;
  markAllNotificationsRead: () => Promise<Result<number>>;
};

const Phase8Context = createContext<Phase8ContextValue | null>(null);

export const Phase8Provider = ({ children }: { children: ReactNode }) => (
  <Phase8Context.Provider value={usePhase8Controller()}>{children}</Phase8Context.Provider>
);

export const usePhase8 = (): Phase8ContextValue => {
  const context = useContext(Phase8Context);
  if (!context) throw new Error("usePhase8 deve stare dentro Phase8Provider");
  return context;
};
