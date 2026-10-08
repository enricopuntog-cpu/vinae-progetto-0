import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createMarketValidationQuestionnaireService } from "@/services/market-validation-questionnaire-service";
import {
  NEW_TESTER_LABEL,
  QUESTIONS,
  answerValid,
  questionnaireStage,
  type QuestionnaireState,
} from "./questionnaire";
import {
  QV2_SESSION_STORAGE_KEY,
  clearMarketValidationSession,
  readMarketValidationSession,
  writeMarketValidationSession,
} from "./persistence";
import {
  QV2_CSV_HEADERS,
  buildQv2ParticipantsCsv,
  decodeAnswer,
  parseQv2AdminParticipant,
  parseQv2Answers,
} from "./questionnaire-admin";

// Allineamento finale del questionario QV2 al requisito approvato: opzione
// «Altro» con specifica per Q7 e Q19, copy di Q12/Q13, GRAZIE persistente e
// nuovo tester solo su comando esplicito.

const root = resolve(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");
const question = (number: number) => QUESTIONS[number - 1];
const labels = (number: number) => question(number).options?.map(([, label]) => label);
const codes = (number: number) => question(number).options?.map(([code]) => code);

describe("QV2 finale: Q7 con «Altro»", () => {
  it("ha titolo, opzioni approvate e la specifica «Specifica»", () => {
    expect(question(7).title).toBe("Cosa ti preoccuperebbe maggiormente acquistando vino da una persona che non conosci?");
    expect(labels(7)).toEqual([
      "Autenticità della bottiglia",
      "Come è stata conservata",
      "Condizioni della bottiglia",
      "Affidabilità del venditore",
      "Pagamento",
      "Spedizione",
      "Possibilità che arrivi danneggiata",
      "Prezzo",
      "Difficoltà nel fare un reclamo",
      "Non comprerei mai vino da un privato",
      "Altro",
    ]);
    expect(question(7).maximum).toBe(3);
    expect(question(7).condition).toEqual({ code: "other", label: "Specifica", field: "other" });
  });

  it("«Altro» conta nel massimo di 3 e richiede la specifica", () => {
    expect(answerValid(question(7), { choices: ["authenticity", "price", "other"], other: "Annata" })).toBeTrue();
    expect(answerValid(question(7), { choices: ["authenticity", "price", "payment", "other"], other: "Annata" })).toBeFalse();
    expect(answerValid(question(7), { choices: ["other"] })).toBeFalse();
    expect(answerValid(question(7), { choices: ["other"], other: "   " })).toBeFalse();
    expect(answerValid(question(7), { choices: ["other"], other: "x".repeat(501) })).toBeFalse();
    expect(answerValid(question(7), ["other"])).toBeFalse();
  });

  it("senza «Altro» la specifica non è ammessa e il formato oggetto o array resta valido", () => {
    expect(answerValid(question(7), { choices: ["price"], other: "Orfano" })).toBeFalse();
    expect(answerValid(question(7), { choices: ["price"] })).toBeTrue();
    expect(answerValid(question(7), ["price", "storage"])).toBeTrue();
  });
});

describe("QV2 finale: Q19 con «Altro»", () => {
  it("ha titolo, opzioni approvate e massimo 2", () => {
    expect(question(19).title).toBe("Quale servizio sarebbe più importante per te?");
    expect(labels(19)).toEqual([
      "Pagamento protetto",
      "Verifica utenti / venditori",
      "Garanzia autenticità",
      "Sistema recensioni",
      "Spedizione assicurata",
      "Assistenza in caso di problemi",
      "Valutazione del prezzo della bottiglia",
      "Community / Club",
      "Altro",
    ]);
    expect(question(19).maximum).toBe(2);
    expect(question(19).condition?.label).toBe("Specifica");
  });

  it("«Altro» conta nel massimo di 2 e richiede la specifica solo se scelto", () => {
    expect(answerValid(question(19), { choices: ["protected_payment", "other"], other: "Ritiro in cantina" })).toBeTrue();
    expect(answerValid(question(19), { choices: ["protected_payment", "reviews", "other"], other: "Troppo" })).toBeFalse();
    expect(answerValid(question(19), { choices: ["protected_payment", "other"] })).toBeFalse();
    expect(answerValid(question(19), { choices: ["reviews"], other: "Orfano" })).toBeFalse();
    expect(answerValid(question(19), { choices: ["reviews", "support"] })).toBeTrue();
  });
});

describe("QV2 finale: copy Q12/Q13 con codici invariati", () => {
  it("Q12 usa la nuova domanda e «A quel prezzo preferirei non acquistare»", () => {
    expect(question(12).title).toBe("Per una bottiglia del valore di circa 50 €, quale costo massimo di spedizione considereresti accettabile?");
    expect(labels(12)).toEqual(["5 € o meno", "6-9 €", "10-12 €", "13-15 €", "Oltre 15 €", "A quel prezzo preferirei non acquistare"]);
    expect(codes(12)).toEqual(["five_or_less", "six_nine", "ten_twelve", "thirteen_fifteen", "over_fifteen", "would_not_buy"]);
  });

  it("Q13 usa la nuova domanda e «Non acquisterei comunque da un privato»", () => {
    expect(question(13).title).toBe("Se invece la bottiglia valesse circa 150 €, quale costo massimo di spedizione considereresti accettabile?");
    expect(labels(13)).toEqual(["5 € o meno", "6-9 €", "10-12 €", "13-15 €", "16-20 €", "Oltre 20 €", "Non acquisterei comunque da un privato"]);
    expect(codes(13)).toEqual(["five_or_less", "six_nine", "ten_twelve", "thirteen_fifteen", "sixteen_twenty", "over_twenty", "would_not_buy"]);
  });

  it("allinea le micro-differenze di copy senza cambiare i codici", () => {
    expect(labels(3)?.[0]).toBe("Meno di una volta al mese");
    expect(labels(5)).toContain("Direttamente dal produttore");
    expect(labels(5)).toContain("Privati che non conoscevo personalmente");
    expect(question(9).title).toBe("Hai attualmente bottiglie che probabilmente non berrai o che preferiresti vendere/scambiare?");
    expect(question(11).secondCondition?.label).toBe("Qual è stata la difficoltà principale?");
    expect(question(17).title).toBe("Qual è la cosa che ti frenerebbe maggiormente dall'utilizzare Vinea?");
    expect(question(18).title).toBe("Qual è la cosa più importante che secondo te manca o dovrebbe essere migliorata?");
    expect(question(20).title).toBe("Se Vinea aprisse al pubblico, quale sarebbe probabilmente il tuo primo utilizzo?");
    expect(codes(20)).toEqual(["buy", "sell", "both", "community_only", "none"]);
  });

  it("il feedback finale resta facoltativo e non diventa Q21", () => {
    expect(QUESTIONS).toHaveLength(20);
    const flow = read("frontend-next/src/app/beta-test/_components/QuestionnaireFlow.tsx");
    expect(flow).toInclude("Una cosa che vorresti dirci su Vinea (facoltativo)");
  });
});

describe("QV2 finale: risposte Q7/Q19 lette dal server", () => {
  const SESSION = "12dc0000-0000-4000-8000-000000000101";
  const CAPABILITY = "12dc0000-0000-4000-8000-0000000000c1";
  const fake = (answers: Record<string, unknown>) => ({
    rpc: async () => ({
      data: {
        session_id: SESSION,
        participant_code: "V017",
        pre_finished_at: "2026-10-08T10:00:00Z",
        post_finished_at: null,
        validation_completed_at: null,
        buyer_completed: false,
        seller_completed: false,
        core_completed: false,
        answers,
      },
      error: null,
    }),
  }) as unknown as SupabaseClient;

  it("ricompone {choices, other} come il form li invia, così il resume li ripropone", async () => {
    const service = createMarketValidationQuestionnaireService(fake({
      q07: ["price", "other"], q07_other: "Annata", q19: ["reviews", "other"], q19_other: "Ritiro",
    }));
    const result = await service.read(SESSION, CAPABILITY);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.data.state.answers.q07).toEqual({ choices: ["price", "other"], other: "Annata" });
    expect(result.data.state.answers.q19).toEqual({ choices: ["reviews", "other"], other: "Ritiro" });
    expect(answerValid(question(7), result.data.state.answers.q07 ?? null)).toBeTrue();
  });

  it("senza specifica restituisce solo le scelte", async () => {
    const service = createMarketValidationQuestionnaireService(fake({ q07: ["price"], q07_other: null, q19: null }));
    const result = await service.read(SESSION, CAPABILITY);
    expect(result.ok && result.data.state.answers.q07).toEqual({ choices: ["price"] });
    expect(result.ok && result.data.state.answers.q19).toBeNull();
  });
});

