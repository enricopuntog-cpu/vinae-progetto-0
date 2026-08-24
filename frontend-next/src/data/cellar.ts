// ============================================================
// Vinea — modelli e mock per "Quando berlo", abbinamenti e cantina 3D.
// Tutti i dati sono simulati per la demo. Pronti a essere mappati
// a un futuro database.
// ============================================================

export type DrinkWindowSource =
  | "editorial" // Dato editoriale
  | "ai" // Suggerito dall'IA
  | "personal" // Personalizzato da te
  | "owner" // Dichiarato dal proprietario
  | "unavailable"; // Informazione non disponibile

export type DrinkPhase =
  | "attesa" // Da attendere
  | "quasi" // Quasi pronto
  | "pronto" // Pronto da bere
  | "ideale" // Nel momento ideale
  | "presto" // Bere entro pochi anni
  | "oltre" // Potenzialmente oltre il momento ideale
  | "none"; // Finestra non disponibile

export type WineVintageMeta = {
  drinkWindowStart?: number;
  drinkWindowEnd?: number;
  peakStart?: number;
  peakEnd?: number;
  source: DrinkWindowSource;
  confidence: "alta" | "media" | "bassa";
  foodPairings: FoodPairing[];
  servingTemperature: string;
  decantingMinutes?: number;
  glassType: string;
  occasione?: string;
  lastUpdatedAt: string;
};

export type PairingLevel = "ideale" | "ottimo" | "possibile";

export type FoodPairing = {
  categoria: string; // es. "Brasati e stufati"
  piatto: string; // es. "Brasato al Barolo"
  livello: PairingLevel;
  note: string;
  emoji: string;
  keywords: string[]; // per il match "cosa stai preparando"
};

export type SaleStatus = "privata" | "cantina_pubblica" | "in_vendita" | "venduta";
export type PriceVisibility = "visibile" | "riservato";

/**
 * I tre valori di `public.bottle_units.stato`.
 *
 * Sono le etichette dell'enum `bottle_unit_stato`, lette da `pg_type` sul
 * progetto reale il 19 agosto 2026 e non dedotte da un file di migrazione:
 * `{chiusa, aperta, consumata}`, in quest'ordine.
 */
export type StatoBottiglia = "chiusa" | "aperta" | "consumata";

export type CellarBottle = {
  bottleId: string;
  wineVintageId: string; // → wines[].id
  quantita: number;
  /**
   * Lo stato reale della bottiglia, distinto da `quantita`.
   *
   * `quantita` lo comprime: vale 1 per una chiusa e 0 per una **aperta o
   * consumata**, che sono così indistinguibili. Bastava finché nessuno doveva
   * dire quale delle due; non basta a un badge che parla di una sola.
   *
   * Facoltativo perché i dati dimostrativi di `bottiglieSeed` non hanno uno
   * stato affatto — lì `quantita` è un conteggio (2, 4, 3…), non un
   * interruttore. `undefined` vale quindi «non lo so» e non «chiusa»: chi
   * disegna non deve dedurne nulla.
   *
   * **Nessuna migrazione**: la colonna era già dentro `COLONNE_BOTTIGLIE` e
   * `authenticated` ha su `bottle_units` un GRANT di tabella in sola lettura.
   * Questo campo smette di buttare via un dato che arrivava già.
   */
  stato?: StatoBottiglia;
  plannedOpenDate?: string;
  override?: {
    drinkWindowStart?: number;
    drinkWindowEnd?: number;
    peakStart?: number;
    peakEnd?: number;
    preferenza?: "giovane" | "equilibrato" | "evoluto";
    nota?: string;
  };
  saleStatus: SaleStatus;
  priceVisibility: PriceVisibility;
  storageLocationId?: string; // → StorageSlot.id
  personalNotes?: string;
  /**
   * Il commento lasciato aprendo la bottiglia, e **il giorno in cui è stata
   * aperta davvero**.
   *
   * Distinti da `personalNotes` e da `plannedOpenDate`, che sono altre due cose:
   * la nota generica di cantina, scrivibile dal client, e una data
   * *programmata*. Fino alla migrazione `20260819120000` la nota di degustazione
   * finiva sopra la prima e il giorno reale non esisteva affatto — perciò una
   * bottiglia aperta prima di quel file ha entrambi questi campi vuoti, e non è
   * un errore di lettura.
   */
  degustazioneNota?: string;
  degustazioneAt?: string;
  /**
   * L'annuncio che impedisce di aprire questa bottiglia, se c'è.
   *
   * Non è «l'annuncio della bottiglia»: è quello in uno dei cinque stati su cui
   * `bottiglia_apri` rifiuta. Serve alla Cantina per sapere *prima* di premere
   * se la strada è libera, se passa per una rimozione o se non passa affatto.
   * Assente vuol dire che aprire non incontra ostacoli, non che non ci sia mai
   * stato un annuncio: uno `sospeso` o `venduto` non blocca più niente.
   */
  annuncioBloccante?: { id: string; stato: string };
};

