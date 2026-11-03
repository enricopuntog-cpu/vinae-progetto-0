import type { DisputeLifecycleStatus, DisputeRecord, DisputeSellerResponseKind, DisputeStato } from "@/services/types";

/**
 * VPM-015B5C — il post-vendita di un ordine Accessori, com'è letto dal browser.
 *
 * Il browser non porta mai un importo o uno stato economico: legge ciò che il
 * database ha deciso (`accessori_postvendita_leggi`). I parser sono rigidi: una
 * risposta fuori forma diventa un errore, non un valore inventato.
 */

export const MOTIVI_CONTESTAZIONE_ACCESSORI = [
  "Articolo rotto",
  "Articolo diverso dalla descrizione",
  "Quantità errata o incompleta",
  "Articolo non ricevuto",
  "Articolo difettoso",
  "Imballaggio inadeguato",
] as const;

export type PostVenditaAccessorio = {
  ordineId: string;
  incassato: boolean;
  consegna: { registrataAt: string; fonte: "vettore" | "manuale_admin"; provaVettore: boolean } | null;
  finestraContestazioneScadeAt: string | null;
  puoContestare: boolean;
  contestazione: {
    stato: DisputeStato;
    motivo: string;
    descrizione: string;
    foto: string[];
    apertaAt: string;
    venditoreScadenzaAt: string;
    puoRispondere: boolean;
    risposta: { tipo: DisputeSellerResponseKind; testo: string; foto: string[]; at: string } | null;
    esitoNota: string | null;
    importoRimborsoCents: number | null;
    chiusaAt: string | null;
  } | null;
  rimborso: { rimborsatoCents: number; inCorsoCents: number } | null;
  ricavo: { stato: "trattenuto" | "rilasciato" | "stornato"; importoCents: number; stornatoCents: number; rilasciatoAt: string | null } | null;
};

export type ElencoPostVenditaAdmin = {
  contestazioni: Array<{
    ordineId: string;
    stato: DisputeStato;
    motivo: string;
    apertaAt: string;
    venditoreScadenzaAt: string;
    rispostaAt: string | null;
    pronta: boolean;
  }>;
  rimborsi: Array<{
    rimborsoId: string;
    ordineId: string;
    origine: "dovuto_automatico" | "contestazione";
    stato: string;
    importoCents: number;
    tentativi: number;
    richiestoAt: string;
    aggiornatoAt: string;
    ultimoErrore: string | null;
  }>;
};

const oggetto = (v: unknown): Record<string, unknown> | null =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
const testo = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const intero = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const elencoTesti = (v: unknown): string[] | null =>
  Array.isArray(v) && v.every((x) => typeof x === "string") ? (v as string[]) : null;

const STATI_DISPUTA: readonly DisputeStato[] = ["aperta", "in_valutazione", "rimborsata", "risolta", "respinta"];
const RISPOSTE: readonly DisputeSellerResponseKind[] = ["accetta", "contesta", "propone_soluzione"];

export function parsePostvendita(v: unknown): PostVenditaAccessorio | null {
  const o = oggetto(v);
  if (!o) return null;
  const ordineId = testo(o.ordineId);
  if (!ordineId || typeof o.incassato !== "boolean" || typeof o.puoContestare !== "boolean") return null;

  let consegna: PostVenditaAccessorio["consegna"] = null;
  if (o.consegna !== null && o.consegna !== undefined) {
    const c = oggetto(o.consegna);
    const registrataAt = c ? testo(c.registrataAt) : null;
    if (!c || !registrataAt || (c.fonte !== "vettore" && c.fonte !== "manuale_admin") || typeof c.provaVettore !== "boolean") {
      return null;
    }
    consegna = { registrataAt, fonte: c.fonte, provaVettore: c.provaVettore };
  }

  let contestazione: PostVenditaAccessorio["contestazione"] = null;
  if (o.contestazione !== null && o.contestazione !== undefined) {
    const c = oggetto(o.contestazione);
    if (!c) return null;
    const foto = elencoTesti(c.foto);
    const stato = STATI_DISPUTA.find((s) => s === c.stato);
    const motivo = testo(c.motivo);
    const descrizione = testo(c.descrizione);
    const apertaAt = testo(c.apertaAt);
    const venditoreScadenzaAt = testo(c.venditoreScadenzaAt);
    if (!foto || !stato || !motivo || !descrizione || !apertaAt || !venditoreScadenzaAt || typeof c.puoRispondere !== "boolean") {
      return null;
    }
    let risposta: NonNullable<PostVenditaAccessorio["contestazione"]>["risposta"] = null;
    if (c.risposta !== null && c.risposta !== undefined) {
      const r = oggetto(c.risposta);
      const tipo = r ? RISPOSTE.find((x) => x === r.tipo) : undefined;
      const rt = r ? testo(r.testo) : null;
      const rf = r ? elencoTesti(r.foto) : null;
      const at = r ? testo(r.at) : null;
      if (!tipo || !rt || !rf || !at) return null;
      risposta = { tipo, testo: rt, foto: rf, at };
    }
    contestazione = {
      stato, motivo, descrizione, foto, apertaAt, venditoreScadenzaAt,
      puoRispondere: c.puoRispondere, risposta,
      esitoNota: typeof c.esitoNota === "string" ? c.esitoNota : null,
      importoRimborsoCents: intero(c.importoRimborsoCents),
      chiusaAt: typeof c.chiusaAt === "string" ? c.chiusaAt : null,
    };
  }

  let rimborso: PostVenditaAccessorio["rimborso"] = null;
  if (o.rimborso !== null && o.rimborso !== undefined) {
    const r = oggetto(o.rimborso);
    const a = r ? intero(r.rimborsatoCents) : null;
    const b = r ? intero(r.inCorsoCents) : null;
    if (a === null || b === null) return null;
    rimborso = { rimborsatoCents: a, inCorsoCents: b };
  }

  let ricavo: PostVenditaAccessorio["ricavo"] = null;
  if (o.ricavo !== null && o.ricavo !== undefined) {
    const r = oggetto(o.ricavo);
    const importoCents = r ? intero(r.importoCents) : null;
    const stornatoCents = r ? intero(r.stornatoCents) : null;
    if (!r || importoCents === null || stornatoCents === null
        || (r.stato !== "trattenuto" && r.stato !== "rilasciato" && r.stato !== "stornato")) {
      return null;
    }
    ricavo = { stato: r.stato, importoCents, stornatoCents, rilasciatoAt: typeof r.rilasciatoAt === "string" ? r.rilasciatoAt : null };
  }

  return {
    ordineId, incassato: o.incassato, consegna,
    finestraContestazioneScadeAt: typeof o.finestraContestazioneScadeAt === "string" ? o.finestraContestazioneScadeAt : null,
    puoContestare: o.puoContestare, contestazione, rimborso, ricavo,
  };
}

