"use client";

import {
  useCallback,
  useEffect,
  useState,
  type Dispatch,
  type FormEvent,
  type SetStateAction,
} from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  parseMarketValidationParticipantCode,
  type MarketValidationSession,
} from "@/lib/market-validation/contract";
import type { MarketValidationDemoListing } from "@/lib/market-validation/demo-data";
import {
  clearMarketValidationSession,
  newMarketValidationCapability,
  readMarketValidationSession,
  writeMarketValidationSession,
} from "@/lib/market-validation/persistence";
import { marketValidationCanComplete } from "@/lib/market-validation/mv2-flow";
import {
  clearMarketValidationProgress,
  INITIAL_MARKET_VALIDATION_PROGRESS,
  restoreMarketValidationProgress,
  writeMarketValidationProgress,
  type MarketValidationProgress,
} from "@/lib/market-validation/progress";
import { startMarketValidationSession } from "./actions";
import { CellarPreview } from "./_components/CellarPreview";
import { ClubDemo } from "./_components/ClubDemo";
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

export default function LegacyBetaTestPageClient({
  shippingFeeCents,
}: {
  shippingFeeCents: number;
}) {
  const [participantCode, setParticipantCode] = useState("");
  const [session, setSession] = useState<MarketValidationSession | null>(null);
  const [progress, setProgress] = useState<MarketValidationProgress>(
    INITIAL_MARKET_VALIDATION_PROGRESS,
  );
  const [ready, setReady] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const resume = async () => {
      const stored = readMarketValidationSession(window.localStorage);
      if (!stored) {
        clearMarketValidationProgress(window.localStorage);
        if (active) setReady(true);
        return;
      }

      if (active) setParticipantCode(stored.participantCode);
      const result = await startMarketValidationSession(
        stored.participantCode,
        stored.capability,
      );
      if (!active) return;

      if (result.ok) {
        writeMarketValidationSession(window.localStorage, result.data);
        setProgress(
          restoreMarketValidationProgress(
            window.localStorage,
            result.data.resumed,
          ),
        );
        setSession(result.data);
      } else {
        clearMarketValidationSession(window.localStorage);
        clearMarketValidationProgress(window.localStorage);
        setError(result.error);
      }
      setReady(true);
    };

    void resume();
    return () => {
      active = false;
    };
  }, []);

  const begin = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;

    const canonical = parseMarketValidationParticipantCode(participantCode);
    if (!canonical) {
      setError("Inserisci un codice da V001 a V999.");
      return;
    }

    const stored = readMarketValidationSession(window.localStorage);
    const capability =
      stored?.participantCode === canonical
        ? stored.capability
        : newMarketValidationCapability();

    setPending(true);
    setError(null);
    const result = await startMarketValidationSession(canonical, capability);
    setPending(false);
    if (!result.ok) {
      clearMarketValidationSession(window.localStorage);
      clearMarketValidationProgress(window.localStorage);
      setError(result.error);
      return;
    }

    writeMarketValidationSession(window.localStorage, result.data);
    setProgress(
      restoreMarketValidationProgress(window.localStorage, result.data.resumed),
    );
    setSession(result.data);
    setParticipantCode(result.data.participantCode);
  };

  if (session) {
    return (
      <MarketValidationExperience
        session={session}
        shippingFeeCents={shippingFeeCents}
        progress={progress}
        onProgress={setProgress}
      />
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <section className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-bordeaux">
            Market Validation
          </p>
          <h1 className="mt-2 font-serif text-3xl font-semibold md:text-4xl">
            Prova Vinea
          </h1>
        </div>

        <p className="mt-5 max-w-xl whitespace-pre-line text-base leading-7 text-muted-foreground md:text-lg">
          {`Stai partecipando alla fase di Beta Testing di Vinea Wine Club.
In due step proverai ad acquistare una bottiglia e ad aggiungerne
una tua, poi potrai scoprire AI, Club e Cantina.
Tutto si svolge qui ed è una simulazione: nessun pagamento,
ordine, annuncio o spedizione reale.`}
        </p>

        <form className="mt-6 max-w-sm space-y-4" onSubmit={begin}>
          <div className="space-y-2">
            <Label htmlFor="participant-code">Codice partecipante</Label>
            <Input
              id="participant-code"
              value={participantCode}
              onChange={(event) => {
                setParticipantCode(event.target.value.toUpperCase());
                setError(null);
              }}
              placeholder="V017"
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              inputMode="text"
              maxLength={4}
              aria-describedby={
                error ? "participant-code-error" : "participant-code-help"
              }
              disabled={!ready || pending}
              className="min-h-11"
            />
            <p id="participant-code-help" className="text-sm text-muted-foreground">
              Usa il codice V001–V999 ricevuto per il test.
            </p>
          </div>

          {error && (
            <p
              id="participant-code-error"
              role="alert"
              className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux"
            >
              {error}
            </p>
          )}

          <Button
            type="submit"
            className="min-h-12 w-full bg-bordeaux text-base hover:bg-bordeaux/90"
            disabled={!ready || pending}
          >
            {pending ? "Avvio in corso…" : "Inizia il test"}
          </Button>
        </form>
      </section>
    </div>
  );
}

function MarketValidationExperience({
  session,
  shippingFeeCents,
  progress,
  onProgress,
}: {
  session: MarketValidationSession;
  shippingFeeCents: number;
  progress: MarketValidationProgress;
  onProgress: Dispatch<SetStateAction<MarketValidationProgress>>;
}) {
  const [screen, setScreen] = useState<MarketValidationScreen>("hub");
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

  useEffect(() => {
    if (screen === "complete") {
      clearMarketValidationSession(window.localStorage);
      clearMarketValidationProgress(window.localStorage);
      return;
    }
    writeMarketValidationProgress(window.localStorage, progress);
  }, [progress, screen]);

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
    // Prima monta lo stato finale in memoria; l'effect terminale pulisce poi le chiavi.
    setScreen("complete");
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

  if (screen === "complete") return <ValidationComplete />;
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
  // La Cantina è una scoperta facoltativa: nessun evento, nessun progresso.
  if (screen === "cellar") return <CellarPreview onBack={() => open("hub")} />;
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
