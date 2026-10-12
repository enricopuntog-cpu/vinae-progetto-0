"use client";

import { useEffect, useMemo, useState } from "react";
import { Package, Truck } from "lucide-react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { euro } from "@/lib/prezzi/classe";
import {
  elencoMancanze,
  etichettaImballaggio,
  misureCm,
  pesoKg,
  riassuntoColli,
} from "@/lib/logistica/etichette";
import {
  creaLogisticaService,
  type OpzioneLogistica,
  type PreventivoLogistica,
} from "@/services/logistica-service";

/**
 * VP-E: il preventivo logistico come lo dà il database. Punto di ritiro
 * prima (consigliato e ordinabile), domicilio come alternativa dichiarata;
 * quando manca una configurazione si dice quale, senza stimare nulla.
 */
export function PreventivoLogisticaCard({ preventivo }: { preventivo: PreventivoLogistica }) {
  const pudo = preventivo.opzioni.find((o) => o.destinazione === "pudo") ?? null;
  const home = preventivo.opzioni.find((o) => o.destinazione === "home") ?? null;

  return (
    <section
      className="mt-3 space-y-3 rounded-2xl border border-border bg-card p-4 text-sm"
      data-testid="preventivo-logistica"
    >
      <div className="flex items-center gap-2">
        <Truck className="h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
        <p className="font-semibold">Spedizione di {preventivo.quantita} bottiglie</p>
      </div>
      {pudo ? <Opzione opzione={pudo} titolo="Al punto di ritiro" consigliata /> : null}
      {home && home.disponibile ? (
        <div className="rounded-xl border border-dashed border-border p-3 text-xs text-muted-foreground">
          A domicilio: {euro(home.totaleCents ?? 0)} · non ancora ordinabile (l&apos;ordine non gestisce
          ancora un indirizzo di consegna).
        </div>
      ) : null}
      {preventivo.addebitata && preventivo.totaleOrdineCents !== null ? (
        <div className="flex items-baseline justify-between gap-3 border-t border-border pt-2 font-semibold text-bordeaux">
          <span>Totale con spedizione</span>
          <span className="shrink-0">{euro(preventivo.totaleOrdineCents)}</span>
        </div>
      ) : null}
    </section>
  );
}

function Opzione({
  opzione,
  titolo,
  consigliata = false,
}: {
  opzione: OpzioneLogistica;
  titolo: string;
  consigliata?: boolean;
}) {
  if (!opzione.disponibile) {
    const righe = elencoMancanze(opzione.mancanti);
    return (
      <div role="status" className="rounded-xl bg-muted/40 p-3" data-testid="logistica-non-disponibile">
        <p className="font-medium">{titolo}: non ancora disponibile per questa quantità.</p>
        {righe.length > 0 ? (
          <ul className="mt-1 list-disc space-y-0.5 pl-5 text-xs text-muted-foreground">
            {righe.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        ) : null}
      </div>
    );
  }
  return (
    <div className="space-y-2" data-testid={`logistica-${opzione.destinazione}`}>
      <p className="text-xs text-muted-foreground">
        {titolo}
        {consigliata ? " · consigliato" : ""} · {riassuntoColli(opzione.colli)}
      </p>
      <ul className="space-y-1">
        {opzione.colli.map((c) => (
          <li key={c.numero} className="flex items-start gap-2 text-xs">
            <Package className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <span className="min-w-0">
              <span className="block">
                {etichettaImballaggio(c.packagingFormat)} · {c.bottiglie}{" "}
                {c.bottiglie === 1 ? "bottiglia" : "bottiglie"}
              </span>
              <span className="block text-muted-foreground">
                {misureCm(c)} · fino a {pesoKg(c.pesoG)}
              </span>
            </span>
          </li>
        ))}
      </ul>
      <Riga label="Imballaggio" value={euro(opzione.imballaggioCents ?? 0)} />
      <Riga label="Trasporto" value={euro(opzione.trasportoCents ?? 0)} />
      {(opzione.altriCostiCents ?? 0) > 0 ? (
        <Riga label="Altri costi logistici" value={euro(opzione.altriCostiCents ?? 0)} />
      ) : null}
      {(opzione.bufferCents ?? 0) > 0 ? (
        <Riga label="Gestione spedizione" value={euro(opzione.bufferCents ?? 0)} />
      ) : null}
      <Riga label="Spedizione e imballaggio" value={euro(opzione.totaleCents ?? 0)} forte />
      {(opzione.feePagamentoCents ?? 0) > 0 ? (
        <Riga
          label="Costi di pagamento sulla spedizione"
          value={euro(opzione.feePagamentoCents ?? 0)}
          testId={`logistica-fee-${opzione.destinazione}`}
        />
      ) : null}
      {opzione.venditore ? (
        <p className="text-xs text-muted-foreground" data-testid="logistica-venditore">
          Costo reale per questa spedizione {euro(opzione.venditore.costoRealeCents)}
          {opzione.venditore.obiettivoApplicabile && opzione.venditore.obiettivoTransazioneCents !== null
            ? ` · obiettivo sotto ${euro(opzione.venditore.obiettivoTransazioneCents)}: ${
                opzione.venditore.entroObiettivoTransazione ? "raggiunto" : "non raggiunto"
              }`
            : ""}
          {opzione.venditore.deduzioneRitiroCents > 0
            ? ` · ritiro a domicilio a tuo carico: ${euro(opzione.venditore.deduzioneRitiroCents)}`
            : ""}
        </p>
      ) : null}
    </div>
  );
}

const Riga = ({
  label,
  value,
  forte = false,
  testId,
}: {
  label: string;
  value: string;
  forte?: boolean;
  testId?: string;
}) => (
  <div
    className={`flex items-baseline justify-between gap-3 text-xs ${forte ? "font-semibold" : ""}`}
    data-testid={testId}
  >
    <span>{label}</span>
    <span className="shrink-0">{value}</span>
  </div>
);

/**
 * Sulla scheda: il preventivo per la quantità scelta, letto dal database a
 * ogni cambio. Una lettura fallita non mostra importi.
 */
export function PreventivoLogisticaAnnuncio({ listingId, quantita }: { listingId: string; quantita: number }) {
  const service = useMemo(() => creaLogisticaService(getSupabaseClient()), []);
  const [stato, setStato] = useState<
    { q: number; esito: "ok"; dati: PreventivoLogistica } | { q: number; esito: "errore" } | null
  >(null);

  useEffect(() => {
    let attivo = true;
    void service.preventivo(listingId, quantita).then((r) => {
      if (!attivo) return;
      setStato(r.ok ? { q: quantita, esito: "ok", dati: r.data } : { q: quantita, esito: "errore" });
    });
    return () => {
      attivo = false;
    };
  }, [service, listingId, quantita]);

  if (!stato || stato.q !== quantita) {
    return (
      <p className="mt-3 text-xs text-muted-foreground" role="status">
        Calcolo della spedizione…
      </p>
    );
  }
  if (stato.esito === "errore") {
    return (
      <p className="mt-3 text-xs text-muted-foreground" role="status" data-testid="logistica-errore">
        Il preventivo di spedizione non è disponibile in questo momento.
      </p>
    );
  }
  return <PreventivoLogisticaCard preventivo={stato.dati} />;
}
