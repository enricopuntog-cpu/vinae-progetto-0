export type QuestionnaireAnswer = string | string[] | Record<string, string | string[]>;

export type QuestionnaireState = {
  session_id: string;
  participant_code: string;
  pre_finished_at: string | null;
  post_finished_at: string | null;
  validation_completed_at: string | null;
  buyer_completed: boolean;
  seller_completed: boolean;
  core_completed: boolean;
  answers: Record<string, QuestionnaireAnswer | null>;
};

type Option = readonly [code: string, label: string];
export type Question = {
  number: number;
  title: string;
  kind: "single" | "multi" | "text";
  options?: readonly Option[];
  maximum?: number;
  condition?: { code: string; label: string; field: string; optional?: boolean };
  secondCondition?: { label: string; field: string };
};

export const QUESTIONS: readonly Question[] = [
  { number: 1, title: "Fascia d'età", kind: "single", options: [["18_24", "18-24"], ["25_34", "25-34"], ["35_44", "35-44"], ["45_54", "45-54"], ["55_64", "55-64"], ["65_plus", "65+"]] },
  { number: 2, title: "Qual è il tuo rapporto con il vino?", kind: "single", options: [["occasional", "Consumatore occasionale"], ["regular", "Consumatore abituale"], ["enthusiast", "Appassionato"], ["collector", "Collezionista"], ["industry_professional", "Professionista del settore"], ["other", "Altro"]], condition: { code: "other", label: "Specifica, se vuoi", field: "other", optional: true } },
  { number: 3, title: "Con quale frequenza acquisti vino?", kind: "single", options: [["under_month", "Meno di 1 volta al mese"], ["one_two_month", "1-2 volte al mese"], ["three_four_month", "3-4 volte al mese"], ["multiple_week", "Più volte a settimana"]] },
  { number: 4, title: "Quanto spendi mediamente per acquistare una bottiglia?", kind: "single", options: [["under_10", "Meno di 10 €"], ["10_20", "10-20 €"], ["20_40", "20-40 €"], ["40_80", "40-80 €"], ["80_150", "80-150 €"], ["over_150", "Oltre 150 €"]] },
  { number: 5, title: "Negli ultimi 12 mesi dove hai acquistato vino?", kind: "multi", options: [["supermarket", "Supermercato"], ["wine_shop", "Enoteca"], ["producer", "Produttore"], ["specialist_ecommerce", "Ecommerce specializzato"], ["large_ecommerce", "Amazon / grandi ecommerce"], ["auction", "Aste"], ["acquaintances", "Amici / conoscenti"], ["unknown_private", "Privati non conosciuti"], ["social", "Social / gruppi / forum"], ["other", "Altro"]], condition: { code: "other", label: "Dove altro?", field: "other" } },
  { number: 6, title: "Hai mai acquistato una bottiglia di vino da un privato?", kind: "single", options: [["yes", "Sì"], ["no", "No"]], condition: { code: "yes", label: "Dove?", field: "where" }, secondCondition: { label: "Perché hai scelto di comprarla da un privato?", field: "why" } },
  { number: 7, title: "Cosa ti preoccuperebbe maggiormente acquistando vino da una persona che non conosci?", kind: "multi", maximum: 3, options: [["authenticity", "Autenticità"], ["storage", "Conservazione"], ["bottle_condition", "Condizioni bottiglia"], ["seller_reliability", "Affidabilità venditore"], ["payment", "Pagamento"], ["shipping", "Spedizione"], ["transport_damage", "Danni durante il trasporto"], ["price", "Prezzo"], ["claims", "Reclami / assistenza"], ["never_buy", "Non comprerei mai"]] },
  { number: 8, title: "Cosa dovrebbe offrirti una piattaforma per farti sentire sufficientemente sicuro?", kind: "text" },
  { number: 9, title: "Hai oggi bottiglie che probabilmente non berrai o che preferiresti vendere o scambiare?", kind: "single", options: [["none", "Nessuna"], ["one_five", "1-5"], ["six_twenty", "6-20"], ["twentyone_fifty", "21-50"], ["over_fifty", "Più di 50"]] },
  { number: 10, title: "Ti è mai capitato di avere bottiglie che non volevi più tenere?", kind: "single", options: [["yes", "Sì"], ["no", "No"]], condition: { code: "yes", label: "Cosa ne hai fatto?", field: "actions" } },
  { number: 11, title: "Hai mai venduto una bottiglia di vino?", kind: "single", options: [["never", "Mai"], ["once", "Una volta"], ["sometimes", "Qualche volta"], ["regularly", "Regolarmente"]], condition: { code: "once", label: "Dove?", field: "where" }, secondCondition: { label: "Difficoltà principale", field: "main_difficulty" } },
  { number: 12, title: "Per una bottiglia da circa 50 €, quale costo massimo di spedizione considereresti accettabile?", kind: "single", options: [["five_or_less", "5 € o meno"], ["six_nine", "6-9 €"], ["ten_twelve", "10-12 €"], ["thirteen_fifteen", "13-15 €"], ["over_fifteen", "Oltre 15 €"], ["would_not_buy", "Non acquisterei"]] },
  { number: 13, title: "Per una bottiglia da circa 150 €, quale costo massimo di spedizione considereresti accettabile?", kind: "single", options: [["five_or_less", "5 € o meno"], ["six_nine", "6-9 €"], ["ten_twelve", "10-12 €"], ["thirteen_fifteen", "13-15 €"], ["sixteen_twenty", "16-20 €"], ["over_twenty", "Oltre 20 €"], ["would_not_buy", "Non acquisterei"]] },
  { number: 14, title: "Qual è stata la prima cosa che hai avuto voglia di fare?", kind: "single", options: [["search_bottle", "Cercare una bottiglia"], ["buy", "Comprare"], ["sell", "Mettere in vendita una bottiglia"], ["clubs", "Guardare i Club / community"], ["explore", "Esplorare senza fare altro"], ["none", "Nulla in particolare"]] },
  { number: 15, title: "Hai trovato almeno una bottiglia che avresti seriamente considerato di acquistare?", kind: "single", options: [["yes", "Sì"], ["no", "No"]], condition: { code: "no", label: "Perché?", field: "why_not" } },
  { number: 16, title: "Se Vinea fosse già operativa oggi, avresti una bottiglia che potresti realmente mettere in vendita?", kind: "single", options: [["yes", "Sì"], ["maybe", "Forse"], ["no", "No"]] },
  { number: 17, title: "Cosa ti frenerebbe maggiormente dall'utilizzare Vinea?", kind: "text" },
  { number: 18, title: "Qual è la cosa più importante che manca o dovrebbe essere migliorata?", kind: "text" },
  { number: 19, title: "Quali servizi sarebbero più importanti per te?", kind: "multi", maximum: 2, options: [["protected_payment", "Pagamento protetto"], ["user_verification", "Verifica utenti"], ["authenticity_guarantee", "Garanzia autenticità"], ["reviews", "Recensioni"], ["insured_shipping", "Spedizione assicurata"], ["support", "Assistenza / reclami"], ["price_valuation", "Valutazione prezzo"], ["community", "Community / Club"]] },
  { number: 20, title: "Se Vinea aprisse oggi, quale sarebbe probabilmente il tuo primo utilizzo?", kind: "single", options: [["buy", "Comprare"], ["sell", "Vendere"], ["both", "Entrambi"], ["community_only", "Solo community / Club"], ["none", "Nessuno"]] },
];

