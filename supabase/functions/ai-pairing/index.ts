// Fase 10a — abbinamento cibo-vino.
//
// Porta di `backend/ai_routes.py:181-223` con **una differenza dichiarata**: il
// catalogo dei candidati non arriva più dal client.
//
// Decisione 7.8. Oggi `frontend/` manda fino a 60 vini scelti da sé, e quei
// vini non vengono dal database: `esplora.tsx` li prende da `@/data/wines`
// (`frontend/src/routes/esplora.tsx:14`), un file statico con diciotto voci
// dimostrative presente identico anche in `frontend-next/src/data/wines.ts`.
// Riprodurre il meccanismo avrebbe conservato la forma perdendo il significato:
// l'AI avrebbe continuato a ragionare su dati finti mentre il progetto ha un
// catalogo vero. Costa una query in più per chiamata, accettata dalla decisione.
//
// Tre conseguenze che non sono estetiche:
//  1. la dimensione del prompt, e quindi il costo, la decide il server e non il
//     browser — presupposto della 7.4;
//  2. la validazione dell'output diventa più forte, non più debole: un
//     `wine_id` proposto è dimostrabilmente un annuncio reale e pubblicato,
//     non un identificativo che il client aveva mandato a sé stesso;
//  3. la lettura passa da `public_listings`, la vista `security_invoker = off`
//     a colonne chiuse, come vogliono le regole di esposizione — non da una
//     policy sulla tabella base.

import { estraiJson } from "../_shared/ai-provider.ts";
import { ISTRUZIONE_DATI_NON_ATTENDIBILI, pulisciUscita, righeNonAttendibili } from "../_shared/ai-sicurezza.ts";
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

// Stesso tetto di `backend/ai_routes.py:148`: il prompt resta limitato anche
// quando il catalogo cresce.
const CATALOGO_MAX = 60;

// Identico a `PAIRING_SYSTEM` (`backend/ai_routes.py:161-165`). Il contratto
// verso il modello non cambia: cambia solo da dove arrivano i candidati.
const SYSTEM = "Sei un sommelier italiano. Rispondi esclusivamente con JSON valido: " +
  '{"intro":"...", "picks":[{"wine_id":"...", "reasoning":"..."}]}. ' +
  "Scegli esattamente 3 vini presenti nel catalogo, oppure tutti se il catalogo ne contiene meno." +
  ISTRUZIONE_DATI_NON_ATTENDIBILI;

type RigaCatalogo = {
  id: string;
  produttore: string | null;
  nome: string | null;
  annata: number | null;
  denominazione: string | null;
  regione: string | null;
  tipo: string | null;
};

/**
 * L'etichetta ricalca quella che `frontend/` costruiva nel browser
 * (`frontend/src/routes/esplora.tsx:102-105`): stessa forma, stessi campi,
 * risolta dove i dati sono veri.
 */
export const etichettaCatalogo = (riga: RigaCatalogo): string =>
  `${riga.produttore ?? ""} — ${riga.nome ?? ""} ${riga.annata ?? ""} ` +
  `(${riga.denominazione ?? ""}, ${riga.regione ?? ""}) — ${riga.tipo ?? ""}`
    .replace(/\s+/g, " ")
    .trim();

type Scelta = { wine_id: string; reasoning: string };

/**
 * Validazione dell'output contro il catalogo **letto dal server**. Porta la
 * logica di `backend/ai_routes.py:202-222`: identificativi sconosciuti e
 * duplicati cadono, e se non ne restano abbastanza è un 502 — il modello non ha
 * risposto alla domanda che gli è stata fatta.
 */