export function parseElencoPostVenditaAdmin(v: unknown): ElencoPostVenditaAdmin | null {
  const o = oggetto(v);
  if (!o || !Array.isArray(o.contestazioni) || !Array.isArray(o.rimborsi)) return null;
  const contestazioni: ElencoPostVenditaAdmin["contestazioni"] = [];
  for (const raw of o.contestazioni) {
    const c = oggetto(raw);
    const stato = c ? STATI_DISPUTA.find((s) => s === c.stato) : undefined;
    if (!c || !stato || !testo(c.ordineId) || !testo(c.motivo) || !testo(c.apertaAt) || !testo(c.venditoreScadenzaAt)
        || typeof c.pronta !== "boolean") {
      return null;
    }
    contestazioni.push({
      ordineId: c.ordineId as string, stato, motivo: c.motivo as string, apertaAt: c.apertaAt as string,
      venditoreScadenzaAt: c.venditoreScadenzaAt as string,
      rispostaAt: typeof c.rispostaAt === "string" ? c.rispostaAt : null, pronta: c.pronta,
    });
  }
  const rimborsi: ElencoPostVenditaAdmin["rimborsi"] = [];
  for (const raw of o.rimborsi) {
    const r = oggetto(raw);
    const importo = r ? intero(r.importoCents) : null;
    const tentativi = r ? intero(r.tentativi) : null;
    if (!r || !testo(r.rimborsoId) || !testo(r.ordineId) || (r.origine !== "dovuto_automatico" && r.origine !== "contestazione")
        || !testo(r.stato) || importo === null || tentativi === null || !testo(r.richiestoAt) || !testo(r.aggiornatoAt)) {
      return null;
    }
    rimborsi.push({
      rimborsoId: r.rimborsoId as string, ordineId: r.ordineId as string, origine: r.origine,
      stato: r.stato as string, importoCents: importo, tentativi, richiestoAt: r.richiestoAt as string,
      aggiornatoAt: r.aggiornatoAt as string, ultimoErrore: typeof r.ultimoErrore === "string" ? r.ultimoErrore : null,
    });
  }
  return { contestazioni, rimborsi };
}

export type IntentoOrfanoAdmin = {
  ordineId: string;
  provider: string;
  intento: string;
  importoCents: number;
  valuta: string;
  statoPagamento: string;
  statoIntento: "da_annullare" | "incerto";
  motivo: string | null;
  aggiornatoAt: string;
};

export type RimborsoDovutoAdmin = {
  ordineId: string;
  importoCents: number;
  valuta: string;
  rimborsatoCents: number;
  motivo: string | null;
  aggiornatoAt: string;
};

