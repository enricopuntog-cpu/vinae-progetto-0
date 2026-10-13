import type {
  Partner,
  PartnerAdmin,
  PartnerAzioneAdmin,
  PartnerDatiInput,
  PartnerInvito,
  PartnerInvitoStato,
  PartnerStato,
  PartnerTipologia,
} from "@/services/types";

/**
 * Vinea Partner — Blocco A: logica pura condivisa da adattatore e interfacce.
 *
 * Niente qui è una regola autorevole. Stati, transizioni, destinatario
 * dell'invito e validità della partita IVA li decide il database
 * (`private.partners_guard`, porte `partner_*`); queste funzioni servono solo a
 * spiegare all'utente, prima della chiamata, ciò che il server gli direbbe.
 */

export const PARTNER_STATI: readonly PartnerStato[] = [
  "invitato",
  "in_verifica",
  "attivo",
  "sospeso",
  "revocato",
];

export const PARTNER_TIPOLOGIE: ReadonlyArray<{ value: PartnerTipologia; label: string }> = [
  { value: "enoteca", label: "Enoteca" },
  { value: "ristorazione", label: "Ristorazione" },
  { value: "cantina_produttore", label: "Cantina / produttore" },
  { value: "distribuzione", label: "Distribuzione" },
  { value: "altro", label: "Altro" },
];

const INVITO_STATI: readonly PartnerInvitoStato[] = ["valido", "usato", "revocato", "scaduto"];

export const ETICHETTA_STATO_PARTNER: Record<PartnerStato, string> = {
  invitato: "Da completare",
  in_verifica: "In verifica",
  attivo: "Attivo",
  sospeso: "Sospeso",
  revocato: "Revocato",
};

export const SPIEGAZIONE_STATO_PARTNER: Record<PartnerStato, string> = {
  invitato:
    "Hai accettato l'invito. Compila i dati della tua attività e inviali alla verifica di Vinea.",
  in_verifica:
    "I dati sono stati inviati e non sono più modificabili. L'amministrazione Vinea li sta verificando.",
  attivo:
    "La tua attività è un Partner Vinea approvato e la tua vetrina è pubblica sul tuo profilo. Condizioni commerciali e vendita professionale non sono ancora aperte: ti avviseremo noi.",
  sospeso:
    "Il Partner è temporaneamente sospeso dall'amministrazione Vinea. Leggi il motivo qui sotto o contatta Vinea.",
  revocato:
    "Il Partner è stato revocato e non è più attivo. Finché Vinea non ti riabilita non puoi vendere, nemmeno da privato; gli ordini già pagati proseguono normalmente. Per tornare Partner serve un nuovo invito di Vinea.",
};

export const ETICHETTA_STATO_INVITO: Record<PartnerInvitoStato, string> = {
  valido: "Valido",
  usato: "Usato",
  revocato: "Revocato",
  scaduto: "Scaduto",
};

export const ETICHETTA_AZIONE: Record<PartnerAzioneAdmin, string> = {
  approva: "Approva",
  restituisci: "Restituisci per correzioni",
  sospendi: "Sospendi",
  riattiva: "Riattiva",
  revoca: "Revoca",
};

/** Le azioni che la porta admin accetterebbe da questo stato. */
export function azioniAmmesse(stato: PartnerStato): PartnerAzioneAdmin[] {
  switch (stato) {
    case "invitato":
      return ["revoca"];
    case "in_verifica":
      return ["approva", "restituisci", "revoca"];
    case "attivo":
      return ["sospendi", "revoca"];
    case "sospeso":
      return ["riattiva", "revoca"];
    case "revocato":
      return [];
  }
}

export function azioneRichiedeMotivo(azione: PartnerAzioneAdmin): boolean {
  return azione === "restituisci" || azione === "sospendi" || azione === "revoca";
}

// ---- Parsing (l'RPC risponde jsonb: si valida, non si assume) ----------

const testo = (v: unknown): string | null => (typeof v === "string" ? v : null);

const eStato = (v: unknown): v is PartnerStato =>
  typeof v === "string" && (PARTNER_STATI as readonly string[]).includes(v);

const eTipologia = (v: unknown): v is PartnerTipologia =>
  typeof v === "string" && PARTNER_TIPOLOGIE.some((t) => t.value === v);

