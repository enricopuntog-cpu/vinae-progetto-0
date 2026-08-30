"use client";

/**
 * Il valore della cantina nel tempo (D3-B).
 *
 * La serie va solo in avanti: nasce dal primo snapshot di riferimento davvero
 * osservato e non ricostruisce nulla all'indietro. Per questo qui esistono tre
 * stati diversi e non uno solo con dentro il vuoto: senza osservazioni non c'è
 * storia, con una sola osservazione c'è un punto e non un andamento, e solo da
 * due in poi una linea afferma qualcosa.
 *
 * Il grafico non è il dato: accanto c'è sempre la stessa serie in tabella, che
 * dichiara anche quante posizioni erano coperte a ogni istante. Chi non vede il
 * disegno legge gli stessi numeri, e un valore più basso perché mancava un
 * riferimento non si confonde con un calo del portafoglio.
 */

import { CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts";
import { ChartContainer, ChartTooltip, type ChartConfig } from "@/components/ui/chart";
import { formatEUR } from "@/lib/format";
import type { PuntoValorePortafoglio } from "@/lib/cantina/portfolio";
import {
  puntiGrafico,
  righeSerieValore,
  statoSerieValore,
} from "@/lib/cantina/presentazione";

const CONFIG: ChartConfig = {
  valore: { label: "Valore di riferimento", color: "var(--bordeaux)" },
};

const giornoBreve = (t: number) =>
  new Date(t).toLocaleDateString("it-IT", { day: "2-digit", month: "short" });

export function ValoreNelTempo({
  serie,
  /**
   * La cornice propria serve quando questo blocco sta da solo. Dentro la card
   * di contabilità sarebbe un riquadro nel riquadro: lì la sezione resta —
   * intestazione, tabella, avvisi — e cade solo il bordo.
   */
  incorniciato = true,
}: {
  serie: PuntoValorePortafoglio[];
  incorniciato?: boolean;
}) {
  const stato = statoSerieValore(serie);
  const righe = righeSerieValore(serie);
  const parziale = righe.some((r) => r.parziale);

  return (
    <section
      aria-labelledby="valore-nel-tempo"
      className={incorniciato ? "rounded-2xl border border-border bg-card p-4 md:p-6" : undefined}
    >
      <h2 id="valore-nel-tempo" className="font-serif text-2xl">
        Valore nel tempo
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Dal primo riferimento osservato in poi. Prima di quella data non esiste una
        rilevazione e nulla viene ricostruito.
      </p>

      {stato === "vuota" ? (
        <p className="mt-4 rounded-xl border border-dashed border-border bg-secondary/40 p-4 text-sm text-muted-foreground">
          Nessun riferimento ancora osservato per le tue bottiglie: la storia del valore
          comincerà dalla prima rilevazione.
        </p>
      ) : (
        <>
          {stato === "osservazione_unica" ? (
            <p className="mt-4 rounded-xl border border-border bg-secondary/40 p-4 text-sm">
              Una sola rilevazione, il {righe[0]?.giorno}:{" "}
              <b className="text-bordeaux">{righe[0]?.valore}</b>. Con un punto solo non
              c&apos;è ancora un andamento da mostrare.
            </p>
          ) : (
            <ChartContainer config={CONFIG} className="mt-4 aspect-[16/9] w-full">
              <LineChart
                data={puntiGrafico(serie)}
                margin={{ left: 4, right: 12, top: 12, bottom: 4 }}
              >
                <CartesianGrid vertical={false} />
                <XAxis
                  type="number"
                  dataKey="t"
                  domain={["dataMin", "dataMax"]}
                  tickFormatter={giornoBreve}
                  tickLine={false}
                  axisLine={false}
                  tickMargin={8}
                  fontSize={11}
                />
                <YAxis
                  dataKey="valore"
                  tickFormatter={(v: number) => formatEUR(v)}
                  tickLine={false}
                  axisLine={false}
                  width={72}
                  fontSize={11}
                />
                <ChartTooltip />
                <Line
                  type="monotone"
                  dataKey="valore"
                  stroke="var(--color-valore)"
                  strokeWidth={2}
                  dot
                  isAnimationActive={false}
                />
              </LineChart>
            </ChartContainer>
          )}

          {parziale && (
            <p className="mt-3 rounded-xl border border-oro/40 bg-oro/10 p-3 text-xs text-antracite">
              In alcune rilevazioni una parte delle bottiglie non aveva un riferimento
              disponibile: quelle posizioni non valgono zero, semplicemente non entrano nel
              totale di quel giorno.
            </p>
          )}

          {/* Il grafico è un'illustrazione della tabella, non il contrario. */}
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">
                Valore di riferimento della cantina per data di rilevazione, con il numero di
                posizioni coperte e scoperte.
              </caption>
              <thead>
                <tr className="text-xs uppercase tracking-wide text-muted-foreground">
                  <th scope="col" className="py-1 pr-4 font-medium">
                    Data
                  </th>
                  <th scope="col" className="py-1 pr-4 font-medium">
                    Valore
                  </th>
                  <th scope="col" className="py-1 font-medium">
                    Copertura
                  </th>
                </tr>
              </thead>
              <tbody>
                {righe.map((r) => (
                  <tr key={r.at} className="border-t border-border">
                    <th scope="row" className="py-1 pr-4 font-normal">
                      {r.giorno}
                    </th>
                    <td className="py-1 pr-4 font-semibold text-bordeaux">{r.valore}</td>
                    <td className="py-1 text-muted-foreground">{r.copertura}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </section>
  );
}
