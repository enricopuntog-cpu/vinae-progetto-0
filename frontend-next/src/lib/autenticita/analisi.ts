// WI-016 — Authenticity Assistant, parte deterministica. Modulo PURO: nessuna rete, nessuna immagine, nessuna AI.
// Confronta ciò che il proprietario dichiara con ciò che dice di leggere sull'etichetta e con le evidenze che ha, e
// produce SEGNALI da sottoporre a una persona. Tiene separati identificazione, qualità della foto, provenienza e
// condizioni; l'autenticità resta SEMPRE «non determinabile»: nessuna regola e nessun modello può stabilirla.

/** Elenco chiuso, identico a quello del database (`private.autenticita_richieste`). */
export const SEGNALI_AUTENTICITA = [
  "etichetta_non_coerente",
  "annata_non_coerente",
  "produttore_non_coerente",
  "qualita_foto_insufficiente",
  "provenienza_non_documentata",
  "condizioni_da_verificare",
] as const;
export type SegnaleAutenticita = (typeof SEGNALI_AUTENTICITA)[number];

export const ETICHETTE_SEGNALE: Record<SegnaleAutenticita, string> = {
  etichetta_non_coerente: "L'etichetta non corrisponde a quanto dichiarato",
  annata_non_coerente: "L'annata sull'etichetta è diversa",
  produttore_non_coerente: "Il produttore sull'etichetta è diverso",
  qualita_foto_insufficiente: "Le foto non sono abbastanza nitide",
  provenienza_non_documentata: "Mancano documenti di acquisto",
  condizioni_da_verificare: "Livello, capsula o etichetta da controllare",
};

export type Evidenze = {
  dichiarato: { produttore: string; annata: number | null };
  /** Ciò che il proprietario legge sull'etichetta; vuoto = non indicato. */
  etichetta: { produttore: string; annata: number | null };
  /** `null` = non risposto: un'assenza di risposta non è un «no». */
  documentoAcquisto: boolean | null;
  fotoNitida: boolean | null;
  condizioniDubbie: boolean;
};

export type AnalisiEvidenze = {
  identificazione: { esito: "coerente" | "non_coerente" | "non_verificata" };
  qualitaFoto: { esito: "sufficiente" | "insufficiente" | "non_valutata" };
  provenienza: { esito: "documentata" | "non_documentata" | "non_verificata" };
  condizioni: { esito: "da_verificare" | "non_segnalate" };
  autenticita: { esito: "non_determinabile"; motivo: string };
  segnali: SegnaleAutenticita[];
};

const piega = (t: string): string =>
  t
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();

const stessoProduttore = (a: string, b: string): boolean => {
  const x = ` ${piega(a)} `;
  const y = ` ${piega(b)} `;
  return x.includes(y) || y.includes(x);
};

export function analizzaEvidenze(e: Evidenze): AnalisiEvidenze {
  const segnali: SegnaleAutenticita[] = [];
  const produttoreLetto = piega(e.etichetta.produttore) !== "";
  const annataLetta = e.etichetta.annata !== null;
  const produttoreDiverso = produttoreLetto && !stessoProduttore(e.dichiarato.produttore, e.etichetta.produttore);
  const annataDiversa = annataLetta && e.dichiarato.annata !== null && e.etichetta.annata !== e.dichiarato.annata;
  if (produttoreDiverso) segnali.push("produttore_non_coerente");
  if (annataDiversa) segnali.push("annata_non_coerente");
  if (e.fotoNitida === false) segnali.push("qualita_foto_insufficiente");
  if (e.documentoAcquisto === false) segnali.push("provenienza_non_documentata");
  if (e.condizioniDubbie) segnali.push("condizioni_da_verificare");

  return {
    identificazione: {
      esito: produttoreDiverso || annataDiversa ? "non_coerente" : produttoreLetto && annataLetta ? "coerente" : "non_verificata",
    },
    qualitaFoto: { esito: e.fotoNitida === null ? "non_valutata" : e.fotoNitida ? "sufficiente" : "insufficiente" },
    provenienza: {
      esito: e.documentoAcquisto === null ? "non_verificata" : e.documentoAcquisto ? "documentata" : "non_documentata",
    },
    condizioni: { esito: e.condizioniDubbie ? "da_verificare" : "non_segnalate" },
    autenticita: {
      esito: "non_determinabile",
      motivo:
        "Nessun controllo automatico stabilisce se una bottiglia è autentica. I segnali servono a decidere che cosa far verificare a una persona.",
    },
    segnali,
  };
}
