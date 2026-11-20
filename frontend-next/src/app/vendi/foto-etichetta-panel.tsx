"use client";

// WI-002 — «Fotografa l'etichetta», dentro il passo Identificazione di /vendi.
//
// Le quattro cose che l'utente vede sono tenute distinte, ognuna con la sua
// etichetta, e nessuna dice «verificato»:
//   • testo letto dalla fotografia (OCR: può contenere errori)
//   • corrispondenza trovata nei dati Vinea
//   • suggerimento AI non verificato (solo se l'utente lo chiede e le azioni AI sono accese)
//   • dato confermato dall'utente (l'unico che entra nel wizard)

import { useId, useRef, useState } from "react";
import { Camera, ImagePlus, Loader2, ScanText, Search, Sparkles, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useFotoEtichetta, type CampiConfermati, type OpzioniFotoEtichetta } from "@/hooks/useFotoEtichetta";
import type { CatalogazioneSuggerimento, Result } from "@/services/types";
import { ElencoCandidati } from "./elenco-candidati";
import { Field } from "./field";

export type AssistenzaAi = {
  chiedi: (ocrText: string) => Promise<Result<CatalogazioneSuggerimento>>;
};

type Props = OpzioniFotoEtichetta & {
  /** Presente solo con azioni AI accese e utente che le ha a disposizione. */
  ai?: AssistenzaAi | null;
  /** Carica la foto come foto della bottiglia: parte solo da un gesto esplicito. */
  conservaFoto?: ((file: File) => Promise<boolean>) | null;
};

const INTESTAZIONE_QUALITA = {
  buona: "Ho letto produttore, nome e annata. Controlla ogni campo: la lettura può sbagliare.",
  parziale: "Ho letto solo una parte dell'etichetta. Completa o correggi i campi.",
  scarsa: "Ho letto del testo ma nessun dato riconoscibile. Compila i campi a mano.",
} as const;

const ID = (base: string, chiave: string) => `${base}-${chiave}`;

