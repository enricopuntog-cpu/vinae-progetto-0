"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import type { OrdineAccessorio } from "@/lib/accessori-ordini/ordine";
import {
  RILETTURA_MS,
  RILETTURA_TENTATIVI,
  TESTI_PAGAMENTO,
  chiaveAperturaPagamento,
  esitoDaStripe,
  faseDaOrdine,
  indirizzoRitorno,
  valutaPagabilita,
  MESSAGGI_NON_PAGABILE,
} from "@/lib/accessori-ordini/pagamento";
import { caricaStripeBrowser } from "@/lib/payments/stripe-client";
import { getSupabaseClient } from "@/lib/supabase/client";
import { creaAccessoriOrdiniService } from "@/services/accessori-ordini-service";
import { apriPagamentoAccessori } from "@/services/phase7/payment-service";

type Fase = "idle" | "apertura" | "pronto" | "in_verifica" | "verifica_lunga" | "errore";

type Props = {
  ordine: OrdineAccessorio;
  /** `NEXT_PUBLIC_PAYMENT_ACTIONS_ENABLED` AND checkout Accessori aperto, calcolati dalla pagina. */
  azioniAbilitate: boolean;
  chiavePublishable: string | null;
  /** Il browser è tornato da Stripe: è solo un invito a rileggere l'ordine, non una prova. */
  inRitorno?: boolean;
  onOrdine: (o: OrdineAccessorio) => void;
  /** Vero mentre un pagamento è aperto o in verifica: l annullo si nasconde per non incrociarlo. */
  onImpegnato?: (impegnato: boolean) => void;
};

/** Form dentro `<Elements>`: conferma con Stripe.js e restituisce l'esito, mai uno stato «pagato». */
function FormPagamento({
  ordineId,
  onEsito,
}: {
  ordineId: string;
  onEsito: (e: ReturnType<typeof esitoDaStripe>) => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const [invio, setInvio] = useState(false);
  const inCorso = useRef(false);
  return (
    <form
      data-testid="pagamento-form"
      className="space-y-3"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!stripe || !elements || inCorso.current) return;
        inCorso.current = true;
        setInvio(true);
        const ritorno = indirizzoRitorno(window.location.origin, ordineId);
        try {
          if (!ritorno) {
            onEsito({ tipo: "errore", messaggio: TESTI_PAGAMENTO.aperturaFallita });
            return;
          }
          const r = await stripe.confirmPayment({
            elements,
            confirmParams: { return_url: ritorno },
            redirect: "if_required",
          });
          onEsito(esitoDaStripe(r));
        } catch {
          onEsito({ tipo: "errore", messaggio: TESTI_PAGAMENTO.nonRiuscito });
        } finally {
          inCorso.current = false;
          setInvio(false);
        }
      }}
    >
      <PaymentElement />
      <button
        type="submit"
        data-testid="pagamento-conferma"
        disabled={!stripe || !elements || invio}
        className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-60"
      >
        {invio ? TESTI_PAGAMENTO.conferma : TESTI_PAGAMENTO.confermaPagamento}
      </button>
    </form>
  );
}

/**
 * Pagamento della prenotazione (acquirente). Riusa `apriPagamentoAccessori` (B5B):
 * dal browser parte solo l'id dell'ordine. Il pagamento risulta riuscito
 * soltanto quando l'ordine riletto dal database è `pagato`.
 */
