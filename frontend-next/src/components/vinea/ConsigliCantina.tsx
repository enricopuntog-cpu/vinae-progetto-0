"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { Info, Moon, Search, UtensilsCrossed, ClipboardList } from "lucide-react";
import { eMetaDiRipiego, phaseShort } from "@/data/cellar";
import type { CellarBottle } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { useCercaMeta } from "@/lib/wine-meta-context";
import { chiaveCantina } from "@/lib/cantina/gruppo";
import {
  categorieAbbinamento,
  consigliAbbinamento,
  consigliStasera,
  datiMancanti,
  type Consiglio,
  type CriterioAbbinamento,
  type IngressoConsigli,
  type Motivo,
  type VinoDaCompletare,
} from "@/lib/cantina/consigli";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

type Scheda = "stasera" | "cena" | "dati";

const ORIGINE: Record<Motivo["origine"], { testo: string; classe: string }> = {
  registrato: { testo: "Registrato", classe: "bg-salvia/15 text-salvia-scuro" },
  dichiarato: { testo: "Dichiarato", classe: "bg-oro/20 text-antracite" },
  stimato: { testo: "Stimato · non verificato", classe: "bg-bordeaux/10 text-bordeaux" },
};

const MOSTRATI_INIZIALI = 3;
const MOSTRATI_ESPANSI = 12;

function titolo(c: Pick<Consiglio, "produttore" | "nome" | "annata" | "formato">): string {
  return [c.produttore, c.nome, c.annata ?? "senza annata"].filter(Boolean).join(" · ");
}

function ancoraGruppo(chiave: string): string {
  return `gruppo-${chiave}`;
}

