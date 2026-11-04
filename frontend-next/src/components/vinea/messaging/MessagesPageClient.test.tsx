import { afterAll, afterEach, beforeEach, describe, expect, it, mock } from "bun:test";
import type { ConversationSummary, Message, Result, SendMessageInput } from "@/services/types";
import { apriDom, chiudiDom } from "@/test/dom";

/**
 * La pagina dei messaggi, eseguita: stati, apertura di una conversazione, lettura e
 * invio con i comandi veri. Il controller è finto: il percorso fino al database è
 * provato da `e2e/messaggi-critici.e2e.ts` e dalla griglia `8_messaging_notifications`.
 */
apriDom();
const { cleanup, fireEvent, render, waitFor, within } = await import("@testing-library/react");
const vineaReale = await import("@/lib/vinea-store");
const phase8Reale = await import("@/lib/phase8/phase8-context");

const conversazione = (id: string, parziale: Partial<ConversationSummary> = {}): ConversationSummary => ({
  id,
  listingId: `annuncio-${id}`,
  listingSlug: `annuncio-${id}`,
  listingPriceCents: 5000,
  orderId: null,
  orderStatus: null,
  counterpart: { userId: `altro-${id}`, username: `utente-${id}`, avatarUrl: null } as unknown as ConversationSummary["counterpart"],
  wineName: `Vino ${id}`,
  wineImage: "",
  writable: true,
  lastMessageId: null,
  lastMessageAt: null,
  lastMessagePreview: `Anteprima ${id}`,
  unreadCount: 0,
  activityAt: "2026-11-04T10:00:00Z",
  createdAt: "2026-11-04T09:00:00Z",
  ...parziale,
});

const messaggio = (id: string, corpo: string, mittente = "altro"): Message => ({
  id,
  conversationId: "c1",
  senderId: mittente,
  kind: "user",
  body: corpo,
  createdAt: "2026-11-04T10:00:00Z",
});

type StatoFinto = {
  conversations: ConversationSummary[];
  messages: Record<string, Message[]>;
  loading: boolean;
  messagesLoading: boolean;
  error: string | null;
  realtimeState: string;
  reload: ReturnType<typeof mock>;
  loadMessages: ReturnType<typeof mock>;
  markConversationRead: ReturnType<typeof mock>;
  sendMessage: ReturnType<typeof mock>;
};

const statoIniziale = (): StatoFinto => ({
  conversations: [],
  messages: {},
  loading: false,
  messagesLoading: false,
  error: null,
  realtimeState: "connected",
  reload: mock(async () => undefined),
  loadMessages: mock(async () => ({ ok: true, data: [] })),
  markConversationRead: mock(async () => ({ ok: true, data: undefined })),
  sendMessage: mock(async () => ({ ok: true, data: messaggio("nuovo", "ok") })),
});

let stato = statoIniziale();
let inTest = false;

mock.module("@/lib/phase8/phase8-context", () => ({
  ...phase8Reale,
  usePhase8: () => (inTest ? stato : phase8Reale.usePhase8()),
}));
mock.module("@/lib/vinea-store", () => ({
  ...vineaReale,
  useVinea: () => (inTest ? { authUser: { userId: "io", email: "io@vinea.test" } } : vineaReale.useVinea()),
}));

const { MessagesPageClient } = await import("./MessagesPageClient");

const pagina = () => within(document.body);
const titolo = () => pagina().getByRole("heading", { name: "Messaggi", level: 1 });

beforeEach(() => {
  inTest = true;
  stato = statoIniziale();
  Object.defineProperty(navigator, "onLine", { configurable: true, value: true });
});

afterEach(() => {
  cleanup();
  inTest = false;
});

afterAll(async () => {
  await chiudiDom();
});

