"use client";

import { useEffect, useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  parseMarketValidationParticipantCode,
  type MarketValidationSession,
} from "@/lib/market-validation/contract";
import {
  clearMarketValidationSession,
  newMarketValidationCapability,
  readMarketValidationSession,
  writeMarketValidationSession,
} from "@/lib/market-validation/persistence";
import { startMarketValidationSession } from "./actions";

export default function BetaTestPageClient() {
  const [participantCode, setParticipantCode] = useState("");
  const [session, setSession] = useState<MarketValidationSession | null>(null);
  const [ready, setReady] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const resume = async () => {
      const stored = readMarketValidationSession(window.localStorage);
      if (!stored) {
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
        setSession(result.data);
      } else {
        clearMarketValidationSession(window.localStorage);
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
      if (stored) clearMarketValidationSession(window.localStorage);
      setError(result.error);
      return;
    }

    writeMarketValidationSession(window.localStorage, result.data);
    setSession(result.data);
    setParticipantCode(result.data.participantCode);
  };

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <section className="rounded-3xl border border-border bg-card p-5 md:p-8">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">
              Market Validation
            </p>
            <h1 className="mt-2 font-serif text-3xl font-semibold md:text-4xl">Prova Vinea</h1>
          </div>
          {session && (
            <span className="rounded-full border border-bordeaux/20 bg-bordeaux/5 px-3 py-1 text-xs font-semibold text-bordeaux">
              Test {session.participantCode}
            </span>
          )}
        </div>

        <p className="mt-5 max-w-xl whitespace-pre-line text-sm leading-6 text-muted-foreground md:text-base">
          {`Stai partecipando alla fase di Beta Testing di Vinea Wine Club.
Puoi esplorare il marketplace, simulare un acquisto e provare
a mettere in vendita una bottiglia.
Nessuna operazione comporterà un pagamento,
una vendita o una spedizione reale.`}
        </p>

        {session ? (
          <div className="mt-6 rounded-2xl border border-border bg-crema p-4">
            <p className="font-medium text-antracite">Sessione di test pronta.</p>
            <p className="mt-1 text-sm text-muted-foreground">
              MV1 prepara soltanto l&apos;ingresso e la sessione anonima. Le esperienze guidate
              arriveranno nelle fasi successive del programma.
            </p>
          </div>
        ) : (
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
                aria-describedby={error ? "participant-code-error" : "participant-code-help"}
                disabled={!ready || pending}
              />
              <p id="participant-code-help" className="text-xs text-muted-foreground">
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
              className="w-full bg-bordeaux hover:bg-bordeaux/90"
              disabled={!ready || pending}
            >
              {pending ? "Avvio in corso…" : "Inizia il test"}
            </Button>
          </form>
        )}
      </section>
    </div>
  );
}
