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
import { AiFormatError, AiProviderError, attendiAi, timeoutMs, creaAiProvider, requestIdOpaco, stimaTokenInput, type AiCall, type AiProvider, type AiUso } from "./ai-provider.ts";
import { impronta, rilevaDatiSensibili, rilevaIstruzioniSospette } from "./ai-sicurezza.ts";

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
// I tre valori sono stati fissati in sessione l'11 agosto 2026, dopo che la
// prima stesura li aveva messi tutti e tre a `10` copiando il modello:
//
// - `ai:chat` a **40/ora** regge circa tre conversazioni realistiche intere
//   (cinque-quindici battute l'una) invece di esaurirsi dentro la prima. È il
//   difetto che il valore precedente aveva: il legacy sta a 20 per 60 s
//   (`backend/.env.example:44-45`), e 10/ora non arrivava in fondo a uno scambio.
// - `ai:pairing` a **15/ora** perché durante una sessione di navigazione si
//   prova più di una combinazione.
// - `ai:catalogo` resta a **10/ora** perché è un'azione per annuncio, non per
//   sessione: chi ne pubblica dieci in un'ora sta facendo un'altra cosa.
//
// Restano vincolanti e non sono parametri di questo file: finestra oraria per
// tutti e tre e nessuna eccezione per `admin`.
//
// WI-010: la clausola della v0 «nessun tetto secondario nostro oltre al rate
// limit» è superata dal budget globale richiesto dal founder il 26 novembre 2026
// (vedi `prenotaBudget`). I valori del tetto non stanno qui e non hanno un
// default: finché non sono configurati nel database nessuna chiamata parte.

export const FINESTRA_SECONDI = 3600;