describe("QV2 finale: GRAZIE persistente e nuovo tester esplicito", () => {
  const memory = () => {
    const data = new Map<string, string>();
    return {
      getItem: (key: string) => data.get(key) ?? null,
      setItem: (key: string, value: string) => void data.set(key, value),
      removeItem: (key: string) => void data.delete(key),
      data,
    };
  };
  const session = (participantCode: "V017" | "V018", capability: string) => ({
    sessionId: "12dc0000-0000-4000-8000-000000000101",
    participantCode,
    capability,
    startedAt: "2026-10-08T10:00:00Z",
    resumed: false,
  });

  it("la sessione QV2 vive in una chiave propria, separata dalla capability MV1", () => {
    const storage = memory();
    writeMarketValidationSession(storage, session("V017", "12dc0000-0000-4000-8000-0000000000c1"));
    // Una capability della guida legacy non viene ripresa dal questionario.
    expect(readMarketValidationSession(storage, QV2_SESSION_STORAGE_KEY)).toBeNull();
    writeMarketValidationSession(storage, session("V018", "12dc0000-0000-4000-8000-0000000000c2"), QV2_SESSION_STORAGE_KEY);
    expect(readMarketValidationSession(storage, QV2_SESSION_STORAGE_KEY)?.participantCode).toBe("V018");
    expect(readMarketValidationSession(storage)?.participantCode).toBe("V017");
  });

  it("il test concluso resta lo stesso codice finché non si sceglie un nuovo tester", () => {
    const storage = memory();
    writeMarketValidationSession(storage, session("V017", "12dc0000-0000-4000-8000-0000000000c1"), QV2_SESSION_STORAGE_KEY);
    const completed: QuestionnaireState = {
      session_id: "12dc0000-0000-4000-8000-000000000101",
      participant_code: "V017",
      pre_finished_at: "2026-10-08T10:00:00Z",
      post_finished_at: "2026-10-08T10:30:00Z",
      validation_completed_at: "2026-10-08T10:30:00Z",
      buyer_completed: true,
      seller_completed: true,
      core_completed: true,
      answers: {},
    };
    // Ricarica o riapertura: stessa capability, stato server concluso → GRAZIE.
    expect(questionnaireStage(completed)).toBe("complete");
    expect(readMarketValidationSession(storage, QV2_SESSION_STORAGE_KEY)?.participantCode).toBe("V017");
    // Solo il comando esplicito libera la sessione locale.
    clearMarketValidationSession(storage, QV2_SESSION_STORAGE_KEY);
    expect(readMarketValidationSession(storage, QV2_SESSION_STORAGE_KEY)).toBeNull();
  });

  it("il client non cancella la sessione alla schermata GRAZIE, solo con «Fai provare Vinea a un'altra persona»", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    expect(NEW_TESTER_LABEL).toBe("Fai provare Vinea a un'altra persona");
    expect(client.match(/clearMarketValidationSession\(/g)).toHaveLength(1);
    const newTester = client.slice(client.indexOf("const newTester = () => {"));
    expect(newTester.slice(0, newTester.indexOf("};"))).toInclude(
      "clearMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);",
    );
    expect(client).not.toMatch(/screen === "complete"\)\s*\{\s*clearMarketValidation/);
    // Il nuovo codice nasce solo da una capability nuova, dopo il comando esplicito.
    expect(client).toInclude("const capability = stored?.capability ?? newMarketValidationCapability();");
    // Progressi locali ripresi solo per un codice davvero ripreso.
    expect(client).toInclude("restoreMarketValidationProgress(window.localStorage, !fresh && result.data.session.resumed)");
  });

  it("la landing usa la copy approvata e nessun campo da compilare", () => {
    const client = read("frontend-next/src/app/beta-test/page-client.tsx");
    for (const copy of [
      "Market Validation",
      "Aiutaci a creare il futuro di Vinea",
      "La tua opinione conta.",
      "Prova Vinea Wine Club e raccontaci cosa ne pensi. Bastano pochi minuti per aiutarci a costruire una piattaforma migliore.",
      "Questa è una Beta di ricerca. Nessun pagamento, vendita o spedizione reale verrà effettuato.",
      "INIZIA IL TEST",
    ]) {
      expect(client).toInclude(copy);
    }
    expect(client).not.toInclude("<input");
  });
});

