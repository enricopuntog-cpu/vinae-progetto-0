// Centralized types & mock data for reports, listing statuses,
// moderation actions, audit log and trust badges.

export type TrustSource = "piattaforma" | "venditore" | "ia";

export const trustLabel: Record<TrustSource, string> = {
  piattaforma: "Verificato dalla piattaforma",
  venditore: "Dichiarato dal venditore",
  ia: "Suggerito dall'IA",
};

export const trustHint: Record<TrustSource, string> = {
  piattaforma:
    "Controllato dal team Vinea con procedure interne. Non è una garanzia assoluta di autenticità.",
  venditore:
    "Informazione fornita e attestata dal venditore. Vinea non l'ha verificata direttamente.",
  ia: "Stima automatica generata dall'assistente IA. Utile come riferimento, da confermare.",
};

// ------------------------ REPORTS ------------------------

export type ReportTargetType =
  | "annuncio"
  | "profilo"
  | "messaggio"
  | "conversazione"
  | "post"
  | "commento"
  | "recensione"
  | "club";

export const reportTargetLabel: Record<ReportTargetType, string> = {
  annuncio: "Annuncio",
  profilo: "Profilo utente",
  messaggio: "Messaggio",
  conversazione: "Conversazione",
  post: "Post di club",
  commento: "Commento",
  recensione: "Recensione",
  club: "Club",
};

export const reportReasons: Record<ReportTargetType, string[]> = {
  annuncio: [
    "Annuncio sospetto o possibile falso",
    "Foto non veritiere o riciclate",
    "Descrizione ingannevole",
    "Prezzo anomalo",
    "Contenuto vietato o pericoloso",
    "Annuncio duplicato",
  ],
  profilo: [
    "Identità sospetta",
    "Comportamento scorretto",
    "Comunicazione offensiva",
    "Sospetta frode",
    "Account impersonatore",
  ],
  messaggio: [
    "Contenuto offensivo",
    "Tentativo di truffa",
    "Richiesta di pagamento fuori piattaforma",
    "Spam o pubblicità non richiesta",
  ],
  conversazione: ["Molestie ripetute", "Truffa in corso", "Comunicazione offensiva"],
  post: ["Contenuto inappropriato", "Off-topic per il club", "Spam commerciale", "Disinformazione"],
  commento: ["Insulti o linguaggio offensivo", "Molestia mirata", "Spam"],
  recensione: ["Recensione falsa", "Contenuto diffamatorio", "Fuori tema rispetto all'ordine"],
  club: ["contenuto_non_conforme", "comportamento_scorretto", "spam", "altro"],
};

export const reportReasonLabel: Partial<Record<ReportTargetType, Record<string, string>>> = {
  club: {
    contenuto_non_conforme: "Contenuto non conforme",
    comportamento_scorretto: "Comportamento scorretto",
    spam: "Spam",
    altro: "Altro",
  },
};

export type ReportStatus = "inviata" | "in_revisione" | "info_richieste" | "risolta" | "respinta";

export const reportStatusLabel: Record<ReportStatus, string> = {
  inviata: "Inviata",
  in_revisione: "In revisione",
  info_richieste: "Informazioni richieste",
  risolta: "Risolta",
  respinta: "Respinta",
};

export const reportStatusTone: Record<ReportStatus, string> = {
  inviata: "bg-oro/15 text-oro",
  in_revisione: "bg-blue-500/10 text-blue-700",
  info_richieste: "bg-oro/25 text-antracite",
  risolta: "bg-salvia/15 text-salvia",
  respinta: "bg-muted text-muted-foreground",
};

export type Priorita = "bassa" | "media" | "alta";

export type ReportHistoryEntry = {
  ts: string;
  testo: string;
  autore: string;
};

export type Report = {
  id: string;
  targetType: ReportTargetType;
  targetId: string;
  targetLabel: string;
  reason: string;
  descrizione: string;
  foto: string[];
  stato: ReportStatus;
  priorita: Priorita;
  reporter: string;
  assignee?: string;
  clubSlug?: string; // se legata a un club, visibile anche al moderatore di club
  createdAt: string;
  updatedAt: string;
  storia: ReportHistoryEntry[];
  noteInterne: ReportHistoryEntry[];
};

export function priorityFromReason(reason: string): Priorita {
  const r = reason.toLowerCase();
  if (r.includes("truff") || r.includes("frod") || r.includes("pagament") || r.includes("molest"))
    return "alta";
  if (
    r.includes("offens") ||
    r.includes("falsa") ||
    r.includes("veritier") ||
    r.includes("ingannev")
  )
    return "media";
  return "bassa";
}

// ------------------------ LISTING STATUS ------------------------

export type ListingStatus =
  | "bozza"
  | "in_revisione"
  | "modifiche_richieste"
  | "attivo"
  | "riservato"
  | "venduto"
  | "sospeso"
  | "rifiutato"
  | "scaduto";