export type EnvShape =
  "parete_lineare" | "scaffalatura_modulare" | "cantinetta" | "cassa_legno" | "nicchia_angolare";

export type EnvTheme =
  "moderna" | "rustica" | "classica" | "pietra" | "industriale" | "minimal" | "premium" | "casse";

export type StorageEnvironment = {
  id: string;
  name: string;
  shape: EnvShape;
  theme: EnvTheme;
  material:
    "rovere" | "noce" | "metallo" | "pietra" | "mattone" | "cemento" | "vetro" | "legno_grezzo";
  lighting: "calda" | "neutra" | "soffusa" | "faretti" | "laterale";
  dimensions: { width: number; height: number; depth: number }; // metri
};

export type StorageModule = {
  id: string;
  environmentId: string;
  label: string;
  position: [number, number, number]; // x,y,z
  rotationY?: number;
  rows: number;
  columns: number;
  depth?: number;
};

export type StorageSlot = {
  id: string;
  moduleId: string;
  row: number;
  column: number;
  depth?: number;
  bottleId?: string;
  status: "libero" | "occupato";
};

// ============================================================
// Metadata per ogni Wine (drink window + abbinamenti)
// Chiave = wine.id
// ============================================================

const NOW = new Date().getFullYear();

const P_ROSSI_STRUTTURATI: FoodPairing[] = [
  {
    categoria: "Brasati e stufati",
    piatto: "Brasato al Barolo con polenta",
    livello: "ideale",
    note: "La struttura tannica bilancia la lunga cottura.",
    emoji: "🥘",
    keywords: ["brasato", "stufato", "polenta", "stracotto"],
  },
  {
    categoria: "Selvaggina",
    piatto: "Cinghiale in umido",
    livello: "ideale",
    note: "Note terrose in armonia con la selvaggina.",
    emoji: "🍖",
    keywords: ["cinghiale", "cervo", "lepre", "selvaggina"],
  },
  {
    categoria: "Formaggi stagionati",
    piatto: "Castelmagno o Parmigiano 36 mesi",
    livello: "ottimo",
    note: "Sapidità e persistenza si esaltano.",
    emoji: "🧀",
    keywords: ["formaggio", "parmigiano", "pecorino", "castelmagno"],
  },
  {
    categoria: "Arrosti",
    piatto: "Arrosto di manzo alle erbe",
    livello: "ottimo",
    note: "Un classico affidabile.",
    emoji: "🥩",
    keywords: ["arrosto", "manzo", "roast"],
  },
  {
    categoria: "Funghi",
    piatto: "Risotto ai porcini",
    livello: "possibile",
    note: "L'umami dei funghi trova un buon dialogo.",
    emoji: "🍄",
    keywords: ["funghi", "porcini", "risotto"],
  },
];

const P_SUPER_TUSCAN: FoodPairing[] = [
  {
    categoria: "Grigliata",
    piatto: "Bistecca alla fiorentina",
    livello: "ideale",
    note: "Cabernet e carne rossa: matrimonio classico.",
    emoji: "🥩",
    keywords: ["bistecca", "fiorentina", "grigliata", "tagliata"],
  },
  {
    categoria: "Selvaggina",
    piatto: "Filetto di capriolo",
    livello: "ideale",
    note: "Grafite e cassis sostengono il selvatico.",
    emoji: "🍖",
    keywords: ["capriolo", "cervo", "selvaggina", "filetto"],
  },
  {
    categoria: "Formaggi",
    piatto: "Pecorino toscano stagionato",
    livello: "ottimo",
    note: "Rotondità mediterranea.",
    emoji: "🧀",
    keywords: ["pecorino", "formaggio"],
  },
  {
    categoria: "Primi importanti",
    piatto: "Pappardelle al ragù di cinghiale",
    livello: "ottimo",
    note: "Piatto di terra toscano.",
    emoji: "🍝",
    keywords: ["ragù", "pappardelle", "pasta", "cinghiale"],
  },
  {
    categoria: "Funghi e tartufo",
    piatto: "Tagliolini al tartufo",
    livello: "possibile",
    note: "Se il vino è ben ossigenato.",
    emoji: "🍄",
    keywords: ["tartufo", "tagliolini", "funghi"],
  },
];

