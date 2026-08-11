// Fase 10 — la porta comune delle function AI.
//
// La decisione 7.6 vuole **una function per funzionalità**, non una parametrica
// con un `action` nel corpo. Questo file non contraddice quella decisione: non
// è una function, è il controllo di accesso che le tre function ripetono
// identico. Tenerlo in tre copie non avrebbe reso le porte più separate, avrebbe
// solo reso possibile che una delle tre invecchiasse.
//
// L'ordine dei controlli non è casuale ed è quello di `payments-checkout`
// (`supabase/functions/payments-checkout/index.ts:104-123`): origine, metodo,
// flag, bearer, identità, stato utente, bucket. Il flag sta **prima**
// dell'autenticazione perché una fase spenta non deve nemmeno guardare un token.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { aiCorsHeadersFor } from "./ai-cors.ts";

export const json = (body: unknown, status: number, headers: HeadersInit = {}): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configurazione server mancante: ${name}`);
  return value;
};

// ---------------------------------------------------------------------------
// I numeri della decisione 7.4, in un punto solo
// ---------------------------------------------------------------------------
//
// Un bucket **per funzionalità**, non uno condiviso come il legacy
// (`ai:user:{user.id}`, `backend/ai_routes.py:29`), dove una raffica di
// abbinamenti consuma il budget della chat. Finestra **oraria** sul modello di
// `report:submit`
// (`supabase/migrations/20260810152000_phase_9a_moderation_schema.sql:524`,
// cioè `10, 3600`) e non al minuto come il checkout. Nessun secondo tetto
// nostro: il tetto complessivo è il limite di spesa configurato sul conto del
// provider (7.11), che è l'unico che protegge anche da una chiave uscita.
//
// ATTENZIONE, e il motivo per cui questi numeri stanno qui e non sparsi: il
// legacy limita la chat a 20 per 60 s (`backend/.env.example:44-45`), mentre una
// conversazione Sommelier realistica è di cinque-quindici battute. `ai:chat` a
// 10/ora si esaurisce **dentro una conversazione sola**. La decisione ha fissato
// la forma — bucket per funzionalità, finestra oraria — citando `10 / 3600` come
// modello; il valore di `ai:chat` è quello da riconfermare prima di accendere
// `AI_ENABLED`, ed è una riga.

export const FINESTRA_SECONDI = 3600;

export const LIMITI: Record<AiScope, number> = {
  "ai:chat": 10,
  "ai:pairing": 10,
  "ai:catalogo": 10,
};

export type AiScope = "ai:chat" | "ai:pairing" | "ai:catalogo";

// ---------------------------------------------------------------------------

export type PortaAperta = {
  cors: HeadersInit;
  supabase: SupabaseClient;
  userId: string;
};

/** Quando la porta non si apre, il chiamante restituisce questa risposta e basta. */
export type PortaChiusa = { risposta: Response };

export const chiusa = (valore: PortaAperta | PortaChiusa): valore is PortaChiusa =>
  "risposta" in valore;

/**
 * Applica tutti i controlli d'ingresso e restituisce o la porta aperta, con il
 * client di servizio e l'identità già risolti, o la risposta da rendere.
 *
 * Il client costruito qui è di **servizio** e non lascia mai la function: al
 * browser tornano solo i dati di dominio. È lo stesso schema di
 * `payments-checkout`, dove il JWT del chiamante attraversa il gateway e non
 * porta nessuna autorità sul database.
 */
export const apriPorta = async (
  request: Request,
  scope: AiScope,
): Promise<PortaAperta | PortaChiusa> => {
  const cors = aiCorsHeadersFor(request);
  if (!cors) return { risposta: json({ error: "Origine non consentita." }, 403) };
  if (request.method === "OPTIONS") {
    return { risposta: new Response(null, { status: 204, headers: cors }) };
  }
  if (request.method !== "POST") {
    return { risposta: json({ error: "Metodo non consentito." }, 405, cors) };
  }

  // 7.5 e 7.11: gemello di `PAYMENTS_ENABLED`
  // (`supabase/functions/payments-checkout/index.ts:108`). Manca la variabile,
  // la funzione è spenta. Qui conta più che per i pagamenti, perché il merge
  // distribuisce le function entro un minuto con qualunque ambiente trovi: con
  // il flag assente per default, ciò che va in produzione va spento.
  if (Deno.env.get("AI_ENABLED") !== "true") {
    return { risposta: json({ error: "Funzioni AI non attive." }, 503, cors) };
  }

  const authorization = request.headers.get("authorization") ?? "";
  const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  // 7.9: l'anonimo prende 401, che è parità con `frontend/` — il pannello resta
  // montato per tutti e l'API rifiuta, non la UI.
  if (!accessToken) {
    return { risposta: json({ error: "Autenticazione richiesta." }, 401, cors) };
  }

  let supabase: SupabaseClient;
  try {
    supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  } catch {
    // Configurazione incompleta: si comporta come il flag spento, perché è la
    // stessa situazione vista dall'utente.
    return { risposta: json({ error: "Funzioni AI non attive." }, 503, cors) };
  }

  const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
  if (authError || !authData.user) {
    return { risposta: json({ error: "Sessione non valida." }, 401, cors) };
  }
  const userId = authData.user.id;

  // 7.9: l'accesso AI segue i due livelli della 9b/9c. Il primo — `sospeso` —
  // blocca le sole scritture social e **non** tocca l'AI; il secondo —
  // `rimosso` — toglie anche la visione, e il Sommelier è una superficie di
  // consultazione.
  //
  // La lettura è diretta su `profiles` perché `private.utente_stato_di` vive in
  // `private` e non ha un wrapper `public`
  // (`supabase/migrations/20260810180000_phase_9b_moderation_actions.sql:161-172`):
  // chiamarlo da PostgREST costerebbe una migrazione in più, e `service_role` ha
  // `bypassrls`, quindi non serve.
  //
  // Nota vincolante che questo controllo non attraversa: **niente qui tocca la
  // macchina dei pagamenti**. Nessuna di queste function guarda un ordine, un
  // pagamento o un payout, e la regola fissata per la 9c non cambia natura
  // perché il predicato lo aggiunge una fase successiva.
  const { data: profilo, error: profiloError } = await supabase
    .from("profiles")
    .select("stato_utente")
    .eq("id", userId)
    .maybeSingle();
  if (profiloError) {
    console.error("[ai] lettura stato utente fallita", { code: profiloError.code });
    return { risposta: json({ error: "Funzioni AI non disponibili." }, 503, cors) };
  }
  if ((profilo?.stato_utente ?? "attivo") === "rimosso") {
    return { risposta: json({ error: "Accesso non consentito." }, 403, cors) };
  }

  // 7.4. `public.rate_limit_consume` è concessa a `service_role` e a nessun
  // altro (`supabase/migrations/20260731135455_phase_7_order_payment_service.sql:157-160`):
  // esiste dalla Fase 7 e non richiede nessuna migrazione nuova. Il limite vale
  // anche per `admin`, senza eccezioni: protegge il budget, non l'utente, e
  // un'esenzione sarebbe una via privilegiata proprio nello scenario in cui il
  // tetto serve.
  const { error: limiteError } = await supabase.rpc("rate_limit_consume", {
    p_scope: scope,
    p_subject: `user:${userId}`,
    p_limit: LIMITI[scope],
    p_window_seconds: FINESTRA_SECONDI,
  });
  if (limiteError) {
    return {
      risposta: json(
        { error: "Limite temporaneo delle funzioni AI raggiunto." },
        429,
        { ...cors, "Retry-After": String(FINESTRA_SECONDI) },
      ),
    };
  }

  return { cors, supabase, userId };
};

/**
 * Corpo della richiesta, con il solo controllo che sia un oggetto JSON. La
 * validazione dei campi appartiene a ogni function, perché è lì che i vincoli
 * del legacy vanno riprodotti uno per uno.
 */
export const leggiCorpo = async (request: Request): Promise<Record<string, unknown> | null> => {
  try {
    const parsed = await request.json();
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
};

/** Testo obbligatorio con lunghezza massima, nella forma dei `Field` del legacy. */
export const testo = (valore: unknown, max: number): string | null => {
  if (typeof valore !== "string") return null;
  const pulito = valore.trim();
  return pulito.length > 0 && pulito.length <= max ? pulito : null;
};
