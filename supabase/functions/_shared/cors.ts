const parseAllowedOrigins = (): ReadonlySet<string> =>
  new Set(
    (Deno.env.get("PAYMENT_ALLOWED_ORIGINS") ?? "http://localhost:3000")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );

export const corsHeadersFor = (request: Request): HeadersInit | null => {
  const origin = request.headers.get("origin");
  if (!origin || !parseAllowedOrigins().has(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-idempotency-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
};
