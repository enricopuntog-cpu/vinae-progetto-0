"use client";

import { useRef, useState } from "react";
import { Info, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import type { Result } from "@/services/types";
import {
  LIMITI_NOTA,
  confrontaConCatalogo,
  eNotaVuota,
  validaNotaPersonale,
  type CampoNota,
  type NotaPersonaleVino,
} from "@/lib/cantina/note-personali";

type EsitoScrittura = Result<void>;

export type VinoPerNota = {
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  denominazione: string;
  formato: string;
  wineSlug?: string;
};

type Form = {
  abbinamenti: string;
  temperatura: string;
  decantazione: string;
  calice: string;
  annata: string;
  nv: boolean;
  denominazione: string;
  regione: string;
  osservazioni: string;
};

const formDa = (n: NotaPersonaleVino | undefined): Form => ({
  abbinamenti: n?.abbinamenti.join("\n") ?? "",
  temperatura: n?.temperaturaC?.toString() ?? "",
  decantazione: n?.decantazioneMinuti?.toString() ?? "",
  calice: n?.calice ?? "",
  annata: n?.annataDichiarata?.toString() ?? "",
  nv: n?.nonMillesimato ?? false,
  denominazione: n?.denominazione ?? "",
  regione: n?.regione ?? "",
  osservazioni: n?.osservazioni ?? "",
});

const formVuoto = (f: Form) =>
  !f.nv && [f.abbinamenti, f.temperatura, f.decantazione, f.calice, f.annata, f.denominazione, f.regione, f.osservazioni].every(
    (v) => v.trim() === "",
  );

function righeRiepilogo(n: NotaPersonaleVino): { etichetta: string; testo: string }[] {
  const out: { etichetta: string; testo: string }[] = [];
  if (n.abbinamenti.length > 0) out.push({ etichetta: "Abbinamenti", testo: n.abbinamenti.join(" · ") });
  if (n.temperaturaC !== null) out.push({ etichetta: "Temperatura di servizio", testo: `${n.temperaturaC} °C` });
  if (n.decantazioneMinuti !== null) out.push({ etichetta: "Decantazione", testo: `${n.decantazioneMinuti} minuti` });
  if (n.calice) out.push({ etichetta: "Calice", testo: n.calice });
  if (n.nonMillesimato) out.push({ etichetta: "Annata", testo: "Non millesimato" });
  else if (n.annataDichiarata !== null) out.push({ etichetta: "Annata", testo: String(n.annataDichiarata) });
  if (n.denominazione) out.push({ etichetta: "Denominazione", testo: n.denominazione });
  if (n.regione) out.push({ etichetta: "Regione", testo: n.regione });
  if (n.osservazioni) out.push({ etichetta: "Osservazioni", testo: n.osservazioni });
  return out;
}

const NOME_CAMPO = { annata: "Annata", regione: "Regione", denominazione: "Denominazione" } as const;

function Campo({
  id,
  etichetta,
  errore,
  aiuto,
  children,
}: {
  id: string;
  etichetta: string;
  errore?: string;
  aiuto?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{etichetta}</Label>
      {children}
      {aiuto ? (
        <p id={`${id}-aiuto`} className="text-[11px] text-muted-foreground">
          {aiuto}
        </p>
      ) : null}
      {errore ? (
        <p id={`${id}-errore`} className="text-xs font-medium text-bordeaux" data-testid={`nota-errore-${id}`}>
          {errore}
        </p>
      ) : null}
    </div>
  );
}

function Corpo({
  vino,
  nota,
  onChiudi,
  onSalva,
  onElimina,
}: {
  vino: VinoPerNota;
  nota: NotaPersonaleVino | undefined;
  onChiudi: () => void;
  onSalva: (slug: string, nota: NotaPersonaleVino) => Promise<EsitoScrittura>;
  onElimina: (slug: string) => Promise<EsitoScrittura>;
}) {
  const [passo, setPasso] = useState<"modifica" | "conferma">("modifica");
  const [form, setForm] = useState<Form>(() => formDa(nota));
  const [errori, setErrori] = useState<Partial<Record<CampoNota, string>>>({});
  const [validata, setValidata] = useState<NotaPersonaleVino | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const [erroreSalvataggio, setErroreSalvataggio] = useState("");
  const [confermaElimina, setConfermaElimina] = useState(false);
  const inVolo = useRef(false);

  const slug = vino.wineSlug ?? "";
  const imposta = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));
  const senzaAnnata = !(Number.isFinite(vino.annata) && vino.annata > 0);

  const rivedi = () => {
    const esito = validaNotaPersonale({
      abbinamenti: form.abbinamenti,
      temperaturaC: form.temperatura,
      decantazioneMinuti: form.decantazione,
      calice: form.calice,
      annataDichiarata: form.annata,
      nonMillesimato: form.nv,
      denominazione: form.denominazione,
      regione: form.regione,
      osservazioni: form.osservazioni,
    });
    if (!esito.ok) {
      setErrori(esito.errori);
      const primo = Object.keys(esito.errori)[0];
      if (primo) setTimeout(() => document.getElementById(primo)?.focus(), 0);
      return;
    }
    setErrori({});
    setErroreSalvataggio("");
    setValidata(esito.nota);
    setPasso("conferma");
  };

  const salva = async () => {
    if (!validata || inVolo.current) return;
    inVolo.current = true;
    setInCorso(true);
    setErroreSalvataggio("");
    const esito = await onSalva(slug, validata);
    inVolo.current = false;
    setInCorso(false);
    if (esito.ok) onChiudi();
    else setErroreSalvataggio(esito.error);
  };

  const elimina = async () => {
    if (inVolo.current) return;
    inVolo.current = true;
    setInCorso(true);
    setErroreSalvataggio("");
    const esito = await onElimina(slug);
    inVolo.current = false;
    setInCorso(false);
    if (esito.ok) onChiudi();
    else {
      setConfermaElimina(false);
      setErroreSalvataggio(esito.error);
    }
  };

  const conflitti = validata ? confrontaConCatalogo(validata, vino) : [];

  const err = (c: CampoNota) => errori[c];
  const invalido = (c: CampoNota) => (err(c) ? ({ "aria-invalid": true, "aria-describedby": `${c}-errore` } as const) : {});

  return (
    <>
      <DialogHeader>
        <DialogTitle className="font-serif text-xl">Completa le informazioni</DialogTitle>
        <DialogDescription>
          {vino.produttore} · {vino.nome}
          {vino.formato ? ` · ${vino.formato}` : ""}
        </DialogDescription>
      </DialogHeader>

      <p
        className="flex items-start gap-2 rounded-xl bg-secondary/60 p-3 text-xs leading-snug text-muted-foreground"
        data-testid="nota-privacy"
      >
        <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
        <span>
          Queste informazioni sono tue: restano private e sono dichiarazioni personali, non certificate. Non cambiano la
          scheda condivisa del vino né i dati degli altri utenti.
        </span>
      </p>

      {passo === "modifica" ? (
        <div className="space-y-4" data-testid="nota-modifica">
          <section aria-label="Cosa riporta il database Vinea" data-testid="nota-catalogo" className="rounded-xl border border-border p-3">
            <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
              Cosa riporta il database Vinea (condiviso, non modificabile da qui)
            </p>
            <dl className="mt-1 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-sm">
              <dt className="text-muted-foreground">Annata</dt>
              <dd>{senzaAnnata ? "Non indicata (senza annata)" : vino.annata}</dd>
              <dt className="text-muted-foreground">Regione</dt>
              <dd>{vino.regione || "Non indicata"}</dd>
              <dt className="text-muted-foreground">Denominazione</dt>
              <dd>{vino.denominazione || "Non indicata"}</dd>
            </dl>
          </section>

          <Campo
            id="abbinamenti"
            etichetta="Abbinamenti"
            aiuto={`Uno per riga, al massimo ${LIMITI_NOTA.abbinamentiMax}. Per esempio «Brasato al Barolo».`}
            errore={err("abbinamenti")}
          >
            <Textarea
              id="abbinamenti"
              data-testid="nota-abbinamenti"
              rows={4}
              value={form.abbinamenti}
              onChange={(e) => imposta("abbinamenti", e.target.value)}
              {...invalido("abbinamenti")}
            />
          </Campo>

          <div className="grid gap-4 sm:grid-cols-2">
            <Campo id="temperaturaC" etichetta="Temperatura di servizio (°C)" errore={err("temperaturaC")}>
              <Input
                id="temperaturaC"
                data-testid="nota-temperatura"
                inputMode="numeric"
                value={form.temperatura}
                onChange={(e) => imposta("temperatura", e.target.value)}
                {...invalido("temperaturaC")}
              />
            </Campo>
            <Campo id="decantazioneMinuti" etichetta="Decantazione (minuti)" errore={err("decantazioneMinuti")}>
              <Input
                id="decantazioneMinuti"
                data-testid="nota-decantazione"
                inputMode="numeric"
                value={form.decantazione}
                onChange={(e) => imposta("decantazione", e.target.value)}
                {...invalido("decantazioneMinuti")}
              />
            </Campo>
          </div>

          <Campo id="calice" etichetta="Calice" errore={err("calice")}>
            <Input
              id="calice"
              data-testid="nota-calice"
              value={form.calice}
              onChange={(e) => imposta("calice", e.target.value)}
              {...invalido("calice")}
            />
          </Campo>

          <fieldset className="space-y-3 rounded-xl border border-border p-3">
            <legend className="px-1 text-xs font-medium text-muted-foreground">Cosa so di questo vino</legend>
            <div className="grid gap-4 sm:grid-cols-2">
              <Campo
                id="annataDichiarata"
                etichetta="Annata"
                aiuto={senzaAnnata ? "Il database non indica un'annata: non è un errore." : undefined}
                errore={err("annataDichiarata")}
              >
                <Input
                  id="annataDichiarata"
                  data-testid="nota-annata"
                  inputMode="numeric"
                  value={form.annata}
                  onChange={(e) => imposta("annata", e.target.value)}
                  {...invalido("annataDichiarata")}
                />
              </Campo>
              <label className="flex items-center gap-2 self-end pb-2 text-sm">
                <input
                  type="checkbox"
                  data-testid="nota-nv"
                  checked={form.nv}
                  onChange={(e) => imposta("nv", e.target.checked)}
                  className="h-4 w-4 accent-[var(--bordeaux,#6b1f2a)]"
                />
                Vino non millesimato
              </label>
            </div>
            <Campo id="denominazione" etichetta="Denominazione" errore={err("denominazione")}>
              <Input
                id="denominazione"
                data-testid="nota-denominazione"
                value={form.denominazione}
                onChange={(e) => imposta("denominazione", e.target.value)}
                {...invalido("denominazione")}
              />
            </Campo>
            <Campo id="regione" etichetta="Regione" errore={err("regione")}>
              <Input
                id="regione"
                data-testid="nota-regione"
                value={form.regione}
                onChange={(e) => imposta("regione", e.target.value)}
                {...invalido("regione")}
              />
            </Campo>
          </fieldset>

          <Campo
            id="osservazioni"
            etichetta="Osservazioni sulla bottiglia"
            aiuto={`${form.osservazioni.length}/${LIMITI_NOTA.osservazioniMax} caratteri`}
            errore={err("osservazioni")}
          >
            <Textarea
              id="osservazioni"
              data-testid="nota-osservazioni"
              rows={3}
              value={form.osservazioni}
              onChange={(e) => imposta("osservazioni", e.target.value)}
              {...invalido("osservazioni")}
            />
          </Campo>

          {erroreSalvataggio ? (
            <p role="alert" className="text-sm font-medium text-bordeaux">
              {erroreSalvataggio}
            </p>
          ) : null}

          <DialogFooter className="flex-col gap-2 sm:flex-row sm:justify-between" data-testid="nota-azioni">
            <div className="flex flex-wrap gap-2">
              {nota && !confermaElimina ? (
                <Button type="button" variant="outline" data-testid="nota-elimina" onClick={() => setConfermaElimina(true)}>
                  Elimina le mie annotazioni
                </Button>
              ) : null}
              {nota && confermaElimina ? (
                <>
                  <Button
                    type="button"
                    variant="destructive"
                    data-testid="nota-elimina-conferma"
                    disabled={inCorso}
                    onClick={() => void elimina()}
                  >
                    {inCorso ? "Elimino…" : "Sì, elimina"}
                  </Button>
                  <Button type="button" variant="outline" data-testid="nota-elimina-annulla" onClick={() => setConfermaElimina(false)}>
                    Non eliminare
                  </Button>
                </>
              ) : null}
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="outline" data-testid="nota-annulla" onClick={onChiudi}>
                Annulla
              </Button>
              <Button
                type="button"
                className="bg-bordeaux hover:bg-bordeaux/90"
                data-testid="nota-rivedi"
                disabled={formVuoto(form) && !nota}
                onClick={rivedi}
              >
                Rivedi
              </Button>
            </div>
          </DialogFooter>
        </div>
      ) : (
        <div className="space-y-4" data-testid="nota-conferma">
          <h3 className="font-serif text-lg">Controlla prima di salvare</h3>
          {validata && !eNotaVuota(validata) ? (
            <dl className="space-y-2 text-sm">
              {righeRiepilogo(validata).map((r) => (
                <div key={r.etichetta} className="flex flex-wrap items-start justify-between gap-x-3 gap-y-1">
                  <div className="min-w-0">
                    <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{r.etichetta}</dt>
                    <dd className="whitespace-pre-line">{r.testo}</dd>
                  </div>
                  <span className="shrink-0 rounded-full bg-oro/20 px-2 py-0.5 text-[10px] font-semibold text-antracite">
                    Dichiarato da te · privato
                  </span>
                </div>
              ))}
            </dl>
          ) : (
            <p className="text-sm">
              Non c'è più nessuna informazione: salvando rimuoverai tutte le tue annotazioni su questo vino.
            </p>
          )}

          {conflitti.length > 0 ? (
            <ul className="space-y-1.5" data-testid="nota-conflitti">
              {conflitti.map((c) => (
                <li key={c.campo} className="flex items-start gap-2 rounded-xl bg-secondary/60 p-2.5 text-xs text-muted-foreground">
                  <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                  <span>
                    {NOME_CAMPO[c.campo]}: tu indichi «{c.personale}», il database Vinea riporta «{c.catalogo}». Il database
                    non cambia: la tua dichiarazione resta privata e vale solo per te.
                  </span>
                </li>
              ))}
            </ul>
          ) : null}

          {erroreSalvataggio ? (
            <p role="alert" className="text-sm font-medium text-bordeaux">
              {erroreSalvataggio}
            </p>
          ) : null}

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button type="button" variant="outline" data-testid="nota-indietro" disabled={inCorso} onClick={() => setPasso("modifica")}>
              Torna a modificare
            </Button>
            <Button
              type="button"
              className="bg-bordeaux hover:bg-bordeaux/90"
              data-testid="nota-salva"
              disabled={inCorso}
              onClick={() => void salva()}
            >
              {inCorso ? "Salvo…" : "Conferma e salva"}
            </Button>
          </DialogFooter>
        </div>
      )}
    </>
  );
}

