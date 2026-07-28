export type Wine = {
  id: string;
  /**
   * Slug del vino di catalogo, distinto da `id`.
   *
   * Divergenza dichiarata rispetto a frontend/src/data/wines.ts, introdotta in
   * Fase 6a. Nei dati mock un oggetto `Wine` è insieme il vino e il suo
   * annuncio, quindi un solo id basta. Sullo schema reale sono due tabelle:
   * `id` identifica l'annuncio (ed è ciò che finisce in /annuncio/<id>),
   * mentre questo campo identifica il vino — la chiave con cui DrinkWindow e
   * FoodPairing ritrovano i propri metadati in src/data/cellar.ts. Due annunci
   * dello stesso vino hanno `id` diversi e lo stesso `wineSlug`.
   *
   * Assente sui dati mock, dove `id` fa entrambi i lavori: chi legge deve
   * usare `wineSlug ?? id`.
   */
  wineSlug?: string;
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  denominazione: string;
  tipo: "Rosso" | "Bianco" | "Bollicine" | "Rosato" | "Dolce";
  formato: string;
  prezzo: number;
  prezzoMercato?: number;
  condizione: "Perfetto" | "Ottimo" | "Buono";
  conservazione: string;
  venditore: {
    nome: string;
    citta: string;
    rating: number;
    valutazioni: number;
    verificato: boolean;
    avatar: string;
  };
  immagini: string[];
  storia: string;
  degustazione: string;
  disponibili: number;
  tag: string[];
  createdAt: string;
};

import { wineImg as img } from "@/lib/wine-images";

