import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState, useMemo } from "react";
import { z } from "zod";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Mail,
  ShieldAlert,
  Sparkles,
  Info,
  RefreshCw,
  User as UserIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Progress } from "@/components/ui/progress";
import { useVinea } from "@/lib/vinea-store";
import {
  obiettiviLabels,
  regioniItaliane,
  tipologieVino,
  fascePrezzo,
  clubSuggeriti,
  esperienzaLabels,
  type Obiettivo,
  type Esperienza,
} from "@/data/onboarding";
import { toast } from "sonner";

const searchSchema = z.object({
  step: z
    .enum(["benvenuto", "obiettivi", "registrazione", "verifica", "preferenze", "profilo", "fine"])
    .optional(),
});

export const Route = createFileRoute("/onboarding")({
  validateSearch: searchSchema,
  head: () => ({
    meta: [
      { title: "Benvenuto — Vinea Wine Club" },
      {
        name: "description",
        content: "Crea il tuo account demo Vinea in pochi passi: obiettivi, preferenze, profilo.",
      },
      { property: "og:title", content: "Onboarding — Vinea Wine Club" },
      { property: "og:description", content: "Modalità demo. Nessun dato reale viene raccolto." },
    ],
  }),
  component: Onboarding,
});

const STEPS = [
  "benvenuto",
  "obiettivi",
  "registrazione",
  "verifica",
  "preferenze",
  "profilo",
  "fine",
] as const;
type Step = (typeof STEPS)[number];

function Onboarding() {
  const nav = useNavigate();
  const search = Route.useSearch();
  const [step, setStep] = useState<Step>((search.step as Step) ?? "benvenuto");
  const stepIdx = STEPS.indexOf(step);
  const progress = ((stepIdx + 1) / STEPS.length) * 100;

  const go = (s: Step) => {
    setStep(s);
    if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
  };
  const next = () => go(STEPS[Math.min(STEPS.length - 1, stepIdx + 1)]);
  const prev = () => go(STEPS[Math.max(0, stepIdx - 1)]);

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="rounded-2xl border border-oro/40 bg-oro/10 p-3 text-xs text-antracite/80">
        <span className="mr-1 rounded-full bg-oro/30 px-2 py-0.5 font-semibold text-antracite">
          Modalità demo
        </span>
        Nessun dato reale viene raccolto o salvato. Puoi uscire in qualsiasi momento.
      </div>

      <div>
        <p className="text-xs uppercase tracking-wide text-muted-foreground">
          Passo {stepIdx + 1} di {STEPS.length}
        </p>
        <Progress value={progress} className="mt-2 h-1.5" />
      </div>

      {step === "benvenuto" && <Benvenuto onNext={next} onSkip={() => nav({ to: "/" })} />}
      {step === "obiettivi" && <Obiettivi onNext={next} onPrev={prev} />}
      {step === "registrazione" && <Registrazione onNext={next} onPrev={prev} />}
      {step === "verifica" && <Verifica onNext={next} onPrev={prev} />}
      {step === "preferenze" && <Preferenze onNext={next} onPrev={prev} />}
      {step === "profilo" && <Profilo onNext={next} onPrev={prev} />}
      {step === "fine" && (
        <Fine
          onDone={() => nav({ to: "/home" })}
          onVerifica={() => nav({ to: "/verifica-venditore" })}
        />
      )}
    </div>
  );
}

function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-3xl border border-border bg-card p-5 md:p-8">
      <h1 className="font-serif text-2xl md:text-3xl">{title}</h1>
      {subtitle && <p className="mt-2 text-sm text-muted-foreground">{subtitle}</p>}
      <div className="mt-5">{children}</div>
    </div>
  );
}

