"use client";

import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
  type ReactNode,
} from "react";
import { CheckCircle2, ImagePlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import {
  EMPTY_MARKET_VALIDATION_SELLER_DRAFT,
  marketValidationPhotoAccepted,
  revokeMarketValidationPhotoUrl,
  validateMarketValidationSellerDraft,
  type MarketValidationSellerDraft,
} from "@/lib/market-validation/mv2-flow";
import type { MarketValidationTrack } from "./types";

export function DemoSellerFlow({
  completed,
  track,
  onCompleted,
  onBack,
}: {
  completed: boolean;
  track: MarketValidationTrack;
  onCompleted: () => void;
  onBack: () => void;
}) {
  const [draft, setDraft] = useState<MarketValidationSellerDraft>(EMPTY_MARKET_VALIDATION_SELLER_DRAFT);
  const [errors, setErrors] = useState<ReturnType<typeof validateMarketValidationSellerDraft>>({});
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const photoUrlRef = useRef<string | null>(null);

  useEffect(() => {
    void track("sell_started", {}, "sell_started");
  }, [track]);

  useEffect(() => () => {
    revokeMarketValidationPhotoUrl(photoUrlRef.current);
  }, []);

  const update = (field: keyof MarketValidationSellerDraft, value: string) => {
    setDraft((current) => ({ ...current, [field]: value }));
    setErrors((current) => ({ ...current, [field]: undefined }));
    setSubmitError(null);
  };

  const selectPhoto = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (!marketValidationPhotoAccepted(file)) {
      setPhotoError("Scegli un file JPG, PNG o WebP fino a 10 MB.");
      return;
    }
    revokeMarketValidationPhotoUrl(photoUrlRef.current);
    const nextUrl = URL.createObjectURL(file);
    photoUrlRef.current = nextUrl;
    setPhotoUrl(nextUrl);
    setPhotoError(null);
    void track("sell_photo_selected", {}, "sell_photo_selected");
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;
    const nextErrors = validateMarketValidationSellerDraft(draft);
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    setPending(true);
    setSubmitError(null);
    const result = await track("sell_completed", {}, "sell_completed");
    setPending(false);
    if (!result.ok) {
      setSubmitError("Non siamo riusciti a registrare la simulazione. I dati restano qui per riprovare.");
      return;
    }
    revokeMarketValidationPhotoUrl(photoUrlRef.current);
    photoUrlRef.current = null;
    setPhotoUrl(null);
    setDraft(EMPTY_MARKET_VALIDATION_SELLER_DRAFT);
    onCompleted();
  };

  if (completed) {
    return (
      <section className="mx-auto max-w-xl rounded-3xl border border-salvia/40 bg-card p-6 text-center md:p-9" aria-labelledby="seller-success-title">
        <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-salvia/15 text-salvia"><CheckCircle2 className="h-7 w-7" aria-hidden /></span>
        <h1 id="seller-success-title" className="mt-4 font-serif text-3xl font-semibold">Vendita simulata</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">Il percorso venditore è completato. Nessun annuncio è stato pubblicato e nessuna foto è stata caricata.</p>
        <Button type="button" className="mt-6 min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" onClick={onBack}>Torna al test</Button>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-xl space-y-5" aria-labelledby="seller-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-bordeaux">Simulazione venditore</p>
          <h1 id="seller-title" className="mt-1 font-serif text-3xl font-semibold">Proponi una bottiglia</h1>
          <p className="mt-2 text-sm text-muted-foreground">I dati restano in memoria soltanto finché compili questa schermata.</p>
        </div>
        <Button type="button" variant="outline" className="min-h-11 shrink-0" onClick={onBack}>Hub</Button>
      </div>

      <form className="space-y-5 rounded-3xl border border-border bg-card p-5 md:p-8" onSubmit={submit} noValidate>
        <Field id="seller-producer" label="Produttore" error={errors.producer}>
          <Input id="seller-producer" className="min-h-11" value={draft.producer} onChange={(event) => update("producer", event.target.value)} aria-invalid={Boolean(errors.producer)} />
        </Field>
        <Field id="seller-wine" label="Nome del vino" error={errors.wine}>
          <Input id="seller-wine" className="min-h-11" value={draft.wine} onChange={(event) => update("wine", event.target.value)} aria-invalid={Boolean(errors.wine)} />
        </Field>
        <Field id="seller-vintage" label="Annata" error={errors.vintage}>
          <Input id="seller-vintage" className="min-h-11" inputMode="numeric" maxLength={4} value={draft.vintage} onChange={(event) => update("vintage", event.target.value)} aria-invalid={Boolean(errors.vintage)} />
        </Field>
        <Field id="seller-format" label="Formato" error={errors.format}>
          <Select value={draft.format} onValueChange={(value) => update("format", value)}>
            <SelectTrigger id="seller-format" className="min-h-11" aria-invalid={Boolean(errors.format)}><SelectValue placeholder="Seleziona" /></SelectTrigger>
            <SelectContent><SelectItem value="0,75 L">0,75 L</SelectItem><SelectItem value="1,5 L">1,5 L</SelectItem></SelectContent>
          </Select>
        </Field>
        <Field id="seller-condition" label="Condizione" error={errors.condition}>
          <Select value={draft.condition} onValueChange={(value) => update("condition", value)}>
            <SelectTrigger id="seller-condition" className="min-h-11" aria-invalid={Boolean(errors.condition)}><SelectValue placeholder="Seleziona" /></SelectTrigger>
            <SelectContent><SelectItem value="Ottima">Ottima</SelectItem><SelectItem value="Buona">Buona</SelectItem></SelectContent>
          </Select>
        </Field>
        <Field id="seller-price" label="Prezzo desiderato (€)" error={errors.desiredPrice}>
          <Input id="seller-price" className="min-h-11" inputMode="decimal" value={draft.desiredPrice} onChange={(event) => update("desiredPrice", event.target.value)} aria-invalid={Boolean(errors.desiredPrice)} />
        </Field>
        <div className="space-y-2">
          <Label htmlFor="seller-notes">Note facoltative</Label>
          <Textarea id="seller-notes" className="min-h-24" maxLength={500} value={draft.notes} onChange={(event) => update("notes", event.target.value)} />
        </div>

        <div className="space-y-3 rounded-2xl border border-dashed border-border p-4">
          <div>
            <Label htmlFor="seller-photo">Foto facoltativa</Label>
            <p className="mt-1 text-xs text-muted-foreground">Solo anteprima locale JPG, PNG o WebP. Zero upload.</p>
          </div>
          <Input id="seller-photo" type="file" accept="image/jpeg,image/png,image/webp" className="min-h-11" onChange={selectPhoto} />
          {photoUrl ? (
            // Blob locale: next/image non accetta questo protocollo e nessun byte lascia il browser.
            // eslint-disable-next-line @next/next/no-img-element
            <img src={photoUrl} alt="Anteprima locale della bottiglia scelta" className="max-h-64 w-full rounded-xl object-contain bg-secondary" />
          ) : (
            <div className="flex min-h-28 items-center justify-center gap-2 rounded-xl bg-secondary/60 text-sm text-muted-foreground"><ImagePlus className="h-5 w-5" aria-hidden /> Nessuna foto selezionata</div>
          )}
          {photoError && <p role="alert" className="text-sm text-bordeaux">{photoError}</p>}
        </div>

        {submitError && <p role="alert" className="rounded-xl border border-bordeaux/30 bg-bordeaux/5 p-3 text-sm text-bordeaux">{submitError}</p>}
        <Button type="submit" className="min-h-12 w-full bg-bordeaux hover:bg-bordeaux/90" disabled={pending}>{pending ? "Registrazione in corso…" : "Completa vendita simulata"}</Button>
      </form>
    </section>
  );
}

function Field({ id, label, error, children }: { id: string; label: string; error?: string; children: ReactNode }) {
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      {children}
      {error && <p id={`${id}-error`} role="alert" className="text-sm text-bordeaux">{error}</p>}
    </div>
  );
}