export const scelteValide = (
  parsed: Record<string, unknown>,
  idAmmessi: ReadonlySet<string>,
): Scelta[] | null => {
  const attese = Math.min(3, idAmmessi.size);
  const grezze = Array.isArray(parsed.picks) ? parsed.picks : [];
  const viste = new Set<string>();
  const scelte: Scelta[] = [];
  for (const grezza of grezze) {
    if (!grezza || typeof grezza !== "object" || Array.isArray(grezza)) continue;
    const candidata = grezza as Record<string, unknown>;
    const wineId = String(candidata.wine_id ?? "");
    if (!idAmmessi.has(wineId) || viste.has(wineId)) continue;
    viste.add(wineId);
    scelte.push({
      wine_id: wineId,
      reasoning: pulisciUscita(String(candidata.reasoning ?? ""), 400),
    });
    if (scelte.length === attese) break;
  }
  return scelte.length === attese ? scelte : null;
};

Deno.serve(async (request) => {
  const porta = await apriPorta(request, "ai:pairing");
  if (chiusa(porta)) return porta.risposta;
  const { cors, supabase, userId } = porta;

  const letto = await leggiCorpo(request, cors);
  if ("risposta" in letto) return letto.risposta;
  // `query` ha gli stessi estremi di `PairingRequest` (`backend/ai_routes.py:147`).
  const query = letto.corpo ? testo(letto.corpo.query, 400) : null;
  if (!query || query.length < 2) {
    return json({ error: "Indicare un piatto o un'occasione." }, 400, cors);
  }

  const ingresso = await apriIngresso(supabase, "ai:pairing", userId, cors, { liberi: [query], identita: [query] });
  if ("risposta" in ingresso) return ingresso.risposta;
  let riuscita = false;
  try {
    const { data: righe, error: catalogoError } = await supabase
      .from("public_listings")
      .select("id,produttore,nome,annata,denominazione,regione,tipo")
      .order("pubblicato_at", { ascending: false })
      .limit(CATALOGO_MAX);
    if (catalogoError) {
      console.error("[ai-pairing] lettura catalogo fallita", { code: catalogoError.code });
      return json({ error: "Abbinamento non disponibile." }, 503, cors);
    }
    const catalogo = (righe ?? []) as RigaCatalogo[];
    if (catalogo.length === 0) {
      // Non è un guasto: è un catalogo vuoto, e va detto come tale invece di
      // mandare al modello un prompt senza candidati.
      return json({ error: "Nessun annuncio pubblicato su cui costruire un abbinamento." }, 409, cors);
    }

    // WI-016: i testi degli annunci sono scritti dai venditori, quindi entrano come dati ripuliti e delimitati.
    const prompt = `Piatto o occasione: ${query}\n\nCatalogo:\n` +
      righeNonAttendibili("annunci del catalogo", catalogo.map((riga) => `- ${riga.id}: ${etichettaCatalogo(riga)}`));

    const chiamata = await chiamataGovernata({
      supabase,
      userId,
      scope: "ai:pairing",
      compito: "pairing",
      cors,
      ingresso,
      system: SYSTEM,
      prompt,
      nonDisponibile: "Il servizio AI non è al momento disponibile.",
      chiama: (provider, call) => provider.completeText(call),
    });
    if (!chiamata.ok) return chiamata.risposta;
    // Il fornitore ha risposto: un formato inutilizzabile non è un suo guasto.
    await registraEsitoFornitore(supabase, "ai:pairing", true);
    await registraConsuntivo(supabase, chiamata.richiestaId, "ok", chiamata.uso());

    let parsed: Record<string, unknown>;
    try {
      parsed = estraiJson(chiamata.valore);
    } catch {
      return json({ error: "Il servizio AI ha restituito un formato non valido." }, 502, cors);
    }
    const scelte = scelteValide(parsed, new Set(catalogo.map((riga) => riga.id)));
    if (!scelte) {
      return json({ error: "Il servizio AI non ha restituito il numero richiesto di vini validi." }, 502, cors);
    }
    riuscita = true;
    return json({ intro: pulisciUscita(String(parsed.intro ?? ""), 300), picks: scelte }, 200, cors);
  } finally {
    await ingresso.chiudi(riuscita);
  }
});
