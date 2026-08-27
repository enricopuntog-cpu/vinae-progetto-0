/**
 * Regole pure del dominio delle qualifiche professionali.
 *
 * NON SONO IL CONFINE DI FIDUCIA. Il confine è nel database: `create` e
 * `update` rifiutano un titolo vuoto, il bucket rifiuta un tipo non ammesso e
 * dieci megabyte superati, e i CHECK della tabella dei documenti legano il
 * percorso alla riga. Quello che segue serve a dire subito a chi compila cosa
 * non va, e a non spedire un file che il bucket rifiuterebbe comunque - non a
 * decidere se il dato è accettabile.
 *
 * Sono funzioni pure: nessuna rete, nessun Supabase, nessun DOM. Si testano da
 * sole, ed è il motivo per cui stanno qui e non dentro il servizio.
 */

/** Gli unici tipi che il bucket privato accetta. Stessa lista della migrazione. */
export const MIME_DOCUMENTO_QUALIFICA = [
  "application/pdf",
  "image/jpeg",
  "image/png",
] as const;

export type MimeDocumentoQualifica = (typeof MIME_DOCUMENTO_QUALIFICA)[number];

/** Dieci megabyte: lo stesso tetto del bucket e del CHECK sulla riga. */
export const DIMENSIONE_MASSIMA_DOCUMENTO = 10 * 1024 * 1024;

/** Il bucket privato. Non è mai pubblico e non produce URL diretti. */
export const BUCKET_QUALIFICHE = "professional-qualifications";

const LIMITE_TITOLO = 160;
const LIMITE_ENTE = 160;
const LIMITE_CREDENZIALE = 120;

const ESTENSIONE_PER_MIME: Record<MimeDocumentoQualifica, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
};

const FORMATO_DATA = /^\d{4}-\d{2}-\d{2}$/;
const FORMATO_PAESE = /^[A-Z]{2}$/;
const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export type CampiQualifica = {
  titolo: string;
  enteEmittente: string;
  paese: string;
  credentialReference: string;
  issuedOn: string;
  expiresOn: string;
};

export type QualificaNormalizzata = {
  titolo: string;
  enteEmittente: string;
  paese: string | null;
  credentialReference: string | null;
  issuedOn: string | null;
  expiresOn: string | null;
};

export type EsitoValidazione =
  | { valido: true; valore: QualificaNormalizzata }
  | { valido: false; errore: string };

const opzionale = (valore: string): string | null => {
  const pulito = valore.trim();
  return pulito === "" ? null : pulito;
};

const dataValida = (valore: string): boolean => {
  if (!FORMATO_DATA.test(valore)) return false;
  const istante = Date.parse(`${valore}T00:00:00Z`);
  if (Number.isNaN(istante)) return false;
  // `Date.parse` accetta il 31 febbraio spostandolo: il confronto smaschera la
  // data inesistente invece di registrarla come un altro giorno.
  return new Date(istante).toISOString().slice(0, 10) === valore;
};

/**
 * Normalizza e verifica i campi di una qualifica. Restituisce il valore già
 * pronto per la RPC — stringhe vuote diventate `null` — oppure il primo errore
 * leggibile, perché mostrarne sei insieme non aiuta chi compila.
 */
export const validaQualifica = (campi: CampiQualifica): EsitoValidazione => {
  const titolo = campi.titolo.trim();
  if (titolo.length < 2) {
    return { valido: false, errore: "Indica il titolo della qualifica." };
  }
  if (titolo.length > LIMITE_TITOLO) {
    return {
      valido: false,
      errore: `Il titolo non può superare ${LIMITE_TITOLO} caratteri.`,
    };
  }

  const enteEmittente = campi.enteEmittente.trim();
  if (enteEmittente.length < 2) {
    return { valido: false, errore: "Indica l'ente che ha rilasciato la qualifica." };
  }
  if (enteEmittente.length > LIMITE_ENTE) {
    return {
      valido: false,
      errore: `Il nome dell'ente non può superare ${LIMITE_ENTE} caratteri.`,
    };
  }

  const paeseGrezzo = opzionale(campi.paese);
  const paese = paeseGrezzo ? paeseGrezzo.toUpperCase() : null;
  if (paese !== null && !FORMATO_PAESE.test(paese)) {
    return {
      valido: false,
      errore: "Il paese va indicato con due lettere, ad esempio IT o FR.",
    };
  }

  const credentialReference = opzionale(campi.credentialReference);
  if (credentialReference !== null && credentialReference.length > LIMITE_CREDENZIALE) {
    return {
      valido: false,
      errore: `Il riferimento non può superare ${LIMITE_CREDENZIALE} caratteri.`,
    };
  }

  const issuedOn = opzionale(campi.issuedOn);
  if (issuedOn !== null && !dataValida(issuedOn)) {
    return { valido: false, errore: "La data di rilascio non è una data valida." };
  }

  const expiresOn = opzionale(campi.expiresOn);
  if (expiresOn !== null && !dataValida(expiresOn)) {
    return { valido: false, errore: "La data di scadenza non è una data valida." };
  }

  if (issuedOn !== null && expiresOn !== null && expiresOn < issuedOn) {
    return {
      valido: false,
      errore: "La scadenza non può precedere il rilascio.",
    };
  }

  return {
    valido: true,
    valore: { titolo, enteEmittente, paese, credentialReference, issuedOn, expiresOn },
  };
};

export type EsitoDocumento =
  | { valido: true; mime: MimeDocumentoQualifica; estensione: string }
  | { valido: false; errore: string };

/**
 * Il file, prima di partire. Il tipo dichiarato dal browser non è una prova —
 * `File.type` arriva dal sistema di chi carica — ma un file che già qui non
 * passa non ha motivo di occupare la rete: il bucket lo rifiuterebbe.
 */
export const validaDocumento = (file: File): EsitoDocumento => {
  const mime = file.type as MimeDocumentoQualifica;
  if (!MIME_DOCUMENTO_QUALIFICA.includes(mime)) {
    return {
      valido: false,
      errore: "Sono ammessi solo file PDF, JPG o PNG.",
    };
  }
  if (file.size <= 0) {
    return { valido: false, errore: "Il file è vuoto." };
  }
  if (file.size > DIMENSIONE_MASSIMA_DOCUMENTO) {
    return { valido: false, errore: "Il file supera 10 MB." };
  }
  return { valido: true, mime, estensione: ESTENSIONE_PER_MIME[mime] };
};

/**
 * Il percorso canonico `<titolare>/<qualifica>/<file>.<ext>`.
 *
 * Gli identificativi sono controllati qui perché una stringa arbitraria
 * costruirebbe un percorso in una cartella altrui. Il database rifiuterebbe
 * comunque la registrazione — il CHECK lega il percorso alle colonne della
 * riga — ma l'oggetto sarebbe già stato caricato: meglio non caricarlo.
 * Restituisce `null` invece di lanciare, così il chiamante decide il messaggio.
 */
export const percorsoDocumento = (
  ownerId: string,
  qualificationId: string,
  fileId: string,
  estensione: string,
): string | null => {
  if (
    !FORMATO_UUID.test(ownerId) ||
    !FORMATO_UUID.test(qualificationId) ||
    !FORMATO_UUID.test(fileId)
  ) {
    return null;
  }
  if (!Object.values(ESTENSIONE_PER_MIME).includes(estensione)) return null;
  return `${ownerId}/${qualificationId}/${fileId}.${estensione}`;
};
