"use client";

/**
 * Price Intelligence della pagina annuncio — Fase 1B.
 *
 * Il read-model puro calcola riferimento, confronto, range, copertura e storico.
 * Questo componente li presenta senza modificare i dati e mantiene richieste e
 * vendite come serie distinte.
 */

import { Scatter, ScatterChart, CartesianGrid, XAxis, YAxis, ZAxis } from "recharts";
import { Info, TrendingDown, TrendingUp, Minus } from "lucide-react";
import { ChartContainer, ChartTooltip, type ChartConfig } from "@/components/ui/chart";
import { formatEUR } from "@/lib/format";
import type { PuntoStorico, VistaPriceIntelligence } from "@/lib/price-intelligence/insights";

const CONFIG_STORICO: ChartConfig = {
  richiesta: { label: "Prezzo richiesto", color: "var(--bordeaux)" },
  vendita: { label: "Prezzo di vendita", color: "var(--salvia-scuro)" },
};

const euro = (cents: number) => formatEUR(cents / 100);

/** Solo lato client: il grafico non viene disegnato durante il render sul server. */
const giornoBreve = (t: number) =>
  new Date(t).toLocaleDateString("it-IT", { day: "2-digit", month: "short" });

export function PriceIntelligenceSummary({ vista }: { vista: VistaPriceIntelligence }) {
  const { riferimento } = vista;

  return (
    <section aria-label="Contesto del prezzo richiesto" className="mt-4 rounded-xl border border-border bg-secondary/30 p-4">
      {riferimento.disponibile ? (
        <>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">
            Riferimento richieste Vinea
          </p>
          <p className="mt-1 font-serif text-2xl font-semibold text-bordeaux">
            {euro(riferimento.medianaCents)}
          </p>
          {vista.confronto ? (
            <p className="mt-1 text-sm font-medium">
              {vista.confronto.posizione === "uguale"
                ? "Coincide con il riferimento richieste Vinea"
                : `${euro(vista.confronto.scartoCents)} ${vista.confronto.posizione} il riferimento richieste Vinea`}
              {vista.confronto.posizione !== "uguale" ? (
                <span className="font-normal text-muted-foreground">
                  {" "}({Math.abs(vista.confronto.scartoPercentuale).toFixed(1).replace(".", ",")}%)
                </span>
              ) : null}
            </p>
          ) : null}
          {vista.posizioneRange ? (
            <p className="mt-1 text-sm text-muted-foreground">
              Prezzo richiesto {vista.posizioneRange} il range dei comparabili, da{" "}
              {euro(riferimento.minimoCents)} a {euro(riferimento.massimoCents)}.
            </p>
          ) : null}
          <p className="mt-2 text-xs text-muted-foreground">
            Comparabili: {vista.comparabili} · Copertura dati: {vista.copertura.etichetta} · Dati
            interni Vinea
          </p>
        </>
      ) : (
        <>
          <p className="flex items-center gap-2 text-sm font-medium">
            <Info className="h-4 w-4 text-salvia" aria-hidden />
            Storico in formazione
          </p>
          <p className="mt-1 text-sm text-muted-foreground">
            Comparabili: {vista.comparabili}.{" "}
            {vista.comparabiliMancanti === 1
              ? "Manca 1 comparabile per raggiungere la soglia richiesta."
              : `Mancano ${vista.comparabiliMancanti} comparabili per raggiungere la soglia richiesta.`}
          </p>
          <p className="mt-2 text-xs text-muted-foreground">
            Copertura dati: {vista.copertura.etichetta} · Dati interni Vinea
          </p>
        </>
      )}
    </section>
  );
}

