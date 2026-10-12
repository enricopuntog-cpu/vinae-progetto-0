"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getSupabaseClient } from "@/lib/supabase/client";
import {
  MAX_BOTTIGLIE_PER_ANNUNCIO,
  MAX_BOTTIGLIE_PER_ORDINE,
  etichettaBottiglie,
  quantitaDaTesto,
} from "@/lib/cantina/gruppo";
import { createListingService, type AnnuncioProprietario } from "@/services/listing-service";

/**
 * Quantità di un annuncio (VP-C). Ogni numero qui è un conteggio di bottiglie
 * reali fatto dal database; l'interfaccia non ne calcola nessuno e non ne è
 * l'autorità: le porte riverificano disponibilità, prenotazioni e limiti.
 */

type Capacita = { ordiniMultiUnita: boolean; maxBottigliePerOrdine: number };

/**
 * Lo specchio degli interruttori (`inventario_capacita`). Finché non risponde,
 * o se risponde male, vale «una bottiglia per ordine»: è ciò che il database
 * accetta comunque, quindi l'errore non apre niente.
 */
export function useCapacitaInventario(): Capacita {
  const [capacita, setCapacita] = useState<Capacita>({
    ordiniMultiUnita: false,
    maxBottigliePerOrdine: 1,
  });
  useEffect(() => {
    const client = getSupabaseClient();
    if (!client) return;
    let attivo = true;
    void client.rpc("inventario_capacita").then(({ data, error }) => {
      if (!attivo || error || !data || typeof data !== "object") return;
      const d = data as Record<string, unknown>;
      if (d.ordiniMultiUnita === true && typeof d.maxBottigliePerOrdine === "number") {
        setCapacita({
          ordiniMultiUnita: true,
          maxBottigliePerOrdine: Math.min(d.maxBottigliePerOrdine, MAX_BOTTIGLIE_PER_ORDINE),
        });
      }
    });
    return () => {
      attivo = false;
    };
  }, []);
  return capacita;
}

/**
 * Per chi compra: quante bottiglie prendere da questo annuncio. Finché gli
 * ordini di più bottiglie non sono attivi (logistica per colli multipli, VP-E)
 * non c'è un selettore che il database rifiuterebbe: c'è la frase vera.
 */
export function SceltaQuantitaAcquisto({
  disponibili,
  valore,
  onChange,
}: {
  disponibili: number;
  valore: number;
  onChange: (quantita: number) => void;
}) {
  const { ordiniMultiUnita, maxBottigliePerOrdine } = useCapacitaInventario();
  if (disponibili <= 1) return null;
  const massimo = Math.max(1, Math.min(disponibili, maxBottigliePerOrdine));

  if (!ordiniMultiUnita || massimo <= 1) {
    return (
      <p className="mt-3 text-xs text-muted-foreground" data-testid="quantita-una-per-ordine">
        Per ora si acquista una bottiglia per ordine: puoi ripetere l&apos;acquisto finché ce ne
        sono.
      </p>
    );
  }
  return (
    <label className="mt-3 flex items-center gap-2 text-sm">
      <span>Bottiglie</span>
      <Input
        type="number"
        inputMode="numeric"
        min={1}
        max={massimo}
        step={1}
        value={valore}
        onChange={(e) => onChange(quantitaDaTesto(e.target.value, massimo) ?? 1)}
        className="w-24"
        aria-label={`Quante bottiglie acquistare, da 1 a ${massimo}`}
      />
      <span className="text-xs text-muted-foreground">fino a {massimo}</span>
    </label>
  );
}

/**
 * Per chi vende: offerte, disponibili, prenotate, vendute, e la quantità in
 * vendita modificabile nel rispetto delle prenotazioni.
 */
export function GestioneQuantitaAnnuncio({ annuncio }: { annuncio: AnnuncioProprietario }) {
  const router = useRouter();
  const q = annuncio.quantita;
  const [testo, setTesto] = useState(q ? String(q.offerte) : "");
  const [inCorso, setInCorso] = useState(false);
  const modificabile = ["bozza", "modifiche_richieste", "attivo", "riservato"].includes(
    annuncio.stato,
  );

  if (!q) return null;

  const salva = async () => {
    const quantita = quantitaDaTesto(testo, MAX_BOTTIGLIE_PER_ANNUNCIO);
    if (quantita === null) {
      toast.error(`La quantità in vendita va da 1 a ${MAX_BOTTIGLIE_PER_ANNUNCIO}.`);
      return;
    }
    if (quantita < q.riservate) {
      toast.error(`Ci sono ${q.riservate} bottiglie prenotate: non puoi scendere sotto.`);
      return;
    }
    const listingId = annuncio.wine.listingId;
    if (!listingId) return;
    setInCorso(true);
    try {
      const esito = await createListingService(getSupabaseClient()).impostaQuantita(
        listingId,
        quantita,
      );
      if (!esito.ok) {
        toast.error(esito.error);
        return;
      }
      toast.success(`In vendita: ${etichettaBottiglie(esito.data.offerte)}`);
      setTesto(String(esito.data.offerte));
      router.refresh();
    } finally {
      setInCorso(false);
    }
  };

  return (
    <section
      className="mt-3 rounded-2xl border border-border bg-card p-4"
      data-testid="gestione-quantita"
    >
      <p className="text-sm font-medium">Bottiglie di questo annuncio</p>
      <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-muted-foreground">In vendita</dt>
          <dd className="font-medium">{q.offerte}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Disponibili</dt>
          <dd className="font-medium">{q.disponibili}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Prenotate</dt>
          <dd className="font-medium">{q.riservate}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Vendute</dt>
          <dd className="font-medium">{q.vendute}</dd>
        </div>
      </dl>
      {modificabile ? (
        <div className="mt-3 flex flex-wrap items-end gap-2">
          <label className="text-sm">
            <span className="block text-xs text-muted-foreground">Nuova quantità in vendita</span>
            <Input
              type="number"
              inputMode="numeric"
              min={Math.max(1, q.riservate)}
              max={MAX_BOTTIGLIE_PER_ANNUNCIO}
              step={1}
              value={testo}
              onChange={(e) => setTesto(e.target.value)}
              className="w-28"
            />
          </label>
          <Button
            variant="outline"
            disabled={inCorso || testo === String(q.offerte)}
            onClick={() => void salva()}
          >
            Aggiorna
          </Button>
          <p className="w-full text-[11px] text-muted-foreground">
            Aumentando, Vinea aggiunge bottiglie identiche libere della tua Cantina; riducendo, le
            ritira dall&apos;annuncio e tornano libere. Le prenotate non si toccano.
          </p>
        </div>
      ) : null}
    </section>
  );
}
