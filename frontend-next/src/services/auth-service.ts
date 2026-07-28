"use client";

import { getSupabaseClient } from "@/lib/supabase/client";
import type { AuthService, Result } from "./types";

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
      },
    });
    if (error) return { ok: false, error: error.message };
    if (!data.user) return { ok: false, error: "Registrazione non riuscita." };
    return { ok: true, data: { userId: data.user.id } };
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

    const redirectTo =
      typeof window !== "undefined" ? window.location.origin : undefined;
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: redirectTo ? { emailRedirectTo: redirectTo } : undefined,
    });
    if (error) return { ok: false, error: error.message };
    return { ok: true, data: undefined };
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
} satisfies AuthService;

export type { Result };