export const listingStatusLabel: Record<ListingStatus, string> = {
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

export const listingStatusTone: Record<ListingStatus, string> = {
  bozza: "bg-secondary text-muted-foreground",
  in_revisione: "bg-oro/15 text-oro",
  modifiche_richieste: "bg-oro/25 text-antracite",
  attivo: "bg-salvia/15 text-salvia",
  riservato: "bg-blue-500/10 text-blue-700",
  venduto: "bg-bordeaux/10 text-bordeaux",
  sospeso: "bg-red-500/10 text-red-700",
  rifiutato: "bg-red-500/15 text-red-700",
  scaduto: "bg-muted text-muted-foreground",
};

// Azioni disponibili in base allo stato (solo azioni compatibili)
export function listingActionsFor(s: ListingStatus): string[] {
  switch (s) {
    case "bozza":
      return ["Pubblica", "Modifica", "Elimina"];
    case "in_revisione":
      return ["Ritira", "Modifica"];
    case "modifiche_richieste":
      return ["Modifica", "Ripubblica"];
    case "attivo":
      return ["Modifica", "Metti in riservato", "Ritira", "Segna venduto"];
    case "riservato":
      return ["Torna attivo", "Segna venduto", "Ritira"];
    case "venduto":
      return ["Duplica"];
    case "sospeso":
      return ["Ricorri", "Modifica"];
    case "rifiutato":
      return ["Ricorri", "Duplica"];
    case "scaduto":
      return ["Rinnova", "Modifica"];
  }
}

// ------------------------ MODERATION ACTIONS & AUDIT ------------------------

export type ModAction =
  | "richiesta_modifiche"
  | "ammonizione"
  | "sospensione"
  | "rimozione"
  | "ripristino"
  | "chiusura"
  | "info_richieste";

export const modActionLabel: Record<ModAction, string> = {
  richiesta_modifiche: "Richiedi modifiche",
  ammonizione: "Ammonisci",
  sospensione: "Sospendi",
  rimozione: "Rimuovi",
  ripristino: "Ripristina",
  chiusura: "Chiudi segnalazione",
  info_richieste: "Richiedi informazioni",
};

export const modActionTone: Record<ModAction, string> = {
  richiesta_modifiche: "border-oro/40 text-antracite hover:bg-oro/10",
  ammonizione: "border-oro/60 text-antracite hover:bg-oro/15",
  sospensione: "border-bordeaux/40 text-bordeaux hover:bg-bordeaux/5",
  rimozione: "border-red-500/40 text-red-700 hover:bg-red-500/5",
  ripristino: "border-salvia/50 text-salvia hover:bg-salvia/10",
  chiusura: "border-border text-antracite hover:bg-secondary",
  info_richieste: "border-blue-500/40 text-blue-700 hover:bg-blue-500/5",
};

export type AuditEntry = {
  id: string;
  ts: string;
  attore: string;
  scope: "piattaforma" | "club";
  clubSlug?: string;
  azione: ModAction;
  target: string;
  motivazione: string;
  durata?: string;
  ricorso?: "nessuno" | "aperto" | "accolto" | "respinto";
};

// ------------------------ SEEDS ------------------------

const daysAgo = (d: number) => new Date(Date.now() - d * 86400000).toISOString();

export const reportsSeed: Report[] = [
  {
    id: "SEG-2026-0201",
    targetType: "annuncio",
    targetId: "monfortino-2015",
    targetLabel: "Barolo Monfortino 2015 — Marco B.",
    reason: "Foto non veritiere o riciclate",
    descrizione: "Le foto del retro etichetta sembrano riciclate da un altro annuncio.",
    foto: [],
    stato: "in_revisione",
    priorita: "media",
    reporter: "Elena Rossi",
    assignee: "Team Vinea",
    createdAt: daysAgo(1),
    updatedAt: daysAgo(0.3),
    storia: [
      { ts: daysAgo(1), testo: "Segnalazione ricevuta", autore: "Sistema" },
      { ts: daysAgo(0.5), testo: "Assegnata al team moderazione", autore: "Sistema" },
    ],
    noteInterne: [],
  },
  {
    id: "SEG-2026-0198",
    targetType: "profilo",
    targetId: "chiara-v",
    targetLabel: "Profilo @chiara-v",
    reason: "Comportamento scorretto",
    descrizione: "Non ha risposto dopo l'accettazione della proposta economica.",
    foto: [],
    stato: "info_richieste",
    priorita: "media",
    reporter: "Luca P.",
    assignee: "Mod. Vinea",
    createdAt: daysAgo(3),
    updatedAt: daysAgo(1),
    storia: [
      { ts: daysAgo(3), testo: "Segnalazione ricevuta", autore: "Sistema" },
      { ts: daysAgo(1), testo: "Chieste informazioni aggiuntive", autore: "Mod. Vinea" },
    ],
    noteInterne: [
      { ts: daysAgo(1), testo: "Attendere screenshot dalla conversazione", autore: "Mod. Vinea" },
    ],
  },
  {
    id: "SEG-2026-0192",
    targetType: "post",
    targetId: "d9",
    targetLabel: "Post 'Solfiti sì o no' in Vini naturali",
    reason: "Off-topic per il club",
    descrizione: "Discussione poco tecnica, sfocia in polemica ideologica.",
    foto: [],
    stato: "risolta",
    priorita: "bassa",
    reporter: "Andrea C.",
    assignee: "Mod. Club",
    clubSlug: "vini-naturali",
    createdAt: daysAgo(5),
    updatedAt: daysAgo(3),
    storia: [
      { ts: daysAgo(5), testo: "Segnalazione ricevuta", autore: "Sistema" },
      { ts: daysAgo(4), testo: "Ammonizione all'autore", autore: "Mod. Club" },
      { ts: daysAgo(3), testo: "Chiusa come risolta", autore: "Mod. Club" },
    ],
    noteInterne: [],
  },
  {
    id: "SEG-2026-0187",
    targetType: "messaggio",
    targetId: "msg-fuori",
    targetLabel: "Messaggio in chat con topbrunello_99",
    reason: "Richiesta di pagamento fuori piattaforma",
    descrizione: "Ha chiesto di completare l'acquisto via bonifico privato, fuori Vinea.",
    foto: [],
    stato: "inviata",
    priorita: "alta",
    reporter: "Elena Rossi",
    createdAt: daysAgo(0.2),
    updatedAt: daysAgo(0.2),
    storia: [{ ts: daysAgo(0.2), testo: "Segnalazione ricevuta", autore: "Sistema" }],
    noteInterne: [],
  },
  {
    id: "SEG-2026-0180",
    targetType: "recensione",
    targetId: "rev-12",
    targetLabel: "Recensione su Sassicaia 2018",
    reason: "Recensione falsa",
    descrizione: "L'utente non risulta aver completato l'ordine collegato.",
    foto: [],
    stato: "respinta",
    priorita: "media",
    reporter: "Sofia R.",
    assignee: "Mod. Vinea",
    createdAt: daysAgo(9),
    updatedAt: daysAgo(6),
    storia: [
      { ts: daysAgo(9), testo: "Segnalazione ricevuta", autore: "Sistema" },
      {
        ts: daysAgo(6),
        testo: "Respinta: l'ordine risulta consegnato e recensito",
        autore: "Mod. Vinea",
      },
    ],
    noteInterne: [],
  },
  {
    id: "SEG-2026-0175",
    targetType: "commento",
    targetId: "cmt-88",
    targetLabel: "Commento a discussione Cannubi vs Brunate",
    reason: "Insulti o linguaggio offensivo",
    descrizione: "Attacco personale al moderatore del club.",
    foto: [],
    stato: "in_revisione",
    priorita: "alta",
    reporter: "Marco B.",
    assignee: "Mod. Club",
    clubSlug: "barolo-barbaresco",
    createdAt: daysAgo(0.6),
    updatedAt: daysAgo(0.4),
    storia: [
      { ts: daysAgo(0.6), testo: "Segnalazione ricevuta", autore: "Sistema" },
      { ts: daysAgo(0.4), testo: "Presa in carico dal moderatore del club", autore: "Mod. Club" },
    ],
    noteInterne: [],
  },
];

export const listingStatusSeed: Record<string, ListingStatus> = {
  "monfortino-2015": "attivo",
  "sassicaia-2018": "attivo",
  "tignanello-2019": "riservato",
  "dom-perignon-2013": "attivo",
  "ornellaia-2017": "attivo",
  "biondi-santi-2016": "in_revisione",
  "rinaldi-brunate-2018": "modifiche_richieste",
  "cadelbosco-annamaria-2015": "attivo",
};

export const auditSeed: AuditEntry[] = [
  {
    id: "au-1",
    ts: daysAgo(3),
    attore: "Mod. Club",
    scope: "club",
    clubSlug: "vini-naturali",
    azione: "ammonizione",
    target: "Federica L.",
    motivazione: "Off-topic ripetuto",
    ricorso: "nessuno",
  },
  {
    id: "au-2",
    ts: daysAgo(6),
    attore: "Mod. Vinea",
    scope: "piattaforma",
    azione: "chiusura",
    target: "SEG-2026-0180",
    motivazione: "Segnalazione infondata",
    ricorso: "nessuno",
  },
  {
    id: "au-3",
    ts: daysAgo(2),
    attore: "Mod. Vinea",
    scope: "piattaforma",
    azione: "sospensione",
    target: "vino_flash_87",
    motivazione: "Foto sospette confermate",
    durata: "7 giorni",
    ricorso: "aperto",
  },
];

// Le mie segnalazioni: solo quelle inviate da "Elena Rossi" nella demo
export const MY_REPORTER = "Elena Rossi";
