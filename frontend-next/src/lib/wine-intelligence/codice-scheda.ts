// WI-011 — il codice di una scheda del catalogo è il LWIN-7 quando esiste, altrimenti l'UUID del vino canonico,
// che è l'identità stabile. Nessun codice viene composto o inventato: arriva dal database o non c'è.

export const LWIN7 = /^[0-9]{7}$/;
export const UUID_SCHEDA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const eCodiceScheda = (valore: unknown): valore is string =>
  typeof valore === "string" && (LWIN7.test(valore) || UUID_SCHEDA.test(valore));
