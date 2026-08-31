"use client";

import { getSupabaseClient } from "@/lib/supabase/client";
import {
  PERCORSO_REIMPOSTA_PASSWORD,
  urlRitornoAuthDalBrowser,
  type ContestoRitornoAuth,
} from "@/lib/auth/ritorno-auth";
import { classificaErroreAuth } from "@/lib/auth/errori-auth";
import type { AuthService, OAuthProvider, Result } from "./types";

/**
 * Supabase non configurato è un **codice**, non più la frase che nominava le due
 * variabili d'ambiente e il percorso del file in cui metterle. Quel testo era
 * scritto per chi sviluppa e finiva in pagina davanti a chi usa il sito: un
 * dettaglio di configurazione mostrato a un utente che non può farci nulla.
 */
const NON_CONFIGURATO = "configurazione-assente" as const;

/**
 * Implementazione reale di AuthService su Supabase Auth (email/password +
 * magic link). Google/Apple restano fuori scope: Fase 5b, quando saranno
 * disponibili le credenziali OAuth.
 *
 * Nessun `error.message` di Supabase esce da questo file. Ogni ramo di errore
 * passa da `classificaErroreAuth`, che riduce il testo del provider a una delle
 * famiglie del vocabolario applicativo; le parole mostrate all'utente le
 * sceglie `lib/auth/errori-auth`, in un punto solo.
 *
 * La creazione della riga in public.profiles NON avviene qui via INSERT
 * diretto: è delegata al trigger handle_new_user() (supabase/migrations),
 * eseguito lato database alla creazione dell'utente in auth.users. Questo
 * evita di dipendere da una sessione autenticata subito dopo signUp(),
 * che potrebbe non esistere ancora se la conferma email è richiesta dal
 * progetto Supabase.
 */