function BottomBar({
  onPrev,
  onNext,
  nextLabel = "Continua",
  skipLabel,
  onSkip,
  nextDisabled,
}: {
  onPrev?: () => void;
  onNext?: () => void;
  nextLabel?: string;
  skipLabel?: string;
  onSkip?: () => void;
  nextDisabled?: boolean;
}) {
  return (
    <div className="sticky bottom-16 z-30 -mx-4 mt-6 flex items-center justify-between gap-2 border-t border-border bg-crema/95 p-3 backdrop-blur md:static md:mx-0 md:border-0 md:bg-transparent md:p-0">
      {onPrev ? (
        <Button variant="ghost" onClick={onPrev} className="min-w-0">
          <ArrowLeft className="h-4 w-4" /> Indietro
        </Button>
      ) : (
        <span />
      )}
      <div className="flex items-center gap-2">
        {skipLabel && onSkip && (
          <Button variant="ghost" onClick={onSkip} className="text-muted-foreground">
            {skipLabel}
          </Button>
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
    </div>
  );
}

function Benvenuto({ onNext, onSkip }: { onNext: () => void; onSkip: () => void }) {
  return (
    <Section
      title="Benvenuto in Vinea Wine Club"
      subtitle="Il marketplace sociale del vino tra privati. Iniziamo con qualche passo per personalizzare la tua esperienza."
    >
      <ul className="space-y-2 text-sm">
        {[
          "Scegli i tuoi obiettivi principali",
          "Crea l'account demo (nessun dato reale)",
          "Personalizza regioni, tipologie e Club",
          "Completa il profilo essenziale",
        ].map((s) => (
          <li key={s} className="flex items-center gap-2">
            <Check className="h-4 w-4 text-salvia" /> {s}
          </li>
        ))}
      </ul>
      <BottomBar onNext={onNext} nextLabel="Iniziamo" skipLabel="Esplora prima" onSkip={onSkip} />
    </Section>
  );
}

function Obiettivi({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  const { obiettivi, toggleObiettivo, saveObiettivi } = useVinea();
  const keys = Object.keys(obiettiviLabels) as Obiettivo[];
  return (
    <Section
      title="Cosa vorresti fare su Vinea?"
      subtitle="Selezioni multiple. Personalizza la tua home e i suggerimenti."
    >
      <div className="grid gap-3 sm:grid-cols-2">
        {keys.map((k) => {
          const info = obiettiviLabels[k];
          const active = obiettivi.has(k);
          return (
            <button
              key={k}
              onClick={() => toggleObiettivo(k)}
              aria-pressed={active}
              className={`flex min-w-0 items-start gap-3 rounded-2xl border p-4 text-left transition ${
                active
                  ? "border-bordeaux bg-bordeaux/5 ring-2 ring-bordeaux/20"
                  : "border-border bg-card hover:border-bordeaux/40"
              }`}
            >
              <span className="text-2xl leading-none">{info.emoji}</span>
              <span className="min-w-0 flex-1">
                <span className="block font-serif text-lg">{info.title}</span>
                <span className="mt-0.5 block text-xs text-muted-foreground">{info.desc}</span>
              </span>
              {active && <Check className="h-5 w-5 shrink-0 text-bordeaux" />}
            </button>
          );
        })}
      </div>
      <BottomBar
        onPrev={onPrev}
        onNext={() => {
          saveObiettivi();
          onNext();
        }}
        nextDisabled={obiettivi.size === 0}
        nextLabel="Continua"
      />
    </Section>
  );
}

function Registrazione({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  const { registerAccount } = useVinea();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [dob, setDob] = useState("");
  const [terms, setTerms] = useState(false);
  const [maggiorenne, setMaggiorenne] = useState(false);

  const age = useMemo(() => {
    if (!dob) return null;
    const d = new Date(dob);
    if (Number.isNaN(d.getTime())) return null;
    const diff = Date.now() - d.getTime();
    return Math.floor(diff / (365.25 * 24 * 3600 * 1000));
  }, [dob]);

  const valid =
    username.trim().length >= 3 &&
    email.includes("@") &&
    password.length >= 6 &&
    dob &&
    terms &&
    maggiorenne &&
    (age ?? 0) >= 18;

  return (
    <Section
      title="Crea il tuo account demo"
      subtitle="Non memorizziamo dati reali. Usa un nome utente e un'email di esempio."
    >
      <div className="space-y-4">
        <div className="rounded-xl border border-oro/30 bg-oro/5 p-3 text-xs">
          <Info className="mr-1 inline h-3.5 w-3.5" /> I campi sono <b>di sola simulazione</b>. Non
          inserire dati sensibili.
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <Label htmlFor="user">Nome utente</Label>
            <Input
              id="user"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="es. elena_r"
              autoComplete="off"
            />
          </div>
          <div>
            <Label htmlFor="email">Email demo</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="nome@demo.it"
              autoComplete="off"
            />
          </div>
          <div>
            <Label htmlFor="pwd">Password (placeholder)</Label>
            <Input
              id="pwd"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="almeno 6 caratteri"
              autoComplete="new-password"
            />
          </div>
          <div>
            <Label htmlFor="dob">Data di nascita</Label>
            <Input id="dob" type="date" value={dob} onChange={(e) => setDob(e.target.value)} />
            {age !== null && age < 18 && (
              <p className="mt-1 text-xs text-bordeaux">
                Devi avere almeno 18 anni per usare Vinea.
              </p>
            )}
          </div>
        </div>

        <label className="flex items-start gap-2 text-sm">
          <Checkbox
            checked={terms}
            onCheckedChange={(v) => setTerms(v === true)}
            className="mt-0.5"
          />
          <span>
            Accetto i{" "}
            <a
              className="text-bordeaux hover:underline"
              href="#"
              onClick={(e) => e.preventDefault()}
            >
              Termini e la Privacy
            </a>{" "}
            di Vinea (demo).
          </span>
        </label>
        <label className="flex items-start gap-2 text-sm">
          <Checkbox
            checked={maggiorenne}
            onCheckedChange={(v) => setMaggiorenne(v === true)}
            className="mt-0.5"
          />
          <span className="flex items-center gap-1">
            <ShieldAlert className="h-3.5 w-3.5 text-bordeaux" /> Confermo di essere maggiorenne.
            Vinea è vietato ai minori di 18 anni.
          </span>
        </label>
      </div>
      <BottomBar
        onPrev={onPrev}
        onNext={() => {
          registerAccount({ username, email, dob, maggiorenne });
          onNext();
        }}
        nextDisabled={!valid}
        nextLabel="Crea account demo"
      />
    </Section>
  );
}

function Verifica({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  const { profilo, emailStatus, verifyEmail } = useVinea();
  const [sent, setSent] = useState(0);
  const resend = () => {
    setSent((n) => n + 1);
    toast("Email di verifica reinviata (demo)");
  };
  return (
    <Section
      title="Controlla la posta"
      subtitle={`Abbiamo inviato un link di verifica a ${profilo.email} (demo).`}
    >
      <div className="flex items-start gap-3 rounded-2xl border border-border bg-crema p-4">
        <Mail className="mt-0.5 h-6 w-6 shrink-0 text-bordeaux" />
        <div className="min-w-0 text-sm">
          <p className="font-medium">Nessuna email reale è stata inviata</p>
          <p className="mt-1 text-muted-foreground">
            In produzione riceveresti un link di conferma. Qui puoi simulare il click sul pulsante
            qui sotto.
          </p>
          {sent > 0 && <p className="mt-2 text-xs text-salvia">Reinviata {sent} volta/e.</p>}
        </div>
      </div>

      <div className="mt-4 flex flex-col gap-2 sm:flex-row">
        <Button variant="outline" onClick={resend} className="min-w-0">
          <RefreshCw className="h-4 w-4" /> Reinvia email
        </Button>
        {emailStatus === "verificata" ? (
          <Button disabled className="min-w-0 bg-salvia hover:bg-salvia">
            Email verificata ✓
          </Button>
        ) : (
          <Button onClick={verifyEmail} className="min-w-0 bg-bordeaux hover:bg-bordeaux/90">
            Ho ricevuto — verifica (demo)
          </Button>
        )}
      </div>

      <BottomBar
        onPrev={onPrev}
        onNext={onNext}
        nextLabel="Continua"
        nextDisabled={emailStatus !== "verificata"}
        skipLabel="Salta"
        onSkip={onNext}
      />
    </Section>
  );
}

function Preferenze({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  const {
    regioniPreferite,
    tipologiePreferite,
    fasciaPrezzo,
    toggleRegionePref,
    toggleTipologiaPref,
    setFasciaPrezzo,
    savePreferenze,
    communityFollows,
    toggleCommunityFollow,
  } = useVinea();
  return (
    <Section
      title="Personalizza i tuoi consigli"
      subtitle="Puoi saltare e completare più tardi dalle Impostazioni."
    >
      <div className="space-y-6">
        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
            Regioni preferite
          </p>
          <div className="flex flex-wrap gap-2">
            {regioniItaliane.map((r) => {
              const active = regioniPreferite.has(r);
              return (
                <button
                  key={r}
                  onClick={() => toggleRegionePref(r)}
                  aria-pressed={active}
                  className={`rounded-full border px-3 py-1 text-xs transition ${active ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card hover:border-bordeaux/40"}`}
                >
                  {r}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
            Tipologie di vino
          </p>
          <div className="flex flex-wrap gap-2">
            {tipologieVino.map((t) => {
              const active = tipologiePreferite.has(t);
              return (
                <button
                  key={t}
                  onClick={() => toggleTipologiaPref(t)}
                  aria-pressed={active}
                  className={`rounded-full border px-3 py-1 text-xs transition ${active ? "border-salvia bg-salvia text-crema" : "border-border bg-card hover:border-salvia/40"}`}
                >
                  {t}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
            Fascia di prezzo
          </p>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {fascePrezzo.map((f) => {
              const active = fasciaPrezzo === f.id;
              return (
                <button
                  key={f.id}
                  onClick={() => setFasciaPrezzo(f.id)}
                  aria-pressed={active}
                  className={`min-w-0 truncate rounded-xl border px-3 py-2 text-sm transition ${active ? "border-oro bg-oro/15" : "border-border bg-card hover:border-oro/40"}`}
                >
                  {f.label}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
            Club suggeriti
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            {clubSuggeriti.map((c) => {
              const follow = communityFollows.has(c.slug);
              return (
                <button
                  key={c.slug}
                  onClick={() => toggleCommunityFollow(c.slug)}
                  aria-pressed={follow}
                  className={`flex min-w-0 items-center justify-between gap-3 rounded-2xl border p-3 text-left transition ${follow ? "border-bordeaux bg-bordeaux/5" : "border-border bg-card hover:border-bordeaux/40"}`}
                >
                  <span className="min-w-0">
                    <span className="block truncate font-serif font-semibold">{c.nome}</span>
                    <span className="mt-0.5 block truncate text-xs text-muted-foreground">
                      {c.desc}
                    </span>
                  </span>
                  <span
                    className={`shrink-0 rounded-full border px-2 py-0.5 text-[10px] ${follow ? "border-bordeaux bg-bordeaux text-crema" : "border-border"}`}
                  >
                    {follow ? "Seguito" : "Segui"}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      </div>
      <BottomBar
        onPrev={onPrev}
        onNext={() => {
          savePreferenze();
          onNext();
        }}
        skipLabel="Salta"
        onSkip={onNext}
      />
    </Section>
  );
}

function Profilo({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  const { profilo, saveProfilo } = useVinea();
  const [bio, setBio] = useState(profilo.bio);
  const [citta, setCitta] = useState(profilo.citta);
  const [provincia, setProvincia] = useState(profilo.provincia);
  const [esperienza, setEsperienza] = useState<Esperienza>(profilo.esperienza);
  const [avatarSeed, setAvatarSeed] = useState(profilo.avatarUrl);
  const avatarOptions = [68, 47, 44, 32, 25, 15];

  return (
    <Section
      title="Il tuo profilo essenziale"
      subtitle="Scegli un avatar demo, aggiungi una bio breve e la tua città."
    >
      <div className="space-y-5">
        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">Avatar demo</p>
          <div className="flex flex-wrap gap-3">
            {avatarOptions.map((n) => {
              const url = `https://i.pravatar.cc/240?img=${n}`;
              const active = avatarSeed === url;
              return (
                <button
                  key={n}
                  onClick={() => setAvatarSeed(url)}
                  aria-pressed={active}
                  className={`rounded-full ring-2 transition ${active ? "ring-bordeaux" : "ring-transparent hover:ring-bordeaux/30"}`}
                >
                  <img src={url} alt="" className="h-14 w-14 rounded-full object-cover" />
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <Label htmlFor="bio">Bio</Label>
          <Textarea
            id="bio"
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            rows={3}
            placeholder="Racconta in poche parole cosa ami del vino."
          />
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="sm:col-span-2">
            <Label htmlFor="citta">Città</Label>
            <Input
              id="citta"
              value={citta}
              onChange={(e) => setCitta(e.target.value)}
              placeholder="es. Milano"
            />
          </div>
          <div>
            <Label htmlFor="prov">Provincia</Label>
            <Input
              id="prov"
              value={provincia}
              onChange={(e) => setProvincia(e.target.value.toUpperCase().slice(0, 2))}
              placeholder="MI"
              maxLength={2}
            />
          </div>
        </div>

        <div>
          <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
            Livello di esperienza
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            {(Object.keys(esperienzaLabels) as Esperienza[]).map((k) => {
              const active = esperienza === k;
              return (
                <button
                  key={k}
                  onClick={() => setEsperienza(k)}
                  aria-pressed={active}
                  className={`min-w-0 truncate rounded-xl border px-3 py-2 text-left text-sm transition ${active ? "border-bordeaux bg-bordeaux/5" : "border-border bg-card hover:border-bordeaux/40"}`}
                >
                  {esperienzaLabels[k]}
                </button>
              );
            })}
          </div>
        </div>
      </div>
      <BottomBar
        onPrev={onPrev}
        onNext={() => {
          saveProfilo({ bio, citta, provincia, esperienza, avatarUrl: avatarSeed });
          onNext();
        }}
        skipLabel="Salta"
        onSkip={onNext}
      />
    </Section>
  );
}

function Fine({ onDone, onVerifica }: { onDone: () => void; onVerifica: () => void }) {
  const { profileCompletion } = useVinea();
  return (
    <Section
      title="Tutto pronto 🎉"
      subtitle="Il tuo account demo è configurato. Puoi completare i passi mancanti quando vuoi."
    >
      <div className="rounded-2xl border border-border bg-crema p-4">
        <div className="flex items-center justify-between gap-3">
          <p className="text-sm font-medium">Completamento profilo</p>
          <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-xs font-semibold text-bordeaux">
            {profileCompletion.perc}%
          </span>
        </div>
        <Progress value={profileCompletion.perc} className="mt-2 h-1.5" />
        <ul className="mt-3 space-y-1.5 text-sm">
          {profileCompletion.items.map((i) => (
            <li key={i.label} className="flex items-center gap-2">
              {i.done ? (
                <Check className="h-4 w-4 text-salvia" />
              ) : (
                <span className="grid h-4 w-4 place-items-center rounded-full border border-border text-[9px] text-muted-foreground">
                  ·
                </span>
              )}
              <span className={i.done ? "text-antracite" : "text-muted-foreground"}>{i.label}</span>
            </li>
          ))}
        </ul>
      </div>

      <div className="mt-4 rounded-2xl border border-oro/40 bg-oro/10 p-4 text-sm">
        <p className="flex items-center gap-2 font-medium">
          <Sparkles className="h-4 w-4 text-oro" /> Vuoi vendere?
        </p>
        <p className="mt-1 text-xs text-antracite/80">
          Prima della prima vendita ti chiederemo una verifica identità simulata. Nessun documento
          reale.
        </p>
      </div>

      <div className="mt-4 flex flex-col gap-2 sm:flex-row">
        <Button variant="outline" onClick={onVerifica} className="min-w-0">
          <UserIcon className="h-4 w-4" /> Verifica venditore
        </Button>
        <Button onClick={onDone} className="min-w-0 bg-bordeaux hover:bg-bordeaux/90">
          Vai alla Home
        </Button>
      </div>

      <p className="mt-4 text-center text-xs text-muted-foreground">
        Puoi modificare tutto dal{" "}
        <Link to="/profilo" className="text-bordeaux hover:underline">
          tuo profilo
        </Link>
        .
      </p>
    </Section>
  );
}
