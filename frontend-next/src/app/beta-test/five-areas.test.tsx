import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createMarketValidationQuestionnaireService } from "@/services/market-validation-questionnaire-service";
import {
  EXPERIENCE_AREAS,
  Q10_ACTIONS,
  QUESTIONS,
  answerValid,
  experienceAreasCount,
  experienceAreasDone,
  multiSelectHint,
  questionnaireStage,
  type ExperienceAreasDone,
  type QuestionnaireState,
} from "@/lib/market-validation/questionnaire";
import { ExperienceHub, EXPERIENCE_CONTINUE_LABEL, EXPERIENCE_LOCKED_LABEL } from "./_components/ExperienceHub";
import { ParticipantCodeBadge } from "./_components/ParticipantCodeBadge";
import { ValidationComplete } from "./_components/ValidationComplete";

// Correzioni dopo il primo test reale su iPhone: codice test visibile e
// assegnato dal server, istruzioni delle multi-select, nuova Q15, immagine
// approvata nella landing e Prova Vinea con cinque aree obbligatorie.

const root = resolve(import.meta.dir, "../../../..");
const read = (path: string) => readFileSync(resolve(root, path), "utf8");
const client = () => read("frontend-next/src/app/beta-test/page-client.tsx");
const question = (number: number) => QUESTIONS[number - 1];
const html = (node: React.ReactNode) => renderToStaticMarkup(<>{node}</>);
const text = (markup: string) => markup.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");

const SESSION = "12dc0000-0000-4000-8000-000000000201";
const CAPABILITY = "12dc0000-0000-4000-8000-0000000000d1";
const AT = "2026-10-08T10:00:00Z";

const serverState = (overrides: Record<string, unknown> = {}) => ({
  session_id: SESSION,
  participant_code: "V002",
  pre_finished_at: AT,
  post_finished_at: null,
  validation_completed_at: null,
  buyer_completed: false,
  seller_completed: false,
  ai_viewed: false,
  club_viewed: false,
  cellar_viewed: false,
  experience_completed: false,
  core_completed: false,
  answers: {},
  ...overrides,
});

// Finto client Supabase: start e read rispondono come le RPC reali.
const fakeClient = (start: unknown, read: unknown = serverState()) => ({
  rpc: async (name: string) => ({
    data: name === "beta_validation_qv2_start" ? start : read,
    error: null,
  }),
}) as unknown as SupabaseClient;

const NONE: ExperienceAreasDone = { buyer: false, seller: false, ai: false, club: false, cellar: false };
const hub = (done: ExperienceAreasDone) =>
  html(<ExperienceHub done={done} completing={false} completionError={null} onOpen={() => undefined} onContinue={() => undefined} />);
const continueButton = (markup: string) => markup.slice(markup.lastIndexOf("<button"));