export const LIMITI: Record<AiScope, number> = {
  "ai:chat": 40,
  "ai:pairing": 15,
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

// ---------------------------------------------------------------------------
// WI-010 — budget globale e interruttore sui guasti del fornitore
// ---------------------------------------------------------------------------
// Si consuma SUBITO PRIMA della chiamata al fornitore, quindi dopo il limite per utente (un utente solo non può
// bruciare il tetto di tutti) e solo per richieste valide. Chiuso per difetto: budget non configurato, esaurito,
// interruttore aperto, RPC assente o risposta inattesa = nessuna chiamata. Il motivo preciso resta nel log del
// server: all utente basta sapere che le funzioni AI non sono disponibili per il budget.

//
// WI-015: la prenotazione conta anche la SPESA massima (modello e token), sotto lo stesso lock, quando il proprietario
// ha impostato un tetto monetario e una tariffa; il consuntivo la chiude con i token dichiarati dal fornitore. Le stime
// non sono fatture.

export type Prenotazione = { richiestaId: string } | { risposta: Response };

export const rifiutata = (p: Prenotazione): p is { risposta: Response } => "risposta" in p;

export const prenotaBudget = async (
  supabase: SupabaseClient,
  scope: AiScope,
  cors: HeadersInit,
  chiamata: { provider: string; modello: string; tokenInput: number; tokenOutputMax: number },
): Promise<Prenotazione> => {
  const { data, error } = await supabase.rpc("ai_budget_prenota", {
    p_scope: scope,
    p_provider: chiamata.provider,
    p_modello: chiamata.modello,
    p_token_input: chiamata.tokenInput,
    p_token_output_max: chiamata.tokenOutputMax,
  });
  const esito = (data ?? null) as { esito?: unknown; richiesta_id?: unknown } | null;
  if (!error && esito?.esito === "consentito" && typeof esito.richiesta_id === "string") {
    return { richiestaId: esito.richiesta_id };
  }
  console.error("[ai] budget non concesso", { scope, esito: error ? error.code : String(esito?.esito) });
  return {
    risposta: json(
      { error: "Le funzioni AI non sono disponibili in questo momento.", motivo: "budget" },
      503,
      { ...cors, "Retry-After": String(FINESTRA_SECONDI) },
    ),
  };
};

export type EsitoChiamata =
  | "ok"
  | "guasto_fornitore"
  | "errore_richiesta"
  | "interrotta_client"
  | "formato_non_valido"
  | "errore_applicativo";

/** Chiude la prenotazione una volta sola. Senza i token del fornitore resta contato il massimo prenotato. */
export const registraConsuntivo = async (
  supabase: SupabaseClient,
  richiestaId: string,
  esito: EsitoChiamata,
  uso: { input: number; output: number } | null = null,
): Promise<void> => {
  try {
    const { error } = await supabase.rpc("ai_budget_consuntivo", {
      p_richiesta: richiestaId,
      p_esito: esito,
      p_token_input: uso?.input ?? null,
      p_token_output: uso?.output ?? null,
    });
    if (error) console.error("[ai] consuntivo non registrato", { code: error.code });
  } catch {
    console.error("[ai] consuntivo non registrato");
  }
};

/** Alimenta l interruttore. Un errore qui non cambia la risposta all utente: resta nel log. */
export const registraEsitoFornitore = async (supabase: SupabaseClient, scope: AiScope, riuscita: boolean): Promise<void> => {
  try {
    const { error } = await supabase.rpc("ai_budget_esito", { p_scope: scope, p_riuscita: riuscita });
    if (error) console.error("[ai] esito del fornitore non registrato", { code: error.code });
  } catch {
    console.error("[ai] esito del fornitore non registrato");
  }
};

// ---------------------------------------------------------------------------
// WI-016 — corpo limitato, ingresso per identità e chiamata governata
// ---------------------------------------------------------------------------

/** Tetto del corpo: il campo più lungo ammesso (OCR, 2.000 caratteri) sta abbondantemente sotto. */
export const CORPO_MAX_BYTE = 32 * 1024;

const leggiEntro = async (request: Request, maxByte: number): Promise<string | null> => {
  if (Number(request.headers.get("content-length") ?? "0") > maxByte) return null;
  if (!request.body) return "";
  const lettore = request.body.getReader();
  const pezzi: Uint8Array[] = [];
  let totale = 0;
  while (true) {
    const { done, value } = await lettore.read();
    if (done) break;
    totale += value.byteLength;
    if (totale > maxByte) {
      await lettore.cancel().catch(() => {});
      return null;
    }
    pezzi.push(value);
  }
  const unito = new Uint8Array(totale);
  let posizione = 0;
  for (const p of pezzi) {
    unito.set(p, posizione);
    posizione += p.byteLength;
  }
  return new TextDecoder().decode(unito);
};

/**
 * Corpo della richiesta: un oggetto JSON entro il tetto di byte. La validazione dei campi appartiene a ogni function,
 * perché è lì che i vincoli del legacy vanno riprodotti uno per uno.
 */
export const leggiCorpo = async (
  request: Request,
  cors: HeadersInit,
): Promise<{ corpo: Record<string, unknown> | null } | { risposta: Response }> => {
  let grezzo: string | null;
  try {
    grezzo = await leggiEntro(request, CORPO_MAX_BYTE);
  } catch {
    return { corpo: null };
  }
  if (grezzo === null) return { risposta: json({ error: "Richiesta troppo grande." }, 413, cors) };
  try {
    const parsed = JSON.parse(grezzo);
    return { corpo: parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : null };
  } catch {
    return { corpo: null };
  }
};

const MESSAGGIO_SENSIBILI =
  "Togli dati personali o segreti (indirizzi di posta, numeri di telefono, carte, IBAN, codici fiscali, password o chiavi) e riprova.";

export type TipoSegnale = "dati_sensibili" | "istruzioni_sospette" | "output_scartato" | "input_eccessivo";

/** Segnale di sicurezza SENZA contenuto. Un errore qui non cambia la risposta all'utente. */
export const segnalaSicurezza = async (supabase: SupabaseClient, userId: string, scope: AiScope, tipo: TipoSegnale): Promise<void> => {
  try {
    const { error } = await supabase.rpc("ai_segnala", { p_user: userId, p_scope: scope, p_tipo: tipo });
    if (error) console.error("[ai] segnale di sicurezza non registrato", { code: error.code });
  } catch {
    console.error("[ai] segnale di sicurezza non registrato");
  }
};

export type Ingresso = {
  maxTentativi: number;
  modelloRiserva: string | null;
  maxInputCaratteri: number;
  /** Idempotente: la prima chiusura vince. Una richiesta non riuscita si può ripetere senza passare per replay. */
  chiudi: (riuscita: boolean) => Promise<void>;
};

const RIFIUTI_PORTA: Record<string, { status: number; error: string; retry?: number }> = {
  sospesa: { status: 503, error: "Questa funzione AI è sospesa." },
  richiesta_ripetuta: { status: 409, error: "Questa richiesta è già in corso: attendi la risposta." },
  concorrenza_utente: { status: 429, error: "Hai già richieste AI in corso: attendi che finiscano.", retry: 5 },
  concorrenza_globale: { status: 429, error: "Le funzioni AI sono molto richieste: riprova fra poco.", retry: 5 },
  quota_account_nuovo: { status: 429, error: "Limite temporaneo delle funzioni AI per i nuovi account raggiunto.", retry: 3600 },
  blocco_abusi: { status: 429, error: "Le funzioni AI sono temporaneamente limitate per questo account.", retry: 3600 },
};

/**
 * Ingresso per identità (dopo autenticazione e validazione, prima di budget e fornitore): dati sensibili rifiutati
 * subito, istruzioni sospette segnalate; doppi invii, concorrenza, quote e sospensioni li decide il database.
 * `liberi` sono i testi scritti dall'utente; `identita` entra solo come impronta.
 */
export const apriIngresso = async (
  supabase: SupabaseClient,
  scope: AiScope,
  userId: string,
  cors: HeadersInit,
  { liberi, identita }: { liberi: readonly string[]; identita: readonly string[] },
): Promise<Ingresso | { risposta: Response }> => {
  if (liberi.some((t) => rilevaDatiSensibili(t) !== null)) {
    await segnalaSicurezza(supabase, userId, scope, "dati_sensibili");
    return { risposta: json({ error: MESSAGGIO_SENSIBILI, motivo: "dati_sensibili" }, 400, cors) };
  }
  if (liberi.some(rilevaIstruzioniSospette)) await segnalaSicurezza(supabase, userId, scope, "istruzioni_sospette");

  const { data, error } = await supabase.rpc("ai_porta_apri", {
    p_user: userId,
    p_scope: scope,
    p_impronta: await impronta([scope, ...identita]),
  });
  const esito = (data ?? null) as {
    esito?: unknown;
    porta_id?: unknown;
    max_tentativi?: unknown;
    modello_riserva?: unknown;
    max_input_caratteri?: unknown;
  } | null;
  const portaId = esito?.porta_id;
  if (error || esito?.esito !== "consentito" || typeof portaId !== "string") {
    const nome = !error && typeof esito?.esito === "string" ? esito.esito : "";
    const rifiuto = RIFIUTI_PORTA[nome];
    if (!rifiuto) {
      console.error("[ai] ingresso non concesso", { scope, esito: error ? error.code : String(esito?.esito) });
      return { risposta: json({ error: "Funzioni AI non disponibili." }, 503, cors) };
    }
    return {
      risposta: json(
        { error: rifiuto.error, motivo: nome },
        rifiuto.status,
        rifiuto.retry ? { ...cors, "Retry-After": String(rifiuto.retry) } : cors,
      ),
    };
  }
  let chiusaGia = false;
  return {
    maxTentativi: esito.max_tentativi === 2 ? 2 : 1,
    modelloRiserva: typeof esito.modello_riserva === "string" ? esito.modello_riserva : null,
    maxInputCaratteri: typeof esito.max_input_caratteri === "number" ? esito.max_input_caratteri : 0,
    chiudi: async (riuscita: boolean) => {
      if (chiusaGia) return;
      chiusaGia = true;
      try {
        const { error: errore } = await supabase.rpc("ai_porta_chiudi", { p_porta: portaId, p_riuscita: riuscita });
        if (errore) console.error("[ai] ingresso non chiuso", { code: errore.code });
      } catch {
        console.error("[ai] ingresso non chiuso");
      }
    },
  };
};

export type Governata<T> =
  | { ok: true; valore: T; richiestaId: string; uso: () => AiUso | null; segnale: AbortSignal; termina: () => void }
  | { ok: false; risposta: Response };

type OpzioniGovernata<T> = {
  supabase: SupabaseClient;
  userId: string;
  scope: AiScope;
  compito: "chat" | "pairing" | "catalogo";
  cors: HeadersInit;
  ingresso: Ingresso;
  system: string;
  prompt: string;
  nonDisponibile: string;
  segnaleClient: AbortSignal;
  chiama: (provider: AiProvider, call: AiCall) => Promise<T>;
};

/**
 * La sola strada verso il fornitore. Tentativi: quelli autorizzati dal proprietario (di base uno) più al massimo UNA
 * riserva, entrambi solo dopo un guasto del fornitore; ogni tentativo prenota il proprio budget e un rifiuto ferma
 * tutto, quindi la riserva non può moltiplicare la spesa oltre i tetti. Un 4xx, un formato non valido o un errore
 * dell'applicazione non si ritentano. Il successo lo consuntiva il chiamante (la chat solo a stream concluso).
 */
export const chiamataGovernata = async <T>(o: OpzioniGovernata<T>): Promise<Governata<T>> => {
  const nonDisponibile = () => ({ ok: false as const, risposta: json({ error: o.nonDisponibile }, 503, o.cors) });
  if (o.system.length + o.prompt.length > o.ingresso.maxInputCaratteri) {
    await segnalaSicurezza(o.supabase, o.userId, o.scope, "input_eccessivo");
    return { ok: false, risposta: json({ error: "Richiesta troppo lunga per questa funzione." }, 413, o.cors) };
  }
  // Ricontrolla i messaggi effettivi dopo la composizione dei contesti e la minimizzazione.
  // Un record del database può contenere il dato: il rifiuto non penalizza l'utente.
  if (rilevaDatiSensibili(o.system) || rilevaDatiSensibili(o.prompt)) {
    return {
      ok: false,
      risposta: json({ error: "Il contesto contiene dati che non possono essere inviati al servizio AI." }, 422, o.cors),
    };
  }

  const scadenza = new AbortController();
  const timer = setTimeout(() => scadenza.abort(new DOMException("Scadenza AI", "TimeoutError")), timeoutMs());
  const termina = () => clearTimeout(timer);
  const segnale = AbortSignal.any([o.segnaleClient, scadenza.signal]);
  let trasferita = false;
  try {
    const tentativi: (string | undefined)[] = Array.from({ length: o.ingresso.maxTentativi }, () => undefined);
    if (o.ingresso.modelloRiserva) tentativi.push(o.ingresso.modelloRiserva);

    for (let n = 0; n < tentativi.length; n++) {
      if (segnale.aborted) return nonDisponibile();
      const provider = creaAiProvider(o.compito, tentativi[n]);
      const prenotazione = await prenotaBudget(o.supabase, o.scope, o.cors, {
        provider: provider.id,
        modello: provider.modello,
        tokenInput: stimaTokenInput(o.system, o.prompt),
        tokenOutputMax: provider.maxOutputTokens,
      });
      if (rifiutata(prenotazione)) return n === 0 ? { ok: false, risposta: prenotazione.risposta } : nonDisponibile();
      const { richiestaId } = prenotazione;
      let uso: AiUso | null = null;
      try {
        segnale.throwIfAborted();
        const valore = await attendiAi(o.chiama(provider, {
          system: o.system,
          prompt: o.prompt,
          segnale,
          requestId: requestIdOpaco(o.compito),
          onUso: (u) => {
            uso = u;
          },
        }), segnale);
        segnale.throwIfAborted();
        trasferita = true;
        return { ok: true, valore, richiestaId, uso: () => uso, segnale, termina };
      } catch (errore) {
        if (o.segnaleClient.aborted) {
          await registraConsuntivo(o.supabase, richiestaId, "interrotta_client", uso);
          return nonDisponibile();
        }
        if (segnale.aborted) {
          await registraConsuntivo(o.supabase, richiestaId, "guasto_fornitore", uso);
          await registraEsitoFornitore(o.supabase, o.scope, false);
          return nonDisponibile();
        }
        if (errore instanceof AiFormatError) {
          await registraConsuntivo(o.supabase, richiestaId, "formato_non_valido", uso);
          return { ok: false, risposta: json({ error: "Il servizio AI ha restituito un formato non valido." }, 502, o.cors) };
        }
        if (!(errore instanceof AiProviderError)) {
          // un errore nostro non dice nulla sulla salute del fornitore e non si ritenta
          await registraConsuntivo(o.supabase, richiestaId, "errore_applicativo", uso);
          console.error("[ai] errore dell'applicazione", { scope: o.scope, tipo: errore instanceof Error ? errore.name : "sconosciuto" });
          return nonDisponibile();
        }
        await registraConsuntivo(o.supabase, richiestaId, errore.guastoFornitore ? "guasto_fornitore" : "errore_richiesta", uso);
        if (!errore.guastoFornitore) return nonDisponibile();
        await registraEsitoFornitore(o.supabase, o.scope, false);
      }
    }
    return nonDisponibile();
  } finally {
    if (!trasferita) termina();
  }
};

/** Testo obbligatorio con lunghezza massima, nella forma dei `Field` del legacy. */
export const testo = (valore: unknown, max: number): string | null => {
  if (typeof valore !== "string") return null;
  const pulito = valore.trim();
  return pulito.length > 0 && pulito.length <= max ? pulito : null;
};
