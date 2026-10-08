"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import {
  Q10_ACTIONS,
  QUESTIONS,
  answerValid,
  questionKey,
  type QuestionnaireAnswer,
  type QuestionnaireState,
} from "@/lib/market-validation/questionnaire";

export function QuestionnaireFlow({
  phase,
  state,
  onSave,
  onFinish,
}: {
  phase: "pre" | "post";
  state: QuestionnaireState;
  onSave: (question: number, answer: QuestionnaireAnswer) => Promise<boolean>;
  onFinish: (feedback?: string) => Promise<boolean>;
}) {
  const start = phase === "pre" ? 1 : 14;
  const end = phase === "pre" ? 13 : 20;
  const [savedAnswers, setSavedAnswers] = useState(state.answers);
  const [number, setNumber] = useState(() => {
    for (let index = start; index <= end; index++) if (state.answers[questionKey(index)] == null) return index;
    return end + 1;
  });
  const question = QUESTIONS[number - 1];
  const [answer, setAnswer] = useState<QuestionnaireAnswer | null>(state.answers[questionKey(number)] ?? null);
  const [feedback, setFeedback] = useState(typeof state.answers.final_feedback === "string" ? state.answers.final_feedback : "");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function move(next: number) {
    setNumber(next);
    setAnswer(savedAnswers[questionKey(next)] ?? null);
    setError(null);
    window.scrollTo({ top: 0 });
  }

  async function next() {
    if (pending || !answerValid(question, answer)) return;
    setPending(true);
    setError(null);
    try {
      const saved = await onSave(number, answer as QuestionnaireAnswer);
      if (saved) {
        setSavedAnswers((current) => ({ ...current, [questionKey(number)]: answer }));
        setNumber(number + 1);
        setAnswer(savedAnswers[questionKey(number + 1)] ?? null);
        window.scrollTo({ top: 0 });
      }
      else setError("Non siamo riusciti a salvare la risposta. Riprova.");
    } catch {
      setError("Non siamo riusciti a salvare la risposta. Riprova.");
    } finally {
      setPending(false);
    }
  }

  async function finish() {
    if (pending) return;
    setPending(true);
    setError(null);
    try {
      if (!(await onFinish(phase === "post" ? feedback : undefined))) setError("Non siamo riusciti a completare questa fase. Riprova.");
    } catch {
      setError("Non siamo riusciti a completare questa fase. Riprova.");
    } finally {
      setPending(false);
    }
  }

  if (number > end) return (
    <section className="mx-auto max-w-2xl space-y-5 rounded-3xl border border-border bg-card p-5 md:p-8">
      {phase === "pre" ? (
        <><h1 className="font-serif text-3xl font-semibold">Ora prova Vinea</h1><p className="text-base leading-7">Adesso esplora Vinea e prova in prima persona le due funzioni principali.</p></>
      ) : (
        <><h1 className="font-serif text-3xl font-semibold">Un'ultima cosa</h1><label htmlFor="final-feedback" className="block text-base font-medium">Una cosa che vorresti dirci su Vinea (facoltativo)</label><textarea id="final-feedback" value={feedback} onChange={(event) => setFeedback(event.target.value)} maxLength={1000} rows={4} className="w-full rounded-xl border border-border bg-background p-3 text-base" /></>
      )}
      {error && <p role="alert" className="text-bordeaux">{error}</p>}
      <Button className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" disabled={pending} onClick={finish}>{pending ? "Salvataggio…" : phase === "pre" ? "PROVA VINEA" : "CONCLUDI IL TEST"}</Button>
      <Button variant="ghost" className="min-h-11" disabled={pending} onClick={() => move(end)}>Indietro</Button>
    </section>
  );

  const object = typeof answer === "object" && !Array.isArray(answer) && answer ? answer : {};
  const choice = typeof answer === "string" ? answer : typeof object.choice === "string" ? object.choice : "";
  const values = Array.isArray(answer) ? answer : Array.isArray(object.choices) ? object.choices : [];
  const hasCondition = question.number === 11 ? choice !== "" && choice !== "never" : choice === question.condition?.code || (question.kind === "multi" && values.includes(question.condition?.code ?? ""));
  const options = question.number === 10 && choice === "yes" ? Q10_ACTIONS : question.options ?? [];

  function updateChoice(value: string) {
    setAnswer(question.condition || question.secondCondition ? { choice: value } : value);
    setError(null);
  }
  function updateField(field: string, value: string | string[]) {
    setAnswer({ ...object, ...(question.kind === "multi" ? {} : { choice }), [field]: value });
    setError(null);
  }
  function toggle(value: string, current: string[], setter: (next: string[]) => void, maximum?: number) {
    if (!current.includes(value) && maximum && current.length >= maximum) return;
    setter(current.includes(value) ? current.filter((item) => item !== value) : [...current, value]);
    setError(null);
  }

  return (
    <section className="mx-auto max-w-2xl space-y-5 rounded-3xl border border-border bg-card p-5 md:p-8" aria-labelledby="question-title">
      <div className="space-y-2"><p className="text-sm font-semibold text-bordeaux">{phase === "pre" ? `Domanda ${number} di 13` : `Domanda ${number} di 20`}</p><Progress value={((number - start + 1) / (end - start + 1)) * 100} aria-label={`Progresso questionario: domanda ${number}`} /></div>
      <h1 id="question-title" className="font-serif text-2xl font-semibold leading-snug md:text-3xl">{question.title}</h1>
      {question.maximum && <p className="text-sm text-muted-foreground">Scegline massimo {question.maximum}</p>}
      {question.kind === "text" ? (
        <textarea aria-label={question.title} rows={4} maxLength={1000} value={typeof answer === "string" ? answer : ""} onChange={(event) => setAnswer(event.target.value)} className="w-full rounded-xl border border-border bg-background p-3 text-base" />
      ) : (
        <div className="grid gap-2" role="group" aria-label={question.title}>
          {question.options?.map(([code, label]) => {
            const selected = question.kind === "multi" ? values.includes(code) : choice === code;
            return <button key={code} type="button" aria-pressed={selected} className={`min-h-12 rounded-xl border p-3 text-left text-base ${selected ? "border-bordeaux bg-bordeaux/10 font-medium" : "border-border bg-background"}`} onClick={() => question.kind === "multi" ? toggle(code, values, (next) => setAnswer(question.condition ? { choices: next, ...(next.includes("other") && typeof object.other === "string" ? { other: object.other } : {}) } : next), question.maximum) : updateChoice(code)}>{label}</button>;
          })}
        </div>
      )}
      {hasCondition && question.number === 10 && <div className="space-y-3"><p className="font-medium">Cosa ne hai fatto?</p>{options.map(([code, label]) => { const actions = Array.isArray(object.actions) ? object.actions : []; return <button key={code} type="button" aria-pressed={actions.includes(code)} className={`block min-h-12 w-full rounded-xl border p-3 text-left ${actions.includes(code) ? "border-bordeaux bg-bordeaux/10" : "border-border"}`} onClick={() => toggle(code, actions, (next) => updateField("actions", next))}>{label}</button>; })}{Array.isArray(object.actions) && object.actions.includes("other") && <input aria-label="Altro" maxLength={200} value={typeof object.other === "string" ? object.other : ""} onChange={(event) => updateField("other", event.target.value)} className="min-h-12 w-full rounded-xl border border-border bg-background p-3" />}</div>}
      {hasCondition && question.condition && question.number !== 10 && <label className="block space-y-2 text-base"><span>{question.condition.label}</span><input maxLength={question.condition.optional ? 200 : 500} value={typeof object[question.condition.field] === "string" ? object[question.condition.field] : ""} onChange={(event) => updateField(question.condition!.field, event.target.value)} className="min-h-12 w-full rounded-xl border border-border bg-background p-3 text-base" /></label>}
      {hasCondition && question.secondCondition && <label className="block space-y-2 text-base"><span>{question.secondCondition.label}</span><input maxLength={500} value={typeof object[question.secondCondition.field] === "string" ? object[question.secondCondition.field] : ""} onChange={(event) => updateField(question.secondCondition!.field, event.target.value)} className="min-h-12 w-full rounded-xl border border-border bg-background p-3 text-base" /></label>}
      {error && <p role="alert" className="text-bordeaux">{error}</p>}
      <Button disabled={pending || !answerValid(question, answer)} onClick={next} className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90">{pending ? "Salvataggio…" : "Continua"}</Button>
      {number > start && <Button variant="ghost" disabled={pending} className="min-h-11" onClick={() => move(number - 1)}>Indietro</Button>}
    </section>
  );
}
