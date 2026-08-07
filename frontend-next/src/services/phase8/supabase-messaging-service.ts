import type { SupabaseClient } from "@supabase/supabase-js";
import { noPhase8Client, pageCursor, phase8Error } from "@/services/phase8/shared";
import type {
  ConversationSummary,
  Message,
  MessagingService,
} from "@/services/types";

type ConversationRow = {
  conversation_id: string;
  listing_id: string;
  listing_slug: string;
  listing_price_cents: number;
  order_id: string | null;
  order_status: string | null;
  counterpart_id: string;
  counterpart_username: string;
  counterpart_avatar_url: string;
  wine_name: string;
  wine_image: string;
  writable: boolean;
  last_message_id: string | null;
  last_message_at: string | null;
  last_message_preview: string | null;
  unread_count: number;
  activity_at: string;
  created_at: string;
};

type MessageRow = {
  id: string;
  conversation_id: string;
  sender_id: string | null;
  kind: "user" | "system";
  body: string;
  created_at: string;
};

export const mapConversation = (row: ConversationRow): ConversationSummary => ({
  id: row.conversation_id,
  listingId: row.listing_id,
  listingSlug: row.listing_slug,
  listingPriceCents: row.listing_price_cents,
  orderId: row.order_id,
  orderStatus: row.order_status,
  counterpart: {
    userId: row.counterpart_id,
    username: row.counterpart_username,
    avatarUrl: row.counterpart_avatar_url,
  },
  wineName: row.wine_name,
  wineImage: row.wine_image,
  writable: row.writable,
  lastMessageId: row.last_message_id,
  lastMessageAt: row.last_message_at,
  lastMessagePreview: row.last_message_preview,
  unreadCount: Number(row.unread_count),
  activityAt: row.activity_at,
  createdAt: row.created_at,
});

export const mapMessage = (row: MessageRow): Message => ({
  id: row.id,
  conversationId: row.conversation_id,
  senderId: row.sender_id,
  kind: row.kind,
  body: row.body,
  createdAt: row.created_at,
});

export const createSupabaseMessagingService = (
  client: SupabaseClient | null,
): MessagingService => ({
  conversazioni: async (cursor, limit = 30) => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("conversations_page", {
      p_before_activity_at: cursor?.createdAt ?? null,
      p_before_id: cursor?.id ?? null,
      p_limit: limit,
    });
    if (error) return phase8Error("conversations_page", error);
    const items = ((data ?? []) as ConversationRow[]).map(mapConversation);
    const last = items.at(-1);
    return {
      ok: true,
      data: {
        items,
        nextCursor:
          items.length === limit && last ? { id: last.id, createdAt: last.activityAt } : null,
      },
    };
  },
  messaggi: async (conversationId, cursor, limit = 50) => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("messages_page", {
      p_conversation_id: conversationId,
      p_before_created_at: cursor?.createdAt ?? null,
      p_before_id: cursor?.id ?? null,
      p_limit: limit,
    });
    if (error) return phase8Error("messages_page", error);
    const items = ((data ?? []) as MessageRow[]).map(mapMessage);
    return { ok: true, data: { items, nextCursor: pageCursor(items, limit) } };
  },
  apri: async (input) => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("conversation_open", {
      p_listing_id: "listingId" in input ? input.listingId : null,
      p_order_id: "orderId" in input ? input.orderId : null,
    });
    return error
      ? phase8Error("conversation_open", error)
      : { ok: true, data: { conversationId: data as string } };
  },
  invia: async (input) => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("message_send", {
      p_conversation_id: input.conversationId,
      p_text: input.text,
      p_idempotency_key: input.idempotencyKey,
    });
    if (error) return phase8Error("message_send", error);
    const row = ((data ?? []) as MessageRow[])[0];
    return row
      ? { ok: true, data: mapMessage(row) }
      : { ok: false, error: "Il server non ha restituito il messaggio inviato." };
  },
  segnaLetti: async (conversationId, messageId) => {
    if (!client) return noPhase8Client();
    const { error } = await client.rpc("conversation_mark_read", {
      p_conversation_id: conversationId,
      p_message_id: messageId ?? null,
    });
    return error ? phase8Error("conversation_mark_read", error) : { ok: true, data: undefined };
  },
});