const P_CHAMPAGNE: FoodPairing[] = [
  {
    categoria: "Crostacei",
    piatto: "Ostriche e scampi crudi",
    livello: "ideale",
    note: "Sapidità e bollicina tagliano la dolcezza iodata.",
    emoji: "🦪",
    keywords: ["ostriche", "scampi", "crudi", "crostacei"],
  },
  {
    categoria: "Pesce nobile",
    piatto: "Astice al vapore",
    livello: "ideale",
    note: "Eleganza su eleganza.",
    emoji: "🦞",
    keywords: ["astice", "aragosta", "pesce"],
  },
  {
    categoria: "Tartare e carpacci",
    piatto: "Tartare di ricciola agli agrumi",
    livello: "ottimo",
    note: "Freschezza vs freschezza.",
    emoji: "🐟",
    keywords: ["tartare", "carpaccio", "crudo"],
  },
  {
    categoria: "Aperitivo",
    piatto: "Focaccia e culatello",
    livello: "ottimo",
    note: "Un aperitivo di livello.",
    emoji: "🥂",
    keywords: ["aperitivo", "focaccia", "salumi"],
  },
  {
    categoria: "Pasticceria salata",
    piatto: "Vol au vent al formaggio",
    livello: "possibile",
    note: "Con moderazione.",
    emoji: "🥐",
    keywords: ["pasticceria", "salata", "vol au vent"],
  },
];

const P_ROSSI_ELEGANTI: FoodPairing[] = [
  {
    categoria: "Primi al ragù",
    piatto: "Pici al ragù di chianina",
    livello: "ideale",
    note: "Sangiovese e ragù, tradizione toscana.",
    emoji: "🍝",
    keywords: ["ragù", "pici", "pasta", "sugo"],
  },
  {
    categoria: "Grigliata",
    piatto: "Costata di manzo",
    livello: "ideale",
    note: "Tannino vibrante contro grasso della carne.",
    emoji: "🥩",
    keywords: ["costata", "griglia", "manzo"],
  },
  {
    categoria: "Formaggi",
    piatto: "Pecorino romano",
    livello: "ottimo",
    note: "Sapidità e freschezza si equilibrano.",
    emoji: "🧀",
    keywords: ["pecorino", "formaggio"],
  },
  {
    categoria: "Verdure alla brace",
    piatto: "Melanzane arrostite",
    livello: "possibile",
    note: "Piatto vegetariano ma d'impatto.",
    emoji: "🍆",
    keywords: ["verdure", "melanzane", "brace"],
  },
];

// Default per bottiglie senza mock esplicito
const DEFAULT_META: WineVintageMeta = {
  source: "unavailable",
  confidence: "bassa",
  foodPairings: P_ROSSI_ELEGANTI,
  servingTemperature: "16–18 °C",
  glassType: "Calice universale ampio",
  decantingMinutes: 30,
  lastUpdatedAt: `${NOW}-06-01`,
};

