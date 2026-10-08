"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/vinea/States";
import { formatPercentage } from "@/lib/market-validation/admin-analytics";
import {
  NOT_ANSWERED,
  POST_RANGE,
  PRE_RANGE,
  QUESTIONNAIRE_UNAVAILABLE,
  QV2_DISTRIBUTION_QUESTIONS,
  QV2_STATUS_COLUMNS,
  buildQuestionDistribution,
  buildQv2Funnel,
  decodeAnswer,
  decodeQuestionnaire,
  qv2TesterStatus,
  type DecodedAnswer,
  type Qv2AdminParticipant,
  type Qv2AdminSummary,
  type Qv2Answers,
  type Qv2Distributions,
  type Qv2EventDetail,
  type Qv2ParticipantDetail,
} from "@/lib/market-validation/questionnaire-admin";
import { getSupabaseClient } from "@/lib/supabase/client";
import { loadQv2ParticipantDetail } from "@/services/market-validation-questionnaire-admin-service";
import type { MarketValidationParticipantCode } from "@/services/types";

export const dateTime = (value: string | null): string =>
  value
    ? new Date(value).toLocaleString("it-IT", {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "—";

function Check({ value, title }: { value: boolean; title: string }) {
  return (
    <span
      title={title}
      aria-label={`${title}: ${value ? "sì" : "no"}`}
      className={value ? "font-semibold text-salvia-scuro" : "text-muted-foreground"}
    >
      {value ? "✓" : "—"}
    </span>
  );
}

function StatCard({ value, label, detail }: { value: string | number; label: string; detail?: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <span className="block text-3xl font-semibold">{value}</span>
        <span className="text-sm text-muted-foreground">{label}</span>
        {detail ? <span className="mt-1 block text-xs text-muted-foreground">{detail}</span> : null}
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- */
/*  KPI e funnel QV2                                                 */
/* ---------------------------------------------------------------- */

export function Qv2KpiSection({ summary }: { summary: Qv2AdminSummary }) {
  const base = summary.qv2.started;
  const share = (value: number) => `${formatPercentage(base > 0 ? (value * 100) / base : 0)} dei test iniziati`;
  return (
    <section aria-labelledby="qv2-kpi-title" className="space-y-3">
      <div>
        <h2 id="qv2-kpi-title" className="font-serif text-2xl">Questionario Market Validation</h2>
        <p className="max-w-3xl text-sm text-muted-foreground">
          Coorte QV2: solo i codici che hanno iniziato il questionario. I tester legacy restano fuori da
          questi denominatori. «Prova Vinea 5/5» richiede Acquisto, Vendita, Vinea AI, Club e Cantina
          registrati; «Market Validation completa» richiede anche il POST.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard value={base} label="Test iniziati" />
        <StatCard value={summary.qv2.preCompleted} label="PRE completati" detail={share(summary.qv2.preCompleted)} />
        <StatCard value={summary.qv2.buyCompleted} label="Acquisto completato" detail={share(summary.qv2.buyCompleted)} />
        <StatCard value={summary.qv2.sellCompleted} label="Vendita completata" detail={share(summary.qv2.sellCompleted)} />
        <StatCard value={summary.qv2.aiViewed} label="Vinea AI visitata" detail={share(summary.qv2.aiViewed)} />
        <StatCard value={summary.qv2.clubViewed} label="Club visitato" detail={share(summary.qv2.clubViewed)} />
        <StatCard value={summary.qv2.cellarViewed} label="Cantina visitata" detail={share(summary.qv2.cellarViewed)} />
        <StatCard
          value={summary.qv2.experienceCompleted}
          label="Prova Vinea 5/5"
          detail={share(summary.qv2.experienceCompleted)}
        />
        <StatCard value={summary.qv2.postCompleted} label="POST completati" detail={share(summary.qv2.postCompleted)} />
        <StatCard
          value={summary.qv2.validationCompleted}
          label="Market Validation completate"
          detail={share(summary.qv2.validationCompleted)}
        />
        <StatCard
          value={formatPercentage(summary.qv2.completionRate)}
          label="Completion rate"
          detail={`${summary.qv2.validationCompleted} complete su ${base} test iniziati`}
        />
      </div>
    </section>
  );
}

export function Qv2FunnelCard({ summary }: { summary: Qv2AdminSummary }) {
  const steps = buildQv2Funnel(summary);
  return (
    <Card>
      <CardHeader>
        <CardTitle className="font-serif text-2xl">Funnel QV2</CardTitle>
        <CardDescription>
          Ogni passaggio conta i codici QV2 che hanno raggiunto il traguardo; la base è sempre il numero di test
          iniziati. Le cinque aree della Prova Vinea sono percorsi indipendenti, senza un ordine obbligatorio.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {steps.map((step) => (
          <div key={step.key} className="space-y-1.5">
            <div className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
              <span className="font-medium">
                {step.label}
                {step.parallel ? <span className="ml-2 text-xs text-muted-foreground">percorso indipendente</span> : null}
              </span>
              <span>
                {step.value} su {step.denominator} · {formatPercentage(step.rate)}
              </span>
            </div>
            <Progress value={step.rate} aria-label={`${step.label}: ${step.value} su ${step.denominator}, ${formatPercentage(step.rate)}`} />
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- */
/*  Elenco tester                                                    */
/* ---------------------------------------------------------------- */

export function Qv2TesterTable({
  participants,
  onOpen,
}: {
  participants: Qv2AdminParticipant[];
  onOpen: (code: MarketValidationParticipantCode) => void;
}) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Codice</TableHead>
          <TableHead>Coorte</TableHead>
          <TableHead>Primo avvio</TableHead>
          <TableHead>Ultima attività</TableHead>
          {QV2_STATUS_COLUMNS.map((column) => (
            <TableHead key={column.key} title={column.title} className="text-center">
              {column.label}
            </TableHead>
          ))}
          <TableHead><span className="sr-only">Dettaglio</span></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {participants.map((participant) => {
          const status = qv2TesterStatus(participant);
          return (
            <TableRow key={participant.participantCode}>
              <TableCell className="font-semibold">
                <button
                  type="button"
                  className="underline-offset-4 hover:underline"
                  onClick={() => onOpen(participant.participantCode)}
                >
                  {participant.participantCode}
                </button>
              </TableCell>
              <TableCell>
                <Badge variant={participant.cohort === "qv2" ? "default" : "secondary"}>
                  {participant.cohort === "qv2" ? "QV2" : "Legacy"}
                </Badge>
              </TableCell>
              <TableCell className="whitespace-nowrap">{dateTime(participant.startedAt)}</TableCell>
              <TableCell className="whitespace-nowrap">{dateTime(participant.lastActivityAt)}</TableCell>
              {QV2_STATUS_COLUMNS.map((column) => (
                <TableCell key={column.key} className="text-center">
                  {participant.cohort === "legacy" && (column.key === "pre" || column.key === "experience" || column.key === "post" || column.key === "complete") ? (
                    <span className="text-muted-foreground" title="Non previsto nel percorso legacy">·</span>
                  ) : (
                    <Check value={status[column.key]} title={column.title} />
                  )}
                </TableCell>
              ))}
              <TableCell>
                <Button size="sm" variant="outline" onClick={() => onOpen(participant.participantCode)}>
                  Apri
                </Button>
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

/* ---------------------------------------------------------------- */
/*  Dettaglio tester                                                 */
/* ---------------------------------------------------------------- */

function AnswerItem({ answer }: { answer: DecodedAnswer }) {
  return (
    <div className="space-y-1 border-b border-border py-3 last:border-b-0">
      <p className="text-sm text-muted-foreground">
        <span className="font-semibold text-antracite">Q{answer.number}</span> · {answer.title}
      </p>
      {answer.answered ? (
        answer.kind === "multi" ? (
          <ul className="flex flex-wrap gap-1.5">
            {answer.values.map((value, index) => (
              <li key={`${value}-${index}`}><Badge variant="outline">{value}</Badge></li>
            ))}
          </ul>
        ) : (
          <p className="whitespace-pre-wrap break-words font-medium">{answer.values.join(", ")}</p>
        )
      ) : (
        <p className="italic text-muted-foreground">{NOT_ANSWERED}</p>
      )}
      {answer.extras.map((extra) => (
        <p key={extra.label} className="text-sm">
          <span className="text-muted-foreground">{extra.label}: </span>
          <span className="whitespace-pre-wrap break-words">{extra.value}</span>
        </p>
      ))}
    </div>
  );
}

function QuestionnaireBlock({
  title,
  answers,
  range,
  completedAt,
}: {
  title: string;
  answers: Qv2Answers | null;
  range: readonly [number, number];
  completedAt: string | null;
}) {
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="font-serif text-xl">{title}</h3>
        <span className="text-xs text-muted-foreground">
          {completedAt ? `Completato ${dateTime(completedAt)}` : "Non completato"}
        </span>
      </div>
      {answers ? (
        <div>
          {decodeQuestionnaire(answers, range[0], range[1]).map((answer) => (
            <AnswerItem key={answer.key} answer={answer} />
          ))}
        </div>
      ) : (
        <p className="rounded-md border border-dashed border-border p-3 text-sm text-muted-foreground">
          {QUESTIONNAIRE_UNAVAILABLE}
        </p>
      )}
    </section>
  );
}

function BehaviourBlock({ events }: { events: Qv2EventDetail[] }) {
  return (
    <section className="space-y-2">
      <h3 className="font-serif text-xl">B · Comportamento reale</h3>
      <p className="text-xs text-muted-foreground">Solo eventi registrati; conteggio e prima/ultima occorrenza.</p>
      <ul className="divide-y divide-border rounded-md border border-border">
        {events.map((event) => (
          <li key={event.event} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
            <span className="flex items-center gap-2">
              <Check value={event.count > 0} title={event.label} />
              {event.label}
            </span>
            <span className="text-muted-foreground">
              {event.count > 0
                ? `${event.count}× · ${dateTime(event.firstAt)}${event.count > 1 ? ` → ${dateTime(event.lastAt)}` : ""}`
                : "non registrato"}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

const eventCount = (events: Qv2EventDetail[], name: Qv2EventDetail["event"]) =>
  events.find((event) => event.event === name)?.count ?? 0;

// Confronto «dichiarato vs provato»: accosta risposte ed eventi, senza
// dedurre un giudizio che il dato non contiene.
function ComparisonBlock({ detail }: { detail: Qv2ParticipantDetail }) {
  const answers = detail.questionnaire;
  const declared = (numbers: number[]) =>
    numbers.map((number) => {
      const decoded = answers ? decodeAnswer(number, answers) : null;
      return {
        number,
        text: decoded?.answered ? decoded.values.join(", ") : answers ? NOT_ANSWERED : QUESTIONNAIRE_UNAVAILABLE,
      };
    });
  const rows = [
    {
      area: "Acquisto",
      declared: declared([15, 20]),
      observed: [
        ["Checkout avviato", eventCount(detail.events, "checkout_started")],
        ["Acquisto beta completato", eventCount(detail.events, "checkout_beta_completed")],
      ] as const,
    },
    {
      area: "Vendita",
      declared: declared([9, 16]),
      observed: [
        ["Vendita avviata", eventCount(detail.events, "sell_started")],
        ["Vendita completata", eventCount(detail.events, "sell_completed")],
      ] as const,
    },
    {
      area: "Spedizione",
      declared: declared([12, 13]),
      observed: [["Costo di spedizione visualizzato", eventCount(detail.events, "shipping_cost_viewed")]] as const,
    },
    {
      area: "Club",
      declared: declared([14]),
      observed: [["Club visualizzati", eventCount(detail.events, "club_viewed")]] as const,
    },
  ];
  return (
    <section className="space-y-2" aria-labelledby="qv2-compare-title">
      <h3 id="qv2-compare-title" className="font-serif text-xl">Dichiarato vs provato</h3>
      <div className="grid gap-2">
        {rows.map((row) => (
          <div key={row.area} className="grid gap-2 rounded-md border border-border p-3 text-sm md:grid-cols-[7rem_1fr_1fr]">
            <span className="font-semibold">{row.area}</span>
            <div className="space-y-1">
              <span className="text-xs uppercase tracking-wide text-muted-foreground">Ha dichiarato</span>
              {row.declared.map((item) => (
                <p key={item.number}><span className="text-muted-foreground">Q{item.number}: </span>{item.text}</p>
              ))}
            </div>
            <div className="space-y-1">
              <span className="text-xs uppercase tracking-wide text-muted-foreground">Ha provato</span>
              {row.observed.map(([label, count]) => (
                <p key={label} className="flex items-center gap-2">
                  <Check value={count > 0} title={label} /> {label}
                  {count > 0 ? <span className="text-muted-foreground">({count}×)</span> : null}
                </p>
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

const firstAt = (events: Qv2EventDetail[], name: Qv2EventDetail["event"]) =>
  events.find((event) => event.event === name)?.firstAt ?? null;

// Stato del tester nell'ordine del percorso: PRE, le cinque aree della Prova
// Vinea, esperienza 5/5, POST e Market Validation completa. Le aree vengono
// solo dagli eventi registrati.
function CompletionBlock({ detail }: { detail: Qv2ParticipantDetail }) {
  const areas = [
    ["ACQUISTO", "checkout_beta_completed"],
    ["VENDITA", "sell_completed"],
    ["AI", "ai_preview_viewed"],
    ["CLUB", "club_viewed"],
    ["CANTINA", "cellar_viewed"],
  ] as const;
  const areasDone = areas.filter(([, event]) => eventCount(detail.events, event) > 0).length;
  const items: ReadonlyArray<readonly [string, boolean, string | null]> = [
    ["PRE", detail.completion.preCompletedAt !== null, detail.completion.preCompletedAt],
    ...areas.map(([label, event]) => [label, eventCount(detail.events, event) > 0, firstAt(detail.events, event)] as const),
    [`EXPERIENCE ${areasDone}/5`, detail.completion.experienceCompleted, null],
    ["POST", detail.completion.postCompletedAt !== null, detail.completion.postCompletedAt],
    ["COMPLETE", detail.completion.validationCompletedAt !== null, detail.completion.validationCompletedAt],
  ];
  const previousRule =
    detail.cohort === "qv2" && detail.completion.coreCompletedAt !== null && !detail.completion.experienceCompleted;
  return (
    <section className="space-y-2">
      <h3 className="font-serif text-xl">D · Completamento</h3>
      {previousRule ? (
        <p className="rounded-md border border-oro/40 bg-oro/10 p-3 text-sm">
          Prova Vinea chiusa con la regola precedente (Acquisto + Vendita) il {dateTime(detail.completion.coreCompletedAt)}:
          le aree non registrate restano non visitate.
        </p>
      ) : null}
      <ul className="divide-y divide-border rounded-md border border-border">
        {items.map(([label, done, at]) => (
          <li key={label} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
            <span className="flex items-center gap-2 font-medium"><Check value={done} title={label} /> {label}</span>
            <span className="text-muted-foreground">{at ? dateTime(at) : done ? "" : "—"}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function Qv2ParticipantDetailSheet({
  participantCode,
  onClose,
}: {
  participantCode: MarketValidationParticipantCode | null;
  onClose: () => void;
}) {
  const [detail, setDetail] = useState<Qv2ParticipantDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (!participantCode) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    setDetail(null);
    loadQv2ParticipantDetail(getSupabaseClient(), participantCode)
      .then((next) => {
        if (!cancelled) setDetail(next);
      })
      .catch((caught: unknown) => {
        if (!cancelled) setError(caught instanceof Error ? caught.message : "Dettaglio non disponibile.");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [participantCode, attempt]);

  return (
    <Sheet open={participantCode !== null} onOpenChange={(open) => (open ? undefined : onClose())}>
      <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-3xl">
        <SheetHeader>
          <SheetTitle className="font-serif text-2xl">Tester {participantCode}</SheetTitle>
          <SheetDescription>
            {detail
              ? `${detail.cohort === "qv2" ? "Coorte QV2" : "Tester legacy"} · primo avvio ${dateTime(detail.startedAt)} · ultima attività ${dateTime(detail.lastActivityAt)}`
              : "Risposte dichiarate e comportamento registrato."}
          </SheetDescription>
        </SheetHeader>
        <div className="mt-6 space-y-8">
          {loading ? <LoadingBlock label="Caricamento dettaglio tester" /> : null}
          {error ? <ErrorState message={error} onRetry={() => setAttempt((value) => value + 1)} home={false} /> : null}
          {!loading && !error && participantCode && !detail ? (
            <EmptyState title={`Nessun dato per ${participantCode}.`} />
          ) : null}
          {detail ? <Qv2ParticipantDetailView detail={detail} /> : null}
        </div>
      </SheetContent>
    </Sheet>
  );
}

// Corpo del dettaglio, senza caricamento né Sheet: A PRE, B comportamento,
// C POST, D completamento, preceduti dal confronto dichiarato/provato.
export function Qv2ParticipantDetailView({ detail }: { detail: Qv2ParticipantDetail }) {
  return (
    <>
      {detail.cohort === "legacy" ? (
        <p className="rounded-md border border-oro/40 bg-oro/10 p-3 text-sm">
          Tester legacy: ha usato la guida senza questionario
          {detail.sessionsCount > 1 ? ` (${detail.sessionsCount} sessioni aggregate)` : ""}.
        </p>
      ) : null}
      <ComparisonBlock detail={detail} />
      <QuestionnaireBlock
        title="A · Questionario PRE"
        answers={detail.questionnaire}
        range={PRE_RANGE}
        completedAt={detail.completion.preCompletedAt}
      />
      <BehaviourBlock events={detail.events} />
      <QuestionnaireBlock
        title="C · Questionario POST"
        answers={detail.questionnaire}
        range={POST_RANGE}
        completedAt={detail.completion.postCompletedAt}
      />
      {detail.questionnaire ? (
        <section className="space-y-1">
          <h4 className="font-semibold">Feedback finale (facoltativo)</h4>
          {detail.questionnaire.final_feedback ? (
            <p className="whitespace-pre-wrap break-words">{detail.questionnaire.final_feedback}</p>
          ) : (
            <p className="italic text-muted-foreground">{NOT_ANSWERED}</p>
          )}
        </section>
      ) : null}
      <CompletionBlock detail={detail} />
    </>
  );
}

/* ---------------------------------------------------------------- */
/*  Distribuzioni                                                    */
/* ---------------------------------------------------------------- */

function DistributionCard({ distributions, number }: { distributions: Qv2Distributions; number: number }) {
  const distribution = buildQuestionDistribution(distributions, number);
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base font-semibold leading-snug">
          Q{distribution.number} · {distribution.title}
        </CardTitle>
        <CardDescription>
          Base: {distribution.base} rispondenti
          {distribution.multi ? " · scelta multipla: le percentuali possono superare complessivamente il 100%" : ""}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {distribution.base === 0 ? (
          <p className="text-sm text-muted-foreground">Nessuna risposta registrata.</p>
        ) : (
          distribution.rows.map((row) => (
            <div key={row.code} className="space-y-1">
              <div className="flex items-baseline justify-between gap-2 text-sm">
                <span>{row.label}</span>
                <span className="whitespace-nowrap text-muted-foreground">
                  {row.count} · {formatPercentage(row.percentage)}
                </span>
              </div>
              <Progress value={row.percentage} aria-label={`${row.label}: ${row.count} su ${distribution.base}, ${formatPercentage(row.percentage)}`} />
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

export function Qv2DistributionsSection({ distributions }: { distributions: Qv2Distributions }) {
  return (
    <section aria-labelledby="qv2-distributions-title" className="space-y-3">
      <div>
        <h2 id="qv2-distributions-title" className="font-serif text-2xl">Distribuzioni delle risposte</h2>
        <p className="text-sm text-muted-foreground">
          Solo risposte registrate dalla coorte QV2 ({distributions.respondents} questionari avviati,{" "}
          {distributions.preCompleted} PRE completati, {distributions.postCompleted} POST completati). Ogni percentuale
          usa come base i rispondenti della singola domanda.
        </p>
      </div>
      {distributions.respondents === 0 ? (
        <EmptyState
          title="Nessuna risposta QV2 registrata."
          message="Le distribuzioni compariranno dopo le prime risposte reali al questionario."
        />
      ) : (
        <Tabs defaultValue="pre">
          <TabsList>
            <TabsTrigger value="pre">PRE · Q1–Q13</TabsTrigger>
            <TabsTrigger value="post">POST · Q14–Q20</TabsTrigger>
          </TabsList>
          <TabsContent value="pre" className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {QV2_DISTRIBUTION_QUESTIONS.pre.map((number) => (
              <DistributionCard key={number} distributions={distributions} number={number} />
            ))}
          </TabsContent>
          <TabsContent value="post" className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {QV2_DISTRIBUTION_QUESTIONS.post.map((number) => (
              <DistributionCard key={number} distributions={distributions} number={number} />
            ))}
          </TabsContent>
        </Tabs>
      )}
      <p className="text-xs text-muted-foreground">
        Le risposte aperte (Q8, Q17, Q18) e i campi condizionali si leggono nel dettaglio del tester e nel CSV.
      </p>
    </section>
  );
}