describe("A/B · codice test assegnato dal server, fail closed", () => {
  it("A: il codice mostrato è quello restituito dalla RPC di avvio", async () => {
    const service = createMarketValidationQuestionnaireService(fakeClient([
      { session_id: SESSION, participant_code: "V002", started_at: AT, resumed: false },
    ]));
    const result = await service.startOrResume(CAPABILITY);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.data.session.participantCode).toBe("V002");
    expect(result.data.state.participant_code).toBe("V002");
    // Il badge riporta quel valore, non un input.
    const badge = html(<ParticipantCodeBadge code={result.data.session.participantCode} />);
    expect(text(badge)).toInclude("Test V002");
    expect(badge).not.toInclude("<input");
  });

  it("A: il badge compare su PRE, hub, cinque moduli e POST", () => {
    const source = client();
    expect(source).toInclude("<ParticipantCodeBadge code={session.participantCode} />");
    for (const screen of ["pre-questionnaire", "post-questionnaire", "marketplace", "seller", "ai", "club", "cellar"]) {
      const branch = source.slice(source.indexOf(`if (screen === "${screen}")`));
      expect(branch.slice(0, branch.indexOf("}\n")).includes("withCode(")).toBeTrue();
    }
    expect(source).toInclude("return withCode(\n    <ExperienceHub");
    expect(source).not.toMatch(/<input[^>]*participant/i);
  });

  it("B: senza codice valido dal server il questionario non parte", async () => {
    for (const start of [
      [],
      [{ session_id: SESSION, participant_code: "V000", started_at: AT, resumed: false }],
      [{ session_id: SESSION, participant_code: "", started_at: AT, resumed: false }],
      [{ session_id: "non-uuid", participant_code: "V002", started_at: AT, resumed: false }],
    ]) {
      const result = await createMarketValidationQuestionnaireService(fakeClient(start)).startOrResume(CAPABILITY);
      expect(result.ok).toBeFalse();
    }
    const failing = { rpc: async () => ({ data: null, error: { message: "boom" } }) } as unknown as SupabaseClient;
    expect((await createMarketValidationQuestionnaireService(failing).startOrResume(CAPABILITY)).ok).toBeFalse();
    expect((await createMarketValidationQuestionnaireService(null).startOrResume(CAPABILITY)).ok).toBeFalse();

    const source = client();
    const begin = source.slice(source.indexOf("const begin = async"), source.indexOf("const newTester"));
    expect(begin).toInclude("if (!result.ok || result.data.state.participant_code !== result.data.session.participantCode) {");
    expect(begin.indexOf("setError(START_ERROR);")).toBeLessThan(begin.indexOf("setSession(result.data.session);"));
    expect(source).toInclude("Non siamo riusciti ad assegnare il tuo codice test.");
  });
});

describe("C/D/E/F · istruzioni delle multi-select", () => {
  it("la regola è generica: massimo dichiarato o più risposte", () => {
    expect(multiSelectHint()).toBe("Puoi selezionare più risposte");
    expect(multiSelectHint(3)).toBe("Scegline massimo 3");
    expect(multiSelectHint(2)).toBe("Scegline massimo 2");
    const flow = read("frontend-next/src/app/beta-test/_components/QuestionnaireFlow.tsx");
    expect(flow).toInclude('{question.kind === "multi" && <p className="text-base font-medium text-bordeaux">{multiSelectHint(question.maximum)}</p>}');
    expect(flow).not.toInclude("Scegline massimo {question.maximum}");
  });

  it("C: Q5 senza massimo mostra «Puoi selezionare più risposte»", () => {
    expect(question(5).title).toBe("Negli ultimi 12 mesi dove hai acquistato vino?");
    expect(question(5).kind).toBe("multi");
    expect(question(5).maximum).toBeUndefined();
    expect(multiSelectHint(question(5).maximum)).toBe("Puoi selezionare più risposte");
    const all = question(5).options!.map(([code]) => code).filter((code) => code !== "other");
    expect(answerValid(question(5), { choices: all })).toBeTrue();
  });

  it("D: Q7 «Scegline massimo 3» con limite reale", () => {
    expect(multiSelectHint(question(7).maximum)).toBe("Scegline massimo 3");
    expect(answerValid(question(7), { choices: ["authenticity", "storage", "price"] })).toBeTrue();
    expect(answerValid(question(7), { choices: ["authenticity", "storage", "price", "payment"] })).toBeFalse();
    // Il toggle non aggiunge oltre il massimo.
    expect(read("frontend-next/src/app/beta-test/_components/QuestionnaireFlow.tsx"))
      .toInclude("if (!current.includes(value) && maximum && current.length >= maximum) return;");
  });

  it("E: le azioni di Q10 mostrano «Puoi selezionare più risposte»", () => {
    const flow = read("frontend-next/src/app/beta-test/_components/QuestionnaireFlow.tsx");
    expect(flow).toInclude('<p className="font-medium">Cosa ne hai fatto?</p><p className="text-base font-medium text-bordeaux">{multiSelectHint()}</p>');
    expect(answerValid(question(10), { choice: "yes", actions: Q10_ACTIONS.filter(([code]) => code !== "other").map(([code]) => code) })).toBeTrue();
  });

  it("F: Q19 «Scegline massimo 2» con limite reale", () => {
    expect(question(19).title).toBe("Quale servizio sarebbe più importante per te?");
    expect(multiSelectHint(question(19).maximum)).toBe("Scegline massimo 2");
    expect(answerValid(question(19), { choices: ["reviews", "support"] })).toBeTrue();
    expect(answerValid(question(19), { choices: ["reviews", "support", "community"] })).toBeFalse();
  });
});

