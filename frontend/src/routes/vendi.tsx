import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import {
  Check,
  ArrowRight,
  ArrowLeft,
  Camera,
  Sparkles,
  WandSparkles,
  Wine,
  Archive,
  Eye,
  Tag,
  ShieldAlert,
  BadgeCheck,
  Loader2,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Progress } from "@/components/ui/progress";
import { useVinea, formatEUR } from "@/lib/vinea-store";
import { wineImages } from "@/lib/wine-images";
import { toast } from "sonner";
import { z } from "zod";
import { useSellWizard, type Modalita } from "@/hooks/useSellWizard";

const searchSchema = z.object({
  mode: z.enum(["catalog", "sell"]).optional(),
});

export const Route = createFileRoute("/vendi")({
  validateSearch: searchSchema,
  head: () => ({
    meta: [
      { title: "Aggiungi o vendi una bottiglia — Vinea" },
      {
        name: "description",
        content: "Cataloga la tua bottiglia in cantina o pubblicala nel marketplace Vinea.",
      },
      { property: "og:title", content: "Vendi o cataloga — Vinea" },
      {
        property: "og:description",
        content: "Un wizard guidato: catalogazione privata, cantina pubblica o vendita.",
      },
    ],
  }),
  component: Vendi,
});

function Vendi() {
  const nav = useNavigate();
  const search = Route.useSearch();
  const { ruolo, sellerStatus, identityStatus } = useVinea();
  const initialMode: Modalita = search.mode === "sell" ? "vendita" : "privata";
  const {
    modalita,
    setModalita,
    step,
    steps,
    progress,
    next,
    prev,
    isVendita,
    bloccatoVendita,
    d,
    set,
    suggerito,
    aiHint,
    setAiHint,
    aiSug,
    aiLoading,
    aiError,
    askListingAI,
    applyAiSuggestion,
    pubblica,
    salvaBozza,
  } = useSellWizard({
    initialMode,
    sellerStatus,
    onNavigate: (path) => nav({ to: path }),
  });

  // Guest: invita a registrarsi
  if (ruolo === "guest") {
    return (
      <div className="mx-auto max-w-lg space-y-4 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
          <Tag className="h-8 w-8 text-bordeaux" />
        </div>
        <h1 className="font-serif text-2xl md:text-3xl">Registrati per catalogare o vendere</h1>
        <p className="text-sm text-muted-foreground">
          Crea l'account demo per usare il wizard di vendita e la tua cantina.
        </p>
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link to="/onboarding">Inizia l'onboarding</Link>
        </Button>
      </div>
    );
  }

  return (
    <div className="relative mx-auto max-w-2xl space-y-6">
      {/* Fondale decorativo */}
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <img
          src={wineImages.crate}
          alt=""
          className="absolute inset-0 h-full w-full object-cover opacity-20"
        />
        <div className="absolute inset-0 bg-gradient-to-b from-background via-background/95 to-background" />
      </div>

      <div>
        <h1 className="font-serif text-3xl md:text-4xl">
          {isVendita ? "Vendi la tua bottiglia" : "Aggiungi una bottiglia"}
        </h1>
        <p className="text-muted-foreground">
          {isVendita
            ? `Percorso guidato in ${steps.length} passi per pubblicare nel marketplace.`
            : `Catalogazione guidata: ${steps.length} passi, nessun obbligo di prezzo.`}
        </p>
      </div>

      {bloccatoVendita && (
        <div className="rounded-2xl border border-bordeaux/30 bg-bordeaux/5 p-4 text-sm">
          <p className="flex items-center gap-2 font-medium text-bordeaux">
            <ShieldAlert className="h-4 w-4" />
            Per pubblicare in vendita devi verificare la tua identità
          </p>
          <p className="mt-1 text-xs text-antracite/80">
            Puoi comunque completare il wizard e <b>salvare come bozza</b> nella cantina. Al termine
            della verifica potrai pubblicare.
            {identityStatus === "in_verifica" && " La tua verifica è in corso."}
          </p>
          <Button asChild size="sm" className="mt-3 bg-bordeaux hover:bg-bordeaux/90">
            <Link to="/verifica-venditore">
              <BadgeCheck className="h-4 w-4" /> Vai alla verifica
            </Link>
          </Button>
        </div>
      )}

      <div>
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>
            Passo {step + 1} di {steps.length}
          </span>
          <span>{steps[step]}</span>
        </div>
        <Progress value={progress} className="mt-2 h-2" />
      </div>

      <div className="rounded-2xl border border-border bg-card/95 p-6 backdrop-blur">
        {step === 0 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Come vuoi usare questa bottiglia?</h2>
            <p className="text-sm text-muted-foreground">
              Puoi cambiare idea in qualsiasi momento.
            </p>
            <div className="grid gap-3">
              <ModeCard
                active={modalita === "privata"}
                onClick={() => setModalita("privata")}
                icon={Archive}
                titolo="Aggiungi alla cantina privata"
                sottotitolo="Solo tu la vedi. Nessun prezzo obbligatorio."
              />
              <ModeCard
                active={modalita === "pubblica"}
                onClick={() => setModalita("pubblica")}
                icon={Eye}
                titolo="Mostra nella cantina pubblica"
                sottotitolo="Appare sul tuo profilo, senza essere in vendita."
              />
              <ModeCard
                active={modalita === "vendita"}
                onClick={() => setModalita("vendita")}
                icon={Tag}
                titolo="Pubblica in vendita"
                sottotitolo="Attivi prezzo, spedizione e proposte."
              />
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="space-y-5">
            <h2 className="font-serif text-2xl">Fotografie</h2>
            <p className="text-sm text-muted-foreground">
              Consigliate: fronte, retro, capsula, livello, fondo, confezione ed eventuali difetti.
            </p>
            <div className="grid grid-cols-3 gap-3">
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <button
                  key={i}
                  onClick={() => toast("Caricamento foto (demo)")}
                  className="grid aspect-square place-items-center rounded-xl border-2 border-dashed border-border bg-secondary/50 text-muted-foreground hover:border-bordeaux hover:text-bordeaux"
                >
                  <Camera className="h-6 w-6" />
                </button>
              ))}
            </div>

            {/* Pannello IA sfondo */}
            <SfondoIAPanel />
          </div>
        )}

        {step === 2 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Identificazione</h2>
            <p className="text-sm text-muted-foreground">
              <span className="inline-flex items-center gap-1 rounded-full bg-oro/20 px-2 py-0.5 text-[10px] font-medium text-antracite">
                <Sparkles className="h-3 w-3" /> Suggerito dall'IA
              </span>{" "}
              Puoi modificare manualmente ogni campo.
            </p>

            <div
              className="rounded-2xl border border-bordeaux/20 bg-gradient-to-br from-bordeaux/5 via-oro/10 to-transparent p-4"
              data-testid="ai-listing-panel"
            >
              <div className="flex items-center gap-2">
                <span className="grid h-9 w-9 place-items-center rounded-full bg-bordeaux text-crema">
                  <Sparkles className="h-4 w-4 text-oro" />
                </span>
                <div className="min-w-0">
                  <p className="font-serif text-base leading-tight">
                    Assistente <span className="gold-shimmer">AI</span>
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    Descrivi la bottiglia o incolla il testo dell'etichetta
                  </p>
                </div>
              </div>
              <textarea
                value={aiHint}
                onChange={(e) => setAiHint(e.target.value)}
                data-testid="ai-listing-hint-input"
                rows={2}
                maxLength={500}
                placeholder="Es. 'Antinori Tignanello 2019, Toscana IGT, capsula intatta'"
                className="mt-3 w-full resize-y rounded-xl border border-border bg-card px-3 py-2 text-sm outline-none focus:border-bordeaux focus:ring-2 focus:ring-bordeaux/30"
              />
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <Button
                  type="button"
                  size="sm"
                  data-testid="ai-listing-ask-btn"
                  onClick={askListingAI}
                  disabled={aiLoading || !aiHint.trim()}
                  className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
                >
                  {aiLoading ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Analisi…
                    </>
                  ) : (
                    <>
                      <Sparkles className="h-3.5 w-3.5" /> Suggerisci con l'AI
                    </>
                  )}
                </Button>
                {aiSug && (
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    data-testid="ai-listing-apply-btn"
                    onClick={applyAiSuggestion}
                  >
                    Applica ai campi
                  </Button>
                )}
                {aiSug && (
                  <span
                    className="text-[11px] text-muted-foreground"
                    data-testid="ai-listing-confidence"
                  >
                    Confidence: {(aiSug.confidence * 100).toFixed(0)}%
                  </span>
                )}
              </div>
              {aiError && (
                <p className="mt-2 rounded-xl bg-destructive/10 px-3 py-2 text-xs text-destructive">
                  {aiError}
                </p>
              )}
              {aiSug && (
                <div
                  className="mt-3 grid gap-2 rounded-xl border border-border bg-card p-3 text-xs md:grid-cols-2"
                  data-testid="ai-listing-preview"
                >
                  <p>
                    <b>Produttore:</b> {aiSug.produttore || "—"}
                  </p>
                  <p>
                    <b>Nome:</b> {aiSug.nome || "—"}
                  </p>
                  <p>
                    <b>Annata:</b> {aiSug.annata ?? "—"}
                  </p>
                  <p>
                    <b>Regione:</b> {aiSug.regione || "—"}
                  </p>
                  <p>
                    <b>Tipologia:</b> {aiSug.tipologia || "—"}
                  </p>
                  <p>
                    <b>Denominazione:</b> {aiSug.denominazione || "—"}
                  </p>
                  {aiSug.note_degustazione && (
                    <p className="md:col-span-2">
                      <b>Note:</b> {aiSug.note_degustazione}
                    </p>
                  )}
                </div>
              )}
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <Field label="Produttore">
                <Input
                  value={d.produttore}
                  onChange={(e) => set("produttore")(e.target.value)}
                  placeholder="Es. Antinori"
                />
              </Field>
              <Field label="Nome / Etichetta">
                <Input
                  value={d.nome}
                  onChange={(e) => set("nome")(e.target.value)}
                  placeholder="Es. Tignanello"
                />
              </Field>
              <Field label="Annata">
                <Input
                  type="number"
                  value={d.annata}
                  onChange={(e) => set("annata")(e.target.value)}
                  placeholder="Es. 2019"
                />
              </Field>
              <Field label="Regione">
                <Input
                  value={d.regione}
                  onChange={(e) => set("regione")(e.target.value)}
                  placeholder="Es. Toscana"
                />
              </Field>
              <Field label="Tipologia">
                <Select value={d.tipo} onValueChange={set("tipo")}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {["Rosso", "Bianco", "Bollicine", "Rosato", "Dolce"].map((t) => (
                      <SelectItem key={t} value={t}>
                        {t}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Condizioni</h2>
            <div className="grid grid-cols-3 gap-2">
              {["Perfetto", "Ottimo", "Buono"].map((c) => (
                <button
                  key={c}
                  onClick={() => set("condizione")(c)}
                  className={`rounded-xl border p-3 text-sm ${d.condizione === c ? "border-bordeaux bg-bordeaux/5" : "border-border"}`}
                >
                  <p className="font-serif text-base">{c}</p>
                </button>
              ))}
            </div>
          </div>
        )}

        {step === 4 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Provenienza e conservazione</h2>
            <Field label="Come è stata conservata">
              <Textarea
                value={d.conservazione}
                onChange={(e) => set("conservazione")(e.target.value)}
                placeholder="Cantina climatizzata a 14°C, umidità 70%, bottiglia sdraiata…"
              />
            </Field>
            <Field label="Racconta la sua storia (opzionale)">
              <Textarea
                value={d.storia}
                onChange={(e) => set("storia")(e.target.value)}
                placeholder="Regalata da mio nonno, dalla verticale di famiglia…"
              />
            </Field>
          </div>
        )}

        {isVendita && step === 5 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Prezzo</h2>
            <div className="rounded-xl border border-oro/40 bg-oro/10 p-4">
              <p className="flex items-center gap-2 text-sm">
                <Sparkles className="h-4 w-4 text-oro" /> Prezzo suggerito dall'IA in base al
                mercato: <b>{formatEUR(suggerito)}</b>
              </p>
            </div>
            <div className="grid gap-3 md:grid-cols-2">
              <Field label="Prezzo (€)">
                <Input
                  type="number"
                  value={d.prezzo}
                  onChange={(e) => set("prezzo")(e.target.value)}
                  placeholder={String(suggerito)}
                />
              </Field>
              <Field label="Bottiglie disponibili">
                <Input
                  type="number"
                  value={d.disponibili}
                  onChange={(e) => set("disponibili")(e.target.value)}
                />
              </Field>
            </div>
          </div>
        )}

        {isVendita && step === 6 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Consegna</h2>
            <div className="grid gap-3 md:grid-cols-2">
              {["Corriere assicurato", "Ritiro a mano", "Punto Vinea"].map((c) => (
                <button
                  key={c}
                  onClick={() => toast(c + " selezionato (demo)")}
                  className="rounded-xl border border-border p-3 text-left hover:border-bordeaux"
                >
                  <p className="font-serif text-base">{c}</p>
                  <p className="text-xs text-muted-foreground">Simulato in demo</p>
                </button>
              ))}
            </div>
          </div>
        )}

        {step === steps.length - 1 && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Anteprima</h2>
            <div className="space-y-2 rounded-xl bg-secondary p-4 text-sm">
              <p>
                <b>{d.produttore || "—"}</b> {d.nome} {d.annata}
              </p>
              <p>
                {d.regione || "—"} • {d.tipo} • {d.condizione}
              </p>
              {isVendita ? (
                <>
                  <p className="font-serif text-2xl text-bordeaux">
                    {d.prezzo ? formatEUR(Number(d.prezzo)) : "—"}
                  </p>
                  <p className="text-xs text-muted-foreground">{d.disponibili} bottiglie</p>
                </>
              ) : (
                <p className="text-xs text-muted-foreground">
                  Modalità: {modalita === "privata" ? "cantina privata" : "cantina pubblica"} —
                  nessun prezzo pubblicato.
                </p>
              )}
            </div>
            <button
              onClick={() => toast.success("Bozza salvata")}
              className="text-sm text-bordeaux hover:underline"
            >
              Salva come bozza
            </button>
          </div>
        )}
      </div>

      <div className="flex flex-wrap justify-between gap-2">
        <Button variant="outline" onClick={prev} disabled={step === 0}>
          <ArrowLeft className="h-4 w-4" /> Indietro
        </Button>
        <div className="flex flex-wrap gap-2">
          <Button variant="ghost" onClick={salvaBozza}>
            Salva bozza
          </Button>
          {step < steps.length - 1 ? (
            <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={next}>
              Continua <ArrowRight className="h-4 w-4" />
            </Button>
          ) : bloccatoVendita ? (
            <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
              <Link to="/verifica-venditore">
                <BadgeCheck className="h-4 w-4" /> Verifica per pubblicare
              </Link>
            </Button>
          ) : (
            <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={pubblica}>
              {isVendita
                ? "Pubblica annuncio"
                : modalita === "pubblica"
                  ? "Aggiungi alla cantina pubblica"
                  : "Aggiungi alla cantina privata"}
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

function ModeCard({
  active,
  onClick,
  icon: Icon,
  titolo,
  sottotitolo,
}: {
  active: boolean;
  onClick: () => void;
  icon: LucideIcon;
  titolo: string;
  sottotitolo: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-3 rounded-xl border p-4 text-left transition ${active ? "border-bordeaux bg-bordeaux/5" : "border-border hover:bg-secondary"}`}
    >
      <span
        className={`grid h-10 w-10 shrink-0 place-items-center rounded-full ${active ? "bg-bordeaux text-crema" : "bg-secondary text-bordeaux"}`}
      >
        <Icon className="h-5 w-5" />
      </span>
      <div className="min-w-0">
        <p className="font-serif text-lg font-semibold">{titolo}</p>
        <p className="text-xs text-muted-foreground">{sottotitolo}</p>
      </div>
      {active && <Check className="ml-auto h-5 w-5 text-bordeaux" />}
    </button>
  );
}

const stili = [
  { key: "casse", nome: "Casse italiane", img: wineImages.crate },
  { key: "moderna", nome: "Cantina moderna", img: wineImages.cellar },
  { key: "rustica", nome: "Cantina rustica", img: wineImages.vineyard },
  { key: "premium", nome: "Esposizione premium", img: wineImages.champagne },
];

function SfondoIAPanel() {
  const [stile, setStile] = useState<string>("casse");
  const [stato, setStato] = useState<"idle" | "loading" | "done">("idle");
  const applica = () => {
    setStato("loading");
    setTimeout(() => {
      setStato("done");
      toast.success("Sfondo applicato (demo)");
    }, 1100);
  };
  const scelto = stili.find((s) => s.key === stile)!;
  return (
    <section className="rounded-2xl border border-oro/40 bg-oro/5 p-4">
      <div className="mb-2 flex items-start gap-2">
        <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-oro/25 text-antracite">
          <WandSparkles className="h-4 w-4" />
        </span>
        <div>
          <p className="font-serif text-lg font-semibold">Migliora lo sfondo con IA</p>
          <p className="text-xs text-muted-foreground">
            Opzione facoltativa: la bottiglia non viene modificata; vengono adattati solo sfondo e
            illuminazione.
          </p>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-3">
        <div>
          <p className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground">Prima</p>
          <div className="aspect-square overflow-hidden rounded-lg border border-border bg-secondary">
            <div className="grid h-full w-full place-items-center">
              <Wine className="h-14 w-14 text-bordeaux/70" />
            </div>
          </div>
        </div>
        <div>
          <p className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground">Dopo</p>
          <div className="relative aspect-square overflow-hidden rounded-lg border border-oro">
            <img src={scelto.img} alt="" className="h-full w-full object-cover" />
            <div className="absolute inset-0 bg-gradient-to-t from-antracite/40 to-transparent" />
            <div className="absolute inset-0 grid place-items-center">
              <Wine className="h-14 w-14 text-crema drop-shadow" />
            </div>
            {stato === "loading" && (
              <div className="absolute inset-0 grid place-items-center bg-antracite/50 text-crema text-xs">
                Elaborazione IA…
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="mt-3">
        <p className="mb-2 text-[11px] uppercase tracking-wide text-muted-foreground">
          Scegli stile
        </p>
        <div className="flex flex-wrap gap-2">
          {stili.map((s) => (
            <button
              key={s.key}
              onClick={() => setStile(s.key)}
              className={`rounded-full border px-3 py-1 text-xs ${stile === s.key ? "border-bordeaux bg-bordeaux text-crema" : "border-border bg-card"}`}
            >
              {s.nome}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="outline"
          onClick={() => {
            setStato("idle");
            toast("Foto originale mantenuta");
          }}
        >
          Mantieni foto originale
        </Button>
        <Button
          size="sm"
          className="bg-oro text-antracite hover:bg-oro/90"
          onClick={applica}
          disabled={stato === "loading"}
        >
          <Sparkles className="h-3.5 w-3.5" /> Applica sfondo suggerito
        </Button>
      </div>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs uppercase tracking-wide text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}