export const wineMeta: Record<string, WineVintageMeta> = {
  "monfortino-2015": {
    drinkWindowStart: 2028,
    drinkWindowEnd: 2055,
    peakStart: 2032,
    peakEnd: 2048,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_ROSSI_STRUTTURATI,
    servingTemperature: "17–18 °C",
    decantingMinutes: 120,
    glassType: "Calice grande Nebbiolo/Borgogna",
    occasione: "Cena importante, tavola formale",
    lastUpdatedAt: "2026-06-01",
  },
  "sassicaia-2018": {
    drinkWindowStart: 2025,
    drinkWindowEnd: 2045,
    peakStart: 2028,
    peakEnd: 2038,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_SUPER_TUSCAN,
    servingTemperature: "17–18 °C",
    decantingMinutes: 90,
    glassType: "Calice Bordeaux",
    occasione: "Cena di gala, verticale con amici",
    lastUpdatedAt: "2026-05-20",
  },
  "tignanello-2019": {
    drinkWindowStart: 2025,
    drinkWindowEnd: 2040,
    peakStart: 2027,
    peakEnd: 2035,
    source: "ai",
    confidence: "media",
    foodPairings: P_SUPER_TUSCAN,
    servingTemperature: "17–18 °C",
    decantingMinutes: 60,
    glassType: "Calice Bordeaux medio",
    occasione: "Cena importante ma informale",
    lastUpdatedAt: "2026-06-10",
  },
  "dom-perignon-2013": {
    drinkWindowStart: 2024,
    drinkWindowEnd: 2040,
    peakStart: 2026,
    peakEnd: 2035,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_CHAMPAGNE,
    servingTemperature: "8–10 °C",
    decantingMinutes: 0,
    glassType: "Tulipano da Champagne",
    occasione: "Celebrazioni, aperitivi importanti",
    lastUpdatedAt: "2026-05-01",
  },
  "ornellaia-2017": {
    drinkWindowStart: 2024,
    drinkWindowEnd: 2038,
    peakStart: 2026,
    peakEnd: 2034,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_SUPER_TUSCAN,
    servingTemperature: "17–18 °C",
    decantingMinutes: 75,
    glassType: "Calice Bordeaux",
    occasione: "Cena importante",
    lastUpdatedAt: "2026-04-15",
  },
  "biondi-santi-2016": {
    drinkWindowStart: 2026,
    drinkWindowEnd: 2050,
    peakStart: 2030,
    peakEnd: 2045,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_ROSSI_ELEGANTI,
    servingTemperature: "17–18 °C",
    decantingMinutes: 90,
    glassType: "Calice Sangiovese ampio",
    occasione: "Cena di grande respiro",
    lastUpdatedAt: "2026-03-30",
  },
  "rinaldi-brunate-2018": {
    drinkWindowStart: 2027,
    drinkWindowEnd: 2045,
    peakStart: 2030,
    peakEnd: 2042,
    source: "ai",
    confidence: "media",
    foodPairings: P_ROSSI_STRUTTURATI,
    servingTemperature: "17 °C",
    decantingMinutes: 90,
    glassType: "Calice Nebbiolo",
    occasione: "Serata tra appassionati",
    lastUpdatedAt: "2026-06-15",
  },
  "cadelbosco-annamaria-2015": {
    drinkWindowStart: 2023,
    drinkWindowEnd: 2035,
    peakStart: 2025,
    peakEnd: 2032,
    source: "editorial",
    confidence: "alta",
    foodPairings: P_CHAMPAGNE,
    servingTemperature: "9–11 °C",
    decantingMinutes: 0,
    glassType: "Tulipano ampio",
    occasione: "Aperitivo o cena di pesce",
    lastUpdatedAt: "2026-05-05",
  },
};

export function getWineMeta(wineId: string): WineVintageMeta {
  return wineMeta[wineId] ?? DEFAULT_META;
}

// ============================================================
// Drink window helpers
// ============================================================

export function computeDrinkPhase(
  meta: Pick<WineVintageMeta, "drinkWindowStart" | "drinkWindowEnd" | "peakStart" | "peakEnd">,
  year: number = new Date().getFullYear(),
): DrinkPhase {
  const { drinkWindowStart: s, drinkWindowEnd: e, peakStart: ps, peakEnd: pe } = meta;
  if (!s || !e) return "none";
  if (year < s - 1) return "attesa";
  if (year < s) return "quasi";
  if (ps && pe && year >= ps && year <= pe) return "ideale";
  if (year > e) return "oltre";
  if (year > e - 3) return "presto";
  return "pronto";
}

export const phaseLabel: Record<DrinkPhase, string> = {
  attesa: "Da attendere",
  quasi: "Quasi pronto",
  pronto: "Pronto da bere",
  ideale: "Nel momento ideale",
  presto: "Bere entro pochi anni",
  oltre: "Potenzialmente oltre il momento ideale",
  none: "Finestra non disponibile",
};

export const phaseShort: Record<DrinkPhase, string> = {
  attesa: "Da attendere",
  quasi: "Quasi pronto",
  pronto: "Pronto ora",
  ideale: "Momento ideale",
  presto: "Bere presto",
  oltre: "Oltre il picco",
  none: "",
};

