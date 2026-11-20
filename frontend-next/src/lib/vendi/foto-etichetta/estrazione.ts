// WI-002 — dal testo letto dall'OCR ai campi riconoscibili.
//
// Sono euristiche sul solo testo: l'OCR non restituisce quale scritta sia la più
// grande, quindi produttore e nome sono un'ipotesi, non una lettura certa. Per
// questo ogni campo può restare `null`, e il risultato è sempre mostrato
// all'utente per la modifica prima di toccare il wizard.

import { formatoValido } from "@/lib/cantina/gruppo";

export type CampiEstratti = {
  produttore: string | null;
  nome: string | null;
  annata: number | null;
  /** Più annate plausibili sull'etichetta: l'annata resta `null` e le propone. */
  annateAlternative: number[];
  denominazione: string | null;
  /** Solo un formato dell'elenco chiuso di Vinea, altrimenti `null`. */
  formato: string | null;
  /** Le righe utili lette, nell'ordine; servono all'interfaccia e all'assistenza AI. */
  righe: string[];
};

export type QualitaLettura = "nessuna" | "scarsa" | "parziale" | "buona";

const ANNATA_MIN = 1900;

const RIGA_RUMORE = /^[^\p{L}\p{N}]*$/u;

/** Righe che non sono mai il nome del vino né il produttore. */
const NON_NOME =
  /(%\s*vol|\bvol\.?\b|\balc\b|contiene|solfiti|sulphites|allergen|\bml\b|\bcl\b|\bprodotto\b|\bproduct of\b|\bproduit\b|imbottigliat|bottled|mis en bouteille|\bitalia\b|\bitaly\b|\bwine of\b|\bvino\b(?!\s+\p{L})|lotto|\bl\.\s?\d|riciclabile|ambiente|disperdere|gravidanza|pregnan|\bwww\.|@|\.com\b|\b\d{5}\b)/iu;

const PAROLE_PRODUTTORE =
  /\b(azienda agricola|az\.?\s?agr\.?|societ[àa] agricola|tenut[ae]|cantin[ae]|fattoria|castello|podere|casa vinicola|cascina|marchesi|conti|domaine|ch[âa]teau|bodega|weingut|vigneti|vignaioli|cooperativa)\b/iu;

const DENOMINAZIONE = /\b(DOCG|DOC|IGT|IGP|DOP|AOC|AOP)\b/;

const INTRODUZIONE_PRODUTTORE =
  /(?:prodotto e imbottigliato (?:da|all['’]origine da)|imbottigliato (?:all['’]origine )?da|imbottigliato dalla?|produced and bottled by|bottled by|mis en bouteille (?:au ch[âa]teau|par))\s*[:\-]?\s*(.*)$/iu;

