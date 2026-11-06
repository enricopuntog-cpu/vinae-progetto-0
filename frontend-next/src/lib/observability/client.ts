import type { ClientEvent } from "./events";

/** At most one report of each kind per minute per tab; no persistent identifier. */
export function createClientReporter(send: typeof fetch = fetch, now = Date.now) {
  const last = new Map<ClientEvent, number>();
  return (event: ClientEvent) => {
    const time = now();
    const previous = last.get(event);
    if (previous !== undefined && time - previous < 60_000) return;
    last.set(event, time);
    // Never pass the original event/error, even as a supposedly sanitized field.
    try {
      void send("/api/technical-events", {
        method: "POST",
        body: event,
        headers: { "Content-Type": "text/plain" },
        credentials: "omit",
        referrerPolicy: "no-referrer",
        cache: "no-store",
        keepalive: true,
      }).catch(() => {});
    } catch { /* Monitoring must not break the application or recurse. */ }
  };
}

export const reportClientEvent = createClientReporter();
