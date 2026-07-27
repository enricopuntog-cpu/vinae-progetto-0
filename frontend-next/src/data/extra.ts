import { wines } from "./wines";

export type Notifica = {
  id: string;
  categoria: "marketplace" | "community" | "sistema";
  testo: string;
  tempo: string;
  letta: boolean;
};

export const notificheComplete: Notifica[] = [
  {
    id: "n1",
    categoria: "marketplace",
    testo: "Marco B. ha accettato la tua proposta per Barolo Monfortino 2015",
    tempo: "5 min fa",
    letta: false,
  },
  {
    id: "n2",
    categoria: "community",
    testo: "Sofia R. ha commentato la tua nota di degustazione su Sassicaia",
    tempo: "30 min fa",
    letta: false,
  },
  {
    id: "n3",
    categoria: "marketplace",
    testo: "Prezzo ribassato: Tignanello 2019 ora a 135 €",
    tempo: "3 ore fa",
    letta: false,
  },
  {
    id: "n4",
    categoria: "community",
    testo: "Chiara V. ha iniziato a seguirti",
    tempo: "6 ore fa",
    letta: true,
  },
  {
    id: "n5",
    categoria: "sistema",
    testo: "La tua verifica identità è stata approvata",
    tempo: "ieri",
    letta: true,
  },
  {
    id: "n6",
    categoria: "marketplace",
    testo: "Nuovo annuncio dal produttore che segui: Ornellaia 2019",
    tempo: "ieri",
    letta: false,
  },
  {
    id: "n7",
    categoria: "community",
    testo: "Nuova discussione in Barolo & Barbaresco: 'Cannubi vs Brunate'",
    tempo: "2 giorni fa",
    letta: true,
  },
  {
    id: "n8",
    categoria: "sistema",
    testo: "Aggiornati i termini del marketplace Vinea",
    tempo: "3 giorni fa",
    letta: true,
  },
];

export type Seller = {
  username: string;
  nome: string;
  bio: string;
  provincia: string;
  verificato: boolean;
  avatar: string;
  membroDal: string;
  follower: number;
  vendite: number;
  acquisti: number;
  tempoRisposta: string;
  rating: number;
  valutazioni: number;
  communities: string[];
};

export const sellers: Seller[] = [
  {
    username: "marco-b",
    nome: "Marco B.",
    bio: "Appassionato di Nebbiolo di Langa. Piccola cantina di famiglia ad Alba.",
    provincia: "Alba (CN)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=13",
    membroDal: "2023",
    follower: 412,
    vendite: 127,
    acquisti: 84,
    tempoRisposta: "< 2h",
    rating: 4.9,
    valutazioni: 127,
    communities: ["barolo-barbaresco", "grandi-formati"],
  },
  {
    username: "sofia-r",
    nome: "Sofia R.",
    bio: "Bolgheri nel cuore. Custodisco piccole verticali toscane.",
    provincia: "Firenze (FI)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=47",
    membroDal: "2024",
    follower: 208,
    vendite: 42,
    acquisti: 60,
    tempoRisposta: "< 4h",
    rating: 5.0,
    valutazioni: 42,
    communities: ["brunello", "amarone"],
  },
  {
    username: "chiara-v",
    nome: "Chiara V.",
    bio: "Bollicine sempre in tavola. Champagne récoltant è passione vera.",
    provincia: "Roma (RM)",
    verificato: false,
    avatar: "https://i.pravatar.cc/240?img=25",
    membroDal: "2024",
    follower: 156,
    vendite: 89,
    acquisti: 40,
    tempoRisposta: "< 6h",
    rating: 4.7,
    valutazioni: 89,
    communities: ["champagne"],
  },
  {
    username: "enrico-m",
    nome: "Enrico M.",
    bio: "Verticali di Bolgheri e Borgogna. Collezionista dal 2005.",
    provincia: "Bologna (BO)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=11",
    membroDal: "2022",
    follower: 890,
    vendite: 214,
    acquisti: 170,
    tempoRisposta: "< 1h",
    rating: 4.95,
    valutazioni: 214,
    communities: ["borgogna", "grandi-formati"],
  },
  {
    username: "giulia-t",
    nome: "Giulia T.",
    bio: "Montalcino di famiglia. Il Brunello è la mia religione laica.",
    provincia: "Siena (SI)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=44",
    membroDal: "2023",
    follower: 320,
    vendite: 58,
    acquisti: 45,
    tempoRisposta: "< 3h",
    rating: 4.9,
    valutazioni: 58,
    communities: ["brunello"],
  },
  {
    username: "andrea-c",
    nome: "Andrea C.",
    bio: "Barolo cult. Piccole allocazioni dai grandi produttori langaroli.",
    provincia: "Torino (TO)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=15",
    membroDal: "2023",
    follower: 245,
    vendite: 31,
    acquisti: 72,
    tempoRisposta: "< 2h",
    rating: 5.0,
    valutazioni: 31,
    communities: ["barolo-barbaserco"],
  },
  {
    username: "federica-l",
    nome: "Federica L.",
    bio: "Franciacorta e vini artigianali. Riserva di famiglia in Franciacorta.",
    provincia: "Brescia (BS)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=32",
    membroDal: "2024",
    follower: 178,
    vendite: 76,
    acquisti: 33,
    tempoRisposta: "< 4h",
    rating: 4.85,
    valutazioni: 76,
    communities: ["vini-naturali"],
  },
  {
    username: "luca-p",
    nome: "Luca P.",
    bio: "Regali aziendali che diventano collezione. Milano.",
    provincia: "Milano (MI)",
    verificato: true,
    avatar: "https://i.pravatar.cc/240?img=33",
    membroDal: "2024",
    follower: 92,
    vendite: 63,
    acquisti: 44,
    tempoRisposta: "< 5h",
    rating: 4.8,
    valutazioni: 63,
    communities: ["grandi-formati"],
  },
];

