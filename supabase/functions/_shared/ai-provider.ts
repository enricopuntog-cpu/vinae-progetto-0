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
  constructor(message = "Il provider AI non è al momento disponibile") {
    super(message);
    this.name = "AiProviderError";
  }
}

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
  /**
   * Identificativo della richiesta inoltrato al fornitore. Non deve contenere
   * dati personali: nel legacy contiene l'uuid utente
   * (`backend/ai_routes.py:77`) ed è un debito registrato, non un modello da
   * riprodurre. Qui è opaco per costruzione — vedi `requestIdOpaco`.
   */
  requestId: string;
};

export interface AiProvider {
  readonly id: string;
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
  completeText: () => Promise.reject(new AiProviderError("Il servizio AI non è configurato")),
  streamText: () => Promise.reject(new AiProviderError("Il servizio AI non è configurato")),
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

type OpenAiOptions = {
  apiKey: string;
  model: string;
  maxOutputTokens: number;
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
  ...(stream ? { stream: true } : {}),
});

/**
 * Ogni riga `data:` di uno stream OpenAI porta un oggetto con `choices[0].delta.content`.
 * Esportata per essere provata senza rete: è la parte che un cambio di
 * fornitore riscrive, quindi è quella che deve avere dei test propri.
 */
export const estraiDeltaOpenAi = (riga: string): string | null => {
  if (!riga.startsWith("data:")) return null;
  const payload = riga.slice(5).trim();
  if (!payload || payload === "[DONE]") return null;
  try {
    const parsed = JSON.parse(payload) as {
      choices?: { delta?: { content?: string | null } }[];
    };
    return parsed.choices?.[0]?.delta?.content ?? null;
  } catch {
    // Una riga malformata in mezzo a uno stream non è una ragione per
    // interrompere: si scarta e si prosegue.
    return null;
  }
};

const creaOpenAiProvider = (options: OpenAiOptions): AiProvider => {
  const chiama = async (call: AiCall, stream: boolean): Promise<Response> => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs());
    try {
      const response = await fetch(OPENAI_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${options.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(corpoOpenAi(call, options, stream)),
        signal: controller.signal,
      });
      if (!response.ok) {
        // Il corpo dell'errore del fornitore non viene letto né propagato.
        console.error("[ai] provider non disponibile", { status: response.status });
        throw new AiProviderError();
      }
      return response;
    } catch (errore) {
      if (errore instanceof AiProviderError) throw errore;
      console.error("[ai] chiamata al provider fallita", {
        tipo: errore instanceof Error ? errore.name : "sconosciuto",
      });
      throw new AiProviderError();
    } finally {
      clearTimeout(timer);
    }
  };

  return {
    id: "openai",
    completeText: async (call) => {
      const response = await chiama(call, false);
      let parsed: { choices?: { message?: { content?: string | null } }[] };
      try {
        parsed = await response.json();
      } catch {
        throw new AiFormatError();
      }
      return parsed.choices?.[0]?.message?.content ?? "";
    },
    streamText: async (call) => {
      const response = await chiama(call, true);
      if (!response.body) throw new AiProviderError();
      let resto = "";
      return response.body
        .pipeThrough(new TextDecoderStream())
        .pipeThrough(
          new TransformStream<string, string>({
            transform: (chunk, controller) => {
              resto += chunk;
              const righe = resto.split("\n");
              resto = righe.pop() ?? "";
              for (const riga of righe) {
                const delta = estraiDeltaOpenAi(riga);
                if (delta) controller.enqueue(delta);
              }
            },
            flush: (controller) => {
              const delta = estraiDeltaOpenAi(resto);
              if (delta) controller.enqueue(delta);
            },
          }),
        );
    },
  };
};

/**
 * Unico punto di scelta del fornitore, per compito. `compito` seleziona la
 * variabile del modello: la 7.1 vuole un modello per compito e non un modello
 * per progetto, quindi il nome è un parametro e non una costante.
 */
export const creaAiProvider = (compito: "chat" | "pairing" | "catalogo"): AiProvider => {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) return creaDisabledProvider();
  const modelloPerCompito = {
    chat: Deno.env.get("AI_MODEL_CHAT"),
    pairing: Deno.env.get("AI_MODEL_PAIRING"),
    catalogo: Deno.env.get("AI_MODEL_CATALOGO"),
  }[compito];
  return creaOpenAiProvider({
    apiKey,
    model: modelloPerCompito ?? Deno.env.get("AI_MODEL_DEFAULT") ?? "gpt-4.1-mini",
    maxOutputTokens: Number(Deno.env.get("AI_MAX_OUTPUT_TOKENS") ?? "800"),
  });
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
