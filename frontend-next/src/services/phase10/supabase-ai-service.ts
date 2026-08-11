// Fase 10 — adapter reale di AiService.
//
// Tre percorsi diversi, e la differenza non e' stilistica:
//
//   * abbinamento e catalogazione passano da `functions.invoke`, come
//     `payments-checkout` (`src/services/phase7/payment-service.ts:8`);
//   * lo storico si legge da `my_sommelier_messages`, una vista a colonne
//     chiuse, e si cancella con una RPC — nessuna delle due tocca una function,
//     perche' non c'e' nessun fornitore da chiamare;
//   * la chat usa `fetch` diretta e non `functions.invoke`, perche' invoke
//     legge la risposta per intero prima di restituirla e uno stream letto per
//     intero non e' piu' uno stream.

import type { SupabaseClient } from "@supabase/supabase-js";
import { aiError, dividiEventiSse, messaggioDaStatus, noClient } from "@/services/phase10/shared";
import type {
  Abbinamento,
  AiService,
  CatalogazioneSuggerimento,
  SommelierEsito,
  SommelierMessaggio,
  SommelierRuolo,
} from "@/services/types";

// ---------------------------------------------------------------------------
// Mappatori — esportati perche' sono la parte che i test possono provare senza
// un client
// ---------------------------------------------------------------------------

type RispostaAbbinamento = {
  intro?: unknown;
  picks?: { wine_id?: unknown; reasoning?: unknown }[];
};

/**
 * Il JSON della function conserva `wine_id`, che e' il nome nel prompt di
 * sistema del legacy. Nel contratto TypeScript diventa `annuncioId`, perche'
 * con la decisione 7.8 identifica un annuncio di `public_listings` e non un
 * vino di un file statico: chiamarlo ancora `wineId` avrebbe nascosto proprio
 * la cosa che la decisione ha cambiato.
 */
export const mapAbbinamento = (grezzo: RispostaAbbinamento | null): Abbinamento | null => {
  if (!grezzo || !Array.isArray(grezzo.picks)) return null;
  const scelte = grezzo.picks
    .filter((pick) => typeof pick?.wine_id === "string" && pick.wine_id.length > 0)
    .map((pick) => ({
      annuncioId: String(pick.wine_id),
      motivazione: String(pick.reasoning ?? ""),
    }));
  return scelte.length > 0
    ? { intro: String(grezzo.intro ?? ""), scelte }
    : null;
};

type RispostaCatalogazione = Record<string, unknown>;

export const mapCatalogazione = (
  grezzo: RispostaCatalogazione | null,
): CatalogazioneSuggerimento | null => {
  if (!grezzo || typeof grezzo !== "object") return null;
  const stringa = (chiave: string) =>
    typeof grezzo[chiave] === "string" ? (grezzo[chiave] as string) : "";
  const annata = grezzo.annata;
  const confidence = typeof grezzo.confidence === "number" ? grezzo.confidence : 0;
  return {
    nome: stringa("nome"),
    produttore: stringa("produttore"),
    annata: typeof annata === "number" && Number.isInteger(annata) ? annata : null,
    denominazione: stringa("denominazione"),
    regione: stringa("regione"),
    tipologia: stringa("tipologia"),
    noteDegustazione: stringa("note_degustazione"),
    condizioniSuggerite: stringa("condizioni_suggerite"),
    // Difesa doppia rispetto alla function, che gia' vincola a [0,1]: qui non
    // costa niente e vale anche se un giorno risponde qualcos'altro.
    confidence: confidence >= 0 && confidence <= 1 ? confidence : 0,
  };
};

type RigaStorico = { ruolo?: unknown; contenuto?: unknown; created_at?: unknown };

export const mapStorico = (righe: RigaStorico[] | null): SommelierMessaggio[] =>
  (righe ?? [])
    .filter((riga) => riga.ruolo === "utente" || riga.ruolo === "sommelier")
    .map((riga) => ({
      ruolo: riga.ruolo as SommelierRuolo,
      contenuto: String(riga.contenuto ?? ""),
      createdAt: String(riga.created_at ?? ""),
    }));

// ---------------------------------------------------------------------------

const urlFunzione = (nome: string): string | null => {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  return base ? `${base.replace(/\/$/, "")}/functions/v1/${nome}` : null;
};

