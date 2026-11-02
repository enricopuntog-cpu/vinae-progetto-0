"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { ShoppingBag } from "lucide-react";
import { RiepilogoStimaLogistica } from "@/components/vinea/accessori-spedizione/StimaSpedizioneAccessorio";
import {
  TESTI_ORDINI_ACCESSORI,
  type DisponibilitaAccessorio,
  type OrdineAccessorio,
} from "@/lib/accessori-ordini/ordine";
import {
  MAX_QUANTITA_LOGISTICA,
  type StimaLogistica,
  type StimaLogisticaDisponibile,
} from "@/lib/accessori-spedizione/stima";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriLogisticaService } from "@/services/accessori-spedizione-service";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";
import { AnnullaPrenotazione, RiepilogoOrdineAccessorio } from "./OrdiniAccessori";

type Fase =
  | { tipo: "verifica" }
  | { tipo: "chiuso"; motivo: "checkout" | "esaurito" | "errore" }
  | { tipo: "form" }
  | { tipo: "riepilogo"; stima: StimaLogisticaDisponibile }
  | { tipo: "ordine"; ordine: OrdineAccessorio };

const nuovaChiave = (): string => `acc-${globalThis.crypto.randomUUID()}`;

/**
 * Prenotazione di 1-N pezzi di un annuncio Accessori (VPM-015B5A). Il browser
 * sceglie la quantità e conferma un riepilogo che il database ha congelato:
 * importi, venditore e spedizione non passano mai da qui. Nessun pagamento: la
 * prenotazione tiene da parte i pezzi per qualche minuto.
 */
