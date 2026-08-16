const PORTA = Number(Bun.env.BETA_MOCK_PORT ?? "54321");
const ORIGINE_APP = Bun.env.BETA_APP_ORIGIN ?? "http://127.0.0.1:3101";
const USER_ID = "11111111-1111-4111-8111-111111111111";

const contatori = { ia: 0, pagamento: 0, logistica: 0 };
const oraIso = "2026-08-15T10:00:00.000Z";
const CONVERSATION_ID = "55555555-5555-4555-8555-555555555555";
let conversazioneAperta = false;
const messaggi: Record<string, unknown>[] = [];
const proposte: Record<string, unknown>[] = [];

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

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": ORIGINE_APP,
          "Access-Control-Allow-Credentials": "true",
          "Access-Control-Allow-Headers":
            request.headers.get("access-control-request-headers") ?? "content-type",
          "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
        },
      });
    }
    if (url.pathname === "/_counts") return json(contatori);
    if (url.pathname === "/auth/v1/token") return json(sessione);
    if (url.pathname === "/auth/v1/user") return json(utente);
    if (url.pathname === "/auth/v1/logout") return json({});
    if (url.pathname === "/rest/v1/profiles") {
      return json({ dob: "1990-01-01", username: "Utente beta" });
    }
    if (url.pathname === "/rest/v1/user_roles") return json([{ role: "admin" }]);
    if (url.pathname === "/rest/v1/public_listings") {
      const singola = request.headers.get("accept")?.includes("vnd.pgrst.object");
      return json(singola ? annuncio : [annuncio], 200, { "Content-Range": "0-0/1" });
    }
    if (url.pathname === "/rest/v1/proposals") return json(proposte);
    if (url.pathname === "/rest/v1/rpc/proposal_invia") {
      const input = (await request.json()) as {
        p_listing_id: string;
        p_prezzo_cents: number;
      };
      const proposta = {
        id: "66666666-6666-4666-8666-666666666666",
        listing_id: input.p_listing_id,
        buyer_id: USER_ID,
        seller_id: annuncio.seller_id,
        prezzo_richiesto_cents: annuncio.prezzo_cents,
        prezzo_proposto_cents: input.p_prezzo_cents,
        controproposta_cents: null,
        stato: "inviata",
        scadenza: "2026-08-22T10:00:00.000Z",
        created_at: oraIso,
        updated_at: oraIso,
      };
      proposte.splice(0, proposte.length, proposta);
      return json(proposta);
    }
    if (url.pathname === "/rest/v1/rpc/conversation_open") {
      conversazioneAperta = true;
      return json(CONVERSATION_ID);
    }
    if (url.pathname === "/rest/v1/rpc/message_send") {
      const input = (await request.json()) as {
        p_conversation_id: string;
        p_text: string;
      };
      const messaggio = {
        id: "77777777-7777-4777-8777-777777777777",
        conversation_id: input.p_conversation_id,
        sender_id: USER_ID,
        kind: "user",
        body: input.p_text,
        created_at: oraIso,
      };
      messaggi.splice(0, messaggi.length, messaggio);
      return json([messaggio]);
    }
    if (url.pathname === "/rest/v1/rpc/conversations_page") {
      return json(
        conversazioneAperta
          ? [
              {
                conversation_id: CONVERSATION_ID,
                listing_id: annuncio.id,
                listing_slug: annuncio.slug,
                listing_price_cents: annuncio.prezzo_cents,
                order_id: null,
                order_status: null,
                counterpart_id: annuncio.seller_id,
                counterpart_username: annuncio.seller_username,
                counterpart_avatar_url: annuncio.seller_avatar_url,
                wine_name: `${annuncio.nome} ${annuncio.annata}`,
                wine_image: annuncio.immagini[0],
                writable: true,
                last_message_id: (messaggi[0]?.id as string | undefined) ?? null,
                last_message_at: messaggi.length ? oraIso : null,
                last_message_preview: (messaggi[0]?.body as string | undefined) ?? null,
                unread_count: 0,
                activity_at: oraIso,
                created_at: oraIso,
              },
            ]
          : [],
      );
    }
    if (url.pathname === "/rest/v1/rpc/messages_page") return json(messaggi);
    if (url.pathname === "/rest/v1/rpc/conversation_mark_read") return json(null);
    if (url.pathname.startsWith("/functions/v1/ai-")) contatori.ia += 1;
    if (url.pathname === "/functions/v1/payments-checkout") contatori.pagamento += 1;
    if (/packaging|shipping|shipment|label/.test(url.pathname)) contatori.logistica += 1;
    if (url.pathname.startsWith("/functions/v1/")) return json({ message: "Azione esterna vietata nello smoke locale." }, 503);
    if (url.pathname.startsWith("/rest/v1/")) return json([]);
    return json({ message: "Endpoint mock non previsto." }, 404);
  },
});

console.log(`Mock Supabase beta in ascolto su http://127.0.0.1:${PORTA}`);
