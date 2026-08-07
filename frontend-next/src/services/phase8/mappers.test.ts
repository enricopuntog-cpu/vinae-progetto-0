import { describe, expect, it } from "bun:test";
import { mapConversation, mapMessage } from "@/services/phase8/supabase-messaging-service";
import { mapNotification } from "@/services/phase8/supabase-notification-service";

const conversationRow: Parameters<typeof mapConversation>[0] = {
  conversation_id: "conversation",
  listing_id: "listing",
  listing_slug: "barolo-2020",
  listing_price_cents: 12345,
  order_id: null,
  order_status: null,
  counterpart_id: "counterpart",
  counterpart_username: "Marco",
  counterpart_avatar_url: "/avatar.png",
  wine_name: "Barolo 2020",
  wine_image: "/wine.png",
  writable: true,
  last_message_id: null,
  last_message_at: null,
  last_message_preview: null,
  unread_count: 4,
  activity_at: "2026-08-07T12:00:00.000Z",
  created_at: "2026-08-07T11:00:00.000Z",
};

const notificationRow = {
  id: "notification",
  category: "marketplace" as const,
  event_type: "new_message",
  body: "Nuovo messaggio",
  destination_kind: "conversation" as const,
  destination_conversation_id: "conversation",
  destination_listing_id: null,
  destination_order_id: null,
  destination_club_slug: null,
  read_at: null,
  created_at: "2026-08-07T12:00:00.000Z",
};

describe("mapping Supabase Fase 8", () => {
  it("mappa la controparte senza esporre il profilo completo", () => {
    expect(mapConversation(conversationRow).counterpart).toEqual({
      userId: "counterpart",
      username: "Marco",
      avatarUrl: "/avatar.png",
    });
  });

  it("conserva UUID interno e slug pubblico dell annuncio separati", () => {
    const result = mapConversation(conversationRow);
    expect(result.listingId).toBe("listing");
    expect(result.listingSlug).toBe("barolo-2020");
  });

  it("normalizza unread_count numerico", () => {
    expect(mapConversation({ ...conversationRow, unread_count: 7 }).unreadCount).toBe(7);
  });

  it("mappa il messaggio senza source_event_key", () => {
    expect(
      mapMessage({
        id: "message",
        conversation_id: "conversation",
        sender_id: null,
        kind: "system",
        body: "Evento",
        created_at: "2026-08-07T12:00:00.000Z",
      }),
    ).toEqual({
      id: "message",
      conversationId: "conversation",
      senderId: null,
      kind: "system",
      body: "Evento",
      createdAt: "2026-08-07T12:00:00.000Z",
    });
  });

  it("mappa la destinazione conversazione come union tipizzata", () => {
    expect(mapNotification(notificationRow).destination).toEqual({
      kind: "conversation",
      conversationId: "conversation",
    });
  });

  it("una destinazione incoerente non diventa un URL arbitrario", () => {
    expect(
      mapNotification({
        ...notificationRow,
        destination_kind: "order",
        destination_conversation_id: null,
        destination_order_id: null,
      }).destination,
    ).toEqual({ kind: "none" });
  });
});
