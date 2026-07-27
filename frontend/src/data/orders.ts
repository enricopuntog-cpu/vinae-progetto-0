import type { Wine } from "./wines";
import { wines } from "./wines";

export type BuyerOrderStatus =
  | "in_attesa_pagamento"
  | "pagato"
  | "in_preparazione"
  | "spedito"
  | "consegnato"
  | "verifica"
  | "completato"
  | "contestato"
  | "rimborsato"
  | "annullato";

export type SellerOrderStatus =
  | "nuovo"
  | "da_preparare"
  | "da_spedire"
  | "spedito"
  | "consegnato"
  | "completato"
  | "contestato"
  | "rimborsato"
  | "annullato";

export type DeliveryMode = "spedizione" | "consegna_mano";
export type PaymentMethod = "stripe_real" | "carta_demo" | "paypal_demo" | "bonifico_demo";

export type TrackingEvent = {
  id: string;
  ts: string;
  titolo: string;
  descrizione?: string;
  luogo?: string;
  tipo: "info" | "spedizione" | "consegna" | "problema" | "sistema";
};

export type Dispute = {
  motivo: string;
  descrizione: string;
  foto: string[];
  stato: "aperta" | "in_valutazione" | "rimborsata" | "risolta" | "respinta";
  aperturaTs: string;
  chiusuraTs?: string;
  esito?: string;
};

export type OrderReview = {
  voto: number;
  conformita: number;
  imballaggio: number;
  comunicazione: number;
  testo: string;
  ts: string;
};

export type Order = {
  id: string;
  wineId: string;
  quantita: number;
  prezzoUnitario: number;
  spedizione: number;
  protezione: number;
  totale: number;
  deliveryMode: DeliveryMode;
  indirizzo: {
    nome: string;
    via: string;
    cap: string;
    citta: string;
    provincia: string;
  };
  metodoPagamento: PaymentMethod;
  cartaMascherata?: string;
  buyer: { nome: string; avatar: string };
  seller: { nome: string; avatar: string; verificato: boolean };
  buyerStatus: BuyerOrderStatus;
  sellerStatus: SellerOrderStatus;
  createdAt: string;
  paidAt?: string;
  shippedAt?: string;
  deliveredAt?: string;
  completedAt?: string;
  tracking: TrackingEvent[];
  trackingNumber?: string;
  courier?: string;
  packagingChecklist?: { id: string; label: string; done: boolean }[];
  packagingPhotos?: string[];
  dispute?: Dispute;
  review?: OrderReview;
  fromProposalId?: string;
};

export type ProposalStatus =
  "inviata" | "controproposta" | "accettata" | "rifiutata" | "scaduta" | "convertita";

export type Proposal = {
  id: string;
  wineId: string;
  prezzoRichiesto: number;
  prezzoProposto: number;
  controProposta?: number;
  stato: ProposalStatus;
  createdAt: string;
  scadenza: string;
  buyer: { nome: string; avatar: string };
  seller: { nome: string; avatar: string };
  orderId?: string;
};

export const indirizzoDemo = {
  nome: "Elena Rossi",
  via: "Via del Vigneto, 12",
  cap: "20121",
  citta: "Milano",
  provincia: "MI",
};

export const carteDemo: ReadonlyArray<{
  id: Exclude<PaymentMethod, "stripe_real">;
  label: string;
  brand: "visa" | "paypal" | "bonifico";
}> = [
  { id: "carta_demo", label: "Visa •••• 4242", brand: "visa" as const },
  { id: "paypal_demo", label: "PayPal — elena@demo.it", brand: "paypal" as const },
  { id: "bonifico_demo", label: "Bonifico bancario (demo)", brand: "bonifico" as const },
];

export function calcolaSpedizione(mode: DeliveryMode, prezzo: number): number {
  if (mode === "consegna_mano") return 0;
  if (prezzo >= 500) return 0;
  return 12;
}

export function calcolaProtezione(prezzo: number): number {
  return Math.round(prezzo * 0.03);
}

export function tempiConsegna(mode: DeliveryMode): string {
  return mode === "consegna_mano" ? "Da concordare con il venditore" : "2–4 giorni lavorativi";
}

function w(id: string): Wine {
  const found = wines.find((x) => x.id === id);
  if (!found) throw new Error(`Wine ${id} not found`);
  return found;
}

function todayMinus(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString();
}

const sassicaia = w("sassicaia-2018");
const tignanello = w("tignanello-2019");
const dom = w("dom-perignon-2013");

