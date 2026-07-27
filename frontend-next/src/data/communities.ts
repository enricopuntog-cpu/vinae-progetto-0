import { wineImg as img } from "@/lib/wine-images";

export type Community = {
  slug: string;
  nome: string;
  descrizione: string;
  cover: string;
  membri: number;
  attivi: number;
  categoria: "Territorio" | "Denominazione" | "Produttore" | "Tipologia";
  territorio?: string;
  denominazione?: string;
  produttore?: string;
  tipologia?: string;
  moderatori: { nome: string; avatar: string }[];
  regole: string[];
  wineIds: string[];
};

export const communities: Community[] = [
  {
    slug: "barolo-barbaresco",
    nome: "Barolo & Barbaresco",
    descrizione: "Il regno del Nebbiolo. Verticali, MGA, annate storiche.",
    cover: img("photo-1506377247377-2a5b3b417ebb"),
    membri: 4820,
    attivi: 128,
    categoria: "Territorio",
    territorio: "Piemonte",
    denominazione: "Barolo DOCG",
    tipologia: "Rosso",
    moderatori: [
      { nome: "Marco B.", avatar: "https://i.pravatar.cc/80?img=13" },
      { nome: "Andrea C.", avatar: "https://i.pravatar.cc/80?img=15" },
    ],
    regole: [
      "Parla di Nebbiolo di Langa e delle sue MGA",
      "Vietato spam commerciale non collegato al marketplace",
      "Cita sempre annata e produttore",
    ],
    wineIds: ["monfortino-2015", "rinaldi-brunate-2018"],
  },
  {
    slug: "brunello",
    nome: "Brunello di Montalcino",
    descrizione: "Sangiovese Grosso, annate mitiche, verticali senesi.",
    cover: img("photo-1543418219-44e30b057fea"),
    membri: 3120,
    attivi: 74,
    categoria: "Denominazione",
    territorio: "Toscana",
    denominazione: "Brunello di Montalcino DOCG",
    tipologia: "Rosso",
    moderatori: [{ nome: "Giulia T.", avatar: "https://i.pravatar.cc/80?img=44" }],
    regole: ["Solo Brunello e Rosso di Montalcino", "Rispetta gli altri collezionisti"],
    wineIds: ["biondi-santi-2016"],
  },
  {
    slug: "champagne",
    nome: "Champagne",
    descrizione: "Grandi Maison e récoltant-manipulant. Dosaggi, terroir, millesimi.",
    cover: img("photo-1550985616-10810253b84d"),
    membri: 5640,
    attivi: 210,
    categoria: "Tipologia",
    territorio: "Champagne",
    denominazione: "Champagne AOC",
    tipologia: "Bollicine",
    moderatori: [{ nome: "Chiara V.", avatar: "https://i.pravatar.cc/80?img=25" }],
    regole: ["Champagne AOC. Metodo Classico italiano nella community dedicata."],
    wineIds: ["dom-perignon-2013"],
  },
  {
    slug: "borgogna",
    nome: "Borgogna",
    descrizione: "Pinot Nero e Chardonnay, climat, Grand Cru e allocazioni.",
    cover: img("photo-1568213816046-0ee1c42bd559"),
    membri: 2980,
    attivi: 96,
    categoria: "Territorio",
    territorio: "Borgogna",
    tipologia: "Rosso",
    moderatori: [{ nome: "Enrico M.", avatar: "https://i.pravatar.cc/80?img=11" }],
    regole: ["Solo vini di Borgogna", "Confronti fra climat benvenuti"],
    wineIds: [],
  },
  {
    slug: "vini-naturali",
    nome: "Vini naturali italiani",
    descrizione: "Fermentazioni spontanee, macerazioni, artigiani del vino.",
    cover: img("photo-1524593166156-312f362cada0"),
    membri: 2100,
    attivi: 58,
    categoria: "Tipologia",
    territorio: "Italia",
    tipologia: "Rosso",
    moderatori: [{ nome: "Federica L.", avatar: "https://i.pravatar.cc/80?img=32" }],
    regole: ["Vini artigianali con basso intervento", "Niente polemiche ideologiche"],
    wineIds: [],
  },
  {
    slug: "grandi-formati",
    nome: "Grandi formati",
    descrizione: "Magnum, Jéroboam e oltre: quando la dimensione conta.",
    cover: img("photo-1516594798947-e65505dbb29d"),
    membri: 1450,
    attivi: 32,
    categoria: "Tipologia",
    tipologia: "Rosso",
    moderatori: [{ nome: "Luca P.", avatar: "https://i.pravatar.cc/80?img=33" }],
    regole: ["Solo formati ≥ 1,5 L", "Documenta con foto"],
    wineIds: ["ornellaia-2017"],
  },
  {
    slug: "amarone",
    nome: "Amarone",
    descrizione: "L'appassimento della Valpolicella. Classico, Riserve, produttori storici.",
    cover: img("photo-1553361371-9b22f78e8b1d"),
    membri: 1780,
    attivi: 41,
    categoria: "Denominazione",
    territorio: "Veneto",
    denominazione: "Amarone della Valpolicella DOCG",
    tipologia: "Rosso",
    moderatori: [{ nome: "Sofia R.", avatar: "https://i.pravatar.cc/80?img=47" }],
    regole: ["Amarone e Recioto benvenuti", "Vietata la disinformazione tecnica"],
    wineIds: [],
  },
];

