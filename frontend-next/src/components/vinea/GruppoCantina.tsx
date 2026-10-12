"use client";

import type { CellarBottle } from "@/data/cellar";
import { AperturaBottiglia } from "@/components/vinea/AperturaBottiglia";
import { etichettaBottiglie, euroDaCentesimi, type RiepilogoGruppo } from "@/lib/cantina/gruppo";
import { formatEUR } from "@/lib/vinea-store";

/**
 * VP-C. Una scheda della Cantina è un gruppo (vino + formato); le bottiglie
 * restano righe. Il riepilogo conta righe reali, il dettaglio le elenca una
 * per una con le loro azioni: aprire una delle dodici agisce su quella.
 */

export function RiepilogoGruppoCantina({
  riepilogo,
  formato,
  libere,
}: {
  riepilogo: RiepilogoGruppo;
  formato?: string;
  libere: number;
}) {
  if (riepilogo.totale === 0) return null;
  const parti = [etichettaBottiglie(riepilogo.chiuse)];
  if (formato) parti.push(formato);
  if (riepilogo.inVendita > 0) parti.push(`${riepilogo.inVendita} in vendita`);
  if (riepilogo.aperte > 0) parti.push(`${riepilogo.aperte} ${riepilogo.aperte === 1 ? "aperta" : "aperte"}`);
  if (riepilogo.consumate > 0)
    parti.push(`${riepilogo.consumate} ${riepilogo.consumate === 1 ? "consumata" : "consumate"}`);
  if (riepilogo.vendute > 0) parti.push(`${riepilogo.vendute} ${riepilogo.vendute === 1 ? "venduta" : "vendute"}`);
  return (
    <p className="text-xs text-muted-foreground" data-testid="riepilogo-gruppo">
      {parti.join(" · ")}
      {riepilogo.inVendita > 0 && libere > 0 ? ` · ${libere} ${libere === 1 ? "libera" : "libere"}` : ""}
    </p>
  );
}

const ETICHETTA_STATO_BOTTIGLIA: Record<string, string> = {
  chiusa: "Chiusa",
  aperta: "Aperta",
  consumata: "Consumata",
};

const ETICHETTA_VENDITA: Record<string, string> = {
  in_vendita: "In vendita",
  riservata: "Prenotata",
  venduta: "Venduta",
};

/** «m-r0c2» → «Riga 1 · Colonna 3»: la posizione si legge da umani. */
function etichettaPosizione(slotId?: string): string | null {
  if (!slotId) return null;
  const m = /-r(\d+)c(\d+)$/.exec(slotId);
  return m ? `Riga ${Number(m[1]) + 1} · Colonna ${Number(m[2]) + 1}` : "Collocata";
}

/**
 * Il dettaglio di un gruppo: una riga per bottiglia, con il suo stato, la sua
 * posizione, il suo eventuale annuncio e il suo costo. Le azioni restano per
 * bottiglia: aprire una delle dodici agisce su quella, non sul gruppo.
 */
export function DettaglioGruppo({ bottiglie, nomeVino }: { bottiglie: CellarBottle[]; nomeVino: string }) {
  return (
    <details className="rounded-xl border border-border bg-card/60 px-3 py-2 text-xs">
      <summary className="cursor-pointer select-none font-medium">
        Dettaglio bottiglie ({bottiglie.length})
      </summary>
      <ul className="mt-2 divide-y divide-border">
        {bottiglie.map((b, i) => {
          const posizione = etichettaPosizione(b.storageLocationId);
          const vendita = b.statoAnnuncio ?? (b.saleStatus === "in_vendita" || b.saleStatus === "venduta" ? b.saleStatus : null);
          return (
            <li key={b.bottleId} className="flex flex-wrap items-center gap-2 py-2">
              <span className="font-medium">Bottiglia {i + 1}</span>
              <span className="rounded-full bg-muted px-2 py-0.5">
                {ETICHETTA_STATO_BOTTIGLIA[b.stato ?? "chiusa"] ?? b.stato}
              </span>
              {vendita ? (
                <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-bordeaux">
                  {ETICHETTA_VENDITA[vendita] ?? vendita}
                </span>
              ) : null}
              <span className="text-muted-foreground">{posizione ?? "Senza posizione"}</span>
              {typeof b.acquisitionCostCents === "number" ? (
                <span className="text-muted-foreground">
                  Costo {formatEUR(euroDaCentesimi(b.acquisitionCostCents))}
                </span>
              ) : null}
              {b.stato === "chiusa" && !b.annuncioBloccante && b.saleStatus !== "venduta" ? (
                <span className="ml-auto">
                  <AperturaBottiglia bottiglia={b} nomeVino={nomeVino} variante="compatto" />
                </span>
              ) : null}
            </li>
          );
        })}
      </ul>
    </details>
  );
}