describe("MessagesPageClient — stati senza elenco", () => {
  it("in caricamento mostra l'avanzamento e un titolo per chi naviga a intestazioni", () => {
    stato.loading = true;
    render(<MessagesPageClient />);
    expect(titolo()).toBeTruthy();
    expect(document.body.textContent).toContain("Caricamento conversazioni");
  });

  it("senza conversazioni spiega come iniziarne una", () => {
    render(<MessagesPageClient />);
    expect(titolo()).toBeTruthy();
    expect(pagina().getByText("Nessuna conversazione")).toBeTruthy();
    expect(stato.loadMessages).not.toHaveBeenCalled();
  });

  it("su errore mostra il messaggio e «Riprova» ricarica", () => {
    stato.error = "Non è stato possibile caricare le conversazioni.";
    render(<MessagesPageClient />);
    expect(titolo()).toBeTruthy();
    expect(pagina().getByText(stato.error)).toBeTruthy();

    fireEvent.click(pagina().getByRole("button", { name: /riprova/i }));
    expect(stato.reload).toHaveBeenCalledTimes(1);
  });

  it("offline e senza dati lo dice e permette di riprovare", () => {
    Object.defineProperty(navigator, "onLine", { configurable: true, value: false });
    render(<MessagesPageClient />);
    expect(titolo()).toBeTruthy();
    fireEvent.click(pagina().getByRole("button", { name: /riprova/i }));
    expect(stato.reload).toHaveBeenCalledTimes(1);
  });
});

describe("MessagesPageClient — conversazioni", () => {
  it("elenca le conversazioni e non apre nulla finché non si sceglie", () => {
    stato.conversations = [conversazione("c1"), conversazione("c2", { unreadCount: 3 })];
    render(<MessagesPageClient />);

    expect(titolo()).toBeTruthy();
    expect(pagina().getByText("Anteprima c1")).toBeTruthy();
    expect(pagina().getByText("3")).toBeTruthy();
    expect(pagina().getByText("Seleziona una conversazione")).toBeTruthy();
    expect(stato.loadMessages).not.toHaveBeenCalled();
  });

  it("scegliendo una conversazione carica i messaggi e segna letto l'ultimo", async () => {
    stato.conversations = [conversazione("c1")];
    stato.messages = { c1: [messaggio("m2", "Ultimo messaggio"), messaggio("m1", "Primo messaggio", "io")] };
    stato.loadMessages = mock(async () => ({ ok: true, data: stato.messages.c1 }));
    render(<MessagesPageClient />);

    fireEvent.click(pagina().getByRole("button", { name: /utente-c1/ }));

    await waitFor(() => expect(stato.markConversationRead).toHaveBeenCalledWith("c1", "m2"));
    expect(stato.loadMessages).toHaveBeenCalledWith("c1");
    expect(pagina().getByText("Primo messaggio")).toBeTruthy();
    expect(pagina().getByText("Ultimo messaggio")).toBeTruthy();
  });

  it("apre la conversazione dell'indirizzo, ma ignora un id che non è tra le proprie", async () => {
    stato.conversations = [conversazione("c1")];
    const { unmount } = render(<MessagesPageClient initialConversationId="c1" />);
    await waitFor(() => expect(stato.loadMessages).toHaveBeenCalledWith("c1"));
    unmount();

    stato = { ...statoIniziale(), conversations: [conversazione("c1")] };
    render(<MessagesPageClient initialConversationId="altrui" />);
    expect(stato.loadMessages).not.toHaveBeenCalled();
    expect(pagina().getByText("Seleziona una conversazione")).toBeTruthy();
  });

  it("se i messaggi non si caricano non segna letto e «Riprova» li richiede", async () => {
    stato.conversations = [conversazione("c1")];
    stato.loadMessages = mock(async () => ({ ok: false, error: "Messaggi non disponibili." }));
    render(<MessagesPageClient initialConversationId="c1" />);

    await waitFor(() => expect(pagina().getByText("Messaggi non disponibili.")).toBeTruthy());
    expect(stato.markConversationRead).not.toHaveBeenCalled();

    stato.loadMessages.mockImplementation(async () => ({ ok: true, data: [messaggio("m9", "Recuperato")] }));
    fireEvent.click(pagina().getByRole("button", { name: /riprova/i }));
    await waitFor(() => expect(stato.loadMessages).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(pagina().queryByText("Messaggi non disponibili.")).toBeNull());
    await waitFor(() => expect(stato.markConversationRead).toHaveBeenCalledWith("c1", "m9"));
  });
});

