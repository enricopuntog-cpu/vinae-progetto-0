/** Ordine di prova per i test (VPM-015B5A): dati sintetici, nessun importo reale. */
export const ID_ORDINE_PROVA = "12f50000-0000-4000-8000-0000000000a1";
export const ID_ANNUNCIO_PROVA = "12f50000-0000-4000-8000-0000000000a2";

export const ordineValido = (extra: Record<string, unknown> = {}) => ({
  id: ID_ORDINE_PROVA,
  stato: "in_attesa_pagamento",
  annuncioId: ID_ANNUNCIO_PROVA,
  ruolo: "acquirente",
  articolo: { nome: "Calice B5A", marchio: null, condizione: "usato" },
  quantita: 2,
  prezzo: { unitarioCents: 2000, quantita: 2, subtotaleCents: 4000 },
  commissione: { cents: 480 },
  pagamento: { coperturaSuLogisticaCents: 25 },
  logistica: {
    trasportoCents: 1180,
    assicurazioneCents: 0,
    totaleCents: 1180,
    colli: 2,
    pezziPerCollo: 1,
    destinazione: "punto_ritiro",
  },
  totaleAcquirenteCents: 4000 + 480 + 25 + 1180,
  valuta: "eur",
  creatoAt: "2026-11-02T10:00:00Z",
  scadeAt: "2026-11-02T10:15:00Z",
  pagatoAt: null,
  motivoChiusura: null,
  pagamentoSimulato: false,
  venditore: { username: "ua" },
  ...extra,
});


/** La stessa vendita come la riceve il venditore: solo ciò che incassa, senza le voci dell'acquirente. */
export const ordineVenditore = (extra: Record<string, unknown> = {}) => {
  const resto: Record<string, unknown> = { ...ordineValido() };
  for (const k of ["venditore", "commissione", "pagamento", "logistica", "totaleAcquirenteCents", "valuta"]) delete resto[k];
  return { ...resto, ruolo: "venditore", ricevi: { cents: 4000 }, ...extra };
};
