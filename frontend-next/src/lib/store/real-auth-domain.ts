"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { supabaseAuthService } from "@/services/auth-service";
import type { OAuthProvider, Result } from "@/services/types";
import { ruoloDaSessione } from "@/lib/auth/role";

export type AuthUser = { userId: string; email: string | null };

/**
 * Stato della dichiarazione di età sul profilo. Vale per qualunque metodo di
 * accesso: email, magic link, Google o Facebook non fanno differenza.
 * - `sconosciuto`: nessuna sessione, lettura non ancora completata, oppure
 *   lettura fallita — in nessuno di questi casi si blocca l'utente.
 * - `da_completare`: sessione attiva ma `profiles.dob` vuoto.
 * - `completo`: data di nascita dichiarata.
 */
export type StatoEta = "sconosciuto" | "da_completare" | "completo";

/**
 * Sessione e ruolo effettivi Supabase. Il selettore dimostrativo può
 * sostituirli soltanto quando la sua flag pubblica è esplicitamente attiva.
 */
export const useRealAuthDomain = () => {
  const [authUser, setAuthUser] = useState<AuthUser | null>(null);
  // Se Supabase non è configurato non c'è nulla da caricare: parte già a
  // false. Evita una setState sincrona nel corpo dell'effect sotto.
  const [authLoading, setAuthLoading] = useState(() => getSupabaseClient() !== null);
  const [authError, setAuthError] = useState<string | null>(null);
  // Data di nascita letta dal profilo, memorizzata insieme all'utente a cui
  // appartiene: così `statoEta` sotto è interamente derivato e non serve
  // resettarlo con una setState sincrona quando la sessione cambia.
  const [dobLetta, setDobLetta] = useState<{ userId: string; dob: string | null } | null>(null);
  const [ruoliLetti, setRuoliLetti] = useState<{ userId: string; ruoli: string[] } | null>(null);

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

  // Legge la data di nascita dichiarata ogni volta che cambia l'utente,
  // qualunque sia il metodo di accesso: un profilo senza `dob` va completato
  // prima di poter usare il resto del sito (vedi AgeGate).
  useEffect(() => {
    if (!authUser) return;

    let active = true;
    const userId = authUser.userId;
    supabaseAuthService.dataNascitaProfilo(userId).then((esito) => {
      if (!active) return;
      // In caso di errore di lettura non registriamo nulla: `statoEta` resta
      // "sconosciuto" e la guardia non blocca l'utente su un dato che non
      // abbiamo potuto verificare.
      if (esito.ok) setDobLetta({ userId, dob: esito.data });
    });

    return () => {
      active = false;
    };
  }, [authUser]);

  useEffect(() => {
    if (!authUser) return;

    let active = true;
    const userId = authUser.userId;
    supabaseAuthService.ruoliProfilo(userId).then((esito) => {
      if (active && esito.ok) setRuoliLetti({ userId, ruoli: esito.data });
    });
    return () => {
      active = false;
    };
  }, [authUser]);

  // Interamente derivato: nessuna sessione, oppure lettura non ancora
  // disponibile per *questo* utente, significano "sconosciuto".
  const statoEta: StatoEta =
    !authUser || dobLetta?.userId !== authUser.userId
      ? "sconosciuto"
      : dobLetta.dob
        ? "completo"
        : "da_completare";
  const ruoliCorrenti =
    authUser && ruoliLetti?.userId === authUser.userId ? ruoliLetti.ruoli : [];
  const authRuolo = ruoloDaSessione(authUser, ruoliCorrenti);

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

  const authAccediConOAuth = useCallback(async (provider: OAuthProvider) => {
    setAuthError(null);
    const result = await supabaseAuthService.accediConOAuth(provider);
    if (!result.ok) setAuthError(result.error);
    return result;
  }, []);

  const authSalvaDataNascita = useCallback(
    async (dataNascita: string): Promise<Result<void>> => {
      if (!authUser) return { ok: false, error: "Nessuna sessione attiva." };
      setAuthError(null);
      const result = await supabaseAuthService.salvaDataNascita(authUser.userId, dataNascita);
      if (!result.ok) {
        setAuthError(result.error);
        return result;
      }
      setDobLetta({ userId: authUser.userId, dob: dataNascita });
      return result;
    },
    [authUser],
  );

  const authLogout = useCallback(async () => {
    await supabaseAuthService.logout();
    setAuthUser(null);
    setDobLetta(null);
    setRuoliLetti(null);
  }, []);

  return {
    authUser,
    authRuolo,
    authLoading,
    authError,
    authClearError,
    authRegistra,
    authLogin,
    authInviaMagicLink,
    authVerificaEmail,
    authAccediConOAuth,
    authStatoEta: statoEta,
    authSalvaDataNascita,
    authLogout,
  };
};
