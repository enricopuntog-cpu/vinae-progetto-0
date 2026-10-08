"use client";

import {
  useCallback,
  useEffect,
  useState,
  type Dispatch,
  type SetStateAction,
} from "react";
import { Button } from "@/components/ui/button";
import type { MarketValidationSession, MarketValidationQuestionnaireState } from "@/services/types";
import type { MarketValidationDemoListing } from "@/lib/market-validation/demo-data";
import { NEW_TESTER_LABEL, questionKey, questionnaireStage, type QuestionnaireAnswer } from "@/lib/market-validation/questionnaire";
import {
  clearMarketValidationSession,
  QV2_SESSION_STORAGE_KEY,
  readMarketValidationSession,
  writeMarketValidationSession,
  newMarketValidationCapability,
} from "@/lib/market-validation/persistence";
import { marketValidationCanComplete } from "@/lib/market-validation/mv2-flow";
import {
  clearMarketValidationProgress,
  INITIAL_MARKET_VALIDATION_PROGRESS,
  restoreMarketValidationProgress,
  writeMarketValidationProgress,
  type MarketValidationProgress,
} from "@/lib/market-validation/progress";
import {
  finishQuestionnairePost,
  finishQuestionnairePre,
  readQuestionnaire,
  saveQuestionnaireAnswer,
  startQuestionnaire,
} from "./actions";
import { CellarPreview } from "./_components/CellarPreview";
import { ClubDemo } from "./_components/ClubDemo";
import { QuestionnaireFlow } from "./_components/QuestionnaireFlow";
import { DemoCheckout } from "./_components/DemoCheckout";
import { DemoListingDetail } from "./_components/DemoListingDetail";
import { DemoMarketplace } from "./_components/DemoMarketplace";
import { SellDemo } from "./_components/SellDemo";
import { StaticAiPreview } from "./_components/StaticAiPreview";
import {
  ValidationHub,
  type MarketValidationScreen,
} from "./_components/ValidationHub";
import { ValidationComplete } from "./_components/ValidationComplete";
import { useMarketValidationTracker } from "./use-market-validation-tracker";

export default function BetaTestPageClient({
  shippingFeeCents,
}: {
  shippingFeeCents: number;
}) {
  const [session, setSession] = useState<MarketValidationSession | null>(null);
  const [questionnaire, setQuestionnaire] = useState<MarketValidationQuestionnaireState | null>(null);
  const [progress, setProgress] = useState<MarketValidationProgress>(INITIAL_MARKET_VALIDATION_PROGRESS);
  const [ready, setReady] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const resume = async () => {
      const stored = readMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);
      if (stored) {
        const result = await startQuestionnaire(stored.capability);
        if (!active) return;
        if (result.ok) {
          writeMarketValidationSession(window.localStorage, result.data.session, QV2_SESSION_STORAGE_KEY);
          setProgress(restoreMarketValidationProgress(window.localStorage, true));
          setQuestionnaire(result.data.state);
          setSession(result.data.session);
        } else {
          setError(result.error);
        }
      }
      if (active) setReady(true);
    };
    void resume();
    return () => { active = false; };
  }, []);

  const begin = async (fresh = false) => {
    if (pending) return;
    setPending(true);
    setError(null);
    const stored = fresh ? null : readMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);
    const capability = stored?.capability ?? newMarketValidationCapability();
    const result = await startQuestionnaire(capability);
    setPending(false);
    if (!result.ok) { setError(result.error); return; }
    writeMarketValidationSession(window.localStorage, result.data.session, QV2_SESSION_STORAGE_KEY);
    // Un codice appena allocato parte da zero: progressi locali residui (per
    // esempio della guida legacy) non valgono per il nuovo partecipante.
    setProgress(restoreMarketValidationProgress(window.localStorage, !fresh && result.data.session.resumed));
    setQuestionnaire(result.data.state);
    setSession(result.data.session);
  };

  const newTester = () => {
    clearMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);
    clearMarketValidationProgress(window.localStorage);
    setSession(null);
    setQuestionnaire(null);
    setProgress(INITIAL_MARKET_VALIDATION_PROGRESS);
    setError(null);
  };

  if (session && questionnaire) {
    return (
      <MarketValidationExperience
        key={session.sessionId}
        session={session}
        questionnaire={questionnaire}
        onQuestionnaire={setQuestionnaire}
        onNewTester={newTester}
        shippingFeeCents={shippingFeeCents}
        progress={progress}
        onProgress={setProgress}
      />
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <section className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Market Validation</p>
        <h1 className="mt-2 font-serif text-3xl font-semibold uppercase leading-tight md:text-4xl">Aiutaci a creare il futuro di Vinea</h1>
        <p className="mt-4 font-serif text-xl text-bordeaux md:text-2xl">La tua opinione conta.</p>
        <p className="mt-4 max-w-xl text-base leading-7 text-muted-foreground md:text-lg">
          Prova Vinea Wine Club e raccontaci cosa ne pensi. Bastano pochi minuti per aiutarci a costruire una piattaforma migliore.
        </p>
        <p className="mt-5 rounded-2xl border border-border bg-crema p-4 text-sm leading-6">
          Questa è una Beta di ricerca. Nessun pagamento, vendita o spedizione reale verrà effettuato.
        </p>
        {error && <p role="alert" className="mt-4 text-bordeaux">{error}</p>}
        <Button className="mt-6 min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" disabled={!ready || pending} onClick={() => void begin()}>
          {pending ? "Avvio in corso…" : "INIZIA IL TEST"}
        </Button>
      </section>
    </div>
  );
}

