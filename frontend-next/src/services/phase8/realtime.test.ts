import { describe, expect, it } from "bun:test";
import {
  conversationTopic,
  createPhase8RealtimeManager,
  notificationTopic,
  parsePhase8Invalidation,
} from "@/services/phase8/realtime";

const USER = "10000000-0000-4000-8000-000000000001";
const CONVERSATION = "20000000-0000-4000-8000-000000000001";
const MESSAGE = "30000000-0000-4000-8000-000000000001";

type Callback = (payload: { payload: unknown }) => void;
type StatusCallback = (status: string) => void;

const fakeClient = () => {
  const calls: string[] = [];
  const channels: Array<{
    topic: string;
    options: unknown;
    callback?: Callback;
    status?: StatusCallback;
  }> = [];
  const client = {
    realtime: { setAuth: async () => void calls.push("setAuth") },
    channel: (topic: string, options: unknown) => {
      const channel = {
        topic,
        options,
        on: (_type: string, _filter: unknown, callback: Callback) => {
          channel.callback = callback;
          return channel;
        },
        subscribe: (callback: StatusCallback) => {
          calls.push(`subscribe:${topic}`);
          channel.status = callback;
          return channel;
        },
      } as (typeof channels)[number] & {
        on: (_type: string, _filter: unknown, callback: Callback) => unknown;
        subscribe: (callback: StatusCallback) => unknown;
      };
      channels.push(channel);
      return channel;
    },
    removeChannel: async (channel: (typeof channels)[number]) => {
      calls.push(`remove:${channel.topic}`);
      return "ok" as const;
    },
  };
  return { client, calls, channels };
};

const messageEvent = {
  schemaVersion: 1,
  entity: "message",
  id: MESSAGE,
  conversationId: CONVERSATION,
  createdAt: "2026-08-07T12:00:00.000Z",
} as const;

describe("payload Realtime Fase 8", () => {
  it("accetta solo la whitelist esatta", () => {
    expect(parsePhase8Invalidation(messageEvent)).toEqual(messageEvent);
    expect(parsePhase8Invalidation({ ...messageEvent, body: "dato non ammesso" })).toBeNull();
  });

  it("respinge UUID, versione e timestamp malformati", () => {
    expect(parsePhase8Invalidation({ ...messageEvent, id: "x" })).toBeNull();
    expect(parsePhase8Invalidation({ ...messageEvent, schemaVersion: 2 })).toBeNull();
    expect(parsePhase8Invalidation({ ...messageEvent, createdAt: "mai" })).toBeNull();
  });

  it("costruisce solo topic privati canonici", () => {
    expect(conversationTopic(CONVERSATION)).toBe(`conversation:${CONVERSATION}`);
    expect(notificationTopic(USER)).toBe(`user:${USER}:notifications`);
  });
});

describe("lifecycle Realtime Fase 8", () => {
  it("autentica prima di creare e sottoscrivere canali privati", async () => {
    const { client, calls, channels } = fakeClient();
    const manager = createPhase8RealtimeManager(client as never, {
      userId: USER,
      conversationIds: [CONVERSATION],
      onMessage: () => undefined,
      onNotifications: () => undefined,
      onCatchUp: () => undefined,
      onState: () => undefined,
    });
    await manager.start();
    expect(calls[0]).toBe("setAuth");
    expect(channels).toHaveLength(2);
    expect(
      channels.every(
        (row) => row.options && (row.options as { config: { private: boolean } }).config.private,
      ),
    ).toBe(true);
    expect(channels.some((row) => row.topic.startsWith("public:"))).toBe(false);
  });

  it("fallisce chiuso se setAuth non riesce", async () => {
    const { client, channels } = fakeClient();
    const states: string[] = [];
    client.realtime.setAuth = async () => {
      throw new Error("sessione assente");
    };
    const manager = createPhase8RealtimeManager(client as never, {
      userId: USER,
      conversationIds: [CONVERSATION],
      onMessage: () => undefined,
      onNotifications: () => undefined,
      onCatchUp: () => undefined,
      onState: (state) => void states.push(state),
    });
    await manager.start();
    expect(channels).toHaveLength(0);
    expect(states).toEqual(["connecting", "error"]);
  });

  it("deduplica invalidazioni e ignora payload di un altro topic", async () => {
    const { client, channels } = fakeClient();
    const received: string[] = [];
    const manager = createPhase8RealtimeManager(client as never, {
      userId: USER,
      conversationIds: [CONVERSATION],
      onMessage: (id) => void received.push(id),
      onNotifications: () => undefined,
      onCatchUp: () => undefined,
      onState: () => undefined,
    });
    await manager.start();
    const channel = channels.find((row) => row.topic.startsWith("conversation:"))!;
    channel.callback?.({ payload: messageEvent });
    channel.callback?.({ payload: messageEvent });
    channel.callback?.({ payload: { ...messageEvent, conversationId: USER } });
    expect(received).toEqual([CONVERSATION]);
  });

  it("esegue catch-up alla subscribe e rimuove ogni canale allo stop", async () => {
    const { client, calls, channels } = fakeClient();
    let catches = 0;
    const states: string[] = [];
    const manager = createPhase8RealtimeManager(client as never, {
      userId: USER,
      conversationIds: [CONVERSATION, CONVERSATION],
      onMessage: () => undefined,
      onNotifications: () => undefined,
      onCatchUp: () => void (catches += 1),
      onState: (state) => void states.push(state),
    });
    await manager.start();
    channels.forEach((row) => row.status?.("SUBSCRIBED"));
    await Promise.resolve();
    expect(catches).toBe(1);
    expect(states.at(-1)).toBe("connected");
    await manager.stop();
    expect(calls.filter((row) => row.startsWith("remove:"))).toHaveLength(2);
    expect(states.at(-1)).toBe("idle");
  });

  it("ignora callback gia consegnate dopo il teardown", async () => {
    const { client, channels } = fakeClient();
    let received = 0;
    const manager = createPhase8RealtimeManager(client as never, {
      userId: USER,
      conversationIds: [CONVERSATION],
      onMessage: () => void (received += 1),
      onNotifications: () => undefined,
      onCatchUp: () => undefined,
      onState: () => undefined,
    });
    await manager.start();
    const callback = channels[1].callback!;
    await manager.stop();
    callback({ payload: messageEvent });
    expect(received).toBe(0);
  });
});