export const wines: Wine[] = [
  {
    id: "monfortino-2015",
    produttore: "Giacomo Conterno",
    nome: "Barolo Riserva Monfortino",
    annata: 2015,
    regione: "Piemonte",
    denominazione: "Barolo DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 1180,
    prezzoMercato: 1350,
    condizione: "Perfetto",
    conservazione: "Cantina climatizzata 14°C, 70% umidità",
    venditore: {
      nome: "Marco B.",
      citta: "Alba (CN)",
      rating: 4.9,
      valutazioni: 127,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=13",
    },
    immagini: [
      img("photo-1553361371-9b22f78e8b1d"),
      img("photo-1568213816046-0ee1c42bd559"),
      img("photo-1547595628-c61a29f496f0"),
    ],
    storia:
      "Acquistato in fine origine dal produttore nel 2019. Custodito in cantina privata climatizzata, mai spostato. Livello nel collo, capsula integra.",
    degustazione:
      "Naso profondo di rosa appassita, catrame e liquirizia. Tannino ancora vibrante, chiusura salina e lunghissima.",
    disponibili: 2,
    tag: ["Investimento", "Collezione", "Nebbiolo"],
    createdAt: "2026-07-14",
  },
  {
    id: "sassicaia-2018",
    produttore: "Tenuta San Guido",
    nome: "Sassicaia",
    annata: 2018,
    regione: "Toscana",
    denominazione: "Bolgheri Sassicaia DOC",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 260,
    prezzoMercato: 295,
    condizione: "Perfetto",
    conservazione: "Cantina interrata a temperatura costante",
    venditore: {
      nome: "Sofia R.",
      citta: "Firenze",
      rating: 5.0,
      valutazioni: 42,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=47",
    },
    immagini: [img("photo-1510812431401-41d2bd2722f3"), img("photo-1506377247377-2a5b3b417ebb")],
    storia:
      "Bottiglia della collezione personale di mio padre, appassionato di Bolgheri dagli anni '90. Documentazione d'acquisto disponibile.",
    degustazione: "Cassis, grafite, macchia mediterranea. Eleganza cabernet in purezza.",
    disponibili: 6,
    tag: ["Bolgheri", "Cabernet", "Super Tuscan"],
    createdAt: "2026-07-18",
  },
  {
    id: "tignanello-2019",
    produttore: "Antinori",
    nome: "Tignanello",
    annata: 2019,
    regione: "Toscana",
    denominazione: "Toscana IGT",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 135,
    prezzoMercato: 150,
    condizione: "Ottimo",
    conservazione: "Armadio-cantina a 15°C",
    venditore: {
      nome: "Luca P.",
      citta: "Milano",
      rating: 4.8,
      valutazioni: 63,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=33",
    },
    immagini: [img("photo-1524593166156-312f362cada0"), img("photo-1566754844467-33ce3b5aef05")],
    storia:
      "Regalo aziendale mai aperto. Rivendo perché preferisco i bianchi. Etichetta impeccabile.",
    degustazione: "Ciliegia matura, vaniglia, tabacco dolce. Sorso pieno e vellutato.",
    disponibili: 3,
    tag: ["Sangiovese", "Super Tuscan"],
    createdAt: "2026-07-20",
  },
  {
    id: "dom-perignon-2013",
    produttore: "Moët & Chandon",
    nome: "Dom Pérignon Vintage",
    annata: 2013,
    regione: "Champagne",
    denominazione: "Champagne AOC",
    tipo: "Bollicine",
    formato: "0,75 L",
    prezzo: 230,
    prezzoMercato: 260,
    condizione: "Perfetto",
    conservazione: "Cantina buia, temperatura 12°C costante",
    venditore: {
      nome: "Chiara V.",
      citta: "Roma",
      rating: 4.7,
      valutazioni: 89,
      verificato: false,
      avatar: "https://i.pravatar.cc/120?img=25",
    },
    immagini: [img("photo-1550985616-10810253b84d"), img("photo-1514362545857-3bc16c4c7d1b")],
    storia: "Acquistato per un anniversario poi rimandato. Bottiglia con astuccio originale.",
    degustazione: "Agrumi canditi, brioche, note minerali. Bollicina finissima e cremosa.",
    disponibili: 1,
    tag: ["Champagne", "Vintage", "Celebrazione"],
    createdAt: "2026-07-10",
  },
  {
    id: "ornellaia-2017",
    produttore: "Ornellaia",
    nome: "Ornellaia",
    annata: 2017,
    regione: "Toscana",
    denominazione: "Bolgheri Superiore DOC",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 235,
    condizione: "Perfetto",
    conservazione: "Cantina professionale climatizzata",
    venditore: {
      nome: "Enrico M.",
      citta: "Bologna",
      rating: 4.95,
      valutazioni: 214,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=11",
    },
    immagini: [img("photo-1516594798947-e65505dbb29d"), img("photo-1560148218-1a83060f7b32")],
    storia: "Parte di una verticale personale. Rivendo alcune annate per fare spazio.",
    degustazione: "Frutti neri, cacao, spezie orientali. Struttura maestosa.",
    disponibili: 4,
    tag: ["Bolgheri", "Merlot", "Verticale"],
    createdAt: "2026-07-19",
  },
  {
    id: "biondi-santi-2016",
    produttore: "Biondi-Santi",
    nome: "Brunello di Montalcino",
    annata: 2016,
    regione: "Toscana",
    denominazione: "Brunello di Montalcino DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 320,
    prezzoMercato: 380,
    condizione: "Perfetto",
    conservazione: "Cantina di famiglia sotto la casa colonica",
    venditore: {
      nome: "Giulia T.",
      citta: "Siena",
      rating: 4.9,
      valutazioni: 58,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=44",
    },
    immagini: [img("photo-1543418219-44e30b057fea"), img("photo-1568213816046-0ee1c42bd559")],
    storia: "Annata leggendaria. Bottiglia della cantina di famiglia dal rilascio.",
    degustazione: "Amarena, cuoio, erbe balsamiche. Longevità impressionante.",
    disponibili: 2,
    tag: ["Brunello", "Sangiovese Grosso", "Icona"],
    createdAt: "2026-07-16",
  },
  {
    id: "rinaldi-brunate-2018",
    produttore: "Giuseppe Rinaldi",
    nome: "Barolo Brunate",
    annata: 2018,
    regione: "Piemonte",
    denominazione: "Barolo DOCG",
    tipo: "Rosso",
    formato: "0,75 L",
    prezzo: 480,
    prezzoMercato: 540,
    condizione: "Perfetto",
    conservazione: "Cantina interrata, 13°C",
    venditore: {
      nome: "Andrea C.",
      citta: "Torino",
      rating: 5.0,
      valutazioni: 31,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=15",
    },
    immagini: [img("photo-1553361371-9b22f78e8b1d"), img("photo-1547595628-c61a29f496f0")],
    storia: "Bottiglia allocata direttamente in cantina. Rivendo perché ho un doppio.",
    degustazione: "Piccoli frutti rossi, china, viola. Tannino nobile e cristallino.",
    disponibili: 1,
    tag: ["Nebbiolo", "Cru", "Culto"],
    createdAt: "2026-07-21",
  },
  {
    id: "cadelbosco-annamaria-2015",
    produttore: "Ca' del Bosco",
    nome: "Cuvée Annamaria Clementi",
    annata: 2015,
    regione: "Lombardia",
    denominazione: "Franciacorta DOCG",
    tipo: "Bollicine",
    formato: "0,75 L",
    prezzo: 175,
    condizione: "Perfetto",
    conservazione: "Cantina climatizzata professionale",
    venditore: {
      nome: "Federica L.",
      citta: "Brescia",
      rating: 4.85,
      valutazioni: 76,
      verificato: true,
      avatar: "https://i.pravatar.cc/120?img=32",
    },
    immagini: [img("photo-1514362545857-3bc16c4c7d1b"), img("photo-1550985616-10810253b84d")],
    storia: "Riserva di famiglia, cofanetto originale integro.",
    degustazione: "Nocciola, pasticceria, iodio. Bollicina setosa, finale infinito.",
    disponibili: 3,
    tag: ["Franciacorta", "Metodo Classico", "Riserva"],
    createdAt: "2026-07-22",
  },
];

