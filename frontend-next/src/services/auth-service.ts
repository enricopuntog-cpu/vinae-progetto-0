"use client";

import { getSupabaseClient } from "@/lib/supabase/client";
import { urlRitornoAuthDalBrowser } from "@/lib/auth/ritorno-auth";
import type { AuthService, OAuthProvider, Result } from "./types";

const NOT_CONFIGURED_ERROR =
  "Supabase non configurato: imposta NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY in frontend-next/.env.local.";

/**
 * Implementazione reale di AuthService su Supabase Auth (email/password +
 * magic link). Google/Apple restano fuori scope: Fase 5b, quando saranno
 * disponibili le credenziali OAuth.
 *
 * La creazione della riga in public.profiles NON avviene qui via INSERT
 * diretto: è delegata al trigger handle_new_user() (supabase/migrations),
 * eseguito lato database alla creazione dell'utente in auth.users. Questo
 * evita di dipendere da una sessione autenticata subito dopo signUp(),
 * che potrebbe non esistere ancora se la conferma email è richiesta dal
 * progetto Supabase.
 */
export const supabaseAuthService: AuthService = {
  async registra({ email, password, dataNascita, username }) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

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
        emailRedirectTo: urlRitornoAuthDalBrowser(),
      },
    });
    if (error) return { ok: false, error: error.message };
    if (!data.user) return { ok: false, error: "Registrazione non riuscita." };
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
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: "signup",
    });
    if (error) return { ok: false, error: error.message };
    return { ok: true, data: undefined };
  },

  async login(email, password) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { ok: false, error: error.message };
    return { ok: true, data: { userId: data.user.id } };
  },

  async inviaMagicLink(email) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

    // Stessa destinazione della registrazione, e per la stessa ragione: il
    // magic link rientra con un `code` da scambiare, non con una sessione
    // pronta. Vedi lib/auth/ritorno-auth.ts.
    const redirectTo = urlRitornoAuthDalBrowser();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: redirectTo ? { emailRedirectTo: redirectTo } : undefined,
    });
    if (error) return { ok: false, error: error.message };
    return { ok: true, data: undefined };
  },

  async accediConOAuth(provider: OAuthProvider) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

    // origine dinamica e non un valore fisso, per la stessa ragione del bug
    // mobile risolto in Fase 5a: un URL cablato su localhost non è
    // raggiungibile da un altro dispositivo. Fuori dal browser non c'è
    // un'origine dell'utente da cui partire, ed è l'unico caso in cui il
    // modulo non risponde.
    const redirectTo = urlRitornoAuthDalBrowser();
    if (!redirectTo) {
      return { ok: false, error: "Il login social si avvia solo dal browser." };
    }

    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo },
    });
    if (error) return { ok: false, error: error.message };

    // supabase-js normalmente reindirizza da sé; se per qualche motivo
    // restituisce solo l'URL senza navigare, lo seguiamo esplicitamente
    // invece di lasciare l'utente su una pagina che sembra non reagire.
    if (data?.url && window.location.href !== data.url) {
      window.location.assign(data.url);
    }
    return { ok: true, data: undefined };
  },

  async signInWithGoogle() {
    return supabaseAuthService.accediConOAuth("google");
  },

  async signInWithFacebook() {
    return supabaseAuthService.accediConOAuth("facebook");
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

  async ruoliProfilo(userId) {
    const supabase = getSupabaseClient();
    if (!supabase) return { ok: false, error: NOT_CONFIGURED_ERROR };

    // Niente select("*"): il grant espone soltanto user_id e role, e la RLS
    // limita la lettura alla riga di auth.uid(). Il parametro serve solo a
    // rendere esplicito quale sessione stiamo risolvendo; non amplia la policy.
    const { data, error } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", userId);
    if (error) return { ok: false, error: error.message };
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
