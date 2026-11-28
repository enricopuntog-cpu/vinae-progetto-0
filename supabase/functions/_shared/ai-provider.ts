// Fase 10 — astrazione del fornitore AI per l'ambiente Edge.
//
// È il gemello Deno di `backend/ai_provider.py`, che la Fase 10 **non
// reimplementa** ma trasporta: stessa forma a due metodi (`completeText`,
// `streamText`), stesso fallimento chiuso quando la configurazione manca, e
// stessa regola per cui ogni eccezione del fornitore collassa in un errore
// generico. Il messaggio del fornitore non raggiunge mai il client: potrebbe
// contenere il prompt, un identificativo di organizzazione o una diagnostica
// che non è nostra da mostrare (decisione 7.5).
//
// La decisione 7.1 dice **un fornitore per compito, non uno solo**: questo file
// non decide quale sia: legge il nome del modello per compito e resta l'unico
// punto in cui compare un nome di fornitore. Sostituirlo è cambiare
// `creaAiProvider` e la lettura del suo segreto, non riscrivere le function —
// che è la ragione per cui il provider di prova (OpenAI) può essere sostituito
// senza refactoring quando le 5-6 conversazioni reali della 7.1 avranno
// risposto.

export class AiProviderError extends Error {
  /**
   * WI-015 (E-01): vero solo se l'errore dice qualcosa sulla salute del fornitore (rete, timeout, 408, 429, 5xx).
   * Un 4xx dovuto alla richiesta o a una configurazione mancante NON alimenta l'interruttore GLOBALE: altrimenti
   * richieste confezionate da un solo utente spegnerebbero l'AI a tutti.
   */
  readonly guastoFornitore: boolean;
  constructor(message = "Il provider AI non è al momento disponibile", guastoFornitore = true) {
    super(message);
    this.name = "AiProviderError";
    this.guastoFornitore = guastoFornitore;
  }
}

export const statoEGuasto = (status: number): boolean => status === 408 || status === 429 || status >= 500;

/** Il fornitore ha risposto, ma con qualcosa che non è utilizzabile. */
export class AiFormatError extends Error {
  constructor(message = "Il provider AI ha restituito un formato non valido") {
    super(message);
    this.name = "AiFormatError";
  }
}

export type AiCall = {
  system: string;
  prompt: string;
  segnale: AbortSignal;
  /**
   * Identificativo della richiesta inoltrato al fornitore. Non deve contenere
   * dati personali: nel legacy contiene l'uuid utente
   * (`backend/ai_routes.py:77`) ed è un debito registrato, non un modello da
   * riprodurre. Qui è opaco per costruzione — vedi `requestIdOpaco`.
   */
  requestId: string;
  /** WI-015: consumo di token dichiarato dal fornitore, quando c'è. Mai stimato qui. */
  onUso?: (uso: AiUso) => void;
};

export type AiUso = { input: number; output: number };

export interface AiProvider {
  readonly id: string;
  /** WI-015: modello e tetto di uscita, per prenotare il costo massimo prima della chiamata. */
  readonly modello: string;
  readonly maxOutputTokens: number;
  readonly maxInputTokens: number;
  completeText(call: AiCall): Promise<string>;
  streamText(call: AiCall): Promise<ReadableStream<string>>;
}

/**
 * Identificativo opaco: prefisso del compito più valore casuale. Chiude il
 * debito che il legacy porta — `sommelier:{user.id}:{session_id}` viaggia al
 * fornitore nel campo `user` — che con la 7.1 sarebbe peggiorato, perché con un
 * fornitore per compito lo stesso dato personale uscirebbe verso tre o quattro
 * terzi invece che verso uno.
 */
export const requestIdOpaco = (compito: string): string =>
  `${compito}:${crypto.randomUUID()}`;

/**
 * Fallisce chiuso, come `DisabledAIProvider` del legacy
 * (`backend/ai_provider.py:19-27`). È ciò che risponde quando la chiave non è
 * configurata, cioè lo stato in cui la fase viene distribuita finché la
 * decisione 7.11 non è onorata.
 */
export const creaDisabledProvider = (): AiProvider => ({
  id: "disabled",
  modello: "nessuno",
  maxOutputTokens: 0,
  maxInputTokens: 0,
  completeText: () => Promise.reject(new AiProviderError("Il servizio AI non è configurato", false)),
  streamText: () => Promise.reject(new AiProviderError("Il servizio AI non è configurato", false)),
});

/**
 * Timeout applicativo. La decisione 7.5 lo vincola al limite di durata proprio
 * della Edge Function e non oltre: la piattaforma chiude una richiesta ferma da
 * 150 s con un 504 di gateway, che non ha corpo, non porta il nostro messaggio
 * generico e non è distinguibile da un guasto nostro. Tenerlo un ordine di
 * grandezza sotto significa che il fallimento resta **nostro**, quindi
 * descrivibile.
 */
