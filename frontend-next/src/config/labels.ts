/**
 * Label italiane centralizzate per stati di dominio.
 * Le macchine a stati canoniche vivono in src/data/{orders,moderation,onboarding}.ts;
 * qui c'è solo la traduzione display. In Next.js diventerà i18n resource.
 */

export const buyerOrderLabels: Record<string, string> = {
  in_attesa_pagamento: "In attesa di pagamento",
  pagato: "Pagato",
  in_preparazione: "In preparazione",
  spedito: "Spedito",
  consegnato: "Consegnato",
  verifica: "Periodo di verifica",
  completato: "Completato",
  contestato: "Contestato",
  rimborsato: "Rimborsato",
  annullato: "Annullato",
};

export const sellerOrderLabels: Record<string, string> = {
  nuovo: "Nuovo ordine",
  da_preparare: "Da preparare",
  da_spedire: "Da spedire",
  spedito: "Spedito",
  consegnato: "Consegnato",
  completato: "Completato",
};

export const listingStatusLabels: Record<string, string> = {
  bozza: "Bozza",
  in_revisione: "In revisione",
  modifiche_richieste: "Modifiche richieste",
  attivo: "Attivo",
  riservato: "Riservato",
  venduto: "Venduto",
  sospeso: "Sospeso",
  rifiutato: "Rifiutato",
  scaduto: "Scaduto",
};

export const reportStatusLabels: Record<string, string> = {
  inviata: "Inviata",
  in_revisione: "In revisione",
  info_richieste: "Informazioni richieste",
  risolta: "Risolta",
  respinta: "Respinta",
};

export const verificationLabels = {
  email: { non_verificata: "Email non verificata", verificata: "Email verificata" },
  eta: {
    dichiarata: "Età dichiarata",
    da_verificare: "Età da verificare",
    verificata: "Età verificata",
  },
  identita: {
    non_avviata: "Identità non avviata",
    in_verifica: "Identità in verifica",
    verificata: "Identità verificata",
    rifiutata: "Identità rifiutata",
  },
  venditore: { non_abilitato: "Venditore non abilitato", abilitato: "Venditore abilitato" },
} as const;