/**
 * WI-005B — «Completa le informazioni»: l'utente annota abbinamenti, servizio, identità dichiarata
 * e osservazioni su un vino della propria Cantina. Passi: Modifica → Rivedi → Conferma e salva.
 * Nulla viene salvato prima della conferma. Sono dichiarazioni personali: private, non certificate,
 * e non modificano mai il catalogo condiviso (il dialogo lo dice e mostra i dati Vinea accanto).
 */
export function NotaPersonaleDialog({
  vino,
  nota,
  open,
  onOpenChange,
  onSalva,
  onElimina,
}: {
  vino: VinoPerNota | null;
  nota: NotaPersonaleVino | undefined;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSalva: (slug: string, nota: NotaPersonaleVino) => Promise<EsitoScrittura>;
  onElimina: (slug: string) => Promise<EsitoScrittura>;
}) {
  return (
    <Dialog open={open && vino !== null} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90dvh] max-w-xl overflow-y-auto">
        {open && vino ? (
          <Corpo
            // Stato nuovo a ogni apertura e a ogni vino: i campi partono dalla nota salvata.
            key={vino.wineSlug ?? vino.nome}
            vino={vino}
            nota={nota}
            onChiudi={() => onOpenChange(false)}
            onSalva={onSalva}
            onElimina={onElimina}
          />
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