export function parsePartner(raw: unknown): Partner | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const id = testo(r.id);
  const createdAt = testo(r.created_at);
  const updatedAt = testo(r.updated_at);
  if (!id || !eStato(r.stato) || !createdAt || !updatedAt) return null;
  return {
    id,
    stato: r.stato,
    ragioneSociale: testo(r.ragione_sociale),
    nomeCommerciale: testo(r.nome_commerciale),
    partitaIva: testo(r.partita_iva),
    paese: testo(r.paese) ?? "IT",
    sedeIndirizzo: testo(r.sede_indirizzo),
    sedeCap: testo(r.sede_cap),
    sedeCitta: testo(r.sede_citta),
    sedeProvincia: testo(r.sede_provincia),
    emailCommerciale: testo(r.email_commerciale),
    tipologia: eTipologia(r.tipologia) ? r.tipologia : null,
    inviatoVerificaAt: testo(r.inviato_verifica_at),
    attivoDal: testo(r.attivo_dal),
    sospesoAt: testo(r.sospeso_at),
    revocatoAt: testo(r.revocato_at),
    ultimoMotivo: testo(r.ultimo_motivo),
    createdAt,
    updatedAt,
    venditeBloccate: r.vendite_bloccate === true,
  };
}

export function parsePartnerAdmin(raw: unknown): PartnerAdmin | null {
  const base = parsePartner(raw);
  if (!base) return null;
  const r = raw as Record<string, unknown>;
  const titolareId = testo(r.titolare_id);
  const invitoEmail = testo(r.invito_email);
  if (!titolareId || !invitoEmail) return null;
  return {
    ...base,
    titolareId,
    titolareEmail: testo(r.titolare_email),
    titolareUsername: testo(r.titolare_username),
    invitoEmail,
  };
}

export function parseInvito(raw: unknown): PartnerInvito | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const id = testo(r.id);
  const email = testo(r.email);
  const scadeAt = testo(r.scade_at);
  const createdAt = testo(r.created_at);
  const stato = r.stato;
  if (!id || !email || !scadeAt || !createdAt) return null;
  if (typeof stato !== "string" || !(INVITO_STATI as readonly string[]).includes(stato)) return null;
  return {
    id,
    email,
    stato: stato as PartnerInvitoStato,
    scadeAt,
    createdAt,
    usatoAt: testo(r.usato_at),
    revocatoAt: testo(r.revocato_at),
    motivoRevoca: testo(r.motivo_revoca),
    notaAdmin: testo(r.nota_admin),
    partnerId: testo(r.partner_id),
  };
}

// ---- Token d'invito ------------------------------------------------------
//
// Il token viaggia nel frammento (`#t=`), che il browser non invia al server:
// non finisce nei log di Netlify né nell'header Referer.

export const FORMATO_TOKEN = /^[0-9a-f]{64}$/;

export function linkInvito(origin: string, token: string): string {
  return `${origin.replace(/\/+$/, "")}/partner/invito#t=${token}`;
}

