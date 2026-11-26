// WI-015 — guardie sulla stringa di connessione dei processi del Company Brain (worker e mittente dei segnali).
// Fail-closed: la credenziale deve essere un login dedicato, mai il proprietario o una chiave amministrativa, e fuori
// da loopback serve TLS verificato. La stringa non viene mai stampata.

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