describe("G · nuova Q15", () => {
  it("chiede dell'acquisto ipotetico con Sì/No e «Perché?» sul No, codici invariati", () => {
    expect(question(15).title).toBe(
      "Se Vinea fosse già operativa e le bottiglie mostrate fossero realmente disponibili, avresti preso seriamente in considerazione un acquisto?",
    );
    expect(question(15).options).toEqual([["yes", "Sì"], ["no", "No"]]);
    expect(question(15).condition).toEqual({ code: "no", label: "Perché?", field: "why_not" });
    expect(read("frontend-next/src/lib/market-validation/questionnaire.ts"))
      .not.toInclude("Hai trovato almeno una bottiglia che avresti seriamente considerato di acquistare?");
  });
});

describe("H · landing con l'immagine approvata", () => {
  it("usa l'asset versionato prima del copy e della CTA", () => {
    const asset = "frontend-next/public/images/market-validation/vinea-market-validation-cover.webp";
    expect(existsSync(resolve(root, asset))).toBeTrue();
    const bytes = readFileSync(resolve(root, asset));
    expect(bytes.subarray(0, 4).toString("ascii")).toBe("RIFF");
    expect(bytes.subarray(8, 12).toString("ascii")).toBe("WEBP");
    expect(bytes.length).toBeLessThan(200_000);

    const source = client();
    expect(source).toInclude('export const MARKET_VALIDATION_COVER = "/images/market-validation/vinea-market-validation-cover.webp";');
    const landing = source.slice(source.indexOf("src={MARKET_VALIDATION_COVER}"));
    expect(source).not.toMatch(/https?:\/\/[^"]*\.(webp|jpe?g|png)/);
    const order = ["src={MARKET_VALIDATION_COVER}", "Aiutaci a creare il futuro di Vinea", "La tua opinione conta.",
      "Prova Vinea Wine Club e raccontaci cosa ne pensi.", "Questa è una Beta di ricerca.", "INIZIA IL TEST"]
      .map((fragment) => landing.indexOf(fragment));
    expect(order.every((index) => index >= 0)).toBeTrue();
    expect([...order].sort((a, b) => a - b)).toEqual(order);
    // Smartphone: card con proporzione fissa e taglio dall'alto; desktop intera.
    expect(source).toInclude("object-cover object-top md:object-contain md:object-center");
    expect(source).toInclude("priority");
  });
});

describe("I/J/K/L/M · cinque aree obbligatorie", () => {
  it("ha le cinque aree con l'evento server che le completa", () => {
    expect(EXPERIENCE_AREAS.map((area) => [area.title, area.event])).toEqual([
      ["Acquisto", "checkout_beta_completed"],
      ["Vendita", "sell_completed"],
      ["Vinea AI", "ai_preview_viewed"],
      ["Club", "club_viewed"],
      ["Cantina", "cellar_viewed"],
    ]);
  });

  it("parte da 0/5 con le card «Da provare» e il pulsante bloccato", () => {
    const markup = hub(NONE);
    expect(text(markup)).toInclude("Prova tutte le funzioni");
    expect(text(markup)).toInclude("Per completare il Beta Test esplora tutte e 5 le aree.");
    expect(text(markup)).toInclude("0 di 5 completate");
    expect(markup.match(/Da provare/g)).toHaveLength(5);
    expect(continueButton(markup)).toMatch(/ disabled=""/);
    expect(text(continueButton(markup))).toInclude(EXPERIENCE_LOCKED_LABEL);
  });

  it("I: Acquisto + Vendita non sbloccano più il POST", () => {
    const done = { ...NONE, buyer: true, seller: true };
    expect(experienceAreasCount(done)).toBe(2);
    const markup = hub(done);
    expect(text(markup)).toInclude("2 di 5 completate");
    expect(continueButton(markup)).toMatch(/ disabled=""/);
    expect(text(markup)).toInclude("Prossima prova: Vinea AI.");
    expect(questionnaireStage(serverState({ buyer_completed: true, seller_completed: true }) as QuestionnaireState)).toBe("hub");
  });

  it.each([
    ["J", "senza Cantina", { buyer: true, seller: true, ai: true, club: true, cellar: false }],
    ["K", "senza Club", { buyer: true, seller: true, ai: true, club: false, cellar: true }],
    ["L", "senza AI", { buyer: true, seller: true, ai: false, club: true, cellar: true }],
  ] as const)("%s: quattro aree %s non bastano", (_id, _label, done) => {
    expect(experienceAreasCount(done)).toBe(4);
    const markup = hub(done);
    expect(text(markup)).toInclude("4 di 5 completate");
    expect(continueButton(markup)).toMatch(/ disabled=""/);
    expect(text(continueButton(markup))).toInclude(EXPERIENCE_LOCKED_LABEL);
  });

  it("M: 5/5 abilita «CONTINUA CON LE ULTIME DOMANDE»", () => {
    const done = { buyer: true, seller: true, ai: true, club: true, cellar: true };
    const markup = hub(done);
    expect(text(markup)).toInclude("5 di 5 completate");
    expect(markup.match(/Completato/g)).toHaveLength(5);
    expect(continueButton(markup)).not.toMatch(/ disabled=""/);
    expect(text(continueButton(markup))).toInclude(EXPERIENCE_CONTINUE_LABEL);
  });

  it("M: il POST si apre solo sullo stato riletto dal server dopo beta_completed", () => {
    const source = client();
    const go = source.slice(source.indexOf("const continueToPost"), source.indexOf("const markBuyerCompleted"));
    expect(go).toInclude("if (completing || experienceAreasCount(done) < 5) return;");
    expect(go).toInclude('const result = await track("beta_completed", {}, "beta_completed");');
    expect(go).toInclude("if (!state || !state.experience_completed || !state.core_completed) {");
    expect(go.indexOf("refreshQuestionnaire()")).toBeLessThan(go.indexOf('setScreen("post-questionnaire")'));
    expect(questionnaireStage(serverState({ experience_completed: true, core_completed: true }) as QuestionnaireState))
      .toBe("post-questionnaire");
  });

  it("nessuna card si completa al click: conta l'evento accettato dal server", () => {
    const source = client();
    const open = source.slice(source.indexOf("const open = (next"), source.indexOf("const selectListing"));
    expect(open).not.toInclude("setConfirmed");
    // Le conferme locali nascono solo dai callback chiamati dopo result.ok.
    expect(source.match(/setConfirmed\(/g)).toHaveLength(5);
    expect(read("frontend-next/src/app/beta-test/_components/ExperienceHub.tsx")).not.toInclude("setConfirmed");
  });
});

describe("N · cellar_viewed solo aprendo la Cantina", () => {
  it("l'hub non registra eventi; la schermata Cantina sì, all'apertura", () => {
    const experienceHub = read("frontend-next/src/app/beta-test/_components/ExperienceHub.tsx");
    expect(experienceHub).not.toInclude("track(");
    expect(experienceHub).not.toInclude("cellar_viewed");
    const preview = read("frontend-next/src/app/beta-test/_components/CellarPreview.tsx");
    expect(preview).toInclude('track("cellar_viewed", {}, "cellar_viewed")');
    expect(experienceAreasDone(serverState())).toEqual(NONE);
  });
});

describe("O · il database impedisce di saltare le cinque prove", () => {
  it("la migrazione rifiuta beta_completed e finish_post sotto 5/5", () => {
    const migration = read("supabase/migrations/20261008230000_market_validation_qv2_five_areas.sql");
    expect(migration).toInclude("'cellar_viewed',");
    expect(migration).toMatch(/count\(distinct e\.event_name\) = 5/);
    expect(migration).toInclude("and not private.beta_validation_qv2_experience_completed(v_session.id) then");
    expect(migration).toInclude("or not private.beta_validation_qv2_experience_completed(v.id) then");
    expect(migration).toInclude("revoke all on function private.beta_validation_qv2_experience_completed(uuid)");
    // Le migrazioni gia distribuite restano intatte.
    expect(read("supabase/migrations/20261008120000_market_validation_questionnaire_qv2.sql")).not.toInclude("cellar_viewed");
    expect(read("supabase/migrations/20261008220000_market_validation_qv2_other_options.sql")).not.toInclude("cellar_viewed");
  });
});

describe("P · refresh e resume conservano le cinque aree", () => {
  it("lo stato delle aree arriva dalla lettura server, senza conferme locali", async () => {
    const state = serverState({ buyer_completed: true, seller_completed: true, ai_viewed: true, club_viewed: true, cellar_viewed: true });
    const service = createMarketValidationQuestionnaireService(fakeClient(
      [{ session_id: SESSION, participant_code: "V002", started_at: AT, resumed: true }],
      state,
    ));
    const result = await service.startOrResume(CAPABILITY);
    expect(result.ok).toBeTrue();
    if (!result.ok) return;
    expect(result.data.session.resumed).toBeTrue();
    expect(experienceAreasCount(experienceAreasDone(result.data.state))).toBe(5);
    // Un valore non booleano dal server non completa l'area.
    const odd = await createMarketValidationQuestionnaireService(fakeClient(
      [{ session_id: SESSION, participant_code: "V002", started_at: AT, resumed: true }],
      serverState({ cellar_viewed: "true", experience_completed: 1 }),
    )).startOrResume(CAPABILITY);
    expect(odd.ok && odd.data.state.cellar_viewed).toBeFalse();
    expect(odd.ok && odd.data.state.experience_completed).toBeFalse();
  });

  it("tornando all'hub lo stato si rilegge dal server", () => {
    const source = client();
    const open = source.slice(source.indexOf("const open = (next"), source.indexOf("const selectListing"));
    expect(open).toInclude('if (next === "hub") void refreshQuestionnaire();');
  });

  it("una Prova Vinea chiusa con la regola precedente propone solo un nuovo codice", () => {
    expect(questionnaireStage(serverState({ buyer_completed: true, seller_completed: true, core_completed: true }) as QuestionnaireState))
      .toBe("previous-rule");
    const source = client();
    const branch = source.slice(source.indexOf('if (screen === "previous-rule")'), source.indexOf('if (screen === "marketplace")'));
    expect(branch).toInclude("<Button onClick={onNewTester}");
    expect(branch).not.toInclude("track(");
  });
});

describe("Q/R · GRAZIE e nuovo tester", () => {
  it("Q: GRAZIE mostra «Test completato» e «Codice test: V002»", () => {
    const output = text(html(<ValidationComplete qv2 participantCode="V002" />));
    expect(output).toInclude("Test completato");
    expect(output).toInclude("Codice test: V002");
    expect(questionnaireStage(serverState({
      core_completed: true, experience_completed: true, post_finished_at: AT, validation_completed_at: AT,
    }) as QuestionnaireState)).toBe("complete");
  });

  it("R: la sessione locale si libera solo con il comando esplicito", () => {
    const source = client();
    expect(source.match(/clearMarketValidationSession\(/g)).toHaveLength(1);
    const newTester = source.slice(source.indexOf("const newTester"), source.indexOf("if (session && questionnaire)"));
    expect(newTester).toInclude("clearMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);");
    expect(source.match(/onClick=\{onNewTester\}/g)).toHaveLength(2);
  });
});
