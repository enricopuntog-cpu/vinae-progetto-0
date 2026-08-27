"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Wine } from "@/data/wines";
import { getSupabaseClient } from "@/lib/supabase/client";
import { eseguiAzioneBeta } from "@/lib/beta/external-actions";
import {
  creaDatiCheckout,
  passiCheckout,
  validaPassoCheckout,
  type DatiCheckoutBeta,
  type ErroriCheckout,
} from "@/lib/beta/checkout";
import { AZIONI_PAGAMENTO_ABILITATE, IMBALLAGGIO_UI_ABILITATO } from "@/config/features";
import { createPaymentService } from "@/services/phase7/payment-service";

export const useBetaCheckout = (wine: Wine, email: string, proposalId?: string) => {
  const router = useRouter();
  const [usaSaldo, setUsaSaldo] = useState(false);
  const [dati, setDati] = useState(() => creaDatiCheckout(email));
  const [indice, setIndice] = useState(0);
  const [errori, setErrori] = useState<ErroriCheckout>({});
  const [bloccato, setBloccato] = useState(false);
  const [erroreAzione, setErroreAzione] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const idempotencyKey = useRef<string | null>(null);
  const passi = useMemo(() => passiCheckout(IMBALLAGGIO_UI_ABILITATO), []);
  const passo = passi[indice];

  const set = <K extends keyof DatiCheckoutBeta>(campo: K, valore: DatiCheckoutBeta[K]) => {
    setDati((correnti) => ({ ...correnti, [campo]: valore }));
    setErrori((correnti) => ({ ...correnti, [campo]: undefined }));
    setBloccato(false);
    setErroreAzione(null);
  };

  const avanti = () => {
    const trovati = validaPassoCheckout(passo, dati);
    setErrori(trovati);
    if (Object.keys(trovati).length === 0) setIndice((i) => Math.min(i + 1, passi.length - 1));
  };

  const indietro = () => {
    if (indice === 0) router.back();
    else setIndice((i) => i - 1);
  };

  const conferma = async () => {
    setInCorso(true);
    setBloccato(false);
    setErroreAzione(null);
    const esito = await eseguiAzioneBeta("pagamento", AZIONI_PAGAMENTO_ABILITATE, async () => {
      idempotencyKey.current ??= crypto.randomUUID();
      return createPaymentService(getSupabaseClient()).creaCheckout({
        listingId: wine.listingId ?? wine.id,
        proposalId,
        deliveryMode: dati.deliveryMode,
        idempotencyKey: idempotencyKey.current,
        usaSaldo,
      });
    });
    setInCorso(false);

    if (!esito.eseguita) {
      setBloccato(true);
      return;
    }
    if (!esito.valore.ok) {
      idempotencyKey.current = null;
      setErroreAzione(esito.valore.error);
      return;
    }
    if (esito.valore.data.saldoOnly) {
      // Il saldo Vinea ha coperto l'intero importo: nessun provider, nessuna
      // pagina di pagamento. Mostriamo una conferma locale.
      setErroreAzione(null);
      router.push(`/ordine/${esito.valore.data.orderId}?checkout=saldo`);
      return;
    }
    if (esito.valore.data.checkoutUrl) window.location.assign(esito.valore.data.checkoutUrl);
    else setErroreAzione("Il metodo di pagamento incorporato non è disponibile in questa build.");
  };

  return {
    dati, set, errori, passi, indice, passo, avanti, indietro, conferma,
    bloccato, erroreAzione, inCorso, usaSaldo, setUsaSaldo,
  };
};
