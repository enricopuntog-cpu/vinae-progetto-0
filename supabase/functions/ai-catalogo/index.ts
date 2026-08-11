// Fase 10a — suggerimento di catalogazione da testo.
//
// Porta di `backend/ai_routes.py:251-279`, **senza differenze di
// comportamento**: stessi due campi in ingresso con gli stessi estremi, stesso
// prompt di sistema, stessi nove campi in uscita, stesso `confidence` in [0,1].
//
// È l'unica delle tre funzionalità migrate che non cambia niente, e va detto:
// l'abbinamento cambia da dove arrivano i candidati (7.8), la chat guadagna una
// tabella (7.2 = A), questa si sposta e basta.
//
// Il campo `ocr_text` esiste nel legacy ma **nessun chiamante di `frontend/` lo
// invia mai**: l'unico punto di chiamata manda solo `hint`
// (`frontend/src/hooks/useSellWizard.ts:66`). Viene portato lo stesso perché il
// contratto lo prevede e perché è l'ingresso su cui si innesterà l'autofill da
// foto della 7.3a — che è una funzionalità nuova, ammessa per eccezione, e
// **non appartiene a questo checkpoint**.

import {
  AiFormatError,
  AiProviderError,
  creaAiProvider,
  estraiJson,
  requestIdOpaco,
} from "../_shared/ai-provider.ts";
import { apriPorta, chiusa, json, leggiCorpo, testo } from "../_shared/ai-gate.ts";

// Identico a `LISTING_SYSTEM` (`backend/ai_routes.py:244-248`). L'ultima frase
// — «Non inventare dati non deducibili» — è l'unico presidio che impedisce a un
// suggerimento di catalogazione di diventare un'affermazione sul vino: non è
// una formula di cortesia e non va riscritta.
const SYSTEM = "Sei un catalogatore di vini italiano. Rispondi esclusivamente con JSON con i campi " +
  "nome, produttore, annata, denominazione, regione, tipologia, note_degustazione, " +
  "condizioni_suggerite e confidence. Non inventare dati non deducibili.";

// Estremi di `ListingRequest` (`backend/ai_routes.py:228-229`).
const OCR_MAX = 2000;
const HINT_MAX = 500;

export type Suggerimento = {
  nome: string;
  produttore: string;
  annata: number | null;
  denominazione: string;
  regione: string;
  tipologia: string;
  note_degustazione: string;
  condizioni_suggerite: string;
  confidence: number;
};

const stringa = (valore: unknown, max = 400): string =>
  typeof valore === "string" ? valore.trim().slice(0, max) : "";

/**
 * `annata` è l'unico campo numerico e l'unico che può restare vuoto: nel legacy
 * è `int | None` (`backend/ai_routes.py:235`). Un valore fuori da un intervallo
 * plausibile è un'invenzione del modello, non un'annata, e diventa `null`
 * invece di finire nel modulo del venditore.
 */
export const annataValida = (valore: unknown): number | null => {
  const numero = typeof valore === "number" ? valore : Number(valore);
  if (!Number.isInteger(numero) || numero < 1800 || numero > 2100) return null;
  return numero;
};

/**
 * `confidence` è vincolata a [0,1] da `Field(0.0, ge=0, le=1)`
 * (`backend/ai_routes.py:241`). Fuori intervallo o non numerica vale 0: un
 * suggerimento che non sa dire quanto è sicuro va trattato come non sicuro.
 */
export const confidenzaValida = (valore: unknown): number => {
  const numero = typeof valore === "number" ? valore : Number(valore);
  if (!Number.isFinite(numero) || numero < 0 || numero > 1) return 0;
  return numero;
};

export const suggerimentoDa = (parsed: Record<string, unknown>): Suggerimento => ({
  nome: stringa(parsed.nome, 200),
  produttore: stringa(parsed.produttore, 200),
  annata: annataValida(parsed.annata),
  denominazione: stringa(parsed.denominazione, 200),
  regione: stringa(parsed.regione, 120),
  tipologia: stringa(parsed.tipologia, 120),
  note_degustazione: stringa(parsed.note_degustazione, 1200),
  condizioni_suggerite: stringa(parsed.condizioni_suggerite, 600),
  confidence: confidenzaValida(parsed.confidence),
});

Deno.serve(async (request) => {
  const porta = await apriPorta(request, "ai:catalogo");
  if (chiusa(porta)) return porta.risposta;
  const { cors } = porta;

  const corpo = await leggiCorpo(request);
  const ocrText = corpo ? testo(corpo.ocr_text, OCR_MAX) : null;
  const hint = corpo ? testo(corpo.hint, HINT_MAX) : null;
  // Stessa condizione di `backend/ai_routes.py:258-259`: almeno uno dei due.
  if (!ocrText && !hint) {
    return json({ error: "Fornire 'ocr_text' o 'hint'." }, 400, cors);
  }

  const parti: string[] = [];
  if (ocrText) parti.push(`OCR etichetta:\n${ocrText}`);
  if (hint) parti.push(`Indicazione utente: ${hint}`);

  try {
    const grezzo = await creaAiProvider("catalogo").completeText({
      system: SYSTEM,
      prompt: parti.join("\n\n"),
      requestId: requestIdOpaco("catalogo"),
    });
    return json(suggerimentoDa(estraiJson(grezzo)), 200, cors);
  } catch (errore) {
    if (errore instanceof AiFormatError) {
      return json({ error: "Il servizio AI ha restituito un formato non valido." }, 502, cors);
    }
    if (errore instanceof AiProviderError) {
      return json({ error: "Il servizio AI non è al momento disponibile." }, 503, cors);
    }
    console.error("[ai-catalogo] errore non previsto");
    return json({ error: "Suggerimento non disponibile." }, 502, cors);
  }
});
