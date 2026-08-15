"use client";

import { useRef } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Check,
  ArrowRight,
  ArrowLeft,
  Camera,
  Loader2,
  Sparkles,
  Archive,
  Eye,
  Tag,
  X,
  type LucideIcon,
} from "lucide-react";
import { toast } from "sonner";
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
import { useSellWizard, MAX_FOTO, type Modalita } from "@/hooks/useSellWizard";
import { confidenzaPercento } from "@/lib/phase10/catalogazione";
import { AiTransparencyLabel } from "@/components/vinea/AiTransparencyLabel";
import { BetaActionNotice } from "@/components/vinea/BetaActionNotice";
import { BetaBackgroundPanel } from "@/components/vinea/BetaBackgroundPanel";
import { BottleSelector } from "@/app/vendi/bottle-selector";
import { AI_UI } from "@/config/features";

/**
 * /vendi portata da frontend/src/routes/vendi.tsx.
 *
 * Le differenze rispetto all'originale sono tutte dichiarate nel rapporto di
 * fase; le tre visibili qui:
 *
 * - il pannello "Assistente AI" del passo Identificazione è rientrato con la
 *   Fase 10c: chiama `ai-catalogo` tramite `AiService` invece del backend
 *   FastAPI, e manda il solo `hint` come faceva il legacy;
 * - il passo Foto carica davvero su Supabase Storage invece di mostrare un
 *   toast di demo;
 * - il campo "Bottiglie disponibili" è visibile ma disabilitato: un annuncio
 *   vende una singola bottle_unit identificata.
 *
 * L'accesso non è più deciso dal demo-switcher `ruolo` ma dalla sessione reale
 * Supabase: da questa fase il wizard scrive, e scrivere richiede un utente
 * vero, non un ruolo scelto da un menu.
 */
