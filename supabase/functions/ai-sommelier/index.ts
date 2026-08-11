// Fase 10b — la chat Sommelier, con storico e streaming.
//
// Porta di `backend/ai_routes.py:47-108`. È l'unica delle tre function che
// **scrive** e l'unica che fa streaming, ed è per questo che sta da sola
// (decisione 7.6).
//
// ---------------------------------------------------------------------------
// IL VINCOLO CHE NON VA SCOPERTO IN PRODUZIONE
// ---------------------------------------------------------------------------
//
// Una Edge Function che inoltra uno stream **può essere troncata** quando il
// worker viene ritirato: Supabase lo documenta come scenario noto («SSE or AI
// streams end before completion»). Se la `Response` viene restituita e l'isolate
// non ha più lavoro registrato, la piattaforma può ritirarlo mentre i chunk
// stanno ancora arrivando dal fornitore.
//
// Il rimedio è tenere l'isolate vivo per tutta la durata dell'inoltro con
// `EdgeRuntime.waitUntil()` sulla `pipeTo`, restituendo il lato leggibile.
// Senza, lo stream si interrompe **in modo intermittente e a metà risposta**,
// che è la classe di difetto peggiore: non fallisce nei test e non fallisce
// sempre.
//
// La decisione 7.7 ci aggiunge la metà che manca: `EdgeRuntime.waitUntil()`
// riduce la probabilità, non la azzera, quindi **anche il client deve trattare
// un troncamento parziale come caso atteso**. Uno stream che finisce senza
// l'evento `done` non è un errore da mostrare: è una risposta parziale da
// tenere. Il contratto lato client è `SommelierEsito.troncato`
// (`frontend-next/src/services/types.ts`).
//
// Conseguenza sulla persistenza, che è dove il troncamento fa male davvero: si
// salva **solo a stream concluso e non vuoto**, come nel legacy
// (`backend/ai_routes.py:92-101`). Una risposta troncata a metà non entra nello
// storico, perché diventerebbe il contesto delle battute successive.

import {
  AiProviderError,
  creaAiProvider,
  requestIdOpaco,
} from "../_shared/ai-provider.ts";
import { apriPorta, chiusa, json, leggiCorpo, testo } from "../_shared/ai-gate.ts";

// Identico a `SOMMELIER_SYSTEM` (`backend/ai_routes.py:18-23`). Le due
// istruzioni finali — non inventare produttori o annate, nessun consiglio
// medico, consumo responsabile — sono l'unico presidio degli invarianti AI
// scritti in `docs/SECURITY.md`, e non sono formule di cortesia.
const SYSTEM = "Sei Vinea Sommelier, un sommelier virtuale esperto che assiste appassionati " +
  "italiani nell'esplorazione del vino. Rispondi sempre in italiano con tono " +
  "cordiale, competente e sintetico (max 4 paragrafi brevi). Non inventare " +
  "produttori o annate. Non fornire consigli medici e ricorda il consumo responsabile.";

// `SOMMELIER_CONTEXT_MESSAGES`, `SOMMELIER_MAX_RESPONSE_CHARS`
// (`backend/.env.example:36-37`). Il tetto sui caratteri non è solo una difesa
// sul traffico: con la 7.2 = A è ciò che tiene la riga dentro il vincolo di
// lunghezza della colonna, quindi appartiene alla stessa migrazione.
const CONTESTO_MESSAGGI = 12;
const RISPOSTA_MAX_CHARS = 8000;
const MESSAGGIO_MAX_CHARS = 2000;

const SESSION_ID = /^[A-Za-z0-9_-]{4,64}$/;

type RigaContesto = { ruolo: "utente" | "sommelier"; contenuto: string };

/**
 * Il prompt con il contesto, nella forma esatta del legacy
 * (`backend/ai_routes.py:57-68`): la conversazione precedente entra come testo
 * marcato «solo contesto», non come messaggi di ruolo. È una scelta del legacy
 * e viene trasportata, non migliorata: cambiarla cambierebbe le risposte, e
 * questa è una migrazione.
 */
export const costruisciPrompt = (contesto: RigaContesto[], messaggio: string): string => {
  if (contesto.length === 0) return messaggio;
  const trascritto = contesto
    .map((riga) => `${riga.ruolo === "utente" ? "Utente" : "Sommelier"}: ${riga.contenuto.trim()}`)
    .join("\n");
  return "Conversazione precedente (solo contesto, non ripetere):\n" +
    `${trascritto}\n\nNuovo messaggio dell'utente:\n${messaggio}`;
};

const sse = (payload: Record<string, unknown>): string =>
  `data: ${JSON.stringify(payload)}\n\n`;

