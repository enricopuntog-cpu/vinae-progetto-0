/** CSP reports are untrusted telemetry, never authentication or an audit trail.
 * Keep only closed categories: URLs can contain reset tokens, signed Storage
 * tokens, user IDs and attacker-controlled text. Never log the original body.
 */
const DIRECTIVES = new Set([
  "default-src", "script-src", "script-src-elem", "script-src-attr",
  "style-src", "style-src-elem", "style-src-attr", "img-src", "font-src",
  "connect-src", "frame-src", "frame-ancestors", "base-uri", "form-action",
  "object-src", "worker-src", "media-src", "manifest-src",
]);

type Report = { directive: string; resource: string };
const record = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown> : null;

function resourceCategory(value: unknown): string {
  if (value === "inline" || value === "eval") return value;
  if (typeof value !== "string") return "unknown";
  try {
    const url = new URL(value);
    if (url.protocol === "data:" || url.protocol === "blob:") return url.protocol.slice(0, -1);
    if (!["https:", "wss:"].includes(url.protocol)) return "other";
    if (url.hostname === "vineawineclub.com") return "vinea";
    if (url.hostname === "pijnmcllmfgjmgsvtcej.supabase.co") return "supabase";
    if (["fonts.googleapis.com", "fonts.gstatic.com"].includes(url.hostname)) return "google-fonts";
    if (url.hostname === "i.pravatar.cc") return "demo-avatar";
    return "external";
  } catch { return "unknown"; }
}

export function sanitizeCspReports(value: unknown): Report[] {
  const candidates = Array.isArray(value) ? value.slice(0, 10) : [value];
  const reports: Report[] = [];
  for (const candidate of candidates) {
    const envelope = record(candidate);
    if (!envelope) continue;
    const body = record(envelope["csp-report"])
      ?? (envelope.type === "csp-violation" ? record(envelope.body) : null);
    if (!body) continue;
    const directive = body["effective-directive"] ?? body.effectiveDirective;
    if (typeof directive !== "string" || !DIRECTIVES.has(directive)) continue;
    reports.push({ directive, resource: resourceCategory(body["blocked-uri"] ?? body.blockedURL) });
  }
  return reports;
}

const MAX_BYTES = 16_384;

/** Bounded even when Content-Length is absent or forged. */
async function readReport(request: Request): Promise<unknown> {
  if (Number(request.headers.get("content-length")) > MAX_BYTES) throw new Error("size");
  const reader = request.body?.getReader();
  if (!reader) throw new Error("body");
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > MAX_BYTES) { await reader.cancel(); throw new Error("size"); }
      chunks.push(chunk.value);
    }
  } finally { reader.releaseLock(); }
  const body = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(body));
}

export function createCspReportHandler(
  log: (reports: Report[]) => void,
  now: () => number = Date.now,
) {
  // Per warm instance, no per-IP/user map. This bounds log volume, not DDoS;
  // infrastructure access logs and edge abuse protection remain separate.
  let start = 0;
  let count = 0;
  return async (request: Request): Promise<Response> => {
    const response = (status: number) => new Response(null, {
      status, headers: { "Cache-Control": "no-store" },
    });
    if (request.headers.get("sec-fetch-site") === "cross-site") return response(403);
    const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim();
    if (!["application/csp-report", "application/reports+json"].includes(contentType ?? "")) {
      return response(415);
    }
    const time = now();
    if (time - start >= 60_000) { start = time; count = 0; }
    if (++count > 30) return response(429);
    try {
      const reports = sanitizeCspReports(await readReport(request));
      if (reports.length) log(reports);
      return response(204);
    } catch { return response(400); }
  };
}
