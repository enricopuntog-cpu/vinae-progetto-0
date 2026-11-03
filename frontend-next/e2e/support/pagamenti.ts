import { eseguiSql } from "./db";

/**
 * Stato dei pagamenti Accessori per i test browser del post-vendita (VPM-015QA-FINAL-B2-COMPLETION).
 *
 * Nessun Stripe: gli eventi del fornitore sono SIMULATI con la stessa porta che usa il webhook firmato
 * (`accessori_pagamento_applica_evento`, riservata a service_role; qui la chiama il superutente dello stack
 * isolato). Prova quindi il comportamento del database e della UI, non quello di Stripe.
 */

export const totaleOrdine = (ordineId: string): number =>
  Number(eseguiSql(`select totale_acquirente_cents from private.accessori_ordini where id = '${ordineId}';`));

export const statoOrdine = (ordineId: string): string =>
  eseguiSql(`select stato from private.accessori_ordini where id = '${ordineId}';`);

export const statoPagamento = (ordineId: string): string =>
  eseguiSql(`select stato from private.accessori_pagamenti where ordine_id = '${ordineId}';`);

interface Evento {
  session_id: string;
  intent_id: string;
  provider_event_type: string;
  amount_cents: number;
  currency: string;
  order_id: string;
  dominio: string;
  amount_refunded?: number;
  refunded?: boolean;
  refunds?: Array<{ id: string; amount_cents: number; status: string; rimborso_id: string; dominio: string }>;
}

let progressivo = 0;

/** Applica un evento del fornitore simulato; restituisce l'esito della funzione (processed / duplicate / ...). */
export const applicaEvento = (
  idEvento: string,
  outcome: "pending" | "authorized" | "settled" | "failed" | "expired" | "refunded",
  oggetto: Evento,
): string =>
  eseguiSql(
    `select public.accessori_pagamento_applica_evento('stripe', '${idEvento}', '${outcome}'::public.payment_outcome,
       ${Math.floor(Date.now() / 1000)}, '${JSON.stringify(oggetto)}'::jsonb);`,
  );

/** Apre il pagamento dell'ordine e lo collega a un PaymentIntent (come fa `payments-checkout`). */
export const apriPagamento = (ordineId: string, buyerId: string, intento: string): void => {
  eseguiSql(`select public.accessori_pagamento_apri('${ordineId}', '${buyerId}');
    select public.accessori_pagamento_collega('${ordineId}', '${buyerId}', 'stripe', '${intento}');`);
};

const evento = (ordineId: string, intento: string, tipo: string, extra: Partial<Evento> = {}): Evento => ({
  session_id: intento,
  intent_id: intento,
  provider_event_type: tipo,
  amount_cents: totaleOrdine(ordineId),
  currency: "eur",
  order_id: ordineId,
  dominio: "accessori",
  ...extra,
});

/** Incasso attendibile: apre, collega e applica `payment_intent.succeeded`. L'ordine diventa pagato. */
export const pagaConEventoFirmato = (ordineId: string, buyerId: string, tag: string): string => {
  const intento = `pi_e2e_${tag}`;
  apriPagamento(ordineId, buyerId, intento);
  const esito = applicaEvento(`evt_e2e_s_${tag}`, "settled", evento(ordineId, intento, "payment_intent.succeeded"));
  if (esito !== "processed") throw new Error(`Evento di incasso non applicato: ${esito}`);
  return intento;
};

/** `charge.refunded` firmato: `rimborsato` è il cumulato; `pieno` chiude il rimborso totale. */
export const eventoRimborso = (
  ordineId: string,
  intento: string,
  idEvento: string,
  rimborsato: number,
  pieno: boolean,
  rimborso?: { id: string; rimborsoId: string; cents: number },
): string =>
  applicaEvento(
    idEvento,
    "refunded",
    evento(ordineId, intento, "charge.refunded", {
      dominio: undefined as unknown as string,
      amount_refunded: rimborsato,
      refunded: pieno,
      ...(rimborso
        ? { refunds: [{ id: rimborso.id, amount_cents: rimborso.cents, status: "succeeded", rimborso_id: rimborso.rimborsoId, dominio: "accessori" }] }
        : {}),
    }),
  );

/** Invecchia la prenotazione oltre i 15 minuti (la scrittura diretta è vietata: la guardia si sospende SOLO sullo stack di prova). */
export const invecchiaPrenotazione = (ordineId: string): void => {
  // In una transazione: se l'update fallisce, la guardia non resta sospesa.
  eseguiSql(`
    begin;
    alter table private.accessori_ordini disable trigger accessori_ordini_guard;
    update private.accessori_ordini set creato_at = now() - interval '30 minutes', scade_at = now() - interval '15 minutes'
     where id = '${ordineId}';
    alter table private.accessori_ordini enable trigger accessori_ordini_guard;
    commit;`);
};

export const etichetta = (): string => `${Date.now().toString(36)}${progressivo++}`;

/**
 * Simula il job di esecuzione dei rimborsi con un provider FINTO: il database prepara la richiesta
 * (`accessori_rimborso_prepara`, `in_invio`) e registra che il fornitore l'ha ACCETTATA
 * (`accessori_rimborso_registra_esito`). Accettato non è eseguito: lo stato finale lo scrive solo `charge.refunded`.
 */
export const simulaInvioRimborso = (rimborsoId: string, refundId: string): void => {
  eseguiSql(`select public.accessori_rimborso_prepara('${rimborsoId}');
    select public.accessori_rimborso_registra_esito('${rimborsoId}', true, '${refundId}', null);`);
};