function CartaConsiglio({ c, posizione }: { c: Consiglio; posizione: number }) {
  return (
    <li
      className="rounded-2xl border border-border bg-card p-4"
      data-testid="consiglio-cantina"
      data-chiave={c.chiave}
      data-bottiglia={c.bottleId}
    >
      <div className="flex items-start gap-3">
        <span
          aria-hidden
          className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-bordeaux font-serif text-sm text-crema"
        >
          {posizione}
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-serif text-lg leading-snug">{titolo(c)}</p>
          <p className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
            <span>{c.formato}</span>
            <span aria-hidden>·</span>
            <span data-testid="consiglio-disponibili">
              {c.disponibili === 1 ? "1 bottiglia disponibile" : `${c.disponibili} bottiglie disponibili`}
            </span>
            {phaseShort[c.fase] ? (
              <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-antracite">
                {phaseShort[c.fase]}
              </span>
            ) : null}
            {c.tipoAbbinamento === "ripiego" ? (
              <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-[10px] font-semibold text-bordeaux">
                Abbinamento generico
              </span>
            ) : null}
          </p>
        </div>
      </div>

      <p className="mt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Perché</p>
      <ul className="mt-1 space-y-1.5">
        {c.motivi.map((m) => (
          <li key={m.testo} className="flex flex-wrap items-start gap-x-2 gap-y-1 text-sm">
            <span className="min-w-0 flex-1">{m.testo}</span>
            <span
              className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold ${ORIGINE[m.origine].classe}`}
              data-origine={m.origine}
            >
              {ORIGINE[m.origine].testo}
            </span>
          </li>
        ))}
      </ul>

      {c.limiti.length > 0 ? (
        <ul className="mt-2 space-y-1" data-testid="consiglio-limiti">
          {c.limiti.map((l) => (
            <li key={l} className="flex gap-1.5 text-xs italic text-muted-foreground">
              <Info className="mt-0.5 h-3 w-3 shrink-0" aria-hidden />
              {l}
            </li>
          ))}
        </ul>
      ) : null}

      <div className="mt-3 flex flex-wrap gap-2">
        <a
          href={`#${ancoraGruppo(c.chiave)}`}
          className="inline-flex min-h-9 items-center rounded-full border border-border px-3 text-xs font-medium hover:border-bordeaux hover:text-bordeaux"
        >
          Vai alla bottiglia
        </a>
        {c.href ? (
          <Link
            href={c.href}
            className="inline-flex min-h-9 items-center rounded-full border border-border px-3 text-xs font-medium hover:border-bordeaux hover:text-bordeaux"
          >
            Scheda del vino
          </Link>
        ) : null}
      </div>
    </li>
  );
}

function ListaConsigli({
  consigli,
  altri,
  espanso,
  onEspandi,
}: {
  consigli: Consiglio[];
  altri: number;
  espanso: boolean;
  onEspandi: () => void;
}) {
  return (
    <>
      <ol className="space-y-3" data-testid="consigli-lista">
        {consigli.map((c, i) => (
          <CartaConsiglio key={c.chiave} c={c} posizione={i + 1} />
        ))}
      </ol>
      {altri > 0 && !espanso ? (
        <Button type="button" variant="outline" size="sm" className="mt-3" onClick={onEspandi}>
          Mostra altri {altri}
        </Button>
      ) : null}
    </>
  );
}

function Vuoto({ children, testId }: { children: React.ReactNode; testId: string }) {
  return (
    <p
      className="rounded-2xl border border-dashed border-border bg-secondary/30 p-4 text-sm text-muted-foreground"
      data-testid={testId}
    >
      {children}
    </p>
  );
}

function CartaDati({ v }: { v: VinoDaCompletare }) {
  return (
    <li className="rounded-2xl border border-border bg-card p-4" data-testid="dati-mancanti-vino" data-chiave={v.chiave}>
      <p className="font-serif text-lg leading-snug">{titolo(v)}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">
        {v.formato} · {v.bottiglie === 1 ? "1 bottiglia" : `${v.bottiglie} bottiglie`}
      </p>
      <ul className="mt-2 space-y-1.5">
        {v.voci.map((x) => (
          <li key={x.campo} className="flex flex-wrap items-start gap-x-2 gap-y-1 text-sm">
            <span className="min-w-0 flex-1">
              <span className="font-medium">{x.etichetta}.</span> {x.nota}
            </span>
            <span
              className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                x.stato === "mancante" ? "bg-secondary text-muted-foreground" : "bg-bordeaux/10 text-bordeaux"
              }`}
              data-stato={x.stato}
            >
              {x.stato === "mancante" ? "Mancante" : "Di ripiego"}
            </span>
          </li>
        ))}
      </ul>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <a
          href={`#${ancoraGruppo(v.chiave)}`}
          className="inline-flex min-h-9 items-center rounded-full border border-border px-3 text-xs font-medium hover:border-bordeaux hover:text-bordeaux"
        >
          Vai alla bottiglia
        </a>
        {v.azione ? (
          <Link
            href={v.azione.href}
            className="inline-flex min-h-9 items-center rounded-full bg-bordeaux px-3 text-xs font-medium text-crema hover:bg-bordeaux/90"
          >
            {v.azione.testo}
          </Link>
        ) : (
          <span className="text-xs italic text-muted-foreground">
            Da qui non c'è ancora un comando per completare questi dati.
          </span>
        )}
      </div>
    </li>
  );
}

/**
 * WI-005 — «Consigli dalla tua Cantina».
 *
 * Una sola sezione in `/cantina`, senza ripetere i contatori già presenti
 * (Pronte da bere, Da attendere, Da bere presto): sceglie e motiva la singola
 * bottiglia. Non scrive nulla, non chiama nessun servizio e nessun modello:
 * legge le bottiglie e i metadati già caricati dalla Cantina e si ricalcola a
 * ogni cambio di stato (apertura, vendita, riserva).
 */
export function ConsigliCantina({
  bottiglie,
  vini,
}: {
  bottiglie: readonly CellarBottle[];
  vini: readonly Wine[];
}) {
  const cercaMeta = useCercaMeta();
  const [scheda, setScheda] = useState<Scheda>("stasera");
  const [categoria, setCategoria] = useState<string | null>(null);
  const [testo, setTesto] = useState("");
  const [espanso, setEspanso] = useState(false);

  const ingresso = useMemo<IngressoConsigli>(
    () => ({
      anno: new Date().getFullYear(),
      bottiglie,
      vini: vini.map((w) => {
        const chiave = chiaveCantina(w);
        const meta = cercaMeta(chiave);
        return { chiave, wine: w, meta, ripiego: eMetaDiRipiego(meta) };
      }),
    }),
    [bottiglie, vini, cercaMeta],
  );

  const max = espanso ? MOSTRATI_ESPANSI : MOSTRATI_INIZIALI;
  const stasera = useMemo(() => consigliStasera(ingresso, { max }), [ingresso, max]);
  const categorie = useMemo(() => categorieAbbinamento(ingresso), [ingresso]);
  const criterio: CriterioAbbinamento | null =
    testo.trim().length > 0 ? { tipo: "testo", valore: testo } : categoria ? { tipo: "categoria", valore: categoria } : null;
  const cena = useMemo(
    () => (criterio ? consigliAbbinamento(ingresso, criterio, { max }) : null),
    // `criterio` è derivato da `testo` e `categoria`
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ingresso, max, testo, categoria],
  );
  const mancanti = useMemo(() => datiMancanti(ingresso), [ingresso]);

  const vuota = bottiglie.length === 0;
  const cambia = (s: Scheda) => {
    setScheda(s);
    setEspanso(false);
  };

  const schede: { id: Scheda; etichetta: string; Icona: typeof Moon }[] = [
    { id: "stasera", etichetta: "Cosa apro stasera", Icona: Moon },
    { id: "cena", etichetta: "Cosa abbino a cena", Icona: UtensilsCrossed },
    { id: "dati", etichetta: "Completa i dati", Icona: ClipboardList },
  ];

  return (
    <section
      id="consigli-cantina"
      aria-labelledby="consigli-cantina-titolo"
      className="scroll-mt-20 rounded-3xl border border-border bg-card p-4 md:p-6"
      data-testid="consigli-cantina"
    >
      <p className="text-xs uppercase tracking-wide text-muted-foreground">Dalla tua Cantina</p>
      <h2 id="consigli-cantina-titolo" className="font-serif text-2xl md:text-3xl">
        Consigli dalla tua Cantina
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Suggerimenti motivati sulle bottiglie che possiedi davvero e che puoi aprire. Nessun modello AI: solo i dati
        della tua Cantina.
      </p>

      {vuota ? (
        <div className="mt-4">
          <Vuoto testId="consigli-vuota">
            La tua Cantina è vuota: quando aggiungerai delle bottiglie qui troverai cosa aprire, cosa abbinare e quali
            dati completare.
          </Vuoto>
        </div>
      ) : (
        <>
          <div role="tablist" aria-label="Criterio dei consigli" className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
            {schede.map(({ id, etichetta, Icona }) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={scheda === id}
                data-testid={`consigli-tab-${id}`}
                onClick={() => cambia(id)}
                className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-full border px-4 text-sm font-medium transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-bordeaux/40 ${
                  scheda === id
                    ? "border-bordeaux bg-bordeaux text-crema"
                    : "border-border bg-secondary/40 text-antracite hover:border-bordeaux"
                }`}
              >
                <Icona className="h-4 w-4" aria-hidden />
                {etichetta}
              </button>
            ))}
          </div>

          <div className="mt-4" role="tabpanel">
            {scheda === "stasera" ? (
              <div className="space-y-3">
                {stasera.consigli.length > 0 ? (
                  <ListaConsigli
                    consigli={stasera.consigli}
                    altri={stasera.altriCandidati}
                    espanso={espanso}
                    onEspandi={() => setEspanso(true)}
                  />
                ) : stasera.totaleApribili === 0 ? (
                  <Vuoto testId="consigli-nessuna-apribile">
                    Nessuna bottiglia è apribile adesso: quelle che hai sono già aperte, consumate, in vendita o
                    riservate.
                  </Vuoto>
                ) : (
                  <Vuoto testId="consigli-nessun-consiglio">
                    Nessuna delle tue bottiglie apribili ha una finestra di bevuta che permetta di consigliarla per
                    stasera.
                  </Vuoto>
                )}
                {stasera.senzaFinestra > 0 || stasera.daAttendere > 0 ? (
                  <p className="text-xs text-muted-foreground" data-testid="consigli-note-stasera">
                    {stasera.senzaFinestra > 0
                      ? `${stasera.senzaFinestra} ${stasera.senzaFinestra === 1 ? "vino apribile non ha" : "vini apribili non hanno"} una finestra di bevuta: non si può dire se siano pronti. `
                      : ""}
                    {stasera.daAttendere > 0
                      ? `${stasera.daAttendere} ${stasera.daAttendere === 1 ? "vino è" : "vini sono"} ancora da attendere secondo la loro finestra.`
                      : ""}
                  </p>
                ) : null}
              </div>
            ) : null}

            {scheda === "cena" ? (
              <div className="space-y-3">
                <p className="text-sm text-muted-foreground">Scegli una categoria o scrivi il piatto.</p>
                {categorie.length > 0 ? (
                  <div className="flex flex-wrap gap-2" role="group" aria-label="Categorie di piatto">
                    {categorie.map((c) => (
                      <button
                        key={c}
                        type="button"
                        aria-pressed={categoria === c && testo.trim() === ""}
                        data-testid="consigli-categoria"
                        onClick={() => {
                          setCategoria(categoria === c ? null : c);
                          setTesto("");
                          setEspanso(false);
                        }}
                        className={`min-h-9 rounded-full border px-3 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-bordeaux/40 ${
                          categoria === c && testo.trim() === ""
                            ? "border-bordeaux bg-bordeaux text-crema"
                            : "border-border hover:border-bordeaux"
                        }`}
                      >
                        {c}
                      </button>
                    ))}
                  </div>
                ) : (
                  <Vuoto testId="consigli-nessuna-categoria">
                    Nessuno dei vini che puoi aprire ha abbinamenti registrati: per ora non ci sono categorie da
                    proporre. Puoi comunque cercare un piatto per vedere gli abbinamenti generici.
                  </Vuoto>
                )}
                <div className="relative">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                  <Input
                    value={testo}
                    onChange={(e) => {
                      setTesto(e.target.value);
                      setEspanso(false);
                    }}
                    placeholder="es. brasato, ostriche, ragù…"
                    aria-label="Piatto"
                    data-testid="consigli-piatto"
                    className="pl-9"
                  />
                </div>

                {cena === null ? (
                  <p className="text-xs text-muted-foreground">Nessun piatto scelto.</p>
                ) : cena.consigli.length > 0 ? (
                  <ListaConsigli
                    consigli={cena.consigli}
                    altri={cena.altriCandidati}
                    espanso={espanso}
                    onEspandi={() => setEspanso(true)}
                  />
                ) : cena.totaleApribili === 0 ? (
                  <Vuoto testId="consigli-cena-nessuna-apribile">Nessuna bottiglia è apribile adesso.</Vuoto>
                ) : (
                  <Vuoto testId="consigli-cena-nessuno">
                    Nessuna bottiglia apribile ha un abbinamento documentato per questo piatto. Non propongo
                    corrispondenze inventate.
                    {cena.senzaAbbinamenti > 0
                      ? ` ${cena.senzaAbbinamenti} ${cena.senzaAbbinamenti === 1 ? "vino non ha" : "vini non hanno"} abbinamenti propri registrati.`
                      : ""}
                  </Vuoto>
                )}
              </div>
            ) : null}

            {scheda === "dati" ? (
              <div className="space-y-3">
                {mancanti.length === 0 ? (
                  <Vuoto testId="dati-completi">
                    Per le bottiglie che hai ancora, i dati principali (annata, regione, denominazione, finestra di
                    bevuta, abbinamenti) sono tutti presenti e non di ripiego.
                  </Vuoto>
                ) : (
                  <>
                    <p className="text-sm text-muted-foreground">
                      {mancanti.length === 1 ? "Un vino ha" : `${mancanti.length} vini hanno`} dati da completare.
                    </p>
                    <ul className="space-y-3">
                      {mancanti.slice(0, espanso ? MOSTRATI_ESPANSI : MOSTRATI_INIZIALI).map((v) => (
                        <CartaDati key={v.chiave} v={v} />
                      ))}
                    </ul>
                    {!espanso && mancanti.length > MOSTRATI_INIZIALI ? (
                      <Button type="button" variant="outline" size="sm" onClick={() => setEspanso(true)}>
                        Mostra altri {mancanti.length - MOSTRATI_INIZIALI}
                      </Button>
                    ) : null}
                  </>
                )}
              </div>
            ) : null}
          </div>

          <p className="mt-4 text-[11px] leading-snug text-muted-foreground">
            Indicazioni ordinate con regole esplicite sui dati disponibili, non una valutazione certificata. Le finestre
            di bevuta e gli abbinamenti possono essere stimati o dichiarati: l'origine è indicata accanto a ogni motivo.
          </p>
        </>
      )}
    </section>
  );
}
