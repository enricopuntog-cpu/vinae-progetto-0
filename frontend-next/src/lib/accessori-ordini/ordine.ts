/**
 * Ordini Accessori — VPM-015B5A.
 *
 * Tipi e parser delle risposte del checkout Accessori. Il browser non invia mai
 * un importo, un prezzo, una quantità autoritativa, un venditore o un costo di
 * spedizione: sceglie un preventivo congelato dal database e una chiave di
 * idempotenza; tutto il resto lo restituisce il database. Il parser è rigido:
 * una risposta incoerente (somme che non tornano al centesimo, stato sconosciuto,
 * scadenze impossibili) non è quella promessa e diventa un errore.
 *
 * Nessun pagamento reale: lo stato `pagato` esiste solo come esito simulato del
 * database e questa interfaccia non ha alcun comando per raggiungerlo.
 */

import { uuidValido } from "@/lib/accessori-vendita/annunci-accessori";

export const STATI_ORDINE_ACCESSORIO = ["in_attesa_pagamento", "pagato", "annullato", "scaduto"] as const;
export type StatoOrdineAccessorio = (typeof STATI_ORDINE_ACCESSORIO)[number];

export const MOTIVI_CHIUSURA = ["acquirente", "scadenza", "annuncio_non_disponibile"] as const;
export type MotivoChiusura = (typeof MOTIVI_CHIUSURA)[number];

export type RuoloOrdine = "acquirente" | "venditore";

export type OrdineAccessorio = {
  id: string;
  stato: StatoOrdineAccessorio;
  ruolo: RuoloOrdine;
  annuncioId: string;
  articolo: { nome: string; marchio: string | null; condizione: string };
  quantita: number;
  prezzo: { unitarioCents: number; quantita: number; subtotaleCents: number };
  /**
   * Le voci che compongono il totale dell'acquirente. La vista del venditore non
   * le riceve (né commissione, né spedizione, né totale): sono `null`.
   */
  commissioneCents: number | null;
  coperturaPagamentoCents: number | null;
  logistica: {
    trasportoCents: number;
    assicurazioneCents: number;
    totaleCents: number;
    colli: number;
    pezziPerCollo: number;
    destinazione: "punto_ritiro";
  } | null;
  totaleAcquirenteCents: number | null;
  creatoAt: string;
  scadeAt: string;
  pagatoAt: string | null;
  motivoChiusura: MotivoChiusura | null;
  pagamentoSimulato: boolean;
  /** Il nome pubblico della controparte. */
  controparte: string | null;
  /** Quanto incassa il venditore (solo la vista del venditore). */
  ricevoCents: number | null;
};

export type DisponibilitaAccessorio = {
  disponibili: number;
  prenotabile: boolean;
  motivo: string | null;
};

type Json = Record<string, unknown>;
const oggetto = (v: unknown): Json | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;
const intero = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) ? v : null;
const nonNegativo = (v: unknown): number | null => {
  const n = intero(v);
  return n !== null && n >= 0 ? n : null;
};
const data = (v: unknown): string | null =>
  typeof v === "string" && !Number.isNaN(Date.parse(v)) ? v : null;

export function parseDisponibilita(v: unknown): DisponibilitaAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const disponibili = nonNegativo(o.disponibili);
  if (disponibili === null || typeof o.prenotabile !== "boolean") return null;
  if (o.motivo !== null && o.motivo !== undefined && typeof o.motivo !== "string") return null;
  // Un annuncio senza pezzi o con il checkout chiuso non si prenota.
  if (o.prenotabile && disponibili < 1) return null;
  return { disponibili, prenotabile: o.prenotabile, motivo: typeof o.motivo === "string" ? o.motivo : null };
}

