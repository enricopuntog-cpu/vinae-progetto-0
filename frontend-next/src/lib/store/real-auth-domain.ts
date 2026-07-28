"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { supabaseAuthService } from "@/services/auth-service";
import type { Result } from "@/services/types";

export type AuthUser = { userId: string; email: string | null };

/**
 * Sessione reale Supabase (Fase 5a), separata dal demo-switcher `ruolo` di
 * auth-domain.ts. Quel demo-switcher (Ospite/Utente/Admin) resta invariato:
 * serve ancora a mostrare le viste degli altri domini non ancora migrati
 * (moderazione, cantina, ecc.), che restano su dati mock. Le due cose
 * convivono senza sovrapporsi finché quei domini non vengono migrati a
 * loro volta.
 */
export function useRealAuthDomain() {
  const [authUser, setAuthUser] = useState<AuthUser | null>(null);
  // Se Supabase non è configurato non c'è nulla da caricare: parte già a
  // false. Evita una setState sincrona nel corpo dell'effect sotto.
  const [authLoading, setAuthLoading] = useState(() => getSupabaseClient() !== null);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabaseClient();
    if (!supabase) return;

    let active = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      setAuthUser(
        data.session
          ? { userId: data.session.user.id, email: data.session.user.email ?? null }
          : null,
      );
      setAuthLoading(false);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, session) => {
      setAuthUser(
        session ? { userId: session.user.id, email: session.user.email ?? null } : null,
      );
      setAuthLoading(false);
    });

    return () => {
      active = false;
      subscription.subscription.unsubscribe();
    };
  }, []);

  const authClearError = useCallback(() => setAuthError(null), []);

  const authRegistra = useCallback(
    async (input: { email: string; password: string; dataNascita: string; username: string }) => {
      setAuthError(null);
      const result = await supabaseAuthService.registra(input);
      if (!result.ok) setAuthError(result.error);
      return result;
    },
    [],
  );

  const authLogin = useCallback(async (email: string, password: string) => {
    setAuthError(null);
    const result = await supabaseAuthService.login(email, password);
    if (!result.ok) setAuthError(result.error);
    return result;
  }, []);

  const authInviaMagicLink = useCallback(async (email: string) => {
    setAuthError(null);
    const result = await supabaseAuthService.inviaMagicLink(email);
    if (!result.ok) setAuthError(result.error);
    return result;
  }, []);

  const authVerificaEmail = useCallback(
    (tokenHash: string): Promise<Result<void>> => supabaseAuthService.verificaEmail(tokenHash),
    [],
  );

  const authLogout = useCallback(async () => {
    await supabaseAuthService.logout();
    setAuthUser(null);
  }, []);

  return {
    authUser,
    authLoading,
    authError,
    authClearError,
    authRegistra,
    authLogin,
    authInviaMagicLink,
    authVerificaEmail,
    authLogout,
  };
}
