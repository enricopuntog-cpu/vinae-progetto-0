// Fase 10 — allowlist di origini delle sole function AI.
//
// Perché questo file esiste invece di un `import` da `_shared/cors.ts`: la
// decisione 7.6 dell'11 agosto 2026 ha respinto il rename dell'allowlist dei
// pagamenti. `PAYMENT_ALLOWED_ORIGINS` resta intatta e `_shared/cors.ts` non va
// toccato, perché il merge ridistribuisce **tutte** le Edge Function insieme
// (verifica registrata nella decisione 7.10): modificare il file condiviso
// significa rimettere in produzione il percorso dei pagamenti a ogni merge
// successivo, chiunque lo faccia e per qualunque motivo. Il guadagno sarebbe
// stato di igiene dei nomi, il rischio 403 su tre function in produzione.
//
// Il pattern è replicato identico e non riscritto: origini **complete** e mai
// sottostringhe, `Vary: Origin`, `null` quando l'origine non è in lista — così
// il chiamante distingue «non consentita» da «consentita senza header».

const parseAllowedOrigins = (): ReadonlySet<string> =>
  new Set(
    (Deno.env.get("AI_ALLOWED_ORIGINS") ?? "http://localhost:3000")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );

export const aiCorsHeadersFor = (request: Request): HeadersInit | null => {
  const origin = request.headers.get("origin");
  if (!origin || !parseAllowedOrigins().has(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
};
