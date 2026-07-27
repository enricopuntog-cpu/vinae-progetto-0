import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import {
  ShieldCheck,
  IdCard,
  Camera,
  ArrowRight,
  ArrowLeft,
  Info,
  Check,
  Clock,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Progress } from "@/components/ui/progress";
import { useVinea } from "@/lib/vinea-store";
import { IdentityBadge, SellerBadge, AgeBadge } from "@/components/vinea/VerificationBadges";
import { toast } from "sonner";

export const Route = createFileRoute("/verifica-venditore")({
  head: () => ({
    meta: [
      { title: "Verifica venditore — Vinea" },
      {
        name: "description",
        content: "Verifica identità simulata per abilitare la vendita su Vinea.",
      },
      { property: "og:title", content: "Verifica venditore — Vinea" },
      {
        property: "og:description",
        content: "Percorso demo di verifica identità. Nessun documento reale.",
      },
    ],
  }),
  component: VerificaVenditore,
});

const STEPS = ["intro", "consenso", "documento", "selfie", "revisione", "esito"] as const;
type Step = (typeof STEPS)[number];

function VerificaVenditore() {
  const nav = useNavigate();
  const {
    identityStatus,
    sellerStatus,
    ageStatus,
    startIdentityVerification,
    completeIdentityVerification,
  } = useVinea();
  const [step, setStep] = useState<Step>(
    identityStatus === "verificata"
      ? "esito"
      : identityStatus === "in_verifica"
        ? "revisione"
        : "intro",
  );
  const [consenso, setConsenso] = useState(false);
  const [docSel, setDocSel] = useState<"cid" | "patente" | "passaporto" | null>(null);
  const [selfieOk, setSelfieOk] = useState(false);
  const idx = STEPS.indexOf(step);
  const perc = ((idx + 1) / STEPS.length) * 100;

  const go = (s: Step) => {
    setStep(s);
    if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const inviaRevisione = () => {
    startIdentityVerification();
    go("revisione");
  };

  const simulaEsito = (esito: "verificata" | "rifiutata") => {
    completeIdentityVerification(esito);
    go("esito");
  };

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-3 text-xs text-antracite/80">
        <span className="mr-1 rounded-full bg-oro/30 px-2 py-0.5 font-semibold text-antracite">
          Modalità demo
        </span>
        Nessun documento reale viene caricato, nessun servizio KYC coinvolto.
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="font-serif text-2xl md:text-3xl">Verifica venditore</h1>
        <div className="flex flex-wrap gap-1.5">
          <AgeBadge status={ageStatus} />
          <IdentityBadge status={identityStatus} />
          <SellerBadge status={sellerStatus} />
        </div>
      </div>

      <Progress value={perc} className="h-1.5" />

      <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
        {step === "intro" && (
          <div>
            <p className="font-serif text-xl">Perché serve la verifica?</p>
            <p className="mt-2 text-sm text-muted-foreground">
              Prima di vendere o ricevere denaro su Vinea verifichiamo la tua identità per
              proteggere acquirenti e venditori.
            </p>
            <ul className="mt-4 space-y-2 text-sm">
              {[
                "Conferma della maggiore età",
                "Riduzione di frodi e annunci falsi",
                'Sblocco del badge "Venditore verificato"',
                "Abilitazione ai pagamenti simulati",
              ].map((s) => (
                <li key={s} className="flex items-center gap-2">
                  <Check className="h-4 w-4 text-salvia" /> {s}
                </li>
              ))}
            </ul>
            <Nav onNext={() => go("consenso")} nextLabel="Iniziamo" />
          </div>
        )}

        {step === "consenso" && (
          <div>
            <p className="font-serif text-xl">Consenso al trattamento</p>
            <p className="mt-2 text-sm text-muted-foreground">
              In una versione reale confermeresti il consenso al trattamento dei dati per la
              verifica KYC. In questa demo è simbolico.
            </p>
            <label className="mt-4 flex items-start gap-2 text-sm">
              <Checkbox
                checked={consenso}
                onCheckedChange={(v) => setConsenso(v === true)}
                className="mt-0.5"
              />
              <span>Accetto il trattamento dei dati per la verifica identità (demo).</span>
            </label>
            <Nav
              onPrev={() => go("intro")}
              onNext={() => go("documento")}
              nextDisabled={!consenso}
            />
          </div>
        )}

        {step === "documento" && (
          <div>
            <p className="font-serif text-xl">Documento di identità</p>
            <p className="mt-2 text-sm text-muted-foreground">
              Seleziona il tipo di documento. <b>Non caricare file reali:</b> useremo un'immagine
              placeholder.
            </p>
            <div className="mt-4 grid gap-2 sm:grid-cols-3">
              {[
                { k: "cid" as const, l: "Carta d'identità" },
                { k: "patente" as const, l: "Patente" },
                { k: "passaporto" as const, l: "Passaporto" },
              ].map((o) => (
                <button
                  key={o.k}
                  onClick={() => setDocSel(o.k)}
                  aria-pressed={docSel === o.k}
                  className={`flex min-w-0 items-center gap-2 rounded-xl border px-3 py-3 text-left text-sm transition ${docSel === o.k ? "border-bordeaux bg-bordeaux/5" : "border-border bg-card hover:border-bordeaux/40"}`}
                >
                  <IdCard className="h-4 w-4 shrink-0 text-bordeaux" />{" "}
                  <span className="truncate">{o.l}</span>
                </button>
              ))}
            </div>

            {docSel && (
              <div className="mt-5 grid gap-3 sm:grid-cols-2">
                {["Fronte", "Retro"].map((l) => (
                  <div
                    key={l}
                    className="rounded-2xl border-2 border-dashed border-border bg-secondary p-6 text-center"
                  >
                    <IdCard className="mx-auto h-8 w-8 text-muted-foreground" />
                    <p className="mt-2 text-sm font-medium">{l} — placeholder</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      Nessun caricamento reale disponibile in demo
                    </p>
                    <Button
                      variant="outline"
                      className="mt-3 text-xs"
                      onClick={() => toast("Placeholder simulato ✓")}
                    >
                      Usa immagine di esempio
                    </Button>
                  </div>
                ))}
              </div>
            )}

            <div className="mt-4 rounded-xl border border-border bg-crema p-3 text-xs text-muted-foreground">
              <Info className="mr-1 inline h-3.5 w-3.5" /> In questa demo non si accede alla
              fotocamera né a file locali.
            </div>

            <Nav onPrev={() => go("consenso")} onNext={() => go("selfie")} nextDisabled={!docSel} />
          </div>
        )}

        {step === "selfie" && (
          <div>
            <p className="font-serif text-xl">Selfie di conferma</p>
            <p className="mt-2 text-sm text-muted-foreground">
              In una versione reale scatteresti un selfie per confrontare il volto con il documento.
              Qui simula il passaggio.
            </p>
            <div className="mt-4 grid place-items-center rounded-2xl border-2 border-dashed border-border bg-secondary p-8 text-center">
              <Camera className="h-10 w-10 text-muted-foreground" />
              <p className="mt-2 text-sm font-medium">Selfie — placeholder</p>
              <Button
                variant={selfieOk ? "default" : "outline"}
                className={`mt-3 ${selfieOk ? "bg-salvia hover:bg-salvia/90" : ""}`}
                onClick={() => setSelfieOk(true)}
              >
                {selfieOk ? "Selfie simulato ✓" : "Simula scatto"}
              </Button>
            </div>
            <Nav
              onPrev={() => go("documento")}
              onNext={inviaRevisione}
              nextDisabled={!selfieOk}
              nextLabel="Invia in verifica"
            />
          </div>
        )}

        {step === "revisione" && (
          <div className="text-center">
            <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-oro/15">
              <Clock className="h-8 w-8 text-oro" />
            </div>
            <p className="mt-4 font-serif text-xl">In revisione</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Riceverai un esito entro 24–48h (demo). Puoi continuare a esplorare Vinea.
            </p>
            <div className="mt-6 grid gap-2 sm:grid-cols-2">
              <Button
                variant="outline"
                onClick={() => simulaEsito("rifiutata")}
                className="min-w-0"
              >
                Simula esito: rifiutata
              </Button>
              <Button
                onClick={() => simulaEsito("verificata")}
                className="min-w-0 bg-bordeaux hover:bg-bordeaux/90"
              >
                Simula esito: verificata
              </Button>
            </div>
          </div>
        )}

        {step === "esito" && (
          <div className="text-center">
            {identityStatus === "verificata" ? (
              <>
                <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-salvia/15">
                  <ShieldCheck className="h-8 w-8 text-salvia" />
                </div>
                <p className="mt-4 font-serif text-2xl">Identità verificata</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Il badge <b>Venditore verificato</b> è ora attivo sui tuoi annunci.
                </p>
                <div className="mt-6 flex flex-wrap justify-center gap-2">
                  <Button variant="outline" onClick={() => nav({ to: "/profilo" })}>
                    Vai al profilo
                  </Button>
                  <Button
                    className="bg-bordeaux hover:bg-bordeaux/90"
                    onClick={() => nav({ to: "/vendi", search: { mode: "sell" } })}
                  >
                    Metti in vendita
                  </Button>
                </div>
              </>
            ) : identityStatus === "rifiutata" ? (
              <>
                <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
                  <Info className="h-8 w-8 text-bordeaux" />
                </div>
                <p className="mt-4 font-serif text-2xl">Verifica non riuscita</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Ripeti la procedura assicurandoti che il documento sia leggibile (demo).
                </p>
                <Button
                  className="mt-6 bg-bordeaux hover:bg-bordeaux/90"
                  onClick={() => go("intro")}
                >
                  Riprova
                </Button>
              </>
            ) : (
              <>
                <p className="font-serif text-xl">Nessuna verifica in corso</p>
                <Button
                  className="mt-4 bg-bordeaux hover:bg-bordeaux/90"
                  onClick={() => go("intro")}
                >
                  Avvia verifica
                </Button>
              </>
            )}
            <p className="mt-6 text-xs text-muted-foreground">
              Torna al{" "}
              <Link to="/profilo" className="text-bordeaux hover:underline">
                profilo
              </Link>{" "}
              o esplora la{" "}
              <Link to="/" className="text-bordeaux hover:underline">
                home
              </Link>
              .
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function Nav({
  onPrev,
  onNext,
  nextLabel = "Continua",
  nextDisabled,
}: {
  onPrev?: () => void;
  onNext?: () => void;
  nextLabel?: string;
  nextDisabled?: boolean;
}) {
  return (
    <div className="mt-6 flex items-center justify-between gap-2">
      {onPrev ? (
        <Button variant="ghost" onClick={onPrev}>
          <ArrowLeft className="h-4 w-4" /> Indietro
        </Button>
      ) : (
        <span />
      )}
      {onNext && (
        <Button
          onClick={onNext}
          disabled={nextDisabled}
          className="bg-bordeaux hover:bg-bordeaux/90"
        >
          {nextLabel} <ArrowRight className="h-4 w-4" />
        </Button>
      )}
    </div>
  );
}