describe("QV2 finale: admin e CSV con le specifiche", () => {
  it("il dettaglio mostra la specifica di Q7 e Q19 sotto le scelte", () => {
    const answers = parseQv2Answers({ q07: ["price", "other"], q07_other: "Annata", q19: ["other"], q19_other: "Ritiro" });
    expect(decodeAnswer(7, answers).values).toEqual(["Prezzo", "Altro"]);
    expect(decodeAnswer(7, answers).extras).toEqual([{ label: "Specifica", value: "Annata" }]);
    expect(decodeAnswer(19, answers).extras).toEqual([{ label: "Specifica", value: "Ritiro" }]);
  });

  it("il CSV ha q07_other e q19_other subito dopo le scelte, una riga per codice", () => {
    const q07 = QV2_CSV_HEADERS.indexOf("q07_private_purchase_concerns");
    const q19 = QV2_CSV_HEADERS.indexOf("q19_important_services");
    expect(QV2_CSV_HEADERS[q07 + 1]).toBe("q07_other");
    expect(QV2_CSV_HEADERS[q19 + 1]).toBe("q19_other");
    expect(QV2_CSV_HEADERS).toHaveLength(54);
    expect(QV2_CSV_HEADERS.filter((header) =>
      /capability|session_id|hash|(^|_)ip(_|$)|user_agent|email/.test(header))).toEqual([]);
    const participant = parseQv2AdminParticipant({
      participant_code: "V017", cohort: "qv2", sessions_count: 1,
      started_at: "2026-10-08T10:00:00Z", last_activity_at: "2026-10-08T10:30:00Z",
      q07: ["price", "other"], q07_other: "=Annata", q19: ["other"], q19_other: "Ritiro",
    });
    expect(participant).not.toBeNull();
    const csv = buildQv2ParticipantsCsv([participant!]);
    const [header, row] = csv.replace(/^﻿/, "").trim().split("\r\n");
    const cells = row.split(";");
    expect(header.split(";")).toHaveLength(54);
    expect(cells[q07 + 1]).toBe("'=Annata");
    expect(cells[q19]).toBe("other");
    expect(cells[q19 + 1]).toBe("Ritiro");
  });
});