export function PriceIntelligencePanel({ vista }: { vista: VistaPriceIntelligence }) {
  const haPunti = vista.richieste.length + vista.vendite.length > 0;

  return (
    <section
      aria-labelledby="price-intelligence-titolo"
      className="rounded-2xl border border-border bg-card p-6"
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="price-intelligence-titolo" className="font-serif text-2xl">
          Price Intelligence
        </h2>
        <p className="text-xs uppercase tracking-wide text-muted-foreground">
          Formato {vista.formato}
        </p>
      </div>

      {/* -- Variazione e copertura ------------------------------------------ */}
      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <Riquadro etichetta="Ultima variazione rilevata">
          {vista.variazione ? (
            <>
              <VariazioneValore pct={vista.variazione.variazionePct} />
              <p className="mt-1 text-xs text-muted-foreground">
                Da {euro(vista.variazione.daCents)} a {euro(vista.variazione.aCents)} fra le ultime
                due richieste osservate.
              </p>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">
              Non disponibile: serve più di una richiesta osservata.
            </p>
          )}
        </Riquadro>

        <Riquadro etichetta="Copertura dati">
          <p className="font-serif text-xl font-semibold">{vista.copertura.etichetta}</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Basata sugli annunci attivi comparabili ({vista.comparabili}). Indica la quantità di
            dati disponibili per questo vino e formato.
          </p>
        </Riquadro>
      </div>

      {/* -- Storico ---------------------------------------------------------- */}
      <div className="mt-5">
        <p className="text-xs uppercase tracking-wide text-muted-foreground">Storico osservato</p>

        {vista.storicoNonDisponibile ? (
          // Stato discreto: la lettura dello storico è fallita e basta. Il resto
          // della pagina — e del pannello — non ne dipende.
          <p className="mt-3 rounded-xl border border-dashed border-border bg-secondary/40 p-4 text-sm text-muted-foreground">
            Storico prezzi non disponibile.
          </p>
        ) : !haPunti ? (
          <p className="mt-3 rounded-xl border border-dashed border-border bg-secondary/40 p-4 text-sm text-muted-foreground">
            Nessuna osservazione registrata per questo vino in questo formato.
          </p>
        ) : (
          <>
            <ChartContainer config={CONFIG_STORICO} className="mt-3 aspect-[16/9] w-full">
              {/*
                Nuvola di punti e non una spezzata: le osservazioni sono eventi
                distinti e non il campionamento di una curva continua. Una linea
                fra due richieste disegnerebbe tutti i prezzi intermedi, che
                nessuno ha mai chiesto — e con una sola osservazione dovrebbe
                inventare una direzione. Così un punto solo si vede, e non
                afferma nulla oltre a sé stesso.
              */}
              <ScatterChart margin={{ left: 4, right: 12, top: 12, bottom: 4 }}>
                <CartesianGrid vertical={false} />
                <XAxis
                  type="number"
                  dataKey="t"
                  domain={vista.dominio ?? ["dataMin", "dataMax"]}
                  tickFormatter={giornoBreve}
                  tickLine={false}
                  axisLine={false}
                  tickMargin={8}
                  fontSize={11}
                />
                <YAxis
                  type="number"
                  dataKey="euro"
                  tickFormatter={(v: number) => formatEUR(v)}
                  tickLine={false}
                  axisLine={false}
                  width={72}
                  fontSize={11}
                />
                {/* Raggio fisso: la dimensione del punto non codifica nulla. */}
                <ZAxis range={[64, 64]} />
                <ChartTooltip content={<TooltipStorico />} />
                <Scatter
                  name="richiesta"
                  data={vista.richieste}
                  fill="var(--color-richiesta)"
                  shape="circle"
                />
                {/*
                  Vendite in rombo oltre che in un altro colore: il colore da
                  solo non basta a distinguere due serie per chi non lo
                  percepisce, e qui la distinzione fra «chiesto» e «pagato» è
                  l'informazione, non una sfumatura.
                */}
                <Scatter
                  name="vendita"
                  data={vista.vendite}
                  fill="var(--color-vendita)"
                  shape="diamond"
                />
              </ScatterChart>
            </ChartContainer>

            <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
              <Legenda colore="var(--bordeaux)" forma="tondo">
                Prezzi richiesti ({vista.osservazioniRichiesta})
              </Legenda>
              <Legenda colore="var(--salvia-scuro)" forma="rombo">
                Prezzi di vendita ({vista.osservazioniVendita})
              </Legenda>
            </div>

            {vista.storicoInFormazione && (
              <p className="mt-2 text-xs text-muted-foreground">
                Storico in formazione: una sola osservazione registrata.
              </p>
            )}

            {vista.osservazioniVendita > 0 && (
              <p className="mt-2 text-xs text-muted-foreground">
                Le vendite sono mostrate ma non concorrono al riferimento sulle richieste.
              </p>
            )}
          </>
        )}
      </div>

      {/* -- Fonte ------------------------------------------------------------ */}
      <p className="mt-5 border-t border-border pt-3 text-xs text-muted-foreground">
        Fonte: <span className="font-medium">Dati interni Vinea</span> · {vista.comparabili}{" "}
        {vista.comparabili === 1 ? "annuncio comparabile attivo" : "annunci comparabili attivi"} ·{" "}
        {vista.osservazioniRichiesta}{" "}
        {vista.osservazioniRichiesta === 1
          ? "osservazione di richiesta"
          : "osservazioni di richiesta"}{" "}
        · {vista.osservazioniVendita}{" "}
        {vista.osservazioniVendita === 1 ? "osservazione di vendita" : "osservazioni di vendita"} ·
        formato {vista.formato}
      </p>
    </section>
  );
}

