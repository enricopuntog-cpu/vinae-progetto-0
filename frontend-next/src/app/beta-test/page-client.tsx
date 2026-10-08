"use client";

import Image from "next/image";
import {
  useCallback,
  useEffect,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react";
import { Button } from "@/components/ui/button";
import type { MarketValidationSession, MarketValidationQuestionnaireState } from "@/services/types";
import type { MarketValidationDemoListing } from "@/lib/market-validation/demo-data";
import {
  experienceAreasCount,
  experienceAreasDone,
  NEW_TESTER_LABEL,
  questionKey,
  questionnaireStage,
  type ExperienceAreasDone,
  type QuestionnaireAnswer,
} from "@/lib/market-validation/questionnaire";
import {
  clearMarketValidationSession,
  QV2_SESSION_STORAGE_KEY,
  readMarketValidationSession,
  writeMarketValidationSession,
  newMarketValidationCapability,
} from "@/lib/market-validation/persistence";
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
import { ExperienceHub } from "./_components/ExperienceHub";
import { ParticipantCodeBadge } from "./_components/ParticipantCodeBadge";
import { SellDemo } from "./_components/SellDemo";
import { StaticAiPreview } from "./_components/StaticAiPreview";
import type { MarketValidationScreen } from "./_components/ValidationHub";
import { ValidationComplete } from "./_components/ValidationComplete";
import { useMarketValidationTracker } from "./use-market-validation-tracker";

// Immagine approvata della Market Validation, versionata nel repository.
export const MARKET_VALIDATION_COVER = "/images/market-validation/vinea-market-validation-cover.webp";
const START_ERROR = "Non siamo riusciti ad assegnare il tuo codice test. Controlla la connessione e riprova.";

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
          setError(START_ERROR);
        }
      }
      if (active) setReady(true);
    };
    void resume();
    return () => { active = false; };
  }, []);

  // Fail closed: senza un codice assegnato o ripreso dal server il
  // questionario non parte e la landing mostra l'errore.
  const begin = async (fresh = false) => {
    if (pending) return;
    setPending(true);
    setError(null);
    const stored = fresh ? null : readMarketValidationSession(window.localStorage, QV2_SESSION_STORAGE_KEY);
    const capability = stored?.capability ?? newMarketValidationCapability();
    const result = await startQuestionnaire(capability);
    setPending(false);
    if (!result.ok || result.data.state.participant_code !== result.data.session.participantCode) {
      setError(START_ERROR);
      return;
    }
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
    <div className="mx-auto max-w-4xl">
      <section className="overflow-hidden rounded-3xl border border-border bg-card md:grid md:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
        <div className="relative aspect-[4/5] w-full bg-crema md:aspect-auto md:min-h-[36rem]">
          <Image
            src={MARKET_VALIDATION_COVER}
            alt="Vinea Wine Club — Aiutaci a creare il futuro di Vinea Wine Club. La tua opinione conta!"
            fill
            priority
            sizes="(min-width: 768px) 420px, 100vw"
            className="object-cover object-top md:object-contain md:object-center"
          />
        </div>
        <div className="p-5 md:flex md:flex-col md:justify-center md:p-8">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">Market Validation</p>
          <h1 className="mt-2 font-serif text-2xl font-semibold uppercase leading-tight md:text-4xl">Aiutaci a creare il futuro di Vinea</h1>
          <p className="mt-3 font-serif text-xl text-bordeaux md:text-2xl">La tua opinione conta.</p>
          <p className="mt-3 max-w-xl text-base leading-7 text-muted-foreground md:text-lg">
            Prova Vinea Wine Club e raccontaci cosa ne pensi. Bastano pochi minuti per aiutarci a costruire una piattaforma migliore.
          </p>
          <p className="mt-4 rounded-2xl border border-border bg-crema p-4 text-sm leading-6">
            Questa è una Beta di ricerca. Nessun pagamento, vendita o spedizione reale verrà effettuato.
          </p>
          {error && <p role="alert" className="mt-4 rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-base text-bordeaux">{error}</p>}
          <Button className="mt-5 min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90" disabled={!ready || pending} onClick={() => void begin()}>
            {pending ? "Avvio in corso…" : "INIZIA IL TEST"}
          </Button>
        </div>
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
  const [screen, setScreen] = useState<MarketValidationScreen | "previous-rule">(() => questionnaireStage(questionnaire));
  const [selectedListing, setSelectedListing] =
    useState<MarketValidationDemoListing | null>(null);
  // Aree il cui evento la porta server ha appena accettato, in attesa della
  // prossima lettura autoritativa: una card non si completa al semplice click.
  const [confirmed, setConfirmed] = useState<Partial<ExperienceAreasDone>>({});
  const [completing, setCompleting] = useState(false);
  const [completionError, setCompletionError] = useState<string | null>(null);
  const track = useMarketValidationTracker(session);
  const done = experienceAreasDone(questionnaire, confirmed);

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

  // Ricarica lo stato autoritativo dopo ogni cambio di fase.
  const refreshQuestionnaire = useCallback(async () => {
    const result = await readQuestionnaire(session.sessionId, session.capability);
    if (result.ok) onQuestionnaire(result.data.state);
    return result.ok ? result.data.state : null;
  }, [session, onQuestionnaire]);

  const open = (next: MarketValidationScreen) => {
    setCompletionError(null);
    setScreen(next);
    // Tornando all'hub lo stato delle cinque aree si rilegge dal server.
    if (next === "hub") void refreshQuestionnaire();
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

  const saveQuestionnaire = useCallback(async (questionNumber: number, answer: QuestionnaireAnswer) => {
    const result = await saveQuestionnaireAnswer(session.sessionId, session.capability, questionKey(questionNumber), answer);
    return result.ok;
  }, [session]);

  // PRE concluso: si apre l'hub con le cinque prove della Prova Vinea.
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

  // 5/5: il server registra beta_completed solo con le cinque aree (lo
  // ricontrolla la porta eventi) e il POST si apre sullo stato riletto.
  const continueToPost = async () => {
    if (completing || experienceAreasCount(done) < 5) return;
    setCompleting(true);
    setCompletionError(null);
    const result = await track("beta_completed", {}, "beta_completed");
    const state = result.ok ? await refreshQuestionnaire() : null;
    setCompleting(false);
    if (!state || !state.experience_completed || !state.core_completed) {
      setCompletionError(
        "Non siamo riusciti a confermare le cinque prove. Riprova: i progressi sono conservati.",
      );
      return;
    }
    setScreen("post-questionnaire");
  };

  const markBuyerCompleted = useCallback(() => {
    updateProgress((current) => ({ ...current, buyerCompleted: true }));
    setConfirmed((current) => ({ ...current, buyer: true }));
  }, [updateProgress]);

  // Lo step Vendi si chiude solo quando la demo interna ha registrato
  // `sell_completed` sulla conferma esplicita dell'ultimo passo.
  const markSellerCompleted = useCallback(() => {
    updateProgress((current) => ({ ...current, sellerCompleted: true }));
    setConfirmed((current) => ({ ...current, seller: true }));
  }, [updateProgress]);

  const markAiViewed = useCallback(() => {
    updateProgress((current) => ({ ...current, aiPreviewViewed: true }));
    setConfirmed((current) => ({ ...current, ai: true }));
  }, [updateProgress]);

  const markClubViewed = useCallback(() => {
    updateProgress((current) => ({ ...current, clubViewed: true }));
    setConfirmed((current) => ({ ...current, club: true }));
  }, [updateProgress]);

  // La Cantina conta solo quando la porta server accetta `cellar_viewed`.
  const markCellarViewed = useCallback(() => {
    setConfirmed((current) => ({ ...current, cellar: true }));
  }, []);

  const withCode = (content: ReactNode) => (
    <>
      <ParticipantCodeBadge code={session.participantCode} />
      {content}
    </>
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
  // Prova Vinea chiusa prima che le cinque aree diventassero obbligatorie: la
  // sessione non accetta più eventi, quindi si ricomincia con un nuovo codice.
  if (screen === "previous-rule") {
    return withCode(
      <section className="mx-auto max-w-xl rounded-3xl border border-border bg-card p-6 text-center md:p-9" aria-labelledby="previous-rule-title">
        <h1 id="previous-rule-title" className="font-serif text-3xl font-semibold">Il test è stato aggiornato</h1>
        <p className="mt-4 text-base leading-7 text-muted-foreground">
          Questo test è stato avviato con una versione precedente della Prova Vinea. Le risposte già date restano registrate con il codice {session.participantCode}.
          Per completare il test aggiornato, con tutte e 5 le prove, ricomincia con un nuovo codice.
        </p>
        <Button onClick={onNewTester} className="mt-6 min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90">
          {NEW_TESTER_LABEL}
        </Button>
      </section>,
    );
  }
  if (screen === "marketplace") {
    return withCode(
      <DemoMarketplace
        favorites={progress.favoriteDemoIds}
        track={track}
        onSelect={selectListing}
        onBack={() => open("hub")}
      />,
    );
  }
  if (screen === "detail" && selectedListing) {
    return withCode(
      <DemoListingDetail
        listing={selectedListing}
        favorite={progress.favoriteDemoIds.includes(selectedListing.id)}
        track={track}
        onToggleFavorite={toggleFavorite}
        onCheckout={() => open("checkout")}
        onBack={() => open("marketplace")}
      />,
    );
  }
  if (screen === "checkout" && selectedListing) {
    return withCode(
      <DemoCheckout
        listing={selectedListing}
        shippingFeeCents={shippingFeeCents}
        completed={progress.buyerCompleted}
        track={track}
        onCompleted={markBuyerCompleted}
        onBack={() => open("detail")}
        onHub={() => open("hub")}
      />,
    );
  }
  if (screen === "seller") {
    return withCode(
      <SellDemo
        completed={progress.sellerCompleted}
        track={track}
        onCompleted={markSellerCompleted}
        onBack={() => open("hub")}
      />,
    );
  }
  if (screen === "club") {
    return withCode(<ClubDemo track={track} onViewed={markClubViewed} onBack={() => open("hub")} />);
  }
  if (screen === "cellar") {
    return withCode(<CellarPreview track={track} onViewed={markCellarViewed} onBack={() => open("hub")} />);
  }
  // Questionario QV2: PRE (Q1-Q13) prima della Prova Vinea, POST (Q14-Q20) dopo le cinque prove.
  if (screen === "pre-questionnaire") {
    return withCode(<QuestionnaireFlow phase="pre" state={questionnaire} onSave={saveQuestionnaire} onFinish={finishPreQuestionnaire} />);
  }
  if (screen === "post-questionnaire") {
    return withCode(<QuestionnaireFlow phase="post" state={questionnaire} onSave={saveQuestionnaire} onFinish={finishPostQuestionnaire} />);
  }
  if (screen === "ai") {
    return withCode(
      <StaticAiPreview
        interested={progress.aiInterest}
        track={track}
        onViewed={markAiViewed}
        onInterest={() =>
          updateProgress((current) => ({ ...current, aiInterest: true }))
        }
        onBack={() => open("hub")}
      />,
    );
  }
  return withCode(
    <ExperienceHub
      done={done}
      completing={completing}
      completionError={completionError}
      onOpen={open}
      onContinue={continueToPost}
    />,
  );
}
