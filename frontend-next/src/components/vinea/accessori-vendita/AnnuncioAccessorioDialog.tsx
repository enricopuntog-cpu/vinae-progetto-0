"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Loader2 } from "lucide-react";
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
import { CONDIZIONI_ACCESSORIO, ETICHETTE_CONDIZIONE } from "@/lib/accessori/accessori";
import {
  ETICHETTE_STATO_ANNUNCIO,
  MAX_DESCRIZIONE_ANNUNCIO,
  centesimiDaEuro,
  moduloAnnuncioVuoto,
  moduloDaAnnuncio,
  quantitaMassimaAnnuncio,
  validaModuloAnnuncio,
  MAX_PREZZO_CENTS,
  MIN_PREZZO_CENTS,
  type AnnuncioAccessorio,
  type ErroriModuloAnnuncio,
  type ModuloAnnuncio,
} from "@/lib/accessori-vendita/annunci-accessori";
import type { AccessorioPersonale } from "@/lib/cantina-accessori/cantina-accessori";
import type { AnnunciAccessoriService } from "@/services/types";
import { RiepilogoEconomico, type StatoRiepilogo } from "./RiepilogoEconomico";

/**
 * Preparazione dell'annuncio di un accessorio posseduto (VPM-015B2).
 *
 * Una BOZZA: nessuno può acquistarla e non compare fra le bottiglie. Il browser
 * sceglie quantità e prezzo richiesto; classe, commissione e totale sono del
 * database (riepilogo). Il dialogo non ha alcun gesto di pubblicazione o
 * d'acquisto: il massimo è «Invia in revisione», che oggi non ha un
 * destinatario operativo.
 */

const CAMPO =
  "w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-bordeaux disabled:opacity-60";

type Messaggio = { tono: "ok" | "errore"; testo: string } | null;

function Avviso({ messaggio }: { messaggio: Messaggio }) {
  if (!messaggio) return null;
  return (
    <p
      role={messaggio.tono === "errore" ? "alert" : "status"}
      className={`rounded-lg border px-3 py-2 text-sm ${
        messaggio.tono === "errore"
          ? "border-bordeaux/40 bg-bordeaux/5 text-bordeaux"
          : "border-salvia/40 bg-salvia/10 text-antracite"
      }`}
    >
      {messaggio.testo}
    </p>
  );
}

type Props = {
  accessorio: Pick<AccessorioPersonale, "id" | "nome" | "condizione" | "quantita" | "immagini">;
  annuncio: AnnuncioAccessorio | null;
  servizio: AnnunciAccessoriService;
  onChiudi: () => void;
  onCambiato: () => Promise<void>;
};

