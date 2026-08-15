"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { CheckCircle2, ChevronRight, Flag } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Textarea } from "@/components/ui/textarea";
import { reportReasons, reportTargetLabel, type ReportTargetType } from "@/data/moderation";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import { createSupabaseModerationService } from "@/services/phase9/supabase-moderation-service";

type Props = {
  targetType: ReportTargetType;
  targetId: string;
  targetLabel: string;
  clubSlug?: string;
  trigger?: ReactNode;
  variant?: "button" | "icon" | "menuitem";
};

const TriggerPredefinito = ({ variant }: { variant: Props["variant"] }) =>
  variant === "icon" ? (
    <button className="rounded-full p-2 text-muted-foreground hover:bg-secondary" aria-label="Segnala">
      <Flag className="h-4 w-4" />
    </button>
  ) : (
    <Button size="sm" variant="ghost" className="text-muted-foreground hover:text-bordeaux">
      <Flag className="h-4 w-4" /> Segnala
    </Button>
  );

const ReportSteps = ({
  step,
  reasons,
  reason,
  setReason,
  descrizione,
  setDescrizione,
}: {
  step: number;
  reasons: readonly string[];
  reason: string;
  setReason: (value: string) => void;
  descrizione: string;
  setDescrizione: (value: string) => void;
}) => (
  <>
    {step === 0 ? (
      <RadioGroup value={reason} onValueChange={setReason} className="space-y-2">
        {reasons.map((voce) => (
          <Label key={voce} className="flex cursor-pointer gap-2 rounded-xl border p-3">
            <RadioGroupItem value={voce} /> {voce}
          </Label>
        ))}
      </RadioGroup>
    ) : null}
    {step === 1 ? (
      <div className="space-y-2">
        <Label htmlFor="report-description">Descrizione facoltativa</Label>
        <Textarea id="report-description" maxLength={500} rows={5} value={descrizione} onChange={(e) => setDescrizione(e.target.value)} />
        <p className="text-xs text-muted-foreground">
          {descrizione.length}/500 caratteri. Gli allegati richiedono un percorso Storage non ancora disponibile e non vengono simulati.
        </p>
      </div>
    ) : null}
    {step === 2 ? (
      <div className="text-center">
        <CheckCircle2 className="mx-auto h-12 w-12 text-salvia" />
        <p className="mt-2 text-sm">La segnalazione è stata registrata.</p>
        <Link href="/segnalazioni" className="text-sm text-bordeaux underline">Segui lo stato</Link>
      </div>
    ) : null}
  </>
);

const ReportFooter = ({ step, loading, close, back, next, send }: { step: number; loading: boolean; close: () => void; back: () => void; next: () => void; send: () => void }) => (
  <DialogFooter className="gap-2 sm:justify-between">
    {step < 2 ? <Button variant="ghost" onClick={step === 0 ? close : back}>{step === 0 ? "Annulla" : "Indietro"}</Button> : null}
    {step === 0 ? <Button onClick={next} className="bg-bordeaux hover:bg-bordeaux/90">Continua <ChevronRight className="h-4 w-4" /></Button> : null}
    {step === 1 ? <Button onClick={send} disabled={loading} className="bg-bordeaux hover:bg-bordeaux/90">{loading ? "Invio…" : "Invia segnalazione"}</Button> : null}
    {step === 2 ? <Button onClick={close} className="ml-auto">Chiudi</Button> : null}
  </DialogFooter>
);

export const ReportDialog = ({
  targetType,
  targetId,
  targetLabel,
  clubSlug,
  trigger,
  variant = "button",
}: Props) => {
  const { authUser } = useVinea();
  const reasons = reportReasons[targetType];
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(0);
  const [reason, setReason] = useState(reasons[0]);
  const [descrizione, setDescrizione] = useState("");
  const [loading, setLoading] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  const reset = () => {
    setStep(0);
    setReason(reasons[0]);
    setDescrizione("");
    setLoading(false);
    setErrore(null);
  };

  const invia = async () => {
    if (!authUser) {
      setErrore("Accedi prima di inviare una segnalazione.");
      return;
    }
    setLoading(true);
    setErrore(null);
    try {
      await createSupabaseModerationService(getSupabaseClient()).segnala({
        targetType,
        targetId,
        targetLabel,
        reason,
        descrizione,
        foto: [],
        clubSlug,
        priorita: "bassa",
        reporter: authUser.email ?? "Utente",
        updatedAt: new Date().toISOString(),
        storia: [],
        noteInterne: [],
      });
      setStep(2);
    } catch (causa) {
      setErrore(causa instanceof Error ? causa.message : "Invio non riuscito. Riprova.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(valore) => {
        setOpen(valore);
        if (!valore) reset();
      }}
    >
      <DialogTrigger asChild>{trigger ?? <TriggerPredefinito variant={variant} />}</DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">
            {step === 2 ? "Segnalazione inviata" : "Segnala questo contenuto"}
          </DialogTitle>
        </DialogHeader>
        <p className="text-xs text-muted-foreground">
          {reportTargetLabel[targetType]} · {targetLabel}
        </p>
        <ReportSteps
          step={step}
          reasons={reasons}
          reason={reason}
          setReason={setReason}
          descrizione={descrizione}
          setDescrizione={setDescrizione}
        />
        {errore ? <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{errore}</p> : null}
        <ReportFooter
          step={step}
          loading={loading}
          close={() => setOpen(false)}
          back={() => setStep(0)}
          next={() => setStep(1)}
          send={() => void invia()}
        />
      </DialogContent>
    </Dialog>
  );
};