Deno.serve(async (request) => {
  const porta = await apriPorta(request, "ai:chat");
  if (chiusa(porta)) return porta.risposta;
  const { cors, supabase, userId } = porta;

  const corpo = await leggiCorpo(request);
  const sessionId = corpo ? testo(corpo.session_id, 64) : null;
  const messaggio = corpo ? testo(corpo.message, MESSAGGIO_MAX_CHARS) : null;
  if (!sessionId || !SESSION_ID.test(sessionId) || !messaggio) {
    return json({ error: "Sessione o messaggio non validi." }, 400, cors);
  }

  // Il contesto passa dalla porta concessa a `service_role`, non dalla vista:
  // con il client di servizio `auth.uid()` è nullo e la vista darebbe zero
  // righe, cioè una conversazione senza memoria che sembra funzionare.
  const { data: contestoGrezzo, error: contestoError } = await supabase.rpc(
    "sommelier_contesto_leggi",
    { p_owner_id: userId, p_session_id: sessionId, p_limite: CONTESTO_MESSAGGI },
  );
  if (contestoError) {
    console.error("[ai-sommelier] lettura contesto fallita", { code: contestoError.code });
    return json({ error: "Il Sommelier non è al momento disponibile." }, 503, cors);
  }
  const contesto = (contestoGrezzo ?? []) as RigaContesto[];

  let sorgente: ReadableStream<string>;
  try {
    sorgente = await creaAiProvider("chat").streamText({
      system: SYSTEM,
      prompt: costruisciPrompt(contesto, messaggio),
      requestId: requestIdOpaco("sommelier"),
    });
  } catch (errore) {
    // Prima che lo stream cominci l'errore è ancora uno status HTTP. Dopo, non
    // può esserlo più: diventa un evento dentro lo stream.
    if (errore instanceof AiProviderError) {
      return json({ error: "Il Sommelier non è al momento disponibile." }, 503, cors);
    }
    console.error("[ai-sommelier] apertura stream fallita");
    return json({ error: "Il Sommelier non è al momento disponibile." }, 503, cors);
  }

  const encoder = new TextEncoder();
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();

  const inoltra = async () => {
    const writer = writable.getWriter();
    const raccolti: string[] = [];
    let rimanenti = RISPOSTA_MAX_CHARS;
    try {
      const lettore = sorgente.getReader();
      while (true) {
        const { done, value } = await lettore.read();
        if (done) break;
        if (rimanenti <= 0) break;
        // Troncamento in uscita, come `remaining_chars`
        // (`backend/ai_routes.py:72`, `:79-87`): vale sui byte trasmessi e su
        // quelli salvati, non su uno solo dei due.
        const sicuro = value.slice(0, rimanenti);
        if (sicuro) {
          raccolti.push(sicuro);
          rimanenti -= sicuro.length;
          await writer.write(encoder.encode(sse({ delta: sicuro })));
        }
        if (sicuro.length < value.length) break;
      }

      const risposta = raccolti.join("").trim();
      if (risposta) {
        // Si salva solo qui: a stream concluso e non vuoto. Una risposta
        // interrotta a metà non entra nello storico, perché diventerebbe il
        // contesto delle battute successive.
        const { error } = await supabase.rpc("sommelier_scambio_registra", {
          p_owner_id: userId,
          p_session_id: sessionId,
          p_domanda: messaggio,
          p_risposta: risposta,
        });
        if (error) {
          // Il testo è già arrivato all'utente: qui non si può più cambiare la
          // risposta, si può solo non mentire sul fatto che non è stata
          // salvata. Resta nel log della function, come vuole la 7.5.
          console.error("[ai-sommelier] scambio non salvato", { code: error.code });
        }
      }
      await writer.write(encoder.encode(sse({ done: true })));
    } catch (errore) {
      // Evento generico dentro lo stream e nessun salvataggio, come
      // `backend/ai_routes.py:88-90`. Il messaggio del fornitore non esce.
      console.error("[ai-sommelier] stream interrotto", {
        tipo: errore instanceof Error ? errore.name : "sconosciuto",
      });
      try {
        await writer.write(
          encoder.encode(sse({ error: "Il Sommelier non è al momento disponibile." })),
        );
      } catch {
        // Il lato scrivente è già chiuso: non c'è nessuno da avvisare.
      }
    } finally {
      try {
        await writer.close();
      } catch {
        // Idem.
      }
    }
  };

  // Il punto: senza questo, la piattaforma può ritirare il worker appena la
  // `Response` è restituita, e i chunk ancora in arrivo dal fornitore vanno
  // persi a metà risposta.
  const attendi = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime?.waitUntil;
  const lavoro = inoltra();
  if (typeof attendi === "function") attendi(lavoro);

  return new Response(readable, {
    status: 200,
    headers: {
      ...cors,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      // Stesso header del legacy (`backend/ai_routes.py:107`): senza, un proxy
      // che bufferizza annulla il vantaggio dello streaming.
      "X-Accel-Buffering": "no",
    },
  });
});
