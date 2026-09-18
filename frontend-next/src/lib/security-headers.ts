/**
 * Header di sicurezza HTTP (security audit del 17 settembre 2026).
 *
 * Vivono in due posti, e servono entrambi: su Netlify le regole `[[headers]]`
 * di `netlify.toml` raggiungono solo i file statici serviti dalla CDN, non le
 * pagine rese dalla funzione Next.js — misurato sulla Deploy Preview della
 * PR #119, dove `/` non portava né X-Frame-Options né la CSP. Le pagine li
 * ricevono da `headers()` in `next.config.ts`, che legge questo elenco.
 * `security-headers.test.ts` impedisce alle due copie di divergere.
 *
 * La CSP è in Report-Only: la versione enforcing con nonce generato nel Proxy
 * è un passo successivo, da scrivere dopo aver letto le violazioni reali.
 * Origini oltre a 'self': Supabase (REST/Auth/Storage via https, Realtime via
 * wss, immagini pubbliche e firmate del bucket), Google Fonts (foglio di stile
 * in `app/layout.tsx` e file dei font) e i.pravatar.cc (avatar dei dati
 * dimostrativi).
 */
const SUPABASE_ORIGIN = "pijnmcllmfgjmgsvtcej.supabase.co";

export const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  `img-src 'self' data: blob: https://${SUPABASE_ORIGIN} https://i.pravatar.cc`,
  "font-src 'self' data: https://fonts.gstatic.com",
  `connect-src 'self' https://${SUPABASE_ORIGIN} wss://${SUPABASE_ORIGIN}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join("; ");

export const SECURITY_HEADERS: ReadonlyArray<{ key: string; value: string }> = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=()" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "Content-Security-Policy-Report-Only", value: CONTENT_SECURITY_POLICY },
];