describe("MessagesPageClient — invio", () => {
  const apri = async (parziale: Partial<ConversationSummary> = {}) => {
    stato.conversations = [conversazione("c1", parziale)];
    render(<MessagesPageClient initialConversationId="c1" />);
    await waitFor(() => expect(stato.loadMessages).toHaveBeenCalled());
    return pagina().getByPlaceholderText(/messaggio|sola lettura/i) as HTMLInputElement;
  };
  const inviaBottone = () => pagina().getByRole("button", { name: "Invia messaggio" });

  it("invia il testo una volta e svuota il campo", async () => {
    const campo = await apri();
    expect(inviaBottone().hasAttribute("disabled")).toBe(true);

    fireEvent.change(campo, { target: { value: "Buongiorno, è disponibile?" } });
    fireEvent.click(inviaBottone());

    await waitFor(() => expect(campo.value).toBe(""));
    expect(stato.sendMessage).toHaveBeenCalledTimes(1);
    const inviato = stato.sendMessage.mock.calls[0]?.[0] as SendMessageInput;
    expect(inviato.conversationId).toBe("c1");
    expect(inviato.text).toBe("Buongiorno, è disponibile?");
    expect(inviato.idempotencyKey.length).toBeGreaterThan(10);
  });

  it("solo spazi non partono, né col pulsante né con Invio", async () => {
    const campo = await apri();
    fireEvent.change(campo, { target: { value: "   " } });
    expect(inviaBottone().hasAttribute("disabled")).toBe(true);
    fireEvent.keyDown(campo, { key: "Enter" });
    expect(stato.sendMessage).not.toHaveBeenCalled();
  });

  it("un secondo Invio durante l'invio non manda un doppione", async () => {
    let sblocca: (r: Result<Message>) => void = () => undefined;
    stato.sendMessage = mock(() => new Promise<Result<Message>>((risolvi) => { sblocca = risolvi; }));
    const campo = await apri();
    fireEvent.change(campo, { target: { value: "Una volta sola" } });
    fireEvent.keyDown(campo, { key: "Enter" });
    fireEvent.keyDown(campo, { key: "Enter" });
    expect(stato.sendMessage).toHaveBeenCalledTimes(1);

    sblocca({ ok: true, data: messaggio("nuovo", "Una volta sola") });
    await waitFor(() => expect(campo.value).toBe(""));
  });

  it("dopo un errore conserva il testo e riprova con la stessa chiave, poi ne usa una nuova", async () => {
    stato.sendMessage = mock(async () => ({ ok: false, error: "Invio non riuscito." }));
    const campo = await apri();
    fireEvent.change(campo, { target: { value: "Da ritentare" } });
    fireEvent.click(inviaBottone());

    await waitFor(() => expect(pagina().getByRole("alert").textContent).toContain("Invio non riuscito."));
    expect(campo.value).toBe("Da ritentare");

    stato.sendMessage.mockImplementation(async () => ({ ok: true, data: messaggio("nuovo", "ok") }));
    fireEvent.click(inviaBottone());
    await waitFor(() => expect(campo.value).toBe(""));
    expect(pagina().queryByRole("alert")).toBeNull();

    fireEvent.change(campo, { target: { value: "Altro messaggio" } });
    fireEvent.click(inviaBottone());
    await waitFor(() => expect(stato.sendMessage).toHaveBeenCalledTimes(3));

    const chiavi = stato.sendMessage.mock.calls.map((c) => (c[0] as SendMessageInput).idempotencyKey);
    expect(chiavi[1]).toBe(chiavi[0]!);
    expect(chiavi[2]).not.toBe(chiavi[0]!);
  });

  it("una conversazione conclusa è in sola lettura e non invia", async () => {
    const campo = await apri({ writable: false });
    expect(campo.hasAttribute("disabled")).toBe(true);
    expect(campo.placeholder).toBe("Conversazione in sola lettura");
    expect(pagina().getByText(/sola lettura\.$/)).toBeTruthy();
    fireEvent.keyDown(campo, { key: "Enter" });
    expect(stato.sendMessage).not.toHaveBeenCalled();
  });

  it("offline si leggono i dati già caricati, ma non si invia", async () => {
    Object.defineProperty(navigator, "onLine", { configurable: true, value: false });
    const campo = await apri();
    expect(pagina().getByText(/Offline: puoi leggere/)).toBeTruthy();
    expect(campo.hasAttribute("disabled")).toBe(true);
  });
});
