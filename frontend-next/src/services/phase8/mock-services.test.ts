import { beforeEach, describe, expect, it } from "bun:test";
import { createMockPhase8Services, MOCK_PHASE8_USER_ID } from "@/services/phase8/mock-services";

let services = createMockPhase8Services();

beforeEach(() => {
  services = createMockPhase8Services();
});

describe("conversazioni mock Fase 8", () => {
  it("espone le tre conversazioni del prototipo", async () => {
    const result = await services.messaging.conversazioni();
    expect(result.ok && result.data.items).toHaveLength(3);
  });

  it("ordina le conversazioni per attivita decrescente", async () => {
    const result = await services.messaging.conversazioni();
    if (!result.ok) throw new Error(result.error);
    expect(result.data.items.map((row) => row.activityAt)).toEqual(
      [...result.data.items.map((row) => row.activityAt)].sort().reverse(),
    );
  });

  it("pagina senza offset e produce un cursore completo", async () => {
    const result = await services.messaging.conversazioni(undefined, 1);
    if (!result.ok) throw new Error(result.error);
    expect(result.data.items).toHaveLength(1);
    expect(result.data.nextCursor).toEqual({
      id: result.data.items[0].id,
      createdAt: result.data.items[0].activityAt,
    });
  });

  it("apre una conversazione esistente dall annuncio", async () => {
    const result = await services.messaging.apri({ listingId: "monfortino-2015" });
    expect(result.ok).toBe(true);
  });

  it("non inventa una conversazione demo per un annuncio sconosciuto", async () => {
    const result = await services.messaging.apri({ listingId: "non-esiste" });
    expect(result.ok).toBe(false);
  });
});

describe("messaggi mock Fase 8", () => {
  it("carica i messaggi canonici con identificativi stabili", async () => {
    const conversations = await services.messaging.conversazioni();
    if (!conversations.ok) throw new Error(conversations.error);
    const result = await services.messaging.messaggi(conversations.data.items[0].id);
    if (!result.ok) throw new Error(result.error);
    expect(result.data.items.length).toBeGreaterThan(0);
    expect(new Set(result.data.items.map((row) => row.id)).size).toBe(result.data.items.length);
  });

  it("normalizza il testo e deriva il mittente corrente", async () => {
    const conversation = await services.messaging.apri({ listingId: "monfortino-2015" });
    if (!conversation.ok) throw new Error(conversation.error);
    const result = await services.messaging.invia({
      conversationId: conversation.data.conversationId,
      text: "  ciao  ",
      idempotencyKey: crypto.randomUUID(),
    });
    if (!result.ok) throw new Error(result.error);
    expect(result.data.body).toBe("ciao");
    expect(result.data.senderId).toBe(MOCK_PHASE8_USER_ID);
  });

  it("un retry identico restituisce la stessa riga", async () => {
    const conversation = await services.messaging.apri({ listingId: "monfortino-2015" });
    if (!conversation.ok) throw new Error(conversation.error);
    const input = {
      conversationId: conversation.data.conversationId,
      text: "retry",
      idempotencyKey: crypto.randomUUID(),
    };
    const first = await services.messaging.invia(input);
    const second = await services.messaging.invia(input);
    expect(first.ok && second.ok && first.data.id === second.data.id).toBe(true);
  });

  it("la stessa chiave con payload diverso fallisce", async () => {
    const conversation = await services.messaging.apri({ listingId: "monfortino-2015" });
    if (!conversation.ok) throw new Error(conversation.error);
    const idempotencyKey = crypto.randomUUID();
    await services.messaging.invia({
      conversationId: conversation.data.conversationId,
      text: "primo",
      idempotencyKey,
    });
    const result = await services.messaging.invia({
      conversationId: conversation.data.conversationId,
      text: "secondo",
      idempotencyKey,
    });
    expect(result.ok).toBe(false);
  });

  it("respinge un messaggio vuoto dopo trim", async () => {
    const result = await services.messaging.invia({
      conversationId: "10000000-0000-4000-8000-000000000001",
      text: "   ",
      idempotencyKey: crypto.randomUUID(),
    });
    expect(result.ok).toBe(false);
  });

  it("aggiorna anteprima e attivita della conversazione", async () => {
    const conversation = await services.messaging.apri({ listingId: "monfortino-2015" });
    if (!conversation.ok) throw new Error(conversation.error);
    await services.messaging.invia({
      conversationId: conversation.data.conversationId,
      text: "nuova anteprima",
      idempotencyKey: crypto.randomUUID(),
    });
    const rows = await services.messaging.conversazioni();
    if (!rows.ok) throw new Error(rows.error);
    expect(rows.data.items[0].lastMessagePreview).toBe("nuova anteprima");
  });

  it("segna la conversazione letta senza userId", async () => {
    await services.messaging.segnaLetti("10000000-0000-4000-8000-000000000001");
    const rows = await services.messaging.conversazioni();
    if (!rows.ok) throw new Error(rows.error);
    expect(rows.data.items.find((row) => row.id.endsWith("1"))?.unreadCount).toBe(0);
  });
});

describe("notifiche mock Fase 8", () => {
  it("il conteggio deriva da readAt", async () => {
    const rows = await services.notifications.elenco();
    const count = await services.notifications.nonLette();
    if (!rows.ok || !count.ok) throw new Error("fixture non disponibile");
    expect(count.data).toBe(rows.data.items.filter((row) => row.readAt === null).length);
  });

  it("segna una sola notifica come letta", async () => {
    const rows = await services.notifications.elenco();
    if (!rows.ok) throw new Error(rows.error);
    const target = rows.data.items.find((row) => row.readAt === null)!;
    await services.notifications.segnaLetta(target.id);
    const after = await services.notifications.elenco();
    if (!after.ok) throw new Error(after.error);
    expect(after.data.items.find((row) => row.id === target.id)?.readAt).not.toBeNull();
  });

  it("segna tutte e restituisce il numero aggiornato", async () => {
    const before = await services.notifications.nonLette();
    const result = await services.notifications.segnaTutteLette();
    const after = await services.notifications.nonLette();
    if (!before.ok || !result.ok || !after.ok) throw new Error("fixture non disponibile");
    expect(result.data).toBe(before.data);
    expect(after.data).toBe(0);
  });
});
