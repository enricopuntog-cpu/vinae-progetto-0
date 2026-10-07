/**
 * Demo interna dei Club dentro la guida Market Validation.
 *
 * Spiega soltanto funzioni reali dei Club di Vinea: Club legati a territori,
 * denominazioni, produttori o passioni; accesso aperto oppure su approvazione;
 * proposta di un nuovo Club con revisione; discussioni per tipo di post.
 * Nomi, regole e discussioni sono esempi fittizi e statici: nessun Club reale
 * viene letto, nessuna iscrizione, post o follow viene scritto.
 */

export const MARKET_VALIDATION_CLUB_DEMO_VERSION = "mv-club-demo-2026-10-07" as const;

/** Gli assi di filtro dei Club reali (`territorio`, `denominazione`, `produttore`) più le passioni. */
export type MarketValidationClubDemoAxis = "Territorio" | "Denominazione" | "Produttore" | "Passione";

/** `aperto` e `chiuso` sono i due `ClubAccessType` reali; «chiuso» si accede su richiesta. */
export type MarketValidationClubDemoAccess = "aperto" | "chiuso";

/** Sottoinsieme dei tipi di post reali (`ClubPostTipo`). */
export type MarketValidationClubDemoPostKind = "discussione" | "domanda" | "degustazione" | "consiglio";

export const MARKET_VALIDATION_CLUB_DEMO_POST_LABEL: Record<MarketValidationClubDemoPostKind, string> = {
  discussione: "Discussione",
  domanda: "Domanda",
  degustazione: "Degustazione",
  consiglio: "Consiglio",
};

export const MARKET_VALIDATION_CLUB_DEMO_ACCESS_LABEL: Record<MarketValidationClubDemoAccess, string> = {
  aperto: "Aperto",
  chiuso: "Su approvazione",
};

export type MarketValidationClubDemo = Readonly<{
  id: `mv_club_${string}`;
  name: string;
  axis: MarketValidationClubDemoAxis;
  focus: string;
  description: string;
  access: MarketValidationClubDemoAccess;
  cover: `/club-covers/${string}.svg`;
  rules: readonly string[];
  posts: ReadonlyArray<Readonly<{ kind: MarketValidationClubDemoPostKind; title: string }>>;
  example: true;
}>;

export const MARKET_VALIDATION_CLUB_DEMOS: readonly MarketValidationClubDemo[] = [
  {
    id: "mv_club_colline_langhe",
    name: "Colline delle Langhe",
    axis: "Territorio",
    focus: "Piemonte",
    description: "Per chi ama le colline piemontesi: cantine da visitare, annate da ricordare e vini da confrontare.",
    access: "aperto",
    cover: "/club-covers/collina.svg",
    rules: ["Parla di vino con rispetto per tutti", "Niente vendite nei post: per vendere c'è il marketplace"],
    posts: [
      { kind: "discussione", title: "Annata 2016: com'è oggi nel bicchiere?" },
      { kind: "consiglio", title: "Tre cantine da visitare in autunno" },
    ],
    example: true,
  },
  {
    id: "mv_club_amici_brunello",
    name: "Amici del Brunello",
    axis: "Denominazione",
    focus: "Brunello di Montalcino",
    description: "Un Club verticale su una sola denominazione: verticali, conservazione e confronti tra annate.",
    access: "chiuso",
    cover: "/club-covers/vigna.svg",
    rules: ["Presentati nella richiesta di ingresso", "Una degustazione condivisa al mese"],
    posts: [
      { kind: "degustazione", title: "Verticale di tre annate, appunti a confronto" },
      { kind: "domanda", title: "Quanto aspettare prima di aprire una Riserva?" },
    ],
    example: true,
  },
  {
    id: "mv_club_tenuta_colle",
    name: "Tenuta del Colle",
    axis: "Produttore",
    focus: "Un produttore",
    description: "Il punto d'incontro di chi segue una cantina: novità, assaggi e domande dirette.",
    access: "aperto",
    cover: "/club-covers/cantina.svg",
    rules: ["Domande e assaggi sui vini della tenuta", "Toni cordiali, anche nel disaccordo"],
    posts: [
      { kind: "discussione", title: "La nuova Riserva: prime impressioni" },
      { kind: "domanda", title: "Meglio aprirla adesso o tra qualche anno?" },
    ],
    example: true,
  },
  {
    id: "mv_club_bollicine_tavola",
    name: "Bollicine a tavola",
    axis: "Passione",
    focus: "Metodo classico e abbinamenti",
    description: "Una passione condivisa: spumanti metodo classico, abbinamenti e piccoli produttori da scoprire.",
    access: "chiuso",
    cover: "/club-covers/calici.svg",
    rules: ["Racconta il contesto degli abbinamenti", "Niente pubblicità"],
    posts: [
      { kind: "consiglio", title: "Franciacorta e cucina di mare: idee" },
      { kind: "degustazione", title: "Pas dosé a confronto: appunti" },
    ],
    example: true,
  },
];
