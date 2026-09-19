/** Server-owned configuration only; never accept origins/nonces from the client. */
export function buildPageCsp(nonce: string, supabaseUrl?: string, development = false): string {
  if (!/^[A-Za-z0-9+/=]{22,128}$/.test(nonce)) throw new Error("Invalid CSP nonce");
  const api = new URL(supabaseUrl || "https://pijnmcllmfgjmgsvtcej.supabase.co");
  if (api.username || api.password || api.pathname !== "/" || api.search || api.hash ||
      !(api.protocol === "https:" || (api.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(api.hostname)))) {
    throw new Error("Invalid Supabase origin");
  }
  const socket = new URL(api);
  socket.protocol = api.protocol === "https:" ? "wss:" : "ws:";
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development ? " 'unsafe-eval'" : ""}`,
    "script-src-attr 'none'",
    // Radix, charts and React set inline styles. This does not allow scripts.
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    `img-src 'self' data: blob: ${api.origin}`,
    "font-src 'self' data: https://fonts.gstatic.com",
    `connect-src 'self' ${api.origin} ${socket.origin}${development ? " ws://localhost:* ws://127.0.0.1:*" : ""}`,
    "worker-src 'self' blob:",
    "frame-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
    "report-uri /api/security/csp-report",
    "report-to csp",
  ].join("; ");
}
