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
import {
  reportReasonLabel,
  reportReasons,
  reportTargetLabel,
  type ReportTargetType,
} from "@/data/moderation";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import { createSupabaseModerationService } from "@/services/phase9/supabase-moderation-service";

type Props = {
  targetType: ReportTargetType;
  targetId?: string;
  targetLabel: string;
  clubSlug?: string;
  trigger?: ReactNode;
  variant?: "button" | "icon" | "menuitem";
  onSuccess?: () => void;
};

const titoloPerTarget: Record<ReportTargetType, string> = {
  annuncio: "Segnala annuncio",
  profilo: "Segnala profilo",
  messaggio: "Segnala messaggio",
  conversazione: "Segnala conversazione",
  post: "Segnala post",
  commento: "Segnala commento",
  recensione: "Segnala recensione",
  club: "Segnala Club",
};

const erroreMediato = (causa: unknown) => {
  const messaggio = causa instanceof Error ? causa.message.toLowerCase() : "";
  if (messaggio.includes("gia una segnalazione") || messaggio.includes("già una segnalazione")) {
    return "Hai già una segnalazione aperta per questo contenuto.";
  }
  if (messaggio.includes("autenticazione") || messaggio.includes("accedi")) {
    return "Accedi prima di inviare una segnalazione.";
  }
  return "Invio non riuscito. Riprova più tardi.";
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

export const ReportDialog = ({
  targetType,
  targetId,
  targetLabel,
  clubSlug,
  trigger,
  variant = "button",
  onSuccess,
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
    if (loading) return;
    if (!authUser) {
      setErrore("Accedi prima di inviare una segnalazione.");
      return;
    }
    if ((targetType === "club" && !clubSlug?.trim()) || (targetType !== "club" && !targetId)) {
      setErrore("Questo contenuto non può essere segnalato.");
      return;
    }
    const client = getSupabaseClient();
    if (!client) {
      setErrore("Il servizio segnalazioni non è disponibile in questa configurazione.");
      return;
    }
    setLoading(true);
    setErrore(null);
    try {
      await createSupabaseModerationService(client).segnala({
        targetType,
        targetId: targetId ?? "",
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
      onSuccess?.();
    } catch (causa) {
      setErrore(erroreMediato(causa));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(valore) => {
        if (loading) return;
        setOpen(valore);
        if (!valore) reset();
      }}
    >
      <DialogTrigger asChild>{trigger ?? <TriggerPredefinito variant={variant} />}</DialogTrigger>
      <DialogContent className="max-w-lg" aria-describedby="report-target-description">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">
            {step === 2 ? "Segnalazione inviata" : titoloPerTarget[targetType]}
          </DialogTitle>
        </DialogHeader>
        <p id="report-target-description" className="text-xs text-muted-foreground">
          {reportTargetLabel[targetType]} · {targetLabel}
        </p>

        {step === 0 ? (
          <RadioGroup value={reason} onValueChange={setReason} className="space-y-2" aria-label="Motivo della segnalazione">
            {reasons.map((voce) => (
              <Label key={voce} className="flex cursor-pointer gap-2 rounded-xl border p-3">
                <RadioGroupItem value={voce} /> {reportReasonLabel[targetType]?.[voce] ?? voce}
              </Label>
            ))}
          </RadioGroup>
        ) : null}

        {step === 1 ? (
          <div className="space-y-2">
            <Label htmlFor="report-description">Descrizione facoltativa</Label>
            <Textarea
              id="report-description"
              maxLength={500}
              rows={5}
              value={descrizione}
              onChange={(evento) => setDescrizione(evento.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              {descrizione.length}/500 caratteri. Non inserire dati personali non necessari.
            </p>
          </div>
        ) : null}

        {step === 2 ? (
          <div className="text-center" role="status">
            <CheckCircle2 className="mx-auto h-12 w-12 text-salvia" />
            <p className="mt-2 text-sm">La segnalazione è stata registrata.</p>
            <Link href="/segnalazioni" className="text-sm text-bordeaux underline">
              Segui lo stato
            </Link>
          </div>
        ) : null}

        {errore ? (
          <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            {errore}
          </p>
        ) : null}

        <DialogFooter className="gap-2 sm:justify-between">
          {step < 2 ? (
            <Button
              variant="ghost"
              disabled={loading}
              onClick={step === 0 ? () => setOpen(false) : () => setStep(0)}
            >
              {step === 0 ? "Annulla" : "Indietro"}
            </Button>
          ) : null}
          {step === 0 ? (
            <Button onClick={() => setStep(1)} className="bg-bordeaux hover:bg-bordeaux/90">
              Continua <ChevronRight className="h-4 w-4" />
            </Button>
          ) : null}
          {step === 1 ? (
            <Button
              onClick={() => void invia()}
              disabled={loading}
              className="bg-bordeaux hover:bg-bordeaux/90"
            >
              {loading ? "Invio…" : "Invia segnalazione"}
            </Button>
          ) : null}
          {step === 2 ? <Button onClick={() => setOpen(false)} className="ml-auto">Chiudi</Button> : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
