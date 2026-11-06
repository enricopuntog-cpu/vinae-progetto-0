/** Closed vocabulary: no error objects, URLs, IDs, messages or session data. */
export const CLIENT_EVENTS = ["client_error", "client_rejection", "client_boundary"] as const;
export type ClientEvent = (typeof CLIENT_EVENTS)[number];

export const isClientEvent = (value: unknown): value is ClientEvent =>
  CLIENT_EVENTS.some((event) => event === value);

export function logClientEvent(event: ClientEvent) {
  console.error("[VINEA_OBS]", JSON.stringify({ event }));
}