export const ordersSeed: Order[] = [
  {
    id: "ORD-2026-0042",
    wineId: sassicaia.id,
    quantita: 1,
    prezzoUnitario: sassicaia.prezzo,
    spedizione: 12,
    protezione: calcolaProtezione(sassicaia.prezzo),
    totale: sassicaia.prezzo + 12 + calcolaProtezione(sassicaia.prezzo),
    deliveryMode: "spedizione",
    indirizzo: indirizzoDemo,
    metodoPagamento: "carta_demo",
    cartaMascherata: "Visa •••• 4242",
    buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
    seller: {
      nome: sassicaia.venditore.nome,
      avatar: sassicaia.venditore.avatar,
      verificato: sassicaia.venditore.verificato,
    },
    buyerStatus: "consegnato",
    sellerStatus: "consegnato",
    createdAt: todayMinus(6),
    paidAt: todayMinus(6),
    shippedAt: todayMinus(4),
    deliveredAt: todayMinus(1),
    trackingNumber: "VNA-4421-773",
    courier: "Corriere Vinea",
    tracking: [
      { id: "t1", ts: todayMinus(6), titolo: "Ordine ricevuto", tipo: "sistema" },
      {
        id: "t2",
        ts: todayMinus(6),
        titolo: "Pagamento confermato",
        descrizione: "Simulazione demo",
        tipo: "sistema",
      },
      { id: "t3", ts: todayMinus(5), titolo: "In preparazione dal venditore", tipo: "info" },
      {
        id: "t4",
        ts: todayMinus(4),
        titolo: "Spedito",
        descrizione: "Corriere Vinea — VNA-4421-773",
        tipo: "spedizione",
      },
      { id: "t5", ts: todayMinus(3), titolo: "In transito", luogo: "Firenze", tipo: "spedizione" },
      { id: "t6", ts: todayMinus(2), titolo: "In consegna", luogo: "Milano", tipo: "spedizione" },
      {
        id: "t7",
        ts: todayMinus(1),
        titolo: "Consegnato",
        descrizione: "Firmato da E. Rossi",
        tipo: "consegna",
      },
    ],
  },
  {
    id: "ORD-2026-0038",
    wineId: tignanello.id,
    quantita: 2,
    prezzoUnitario: tignanello.prezzo,
    spedizione: 0,
    protezione: calcolaProtezione(tignanello.prezzo * 2),
    totale: tignanello.prezzo * 2 + calcolaProtezione(tignanello.prezzo * 2),
    deliveryMode: "spedizione",
    indirizzo: indirizzoDemo,
    metodoPagamento: "paypal_demo",
    cartaMascherata: "PayPal — elena@demo.it",
    buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
    seller: {
      nome: tignanello.venditore.nome,
      avatar: tignanello.venditore.avatar,
      verificato: tignanello.venditore.verificato,
    },
    buyerStatus: "spedito",
    sellerStatus: "spedito",
    createdAt: todayMinus(3),
    paidAt: todayMinus(3),
    shippedAt: todayMinus(1),
    trackingNumber: "VNA-8891-002",
    courier: "Corriere Vinea",
    tracking: [
      { id: "t1", ts: todayMinus(3), titolo: "Ordine ricevuto", tipo: "sistema" },
      { id: "t2", ts: todayMinus(3), titolo: "Pagamento confermato", tipo: "sistema" },
      { id: "t3", ts: todayMinus(2), titolo: "In preparazione", tipo: "info" },
      {
        id: "t4",
        ts: todayMinus(1),
        titolo: "Spedito",
        descrizione: "Corriere Vinea — VNA-8891-002",
        tipo: "spedizione",
      },
    ],
  },
  {
    id: "ORD-2026-0031",
    wineId: dom.id,
    quantita: 1,
    prezzoUnitario: dom.prezzo,
    spedizione: 12,
    protezione: calcolaProtezione(dom.prezzo),
    totale: dom.prezzo + 12 + calcolaProtezione(dom.prezzo),
    deliveryMode: "spedizione",
    indirizzo: indirizzoDemo,
    metodoPagamento: "carta_demo",
    cartaMascherata: "Visa •••• 4242",
    buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
    seller: {
      nome: dom.venditore.nome,
      avatar: dom.venditore.avatar,
      verificato: dom.venditore.verificato,
    },
    buyerStatus: "completato",
    sellerStatus: "completato",
    createdAt: todayMinus(30),
    paidAt: todayMinus(30),
    shippedAt: todayMinus(28),
    deliveredAt: todayMinus(25),
    completedAt: todayMinus(18),
    trackingNumber: "VNA-1122-988",
    courier: "Corriere Vinea",
    tracking: [
      { id: "t1", ts: todayMinus(30), titolo: "Ordine ricevuto", tipo: "sistema" },
      { id: "t2", ts: todayMinus(30), titolo: "Pagamento confermato", tipo: "sistema" },
      { id: "t3", ts: todayMinus(28), titolo: "Spedito", tipo: "spedizione" },
      { id: "t4", ts: todayMinus(25), titolo: "Consegnato", tipo: "consegna" },
      { id: "t5", ts: todayMinus(18), titolo: "Ordine completato", tipo: "sistema" },
    ],
    review: {
      voto: 5,
      conformita: 5,
      imballaggio: 5,
      comunicazione: 5,
      testo: "Bottiglia impeccabile, imballaggio perfetto. Comunicazione rapida.",
      ts: todayMinus(18),
    },
  },
];