function MarketValidationExperience({
  session,
  questionnaire,
  onQuestionnaire,
  onNewTester,
  shippingFeeCents,
  progress,
  onProgress,
}: {
  session: MarketValidationSession;
  questionnaire: MarketValidationQuestionnaireState;
  onQuestionnaire: (next: MarketValidationQuestionnaireState) => void;
  onNewTester: () => void;
  shippingFeeCents: number;
  progress: MarketValidationProgress;
  onProgress: Dispatch<SetStateAction<MarketValidationProgress>>;
}) {
  // QV2: la prima schermata dipende dalla fase aperta sul server, non dal client.
  const [screen, setScreen] = useState<MarketValidationScreen>(() => questionnaireStage(questionnaire));
  const [selectedListing, setSelectedListing] =
    useState<MarketValidationDemoListing | null>(null);
  const [completing, setCompleting] = useState(false);
  const [completionError, setCompletionError] = useState<string | null>(null);
  const track = useMarketValidationTracker(session);

  const updateProgress = useCallback(
    (update: (current: MarketValidationProgress) => MarketValidationProgress) => {
      onProgress((current) => {
        const next = update(current);
        if (
          next.buyerCompleted === current.buyerCompleted &&
          next.sellerCompleted === current.sellerCompleted &&
          next.aiPreviewViewed === current.aiPreviewViewed &&
          next.aiInterest === current.aiInterest &&
          next.clubViewed === current.clubViewed &&
          next.favoriteDemoIds.length === current.favoriteDemoIds.length &&
          next.favoriteDemoIds.every(
            (id, index) => id === current.favoriteDemoIds[index],
          )
        ) {
          return current;
        }
        return next;
      });
    },
    [onProgress],
  );

  // Il test concluso resta legato a questo browser: ricarica o riapertura
  // riprendono la schermata GRAZIE dello stesso codice. Solo il comando
  // esplicito «Fai provare Vinea a un'altra persona» libera la sessione locale.
  useEffect(() => {
    writeMarketValidationProgress(window.localStorage, progress);
  }, [progress]);

  // Ogni schermata della guida si apre dall'alto: su smartphone le card stanno
  // a metà pagina e il «← Indietro» deve essere subito visibile.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [screen]);

  const open = (next: MarketValidationScreen) => {
    setCompletionError(null);
    setScreen(next);
  };

  const selectListing = (listing: MarketValidationDemoListing) => {
    setSelectedListing(listing);
    setScreen("detail");
  };

  const toggleFavorite = (id: MarketValidationDemoListing["id"]) => {
    updateProgress((current) => ({
      ...current,
      favoriteDemoIds: current.favoriteDemoIds.includes(id)
        ? current.favoriteDemoIds.filter((candidate) => candidate !== id)
        : [...current.favoriteDemoIds, id],
    }));
  };

  // Ricarica lo stato autoritativo dopo ogni cambio di fase.
  const refreshQuestionnaire = useCallback(async () => {
    const result = await readQuestionnaire(session.sessionId, session.capability);
    if (result.ok) onQuestionnaire(result.data.state);
    return result.ok;
  }, [session, onQuestionnaire]);

  const saveQuestionnaire = useCallback(async (questionNumber: number, answer: QuestionnaireAnswer) => {
    const result = await saveQuestionnaireAnswer(session.sessionId, session.capability, questionKey(questionNumber), answer);
    return result.ok;
  }, [session]);

  // PRE concluso: si apre la guida Prova Vinea (CORE) già approvata.
  const finishPreQuestionnaire = useCallback(async () => {
    const result = await finishQuestionnairePre(session.sessionId, session.capability);
    if (!result.ok) return false;
    await refreshQuestionnaire();
    setScreen("hub");
    return true;
  }, [session, refreshQuestionnaire]);

  // POST concluso: il feedback finale è facoltativo e si salva prima della chiusura.
  const finishPostQuestionnaire = useCallback(async (feedback?: string) => {
    if (feedback !== undefined && feedback.trim() !== "") {
      const saved = await saveQuestionnaireAnswer(session.sessionId, session.capability, "final_feedback", feedback);
      if (!saved.ok) return false;
    }
    const result = await finishQuestionnairePost(session.sessionId, session.capability);
    if (!result.ok) return false;
    setScreen("complete");
    return true;
  }, [session]);

  const complete = async () => {
    if (completing || !marketValidationCanComplete(progress)) return;
    setCompleting(true);
    setCompletionError(null);
    const result = await track("beta_completed", {}, "beta_completed");
    setCompleting(false);
    if (!result.ok) {
      setCompletionError(
        "Non siamo riusciti a concludere il test. Riprova: i progressi sono conservati.",
      );
      return;
    }
    // CORE concluso con beta_completed registrato: si apre il POST (Q14-Q20).
    await refreshQuestionnaire();
    setScreen("post-questionnaire");
  };

  // Lo step Vendi si chiude solo quando la demo interna ha registrato
  // `sell_completed` sulla conferma esplicita dell'ultimo passo.
  const markSellerCompleted = useCallback(
    () => updateProgress((current) => ({ ...current, sellerCompleted: true })),
    [updateProgress],
  );

  const markClubViewed = useCallback(
    () => updateProgress((current) => ({ ...current, clubViewed: true })),
    [updateProgress],
  );

  if (screen === "complete") {
    return (
      <ValidationComplete
        qv2
        participantCode={session.participantCode}
        action={
          <Button onClick={onNewTester} className="mt-6 min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90">
            {NEW_TESTER_LABEL}
          </Button>
        }
      />
    );
  }
  if (screen === "marketplace") {
    return (
      <DemoMarketplace
        favorites={progress.favoriteDemoIds}
        track={track}
        onSelect={selectListing}
        onBack={() => open("hub")}
      />
    );
  }
  if (screen === "detail" && selectedListing) {
    return (
      <DemoListingDetail
        listing={selectedListing}
        favorite={progress.favoriteDemoIds.includes(selectedListing.id)}
        track={track}
        onToggleFavorite={toggleFavorite}
        onCheckout={() => open("checkout")}
        onBack={() => open("marketplace")}
      />
    );
  }
  if (screen === "checkout" && selectedListing) {
    return (
      <DemoCheckout
        listing={selectedListing}
        shippingFeeCents={shippingFeeCents}
        completed={progress.buyerCompleted}
        track={track}
        onCompleted={() =>
          updateProgress((current) => ({ ...current, buyerCompleted: true }))
        }
        onBack={() => open("detail")}
        onHub={() => open("hub")}
      />
    );
  }
  if (screen === "seller") {
    return (
      <SellDemo
        completed={progress.sellerCompleted}
        track={track}
        onCompleted={markSellerCompleted}
        onBack={() => open("hub")}
      />
    );
  }
  if (screen === "club") {
    return <ClubDemo track={track} onViewed={markClubViewed} onBack={() => open("hub")} />;
  }
  if (screen === "cellar") return <CellarPreview onBack={() => open("hub")} />;
  // Questionario QV2: PRE (Q1-Q13) prima della guida, POST (Q14-Q20) dopo beta_completed.
  if (screen === "pre-questionnaire") {
    return <QuestionnaireFlow phase="pre" state={questionnaire} onSave={saveQuestionnaire} onFinish={finishPreQuestionnaire} />;
  }
  if (screen === "post-questionnaire") {
    return <QuestionnaireFlow phase="post" state={questionnaire} onSave={saveQuestionnaire} onFinish={finishPostQuestionnaire} />;
  }
  if (screen === "ai") {
    return (
      <StaticAiPreview
        interested={progress.aiInterest}
        track={track}
        onViewed={() =>
          updateProgress((current) => ({ ...current, aiPreviewViewed: true }))
        }
        onInterest={() =>
          updateProgress((current) => ({ ...current, aiInterest: true }))
        }
        onBack={() => open("hub")}
      />
    );
  }
  return (
    <ValidationHub
      participantCode={session.participantCode}
      progress={progress}
      completing={completing}
      completionError={completionError}
      onOpen={open}
      onComplete={complete}
    />
  );
}
