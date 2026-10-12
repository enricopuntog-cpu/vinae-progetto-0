"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { PackagePlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { PrezzoPerAcquirente } from "@/components/vinea/PrezzoPerAcquirente";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createListingService } from "@/services/listing-service";
import { creaPreventivoService, type PreventivoVendita } from "@/services/preventivo-service";
import type { GruppoScorte } from "@/services/partner-scorte-service";

const CONDIZIONI = ["Perfetto", "Ottimo", "Buono"] as const;
const MAX_PER_PRODOTTO = 120;

/** Centesimi da un importo scritto in euro («45», «45,50», «45.5»). */
export function centesimiDaEuro(testo: string): number | null {
  const pulito = testo.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(pulito)) return null;
  const cents = Math.round(Number(pulito) * 100);
  return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

/**
 * VP-D: un prodotto commerciale nasce in bozza dalle scorte libere di un
 * gruppo (stesso vino, annata e formato), con il prezzo per bottiglia che il
 * Partner vuole ricevere. Le unità sono le prime libere in ordine d'ingresso;
 * il database le riverifica tutte (proprie, commerciali, dello stesso Partner,
 * chiuse e in nessun altro prodotto). La spiegazione del prezzo viene da
 * `preventivo_vendita`, con la classe che il database attribuisce al Partner.
 */
export function CreaProdottoPartner({
  gruppo,
  libere,
}: {
  gruppo: GruppoScorte;
  /** Unità libere del gruppo; `null` se non si è potuto verificarlo. */
  libere: string[] | null;
}) {
  const router = useRouter();
  const client = getSupabaseClient();
  const preventivi = useMemo(() => creaPreventivoService(client), [client]);
  const annunci = useMemo(() => createListingService(client), [client]);
  const massimo = Math.min(libere?.length ?? 0, MAX_PER_PRODOTTO);

  const [aperto, setAperto] = useState(false);
  const [quantita, setQuantita] = useState(String(Math.max(1, massimo)));
  const [prezzo, setPrezzo] = useState("");
  const [condizione, setCondizione] = useState<(typeof CONDIZIONI)[number]>("Perfetto");
  const [conservazione, setConservazione] = useState("");
  const [descrizione, setDescrizione] = useState("");
  const [stima, setStima] = useState<PreventivoVendita | null>(null);
  const [stimaErrore, setStimaErrore] = useState(false);
  const [inCorso, setInCorso] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);

  const q = Number(quantita);
  const quantitaValida = Number.isInteger(q) && q >= 1 && q <= massimo;
  const cents = centesimiDaEuro(prezzo);

  useEffect(() => {
    setStima(null);
    setStimaErrore(false);
    if (!aperto || cents === null || !quantitaValida) return;
    let attivo = true;
    const timer = setTimeout(() => {
      void preventivi.vendita(cents, q, "commerciale").then((esito) => {
        if (!attivo) return;
        if (esito.ok) setStima(esito.data);
        else setStimaErrore(true);
      });
    }, 300);
    return () => {
      attivo = false;
      clearTimeout(timer);
    };
  }, [aperto, cents, q, quantitaValida, preventivi]);

  if (!libere) {
    return (
      <p className="text-xs text-muted-foreground" data-testid="crea-prodotto-non-verificato">
        Non è stato possibile verificare le unità libere: riprova a ricaricare la pagina.
      </p>
    );
  }
  if (massimo === 0) {
    return (
      <p className="text-xs text-muted-foreground" data-testid="crea-prodotto-nessuna-libera">
        Tutte le unità sono già in un prodotto.
      </p>
    );
  }

  const crea = async () => {
    if (!quantitaValida || cents === null) {
      setErrore("Indica quante bottiglie e il prezzo per bottiglia.");
      return;
    }
    setInCorso(true);
    setErrore(null);
    const esito = await annunci.creaLotto({
      bottleUnitIds: libere.slice(0, q),
      prezzoCents: cents,
      condizione,
      conservazione: conservazione.trim(),
      storia: descrizione.trim(),
      immagini: [],
    });
    setInCorso(false);
    if (!esito.ok) {
      setErrore(esito.error);
      return;
    }
    setAperto(false);
    router.push(`/annuncio/${esito.data.slug}`);
  };

  return (
    <Dialog open={aperto} onOpenChange={setAperto}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" data-testid={`crea-prodotto-${gruppo.chiave}`}>
          <PackagePlus className="mr-1 h-4 w-4" aria-hidden /> Crea prodotto
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="font-serif text-2xl">Nuovo prodotto</DialogTitle>
          <DialogDescription>
            {gruppo.produttore} {gruppo.nome} {gruppo.annata} · {gruppo.formato}. Nasce in bozza: fotografie,
            pubblicazione e quantità si gestiscono dalla scheda del prodotto.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor={`q-${gruppo.chiave}`}>Bottiglie in vendita</Label>
              <Input
                id={`q-${gruppo.chiave}`}
                type="number"
                inputMode="numeric"
                min={1}
                max={massimo}
                value={quantita}
                onChange={(e) => setQuantita(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">Libere: {libere.length}</p>
            </div>
            <div className="space-y-1">
              <Label htmlFor={`p-${gruppo.chiave}`}>Vuoi ricevere, per bottiglia (€)</Label>
              <Input
                id={`p-${gruppo.chiave}`}
                inputMode="decimal"
                placeholder="45,00"
                value={prezzo}
                onChange={(e) => setPrezzo(e.target.value)}
              />
            </div>
          </div>
          {cents !== null && quantitaValida ? (
            stima ? (
              <PrezzoPerAcquirente
                preventivo={stima.preventivo}
                classe={stima.classe}
                motivo={stima.preventivo ? null : stima.motivo}
                vista="venditore"
              />
            ) : stimaErrore ? (
              <p role="status" className="text-sm text-muted-foreground">
                Il prezzo per l&apos;acquirente non è disponibile in questo momento.
              </p>
            ) : null
          ) : null}
          <div className="space-y-1">
            <Label htmlFor={`c-${gruppo.chiave}`}>Condizione</Label>
            <select
              id={`c-${gruppo.chiave}`}
              className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
              value={condizione}
              onChange={(e) => setCondizione(e.target.value as (typeof CONDIZIONI)[number])}
            >
              {CONDIZIONI.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`s-${gruppo.chiave}`}>Conservazione</Label>
            <Input
              id={`s-${gruppo.chiave}`}
              maxLength={500}
              placeholder="Magazzino a temperatura controllata"
              value={conservazione}
              onChange={(e) => setConservazione(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`d-${gruppo.chiave}`}>Descrizione commerciale</Label>
            <Textarea
              id={`d-${gruppo.chiave}`}
              maxLength={2000}
              rows={4}
              value={descrizione}
              onChange={(e) => setDescrizione(e.target.value)}
            />
          </div>
          {errore ? (
            <p role="alert" className="text-sm text-destructive">
              {errore}
            </p>
          ) : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setAperto(false)} disabled={inCorso}>
            Annulla
          </Button>
          <Button
            className="bg-bordeaux hover:bg-bordeaux/90"
            onClick={() => void crea()}
            disabled={inCorso || !quantitaValida || cents === null}
          >
            {inCorso ? "Creazione…" : "Crea la bozza"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