export const Q10_ACTIONS: readonly Option[] = [["drank", "Bevute"], ["gifted", "Regalate"], ["sold", "Vendute"], ["traded", "Scambiate"], ["still_in_cellar", "Ancora in cantina"], ["other", "Altro"]];
export const questionKey = (number: number) => `q${String(number).padStart(2, "0")}`;

export type QuestionnaireStage = "pre-questionnaire" | "hub" | "post-questionnaire" | "complete";

// Lifecycle LANDING → PRE → CORE → POST → GRAZIE, derivato soltanto dallo
// stato server: un resume riprende sempre dalla fase ancora aperta.
export function questionnaireStage(state: QuestionnaireState): QuestionnaireStage {
  if (!state.pre_finished_at) return "pre-questionnaire";
  if (!state.core_completed) return "hub";
  if (!state.post_finished_at) return "post-questionnaire";
  return "complete";
}

export function firstIncomplete(answers: QuestionnaireState["answers"], from: number, to: number): number | null {
  for (let number = from; number <= to; number++) {
    if (answers[questionKey(number)] === null || answers[questionKey(number)] === undefined) return number;
  }
  return null;
}

export function answerValid(question: Question, answer: QuestionnaireAnswer | null): boolean {
  if (question.kind === "text") return typeof answer === "string" && answer.trim().length > 0 && answer.length <= 1000;
  const object = answer && typeof answer === "object" && !Array.isArray(answer) ? answer : null;
  const choice = object?.choice ?? answer;
  if (question.kind === "multi") {
    const values = Array.isArray(answer) ? answer : question.number === 5 ? object?.choices : null;
    if (!Array.isArray(values) || values.length === 0 || (question.maximum && values.length > question.maximum) ||
        new Set(values).size !== values.length || !values.every((value) => question.options?.some(([code]) => code === value))) return false;
    return !values.includes("other") || (typeof object?.other === "string" && object.other.trim().length > 0 && object.other.length <= 500);
  }
  if (typeof choice !== "string" || !question.options?.some(([code]) => code === choice)) return false;
  if (question.number === 10 && choice === "yes") {
    const actions = object?.actions;
    if (!Array.isArray(actions) || actions.length === 0 || new Set(actions).size !== actions.length ||
        !actions.every((value) => Q10_ACTIONS.some(([code]) => code === value))) return false;
    if (actions.includes("other") && (typeof object?.other !== "string" || !object.other.trim() || object.other.length > 500)) return false;
  }
  return true;
}
