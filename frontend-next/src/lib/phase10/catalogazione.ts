// Fase 10c — dal suggerimento di catalogazione ai campi del wizard.
//
// Porta di `applyAiSuggestion` (`frontend/src/hooks/useSellWizard.ts:77-91`),
// con **una differenza dichiarata** su `tipo`, spiegata sotto.

import type { CatalogazioneSuggerimento } from "@/services/types";

/** I campi del passo Identificazione che il suggerimento può riempire. */
export type CampiIdentificazione = {
  produttore: string;
  nome: string;
  annata: string;
  regione: string;
  tipo: string;
  storia: string;
  conservazione: string;
};

/**
 * I cinque valori della tendina Tipologia
 * (`frontend-next/src/app/vendi/page-client.tsx`, passo Identificazione), che
 * sono anche i cinque di `Wine["tipo"]` (`frontend-next/src/data/wines.ts:33`).
 */
export const TIPI_AMMESSI = ["Rosso", "Bianco", "Bollicine", "Rosato", "Dolce"] as const;

const tipoAmmesso = (valore: string): boolean =>
  (TIPI_AMMESSI as readonly string[]).includes(valore);

/**
 * Applica il suggerimento ai campi correnti: un campo vuoto nel suggerimento
 * non cancella quello che l'utente ha già scritto.
 *
 * DIVERGENZA DICHIARATA rispetto a `frontend/`, unica di questo file. Il
 * legacy assegna `tipo: aiSug.tipologia || s.tipo` senza guardare che valore
 * sia; lì la pubblicazione è un toast dimostrativo
 * (`frontend/src/hooks/useSellWizard.ts:100`, «Annuncio pubblicato! (demo)»),
 * quindi una tipologia inventata dal modello — «Rosso fermo», «Red» — al più
 * lascia la tendina vuota a schermo. Qui il wizard scrive davvero, e quel
 * valore arriverebbe a `bottiglia_crea` come `tipo`: si accetta solo se è uno
 * dei cinque, altrimenti resta quello scelto dall'utente. Non è un
 * miglioramento di prodotto, è la stessa scrittura resa possibile senza
 * introdurre un modo nuovo di fallire.
 *
 * `annata` segue invece il legacy alla lettera: la function la vincola già a
 * 1800–2100 o `null` (`supabase/functions/ai-catalogo/index.ts`), e un `null`
 * lascia il campo com'era.
 */
export const campiDaSuggerimento = (
  suggerimento: CatalogazioneSuggerimento,
  correnti: CampiIdentificazione,
): CampiIdentificazione => ({
  produttore: suggerimento.produttore || correnti.produttore,
  nome: suggerimento.nome || correnti.nome,
  annata: suggerimento.annata ? String(suggerimento.annata) : correnti.annata,
  regione: suggerimento.regione || correnti.regione,
  tipo: tipoAmmesso(suggerimento.tipologia) ? suggerimento.tipologia : correnti.tipo,
  storia: suggerimento.noteDegustazione || correnti.storia,
  conservazione: suggerimento.condizioniSuggerite || correnti.conservazione,
});

/** La confidenza in percentuale intera, come la mostra `frontend/`. */
export const confidenzaPercento = (confidence: number): number =>
  Math.round(Math.min(1, Math.max(0, confidence)) * 100);