export function parseOrdineAccessorio(v: unknown): OrdineAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const articolo = oggetto(o.articolo);
  const prezzo = oggetto(o.prezzo);
  if (!articolo || !prezzo) return null;

  const stato = STATI_ORDINE_ACCESSORIO.find((s) => s === o.stato);
  const ruolo: RuoloOrdine | null = o.ruolo === "acquirente" || o.ruolo === "venditore" ? (o.ruolo as RuoloOrdine) : null;
  const quantita = intero(o.quantita);
  const unitario = nonNegativo(prezzo.unitarioCents);
  const qPrezzo = intero(prezzo.quantita);
  const subtotale = nonNegativo(prezzo.subtotaleCents);
  const creatoAt = data(o.creatoAt);
  const scadeAt = data(o.scadeAt);

  if (
    typeof o.id !== "string" || !uuidValido(o.id) ||
    typeof o.annuncioId !== "string" || !uuidValido(o.annuncioId) ||
    !stato || !ruolo || quantita === null || quantita < 1 || quantita > 120 ||
    unitario === null || unitario <= 0 || qPrezzo !== quantita || subtotale === null ||
    !creatoAt || !scadeAt ||
    typeof articolo.nome !== "string" || articolo.nome.length === 0 ||
    typeof articolo.condizione !== "string" ||
    (articolo.marchio !== null && articolo.marchio !== undefined && typeof articolo.marchio !== "string") ||
    typeof o.pagamentoSimulato !== "boolean"
  ) {
    return null;
  }
  if (subtotale !== unitario * quantita || Date.parse(scadeAt) <= Date.parse(creatoAt)) return null;

  const pagatoAt = o.pagatoAt === null || o.pagatoAt === undefined ? null : data(o.pagatoAt);
  if (o.pagatoAt !== null && o.pagatoAt !== undefined && !pagatoAt) return null;
  const motivoChiusura =
    o.motivoChiusura === null || o.motivoChiusura === undefined
      ? null
      : (MOTIVI_CHIUSURA.find((m) => m === o.motivoChiusura) ?? null);
  if (o.motivoChiusura !== null && o.motivoChiusura !== undefined && !motivoChiusura) return null;
  // Coerenza dello stato: pagato ⇔ data di pagamento; annullato/scaduto ⇔ motivo.
  // Uno `scaduto` derivato dalla sola scadenza (non ancora chiuso) non ha motivo.
  if ((stato === "pagato") !== (pagatoAt !== null)) return null;
  if (stato === "annullato" && !motivoChiusura) return null;
  if ((stato === "in_attesa_pagamento" || stato === "pagato") && motivoChiusura) return null;
  // `pagamentoSimulato` vale solo per un ordine pagato: pagato dal fornitore (webhook firmato)
  // è `pagato` con `pagamentoSimulato=false`; un ordine non pagato non ha alcun modo di pagamento.
  if (o.pagamentoSimulato && stato !== "pagato") return null;

  const base = {
    id: o.id,
    stato,
    ruolo,
    annuncioId: o.annuncioId,
    articolo: {
      nome: articolo.nome,
      marchio: typeof articolo.marchio === "string" ? articolo.marchio : null,
      condizione: articolo.condizione,
    },
    quantita,
    prezzo: { unitarioCents: unitario, quantita: qPrezzo, subtotaleCents: subtotale },
    creatoAt,
    scadeAt,
    pagatoAt,
    motivoChiusura,
    pagamentoSimulato: o.pagamentoSimulato,
  };

  if (ruolo === "venditore") {
    // Il venditore vede quanto incassa; le voci dell'acquirente non gli arrivano
    // e un'eventuale presenza è una risposta che non è quella promessa.
    const ricevi = oggetto(o.ricevi);
    const acquirente = oggetto(o.acquirente);
    if (
      o.venditore !== undefined || o.commissione !== undefined || o.pagamento !== undefined ||
      o.logistica !== undefined || o.totaleAcquirenteCents !== undefined ||
      !ricevi || nonNegativo(ricevi.cents) !== subtotale ||
      // L'acquirente è noto al venditore solo a vendita avvenuta.
      (acquirente !== null) !== (stato === "pagato") ||
      (acquirente !== null && typeof acquirente.username !== "string")
    ) {
      return null;
    }
    return {
      ...base,
      commissioneCents: null,
      coperturaPagamentoCents: null,
      logistica: null,
      totaleAcquirenteCents: null,
      controparte: acquirente && typeof acquirente.username === "string" ? acquirente.username : null,
      ricevoCents: subtotale,
    };
  }

  const commissione = oggetto(o.commissione);
  const pagamento = oggetto(o.pagamento);
  const logistica = oggetto(o.logistica);
  const venditore = oggetto(o.venditore);
  if (!commissione || !pagamento || !logistica || o.acquirente !== undefined || o.ricevi !== undefined) return null;
  const comm = nonNegativo(commissione.cents);
  const copertura = nonNegativo(pagamento.coperturaSuLogisticaCents);
  const trasporto = nonNegativo(logistica.trasportoCents);
  const assicurazione = nonNegativo(logistica.assicurazioneCents);
  const totaleLogistica = nonNegativo(logistica.totaleCents);
  const colli = intero(logistica.colli);
  const pezziPerCollo = intero(logistica.pezziPerCollo);
  const totale = nonNegativo(o.totaleAcquirenteCents);
  if (
    comm === null || copertura === null || trasporto === null || assicurazione === null ||
    totaleLogistica === null || colli === null || colli < 1 || pezziPerCollo === null || pezziPerCollo < 1 ||
    totale === null || logistica.destinazione !== "punto_ritiro"
  ) {
    return null;
  }
  // Le somme devono tornare al centesimo: prezzo, commissione, pagamento e
  // logistica sono voci separate e il totale è la loro somma.
  if (totaleLogistica !== trasporto + assicurazione || totale !== subtotale + comm + copertura + totaleLogistica) {
    return null;
  }
  return {
    ...base,
    commissioneCents: comm,
    coperturaPagamentoCents: copertura,
    logistica: {
      trasportoCents: trasporto,
      assicurazioneCents: assicurazione,
      totaleCents: totaleLogistica,
      colli,
      pezziPerCollo,
      destinazione: "punto_ritiro",
    },
    totaleAcquirenteCents: totale,
    controparte: venditore && typeof venditore.username === "string" ? venditore.username : null,
    ricevoCents: null,
  };
}

