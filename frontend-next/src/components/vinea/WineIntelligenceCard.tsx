"use client";

import { useMemo } from "react";
import Link from "next/link";
import { AlertTriangle, ChevronDown, Info, Sparkles } from "lucide-react";
import { mergeMeta } from "@/components/vinea/DrinkWindow";
import { useWineMeta } from "@/lib/wine-meta-context";
import { useVinea } from "@/lib/vinea-store";
import {
  costruisciIntelligenzaVino,
  type VinoPerIntelligenza,
} from "@/lib/wine-intelligence/costruisci";
import type { Attributo, IntelligenzaVino, StatoConoscenza } from "@/lib/wine-intelligence/types";

const ETICHETTA_STATO: Record<StatoConoscenza, string> = {
  registrato: "Registrato",
  dichiarato: "Dichiarato",
  stimato: "Stimato · non verificato",
  mancante: "Non noto",
};

const COLORE_STATO: Record<StatoConoscenza, string> = {
  registrato: "bg-salvia/15 text-salvia",
  dichiarato: "bg-oro/20 text-antracite",
  stimato: "bg-bordeaux/10 text-bordeaux",
  mancante: "bg-secondary text-muted-foreground",
};

function StatoBadge({ attributo }: { attributo: Attributo<unknown> }) {
  return (
    <span
      title={attributo.nota}
      className={`inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${COLORE_STATO[attributo.stato]}`}
      data-testid="wi-stato"
      data-stato={attributo.stato}
    >
      {ETICHETTA_STATO[attributo.stato]}
    </span>
  );
}

function Riga({
  etichetta,
  valore,
  attributo,
  rimando,
  senzaNota = false,
}: {
  /** L'identità condivide un'unica nota di provenienza, mostrata sotto il blocco. */
  senzaNota?: boolean;
  etichetta: string;
  valore: string | null;
  attributo: Attributo<unknown>;
  rimando?: { href: string; testo: string };
}) {
  const noto = attributo.stato !== "mancante" && valore !== null;
  return (
    <div className="flex flex-wrap items-start justify-between gap-x-3 gap-y-1 py-2" data-testid="wi-riga">
      <div className="min-w-0">
        <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{etichetta}</p>
        <p className={`text-sm ${noto ? "" : "italic text-muted-foreground"}`}>
          {noto ? valore : "Non ancora noto"}
          {noto && rimando ? (
            <>
              {" · "}
              <a href={rimando.href} className="text-bordeaux underline-offset-2 hover:underline">
                {rimando.testo}
              </a>
            </>
          ) : null}
        </p>
        {!senzaNota && attributo.nota && attributo.stato !== "mancante" ? (
          <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">{attributo.nota}</p>
        ) : null}
      </div>
      <StatoBadge attributo={attributo} />
    </div>
  );
}

function descrizioneFinestra(a: IntelligenzaVino["enologia"]["finestraBevuta"]): string | null {
  const v = a.valore;
  if (!v) return null;
  const apice = v.apiceInizio && v.apiceFine ? ` · momento ideale ${v.apiceInizio}–${v.apiceFine}` : "";
  return `${v.inizio}–${v.fine}${apice}`;
}

/**
 * Scheda Wine Intelligence: identità, informazioni enologiche, provenienza,
 * qualità e limiti, a partire dai dati realmente presenti. Non ripete «Quando
 * berlo», «Abbinamenti» e Price Intelligence: li riassume e rimanda alle
 * sezioni esistenti.
 *
 * `wineId` è la chiave dei metadati (`wineSlug ?? id`), la stessa di
 * `DrinkWindowSection` e `FoodPairingSection`. `compatta` è la versione per la
 * Cantina: richiusa di default, senza ancore a sezioni che lì non esistono.
 */
