/**
 * Creazione di un club: validazione locale e sequenza cover -> RPC -> cleanup.
 *
 * Sta qui e non dentro il componente per la stessa ragione di
 * `validaNuovoPost`: la parte che puo sbagliare non ha bisogno di un DOM per
 * essere verificata, e la sequenza del cleanup e proprio la parte che va
 * verificata.
 *
 * La responsabilita e divisa come richiesto: il binario lo carica il CLIENT nel
 * bucket, la RPC riceve soltanto il percorso. Se la proposta fallisce dopo un
 * upload andato a buon fine, l'oggetto appena caricato viene rimosso: senza
 * questo passaggio ogni tentativo fallito lascerebbe un file orfano nella
 * cartella di chi ci ha provato.
 */

import { PRESET_COVER_CLUB, type CoverPresetId } from "@/lib/phase12/club-cover";
import { preparaCoverClub, preparaCoverPreset } from "@/lib/phase12/prepara-cover-club";
import type {
  ClubAccessType,
  ClubProposal,
  ClubService,
  ClubPostingMode,
  Result,
} from "@/services/types";

// Gli stessi numeri delle validazioni di public.club_proposta_crea. Se divergono vince
// il database: qui si perde solo il messaggio gentile.
export const LIMITI_CLUB = {
  nomeMin: 2,
  nomeMax: 120,
  descrizioneMin: 10,
  descrizioneMax: 2000,
  categoriaMin: 2,
  categoriaMax: 40,
  territorioMax: 80,
  requirementsMax: 1000,
  regoleMin: 1,
  regoleMax: 20,
} as const;

export type SceltaCover =
  | { tipo: "nessuna" }
  | { tipo: "preset"; id: CoverPresetId }
  | { tipo: "file"; file: File };

export type BozzaClub = {
  nome: string;
  descrizione: string;
  categoria: string;
  territorio: string;
  accessType: ClubAccessType;
  requirements: string;
  regole: string[];
  postingMode: ClubPostingMode;
  cover: SceltaCover;
};

export const BOZZA_VUOTA: BozzaClub = {
  nome: "",
  descrizione: "",
  categoria: "",
  territorio: "",
  accessType: "aperto",
  requirements: "",
  regole: [],
  postingMode: "OPEN",
  cover: { tipo: "nessuna" },
};

/** `null` quando va bene, come `validaNuovoPost`. */
export const validaBozzaClub = (bozza: BozzaClub): string | null => {
  const nome = bozza.nome.trim();
  const descrizione = bozza.descrizione.trim();

  if (nome.length < LIMITI_CLUB.nomeMin) {
    return `Il nome deve avere almeno ${LIMITI_CLUB.nomeMin} caratteri.`;
  }
  if (nome.length > LIMITI_CLUB.nomeMax) {
    return `Il nome non puo superare ${LIMITI_CLUB.nomeMax} caratteri.`;
  }
  if (descrizione.length < LIMITI_CLUB.descrizioneMin) {
    return `La descrizione deve avere almeno ${LIMITI_CLUB.descrizioneMin} caratteri.`;
  }
  if (descrizione.length > LIMITI_CLUB.descrizioneMax) {
    return `La descrizione non puo superare ${LIMITI_CLUB.descrizioneMax} caratteri.`;
  }
  const categoria = bozza.categoria.trim();
  if (categoria.length < LIMITI_CLUB.categoriaMin || categoria.length > LIMITI_CLUB.categoriaMax) {
    return "La categoria deve contenere da 2 a 40 caratteri.";
  }
  if (bozza.territorio.trim().length > LIMITI_CLUB.territorioMax) {
    return `Il territorio non puo superare ${LIMITI_CLUB.territorioMax} caratteri.`;
  }
  const requirements = bozza.requirements.trim();
  if (requirements && (requirements.length < 3 || requirements.length > LIMITI_CLUB.requirementsMax)) {
    return "I requisiti devono contenere da 3 a 1000 caratteri.";
  }
  if (bozza.regole.length < LIMITI_CLUB.regoleMin || bozza.regole.length > LIMITI_CLUB.regoleMax) {
    return `Inserisci da ${LIMITI_CLUB.regoleMin} a ${LIMITI_CLUB.regoleMax} regole.`;
  }
  if (bozza.regole.some((regola) => regola.trim().length < 3 || regola.trim().length > 500)) {
    return "Ogni regola deve contenere da 3 a 500 caratteri.";
  }
  return null;
};

/**
 * Le regole si scrivono in un'area di testo, una per riga. Le righe vuote non
 * sono regole: toglierle qui evita che l'utente crei una regola invisibile
 * premendo invio due volte.
 */
export const regoleDaTesto = (testo: string): string[] =>
  testo
    .split("\n")
    .map((r) => r.trim())
    .filter((r) => r.length > 0);

export type PreparazioneCover = {
  daFile(file: File): Promise<File>;
  daPreset(percorso: string): Promise<File>;
};

const preparazioneBrowser: PreparazioneCover = {
  daFile: (file) => preparaCoverClub(file),
  daPreset: (percorso) => preparaCoverPreset(percorso),
};

/**
 * Prepara e carica la cover scelta, restituendo il percorso nel bucket. `null`
 * significa "nessuna cover", che e un esito legittimo e non un errore.
 */
const caricaCover = async (
  cover: SceltaCover,
  servizio: ClubService,
  preparazione: PreparazioneCover,
): Promise<Result<string | null>> => {
  if (cover.tipo === "nessuna") return { ok: true, data: null };

  let preparata: File;
  try {
    if (cover.tipo === "file") {
      preparata = await preparazione.daFile(cover.file);
    } else {
      const voce = PRESET_COVER_CLUB.find((v) => v.id === cover.id);
      // Un preset che non e nell'elenco non e un preset: l'unica sorgente di
      // quegli URL e questa costante, e non ci arriva niente dall'utente.
      if (!voce) return { ok: false, error: "Cover predefinita non riconosciuta." };
      preparata = await preparazione.daPreset(voce.percorso);
    }
  } catch (errore) {
    return {
      ok: false,
      error: errore instanceof Error ? errore.message : "Cover non valida.",
    };
  }

  return servizio.caricaCoverClub(preparata);
};

export const creaClub = async (
  bozza: BozzaClub,
  servizio: ClubService,
  preparazione: PreparazioneCover = preparazioneBrowser,
): Promise<Result<ClubProposal>> => {
  const problema = validaBozzaClub(bozza);
  if (problema) return { ok: false, error: problema };

  const cover = await caricaCover(bozza.cover, servizio, preparazione);
  if (!cover.ok) return cover;

  const esito = await servizio.crea({
    nome: bozza.nome.trim(),
    descrizione: bozza.descrizione.trim(),
    categoria: bozza.categoria.trim(),
    territorio: bozza.territorio.trim() || null,
    accessType: bozza.accessType,
    requirements: bozza.requirements.trim() || null,
    regole: bozza.regole,
    postingMode: bozza.postingMode,
    coverImage: cover.data,
  });

  if (!esito.ok && cover.data) {
    // Il club non esiste, quindi quel file non e la cover di niente. Si rimuove
    // subito: aspettare una pulizia periodica vorrebbe dire accumulare un
    // oggetto per ogni tentativo fallito. Se anche la rimozione fallisce
    // l'utente vede comunque l'errore vero, che e quello della proposta.
    await servizio.eliminaCoverClub(cover.data);
  }

  return esito;
};