export const createSupabaseAiService = (client: SupabaseClient | null): AiService => ({
  abbinamento: async (query) => {
    if (!client) return noClient();
    const { data, error } = await client.functions.invoke("ai-pairing", {
      body: { query },
    });
    if (error) return aiError("ai-pairing", error);
    const mappato = mapAbbinamento(data as RispostaAbbinamento | null);
    return mappato
      ? { ok: true, data: mappato }
      : { ok: false, error: "Il servizio AI non ha proposto nessun abbinamento valido." };
  },

  catalogazione: async (input) => {
    if (!client) return noClient();
    if (!input.ocrText && !input.hint) {
      return { ok: false, error: "Fornire un testo dell'etichetta o un'indicazione." };
    }
    const { data, error } = await client.functions.invoke("ai-catalogo", {
      body: { ocr_text: input.ocrText ?? null, hint: input.hint ?? null },
    });
    if (error) return aiError("ai-catalogo", error);
    const mappato = mapCatalogazione(data as RispostaCatalogazione | null);
    return mappato
      ? { ok: true, data: mappato }
      : { ok: false, error: "Il servizio AI non ha restituito un suggerimento utilizzabile." };
  },

  sommelierStorico: async (sessionId) => {
    if (!client) return noClient();
    // La vista filtra gia' su `owner_id = auth.uid()` al suo interno: qui si
    // aggiunge la sola meta' che il client puo' fornire senza poterla falsare,
    // e mai `owner_id`, che non e' nemmeno fra le colonne esposte.
    // L'ordine e' `ordinale` e non `created_at`: le due righe di uno scambio
    // nascono nella stessa istruzione e condividono l'istante, quindi ordinare
    // per tempo puo' mostrare la risposta prima della domanda.
    const { data, error } = await client
      .from("my_sommelier_messages")
      .select("ruolo,contenuto,created_at,ordinale")
      .eq("session_id", sessionId)
      .order("ordinale", { ascending: true });
    return error
      ? aiError("my_sommelier_messages.select", error)
      : { ok: true, data: mapStorico(data as RigaStorico[] | null) };
  },

  sommelierCancella: async (sessionId) => {
    if (!client) return noClient();
    const { error } = await client.rpc("sommelier_storico_cancella", {
      p_session_id: sessionId,
    });
    return error
      ? aiError("sommelier_storico_cancella", error)
      : { ok: true, data: undefined };
  },

  sommelierChat: async (input, onDelta) => {
    if (!client) return noClient<SommelierEsito>();
    const url = urlFunzione("ai-sommelier");
    if (!url) return noClient<SommelierEsito>();

    const { data: sessione } = await client.auth.getSession();
    const token = sessione.session?.access_token;
    // 7.9: il pannello resta montato anche per gli anonimi, e chi non ha
    // sessione riceve un 401. Qui non si finge un errore diverso.
    if (!token) return { ok: false, error: "Sessione non valida: accedi per usare il Sommelier." };

    let risposta: Response;
    try {
      risposta = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ session_id: input.sessionId, message: input.messaggio }),
      });
    } catch {
      return { ok: false, error: "Il Sommelier non e al momento raggiungibile." };
    }

    if (!risposta.ok || !risposta.body) {
      let corpo: unknown = null;
      try {
        corpo = await risposta.json();
      } catch {
        // Nessun corpo: e' il caso del gateway, coperto da messaggioDaStatus.
      }
      console.error("[Phase10] ai-sommelier fallita", { status: risposta.status });
      return { ok: false, error: messaggioDaStatus(risposta.status, corpo) };
    }

    const lettore = risposta.body.pipeThrough(new TextDecoderStream()).getReader();
    let buffer = "";
    let testo = "";
    // Decisione 7.7: il troncamento e' un **caso atteso**, non un errore raro.
    // Resta vero finche' non arriva l'evento `done`, e un troncamento con del
    // testo gia' ricevuto e' un successo parziale — la risposta si tiene.
    let troncato = true;
    try {
      while (true) {
        const { done, value } = await lettore.read();
        if (done) break;
        buffer += value;
        const { eventi, resto } = dividiEventiSse(buffer);
        buffer = resto;
        for (const evento of eventi) {
          if ("delta" in evento) {
            testo += evento.delta;
            onDelta(evento.delta);
          } else if ("done" in evento) {
            troncato = false;
          } else if ("error" in evento) {
            // Errore del fornitore emesso dentro lo stream: la function non ha
            // salvato niente, e nemmeno noi teniamo un mezzo testo.
            return { ok: false, error: evento.error };
          }
        }
      }
    } catch {
      // La connessione e' caduta a meta': se del testo e' arrivato vale come
      // risposta troncata, altrimenti e' un fallimento.
      if (!testo) return { ok: false, error: "Il Sommelier si e interrotto prima di rispondere." };
    }

    return testo
      ? { ok: true, data: { testo, troncato } }
      : { ok: false, error: "Il Sommelier non ha prodotto nessuna risposta." };
  },
});