export const communityPosts = [
  {
    id: "p1",
    autore: "Sofia R.",
    avatar: "https://i.pravatar.cc/80?img=47",
    tempo: "2 ore fa",
    testo:
      "Aperto ieri sera un Sassicaia 2015 con amici. Ancora giovanissimo, ma che eleganza. Consiglio decanter di almeno 2 ore.",
    immagine: img("photo-1510812431401-41d2bd2722f3"),
    mi_piace: 128,
    commenti: 24,
  },
  {
    id: "p2",
    autore: "Marco B.",
    avatar: "https://i.pravatar.cc/80?img=13",
    tempo: "ieri",
    testo:
      "Piccolo tour tra le vigne del Barolo. La 2022 promette bene: acidità viva e maturità perfetta.",
    immagine: img("photo-1506377247377-2a5b3b417ebb"),
    mi_piace: 342,
    commenti: 41,
  },
  {
    id: "p3",
    autore: "Enrico M.",
    avatar: "https://i.pravatar.cc/80?img=11",
    tempo: "3 giorni fa",
    testo: "Verticale Ornellaia 2015-2019 tra amici. La 2016 resta imbattibile per equilibrio.",
    immagine: img("photo-1516594798947-e65505dbb29d"),
    mi_piace: 210,
    commenti: 33,
  },
];

export const messagesMock = [
  {
    id: "m1",
    utente: "Marco B.",
    avatar: "https://i.pravatar.cc/80?img=13",
    ultimo: "Certo, posso spedire lunedì. La bottiglia è pronta.",
    tempo: "14:32",
    nonLetti: 2,
    wineId: "monfortino-2015",
  },
  {
    id: "m2",
    utente: "Sofia R.",
    avatar: "https://i.pravatar.cc/80?img=47",
    ultimo: "Grazie della proposta, accetto a 250€.",
    tempo: "ieri",
    nonLetti: 0,
    wineId: "sassicaia-2018",
  },
  {
    id: "m3",
    utente: "Chiara V.",
    avatar: "https://i.pravatar.cc/80?img=25",
    ultimo: "Il Dom Pérignon è ancora disponibile?",
    tempo: "lun",
    nonLetti: 1,
    wineId: "dom-perignon-2013",
  },
];

export const notifications = [
  {
    id: "n1",
    testo: "Marco B. ha accettato la tua proposta per Barolo Monfortino 2015",
    tempo: "5 min fa",
    tipo: "trade",
  },
  { id: "n2", testo: "Sofia R. ha iniziato a seguirti", tempo: "1 ora fa", tipo: "social" },
  {
    id: "n3",
    testo: "Prezzo ribassato: Tignanello 2019 ora a 135€",
    tempo: "3 ore fa",
    tipo: "price",
  },
];
