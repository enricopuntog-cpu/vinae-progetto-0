export type Obiettivo = "comprare" | "vendere" | "cantina" | "club";

export const obiettiviLabels: Record<Obiettivo, { title: string; desc: string; emoji: string }> = {
  comprare: {
    title: "Comprare vino",
    desc: "Scopri bottiglie da collezionisti verificati.",
    emoji: "🍷",
  },
  vendere: {
    title: "Vendere bottiglie",
    desc: "Pubblica annunci e raggiungi appassionati.",
    emoji: "🏷️",
  },
  cantina: {
    title: "Gestire la cantina",
    desc: "Cataloga, monitora valore e finestre di consumo.",
    emoji: "🗄️",
  },
  club: {
    title: "Partecipare ai Club",
    desc: "Discussioni, note di degustazione, verticali.",
    emoji: "🍾",
  },
};

export type EmailStatus = "non_verificata" | "verificata";
export type AgeStatus = "da_verificare" | "dichiarata" | "verificata";
export type IdentityStatus = "non_avviata" | "in_verifica" | "verificata" | "rifiutata";
export type SellerStatus = "non_abilitato" | "abilitato";

export type Esperienza = "curioso" | "appassionato" | "collezionista" | "esperto";

export const esperienzaLabels: Record<Esperienza, string> = {
  curioso: "Curioso — sto iniziando",
  appassionato: "Appassionato",
  collezionista: "Collezionista",
  esperto: "Esperto / professionista",
};

export type ProfiloUtente = {
  username: string;
  email: string;
  bio: string;
  citta: string;
  provincia: string;
  esperienza: Esperienza;
  avatarUrl: string;
  dob: string; // YYYY-MM-DD
};

export const profiloDemoIniziale: ProfiloUtente = {
  username: "elena_r",
  email: "elena@demo.vinea.it",
  bio: "Appassionata di Nebbiolo e bollicine italiane. Custodisco piccole verticali di famiglia.",
  citta: "Milano",
  provincia: "MI",
  esperienza: "appassionato",
  avatarUrl: "https://i.pravatar.cc/240?img=68",
  dob: "1990-05-14",
};

export const regioniItaliane = [
  "Piemonte",
  "Toscana",
  "Veneto",
  "Sicilia",
  "Puglia",
  "Trentino-Alto Adige",
  "Friuli-Venezia Giulia",
  "Lombardia",
  "Campania",
  "Marche",
  "Umbria",
  "Sardegna",
  "Emilia-Romagna",
  "Abruzzo",
  "Lazio",
  "Liguria",
];

export const tipologieVino = [
  "Rossi strutturati",
  "Rossi giovani",
  "Bianchi minerali",
  "Bianchi aromatici",
  "Bollicine metodo classico",
  "Prosecco e frizzanti",
  "Rosati",
  "Dolci e passiti",
  "Vini naturali",
];

export const fascePrezzo = [
  { id: "sotto50", label: "Sotto 50 €", min: 0, max: 50 },
  { id: "50-150", label: "50 – 150 €", min: 50, max: 150 },
  { id: "150-400", label: "150 – 400 €", min: 150, max: 400 },
  { id: "oltre400", label: "Oltre 400 €", min: 400, max: 9999 },
] as const;

export const clubSuggeriti = [
  { slug: "barolo-barbaresco", nome: "Barolo & Barbaresco", desc: "Nebbiolo di Langa" },
  { slug: "brunello", nome: "Brunello di Montalcino", desc: "Sangiovese Grosso" },
  { slug: "champagne", nome: "Champagne", desc: "Bollicine francesi" },
  { slug: "borgogna", nome: "Borgogna", desc: "Pinot Noir e Chardonnay" },
  { slug: "vini-naturali", nome: "Vini naturali", desc: "Artigianato in vigna" },
  { slug: "amarone", nome: "Amarone", desc: "Valpolicella storica" },
];

export function calcolaCompletamento(input: {
  registrato: boolean;
  emailVerificata: boolean;
  obiettivi: number;
  preferenzeSalvate: boolean;
  profiloBase: boolean;
  identita: IdentityStatus;
  venditore: SellerStatus;
}): { perc: number; items: { label: string; done: boolean; to?: string }[] } {
  const items = [
    { label: "Account creato", done: input.registrato, to: "/onboarding" },
    { label: "Email verificata", done: input.emailVerificata, to: "/onboarding?step=verifica" },
    { label: "Obiettivi selezionati", done: input.obiettivi > 0, to: "/onboarding?step=obiettivi" },
    {
      label: "Preferenze salvate",
      done: input.preferenzeSalvate,
      to: "/onboarding?step=preferenze",
    },
    { label: "Profilo essenziale", done: input.profiloBase, to: "/onboarding?step=profilo" },
    {
      label: "Identità verificata",
      done: input.identita === "verificata",
      to: "/verifica-venditore",
    },
    {
      label: "Venditore abilitato",
      done: input.venditore === "abilitato",
      to: "/verifica-venditore",
    },
  ];
  const done = items.filter((i) => i.done).length;
  return { perc: Math.round((done / items.length) * 100), items };
}