export function PrenotazioneAccessorio({
  annuncioId,
  autenticato,
}: {
  annuncioId: string;
  autenticato: boolean;
}) {
  const ordini = useMemo(() => creaAccessoriOrdiniService(getSupabaseClient()), []);
  const logistica = useMemo(() => creaAccessoriLogisticaService(getSupabaseClient()), []);
  const [fase, setFase] = useState<Fase>({ tipo: "verifica" });
  const [disp, setDisp] = useState<DisponibilitaAccessorio | null>(null);
  const [quantita, setQuantita] = useState(1);
  const [lavoro, setLavoro] = useState(false);
  const [errore, setErrore] = useState<string | null>(null);
  const [negata, setNegata] = useState<StimaLogistica | null>(null);
  // La stessa chiave per ogni ripetizione dello stesso gesto (doppio click, nuovo
  // tentativo dopo un errore di rete); cambia solo con un nuovo riepilogo.
  const chiave = useRef<string>(nuovaChiave());
  const inCorso = useRef(false);

  useEffect(() => {
    let attivo = true;
    ordini.disponibilita(annuncioId).then((r) => {
      if (!attivo) return;
      if (r.ok && r.data.prenotabile) {
        setDisp(r.data);
        setFase({ tipo: "form" });
      } else if (!r.ok) {
        setFase({ tipo: "chiuso", motivo: "errore" });
      } else {
        setFase({ tipo: "chiuso", motivo: r.data.motivo === "esaurito" ? "esaurito" : "checkout" });
      }
    });
    return () => {
      attivo = false;
    };
  }, [ordini, annuncioId]);

  if (fase.tipo === "verifica") return null;

  if (fase.tipo === "chiuso") {
    return (
      <section data-testid="prenotazione-chiusa" className="mx-auto max-w-3xl px-4 pb-10 text-sm text-muted-foreground">
        {fase.motivo === "esaurito"
          ? TESTI_ORDINI_ACCESSORI.esaurito
          : fase.motivo === "errore"
            ? TESTI_ORDINI_ACCESSORI.nonRaggiungibile
            : TESTI_ORDINI_ACCESSORI.chiuso}
      </section>
    );
  }

  const massimo = Math.min(Math.max(1, disp?.disponibili ?? 1), MAX_QUANTITA_LOGISTICA);

  async function preparaRiepilogo() {
    if (inCorso.current) return;
    inCorso.current = true;
    setLavoro(true);
    setErrore(null);
    setNegata(null);
    const r = await logistica.congela({ annuncioId, quantita });
    inCorso.current = false;
    setLavoro(false);
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    if (!r.data.ok) {
      setNegata(r.data);
      return;
    }
    if (!r.data.congelato || !r.data.preventivoId) {
      setErrore("Il riepilogo non è disponibile: riprova fra qualche istante.");
      return;
    }
    chiave.current = nuovaChiave();
    setFase({ tipo: "riepilogo", stima: r.data });
  }

  async function conferma(stima: StimaLogisticaDisponibile) {
    // Doppio click: il secondo gesto trova il lavoro già in corso.
    if (inCorso.current || !stima.preventivoId) return;
    inCorso.current = true;
    setLavoro(true);
    setErrore(null);
    const r = await ordini.crea({ preventivoId: stima.preventivoId, chiave: chiave.current });
    inCorso.current = false;
    setLavoro(false);
    if (!r.ok) {
      // Si resta sul riepilogo con la STESSA chiave: se la risposta si è persa ma
      // l'ordine esiste, ripetere la conferma restituisce lo stesso ordine. Per un
      // riepilogo non più valido si torna indietro con «Cambia quantità», che ne
      // prepara uno nuovo con una chiave nuova.
      setErrore(r.error);
      return;
    }
    setFase({ tipo: "ordine", ordine: r.data });
  }

  return (
    <section
      aria-labelledby="titolo-prenotazione"
      data-testid="sezione-prenotazione"
      aria-live="polite"
      className="mx-auto max-w-3xl space-y-3 px-4 pb-10"
    >
      <h2 id="titolo-prenotazione" className="flex items-center gap-2 text-lg font-semibold">
        <ShoppingBag className="size-5" aria-hidden /> {TESTI_ORDINI_ACCESSORI.titolo}
      </h2>

      {!autenticato ? (
        <p className="text-sm">
          <Link href={`/accedi?next=${encodeURIComponent(`/accessori/annunci/${annuncioId}`)}`} className="underline">
            {TESTI_ORDINI_ACCESSORI.accedi}
          </Link>
        </p>
      ) : fase.tipo === "form" ? (
        <>
          <p className="text-sm text-muted-foreground">{TESTI_ORDINI_ACCESSORI.introduzione}</p>
          <div className="flex flex-wrap items-center gap-3 text-sm">
            <label className="flex items-center gap-2">
              Quantità
              <input
                type="number"
                min={1}
                max={massimo}
                value={quantita}
                data-testid="prenotazione-quantita"
                onChange={(e) => {
                  const n = Math.trunc(Number(e.target.value));
                  if (Number.isFinite(n)) setQuantita(Math.min(Math.max(1, n), massimo));
                }}
                className="w-20 rounded-md border bg-background px-2 py-1"
              />
            </label>
            <span className="text-muted-foreground" data-testid="prenotazione-disponibili">
              {disp?.disponibili} {disp?.disponibili === 1 ? "pezzo disponibile" : "pezzi disponibili"}
            </span>
            <button
              type="button"
              data-testid="prenotazione-prepara"
              disabled={lavoro}
              onClick={preparaRiepilogo}
              className="rounded-md border px-3 py-1.5"
            >
              {lavoro ? "Preparo…" : "Prepara il riepilogo"}
            </button>
          </div>
          {negata ? (
            <div aria-live="polite">
              <RiepilogoStimaLogistica stato={{ tipo: "pronto", stima: negata }} />
            </div>
          ) : null}
        </>
      ) : fase.tipo === "riepilogo" ? (
        <>
          <div aria-live="polite" data-testid="prenotazione-riepilogo">
            <RiepilogoStimaLogistica stato={{ tipo: "pronto", stima: fase.stima }} />
          </div>
          <p className="text-xs text-muted-foreground">{TESTI_ORDINI_ACCESSORI.nessunAddebito}</p>
          <div className="flex gap-3">
            <button
              type="button"
              data-testid="prenotazione-conferma"
              disabled={lavoro}
              onClick={() => conferma(fase.stima)}
              className="rounded-md border bg-primary px-3 py-1.5 text-primary-foreground"
            >
              {lavoro ? "Confermo…" : "Conferma la prenotazione"}
            </button>
            <button
              type="button"
              disabled={lavoro}
              onClick={() => setFase({ tipo: "form" })}
              className="rounded-md border px-3 py-1.5"
            >
              Cambia quantità
            </button>
          </div>
        </>
      ) : (
        <>
          <RiepilogoOrdineAccessorio ordine={fase.ordine} />
          <AnnullaPrenotazione ordine={fase.ordine} onAnnullato={(o) => setFase({ tipo: "ordine", ordine: o })} />
          <Link href="/ordini-accessori" className="block text-sm underline">
            {TESTI_ORDINI_ACCESSORI.tuttiGliOrdini}
          </Link>
        </>
      )}

      {errore ? (
        <div role="alert" data-testid="prenotazione-errore" className="space-y-1 text-sm text-destructive">
          <p>{errore}</p>
          <Link href="/ordini-accessori" className="underline">
            {TESTI_ORDINI_ACCESSORI.tuttiGliOrdini}
          </Link>
        </div>
      ) : null}
    </section>
  );
}
