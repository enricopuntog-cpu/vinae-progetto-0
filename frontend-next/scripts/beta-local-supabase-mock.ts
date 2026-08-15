const PORTA = Number(Bun.env.BETA_MOCK_PORT ?? "54321");
const ORIGINE_APP = Bun.env.BETA_APP_ORIGIN ?? "http://127.0.0.1:3101";
const USER_ID = "11111111-1111-4111-8111-111111111111";

const contatori = { ia: 0, pagamento: 0, logistica: 0 };
const oraIso = "2026-08-15T10:00:00.000Z";

const base64Url = (valore: object) =>
  Buffer.from(JSON.stringify(valore)).toString("base64url");

const token = `${base64Url({ alg: "HS256", typ: "JWT" })}.${base64Url({
  aud: "authenticated",
  exp: Math.floor(Date.now() / 1000) + 3600,
  sub: USER_ID,
  role: "authenticated",
  email: "beta@local.test",
})}.firma-locale`;

const utente = {
  id: USER_ID,
  aud: "authenticated",
  role: "authenticated",
  email: "beta@local.test",
  email_confirmed_at: oraIso,
  phone: "",
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: {},
  identities: [],
  created_at: oraIso,
  updated_at: oraIso,
};

const sessione = {
  access_token: token,
  token_type: "bearer",
  expires_in: 3600,
  expires_at: Math.floor(Date.now() / 1000) + 3600,
  refresh_token: "refresh-locale",
  user: utente,
};

const annuncio = {
  id: "22222222-2222-4222-8222-222222222222",
  slug: "beta-barolo",
  prezzo_cents: 10000,
  prezzo_mercato_cents: 12000,
  quantita: 1,
  condizione: "Ottima",
  conservazione: "Cantina climatizzata",
  storia: "Annuncio generato dal mock locale per lo smoke beta.",
  degustazione: "Frutto rosso e tannino fine.",
  immagini: ["/images/vinea-bottle-1.jpg"],
  tag: ["mock locale"],
  published_at: oraIso,
  created_at: oraIso,
  pubblicato_at: oraIso,
  wine_id: "33333333-3333-4333-8333-333333333333",
  wine_slug: "barolo-beta",
  produttore: "Cantina Locale",
  nome: "Barolo Beta",
  annata: 2019,
  regione: "Piemonte",
  denominazione: "Barolo DOCG",
  tipo: "rosso",
  formato: "0,75 L",
  ricerca: "barolo beta cantina locale",
  seller_id: "44444444-4444-4444-8444-444444444444",
  seller_username: "Venditore locale",
  seller_citta: "Torino",
  seller_avatar_url: "/images/vinea-bottle-1.jpg",
  wine_provenienza: "staff",
};

const json = (body: unknown, status = 200, extra: HeadersInit = {}) =>
  Response.json(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin": ORIGINE_APP,
      "Access-Control-Allow-Credentials": "true",
      "Access-Control-Allow-Headers": "accept-profile, authorization, apikey, content-profile, content-type, prefer, range, x-client-info, x-supabase-api-version",
      "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
      ...extra,
    },
  });

Bun.serve({
  hostname: "127.0.0.1",
  port: PORTA,
  fetch: async (request) => {
    const url = new URL(request.url);
    console.log(`${request.method} ${url.pathname}${url.search}`);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { "Access-Control-Allow-Origin": ORIGINE_APP, "Access-Control-Allow-Credentials": "true", "Access-Control-Allow-Headers": "accept-profile, authorization, apikey, content-profile, content-type, prefer, range, x-client-info, x-supabase-api-version", "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS" } });
    if (url.pathname === "/_counts") return json(contatori);
    if (url.pathname === "/auth/v1/token") return json(sessione);
    if (url.pathname === "/auth/v1/user") return json(utente);
    if (url.pathname === "/auth/v1/logout") return json({});
    if (url.pathname === "/rest/v1/profiles") return json({ dob: "1990-01-01" });
    if (url.pathname === "/rest/v1/user_roles") return json([{ role: "admin" }]);
    if (url.pathname === "/rest/v1/public_listings") {
      const singola = request.headers.get("accept")?.includes("vnd.pgrst.object");
      return json(singola ? annuncio : [annuncio], 200, { "Content-Range": "0-0/1" });
    }
    if (url.pathname.startsWith("/functions/v1/ai-")) contatori.ia += 1;
    if (url.pathname === "/functions/v1/payments-checkout") contatori.pagamento += 1;
    if (/packaging|shipping|shipment|label/.test(url.pathname)) contatori.logistica += 1;
    if (url.pathname.startsWith("/functions/v1/")) return json({ message: "Azione esterna vietata nello smoke locale." }, 503);
    if (url.pathname.startsWith("/rest/v1/")) return json([]);
    return json({ message: "Endpoint mock non previsto." }, 404);
  },
});

console.log(`Mock Supabase beta in ascolto su http://127.0.0.1:${PORTA}`);
