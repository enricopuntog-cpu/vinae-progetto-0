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

import { estraiJson } from "../_shared/ai-provider.ts";
import { bloccoNonAttendibile, ISTRUZIONE_DATI_NON_ATTENDIBILI, pulisciUscita, togliRecapiti } from "../_shared/ai-sicurezza.ts";
import {
  apriIngresso,
  apriPorta,
  chiamataGovernata,
  chiusa,
  json,
  leggiCorpo,
  registraConsuntivo,
  registraEsitoFornitore,
  testo,
} from "../_shared/ai-gate.ts";

// Identico a `LISTING_SYSTEM` (`backend/ai_routes.py:244-248`). L'ultima frase
// — «Non inventare dati non deducibili» — è l'unico presidio che impedisce a un
// suggerimento di catalogazione di diventare un'affermazione sul vino: non è
// una formula di cortesia e non va riscritta.
const SYSTEM = "Sei un catalogatore di vini italiano. Rispondi esclusivamente con JSON con i campi " +
  "nome, produttore, annata, denominazione, regione, tipologia, note_degustazione, " +
  "condizioni_suggerite e confidence. Non inventare dati non deducibili." + ISTRUZIONE_DATI_NON_ATTENDIBILI;

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

// WI-016: i campi suggeriti perdono collegamenti, recapiti e segreti prima di tornare al venditore.
const stringa = (valore: unknown, max = 400): string => pulisciUscita(valore, max);

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
  const { cors, supabase, userId } = porta;

  const letto = await leggiCorpo(request, cors);
  if ("risposta" in letto) return letto.risposta;
  const ocrText = letto.corpo ? testo(letto.corpo.ocr_text, OCR_MAX) : null;
  const hint = letto.corpo ? testo(letto.corpo.hint, HINT_MAX) : null;
  // Stessa condizione di `backend/ai_routes.py:258-259`: almeno uno dei due.
  if (!ocrText && !hint) {
    return json({ error: "Fornire 'ocr_text' o 'hint'." }, 400, cors);
  }
  // WI-016: dall'etichetta si tolgono i recapiti del produttore; segreti, carte e codici restano un rifiuto.
  const ocr = ocrText ? togliRecapiti(ocrText) : null;

  const ingresso = await apriIngresso(supabase, "ai:catalogo", userId, cors, {
    liberi: [ocr ?? "", hint ?? ""],
    identita: [ocrText ?? "", hint ?? ""],
  });
  if ("risposta" in ingresso) return ingresso.risposta;
  let riuscita = false;
  try {
    const parti: string[] = [];
    if (ocr) parti.push(bloccoNonAttendibile("testo letto dall'etichetta", ocr, OCR_MAX));
    if (hint) parti.push(bloccoNonAttendibile("indicazione dell'utente", hint, HINT_MAX));

    const chiamata = await chiamataGovernata({
      supabase,
      userId,
      scope: "ai:catalogo",
      compito: "catalogo",
      cors,
      ingresso,
      system: SYSTEM,
      prompt: parti.join("\n\n"),
      nonDisponibile: "Il servizio AI non è al momento disponibile.",
      segnaleClient: request.signal,
      chiama: (provider, call) => provider.completeText(call),
    });
    if (!chiamata.ok) return chiamata.risposta;
    chiamata.termina();
    // Il fornitore ha risposto: anche un formato inutilizzabile non è un suo guasto.
    await registraEsitoFornitore(supabase, "ai:catalogo", true);
    let suggerimento: ReturnType<typeof suggerimentoDa>;
    try {
      suggerimento = suggerimentoDa(estraiJson(chiamata.valore));
    } catch {
      await registraConsuntivo(supabase, chiamata.richiestaId, "formato_non_valido", chiamata.uso());
      return json({ error: "Il servizio AI ha restituito un formato non valido." }, 502, cors);
    }
    await registraConsuntivo(supabase, chiamata.richiestaId, "ok", chiamata.uso());
    riuscita = true;
    return json(suggerimento, 200, cors);
  } finally {
    await ingresso.chiudi(riuscita);
  }
});