// Vendite lato venditore (Elena come venditrice)
export const salesSeed: Order[] = [
  {
    id: "ORD-2026-0051",
    wineId: w("ornellaia-2017").id,
    quantita: 1,
    prezzoUnitario: w("ornellaia-2017").prezzo,
    spedizione: 12,
    protezione: calcolaProtezione(w("ornellaia-2017").prezzo),
    totale: w("ornellaia-2017").prezzo + 12 + calcolaProtezione(w("ornellaia-2017").prezzo),
    deliveryMode: "spedizione",
    indirizzo: {
      nome: "Andrea C.",
      via: "Corso Vittorio, 88",
      cap: "10121",
      citta: "Torino",
      provincia: "TO",
    },
    metodoPagamento: "carta_demo",
    cartaMascherata: "Visa •••• 1111",
    buyer: { nome: "Andrea C.", avatar: "https://i.pravatar.cc/120?img=15" },
    seller: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68", verificato: true },
    buyerStatus: "pagato",
    sellerStatus: "da_preparare",
    createdAt: todayMinus(1),
    paidAt: todayMinus(1),
    tracking: [
      { id: "t1", ts: todayMinus(1), titolo: "Nuovo ordine ricevuto", tipo: "sistema" },
      { id: "t2", ts: todayMinus(1), titolo: "Pagamento confermato", tipo: "sistema" },
    ],
  },
  {
    id: "ORD-2026-0047",
    wineId: w("biondi-santi-2016").id,
    quantita: 1,
    prezzoUnitario: w("biondi-santi-2016").prezzo,
    spedizione: 0,
    protezione: calcolaProtezione(w("biondi-santi-2016").prezzo),
    totale: w("biondi-santi-2016").prezzo + calcolaProtezione(w("biondi-santi-2016").prezzo),
    deliveryMode: "spedizione",
    indirizzo: {
      nome: "Sofia R.",
      via: "Via Ghibellina, 21",
      cap: "50122",
      citta: "Firenze",
      provincia: "FI",
    },
    metodoPagamento: "paypal_demo",
    cartaMascherata: "PayPal — sofia@demo.it",
    buyer: { nome: "Sofia R.", avatar: "https://i.pravatar.cc/120?img=47" },
    seller: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68", verificato: true },
    buyerStatus: "spedito",
    sellerStatus: "spedito",
    createdAt: todayMinus(5),
    paidAt: todayMinus(5),
    shippedAt: todayMinus(2),
    trackingNumber: "VNA-7712-441",
    courier: "Corriere Vinea",
    tracking: [
      { id: "t1", ts: todayMinus(5), titolo: "Nuovo ordine", tipo: "sistema" },
      { id: "t2", ts: todayMinus(5), titolo: "Pagamento confermato", tipo: "sistema" },
      { id: "t3", ts: todayMinus(3), titolo: "In preparazione", tipo: "info" },
      {
        id: "t4",
        ts: todayMinus(2),
        titolo: "Spedito",
        descrizione: "Corriere Vinea — VNA-7712-441",
        tipo: "spedizione",
      },
    ],
  },
];

export const proposalsSeed: Proposal[] = [
  {
    id: "PRP-2026-0012",
    wineId: "monfortino-2015",
    prezzoRichiesto: 1180,
    prezzoProposto: 980,
    controProposta: 1080,
    stato: "controproposta",
    createdAt: todayMinus(2),
    scadenza: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(),
    buyer: { nome: "Elena Rossi", avatar: "https://i.pravatar.cc/120?img=68" },
    seller: { nome: "Marco B.", avatar: "https://i.pravatar.cc/120?img=13" },
  },
];

export function labelBuyerStatus(s: BuyerOrderStatus): string {
  return {
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
  }[s];
}

export function labelSellerStatus(s: SellerOrderStatus): string {
  return {
    nuovo: "Nuovo ordine",
    da_preparare: "Da preparare",
    da_spedire: "Da spedire",
    spedito: "Spedito",
    consegnato: "Consegnato",
    completato: "Completato",
    contestato: "Contestato",
    rimborsato: "Rimborsato",
    annullato: "Annullato",
  }[s];
}

export function colorBuyerStatus(s: BuyerOrderStatus): string {
  switch (s) {
    case "in_attesa_pagamento":
      return "bg-oro/15 text-oro";
    case "pagato":
    case "in_preparazione":
      return "bg-secondary text-antracite";
    case "spedito":
      return "bg-blue-500/10 text-blue-700";
    case "consegnato":
    case "verifica":
      return "bg-salvia/15 text-salvia";
    case "completato":
      return "bg-bordeaux/10 text-bordeaux";
    case "contestato":
      return "bg-red-500/10 text-red-700";
    case "rimborsato":
      return "bg-oro/20 text-oro";
    case "annullato":
      return "bg-muted text-muted-foreground";
  }
}