export function tokenDaFrammento(hash: string): string | null {
  const parametri = new URLSearchParams(hash.replace(/^#/, ""));
  const token = (parametri.get("t") ?? "").trim().toLowerCase();
  return FORMATO_TOKEN.test(token) ? token : null;
}

// ---- Validazione di cortesia (il server rivaluta tutto) ------------------

export function normalizzaPartitaIva(valore: string): string {
  const compatta = valore.replace(/\s+/g, "").toUpperCase();
  return compatta.startsWith("IT") ? compatta.slice(2) : compatta;
}

/** Stesso algoritmo di `private.partita_iva_valida`. */
export function partitaIvaValida(valore: string): boolean {
  if (!/^[0-9]{11}$/.test(valore)) return false;
  let somma = 0;
  for (let i = 0; i < 10; i++) {
    let cifra = Number(valore[i]);
    if (i % 2 === 1) {
      cifra *= 2;
      if (cifra > 9) cifra -= 9;
    }
    somma += cifra;
  }
  return (10 - (somma % 10)) % 10 === Number(valore[10]);
}

export type CampoPartner = keyof PartnerDatiInput;

/** Errori per campo, per i soli campi compilati; `completo` per la consegna. */
export function validaDatiPartner(dati: PartnerDatiInput): {
  errori: Partial<Record<CampoPartner, string>>;
  completo: boolean;
} {
  const errori: Partial<Record<CampoPartner, string>> = {};
  const piva = normalizzaPartitaIva(dati.partitaIva);
  if (piva && !partitaIvaValida(piva)) errori.partitaIva = "Partita IVA non valida (11 cifre).";
  const email = dati.emailCommerciale.trim();
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    errori.emailCommerciale = "Email non valida.";
  }
  const cap = dati.sedeCap.trim();
  if (cap && !/^[0-9]{5}$/.test(cap)) errori.sedeCap = "Il CAP ha 5 cifre.";
  const provincia = dati.sedeProvincia.trim();
  if (provincia && !/^[A-Za-z]{2}$/.test(provincia)) errori.sedeProvincia = "Sigla di 2 lettere.";
  const ragione = dati.ragioneSociale.trim();
  if (ragione && ragione.length < 2) errori.ragioneSociale = "Troppo breve.";
  const nome = dati.nomeCommerciale.trim();
  if (nome && nome.length < 2) errori.nomeCommerciale = "Troppo breve.";
  const indirizzo = dati.sedeIndirizzo.trim();
  if (indirizzo && indirizzo.length < 3) errori.sedeIndirizzo = "Troppo breve.";
  const citta = dati.sedeCitta.trim();
  if (citta && citta.length < 2) errori.sedeCitta = "Troppo breve.";

  const completo =
    Boolean(ragione && nome && piva && email && cap && provincia && indirizzo && citta) &&
    dati.tipologia !== null;
  return { errori, completo };
}

export function datiDaPartner(p: Partner | null): PartnerDatiInput {
  return {
    ragioneSociale: p?.ragioneSociale ?? "",
    nomeCommerciale: p?.nomeCommerciale ?? "",
    partitaIva: p?.partitaIva ?? "",
    emailCommerciale: p?.emailCommerciale ?? "",
    tipologia: p?.tipologia ?? null,
    sedeIndirizzo: p?.sedeIndirizzo ?? "",
    sedeCap: p?.sedeCap ?? "",
    sedeCitta: p?.sedeCitta ?? "",
    sedeProvincia: p?.sedeProvincia ?? "",
  };
}

// ---- Errori --------------------------------------------------------------
//
// Le porte segnalano i casi previsti con un HINT stabile. Si mostra una frase
// scritta qui, mai il testo di PostgreSQL: un dettaglio di schema in pagina
// racconta il database a chi guarda.

const MESSAGGI_HINT: Record<string, string> = {
  invito_non_valido: "Questo link d'invito non è valido. Controlla di averlo copiato per intero.",
  invito_usato: "Questo invito è già stato utilizzato.",
  invito_revocato: "Questo invito è stato revocato da Vinea.",
  invito_scaduto: "Questo invito è scaduto. Chiedi a Vinea un nuovo invito.",
  invito_email_diversa:
    "Questo invito è intestato a un altro indirizzo email. Accedi con l'account che usa l'indirizzo a cui è stato inviato.",
  email_non_confermata: "Conferma prima il tuo indirizzo email, poi riapri il link d'invito.",
  partner_gia_presente: "Esiste già un Partner aperto per questo account.",
  invito_gia_valido: "Esiste già un invito valido per questa email: revocalo prima di crearne un altro.",
  partner_non_trovato: "Partner non trovato.",
  dati_congelati: "I dati sono già stati inviati alla verifica e non sono più modificabili.",
  dati_incompleti: "Completa tutti i campi prima di inviare i dati alla verifica.",
  partita_iva_gia_registrata: "Questa partita IVA è già registrata per un altro Partner.",
  transizione_non_ammessa: "Questa azione non è ammessa nello stato attuale. Ricarica la pagina.",
  titolare_rimosso: "Il titolare di questo Partner non è più attivo su Vinea.",
  // Vetrina (Blocco B).
  vetrina_non_modificabile: "La vetrina non è modificabile nello stato attuale del Partner.",
  utente_non_attivo: "Il tuo account non può pubblicare contenuti in questo momento.",
  presentazione_lunga: "La presentazione può avere al massimo 160 caratteri.",
  descrizione_lunga: "La descrizione può avere al massimo 2000 caratteri.",
  troppe_foto: "Puoi pubblicare al massimo quattro fotografie.",
  media_duplicato: "La stessa immagine è stata usata due volte.",
  media_non_valido: "Una delle immagini non appartiene alla tua vetrina. Caricala di nuovo.",
  media_non_trovato: "Una delle immagini non è stata trovata. Caricala di nuovo.",
  partner_checkout_non_disponibile: "Gli acquisti da Partner Vinea non sono ancora disponibili.",
  // Sicurezza Partner (revoca).
  partner_revocato: "Questo account non può vendere finché Vinea non lo riabilita.",
};

export type ErroreRpc = { code?: string; message?: string; hint?: string | null } | null;

export function messaggioErrorePartner(errore: ErroreRpc, ricaduta: string): string {
  const hint = errore?.hint ?? "";
  if (hint && MESSAGGI_HINT[hint]) return MESSAGGI_HINT[hint];
  // 22023 è la classe che le porte usano per i propri controlli d'ingresso,
  // con frasi scritte per chi le legge («Partita IVA non valida.»).
  if (errore?.code === "22023") {
    return errore.message || "Alcuni dati non sono validi. Controlla i campi e riprova.";
  }
  if (errore?.code === "42501") return "Operazione non consentita.";
  return ricaduta;
}
