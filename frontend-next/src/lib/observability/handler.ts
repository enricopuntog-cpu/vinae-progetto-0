import { isClientEvent, logClientEvent, type ClientEvent } from "./events";

/** Process-local volume cap, not authentication or a distributed anti-DDoS limit. */
export function createTechnicalEventHandler(log: (event: ClientEvent) => void = logClientEvent, now = Date.now) {
  let start = 0;
  let count = 0;
  return async (request: Request): Promise<Response> => {
    const response = (status: number) => new Response(null, {
      status, headers: { "Cache-Control": "no-store" },
    });
    const origin = request.headers.get("origin");
    if (request.headers.get("sec-fetch-site") === "cross-site") return response(403);
    if (origin) {
      try {
        const parsed = new URL(origin);
        // Next may normalize request.url to localhost internally. Host is the
        // effective browser-facing authority; this anonymous check grants no privilege.
        const host = request.headers.get("host") ?? new URL(request.url).host;
        if (!["http:", "https:"].includes(parsed.protocol) || parsed.host !== host) return response(403);
      } catch { return response(403); }
    }
    if (request.headers.get("content-type")?.split(";", 1)[0].trim() !== "text/plain") return response(415);
    const time = now();
    if (time - start >= 60_000) { start = time; count = 0; }
    if (++count > 30) return response(429);
    if (Number(request.headers.get("content-length")) > 32) return response(413);
    const reader = request.body?.getReader();
    if (!reader) return response(400);
    try {
      let body = "";
      let bytes = 0;
      const decoder = new TextDecoder();
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        bytes += chunk.value.byteLength;
        if (bytes > 32) { await reader.cancel(); return response(413); }
        body += decoder.decode(chunk.value, { stream: true });
      }
      body += decoder.decode();
      if (!isClientEvent(body)) return response(400);
      log(body);
      return response(204);
    } catch { return response(400); }
    finally { reader.releaseLock(); }
  };
}