export const AI_TIMEOUT_MS_DEFAULT = 30_000;
const AI_TIMEOUT_MS_MAX = 120_000;

export const timeoutMs = (): number => {
  const grezzo = Number(Deno.env.get("AI_TIMEOUT_SECONDS") ?? "30");
  if (!Number.isFinite(grezzo) || grezzo <= 0) return AI_TIMEOUT_MS_DEFAULT;
  return Math.min(grezzo * 1000, AI_TIMEOUT_MS_MAX);
};

/** Interrompe anche attese locali il cui produttore non rispetta il segnale. */
export async function attendiAi<T>(attesa: Promise<T>, segnale: AbortSignal): Promise<T> {
  let annulla: () => void = () => {};
  const interruzione = new Promise<never>((_, rifiuta) => {
    annulla = () => rifiuta(segnale.reason);
    if (segnale.aborted) annulla();
    else segnale.addEventListener("abort", annulla, { once: true });
  });
  try {
    return await Promise.race([interruzione, attesa]);
  } finally {
    segnale.removeEventListener("abort", annulla);
  }
}

const RISPOSTA_MAX_BYTE = 512 * 1024;

function corpoLimitato(risposta: Response, segnale: AbortSignal): ReadableStream<Uint8Array> {
  if (!risposta.body) throw new AiFormatError();
  const lettore = risposta.body.getReader();
  let byte = 0;
  let chiuso = false;
  let annulla: () => void;
  const termina = (interrotto: boolean) => {
    if (chiuso) return;
    chiuso = true;
    segnale.removeEventListener("abort", annulla);
    if (interrotto) void lettore.cancel().catch(() => {});
    lettore.releaseLock();
  };
  return new ReadableStream({
    start(controllo) {
      annulla = () => {
        termina(true);
        controllo.error(segnale.reason);
      };
      if (segnale.aborted) annulla();
      else segnale.addEventListener("abort", annulla, { once: true });
    },
    async pull(controllo) {
      try {
        const { done, value } = await lettore.read();
        if (chiuso) return;
        if (done) {
          termina(false);
          controllo.close();
          return;
        }
        byte += value.byteLength;
        if (byte > RISPOSTA_MAX_BYTE) throw new AiFormatError();
        controllo.enqueue(value);
      } catch (errore) {
        if (chiuso) return;
        termina(true);
        controllo.error(errore);
      }
    },
    cancel() { termina(true); },
  });
}

type OpenAiOptions = {
  apiKey: string;
  model: string;
  maxOutputTokens: number;
  maxInputTokens: number;
};

const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

const corpoOpenAi = (call: AiCall, options: OpenAiOptions, stream: boolean) => ({
  model: options.model,
  messages: [
    { role: "system", content: call.system },
    { role: "user", content: call.prompt },
  ],
  max_completion_tokens: options.maxOutputTokens,
  user: call.requestId,
  ...(stream ? { stream: true, stream_options: { include_usage: true } } : {}),
});

/** Il consumo come lo dichiara il fornitore (`usage`), oppure nulla: un numero mancante non si inventa. */
export const leggiUsoOpenAi = (corpo: unknown): AiUso | null => {
  const uso = (corpo as { usage?: { prompt_tokens?: unknown; completion_tokens?: unknown } | null })?.usage;
  const input = uso?.prompt_tokens;
  const output = uso?.completion_tokens;
  return Number.isInteger(input) && Number.isInteger(output) && (input as number) >= 0 && (output as number) >= 0
    ? { input: input as number, output: output as number }
    : null;
};

type ChunkOpenAi = {
  model?: unknown;
  choices?: { delta?: { content?: string | null } }[];
};

