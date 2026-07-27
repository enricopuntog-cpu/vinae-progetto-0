"use client";

import { useState, type ReactNode } from "react";
import { Flag, Camera, ChevronRight, CheckCircle2, AlertTriangle } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { reportReasons, reportTargetLabel, type ReportTargetType } from "@/data/moderation";
import { useVinea } from "@/lib/vinea-store";

type Props = {
  targetType: ReportTargetType;
  targetId: string;
  targetLabel: string;
  clubSlug?: string;
  trigger?: ReactNode;
  variant?: "button" | "icon" | "menuitem";
};

export function ReportDialog({
  targetType,
  targetId,
  targetLabel,
  clubSlug,
  trigger,
  variant = "button",
}: Props) {
  const { submitReport } = useVinea();
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(0);
  const reasons = reportReasons[targetType];
  const [reason, setReason] = useState<string>(reasons[0]);
  const [descr, setDescr] = useState("");
  const [foto, setFoto] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);

  function reset() {
    setStep(0);
    setReason(reasons[0]);
    setDescr("");
    setFoto([]);
    setLoading(false);
  }

  function addPhotoMock() {
    setFoto((p) => [...p, `mock-${p.length + 1}`]);
  }

  function invia() {
    setLoading(true);
    setTimeout(() => {
      submitReport({
        targetType,
        targetId,
        targetLabel,
        reason,
        descrizione: descr,
        foto,
        clubSlug,
      });
      setLoading(false);
      setStep(3);
    }, 700);
  }

  const defaultTrigger =
    variant === "icon" ? (
      <button
        className="rounded-full p-2 text-muted-foreground hover:bg-secondary hover:text-bordeaux"
        aria-label="Segnala"
      >
        <Flag className="h-4 w-4" />
      </button>
    ) : variant === "menuitem" ? (
      <button className="flex w-full items-center gap-2 px-2 py-1.5 text-sm hover:bg-secondary">
        <Flag className="h-4 w-4" /> Segnala
      </button>
    ) : (
      <Button size="sm" variant="ghost" className="text-muted-foreground hover:text-bordeaux">
        <Flag className="h-4 w-4" /> Segnala
      </Button>
    );

  return (
    <Dialog
      open={open}
      onOpenChange={(v) => {
        setOpen(v);
        if (!v) setTimeout(reset, 200);
      }}
    >
      <DialogTrigger asChild>{trigger ?? defaultTrigger}</DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">
            {step === 3 ? "Segnalazione inviata" : "Segnala questo contenuto"}
          </DialogTitle>
        </DialogHeader>

        <div className="rounded-xl border border-oro/40 bg-oro/10 p-3 text-xs">
          <p className="flex items-center gap-1 font-semibold text-oro">
            <AlertTriangle className="h-3.5 w-3.5" /> Modalità demo — non inviare dati reali
          </p>
          <p className="mt-1 text-antracite/80">Nessuna segnalazione viene trasmessa a terzi.</p>
        </div>

        <div className="mt-2 text-xs text-muted-foreground">
          {reportTargetLabel[targetType]} · <span className="text-antracite">{targetLabel}</span>
        </div>

        {/* Progress dots */}
        {step < 3 && (
          <div className="mt-1 flex gap-1">
            {[0, 1, 2].map((i) => (
              <span
                key={i}
                className={`h-1.5 flex-1 rounded-full ${i <= step ? "bg-bordeaux" : "bg-secondary"}`}
              />
            ))}
          </div>
        )}

        {step === 0 && (
          <div className="mt-3 space-y-3">
            <Label className="text-xs uppercase tracking-wide">Motivo</Label>
            <RadioGroup value={reason} onValueChange={setReason} className="space-y-2">
              {reasons.map((r) => (
                <label
                  key={r}
                  className={`flex cursor-pointer items-start gap-2 rounded-xl border p-3 text-sm ${
                    reason === r ? "border-bordeaux bg-bordeaux/5" : "border-border"
                  }`}
                >
                  <RadioGroupItem value={r} className="mt-0.5" />
                  <span>{r}</span>
                </label>
              ))}
            </RadioGroup>
          </div>
        )}

        {step === 1 && (
          <div className="mt-3 space-y-2">
            <Label className="text-xs uppercase tracking-wide">Descrizione (facoltativa)</Label>
            <Textarea
              value={descr}
              onChange={(e) => setDescr(e.target.value)}
              placeholder="Racconta cosa hai notato. Non condividere dati personali reali."
              rows={4}
            />
            <p className="text-[11px] text-muted-foreground">Massimo 500 caratteri.</p>
          </div>
        )}

        {step === 2 && (
          <div className="mt-3 space-y-3">
            <Label className="text-xs uppercase tracking-wide">Prove (placeholder demo)</Label>
            <p className="text-xs text-muted-foreground">
              In demo non si caricano foto reali: aggiungi allegati fittizi per completare il
              flusso.
            </p>
            <div className="flex flex-wrap gap-2">
              {foto.map((f) => (
                <div
                  key={f}
                  className="grid h-16 w-16 place-items-center rounded-lg border border-border bg-secondary text-[10px] text-muted-foreground"
                >
                  {f}
                </div>
              ))}
              <button
                type="button"
                onClick={addPhotoMock}
                className="grid h-16 w-16 place-items-center rounded-lg border-2 border-dashed border-border text-muted-foreground hover:border-bordeaux hover:text-bordeaux"
                aria-label="Aggiungi allegato mock"
              >
                <Camera className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-3 rounded-xl border border-border bg-secondary/40 p-3 text-xs">
              <p className="font-semibold">Riepilogo</p>
              <p className="mt-1">
                Motivo: <b>{reason}</b>
              </p>
              {descr && <p className="mt-1">Descrizione: {descr}</p>}
              <p className="mt-1">Allegati: {foto.length} (mock)</p>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="mt-3 space-y-2 text-center">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-salvia/15 text-salvia">
              <CheckCircle2 className="h-7 w-7" />
            </div>
            <p className="font-serif text-lg">Segnalazione inviata (demo)</p>
            <p className="text-sm text-muted-foreground">
              Potrai seguirne lo stato in <b>Le mie segnalazioni</b>.
            </p>
          </div>
        )}

        <DialogFooter className="mt-2 flex-col-reverse gap-2 sm:flex-row sm:justify-between">
          {step < 3 ? (
            <>
              <Button
                variant="ghost"
                onClick={() => (step === 0 ? setOpen(false) : setStep((s) => s - 1))}
                disabled={loading}
              >
                {step === 0 ? "Annulla" : "Indietro"}
              </Button>
              {step < 2 ? (
                <Button
                  className="bg-bordeaux hover:bg-bordeaux/90"
                  onClick={() => setStep((s) => s + 1)}
                >
                  Continua <ChevronRight className="h-4 w-4" />
                </Button>
              ) : (
                <Button
                  className="bg-bordeaux hover:bg-bordeaux/90"
                  onClick={invia}
                  disabled={loading}
                >
                  {loading ? "Invio…" : "Invia segnalazione"}
                </Button>
              )}
            </>
          ) : (
            <Button
              className="ml-auto bg-bordeaux hover:bg-bordeaux/90"
              onClick={() => setOpen(false)}
            >
              Chiudi
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}