function Riquadro({ etichetta, children }: { etichetta: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-border bg-secondary/30 p-4">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{etichetta}</p>
      <div className="mt-1">{children}</div>
    </div>
  );
}

function VariazioneValore({ pct }: { pct: number }) {
  const Icona = pct > 0 ? TrendingUp : pct < 0 ? TrendingDown : Minus;
  // Neutro di proposito: una richiesta più alta non è una buona notizia per chi
  // compra e una più bassa non lo è per chi vende. Il verde e il rosso
  // direbbero a entrambi la stessa cosa, e a uno dei due sarebbe falsa.
  return (
    <p className="flex items-center gap-1.5 font-serif text-xl font-semibold">
      <Icona className="h-4 w-4 text-muted-foreground" aria-hidden />
      {pct > 0 ? "+" : ""}
      {/* Virgola decimale scritta a mano, come in `@/lib/format`: `Intl` qui
          farebbe dipendere il testo dai dati locale del runtime, e questo
          numero viene reso una volta sul server e una nel browser. */}
      {pct.toFixed(1).replace(".", ",")}%
    </p>
  );
}

function Legenda({
  colore,
  forma,
  children,
}: {
  colore: string;
  forma: "tondo" | "rombo";
  children: React.ReactNode;
}) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span
        aria-hidden
        className={`h-2.5 w-2.5 shrink-0 ${forma === "tondo" ? "rounded-full" : "rotate-45"}`}
        style={{ backgroundColor: colore }}
      />
      {children}
    </span>
  );
}

/**
 * Il tooltip è scritto qui e non riusa `ChartTooltipContent`: quel componente
 * legge `payload[0].dataKey` per trovare l'etichetta, e su una nuvola di punti
 * ogni voce porta due chiavi (l'istante e il prezzo). Riadattarlo costerebbe
 * più di queste dieci righe e lascerebbe un componente condiviso più fragile.
 */
function TooltipStorico({
  active,
  payload,
}: {
  active?: boolean;
  payload?: { payload?: PuntoStorico }[];
}) {
  const punto = payload?.[0]?.payload;
  if (!active || !punto) return null;

  // Il tipo si legge dal PUNTO e non da `payload[0].name`: con un `dataKey`
  // esplicito sull'asse X, quel nome e `t`, non il nome della serie. Leggerlo
  // di la avrebbe etichettato «Prezzo richiesto» anche le vendite.
  const nome = punto.tipo === "vendita" ? "Prezzo di vendita" : "Prezzo richiesto";

  return (
    <div className="rounded-lg border border-border/50 bg-background px-2.5 py-1.5 text-xs shadow-xl">
      <p className="font-medium">{nome}</p>
      <p className="mt-0.5">{euro(punto.prezzoCents)}</p>
      <p className="text-muted-foreground">{giornoBreve(punto.t)}</p>
    </div>
  );
}