export default function VendiPageClient() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { authUser, authLoading, bottiglieCantina, viniCantina, cantinaLoading, ricaricaCantina } =
    useVinea();
  const initialMode: Modalita = searchParams.get("mode") === "sell" ? "vendita" : "privata";
  // Bottiglia già in cantina, scelta dal pulsante "Metti in vendita" (6c-2).
  const bottleUnitId = searchParams.get("bottiglia");

  const bottiglia = bottleUnitId
    ? bottiglieCantina.find((b) => b.bottleId === bottleUnitId)
    : undefined;
  const vinoBottiglia = bottiglia
    ? viniCantina.find((w) => (w.wineSlug ?? w.id) === bottiglia.wineVintageId)
    : undefined;

  const {
    modalita,
    setModalita,
    step,
    steps,
    primoPasso,
    passiVisibili,
    numeroPasso,
    daCantina,
    progress,
    next,
    prev,
    isVendita,
    d,
    set,
    suggerito,
    foto,
    fotoInCorso,
    caricaFoto,
    rimuoviFoto,
    inviando,
    pubblica,
    salvaBozza,
    aiHint,
    setAiHint,
    aiSuggerimento,
    aiInCorso,
    aiErrore,
    aiBloccata,
    chiediSuggerimento,
    applicaSuggerimento,
  } = useSellWizard({
    initialMode,
    onNavigate: (path) => router.push(path),
    bottleUnitId,
    onCantinaCambiata: ricaricaCantina,
  });

  if (authLoading) {
    return (
      <div className="mx-auto max-w-lg py-16 text-center text-sm text-muted-foreground">
        <Loader2 className="mx-auto h-6 w-6 animate-spin text-bordeaux" />
        <p className="mt-3">Caricamento…</p>
      </div>
    );
  }

  // Senza sessione reale non c'è niente da catalogare né da vendere: il
  // venditore di un annuncio è sempre auth.uid(), mai un ruolo di demo.
  if (!authUser) {
    return (
      <div className="mx-auto max-w-lg space-y-4 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
          <Tag className="h-8 w-8 text-bordeaux" />
        </div>
        <h1 className="font-serif text-2xl md:text-3xl">Accedi per catalogare o vendere</h1>
        <p className="text-sm text-muted-foreground">
          Serve un account per usare il wizard di vendita e la tua cantina.
        </p>
        <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
          <Link href="/registrati">Crea un account</Link>
        </Button>
      </div>
    );
  }

  if (initialMode === "vendita" && !bottleUnitId) {
    if (cantinaLoading) {
      return (
        <div className="mx-auto max-w-lg py-16 text-center text-sm text-muted-foreground">
          <Loader2 className="mx-auto h-6 w-6 animate-spin text-bordeaux" />
          <p className="mt-3">Carico la Cantina…</p>
        </div>
      );
    }
    return <BottleSelector bottiglie={bottiglieCantina} vini={viniCantina} />;
  }

  // Bottiglia richiesta ma cantina non ancora letta: si aspetta invece di
  // mostrare "non è tua" a chi la possiede davvero.
  if (daCantina && cantinaLoading) {
    return (
      <div className="mx-auto max-w-lg py-16 text-center text-sm text-muted-foreground">
        <Loader2 className="mx-auto h-6 w-6 animate-spin text-bordeaux" />
        <p className="mt-3">Carico la bottiglia…</p>
      </div>
    );
  }

  // Id inventato, bottiglia di un altro, o unità cancellata. Il database la
  // rifiuterebbe comunque (`listing_crea_da_bottiglia` verifica la proprietà),
  // ma dirlo qui
  // evita di far compilare sei passi per poi negare alla fine.
  if (daCantina && !bottiglia) {
    return (
      <div className="mx-auto max-w-lg space-y-4 rounded-3xl border border-border bg-card p-6 text-center md:p-10">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-bordeaux/10">
          <Archive className="h-8 w-8 text-bordeaux" />
        </div>
        <h1 className="font-serif text-2xl md:text-3xl">Bottiglia non trovata</h1>
        <p className="text-sm text-muted-foreground">
          Questa bottiglia non è nella tua cantina. Scegline una dalla tua cantina, oppure
          aggiungine prima una nuova.
        </p>
        <div className="flex flex-wrap justify-center gap-2">
          <Button asChild className="bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/cantina">Vai alla cantina</Link>
          </Button>
          <Button asChild variant="outline">
            <Link href="/vendi?mode=catalog">Aggiungi una bottiglia</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="relative mx-auto max-w-2xl space-y-6">
      {/* Fondale decorativo */}
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        {/* eslint-disable-next-line @next/next/no-img-element */}
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
            ? `Percorso guidato in ${passiVisibili} passi per pubblicare nel marketplace.`
            : `Catalogazione guidata: ${passiVisibili} passi, nessun obbligo di prezzo.`}
        </p>
      </div>

      <div>
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>
            Passo {numeroPasso} di {passiVisibili}
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
            <FotoGriglia
              foto={foto}
              inCorso={fotoInCorso}
              onCarica={caricaFoto}
              onRimuovi={rimuoviFoto}
            />
            {AI_UI.catalogazione && <BetaBackgroundPanel haFoto={foto.length > 0} />}
          </div>
        )}

        {/*
          Identificazione, versione "bottiglia già in cantina".

          I cinque campi liberi spariscono e restano in sola lettura: descrivono
          il vino, che per un'unità esistente è già deciso e vive in `wines`,
          catalogo condiviso già collegato all'unità. Renderli modificabili
          suggerirebbe di poter correggere il vino da qui — la stessa ragione
          per cui in 6b `aggiorna` non li contiene.
        */}
        {step === 2 && daCantina && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Identificazione</h2>
            <p className="text-sm text-muted-foreground">
              Questa bottiglia è già nella tua cantina: il vino lo conosciamo.
            </p>

            <div className="flex items-start gap-4 rounded-2xl border border-oro/40 bg-oro/10 p-4">
              {vinoBottiglia && (
                /* eslint-disable-next-line @next/next/no-img-element */
                <img
                  src={vinoBottiglia.immagini[0]}
                  alt=""
                  className="h-24 w-20 shrink-0 rounded-lg object-cover"
                />
              )}
              <div className="min-w-0 flex-1">
                <p className="text-xs uppercase tracking-wide text-salvia">
                  {vinoBottiglia?.produttore}
                </p>
                <p className="font-serif text-xl font-semibold">
                  {vinoBottiglia?.nome} {vinoBottiglia?.annata}
                </p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {[vinoBottiglia?.regione, vinoBottiglia?.denominazione, vinoBottiglia?.tipo]
                    .filter(Boolean)
                    .join(" · ")}
                </p>
                <p className="mt-2 text-[11px] text-muted-foreground">
                  Il vino non si modifica da qui: appartiene al catalogo condiviso.
                </p>
              </div>
            </div>

            <Button asChild variant="outline" size="sm">
              <Link href="/cantina">Cambia bottiglia</Link>
            </Button>
          </div>
        )}

        {step === 2 && !daCantina && (
          <div className="space-y-4">
            <h2 className="font-serif text-2xl">Identificazione</h2>
            <p className="text-sm text-muted-foreground">
              Compila i campi che descrivono la bottiglia. Puoi modificare manualmente ogni campo.
            </p>

            {AI_UI.catalogazione && (
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
                    Descrivi la bottiglia o incolla il testo dell&apos;etichetta
                  </p>
                  <AiTransparencyLabel superficie="catalogazione" />
                </div>
              </div>
              <textarea
                value={aiHint}
                onChange={(e) => setAiHint(e.target.value)}
                data-testid="ai-listing-hint-input"
                rows={2}
                // Stesso tetto del legacy e della function: `hint` ≤ 500
                // caratteri (`backend/ai_routes.py:229`).
                maxLength={500}
                placeholder="Es. 'Antinori Tignanello 2019, Toscana IGT, capsula intatta'"
                className="mt-3 w-full resize-y rounded-xl border border-border bg-card px-3 py-2 text-sm outline-none focus:border-bordeaux focus:ring-2 focus:ring-bordeaux/30"
              />
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <Button
                  type="button"
                  size="sm"
                  data-testid="ai-listing-ask-btn"
                  onClick={() => void chiediSuggerimento()}
                  disabled={aiInCorso || !aiHint.trim()}
                  className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
                >
                  {aiInCorso ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Analisi…
                    </>
                  ) : (
                    <>
                      <Sparkles className="h-3.5 w-3.5" /> Suggerisci con l&apos;AI
                    </>
                  )}
                </Button>
                {aiSuggerimento && (
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    data-testid="ai-listing-apply-btn"
                    onClick={applicaSuggerimento}
                  >
                    Applica ai campi
                  </Button>
                )}
                {aiSuggerimento && (
                  <span
                    className="text-[11px] text-muted-foreground"
                    data-testid="ai-listing-confidence"
                  >
                    Confidence: {confidenzaPercento(aiSuggerimento.confidence)}%
                  </span>
                )}
              </div>
              {aiErrore && (
                <p
                  className="mt-2 rounded-xl bg-destructive/10 px-3 py-2 text-xs text-destructive"
                  data-testid="ai-listing-error"
                >
                  {aiErrore}
                </p>
              )}
              {aiBloccata && <BetaActionNotice tipo="ia" className="mt-3" />}
              {aiSuggerimento && (
                <div
                  className="mt-3 grid gap-2 rounded-xl border border-border bg-card p-3 text-xs md:grid-cols-2"
                  data-testid="ai-listing-preview"
                >
                  <p>
                    <b>Produttore:</b> {aiSuggerimento.produttore || "—"}
                  </p>
                  <p>
                    <b>Nome:</b> {aiSuggerimento.nome || "—"}
                  </p>
                  <p>
                    <b>Annata:</b> {aiSuggerimento.annata ?? "—"}
                  </p>
                  <p>
                    <b>Regione:</b> {aiSuggerimento.regione || "—"}
                  </p>
                  <p>
                    <b>Tipologia:</b> {aiSuggerimento.tipologia || "—"}
                  </p>
                  <p>
                    <b>Denominazione:</b> {aiSuggerimento.denominazione || "—"}
                  </p>
                  {aiSuggerimento.noteDegustazione && (
                    <p className="md:col-span-2">
                      <b>Note:</b> {aiSuggerimento.noteDegustazione}
                    </p>
                  )}
                </div>
              )}
              </div>
            )}

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
                <Tag className="h-4 w-4 text-oro" /> Riferimento beta locale basato sui dati
                disponibili: <b>{formatEUR(suggerito)}</b>
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
                <Input type="number" value={d.disponibili} disabled readOnly />
                <p className="text-[11px] text-muted-foreground">
                  Un annuncio vende una bottiglia identificata. Più unità sullo stesso annuncio
                  arriveranno con la cantina.
                </p>
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
              {/* Con una bottiglia già in cantina i campi liberi restano vuoti:
                  l'anteprima legge il vino dell'unità, che è ciò che finirà
                  davvero sull'annuncio. */}
              <p>
                <b>{(daCantina ? vinoBottiglia?.produttore : d.produttore) || "—"}</b>{" "}
                {daCantina ? vinoBottiglia?.nome : d.nome}{" "}
                {daCantina ? vinoBottiglia?.annata : d.annata}
              </p>
              <p>
                {(daCantina ? vinoBottiglia?.regione : d.regione) || "—"} •{" "}
                {daCantina ? vinoBottiglia?.tipo : d.tipo} • {d.condizione}
              </p>
              {isVendita ? (
                <>
                  <p className="font-serif text-2xl text-bordeaux">
                    {d.prezzo ? formatEUR(Number(d.prezzo)) : "—"}
                  </p>
                  <p className="text-xs text-muted-foreground">1 bottiglia</p>
                </>
              ) : (
                <p className="text-xs text-muted-foreground">
                  Modalità: {modalita === "privata" ? "cantina privata" : "cantina pubblica"} —
                  nessun prezzo pubblicato.
                </p>
              )}
            </div>
          </div>
        )}
      </div>

      <div className="flex flex-wrap justify-between gap-2">
        <Button variant="outline" onClick={prev} disabled={step === primoPasso || inviando}>
          <ArrowLeft className="h-4 w-4" /> Indietro
        </Button>
        <div className="flex flex-wrap gap-2">
          {isVendita && (
            <Button variant="ghost" onClick={salvaBozza} disabled={inviando}>
              Salva bozza
            </Button>
          )}
          {step < steps.length - 1 ? (
            <Button className="bg-bordeaux hover:bg-bordeaux/90" onClick={next}>
              Continua <ArrowRight className="h-4 w-4" />
            </Button>
          ) : (
            <Button
              className="bg-bordeaux hover:bg-bordeaux/90"
              onClick={pubblica}
              disabled={inviando}
            >
              {inviando && <Loader2 className="h-4 w-4 animate-spin" />}
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

/**
 * Le sei caselle del passo Foto. In frontend/ ognuna apre un toast di demo;
 * qui apre il selettore di file e carica davvero.
 */
function FotoGriglia({
  foto,
  inCorso,
  onCarica,
  onRimuovi,
}: {
  foto: { percorso: string; anteprima: string }[];
  inCorso: boolean;
  onCarica: (file: File) => void;
  onRimuovi: (indice: number) => void;
}) {
  const input = useRef<HTMLInputElement>(null);

  return (
    <>
      <input
        ref={input}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/avif"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) onCarica(file);
          // Azzerato per poter riselezionare lo stesso file dopo averlo tolto.
          e.target.value = "";
        }}
      />
      <div className="grid grid-cols-3 gap-3">
        {foto.map((f, i) => (
          <div key={f.percorso} className="relative aspect-square overflow-hidden rounded-xl border border-border">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={f.anteprima} alt="" className="h-full w-full object-cover" />
            <button
              onClick={() => onRimuovi(i)}
              aria-label="Rimuovi fotografia"
              className="absolute right-1 top-1 grid h-6 w-6 place-items-center rounded-full bg-antracite/70 text-crema hover:bg-antracite"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
        {Array.from({ length: Math.max(0, MAX_FOTO - foto.length) }).map((_, i) => (
          <button
            key={`vuota-${i}`}
            onClick={() => input.current?.click()}
            disabled={inCorso}
            className="grid aspect-square place-items-center rounded-xl border-2 border-dashed border-border bg-secondary/50 text-muted-foreground hover:border-bordeaux hover:text-bordeaux disabled:opacity-50"
          >
            {inCorso && i === 0 ? (
              <Loader2 className="h-6 w-6 animate-spin" />
            ) : (
              <Camera className="h-6 w-6" />
            )}
          </button>
        ))}
      </div>
      <p className="text-[11px] text-muted-foreground">
        JPEG, PNG, WebP o AVIF, fino a 5 MB per fotografia.
      </p>
    </>
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

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs uppercase tracking-wide text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}