/** VPM-015QA-FINAL-B2: elenco admin degli intenti orfani non risolti (`accessori_pagamenti_intenti_orfani`). */
export function parseIntentiOrfaniAdmin(v: unknown): IntentoOrfanoAdmin[] | null {
  if (!Array.isArray(v)) return null;
  const out: IntentoOrfanoAdmin[] = [];
  for (const raw of v) {
    const r = oggetto(raw);
    const importo = r ? intero(r.importo_cents) : null;
    const stato = r && (r.stato_intento === "da_annullare" || r.stato_intento === "incerto") ? r.stato_intento : null;
    if (!r || !stato || importo === null || !testo(r.ordine_id) || !testo(r.provider) || !testo(r.intento)
        || !testo(r.valuta) || !testo(r.stato_pagamento) || !testo(r.aggiornato_at)) {
      return null;
    }
    out.push({
      ordineId: r.ordine_id as string, provider: r.provider as string, intento: r.intento as string,
      importoCents: importo, valuta: r.valuta as string, statoPagamento: r.stato_pagamento as string,
      statoIntento: stato, motivo: typeof r.motivo === "string" ? r.motivo : null, aggiornatoAt: r.aggiornato_at as string,
    });
  }
  return out;
}

/** VPM-015QA-FINAL-B2: pagamenti incassati e non applicabili (`accessori_pagamenti_rimborso_dovuto`). */
export function parseRimborsiDovutiAdmin(v: unknown): RimborsoDovutoAdmin[] | null {
  if (!Array.isArray(v)) return null;
  const out: RimborsoDovutoAdmin[] = [];
  for (const raw of v) {
    const r = oggetto(raw);
    const importo = r ? intero(r.importo_cents) : null;
    const rimborsato = r ? intero(r.rimborsato_cents) : null;
    if (!r || importo === null || rimborsato === null || !testo(r.ordine_id) || !testo(r.valuta) || !testo(r.aggiornato_at)) {
      return null;
    }
    out.push({
      ordineId: r.ordine_id as string, importoCents: importo, valuta: r.valuta as string, rimborsatoCents: rimborsato,
      motivo: typeof r.motivo === "string" ? r.motivo : null, aggiornatoAt: r.aggiornato_at as string,
    });
  }
  return out;
}

/** Messaggi per gli `hint` delle porte (mai testo del database né dettagli interni). */
export const MESSAGGI_POSTVENDITA: Readonly<Record<string, string>> = {
  non_trovato: "Ordine non trovato.",
  ordine_non_contestabile: "Questo ordine non si può contestare.",
  consegna_non_registrata: "La consegna non è ancora registrata: potrai contestare entro 48 ore da quel momento.",
  finestra_scaduta: "Il termine di 48 ore dalla consegna è scaduto.",
  gia_aperta: "Hai già aperto una contestazione per questo ordine.",
  motivo_non_valido: "Scegli uno dei motivi proposti.",
  descrizione_non_valida: "La descrizione deve contenere da 3 a 2000 caratteri.",
  risposta_non_valida: "La risposta deve contenere da 3 a 2000 caratteri.",
  gia_risposto: "La risposta è già stata registrata.",
  risposta_scaduta: "La finestra di 48 ore per rispondere è terminata.",
  contestazione_chiusa: "La contestazione è già chiusa.",
  documentazione_incompleta: "Il venditore ha ancora tempo per rispondere.",
  importo_non_valido: "Importo del rimborso non valido.",
  gia_decisa: "La contestazione è già stata decisa.",
  nessun_rimborso: "Nessun rimborso per questo ordine.",
  reso_gia_registrato: "Il reso è già registrato.",
  quantita_non_valida: "Quantità non valida.",
  riferimento_non_valido: "Indica un riferimento di almeno 3 caratteri.",
};

export const messaggioPostvendita = (hint: string): string | null => MESSAGGI_POSTVENDITA[hint] ?? null;

/**
 * Adatta la contestazione di dominio al fascicolo che `DisputePanel` già mostra
 * (stesso componente del vino): non esiste un secondo pannello. `foto` sono URL
 * firmati. Il ciclo di vita deriva dallo stato e dalla risposta.
 */
export function contestazioneComeFascicolo(
  p: PostVenditaAccessorio,
  foto: { acquirente: string[]; venditore: string[] },
): DisputeRecord | null {
  const c = p.contestazione;
  if (!c) return null;
  const chiusa = c.chiusaAt !== null;
  const lifecycle: DisputeLifecycleStatus = !chiusa
    ? c.risposta ? "documentazione_completa" : "attesa_venditore"
    : c.stato === "rimborsata" ? "risolta_acquirente" : c.stato === "risolta" ? "accordo" : "respinta";
  return {
    id: p.ordineId, order_id: p.ordineId, aperta_da: "", motivo: c.motivo, descrizione: c.descrizione,
    foto: foto.acquirente, stato: c.stato, esito_nota: c.esitoNota, apertura_at: c.apertaAt, chiusura_at: c.chiusaAt,
    venditore_scadenza_at: c.venditoreScadenzaAt, venditore_risposta_tipo: c.risposta?.tipo ?? null,
    venditore_risposta: c.risposta?.testo ?? null, venditore_foto: foto.venditore,
    venditore_risposta_at: c.risposta?.at ?? null, documentazione_completa_at: c.risposta?.at ?? null,
    lifecycle_status: lifecycle, review_started_at: null, resolution_kind: null,
    resolution_note: c.esitoNota, resolved_at: c.chiusaAt, resolution_version: 1,
  };
}