export function PagamentoAccessorio({ ordine, azioniAbilitate, chiavePublishable, inRitorno, onOrdine, onImpegnato }: Props) {
  const servizio = useMemo(() => creaAccessoriOrdiniService(getSupabaseClient()), []);
  const [fase, setFase] = useState<Fase>(inRitorno && ordine.stato === "in_attesa_pagamento" ? "in_verifica" : "idle");
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [azione, setAzione] = useState(false);
  const apertura = useRef(false);
  const [adesso, setAdesso] = useState(() => Date.now());
  const [chiusoInVerifica, setChiusoInVerifica] = useState(false);

  // Stripe riaccoda al ritorno `payment_intent_client_secret` e `payment_intent`: via dall URL e dalla cronologia.
  useEffect(() => {
    if (inRitorno && window.location.search) window.history.replaceState(null, "", window.location.pathname);
  }, [inRitorno]);

  const impegnato = fase !== "idle" && fase !== "errore";
  useEffect(() => {
    onImpegnato?.(impegnato);
  }, [impegnato, onImpegnato]);

  const stripePromise = useMemo(
    // Stripe.js (script di terze parti) si carica solo quando il pagamento è stato aperto, non alla vista dell ordine.
    () => (chiavePublishable && clientSecret ? caricaStripeBrowser(chiavePublishable) : null),
    [chiavePublishable, clientSecret],
  );

  // Stripe.js non caricato (rete, blocco dello script): si torna a «Paga» con un errore chiaro.
  useEffect(() => {
    if (!stripePromise) return;
    let attivo = true;
    const fallito = () => {
      if (!attivo) return;
      setClientSecret(null);
      setErrore(TESTI_PAGAMENTO.moduloNonCaricato);
      setFase("errore");
    };
    stripePromise.then((s) => (s ? undefined : fallito())).catch(fallito);
    return () => {
      attivo = false;
    };
  }, [stripePromise]);

  // Rilettura autoritativa dell'ordine mentre il pagamento è in verifica.
  const verificaAttiva = fase === "in_verifica";
  useEffect(() => {
    if (!verificaAttiva) return;
    let attivo = true;
    let tentativo = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const rileggi = async () => {
      tentativo += 1;
      const r = await servizio.leggi(ordine.id).catch(() => null);
      if (!attivo) return;
      if (r?.ok) {
        const f = faseDaOrdine(r.data);
        if (f !== "in_attesa") {
          setFase("idle");
          setChiusoInVerifica(f === "chiuso");
          onOrdine(r.data); // pagato (o chiuso: scaduto/annullato con eventuale compensazione B5B)
          return;
        }
      }
      if (tentativo >= RILETTURA_TENTATIVI) {
        setFase("verifica_lunga");
        return;
      }
      timer = setTimeout(rileggi, RILETTURA_MS);
    };
    void rileggi();
    return () => {
      attivo = false;
      if (timer) clearTimeout(timer);
    };
  }, [verificaAttiva, servizio, ordine.id, onOrdine]);

  const apri = useCallback(async () => {
    if (apertura.current) return; // doppio click: una sola apertura
    apertura.current = true;
    setErrore(null);
    setFase("apertura");
    try {
      const r = await apriPagamentoAccessori(getSupabaseClient(), {
        ordineId: ordine.id,
        idempotencyKey: chiaveAperturaPagamento(ordine.id),
      });
      if (!r.ok) {
        setErrore(TESTI_PAGAMENTO.aperturaFallita);
        setFase("errore");
        return;
      }
      if (!r.data.clientSecret) {
        // Il provider corrente usa PaymentIntent: una pagina ospitata non è supportata qui.
        setErrore(TESTI_PAGAMENTO.nonSupportato);
        setFase("errore");
        return;
      }
      setClientSecret(r.data.clientSecret);
      setFase("pronto");
    } catch {
      setErrore(TESTI_PAGAMENTO.aperturaFallita);
      setFase("errore");
    } finally {
      apertura.current = false;
    }
  }, [ordine.id]);

  const valutazione = valutaPagabilita({ ordine, azioniAbilitate, chiavePublishable, adesso });
  if (ordine.ruolo !== "acquirente") return null;

  // Ritorno da Stripe o conferma in corso: lo stato lo decide la rilettura, non il ritorno.
  if ((fase === "in_verifica" || fase === "verifica_lunga") && ordine.stato === "in_attesa_pagamento") {
    return (
      <div className="space-y-2">
        <p role="status" data-testid="pagamento-stato" className="text-sm">
          {fase === "in_verifica" ? TESTI_PAGAMENTO.inElaborazione : TESTI_PAGAMENTO.inElaborazioneLunga}
        </p>
        {fase === "verifica_lunga" ? (
          <button
            type="button"
            data-testid="pagamento-ricontrolla"
            onClick={() => setFase("in_verifica")}
            className="rounded-md border px-3 py-1.5 text-sm"
          >
            {TESTI_PAGAMENTO.ricontrolla}
          </button>
        ) : null}
      </div>
    );
  }

  if (chiusoInVerifica && ordine.stato !== "pagato") {
    return (
      <p role="status" data-testid="pagamento-chiuso" className="text-sm">
        {TESTI_PAGAMENTO.chiusoDuranteVerifica}
      </p>
    );
  }

  if (!valutazione.pagabile) {
    const testo = MESSAGGI_NON_PAGABILE[valutazione.motivo];
    return testo ? (
      <p data-testid="pagamento-non-disponibile" className="text-sm text-muted-foreground">
        {testo}
      </p>
    ) : null;
  }

  return (
    <div className="space-y-3" data-testid="pagamento-accessorio">
      {fase === "pronto" && clientSecret && stripePromise ? (
        <Elements stripe={stripePromise} options={{ clientSecret, locale: "it" }}>
          <FormPagamento
            ordineId={ordine.id}
            onEsito={(e) => {
              setAzione(false);
              setErrore(null);
              if (e.tipo === "in_verifica") {
                setAzione(false);
                setFase("in_verifica");
              } else if (e.tipo === "richiede_azione") {
                setAzione(true);
              } else {
                setErrore(e.messaggio);
              }
            }}
          />
        </Elements>
      ) : (
        <button
          type="button"
          data-testid="pagamento-paga"
          disabled={fase === "apertura"}
          onClick={() => {
            setAdesso(Date.now());
            void apri();
          }}
          className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-60"
        >
          {fase === "apertura" ? TESTI_PAGAMENTO.apertura : TESTI_PAGAMENTO.paga}
        </button>
      )}
      {azione ? (
        <p role="status" className="text-sm">
          {TESTI_PAGAMENTO.azioneRichiesta}
        </p>
      ) : null}
      {errore ? (
        <p role="alert" data-testid="pagamento-errore" className="text-sm text-destructive">
          <span className="font-medium">{TESTI_PAGAMENTO.nonRiuscito}.</span> {errore}
        </p>
      ) : null}
      <p className="text-xs text-muted-foreground">{TESTI_PAGAMENTO.sullaCopia}</p>
    </div>
  );
}