export function AnnuncioAccessorioDialog({ accessorio, annuncio, servizio, onChiudi, onCambiato }: Props) {
  // L'id di un annuncio nuovo lo sceglie il client: ripetere il salvataggio dopo
  // un errore di rete non ne crea due.
  const [idNuovo] = useState(() => crypto.randomUUID());
  const [corrente, setCorrente] = useState<AnnuncioAccessorio | null>(annuncio);
  const [modulo, setModulo] = useState<ModuloAnnuncio>(
    annuncio ? moduloDaAnnuncio(annuncio) : moduloAnnuncioVuoto(accessorio.condizione),
  );
  const [errori, setErrori] = useState<ErroriModuloAnnuncio>({});
  const [messaggio, setMessaggio] = useState<Messaggio>(null);
  const [inCorso, setInCorso] = useState(false);
  const [confermaRitiro, setConfermaRitiro] = useState(false);
  const [riepilogo, setRiepilogo] = useState<StatoRiepilogo>({ tipo: "vuoto" });

  const inRevisione = corrente?.stato === "in_revisione";
  const massimo = quantitaMassimaAnnuncio(accessorio.quantita, 0);
  const modificato = useMemo(
    () => (corrente ? JSON.stringify(modulo) !== JSON.stringify(moduloDaAnnuncio(corrente)) : true),
    [corrente, modulo],
  );
  const senzaFoto = accessorio.immagini.length === 0;

  // Riepilogo economico: richiesto al database quando prezzo e quantità sono
  // plausibili. Il risultato di una richiesta superata non sostituisce quello nuovo.
  const prezzoCents = centesimiDaEuro(modulo.prezzo);
  const quantitaNum = /^\d{1,3}$/.test(modulo.quantita.trim()) ? Number(modulo.quantita) : null;
  const richiedibile =
    prezzoCents !== null && prezzoCents >= MIN_PREZZO_CENTS && prezzoCents <= MAX_PREZZO_CENTS &&
    quantitaNum !== null && quantitaNum >= 1 && quantitaNum <= Math.max(massimo, 1);

  useEffect(() => {
    if (!richiedibile || prezzoCents === null || quantitaNum === null) {
      setRiepilogo({ tipo: "vuoto" });
      return;
    }
    let attivo = true;
    setRiepilogo({ tipo: "caricamento" });
    const t = setTimeout(async () => {
      const r = await servizio.preventivo(prezzoCents, quantitaNum, accessorio.id);
      if (!attivo) return;
      setRiepilogo(r.ok ? { tipo: "pronto", dati: r.data } : { tipo: "errore", messaggio: r.error });
    }, 350);
    return () => {
      attivo = false;
      clearTimeout(t);
    };
  }, [servizio, accessorio.id, richiedibile, prezzoCents, quantitaNum]);

  const aggiorna = <K extends keyof ModuloAnnuncio>(campo: K, valore: ModuloAnnuncio[K]) =>
    setModulo((m) => ({ ...m, [campo]: valore }));

  const salva = async (e: FormEvent) => {
    e.preventDefault();
    if (inRevisione) return;
    const v = validaModuloAnnuncio(modulo, accessorio.id, massimo);
    if (!v.ok) {
      setErrori(v.errori);
      return;
    }
    setErrori({});
    setInCorso(true);
    const r = await servizio.salva(corrente?.id ?? idNuovo, v.dati);
    setInCorso(false);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    setCorrente(r.data);
    setModulo(moduloDaAnnuncio(r.data));
    setMessaggio({ tono: "ok", testo: "Bozza salvata. Non è in vendita: le vendite non sono ancora attive." });
    await onCambiato();
  };

  const passa = async (a: "bozza" | "in_revisione" | "ritirato", testo: string) => {
    if (!corrente) return;
    setInCorso(true);
    const r = await servizio.transizione(corrente.id, a);
    setInCorso(false);
    setConfermaRitiro(false);
    if (!r.ok) return setMessaggio({ tono: "errore", testo: r.error });
    await onCambiato();
    if (a === "ritirato") {
      onChiudi();
      return;
    }
    setCorrente(r.data);
    setModulo(moduloDaAnnuncio(r.data));
    setMessaggio({ tono: "ok", testo });
  };

  const errore = (campo: keyof ModuloAnnuncio) =>
    errori[campo] ? (
      <p role="alert" id={`aa-${campo}-errore`} className="mt-1 text-xs text-bordeaux">
        {errori[campo]}
      </p>
    ) : null;
  const descritto = (campo: keyof ModuloAnnuncio) => (errori[campo] ? `aa-${campo}-errore` : undefined);

  return (
    <Dialog open onOpenChange={(aperto) => (aperto ? null : onChiudi())}>
      <DialogContent className="max-h-[90vh] overflow-y-auto" data-testid="annuncio-accessorio-dialog">
        <DialogHeader>
          <DialogTitle>
            {corrente ? `Annuncio di «${accessorio.nome}»` : `Prepara la vendita di «${accessorio.nome}»`}
          </DialogTitle>
          <DialogDescription>
            {corrente
              ? `Stato: ${ETICHETTE_STATO_ANNUNCIO[corrente.stato]}.`
              : "Scegli quanti pezzi e a che prezzo: gli altri restano tuoi."}
          </DialogDescription>
        </DialogHeader>

        <p
          role="note"
          data-testid="avviso-vendite-disattivate"
          className="rounded-lg border border-border bg-secondary/60 px-3 py-2 text-sm"
        >
          <strong>Le vendite non sono ancora attive.</strong> Questa è solo la preparazione dell&apos;annuncio:
          nessuno può acquistarlo e non compare fra le bottiglie.
        </p>

        <form onSubmit={salva} className="space-y-4" aria-label="Annuncio accessorio">
          <Avviso messaggio={messaggio} />

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="aa-quantita">Pezzi in vendita</Label>
              <Input
                id="aa-quantita"
                inputMode="numeric"
                value={modulo.quantita}
                disabled={inRevisione}
                aria-describedby={`aa-quantita-aiuto ${descritto("quantita") ?? ""}`.trim()}
                aria-invalid={errori.quantita ? true : undefined}
                onChange={(e) => aggiorna("quantita", e.target.value)}
              />
              <p id="aa-quantita-aiuto" className="mt-1 text-xs text-muted-foreground">
                Ne possiedi {accessorio.quantita}: {accessorio.quantita === 1 ? "è quello" : "gli altri restano tuoi"}.
              </p>
              {errore("quantita")}
            </div>
            <div>
              <Label htmlFor="aa-prezzo">Prezzo per pezzo che vuoi ricevere (€)</Label>
              <Input
                id="aa-prezzo"
                inputMode="decimal"
                placeholder="12,50"
                value={modulo.prezzo}
                disabled={inRevisione}
                aria-describedby={`aa-prezzo-aiuto ${descritto("prezzo") ?? ""}`.trim()}
                aria-invalid={errori.prezzo ? true : undefined}
                onChange={(e) => aggiorna("prezzo", e.target.value)}
              />
              <p id="aa-prezzo-aiuto" className="mt-1 text-xs text-muted-foreground">
                Da 1 € a 10.000 €. Commissione e costi di pagamento si aggiungono per l&apos;acquirente.
              </p>
              {errore("prezzo")}
            </div>
          </div>

          <div>
            <Label htmlFor="aa-condizione">Condizione</Label>
            <select
              id="aa-condizione"
              className={CAMPO}
              value={modulo.condizione}
              disabled={inRevisione}
              onChange={(e) => aggiorna("condizione", e.target.value as ModuloAnnuncio["condizione"])}
            >
              {CONDIZIONI_ACCESSORIO.map((c) => (
                <option key={c} value={c}>
                  {ETICHETTE_CONDIZIONE[c]}
                </option>
              ))}
            </select>
            {errore("condizione")}
          </div>

          <div>
            <Label htmlFor="aa-descrizione">Descrizione dell&apos;offerta (facoltativa)</Label>
            <Textarea
              id="aa-descrizione"
              rows={3}
              maxLength={MAX_DESCRIZIONE_ANNUNCIO}
              value={modulo.descrizione}
              disabled={inRevisione}
              onChange={(e) => aggiorna("descrizione", e.target.value)}
            />
            {errore("descrizione")}
          </div>

          <details className="rounded-lg border border-border px-3 py-2">
            <summary className="cursor-pointer text-sm font-medium">Dati del pacco (facoltativi)</summary>
            <div className="mt-3 space-y-3">
              <p className="text-xs text-muted-foreground">
                La spedizione è a carico dell&apos;acquirente e l&apos;imballaggio lo prepari tu, con una scatola
                adatta: Vinea non addebita né rimborsa costi di scatola. Peso e misure (per pezzo, con
                l&apos;imballaggio) serviranno a preventivare la spedizione.
              </p>
              <div className="grid gap-3 sm:grid-cols-4">
                <div>
                  <Label htmlFor="aa-peso">Peso (g)</Label>
                  <Input
                    id="aa-peso"
                    inputMode="numeric"
                    value={modulo.pesoG}
                    disabled={inRevisione}
                    onChange={(e) => aggiorna("pesoG", e.target.value)}
                  />
                  {errore("pesoG")}
                </div>
                <div>
                  <Label htmlFor="aa-lunghezza">Lungh. (mm)</Label>
                  <Input
                    id="aa-lunghezza"
                    inputMode="numeric"
                    value={modulo.lunghezzaMm}
                    disabled={inRevisione}
                    onChange={(e) => aggiorna("lunghezzaMm", e.target.value)}
                  />
                  {errore("lunghezzaMm")}
                </div>
                <div>
                  <Label htmlFor="aa-larghezza">Largh. (mm)</Label>
                  <Input
                    id="aa-larghezza"
                    inputMode="numeric"
                    value={modulo.larghezzaMm}
                    disabled={inRevisione}
                    onChange={(e) => aggiorna("larghezzaMm", e.target.value)}
                  />
                  {errore("larghezzaMm")}
                </div>
                <div>
                  <Label htmlFor="aa-altezza">Alt. (mm)</Label>
                  <Input
                    id="aa-altezza"
                    inputMode="numeric"
                    value={modulo.altezzaMm}
                    disabled={inRevisione}
                    onChange={(e) => aggiorna("altezzaMm", e.target.value)}
                  />
                  {errore("altezzaMm")}
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={modulo.fragile}
                  disabled={inRevisione}
                  onChange={(e) => aggiorna("fragile", e.target.checked)}
                />
                Fragile (vetro, cristallo)
              </label>
            </div>
          </details>

          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              className="mt-1"
              checked={modulo.conforme}
              disabled={inRevisione}
              onChange={(e) => aggiorna("conforme", e.target.checked)}
            />
            <span>
              Dichiaro che l&apos;articolo non è un prodotto alcolico né un articolo regolamentato (come armi o
              sciabole).
            </span>
          </label>

          <RiepilogoEconomico stato={riepilogo} />

          {senzaFoto ? (
            <p className="text-xs text-muted-foreground" data-testid="aa-foto-mancante">
              Per inviare l&apos;annuncio in revisione serve almeno una foto dell&apos;accessorio: aggiungila da
              «Modifica» sulla scheda.
            </p>
          ) : null}

          <DialogFooter className="gap-2 sm:flex-wrap">
            <Button type="button" variant="ghost" onClick={onChiudi}>
              Chiudi
            </Button>
            {corrente && !confermaRitiro ? (
              <Button type="button" variant="ghost" disabled={inCorso} onClick={() => setConfermaRitiro(true)}>
                Ritira annuncio
              </Button>
            ) : null}
            {confermaRitiro ? (
              <Button type="button" variant="outline" disabled={inCorso} onClick={() => void passa("ritirato", "")}>
                Sì, ritira l&apos;annuncio
              </Button>
            ) : null}
            {inRevisione ? (
              <Button
                type="button"
                variant="outline"
                disabled={inCorso}
                onClick={() => void passa("bozza", "Annuncio riportato in bozza.")}
              >
                Riporta in bozza
              </Button>
            ) : (
              <>
                {corrente?.stato === "bozza" ? (
                  <Button
                    type="button"
                    variant="outline"
                    disabled={inCorso || modificato || senzaFoto}
                    onClick={() => void passa("in_revisione", "Annuncio inviato in revisione. Non è in vendita.")}
                  >
                    Invia in revisione
                  </Button>
                ) : null}
                <Button type="submit" disabled={inCorso}>
                  {inCorso ? <Loader2 className="animate-spin" aria-hidden /> : null} Salva bozza
                </Button>
              </>
            )}
          </DialogFooter>
          {corrente?.stato === "bozza" && modificato ? (
            <p className="text-xs text-muted-foreground">Salva le modifiche prima di inviare in revisione.</p>
          ) : null}
        </form>
      </DialogContent>
    </Dialog>
  );
}