/**
 * Le classi delle pastiglie della finestra di bevuta.
 *
 * `pronto` è **opaco** — `bg-salvia-scuro text-crema`, 7,27:1 — e non lo era.
 * Valeva `bg-salvia/25 text-salvia`, e un fondo traslucido sovrapposto a una
 * foto non ha un contrasto proprio: ce l'ha *insieme alla foto*, che è un dato
 * caricato dall'utente e quindi ignoto. Misurato, dava 3,09:1 su una foto
 * chiara e 3,96:1 su una scura, cioè sotto la soglia WCAG 2.1 AA di 4,5:1 su
 * entrambe, per un testo che a 10px in grassetto non è «testo grande» sotto
 * nessuna definizione. Ora il numero è **lo stesso qualunque sia la foto**.
 *
 * `--salvia-scuro` è un token nuovo e non un riuso, perché nessuna coppia fra i
 * token esistenti passava: `--salvia` è un mezzotono (L46%) e falliva in tutte
 * e due le direzioni — 3,76:1 con `crema`, 3,92:1 con `antracite`. Renderlo
 * semplicemente opaco non sarebbe bastato, ed è la ragione per cui questa
 * correzione tocca `globals.css` mentre quella del badge «Aperta» no.
 *
 * `quasi` è **opaco** dal 24 agosto 2026, per lo stesso motivo e con lo stesso
 * rimedio. Valeva `bg-oro/25 text-antracite`, cioè oro al 25% e testo scuro: su
 * una foto chiara dava 13,12:1, su una scura **1,10:1** — il numero peggiore
 * dell'intera tavolozza, e ben sotto i 3,96:1 che avevano motivato la correzione
 * di `pronto`. Era stato misurato allora e lasciato fuori perimetro; ora è
 * `bg-oro-scuro text-crema`, 7,38:1 qualunque sia la foto.
 *
 * `--oro-scuro` è un token nuovo e non un riuso, e la ragione è la stessa
 * misurata per `--salvia-scuro`: nessuna coppia esistente reggeva *e* restava
 * distinguibile. `--oro` pieno con `antracite` passerebbe (6,03:1), ma è già la
 * pastiglia di `presto`, e `quasi` («troppo giovane») e `presto` («bevila
 * adesso») direbbero due cose opposte con lo stesso colore. Oggi differiscono
 * solo per la trasparenza, che è esattamente ciò che va tolto.
 *
 * `ideale` **non** è toccato: `bg-bordeaux text-crema` misura 9,99:1 ed era già
 * leggibile. `oltre` resta traslucido — è fuori dal perimetro chiesto, e la sua
 * misura sta in `badge-stato.test.ts` invece che qui.
 */
export const phaseColor: Record<DrinkPhase, string> = {
  attesa: "bg-secondary text-antracite",
  quasi: "bg-oro-scuro text-crema",
  pronto: "bg-salvia-scuro text-crema",
  ideale: "bg-bordeaux text-crema",
  presto: "bg-oro text-antracite",
  oltre: "bg-destructive/20 text-destructive",
  none: "bg-muted text-muted-foreground",
};

export const sourceLabel: Record<DrinkWindowSource, string> = {
  editorial: "Dato editoriale",
  ai: "Suggerito dall'IA",
  personal: "Personalizzato da te",
  owner: "Dichiarato dal proprietario",
  unavailable: "Informazione non disponibile",
};

export const DRINK_WINDOW_DISCLAIMER =
  "Indicazione orientativa basata su vino, annata, stile e condizioni dichiarate. L'evoluzione reale può variare in base alla conservazione e alle preferenze personali.";

// ============================================================
// Cellar mock: 2 ambienti, moduli, slot con bottiglie
// ============================================================

export const environments: StorageEnvironment[] = [
  {
    id: "env-cantina",
    name: "Cantina interrata",
    shape: "scaffalatura_modulare",
    theme: "pietra",
    material: "legno_grezzo",
    lighting: "soffusa",
    dimensions: { width: 5, height: 2.5, depth: 3 },
  },
  {
    id: "env-salotto",
    name: "Cantinetta salotto",
    shape: "cantinetta",
    theme: "moderna",
    material: "metallo",
    lighting: "faretti",
    dimensions: { width: 1, height: 1.8, depth: 0.6 },
  },
];

export const modules: StorageModule[] = [
  {
    id: "mod-a",
    environmentId: "env-cantina",
    label: "Scaffale A — Rossi da invecchiamento",
    position: [-1.6, 0, 0],
    rows: 4,
    columns: 5,
    depth: 2,
  },
  {
    id: "mod-b",
    environmentId: "env-cantina",
    label: "Scaffale B — Toscana",
    position: [0.4, 0, 0],
    rows: 4,
    columns: 5,
    depth: 2,
  },
  {
    id: "mod-c",
    environmentId: "env-cantina",
    label: "Cassa Champagne",
    position: [2.4, 0, 0],
    rows: 2,
    columns: 3,
    depth: 1,
  },
  {
    id: "mod-d",
    environmentId: "env-salotto",
    label: "Cantinetta salotto",
    position: [0, 0, 0],
    rows: 5,
    columns: 3,
    depth: 1,
  },
];