export function WineIntelligenceCard({
  wine,
  wineId,
  compatta = false,
  ancore = false,
  schedaHref,
  conNotePersonali = false,
}: {
  wine: VinoPerIntelligenza;
  wineId: string;
  compatta?: boolean;
  /** Mostra i rimandi alle sezioni della scheda annuncio (esistono solo lì). */
  ancore?: boolean;
  /** Collegamento alla scheda completa, per la versione compatta. */
  schedaHref?: string | null;
  /** WI-005B: mostra le dichiarazioni private del proprietario (solo dalla sua Cantina, non sugli annunci). */
  conNotePersonali?: boolean;
}) {
  const { drinkWindowOverrides, notePersonaliVino } = useVinea();
  const base = useWineMeta(wineId);
  const override = drinkWindowOverrides[wineId];
  // WI-005B: la dichiarazione personale dell'utente su QUESTO vino (private, non certificate).
  const nota = conNotePersonali && wine.wineSlug ? notePersonaliVino?.[wine.wineSlug] : undefined;
  const i = useMemo(
    () =>
      costruisciIntelligenzaVino({
        wine,
        meta: mergeMeta(base, override),
        base,
        personale: nota,
      }),
    [wine, base, override, nota],
  );
  const { identita: id, enologia: en, qualita: q } = i;

  const corpo = (
    <div data-testid="wine-intelligence-corpo">
      {compatta ? null : (
        <section aria-label="Identità del vino" className="divide-y divide-border">
          <Riga senzaNota etichetta="Produttore" valore={id.produttore.valore} attributo={id.produttore} />
          <Riga senzaNota etichetta="Vino" valore={id.nome.valore} attributo={id.nome} />
          <Riga senzaNota etichetta="Annata" valore={id.annata.valore?.toString() ?? null} attributo={id.annata} />
          <Riga senzaNota etichetta="Regione" valore={id.regione.valore} attributo={id.regione} />
          <Riga senzaNota etichetta="Denominazione" valore={id.denominazione.valore} attributo={id.denominazione} />
          <Riga senzaNota etichetta="Tipologia" valore={id.tipologia.valore} attributo={id.tipologia} />
          <Riga senzaNota etichetta="Formato" valore={id.formato.valore} attributo={id.formato} />
          {id.nome.nota ? (
            <p className="py-2 text-[11px] leading-snug text-muted-foreground" data-testid="wi-nota-identita">
              {id.nome.nota}
            </p>
          ) : null}
        </section>
      )}

      <section
        aria-label="Informazioni enologiche"
        className={`divide-y divide-border ${compatta ? "" : "mt-3 border-t border-border pt-1"}`}
      >
        <Riga
          etichetta="Finestra di bevuta"
          valore={descrizioneFinestra(en.finestraBevuta)}
          attributo={en.finestraBevuta}
          rimando={ancore ? { href: "#quando-berlo", testo: "dettagli" } : undefined}
        />
        <Riga etichetta="Temperatura di servizio" valore={en.temperaturaServizio.valore} attributo={en.temperaturaServizio} />
        <Riga etichetta="Calice" valore={en.calice.valore} attributo={en.calice} />
        <Riga
          etichetta="Decantazione"
          valore={en.decantazione.valore === null ? null : `${en.decantazione.valore} minuti`}
          attributo={en.decantazione}
        />
        <Riga
          etichetta="Abbinamenti"
          valore={
            en.abbinamenti.valore === null
              ? null
              : `${en.abbinamenti.valore} ${en.abbinamenti.valore === 1 ? "indicazione" : "indicazioni"}`
          }
          attributo={en.abbinamenti}
          rimando={ancore ? { href: "#abbinamenti", testo: "vedi abbinamenti" } : undefined}
        />
        <Riga etichetta="Occasione" valore={en.occasione.valore} attributo={en.occasione} />
      </section>

      {i.personale ? (
        <section
          aria-label="Le tue dichiarazioni"
          className="mt-3 rounded-xl border border-oro/40 bg-oro/5 p-3"
          data-testid="wi-personale"
        >
          <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            Le tue dichiarazioni · private
          </p>
          <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">
            Le hai scritte tu: valgono solo per te, non sono certificate e non cambiano i dati condivisi qui sopra.
          </p>
          <dl className="mt-2 divide-y divide-border">
            {i.personale.dichiarazioni.map((d) => (
              <div key={d.chiave} className="flex flex-wrap items-start justify-between gap-x-3 gap-y-1 py-1.5">
                <div className="min-w-0">
                  <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{d.etichetta}</dt>
                  <dd className="text-sm">{d.testo}</dd>
                </div>
                <span
                  className="inline-flex shrink-0 items-center rounded-full bg-oro/20 px-2 py-0.5 text-[10px] font-semibold text-antracite"
                  data-origine={d.origine}
                  data-stato={d.stato}
                >
                  Dichiarato da te
                </span>
              </div>
            ))}
          </dl>
          {i.personale.osservazioni ? (
            <p className="mt-2 whitespace-pre-line text-sm" data-testid="wi-personale-osservazioni">
              <span className="block text-[11px] uppercase tracking-wide text-muted-foreground">Osservazioni</span>
              {i.personale.osservazioni}
            </p>
          ) : null}
        </section>
      ) : null}

      {q.segnalazioni.length > 0 ? (
        <ul
          className="mt-3 space-y-1.5"
          aria-label="Segnalazioni sulla scheda"
          data-testid="wi-segnalazioni"
        >
          {q.segnalazioni.map((s) => (
            <li
              key={s.codice}
              data-gravita={s.gravita}
              className={`flex items-start gap-2 rounded-xl p-2.5 text-xs ${
                s.gravita === "attenzione" ? "bg-bordeaux/10 text-bordeaux" : "bg-secondary/60 text-muted-foreground"
              }`}
            >
              {s.gravita === "attenzione" ? (
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
              ) : (
                <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
              )}
              <span>{s.testo}</span>
            </li>
          ))}
        </ul>
      ) : null}

      <p className="mt-3 text-[11px] leading-snug text-muted-foreground" data-testid="wi-nota-completezza">
        La completezza dice quanti campi sono compilati, non quanto siano affidabili.
        {q.ultimoAggiornamento ? ` Ultimo aggiornamento registrato: ${q.ultimoAggiornamento}.` : ""}
      </p>

      {ancore ? (
        <div className="mt-3 flex flex-wrap gap-2" data-testid="wi-azioni">
          <a href="#quando-berlo" className="rounded-full border border-border px-3 py-1 text-xs hover:border-bordeaux hover:text-bordeaux">
            Quando berlo
          </a>
          <a href="#abbinamenti" className="rounded-full border border-border px-3 py-1 text-xs hover:border-bordeaux hover:text-bordeaux">
            Abbinamenti
          </a>
          <a href="#price-intelligence-titolo" className="rounded-full border border-border px-3 py-1 text-xs hover:border-bordeaux hover:text-bordeaux">
            Price Intelligence
          </a>
        </div>
      ) : null}
      {compatta && schedaHref ? (
        <Link href={schedaHref} className="mt-3 inline-block text-xs text-bordeaux hover:underline">
          Apri la scheda completa
        </Link>
      ) : null}
    </div>
  );

  const completatiDaTe = i.personale?.completati.length ?? 0;
  const riepilogo = `${q.conosciuti} su ${q.totale} campi noti${q.stimati ? ` · ${q.stimati} stimati` : ""}${
    q.mancantiPersonali.length ? ` · ${q.mancantiPersonali.length} mancanti` : ""
  }${
    completatiDaTe
      ? ` · ${completatiDaTe} ${completatiDaTe === 1 ? "completato" : "completati"} da te`
      : ""
  }`;

  if (compatta) {
    return (
      <details
        className="group rounded-xl border border-border bg-card px-3 py-2"
        data-testid="wine-intelligence"
      >
        <summary className="flex cursor-pointer list-none items-center justify-between gap-2 text-xs font-medium">
          <span className="inline-flex items-center gap-1">
            <Sparkles className="h-3 w-3 text-oro" aria-hidden /> Scheda intelligente
            <span className="font-normal text-muted-foreground">· {riepilogo}</span>
          </span>
          <ChevronDown className="h-3.5 w-3.5 transition group-open:rotate-180" aria-hidden />
        </summary>
        <div className="mt-2">{corpo}</div>
      </details>
    );
  }

  return (
    <section
      aria-labelledby="wine-intelligence-titolo"
      className="rounded-2xl border border-border bg-card p-5"
      data-testid="wine-intelligence"
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Wine Intelligence</p>
          <h2 id="wine-intelligence-titolo" className="font-serif text-2xl">
            Cosa sappiamo di questo vino
          </h2>
        </div>
        <span className="text-xs text-muted-foreground" data-testid="wi-riepilogo">
          {riepilogo}
        </span>
      </div>
      <p className="mt-1 text-xs text-muted-foreground">
        Ogni informazione indica se è registrata, dichiarata, stimata o ancora ignota.
      </p>
      <div className="mt-3">{corpo}</div>
    </section>
  );
}
