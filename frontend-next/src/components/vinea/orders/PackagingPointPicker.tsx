"use client";

import { useCallback, useEffect, useState } from "react";
import { MapPin } from "lucide-react";
import { Button } from "@/components/ui/button";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createPackagingService } from "@/services/phase7c/packaging-service";
import type { OrderRecord, PackagingPoint } from "@/services/types";

/**
 * Scelta del punto fisico di consegna alla rete logistica.
 *
 * Compare **dopo** il pagamento, ed è il pezzo che rende sostenibile la
 * collocazione scelta per la Fase 7c: il *metodo* ha un prezzo e lo dichiara il
 * venditore sull'annuncio, quindi il compratore lo conosce al checkout; il
 * *punto* non ha prezzo, quindi può essere deciso qui senza che nessun importo
 * si muova. La RPC non scrive `imballaggio_cents`, per costruzione.
 *
 * I punti arrivano dal `FakePackagingProvider`: dati inventati, coordinate
 * finte, nessuna chiamata esterna. A parità di CAP la lista non cambia.
 */
export function PackagingPointPicker({
  ordine,
  onScelto,
}: {
  ordine: OrderRecord;
  onScelto: () => void;
}) {
  const [punti, setPunti] = useState<PackagingPoint[]>([]);
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);

  const servizio = createPackagingService(getSupabaseClient());
  const codice = ordine.imballaggio_codice;

  useEffect(() => {
    if (!codice) return;
    let vivo = true;
    void servizio.punti({ codice, cap: null }).then((esito) => {
      if (!vivo) return;
      if (esito.ok) setPunti(esito.data);
      else setErrore(esito.error);
    });
    return () => {
      vivo = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [codice]);

  const scegli = useCallback(
    async (punto: PackagingPoint) => {
      setInCorso(true);
      const esito = await servizio.scegliPunto({
        orderId: ordine.id,
        puntoId: punto.id,
        puntoNome: punto.nome,
      });
      setInCorso(false);
      if (!esito.ok) setErrore(esito.error);
      else onScelto();
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ordine.id, onScelto],
  );

  if (!codice || punti.length === 0) return null;

  return (
    <div>
      <p className="text-xs uppercase text-muted-foreground">Punto di consegna</p>
      {errore && <p className="mt-1 text-xs text-red-700">{errore}</p>}
      <div className="mt-2 grid gap-2 sm:grid-cols-2">
        {punti.map((p) => {
          const scelto = ordine.imballaggio_punto_id === p.id;
          return (
            <button
              key={p.id}
              type="button"
              disabled={inCorso}
              onClick={() => void scegli(p)}
              className={`flex items-start gap-2 rounded-xl border p-2 text-left text-sm transition ${
                scelto ? "border-bordeaux bg-bordeaux/5" : "border-border hover:bg-secondary"
              }`}
            >
              <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" />
              <span className="min-w-0">
                <span className="block truncate font-medium">{p.nome}</span>
                <span className="block truncate text-xs text-muted-foreground">{p.indirizzo}</span>
                {p.distanzaMetri !== null && (
                  <span className="block text-[11px] text-muted-foreground">
                    a {p.distanzaMetri} m · dati dimostrativi
                  </span>
                )}
              </span>
            </button>
          );
        })}
      </div>
      <Button variant="ghost" size="sm" className="mt-2" disabled>
        Mappa non disponibile in questa fase
      </Button>
    </div>
  );
}
