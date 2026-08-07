import { notificheComplete, systemThreadDemo } from "@/data/extra";
import { messagesMock, wines } from "@/data/wines";
import { pageCursor } from "@/services/phase8/shared";
import type {
  ConversationSummary,
  Message,
  MessagingService,
  Notification,
  NotificationService,
  PageCursor,
} from "@/services/types";

export const MOCK_PHASE8_USER_ID = "00000000-0000-4000-8000-000000000008";

const counterpartIds = [
  "00000000-0000-4000-8000-000000000101",
  "00000000-0000-4000-8000-000000000102",
  "00000000-0000-4000-8000-000000000103",
];

const conversationIds = [
  "10000000-0000-4000-8000-000000000001",
  "10000000-0000-4000-8000-000000000002",
  "10000000-0000-4000-8000-000000000003",
];

const baseTime = Date.parse("2026-08-07T12:32:00.000Z");

const seedConversations = (): ConversationSummary[] =>
  messagesMock.map((row, index) => {
    const wine = wines.find((item) => item.id === row.wineId)!;
    const createdAt = new Date(baseTime - index * 86_400_000).toISOString();
    return {
      id: conversationIds[index],
      listingId: wine.id,
      listingSlug: wine.id,
      listingPriceCents: Math.round(wine.prezzo * 100),
      orderId: null,
      orderStatus: null,
      counterpart: {
        userId: counterpartIds[index],
        username: row.utente,
        avatarUrl: row.avatar,
      },
      wineName: `${wine.produttore} ${wine.nome} ${wine.annata}`,
      wineImage: wine.immagini[0],
      writable: true,
      lastMessageId: null,
      lastMessageAt: createdAt,
      lastMessagePreview: row.ultimo,
      unreadCount: row.nonLetti,
      activityAt: createdAt,
      createdAt,
    };
  });

const seedMessages = (): Map<string, Message[]> => {
  const map = new Map<string, Message[]>();
  for (const [conversationIndex, conversationId] of conversationIds.entries()) {
    const source = conversationIndex === 0 ? systemThreadDemo : [];
    map.set(
      conversationId,
      source.map((row, index) => ({
        id: `20000000-0000-4000-8000-${String(conversationIndex * 100 + index).padStart(12, "0")}`,
        conversationId,
        senderId: row.sistema
          ? null
          : row.me
            ? MOCK_PHASE8_USER_ID
            : counterpartIds[conversationIndex],
        kind: row.sistema ? "system" : "user",
        body: row.t,
        createdAt: new Date(baseTime - (source.length - index) * 60_000).toISOString(),
      })),
    );
  }
  return map;
};

const seedNotifications = (): Notification[] =>
  notificheComplete.map((row, index) => ({
    id: `30000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    category: row.categoria,
    eventType: `demo_${row.categoria}`,
    body: row.testo,
    destination:
      row.categoria === "marketplace"
        ? { kind: "conversation" as const, conversationId: conversationIds[index % 3] }
        : { kind: "none" as const },
    readAt: row.letta ? new Date(baseTime - index * 3_600_000).toISOString() : null,
    createdAt: new Date(baseTime - index * 3_600_000).toISOString(),
  }));

const afterCursor = <T extends { id: string; createdAt: string }>(
  rows: T[],
  cursor?: PageCursor,
): T[] =>
  cursor
    ? rows.filter(
        (row) =>
          row.createdAt < cursor.createdAt ||
          (row.createdAt === cursor.createdAt && row.id < cursor.id),
      )
    : rows;

export const createMockPhase8Services = (): {
  messaging: MessagingService;
  notifications: NotificationService;
} => {
  const conversations = seedConversations();
  const messages = seedMessages();
  let notifications = seedNotifications();
  const idempotent = new Map<string, Message>();

  const messaging: MessagingService = {
    conversazioni: async (cursor, limit = 30) => {
      const rows = [...conversations]
        .sort((a, b) => b.activityAt.localeCompare(a.activityAt) || b.id.localeCompare(a.id))
        .filter(
          (row) =>
            !cursor ||
            row.activityAt < cursor.createdAt ||
            (row.activityAt === cursor.createdAt && row.id < cursor.id),
        )
        .slice(0, limit);
      const last = rows.at(-1);
      return {
        ok: true,
        data: {
          items: rows,
          nextCursor:
            rows.length === limit && last ? { id: last.id, createdAt: last.activityAt } : null,
        },
      };
    },
    messaggi: async (conversationId, cursor, limit = 50) => {
      const rows = afterCursor(
        [...(messages.get(conversationId) ?? [])].sort(
          (a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id),
        ),
        cursor,
      ).slice(0, limit);
      return { ok: true, data: { items: rows, nextCursor: pageCursor(rows, limit) } };
    },
    apri: async (input) => {
      const found = conversations.find((row) =>
        "listingId" in input ? row.listingId === input.listingId : row.orderId === input.orderId,
      );
      return found
        ? { ok: true, data: { conversationId: found.id } }
        : { ok: false, error: "Conversazione demo non disponibile per questo annuncio." };
    },
    invia: async (input) => {
      const body = input.text.trim();
      if (!body || body.length > 2000) return { ok: false, error: "Messaggio non valido." };
      const key = `${input.conversationId}:${input.idempotencyKey}`;
      const existing = idempotent.get(key);
      if (existing) {
        return existing.body === body
          ? { ok: true, data: existing }
          : { ok: false, error: "Chiave idempotenza gia usata con un altro payload." };
      }
      const message: Message = {
        id: crypto.randomUUID(),
        conversationId: input.conversationId,
        senderId: MOCK_PHASE8_USER_ID,
        kind: "user",
        body,
        createdAt: new Date().toISOString(),
      };
      idempotent.set(key, message);
      messages.set(input.conversationId, [...(messages.get(input.conversationId) ?? []), message]);
      const conversation = conversations.find((row) => row.id === input.conversationId);
      if (conversation) {
        Object.assign(conversation, {
          lastMessageId: message.id,
          lastMessageAt: message.createdAt,
          lastMessagePreview: message.body,
          activityAt: message.createdAt,
        });
      }
      return { ok: true, data: message };
    },
    segnaLetti: async (conversationId) => {
      const conversation = conversations.find((row) => row.id === conversationId);
      if (conversation) conversation.unreadCount = 0;
      return { ok: true, data: undefined };
    },
  };

  const notificationService: NotificationService = {
    elenco: async (cursor, limit = 50) => {
      const rows = afterCursor(
        [...notifications].sort(
          (a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id),
        ),
        cursor,
      ).slice(0, limit);
      return { ok: true, data: { items: rows, nextCursor: pageCursor(rows, limit) } };
    },
    nonLette: async () => ({
      ok: true,
      data: notifications.filter((row) => row.readAt === null).length,
    }),
    segnaLetta: async (id) => {
      notifications = notifications.map((row) =>
        row.id === id && row.readAt === null ? { ...row, readAt: new Date().toISOString() } : row,
      );
      return { ok: true, data: undefined };
    },
    segnaTutteLette: async () => {
      const count = notifications.filter((row) => row.readAt === null).length;
      const readAt = new Date().toISOString();
      notifications = notifications.map((row) => ({ ...row, readAt: row.readAt ?? readAt }));
      return { ok: true, data: count };
    },
  };

  return { messaging, notifications: notificationService };
};