export const supabaseAuthService: AuthService = {
  async registra({ email, password, dataNascita, username }, contesto) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { username, dob: dataNascita },
        // Riporta la conferma sull'origine da cui è partita la registrazione, e
        // sul percorso che sa scambiare il `code` per una sessione — non
        // sull'origine nuda. Vedi lib/auth/ritorno-auth.ts: con il flusso PKCE
        // il link di conferma torna con un `?code=` che solo /auth/callback
        // scambia, e la voce in elenco su Supabase per il dominio beta è
        // proprio `<origine>/auth/callback`. Mandare l'origine nuda non dava un
        // errore: Supabase non trovava corrispondenza fra i Redirect URLs e
        // ricadeva in silenzio sul Site URL, cioè http://localhost:3000, dove
        // l'utente vedeva una pagina irraggiungibile e credeva che la
        // registrazione fosse fallita — mentre la conferma era già avvenuta.
        emailRedirectTo: urlRitornoAuthDalBrowser(contesto),
      },
    });
    if (error) return { ok: false, error: classificaErroreAuth(error, "registrazione") };
    if (!data.user) return { ok: false, error: "generico" };
    return {
      ok: true,
      data: {
        userId: data.user.id,
        sessioneAttiva: data.session !== null,
        // Serve attendere una conferma solo se l'email non risulta già
        // confermata: con l'auto-conferma attiva `email_confirmed_at` è
        // valorizzato subito e non arriverà nessuna email da cliccare.
        confermaEmailRichiesta: data.session === null && !data.user.email_confirmed_at,
      },
    };
  },

  async verificaEmail(tokenHash) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: "signup",
    });
    if (error) return { ok: false, error: classificaErroreAuth(error, "scambio-codice") };
    return { ok: true, data: undefined };
  },

  async login(email, password) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { ok: false, error: classificaErroreAuth(error, "login") };
    return { ok: true, data: { userId: data.user.id } };
  },

  async inviaMagicLink(email, contesto) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    // Stessa destinazione della registrazione, e per la stessa ragione: il
    // magic link rientra con un `code` da scambiare, non con una sessione
    // pronta. Vedi lib/auth/ritorno-auth.ts.
    const redirectTo = urlRitornoAuthDalBrowser(contesto);
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: redirectTo ? { emailRedirectTo: redirectTo } : undefined,
    });
    if (error) return { ok: false, error: classificaErroreAuth(error, "magic-link") };
    return { ok: true, data: undefined };
  },

  async inviaRecuperoPassword(email) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    // Stessa destinazione di rientro degli altri flussi, con `next` che porta
    // alla pagina di reimpostazione: il link torna su /auth/callback, che
    // scambia il code e apre la sessione di recupero, poi manda l'utente lì.
    // Nessun secondo punto di scambio, nessuna seconda regola d'origine.
    const redirectTo = urlRitornoAuthDalBrowser({ next: PERCORSO_REIMPOSTA_PASSWORD });
    const { error } = await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo ? { redirectTo } : undefined,
    );
    if (error) return { ok: false, error: classificaErroreAuth(error, "recupero-password") };
    return { ok: true, data: undefined };
  },

  async aggiornaPasswordNuova(password) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    // La password non passa da nessuna tabella di questo progetto e non viene
    // registrata da nessuna parte: la riceve Supabase Auth, che è l'unico
    // posto in cui esiste. Qui non c'è nulla da salvare né da loggare.
    const { error } = await supabase.auth.updateUser({ password });
    if (error) return { ok: false, error: classificaErroreAuth(error, "aggiornamento-password") };
    return { ok: true, data: undefined };
  },

  async accediConOAuth(provider: OAuthProvider, contesto?: ContestoRitornoAuth) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    // origine dinamica e non un valore fisso, per la stessa ragione del bug
    // mobile risolto in Fase 5a: un URL cablato su localhost non è
    // raggiungibile da un altro dispositivo. Fuori dal browser non c'è
    // un'origine dell'utente da cui partire, ed è l'unico caso in cui il
    // modulo non risponde.
    const redirectTo = urlRitornoAuthDalBrowser(contesto);
    if (!redirectTo) {
      // Fuori dal browser non c'è un gesto dell'utente da completare: è un
      // avvio non riuscito, non una configurazione mancante.
      return { ok: false, error: "oauth-avvio-non-riuscito" };
    }

    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo },
    });
    if (error) return { ok: false, error: classificaErroreAuth(error, "oauth-avvio") };

    // supabase-js normalmente reindirizza da sé; se per qualche motivo
    // restituisce solo l'URL senza navigare, lo seguiamo esplicitamente
    // invece di lasciare l'utente su una pagina che sembra non reagire.
    if (data?.url && window.location.href !== data.url) {
      window.location.assign(data.url);
    }
    return { ok: true, data: undefined };
  },

  async signInWithGoogle(contesto) {
    return supabaseAuthService.accediConOAuth("google", contesto);
  },

  async signInWithFacebook(contesto) {
    return supabaseAuthService.accediConOAuth("facebook", contesto);
  },

  async logout() {
    const supabase = getSupabaseClient();
    if (!supabase) return;
    await supabase.auth.signOut();
  },

  async utenteCorrente() {
    const supabase = getSupabaseClient();
    if (!supabase) return null;

    const { data } = await supabase.auth.getSession();
    if (!data.session) return null;
    return { userId: data.session.user.id, email: data.session.user.email ?? null };
  },

  /**
   * Unico metodo che non parla il vocabolario degli errori di ingresso: il suo
   * esito non arriva mai in pagina. `real-auth-domain` legge i ruoli e, se la
   * lettura fallisce, resta sull'insieme vuoto — cioè sul ruolo meno
   * privilegiato. Non c'è un messaggio da mostrare, quindi non c'è un codice da
   * scegliere; c'è solo da non far uscire il testo del database.
   */
  async ruoliProfilo(userId) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NON_CONFIGURATO };

    // Niente select("*"): il grant espone soltanto user_id e role, e la RLS
    // limita la lettura alla riga di auth.uid(). Il parametro serve solo a
    // rendere esplicito quale sessione stiamo risolvendo; non amplia la policy.
    const { data, error } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", userId);
    if (error) return { ok: false, error: "ruoli-non-letti" };
    return {
      ok: true,
      data: (data ?? [])
        .map((riga) => riga.role)
        .filter((ruolo): ruolo is string => typeof ruolo === "string"),
    };
  },

  // Profilo: vedi services/profile-service.ts. Questo servizio si ferma
  // all'autenticazione e ai ruoli.
} satisfies AuthService;

export type { Result };
