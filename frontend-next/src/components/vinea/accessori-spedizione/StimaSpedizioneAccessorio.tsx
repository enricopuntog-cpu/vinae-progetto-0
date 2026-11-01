"use client";

import { useEffect, useMemo, useState } from "react";
import { Truck } from "lucide-react";
import {
  DESTINAZIONI_LOGISTICA,
  MAX_QUANTITA_LOGISTICA,
  messaggioMotivoLogistica,
  TESTI_LOGISTICA_ACCESSORI,
  type DestinazioneLogistica,
  type StimaLogistica,
} from "@/lib/accessori-spedizione/stima";
import { euro } from "@/lib/prezzi/classe";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriLogisticaService } from "@/services/accessori-spedizione-service";

type Stato = { tipo: "caricamento" } | { tipo: "errore"; messaggio: string } | { tipo: "pronto"; stima: StimaLogistica };

/** Vista pura: tutto ciò che l'utente legge, senza I/O. */
export function RiepilogoStimaLogistica({ stato }: { stato: Stato }) {
  if (stato.tipo === "caricamento") {
    return <p data-testid="stima-logistica-caricamento" className="text-sm text-muted-foreground">Calcolo della spedizione…</p>;
  }
  if (stato.tipo === "errore") {
    return <p data-testid="stima-logistica-errore" className="text-sm text-muted-foreground">{stato.messaggio}</p>;
  }
  const s = stato.stima;
  if (!s.ok) {
    // Fail-closed: nessun prezzo, nessun totale, solo il perché.
    return (
      <ul data-testid="stima-logistica-non-disponibile" className="list-disc pl-5 text-sm text-muted-foreground">
        {[...new Set(s.motivi.map(messaggioMotivoLogistica))].map((m) => (
          <li key={m}>{m}</li>
        ))}
      </ul>
    );
  }
  return (
    <dl data-testid="stima-logistica" className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
      <dt>
        {s.prezzo.quantita} {s.prezzo.quantita === 1 ? "pezzo" : "pezzi"} × {euro(s.prezzo.unitarioCents)}
      </dt>
      <dd>{euro(s.prezzo.subtotaleCents)}</dd>
      <dt>Commissione Vinea</dt>
      <dd>{euro(s.commissioneCents)}</dd>
      <dt>
        Spedizione ({s.logistica.colli} {s.logistica.colli === 1 ? "collo" : "colli"})
      </dt>
      <dd>{euro(s.logistica.trasportoCents)}</dd>
      {s.logistica.assicurazioneRichiesta ? (
        <>
          <dt>Assicurazione</dt>
          <dd>{euro(s.logistica.assicurazioneCents)}</dd>
        </>
      ) : null}
      <dt>Costo di pagamento sulla spedizione</dt>
      <dd>{euro(s.coperturaPagamentoCents)}</dd>
      <dt className="font-medium">Totale stimato</dt>
      <dd className="font-medium" data-testid="stima-logistica-totale">{euro(s.totaleAcquirenteCents)}</dd>
      {s.requisiti.fragile ? (
        <dd className="col-span-2 text-muted-foreground">{TESTI_LOGISTICA_ACCESSORI.fragile}</dd>
      ) : null}
      {!s.ordinabile ? (
        <dd className="col-span-2 text-muted-foreground" data-testid="stima-logistica-non-ordinabile">
          {messaggioMotivoLogistica(s.motivoNonOrdinabile ?? "domicilio_non_ordinabile")}
        </dd>
      ) : null}
    </dl>
  );
}

/**
 * Stima della spedizione di un annuncio Accessori (VPM-015B4). Solo lettura:
 * nessun gesto d'acquisto, nessun ordine, nessun corriere. Il browser invia
 * annuncio, quantità e modalità; importi e tariffe sono del database.
 */
export function StimaSpedizioneAccessorio({ annuncioId, disponibili }: { annuncioId: string; disponibili: number }) {
  const servizio = useMemo(() => creaAccessoriLogisticaService(getSupabaseClient()), []);
  const massimo = Math.min(Math.max(1, disponibili), MAX_QUANTITA_LOGISTICA);
  const [quantita, setQuantita] = useState(1);
  const [destinazione, setDestinazione] = useState<DestinazioneLogistica>("punto_ritiro");
  const [stato, setStato] = useState<Stato>({ tipo: "caricamento" });

  useEffect(() => {
    let attivo = true;
    setStato({ tipo: "caricamento" });
    servizio.stima({ annuncioId, quantita, destinazione }).then((r) => {
      if (!attivo) return;
      setStato(r.ok ? { tipo: "pronto", stima: r.data } : { tipo: "errore", messaggio: r.error });
    });
    return () => {
      attivo = false;
    };
  }, [servizio, annuncioId, quantita, destinazione]);

  return (
    <section aria-labelledby="titolo-logistica" data-testid="sezione-logistica" className="mx-auto max-w-3xl px-4 pb-10">
      <h2 id="titolo-logistica" className="flex items-center gap-2 text-lg font-semibold">
        <Truck className="size-5" aria-hidden /> {TESTI_LOGISTICA_ACCESSORI.titolo}
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">{TESTI_LOGISTICA_ACCESSORI.introduzione}</p>
      <div className="mt-3 flex flex-wrap items-center gap-3 text-sm">
        <label className="flex items-center gap-2">
          Quantità
          <input
            type="number"
            min={1}
            max={massimo}
            value={quantita}
            onChange={(e) => {
              const n = Math.trunc(Number(e.target.value));
              if (Number.isFinite(n)) setQuantita(Math.min(Math.max(1, n), massimo));
            }}
            className="w-20 rounded-md border bg-background px-2 py-1"
          />
        </label>
        <label className="flex items-center gap-2">
          Consegna
          <select
            value={destinazione}
            onChange={(e) => setDestinazione(e.target.value as DestinazioneLogistica)}
            className="rounded-md border bg-background px-2 py-1"
          >
            {DESTINAZIONI_LOGISTICA.map((d) => (
              <option key={d} value={d}>
                {d === "punto_ritiro" ? TESTI_LOGISTICA_ACCESSORI.puntoRitiro : TESTI_LOGISTICA_ACCESSORI.domicilio}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="mt-3" aria-live="polite">
        <RiepilogoStimaLogistica stato={stato} />
      </div>
      <p className="mt-3 text-xs text-muted-foreground" data-testid="avviso-acquisti-logistica">
        {TESTI_LOGISTICA_ACCESSORI.avvisoAcquisti}
      </p>
    </section>
  );
}