const pulisciRiga = (riga: string): string =>
  riga
    .replace(/[|_~=<>{}\\]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const lettereRatio = (riga: string): number => {
  const alnum = riga.match(/[\p{L}\p{N}]/gu)?.length ?? 0;
  if (alnum === 0) return 0;
  const lettere = riga.match(/\p{L}/gu)?.length ?? 0;
  return lettere / alnum;
};

/** Righe con abbastanza contenuto da essere state lette davvero. */
export function righeUtili(testo: string): string[] {
  return testo
    .split(/\r?\n/)
    .map(pulisciRiga)
    .filter((riga) => !RIGA_RUMORE.test(riga))
    .filter((riga) => (riga.match(/[\p{L}\p{N}]/gu)?.length ?? 0) >= 3);
}

const annataMax = (): number => new Date().getFullYear();

function trovaAnnate(righe: string[]): number[] {
  const trovate = new Set<number>();
  for (const riga of righe) {
    for (const m of riga.matchAll(/(?<![\d.,])((?:19|20)\d{2})(?![\d])/g)) {
      const anno = Number(m[1]);
      if (anno >= ANNATA_MIN && anno <= annataMax()) trovate.add(anno);
    }
  }
  return [...trovate].sort((a, b) => a - b);
}

const FORMATO_DA_VOLUME: ReadonlyArray<[number, string]> = [
  [0.1875, "0,1875 L"],
  [0.375, "0,375 L"],
  [0.5, "0,5 L"],
  [0.75, "0,75 L"],
  [1, "1 L"],
  [1.5, "1,5 L"],
  [3, "3 L"],
  [4.5, "4,5 L"],
  [5, "5 L"],
  [6, "6 L"],
  [9, "9 L"],
  [12, "12 L"],
  [15, "15 L"],
];

function trovaFormato(testo: string): string | null {
  let litri: number | null = null;
  const ml = testo.match(/(?<![\d.,])(\d{3,4})\s?ml\b/i);
  const cl = testo.match(/(?<![\d.,])(\d{2,3})\s?cl\b/i);
  const lt = testo.match(/(?<![\d.,])(\d+(?:[.,]\d+)?)\s?(?:l|lt|litri|liters?|litres?)\b/i);
  if (ml) litri = Number(ml[1]) / 1000;
  else if (cl) litri = Number(cl[1]) / 100;
  else if (lt) litri = Number(lt[1].replace(",", "."));
  else if (/\bmagnum\b/i.test(testo)) litri = 1.5;
  if (litri === null || !Number.isFinite(litri)) return null;
  const hit = FORMATO_DA_VOLUME.find(([v]) => Math.abs(v - litri) < 0.0005);
  return hit && formatoValido(hit[1]) ? hit[1] : null;
}

const capitalizza = (testo: string): string =>
  testo
    .toLocaleLowerCase("it-IT")
    .replace(/(^|[\s'’-])(\p{L})/gu, (_, sep: string, c: string) => sep + c.toLocaleUpperCase("it-IT"));

/** Un testo tutto maiuscolo (tipico delle etichette) diventa leggibile; il resto resta com'è. */
const comeScritto = (riga: string): string => {
  const lettere = riga.replace(/[^\p{L}]/gu, "");
  return lettere.length > 3 && lettere === lettere.toLocaleUpperCase("it-IT") ? capitalizza(riga) : riga;
};

const tagliaA = (testo: string, max: number): string => testo.slice(0, max).trim();

export function estraiCampiDaTestoOcr(testo: string): CampiEstratti {
  const righe = righeUtili(testo);
  const annate = trovaAnnate(righe);
  const usate = new Set<number>();

  // Denominazione.
  let denominazione: string | null = null;
  const iDen = righe.findIndex((r) => DENOMINAZIONE.test(r));
  if (iDen >= 0) {
    usate.add(iDen);
    const sigla = righe[iDen].match(DENOMINAZIONE)![1];
    const prima = righe[iDen]
      .slice(0, righe[iDen].search(DENOMINAZIONE))
      .replace(/denominazione di origine.*$/iu, "")
      .replace(/[^\p{L}\p{N}\s'’-]/gu, " ")
      .replace(/\s+/g, " ")
      .trim();
    // Al massimo le tre parole che precedono la sigla: «Chianti Classico DOCG».
    const parole = prima ? prima.split(" ").slice(-3).join(" ") : "";
    denominazione = tagliaA(comeScritto(`${parole} ${sigla}`.trim()), 80);
  }

  // Produttore: prima l'introduzione esplicita, poi una parola tipica.
  let produttore: string | null = null;
  for (let i = 0; i < righe.length && !produttore; i++) {
    const m = righe[i].match(INTRODUZIONE_PRODUTTORE);
    if (!m) continue;
    usate.add(i);
    let valore = m[1].trim();
    if (valore.length < 3 && righe[i + 1]) {
      valore = righe[i + 1];
      usate.add(i + 1);
    }
    valore = valore.replace(/\b(s\.?r\.?l\.?|s\.?p\.?a\.?|s\.?s\.?|s\.?a\.?s\.?)\b.*$/iu, "").trim();
    if (valore.length >= 3) produttore = tagliaA(comeScritto(valore), 80);
  }
  if (!produttore) {
    const i = righe.findIndex((r, k) => !usate.has(k) && PAROLE_PRODUTTORE.test(r) && !NON_NOME.test(r));
    if (i >= 0) {
      usate.add(i);
      produttore = tagliaA(comeScritto(righe[i]), 80);
    }
  }

  // Nome: la prima riga rimasta che somiglia a un nome, dopo il produttore se c'è.
  const iProd = produttore ? righe.findIndex((r) => comeScritto(r).startsWith(produttore!.slice(0, 12))) : -1;
  const candidate = righe
    .map((riga, i) => ({ riga, i }))
    .filter(({ riga, i }) => {
      if (usate.has(i)) return false;
      if (NON_NOME.test(riga) || DENOMINAZIONE.test(riga)) return false;
      if (/^\W*(?:19|20)\d{2}\W*$/.test(riga)) return false;
      if (riga.length < 3 || riga.length > 48) return false;
      if (lettereRatio(riga) < 0.75) return false;
      if (/^(rosso|bianco|rosato|riserva|superiore|classico|bio|biologico)$/i.test(riga)) return false;
      return true;
    });
  // Tra le prime tre righe candidate si preferisce la più lunga: in genere un
  // nome («Rosso di Prova») batte una località o un titolo di una parola.
  const rosa = candidate.filter(({ i }) => i > iProd).slice(0, 3);
  const scelta = (rosa.length > 0 ? rosa : candidate.slice(0, 3)).reduce<
    { riga: string; i: number } | undefined
  >((migliore, c) => (!migliore || c.riga.length > migliore.riga.length ? c : migliore), undefined);
  const nome = scelta ? tagliaA(comeScritto(scelta.riga.replace(/\b(?:19|20)\d{2}\b/g, "").trim()), 80) || null : null;

  return {
    produttore,
    nome,
    annata: annate.length === 1 ? annate[0] : null,
    annateAlternative: annate.length > 1 ? annate : [],
    denominazione,
    formato: trovaFormato(testo),
    righe,
  };
}

/**
 * Quanto è servita la lettura. `nessuna`: niente di leggibile; `scarsa`: testo ma
 * nessun campo riconosciuto; `parziale`: alcuni campi; `buona`: produttore, nome
 * e annata. Non misura la correttezza: solo la completezza.
 */
export function qualitaLettura(campi: CampiEstratti, confidenzaOcr: number): QualitaLettura {
  const alnum = campi.righe.join("").match(/[\p{L}\p{N}]/gu)?.length ?? 0;
  if (alnum < 6 || (confidenzaOcr < 20 && campi.righe.length < 2)) return "nessuna";
  const riconosciuti = [campi.produttore, campi.nome, campi.annata, campi.denominazione].filter(
    (v) => v !== null,
  ).length;
  if (riconosciuti === 0) return "scarsa";
  if (campi.produttore && campi.nome && campi.annata) return "buona";
  return "parziale";
}
