import type { SupabaseClient } from "@supabase/supabase-js";
import { noPhase8Client, pageCursor, phase8Error } from "@/services/phase8/shared";
import type {
  Notification,
  NotificationDestination,
  NotificationService,
} from "@/services/types";

type NotificationRow = {
  id: string;
  category: Notification["category"];
  event_type: string;
  body: string;
  destination_kind: NotificationDestination["kind"];
  destination_conversation_id: string | null;
  destination_listing_id: string | null;
  destination_order_id: string | null;
  destination_club_slug: string | null;
  read_at: string | null;
  created_at: string;
};

const mapDestination = (row: NotificationRow): NotificationDestination => {
  if (row.destination_kind === "conversation" && row.destination_conversation_id) {
    return { kind: "conversation", conversationId: row.destination_conversation_id };
  }
  if (row.destination_kind === "listing" && row.destination_listing_id) {
    return { kind: "listing", listingId: row.destination_listing_id };
  }
  if (row.destination_kind === "order" && row.destination_order_id) {
    return { kind: "order", orderId: row.destination_order_id };
  }
  if (row.destination_kind === "club" && row.destination_club_slug) {
    return { kind: "club", clubSlug: row.destination_club_slug };
  }
  return { kind: "none" };
};

export const mapNotification = (row: NotificationRow): Notification => ({
  id: row.id,
  category: row.category,
  eventType: row.event_type,
  body: row.body,
  destination: mapDestination(row),
  readAt: row.read_at,
  createdAt: row.created_at,
});

export const createSupabaseNotificationService = (
  client: SupabaseClient | null,
): NotificationService => ({
  elenco: async (cursor, limit = 50) => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("notifications_page", {
      p_before_created_at: cursor?.createdAt ?? null,
      p_before_id: cursor?.id ?? null,
      p_limit: limit,
    });
    if (error) return phase8Error("notifications_page", error);
    const items = ((data ?? []) as NotificationRow[]).map(mapNotification);
    return { ok: true, data: { items, nextCursor: pageCursor(items, limit) } };
  },
  nonLette: async () => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("notifications_unread_count");
    return error
      ? phase8Error("notifications_unread_count", error)
      : { ok: true, data: Number(data ?? 0) };
  },
  segnaLetta: async (id) => {
    if (!client) return noPhase8Client();
    const { error } = await client.rpc("notification_mark_read", {
      p_notification_id: id,
    });
    return error ? phase8Error("notification_mark_read", error) : { ok: true, data: undefined };
  },
  segnaTutteLette: async () => {
    if (!client) return noPhase8Client();
    const { data, error } = await client.rpc("notifications_mark_all_read");
    return error
      ? phase8Error("notifications_mark_all_read", error)
      : { ok: true, data: Number(data ?? 0) };
  },
});
