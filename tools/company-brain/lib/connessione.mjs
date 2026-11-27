// WI-015 — guardie sulla stringa di connessione dei processi del Company Brain (worker e mittente dei segnali).
// Fail-closed: la credenziale deve essere un login dedicato, mai il proprietario o una chiave amministrativa, e fuori
// da loopback serve TLS verificato. La stringa non viene mai stampata.

import { assertVerifiedTlsUrl, tlsOptions } from "../../wine-catalog/lib/cloud-tls.mjs";

const VIETATI = /^(postgres|authenticator|anon|authenticated|service_role|supabase_|catalog_)/;

export function controllaConnessione(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    return { ok: false, motivo: "stringa di connessione non valida" };
  }
  if (!/^postgres(ql)?:$/.test(u.protocol)) return { ok: false, motivo: "serve una connessione PostgreSQL" };
  // Sul pooler di Supabase l'utente e «ruolo.riferimento-progetto».
  const utente = decodeURIComponent(u.username).split(".")[0];
  if (!utente || VIETATI.test(utente)) return { ok: false, motivo: "serve il login dedicato, non un ruolo amministrativo" };
  const loopback = ["127.0.0.1", "localhost", "[::1]"].includes(u.hostname);
  if (!loopback && u.searchParams.get("sslmode") !== "verify-full") {
    return { ok: false, motivo: "fuori da loopback serve sslmode=verify-full" };
  }
  return { ok: true, utente };
}

// WI-016 — fuori da loopback il TLS e verificato contro la CA del progetto (VINEA_DB_CA_PEM): catena e nome del server,
// con le stesse guardie gia provate dal runner del catalogo (un solo sslmode=verify-full, nessun altro parametro TLS).
// Senza CA non si ripiega su una verifica piu debole: ci si ferma.
export function opzioniConnessione(url, env = process.env) {
  const controllo = controllaConnessione(url);
  if (!controllo.ok) return controllo;
  const host = new URL(url).hostname;
  if (["127.0.0.1", "localhost", "[::1]"].includes(host)) return { ok: true, utente: controllo.utente, opzioni: { url } };
  try {
    assertVerifiedTlsUrl(url);
    return { ok: true, utente: controllo.utente, opzioni: { url, tls: tlsOptions(env.VINEA_DB_CA_PEM ?? "") } };
  } catch (errore) {
    const messaggio = String(errore?.message ?? "");
    return { ok: false, motivo: messaggio.includes("CA") ? "serve la CA del progetto in VINEA_DB_CA_PEM, valida e senza chiavi private" : "parametri TLS non ammessi: un solo sslmode=verify-full" };
  }
}
