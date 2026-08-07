import type { SupabaseClient } from "@supabase/supabase-js";
import type { RealtimeState } from "@/services/types";

type MessageInvalidation = {
  schemaVersion: 1;
  entity: "message";
  id: string;
  conversationId: string;
  createdAt: string;
};

type NotificationInvalidation = {
  schemaVersion: 1;
  entity: "notification";
  id: string;
  createdAt: string;
};

export type Phase8Invalidation = MessageInvalidation | NotificationInvalidation;

type RealtimeClient = {
  realtime: Pick<SupabaseClient["realtime"], "setAuth">;
  channel: SupabaseClient["channel"];
  removeChannel: SupabaseClient["removeChannel"];
};

type ManagerInput = {
  userId: string;
  conversationIds: string[];
  onMessage: (conversationId: string) => void | Promise<void>;
  onNotifications: () => void | Promise<void>;
  onCatchUp: () => void | Promise<void>;
  onState: (state: RealtimeState) => void;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const hasExactKeys = (value: Record<string, unknown>, keys: string[]) =>
  Object.keys(value).sort().join("|") === [...keys].sort().join("|");

const isTimestamp = (value: unknown): value is string =>
  typeof value === "string" && !Number.isNaN(Date.parse(value));

export const parsePhase8Invalidation = (value: unknown): Phase8Invalidation | null => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  if (row.schemaVersion !== 1 || typeof row.id !== "string" || !UUID.test(row.id)) return null;
  if (!isTimestamp(row.createdAt)) return null;

  if (row.entity === "message") {
    if (!hasExactKeys(row, ["schemaVersion", "entity", "id", "conversationId", "createdAt"])) {
      return null;
    }
    return typeof row.conversationId === "string" && UUID.test(row.conversationId)
      ? (row as MessageInvalidation)
      : null;
  }

  return row.entity === "notification" &&
    hasExactKeys(row, ["schemaVersion", "entity", "id", "createdAt"])
    ? (row as NotificationInvalidation)
    : null;
};

export const conversationTopic = (conversationId: string) => `conversation:${conversationId}`;
export const notificationTopic = (userId: string) => `user:${userId}:notifications`;

export const createPhase8RealtimeManager = (client: RealtimeClient, input: ManagerInput) => {
  let active = true;
  let connectedOnce = false;
  let catchUp: Promise<void> | null = null;
  const channels: ReturnType<RealtimeClient["channel"]>[] = [];
  const subscribed = new Set<ReturnType<RealtimeClient["channel"]>>();
  const seen = new Set<string>();

  const runCatchUp = () => {
    if (!active || catchUp) return;
    catchUp = Promise.resolve(input.onCatchUp()).finally(() => {
      catchUp = null;
    });
  };

  const accept = (event: unknown, expectedConversationId?: string) => {
    if (!active) return;
    const invalidation = parsePhase8Invalidation(event);
    if (!invalidation) return;
    if (
      invalidation.entity === "message" &&
      expectedConversationId !== invalidation.conversationId
    ) {
      return;
    }
    const key = `${invalidation.entity}:${invalidation.id}`;
    if (seen.has(key)) return;
    seen.add(key);
    if (seen.size > 512) seen.delete(seen.values().next().value!);
    if (invalidation.entity === "message") void input.onMessage(invalidation.conversationId);
    else void input.onNotifications();
  };

  const subscribe = (channel: ReturnType<RealtimeClient["channel"]>) => {
    channels.push(channel);
    channel.subscribe((status) => {
      if (!active) return;
      if (status === "SUBSCRIBED") {
        subscribed.add(channel);
        connectedOnce = true;
        input.onState(subscribed.size === channels.length ? "connected" : "connecting");
        runCatchUp();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        subscribed.delete(channel);
        input.onState(connectedOnce ? "reconnecting" : "error");
      } else if (status === "CLOSED") {
        subscribed.delete(channel);
        input.onState("reconnecting");
      }
    });
  };

  const start = async () => {
    input.onState("connecting");
    try {
      await client.realtime.setAuth();
    } catch {
      if (active) input.onState("error");
      return;
    }
    if (!active) return;

    const notificationChannel = client
      .channel(notificationTopic(input.userId), { config: { private: true } })
      .on("broadcast", { event: "notification.changed" }, ({ payload }) => accept(payload));
    subscribe(notificationChannel);

    for (const conversationId of [...new Set(input.conversationIds)].sort()) {
      const channel = client
        .channel(conversationTopic(conversationId), { config: { private: true } })
        .on("broadcast", { event: "message.changed" }, ({ payload }) =>
          accept(payload, conversationId),
        );
      subscribe(channel);
    }
  };

  const stop = async () => {
    active = false;
    input.onState("idle");
    await Promise.all(channels.map((channel) => client.removeChannel(channel)));
    channels.length = 0;
    subscribed.clear();
    seen.clear();
  };

  return { start, stop };
};