export function FotoEtichettaPanel({ ai = null, conservaFoto = null, ...opzioni }: Props) {
  const stato = useFotoEtichetta(opzioni);
  const base = useId();
  const cameraRef = useRef<HTMLInputElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const [aiStato, setAiStato] = useState<
    | { fase: "ferma" }
    | { fase: "in_corso" }
    | { fase: "errore"; messaggio: string }
    | { fase: "pronto"; suggerimento: CatalogazioneSuggerimento }
  >({ fase: "ferma" });
  const [fotoConservata, setFotoConservata] = useState<"no" | "in_corso" | "si">("no");

  // Cambia a ogni foto: una risposta AI o un caricamento di una foto precedente non conta.
  const gettone = useRef(0);
  const inLettura = stato.fase === "in_corso";
  const haRisultato = stato.fase === "letta";

  const alCambioFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const scelto = e.target.files?.[0] ?? null;
    // Permette di scegliere di nuovo lo stesso file.
    e.target.value = "";
    gettone.current++;
    setAiStato({ fase: "ferma" });
    setFotoConservata("no");
    stato.scegliFile(scelto);
  };

  const chiediAi = async () => {
    if (!ai || !stato.testo.trim()) return;
    const mio = gettone.current;
    setAiStato({ fase: "in_corso" });
    const esito = await ai.chiedi(stato.testo.slice(0, 2000)).catch(() => null);
    if (mio !== gettone.current) return;
    if (!esito) setAiStato({ fase: "errore", messaggio: "Suggerimento non disponibile." });
    else if (!esito.ok) setAiStato({ fase: "errore", messaggio: esito.error });
    else setAiStato({ fase: "pronto", suggerimento: esito.data });
  };

  const usaSuggerimentoAi = (s: CatalogazioneSuggerimento) => {
    if (s.produttore) stato.modificaCampo("produttore", s.produttore);
    if (s.nome) stato.modificaCampo("nome", s.nome);
    if (s.annata) stato.modificaCampo("annata", String(s.annata));
    if (s.denominazione) stato.modificaCampo("denominazione", s.denominazione);
    setAiStato({ fase: "ferma" });
  };

  const conserva = async () => {
    if (!conservaFoto || !stato.file) return;
    const mio = gettone.current;
    setFotoConservata("in_corso");
    let riuscita = false;
    try {
      riuscita = await conservaFoto(stato.file);
    } catch {
      riuscita = false;
    }
    if (mio === gettone.current) setFotoConservata(riuscita ? "si" : "no");
  };

  const campo = (chiave: keyof CampiConfermati, etichetta: string, extra?: { tipo?: string; segnaposto?: string }) => (
    <Field label={etichetta} htmlFor={ID(base, chiave)}>
      <Input
        id={ID(base, chiave)}
        value={stato.campi[chiave]}
        onChange={(e) => stato.modificaCampo(chiave, e.target.value)}
        data-testid={`foto-etichetta-campo-${chiave}`}
        type={extra?.tipo}
        placeholder={extra?.segnaposto}
        maxLength={chiave === "annata" ? 4 : 120}
      />
    </Field>
  );

  return (
    <section
      className="rounded-2xl border border-border bg-card p-4"
      aria-labelledby={ID(base, "titolo")}
      data-testid="foto-etichetta-panel"
    >
      <div className="flex items-start gap-3">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-bordeaux text-crema">
          <ScanText className="h-4 w-4 text-oro" aria-hidden />
        </span>
        <div className="min-w-0">
          <h3 id={ID(base, "titolo")} className="font-serif text-base leading-tight">
            Fotografa l&apos;etichetta
          </h3>
          <p className="text-[11px] text-muted-foreground">
            La lettura avviene sul tuo dispositivo: la foto non viene inviata né pubblicata.
          </p>
        </div>
      </div>

      {/* Due ingressi: su smartphone il primo apre la fotocamera, su desktop entrambi aprono i file. */}
      <div className="mt-3 flex flex-wrap gap-2">
        <input
          ref={cameraRef}
          type="file"
          accept="image/*"
          capture="environment"
          className="sr-only"
          tabIndex={-1}
          aria-hidden
          data-testid="foto-etichetta-input-camera"
          onChange={alCambioFile}
        />
        <input
          ref={fileRef}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="sr-only"
          tabIndex={-1}
          aria-hidden
          data-testid="foto-etichetta-input-file"
          onChange={alCambioFile}
        />
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={inLettura || fotoConservata === "in_corso"}
          onClick={() => cameraRef.current?.click()}
          data-testid="foto-etichetta-scatta-btn"
        >
          <Camera className="h-3.5 w-3.5" /> Scatta una foto
        </Button>
        <Button
          type="button"
          size="sm"
          variant="outline"
          disabled={inLettura || fotoConservata === "in_corso"}
          onClick={() => fileRef.current?.click()}
          data-testid="foto-etichetta-scegli-btn"
        >
          <ImagePlus className="h-3.5 w-3.5" /> Scegli un&apos;immagine
        </Button>
      </div>

      {stato.fase === "errore" && stato.messaggio && (
        <p
          role="alert"
          className="mt-3 rounded-xl bg-destructive/10 px-3 py-2 text-xs text-destructive"
          data-testid="foto-etichetta-errore"
        >
          {stato.messaggio} Puoi sempre compilare i campi qui sotto a mano.
        </p>
      )}

      {stato.anteprima && (
        <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:items-start">
          {/* eslint-disable-next-line @next/next/no-img-element -- anteprima locale blob: della foto scelta, mai caricata */}
          <img
            src={stato.anteprima}
            alt="Anteprima della fotografia dell'etichetta"
            className="max-h-56 w-full rounded-xl border border-border object-contain sm:w-48"
            data-testid="foto-etichetta-anteprima"
          />
          <div className="flex flex-col gap-2">
            {!haRisultato && (
              <Button
                type="button"
                size="sm"
                className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
                disabled={inLettura}
                onClick={() => void stato.leggi()}
                data-testid="foto-etichetta-leggi-btn"
              >
                {inLettura ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin" /> Lettura in corso…
                  </>
                ) : (
                  <>
                    <ScanText className="h-3.5 w-3.5" /> Leggi l&apos;etichetta
                  </>
                )}
              </Button>
            )}
            {inLettura && (
              <>
                <p role="status" aria-live="polite" className="text-xs text-muted-foreground" data-testid="foto-etichetta-progresso">
                  Sto leggendo il testo… {Math.round(stato.progresso * 100)}%. La prima volta può
                  richiedere qualche secondo.
                </p>
                <Button type="button" size="sm" variant="ghost" onClick={stato.annullaLettura} data-testid="foto-etichetta-annulla-btn">
                  <X className="h-3.5 w-3.5" /> Annulla
                </Button>
              </>
            )}
            <Button type="button" size="sm" variant="ghost" onClick={() => {
                gettone.current++;
                setAiStato({ fase: "ferma" });
                setFotoConservata("no");
                stato.ricomincia();
              }}
              disabled={inLettura} data-testid="foto-etichetta-rimuovi-btn">
              Rimuovi la foto
            </Button>
          </div>
        </div>
      )}

      {haRisultato && stato.qualita && (
        <div className="mt-4 space-y-4" data-testid="foto-etichetta-risultato">
          <div>
            <p className="inline-flex rounded-full border border-border bg-muted px-2 py-0.5 text-[10px] font-medium">
              Testo letto dalla fotografia
            </p>
            <p className="mt-1 text-xs text-muted-foreground" role="status">
              {INTESTAZIONE_QUALITA[stato.qualita]}
            </p>
            <div className="mt-2 grid gap-3 md:grid-cols-2">
              {campo("produttore", "Produttore")}
              {campo("nome", "Nome / Etichetta")}
              {campo("annata", "Annata", { tipo: "text", segnaposto: "Es. 2019" })}
              {campo("denominazione", "Denominazione")}
            </div>
            {stato.annateAlternative.length > 0 && (
              <p className="mt-1 text-[11px] text-muted-foreground" data-testid="foto-etichetta-annate-multiple">
                Ho trovato più annate possibili ({stato.annateAlternative.join(", ")}): scegli quella
                giusta.
              </p>
            )}
            <details className="mt-2 text-[11px] text-muted-foreground">
              <summary className="cursor-pointer">Mostra il testo letto</summary>
              <pre className="mt-1 whitespace-pre-wrap rounded-lg bg-muted p-2" data-testid="foto-etichetta-testo">
                {stato.testo.trim()}
              </pre>
            </details>
          </div>

          <div data-testid="foto-etichetta-ricerca">
            <div className="flex flex-wrap items-center gap-2">
              <p className="inline-flex rounded-full border border-border bg-muted px-2 py-0.5 text-[10px] font-medium">
                Corrispondenze nei vini già presenti su Vinea
              </p>
              <Button type="button" size="sm" variant="ghost" onClick={stato.cercaDiNuovo} disabled={stato.faseRicerca === "in_corso"} data-testid="foto-etichetta-cerca-btn">
                <Search className="h-3.5 w-3.5" /> Cerca di nuovo
              </Button>
            </div>
            {stato.faseRicerca === "in_corso" && (
              <p role="status" className="mt-2 text-xs text-muted-foreground">
                Cerco nei vini di Vinea…
              </p>
            )}
            {stato.faseRicerca === "errore" && (
              <p role="alert" className="mt-2 text-xs text-destructive" data-testid="foto-etichetta-ricerca-errore">
                {stato.messaggioRicerca} Puoi continuare con i dati letti.
              </p>
            )}
            {stato.faseRicerca === "fatta" && stato.candidati.length === 0 && (
              <p className="mt-2 text-xs" data-testid="foto-etichetta-nessuna-corrispondenza">
                Nessuna corrispondenza trovata. Puoi continuare con i dati letti: è normale per i
                vini non ancora presenti su Vinea.
              </p>
            )}
            {stato.faseRicerca === "fatta" && stato.candidati.length > 0 && (
              <ElencoCandidati
                candidati={stato.candidati}
                sintesi={stato.sintesi}
                selezionato={stato.selezionato}
                onSeleziona={stato.seleziona}
                nomeGruppo={ID(base, "candidato")}
                prefissoTest="foto-etichetta"
              />
            )}
          </div>

          {ai && (
            <div data-testid="foto-etichetta-ai">
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={aiStato.fase === "in_corso"}
                onClick={() => void chiediAi()}
                data-testid="foto-etichetta-ai-btn"
              >
                {aiStato.fase === "in_corso" ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin" /> Analisi…
                  </>
                ) : (
                  <>
                    <Sparkles className="h-3.5 w-3.5" /> Chiedi aiuto all&apos;AI sul testo letto
                  </>
                )}
              </Button>
              <p className="mt-1 text-[11px] text-muted-foreground">
                Invia all&apos;AI il solo testo letto (non la foto). Solo se lo chiedi tu.
              </p>
              {aiStato.fase === "errore" && (
                <p role="alert" className="mt-2 text-xs text-destructive" data-testid="foto-etichetta-ai-errore">
                  {aiStato.messaggio}
                </p>
              )}
              {aiStato.fase === "pronto" && (
                <div className="mt-2 rounded-xl border border-oro/40 bg-oro/10 p-3 text-xs" data-testid="foto-etichetta-ai-suggerimento">
                  <p className="inline-flex rounded-full border border-oro/40 bg-oro/15 px-2 py-0.5 text-[10px] font-medium">
                    Suggerimento AI non verificato
                  </p>
                  <p className="mt-1">
                    {[aiStato.suggerimento.produttore, aiStato.suggerimento.nome, aiStato.suggerimento.annata]
                      .filter(Boolean)
                      .join(" · ") || "Nessun dato dedotto."}
                  </p>
                  <Button type="button" size="sm" variant="outline" className="mt-2" onClick={() => usaSuggerimentoAi(aiStato.suggerimento)} data-testid="foto-etichetta-ai-usa-btn">
                    Metti nei campi sopra
                  </Button>
                </div>
              )}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2 border-t border-border pt-3">
            <Button
              type="button"
              size="sm"
              className="rounded-full bg-bordeaux hover:bg-bordeaux/90"
              onClick={stato.conferma}
              disabled={!stato.campi.produttore.trim() && !stato.campi.nome.trim() && stato.selezionato === null}
              data-testid="foto-etichetta-conferma-btn"
            >
              Conferma e compila i campi
            </Button>
            {stato.applicato && (
              <span role="status" className="text-xs text-muted-foreground" data-testid="foto-etichetta-applicato">
                Dati confermati da te e applicati ai campi qui sotto. Puoi ancora modificarli.
              </span>
            )}
          </div>

          {conservaFoto && (
            <div className="text-xs">
              <Button
                type="button"
                size="sm"
                variant="ghost"
                disabled={fotoConservata !== "no"}
                onClick={() => void conserva()}
                data-testid="foto-etichetta-conserva-btn"
              >
                {fotoConservata === "si"
                  ? "Foto aggiunta alla bottiglia"
                  : fotoConservata === "in_corso"
                    ? "Caricamento…"
                    : "Conserva questa foto nella scheda della bottiglia"}
              </Button>
              <p className="text-[11px] text-muted-foreground">
                Facoltativo. Senza questo passaggio la foto non viene salvata.
              </p>
            </div>
          )}
        </div>
      )}

      <p className="mt-3 text-[11px] text-muted-foreground">
        Il riconoscimento non è perfetto e non attesta l&apos;autenticità della bottiglia. Puoi
        sempre compilare i campi a mano.
      </p>
    </section>
  );
}