export const communityConsigliate = ["borgogna", "vini-naturali", "grandi-formati"];
export const communitySeguiteIniziali = ["barolo-barbaresco", "champagne"];

export type PostTipo =
  "discussione" | "domanda" | "degustazione" | "confronto" | "consiglio" | "sondaggio" | "annuncio";

export type Discussion = {
  id: string;
  communitySlug: string;
  tipo: PostTipo;
  titolo: string;
  autore: string;
  avatar: string;
  tempo: string;
  anteprima: string;
  risposte: number;
  mi_piace: number;
  wineId?: string;
};

export const discussions: Discussion[] = [
  {
    id: "d1",
    communitySlug: "barolo-barbaresco",
    tipo: "degustazione",
    titolo: "Monfortino 2015 stappato ieri: appunti",
    autore: "Marco B.",
    avatar: "https://i.pravatar.cc/80?img=13",
    tempo: "2 ore fa",
    anteprima: "Naso di rosa appassita, tannino ancora nobile. Consiglio 3 ore di decanter.",
    risposte: 24,
    mi_piace: 128,
  },
  {
    id: "d2",
    communitySlug: "barolo-barbaresco",
    tipo: "confronto",
    titolo: "Cannubi vs Brunate: qual è la MGA più elegante?",
    autore: "Andrea C.",
    avatar: "https://i.pravatar.cc/80?img=15",
    tempo: "ieri",
    anteprima: "Con l'annata 2018 le differenze sono davvero marcate…",
    risposte: 41,
    mi_piace: 210,
  },
  {
    id: "d3",
    communitySlug: "barolo-barbaresco",
    tipo: "annuncio",
    titolo: "Vendo Barolo Brunate 2018 — G. Rinaldi",
    autore: "Andrea C.",
    avatar: "https://i.pravatar.cc/80?img=15",
    tempo: "3 giorni fa",
    anteprima: "Bottiglia allocata direttamente in cantina. Doppio pezzo.",
    risposte: 7,
    mi_piace: 34,
    wineId: "rinaldi-brunate-2018",
  },
  {
    id: "d4",
    communitySlug: "brunello",
    tipo: "discussione",
    titolo: "Biondi-Santi 2016 fra 20 anni?",
    autore: "Giulia T.",
    avatar: "https://i.pravatar.cc/80?img=44",
    tempo: "5 ore fa",
    anteprima: "L'annata è mitica. Come pensate evolverà?",
    risposte: 33,
    mi_piace: 180,
  },
  {
    id: "d5",
    communitySlug: "brunello",
    tipo: "sondaggio",
    titolo: "Miglior annata Brunello dell'ultimo decennio",
    autore: "Giulia T.",
    avatar: "https://i.pravatar.cc/80?img=44",
    tempo: "ieri",
    anteprima: "2010, 2015, 2016 o 2019? Vota!",
    risposte: 96,
    mi_piace: 245,
  },
  {
    id: "d6",
    communitySlug: "champagne",
    tipo: "consiglio",
    titolo: "Récoltant sotto i 100€ da provare",
    autore: "Chiara V.",
    avatar: "https://i.pravatar.cc/80?img=25",
    tempo: "oggi",
    anteprima: "Cerco consigli su piccoli vigneron della Côte des Bar.",
    risposte: 52,
    mi_piace: 140,
  },
  {
    id: "d7",
    communitySlug: "champagne",
    tipo: "domanda",
    titolo: "Dom Pérignon 2013: già pronto o da aspettare?",
    autore: "Chiara V.",
    avatar: "https://i.pravatar.cc/80?img=25",
    tempo: "2 giorni fa",
    anteprima: "Ho un paio di bottiglie in cantina. Opinioni?",
    risposte: 21,
    mi_piace: 75,
    wineId: "dom-perignon-2013",
  },
  {
    id: "d8",
    communitySlug: "borgogna",
    tipo: "degustazione",
    titolo: "Verticale Gevrey-Chambertin 2015-2019",
    autore: "Enrico M.",
    avatar: "https://i.pravatar.cc/80?img=11",
    tempo: "ieri",
    anteprima: "Note dettagliate su cinque annate consecutive.",
    risposte: 18,
    mi_piace: 92,
  },
  {
    id: "d9",
    communitySlug: "vini-naturali",
    tipo: "discussione",
    titolo: "Solfiti sì o no: la vera domanda",
    autore: "Federica L.",
    avatar: "https://i.pravatar.cc/80?img=32",
    tempo: "3 ore fa",
    anteprima: "Dopo dieci anni di degustazioni ho un'opinione precisa.",
    risposte: 61,
    mi_piace: 118,
  },
  {
    id: "d10",
    communitySlug: "grandi-formati",
    tipo: "annuncio",
    titolo: "Vendo Magnum Ornellaia 2017",
    autore: "Enrico M.",
    avatar: "https://i.pravatar.cc/80?img=11",
    tempo: "ieri",
    anteprima: "Bottiglia della verticale personale. Astuccio originale.",
    risposte: 12,
    mi_piace: 44,
    wineId: "ornellaia-2017",
  },
  {
    id: "d11",
    communitySlug: "amarone",
    tipo: "consiglio",
    titolo: "Amarone Classico vs moderno",
    autore: "Sofia R.",
    avatar: "https://i.pravatar.cc/80?img=47",
    tempo: "oggi",
    anteprima: "Quali produttori restano fedeli al Classico?",
    risposte: 27,
    mi_piace: 71,
  },
];

export function communityMembriMock(slug: string) {
  const base = [
    { nome: "Marco B.", avatar: "https://i.pravatar.cc/80?img=13" },
    { nome: "Sofia R.", avatar: "https://i.pravatar.cc/80?img=47" },
    { nome: "Luca P.", avatar: "https://i.pravatar.cc/80?img=33" },
    { nome: "Chiara V.", avatar: "https://i.pravatar.cc/80?img=25" },
    { nome: "Enrico M.", avatar: "https://i.pravatar.cc/80?img=11" },
    { nome: "Giulia T.", avatar: "https://i.pravatar.cc/80?img=44" },
    { nome: "Andrea C.", avatar: "https://i.pravatar.cc/80?img=15" },
    { nome: "Federica L.", avatar: "https://i.pravatar.cc/80?img=32" },
  ];
  return base.slice(0, 6 + (slug.length % 3));
}