function makeSlots(): StorageSlot[] {
  const out: StorageSlot[] = [];
  for (const m of modules) {
    for (let r = 0; r < m.rows; r++) {
      for (let c = 0; c < m.columns; c++) {
        out.push({ id: `${m.id}-r${r}c${c}`, moduleId: m.id, row: r, column: c, status: "libero" });
      }
    }
  }
  return out;
}

export const slotsSeed: StorageSlot[] = makeSlots();

// Bottiglie fisiche demo — 1+ per Wine
export const bottiglieSeed: CellarBottle[] = [
  {
    bottleId: "b-monf-1",
    wineVintageId: "monfortino-2015",
    quantita: 2,
    saleStatus: "privata",
    priceVisibility: "riservato",
    storageLocationId: "mod-a-r0c0",
    plannedOpenDate: "2032-12-24",
  },
  {
    bottleId: "b-sass-1",
    wineVintageId: "sassicaia-2018",
    quantita: 4,
    saleStatus: "in_vendita",
    priceVisibility: "visibile",
    storageLocationId: "mod-b-r0c0",
  },
  {
    bottleId: "b-sass-2",
    wineVintageId: "sassicaia-2018",
    quantita: 2,
    saleStatus: "cantina_pubblica",
    priceVisibility: "visibile",
    storageLocationId: "mod-b-r0c1",
  },
  {
    bottleId: "b-tign-1",
    wineVintageId: "tignanello-2019",
    quantita: 3,
    saleStatus: "in_vendita",
    priceVisibility: "visibile",
    storageLocationId: "mod-b-r1c0",
  },
  {
    bottleId: "b-domp-1",
    wineVintageId: "dom-perignon-2013",
    quantita: 1,
    saleStatus: "in_vendita",
    priceVisibility: "visibile",
    storageLocationId: "mod-c-r0c0",
    plannedOpenDate: `${NOW}-12-31`,
  },
  {
    bottleId: "b-orn-1",
    wineVintageId: "ornellaia-2017",
    quantita: 4,
    saleStatus: "privata",
    priceVisibility: "visibile",
    storageLocationId: "mod-b-r2c0",
  },
  {
    bottleId: "b-bs-1",
    wineVintageId: "biondi-santi-2016",
    quantita: 2,
    saleStatus: "privata",
    priceVisibility: "visibile",
    storageLocationId: "mod-a-r1c0",
  },
  {
    bottleId: "b-rin-1",
    wineVintageId: "rinaldi-brunate-2018",
    quantita: 1,
    saleStatus: "privata",
    priceVisibility: "visibile",
    storageLocationId: "mod-a-r0c1",
  },
  {
    bottleId: "b-cdb-1",
    wineVintageId: "cadelbosco-annamaria-2015",
    quantita: 3,
    saleStatus: "cantina_pubblica",
    priceVisibility: "visibile",
    storageLocationId: "mod-d-r0c0",
  },
];

// Applica bottleId agli slot seed
export function slotsWithBottles(bottiglie: CellarBottle[]): StorageSlot[] {
  const map = new Map<string, StorageSlot>(slotsSeed.map((s) => [s.id, { ...s }]));
  for (const b of bottiglie) {
    if (b.storageLocationId && map.has(b.storageLocationId)) {
      const s = map.get(b.storageLocationId)!;
      map.set(b.storageLocationId, { ...s, bottleId: b.bottleId, status: "occupato" });
    }
  }
  return Array.from(map.values());
}

// ============================================================
// Configuratore: forme + preset
// ============================================================

export const SHAPE_LABELS: Record<EnvShape, string> = {
  parete_lineare: "Parete lineare",
  scaffalatura_modulare: "Scaffalatura modulare",
  cantinetta: "Cantinetta frigorifera",
  cassa_legno: "Cassa di legno",
  nicchia_angolare: "Nicchia angolare",
};

export const THEME_LABELS: Record<EnvTheme, string> = {
  moderna: "Moderna",
  rustica: "Rustica",
  classica: "Classica",
  pietra: "Pietra",
  industriale: "Industriale",
  minimal: "Minimal",
  premium: "Premium",
  casse: "Parete di casse",
};