export function sellerByNome(nome: string) {
  return sellers.find((s) => s.nome === nome);
}
export function sellerByUsername(u: string) {
  return sellers.find((s) => s.username === u);
}
export function annunciDelVenditore(nome: string) {
  return wines.filter((w) => w.venditore.nome === nome);
}

export const adminKpi = {
  utenti: 12480,
  annunciAttivi: 1867,
  segnalazioniAperte: 14,
  inRevisione: 23,
  communityAttive: 42,
};

export type Segnalazione = {
  id: string;
  tipo: "Annuncio sospetto" | "Utente scorretto" | "Contenuto inappropriato" | "Frode sospetta";
  oggetto: string;
  segnalante: string;
  segnalato: string;
  data: string;
  stato: "In attesa" | "In revisione" | "Chiusa";
  gravita: "bassa" | "media" | "alta";
};

export const segnalazioni: Segnalazione[] = [
  {
    id: "s1",
    tipo: "Annuncio sospetto",
    oggetto: "Dom Pérignon 2005 a 60 € — foto generiche",
    segnalante: "Chiara V.",
    segnalato: "vino_flash_87",
    data: "24 lug",
    stato: "In attesa",
    gravita: "alta",
  },
  {
    id: "s2",
    tipo: "Contenuto inappropriato",
    oggetto: "Post con insulti nella community Brunello",
    segnalante: "Giulia T.",
    segnalato: "topbrunello_99",
    data: "24 lug",
    stato: "In revisione",
    gravita: "media",
  },
  {
    id: "s3",
    tipo: "Utente scorretto",
    oggetto: "Non risponde dopo proposta accettata",
    segnalante: "Luca P.",
    segnalato: "collector_rm",
    data: "23 lug",
    stato: "In attesa",
    gravita: "media",
  },
  {
    id: "s4",
    tipo: "Frode sospetta",
    oggetto: "Livelli fotografati alterati (Sassicaia 1998)",
    segnalante: "Marco B.",
    segnalato: "old_wines_it",
    data: "22 lug",
    stato: "In attesa",
    gravita: "alta",
  },
  {
    id: "s5",
    tipo: "Annuncio sospetto",
    oggetto: "Barolo Monfortino 2015 duplicato",
    segnalante: "Sistema",
    segnalato: "cantina_alba",
    data: "22 lug",
    stato: "In revisione",
    gravita: "bassa",
  },
];

export type SystemMessage = { me: boolean; sistema?: boolean; t: string; ora: string };

export const systemThreadDemo: SystemMessage[] = [
  { me: true, t: "Ciao! Sarei interessato al Monfortino, valuti proposte?", ora: "14:20" },
  { me: false, t: "Ciao, certo. Che cifra proponi?", ora: "14:22" },
  { sistema: true, me: false, t: "Hai inviato una proposta di 180 €", ora: "14:23" },
  { me: false, t: "180 mi sembra bassa, il mercato è oltre i 1.100 €.", ora: "14:25" },
  {
    sistema: true,
    me: false,
    t: "Il venditore ha inviato una controproposta di 195 €",
    ora: "14:28",
  },
  { me: true, t: "Va bene, accetto.", ora: "14:31" },
  { sistema: true, me: false, t: "La proposta è stata accettata", ora: "14:32" },
];