export function parseElencoOrdini(v: unknown): OrdineAccessorio[] | null {
  if (!Array.isArray(v) || v.length > 60) return null;
  const ordini: OrdineAccessorio[] = [];
  for (const voce of v) {
    const o = parseOrdineAccessorio(voce);
    if (!o) return null;
    ordini.push(o);
  }
  return ordini;
}

/** Chiave di idempotenza di un gesto: la stessa per ogni ripetizione dello stesso click. */
export const chiaveIdempotenzaValida = (c: string): boolean => /^[A-Za-z0-9._:-]{8,128}$/.test(c);

/** Perché una richiesta è stata rifiutata, in parole. Mai un dettaglio tecnico. */
export const MESSAGGI_ORDINI_ACCESSORI: Readonly<Record<string, string>> = {
  checkout_non_attivo: "Le prenotazioni degli Accessori non sono ancora attive.",
  annuncio_non_disponibile: "Questo annuncio non è più disponibile.",
  quantita_non_disponibile: "Non ci sono abbastanza pezzi disponibili: riduci la quantità.",
  troppe_prenotazioni: "Hai già troppe prenotazioni aperte: completane o annullane una.",
  preventivo_incoerente: "Il riepilogo non è valido: preparane uno nuovo.",
  richiesta_non_valida: "Richiesta non valida. Riprova.",
  dati_non_validi: "Richiesta non valida. Riprova.",
  prenotazione_aperta: "Hai già una prenotazione aperta per questo annuncio: completala o annullala.",
  proprio_annuncio: "Non puoi prenotare il tuo annuncio.",
  venditore_non_ammesso: "Il venditore non può vendere in questo momento.",
  account_non_attivo: "Il tuo account non può prenotare in questo momento.",
  preventivo_non_trovato: "Il riepilogo non è più valido: preparane uno nuovo.",
  preventivo_scaduto: "Il riepilogo è scaduto: preparane uno nuovo.",
  preventivo_consumato: "Questo riepilogo è già stato usato.",
  preventivo_annuncio_cambiato: "L'annuncio è cambiato: preparane un nuovo riepilogo.",
  preventivo_non_disponibile: "La spedizione non è più disponibile: preparane un nuovo riepilogo.",
  preventivo_quantita_non_disponibile: "Non ci sono abbastanza pezzi disponibili: riduci la quantità.",
  chiave_riusata: "Richiesta non valida. Riprova.",
  ordine_pagato: "Un ordine pagato non si annulla da qui.",
  pagamento_in_corso: "Il pagamento è in corso: attendi l'esito prima di annullare.",
  non_trovato: "Ordine non trovato.",
};

export const messaggioOrdineAccessori = (hint: string): string | null => MESSAGGI_ORDINI_ACCESSORI[hint] ?? null;

/** Lo stato in parole; un ordine pagato distingue la prova (simulata) dal pagamento del fornitore. */
export const testoStatoOrdine = (o: Pick<OrdineAccessorio, "stato" | "pagamentoSimulato">): string =>
  o.stato === "pagato" ? (o.pagamentoSimulato ? "Pagato (simulato)" : "Pagamento confermato") : TESTI_STATO_ORDINE[o.stato];

export const TESTI_STATO_ORDINE: Readonly<Record<StatoOrdineAccessorio, string>> = {
  in_attesa_pagamento: "Prenotato, in attesa di pagamento",
  pagato: "Pagato (simulato)",
  annullato: "Annullato",
  scaduto: "Scaduto",
};

export const MESSAGGI_CHIUSURA: Readonly<Record<MotivoChiusura, string>> = {
  acquirente: "Hai annullato la prenotazione.",
  scadenza: "La prenotazione è scaduta: i pezzi sono tornati disponibili.",
  annuncio_non_disponibile: "L'annuncio non è più disponibile: la prenotazione è stata annullata.",
};

/** Testi della prenotazione. */
export const TESTI_ORDINI_ACCESSORI = {
  titolo: "Prenotazione",
  introduzione:
    "Scegli quanti pezzi: il riepilogo con spedizione al punto di ritiro lo calcola Vinea. Confermando prenoti i pezzi per alcuni minuti.",
  nessunAddebito:
    "La sola prenotazione non addebita denaro: tiene da parte i pezzi finché non scade o la annulli. L'addebito avviene solo se confermi il pagamento, quando sarà attivo.",
  chiuso: "Gli acquisti non sono ancora disponibili.",
  esaurito: "Questo annuncio è esaurito: non ci sono più pezzi da prenotare.",
  nonRaggiungibile: "La prenotazione non è disponibile in questo momento.",
  accedi: "Accedi per prenotare",
  tuttiGliOrdini: "I miei ordini Accessori",
} as const;