const creaOpenAiProvider = (options: OpenAiOptions): AiProvider => {
  const chiama = async (call: AiCall, stream: boolean): Promise<Response> => {
    try {
      const response = await attendiAi(fetch(OPENAI_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${options.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(corpoOpenAi(call, options, stream)),
        signal: call.segnale,
      }), call.segnale);
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        // Il corpo dell'errore del fornitore non viene letto né propagato.
        console.error("[ai] provider non disponibile", { status: response.status });
        throw new AiProviderError(undefined, statoEGuasto(response.status));
      }
      return response;
    } catch (errore) {
      if (call.segnale.aborted || errore instanceof AiProviderError) throw errore;
      console.error("[ai] chiamata al provider fallita", {
        tipo: errore instanceof Error ? errore.name : "sconosciuto",
      });
      throw new AiProviderError();
    }
  };

  return {
    id: "openai",
    modello: options.model,
    maxOutputTokens: options.maxOutputTokens,
    maxInputTokens: options.maxInputTokens,
    completeText: async (call) => {
      const response = await chiama(call, false);
      let parsed: { model?: unknown; choices?: { message?: { content?: string | null } }[] };
      try {
        const testo = await attendiAi(new Response(corpoLimitato(response, call.segnale)).text(), call.segnale);
        call.segnale.throwIfAborted();
        parsed = JSON.parse(testo);
      } catch (errore) {
        if (call.segnale.aborted || errore instanceof AiFormatError) throw errore;
        if (errore instanceof SyntaxError) throw new AiFormatError();
        throw new AiProviderError();
      }
      if (parsed?.model !== options.model) throw new AiFormatError();
      const uso = leggiUsoOpenAi(parsed);
      if (uso) call.onUso?.(uso);
      return parsed.choices?.[0]?.message?.content ?? "";
    },
    streamText: async (call) => {
      const response = await chiama(call, true);
      let resto = "";
      let completato = false;
      const leggiRiga = (riga: string, controller: TransformStreamDefaultController<string>) => {
        if (riga.startsWith("data:") && riga.slice(5).trim() === "[DONE]") {
          completato = true;
          return;
        }
        if (completato || !riga.startsWith("data:")) return;
        const payload = riga.slice(5).trim();
        if (!payload) return;
        let chunk: ChunkOpenAi;
        try {
          chunk = JSON.parse(payload) as ChunkOpenAi;
        } catch {
          throw new AiFormatError();
        }
        if (chunk?.model !== options.model) throw new AiFormatError();
        const uso = leggiUsoOpenAi(chunk);
        if (uso) call.onUso?.(uso);
        const delta = chunk.choices?.[0]?.delta?.content;
        if (typeof delta === "string" && delta) controller.enqueue(delta);
      };
      const opzioni = { signal: call.segnale };
      return corpoLimitato(response, call.segnale)
        .pipeThrough(new TextDecoderStream(), opzioni)
        .pipeThrough(new TransformStream<string, string>({
          transform(chunk, controller) {
            resto += chunk;
            const righe = resto.split("\n");
            resto = righe.pop() ?? "";
            for (const riga of righe) leggiRiga(riga, controller);
          },
          flush(controller) {
            leggiRiga(resto, controller);
            if (!completato) throw new AiFormatError();
          },
        }), opzioni);
    },
  };
};

/**
 * Unico punto di scelta del fornitore, per compito. `compito` seleziona la
 * variabile del modello: la 7.1 vuole un modello per compito e non un modello
 * per progetto, quindi il nome è un parametro e non una costante.
 */
export const creaAiProvider = (compito: "chat" | "pairing" | "catalogo", modelloRiserva?: string): AiProvider => {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) return creaDisabledProvider();
  const modelloPerCompito = {
    chat: Deno.env.get("AI_MODEL_CHAT"),
    pairing: Deno.env.get("AI_MODEL_PAIRING"),
    catalogo: Deno.env.get("AI_MODEL_CATALOGO"),
  }[compito];
  // Solo la versione esplicita ha un contratto verificato. Non stima il prompt:
  // riserva l'intera finestra, incluso il framing. Un alias può cambiare contratto.
  // Finestra e output: developers.openai.com/api/docs/models/gpt-4.1-mini e /gpt-5.4-mini.
  const model = modelloRiserva ?? modelloPerCompito ?? Deno.env.get("AI_MODEL_DEFAULT");
  const maxOutputTokens = Number(Deno.env.get("AI_MAX_OUTPUT_TOKENS") ?? "800");
  if (!model || !Number.isInteger(maxOutputTokens) || maxOutputTokens <= 0) return creaDisabledProvider();
  // max_completion_tokens comprende anche eventuali token di ragionamento.
  switch (model) {
    case "gpt-4.1-mini-2025-04-14":
      if (maxOutputTokens <= 32_768) return creaOpenAiProvider({ apiKey, model, maxOutputTokens, maxInputTokens: 1_047_576 });
      break;
    case "gpt-5.4-mini-2026-03-17":
      if (maxOutputTokens <= 128_000) return creaOpenAiProvider({ apiKey, model, maxOutputTokens, maxInputTokens: 400_000 });
      break;
  }
  return creaDisabledProvider();
};

/**
 * Estrazione di un oggetto JSON da una risposta che potrebbe essere avvolta in
 * un blocco di codice. Porta identica `_extract_json` del legacy
 * (`backend/ai_routes.py:168-178`): un modello che risponde con ```json non ha
 * sbagliato abbastanza da meritare un 502.
 */
export const estraiJson = (grezzo: string): Record<string, unknown> => {
  let testo = grezzo.trim();
  if (testo.startsWith("```")) {
    testo = testo.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  }
  try {
    return JSON.parse(testo) as Record<string, unknown>;
  } catch {
    const match = testo.match(/\{[\s\S]*\}/);
    if (!match) throw new AiFormatError();
    try {
      return JSON.parse(match[0]) as Record<string, unknown>;
    } catch {
      throw new AiFormatError();
    }
  }
};
