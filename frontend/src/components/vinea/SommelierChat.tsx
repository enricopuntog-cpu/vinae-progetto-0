import { useEffect, useMemo, useRef, useState } from "react";
import { MessageSquareText, Send, Sparkles, X, Trash2, Loader2 } from "lucide-react";
import { apiJson, apiResponse, jsonRequest } from "@/services/api-client";
import {
  sommelierChunkSchema,
  sommelierHistorySchema,
  type ChatMessage,
} from "@/services/api-contracts";

const STORAGE_KEY = "vinea:sommelier:session";

function ensureSessionId(): string {
  try {
    const cached = localStorage.getItem(STORAGE_KEY);
    if (cached && cached.length >= 4) return cached;
  } catch {
    /* private mode */
  }
  const id = `s-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`;
  try {
    localStorage.setItem(STORAGE_KEY, id);
  } catch {
    /* noop */
  }
  return id;
}

const SUGGESTIONS = [
  "Consigliami un vino per una cena a base di pesce",
  "Come conservo un Barolo da invecchiamento?",
  "Che differenza c'è tra Brunello e Rosso di Montalcino?",
];

export default function SommelierChat() {
  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [sessionId] = useState(ensureSessionId);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Load history the first time the panel opens
  useEffect(() => {
    if (!open || messages.length > 0) return;
    apiJson(`/api/ai/sommelier/history/${encodeURIComponent(sessionId)}`, sommelierHistorySchema)
      .then((data) => setMessages(data.messages ?? []))
      .catch(() => {
        /* first open — ignore */
      });
  }, [open, sessionId, messages.length]);

  useEffect(() => {
    scrollerRef.current?.scrollTo({ top: scrollerRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, sending]);

  useEffect(
    () => () => {
      abortRef.current?.abort();
    },
    [],
  );

  async function send(text: string) {
    const trimmed = text.trim();
    if (!trimmed || sending) return;
    const nextUser: ChatMessage = { role: "user", content: trimmed };
    setMessages((m) => [...m, nextUser, { role: "assistant", content: "" }]);
    setInput("");
    setSending(true);

    const controller = new AbortController();
    abortRef.current = controller;
    try {
      const res = await apiResponse(
        "/api/ai/sommelier/chat",
        jsonRequest(
          { session_id: sessionId, message: trimmed },
          {
            method: "POST",
            headers: { Accept: "text/event-stream" },
            signal: controller.signal,
          },
        ),
      );
      if (!res.body) throw new Error("La risposta del sommelier non contiene dati.");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let assistantText = "";
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let eolIdx: number;
        while ((eolIdx = buffer.indexOf("\n\n")) !== -1) {
          const raw = buffer.slice(0, eolIdx).trim();
          buffer = buffer.slice(eolIdx + 2);
          if (!raw.startsWith("data:")) continue;
          const payload = raw.slice(5).trim();
          if (!payload) continue;
          try {
            const parsed = sommelierChunkSchema.safeParse(JSON.parse(payload));
            if (!parsed.success) continue;
            const chunk = parsed.data;
            if (chunk.delta) {
              assistantText += chunk.delta;
              setMessages((m) => {
                const copy = [...m];
                copy[copy.length - 1] = { role: "assistant", content: assistantText };
                return copy;
              });
            } else if (chunk.error) {
              assistantText += "\n\nNon è stato possibile completare la risposta.";
              setMessages((m) => {
                const copy = [...m];
                copy[copy.length - 1] = { role: "assistant", content: assistantText };
                return copy;
              });
            }
          } catch {
            /* skip malformed chunk */
          }
        }
      }
    } catch (e: unknown) {
      const name = (e as { name?: string })?.name;
      if (name !== "AbortError") {
        setMessages((m) => {
          const copy = [...m];
          const last = copy[copy.length - 1];
          if (last?.role === "assistant" && !last.content) {
            copy[copy.length - 1] = {
              role: "assistant",
              content: "⚠️ Impossibile contattare il sommelier. Riprova tra un istante.",
            };
          }
          return copy;
        });
      }
    } finally {
      setSending(false);
      abortRef.current = null;
    }
  }

  async function reset() {
    try {
      await apiResponse(`/api/ai/sommelier/history/${encodeURIComponent(sessionId)}`, {
        method: "DELETE",
      });
    } catch {
      /* noop */
    }
    setMessages([]);
  }

  const hasChat = messages.length > 0;
  const empty = useMemo(() => !hasChat && !sending, [hasChat, sending]);

  if (!mounted) return null;

  return (
    <>
      {/* Floating trigger */}
      <button
        aria-label="Apri chat Sommelier AI"
        data-testid="sommelier-trigger"
        onClick={() => setOpen(true)}
        className={`fixed right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-bordeaux text-crema shadow-xl ring-4 ring-bordeaux/25 transition-transform duration-200 hover:scale-105 active:scale-95 md:h-16 md:w-16 ${
          open ? "pointer-events-none opacity-0 scale-90" : "opacity-100"
        }`}
        style={{ bottom: "calc(env(safe-area-inset-bottom, 0px) + 5rem)" }}
      >
        <span className="absolute -top-1 -right-1 inline-flex h-3 w-3 rounded-full bg-oro ring-2 ring-crema animate-pulse-soft" />
        <MessageSquareText className="h-6 w-6" />
      </button>

      {/* Backdrop */}
      <div
        onClick={() => setOpen(false)}
        aria-hidden
        className={`fixed inset-0 z-40 bg-antracite/40 backdrop-blur-[2px] transition-opacity duration-200 ${open ? "opacity-100" : "pointer-events-none opacity-0"}`}
      />

      {/* Panel */}
      <aside
        role="dialog"
        aria-label="Sommelier AI"
        data-testid="sommelier-panel"
        className={`fixed right-2 bottom-2 z-50 flex w-[min(94vw,420px)] flex-col overflow-hidden rounded-3xl border border-border bg-card shadow-2xl transition-all duration-300 md:right-6 md:bottom-6 md:w-[420px] ${
          open
            ? "translate-y-0 opacity-100 pointer-events-auto"
            : "translate-y-4 opacity-0 pointer-events-none"
        }`}
        style={{ maxHeight: "min(78vh, 720px)" }}
      >
        {/* Header */}
        <header className="relative overflow-hidden bg-bordeaux px-4 py-4 text-crema">
          <div
            className="absolute inset-0 opacity-25 animate-ken-burns"
            style={{
              backgroundImage: "radial-gradient(circle at 20% 30%, #B59A63 0%, transparent 55%)",
            }}
          />
          <div className="relative flex items-center gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-crema/15">
              <Sparkles className="h-5 w-5 text-oro" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[10px] uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
              <h2 className="font-serif text-xl leading-none">
                Sommelier <span className="gold-shimmer">AI</span>
              </h2>
              <p className="text-[11px] text-crema/70">Assistente Vinea · risposte in italiano</p>
            </div>
            <button
              aria-label="Cancella conversazione"
              data-testid="sommelier-reset"
              onClick={reset}
              disabled={!hasChat}
              className="grid h-9 w-9 place-items-center rounded-full bg-crema/10 text-crema/80 transition hover:bg-crema/20 disabled:opacity-30"
            >
              <Trash2 className="h-4 w-4" />
            </button>
            <button
              aria-label="Chiudi chat"
              data-testid="sommelier-close"
              onClick={() => setOpen(false)}
              className="grid h-9 w-9 place-items-center rounded-full bg-crema/10 text-crema transition hover:bg-crema/20"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </header>

        {/* Messages */}
        <div
          ref={scrollerRef}
          className="flex-1 overflow-y-auto px-3 py-3"
          data-testid="sommelier-messages"
        >
          {empty && (
            <div className="space-y-3 p-2">
              <p className="text-sm text-muted-foreground">
                Ciao! Sono il tuo sommelier virtuale. Chiedimi consigli di abbinamento, curiosità
                sulle denominazioni o dubbi sul servizio.
              </p>
              <div className="grid gap-2">
                {SUGGESTIONS.map((s) => (
                  <button
                    key={s}
                    onClick={() => send(s)}
                    data-testid="sommelier-suggestion"
                    className="rounded-2xl border border-border bg-secondary/50 px-3 py-2 text-left text-xs text-antracite transition hover:border-bordeaux hover:bg-bordeaux/5"
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>
          )}
          {messages.map((m, i) => (
            <div
              key={i}
              className={`mb-2 flex ${m.role === "user" ? "justify-end" : "justify-start"}`}
            >
              <div
                data-testid={m.role === "user" ? "sommelier-msg-user" : "sommelier-msg-assistant"}
                className={`max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm leading-relaxed shadow-sm ${
                  m.role === "user"
                    ? "rounded-br-md bg-bordeaux text-crema"
                    : "rounded-bl-md border border-border bg-secondary/60 text-antracite"
                }`}
              >
                {m.content ||
                  (sending && i === messages.length - 1 ? (
                    <span className="inline-flex items-center gap-1 text-muted-foreground">
                      <Loader2 className="h-3 w-3 animate-spin" /> il sommelier sta scrivendo…
                    </span>
                  ) : (
                    ""
                  ))}
              </div>
            </div>
          ))}
        </div>

        {/* Composer */}
        <form
          className="flex items-center gap-2 border-t border-border bg-crema/60 px-3 py-3"
          onSubmit={(e) => {
            e.preventDefault();
            send(input);
          }}
        >
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Chiedi al sommelier…"
            data-testid="sommelier-input"
            className="min-w-0 flex-1 rounded-full border border-border bg-card px-4 py-2 text-sm outline-none focus:border-bordeaux focus:ring-2 focus:ring-bordeaux/30"
            maxLength={2000}
            disabled={sending}
          />
          <button
            type="submit"
            aria-label="Invia messaggio"
            data-testid="sommelier-send"
            disabled={sending || !input.trim()}
            className="grid h-10 w-10 place-items-center rounded-full bg-bordeaux text-crema shadow transition hover:bg-bordeaux/90 disabled:opacity-40"
          >
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </button>
        </form>
      </aside>
    </>
  );
}
