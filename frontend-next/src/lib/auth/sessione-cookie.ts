import { cookies } from "next/headers";

/** `sb-<progetto>-auth-token`, anche a pezzi (`.0`, `.1`). Non il `code-verifier` del PKCE. */
const COOKIE_SESSIONE = /^sb-.+-auth-token(?:\.\d+)?$/;

export const eCookieDiSessione = (nome: string): boolean => COOKIE_SESSIONE.test(nome);

/**
 * Solo un suggerimento per impaginare il primo render: dice se conviene riservare lo spazio
 * di una pagina privata e precaricare la sua immagine, così un ospite non scarica nulla in
 * più. **Non prova l'identità** e non autorizza niente: il cookie può essere scaduto o
 * falso, e identità e permessi restano decisi da sessione verificata, RLS e porte del
 * database. Sbagliare costa al massimo un guscio di caricamento diverso.
 */
export const cookieSessionePresente = async (): Promise<boolean> =>
  (await cookies()).getAll().some((cookie) => eCookieDiSessione(cookie.name));
