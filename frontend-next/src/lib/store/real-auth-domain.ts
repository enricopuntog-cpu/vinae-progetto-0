"use client";

import { useCallback, useEffect, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { supabaseAuthService } from "@/services/auth-service";
import { supabaseProfileService } from "@/services/profile-service";
import type { OAuthProvider, ProfiloCorrente, ProfiloModifica, Result } from "@/services/types";
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
 * Profilo letto, memorizzato insieme all'utente a cui appartiene: così tutto
 * ciò che ne deriva è calcolato e non serve azzerarlo con una setState sincrona
 * quando la sessione cambia.
 *
 * `letto` distingue «lettura riuscita» da «lettura fallita», che non è un
 * dettaglio: un errore di rete non deve diventare un «questo profilo non ha la
 * data di nascita» e mandare l'utente a /completa-profilo per un dato che non
 * abbiamo potuto verificare.
 */
type ProfiloInMemoria = { userId: string; profilo: ProfiloCorrente | null; letto: boolean };

/**
 * Sessione, profilo e ruolo effettivi Supabase. Il selettore dimostrativo può
 * sostituirli soltanto quando la sua flag pubblica è esplicitamente attiva.
 */
export const useRealAuthDomain = () => {
  const [authUser, setAuthUser] = useState<AuthUser | null>(null);
  // Se Supabase non è configurato non c'è nulla da caricare: parte già a
  // false. Evita una setState sincrona nel corpo dell'effect sotto.
  const [authLoading, setAuthLoading] = useState(() => getSupabaseClient() !== null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [profiloLetto, setProfiloLetto] = useState<ProfiloInMemoria | null>(null);
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

  /**
   * Una lettura sola per l'intero profilo, non una per campo. Prima erano due
   * chiamate distinte — data di nascita e nome utente — che tornavano pezzi
   * della stessa riga e potevano disallinearsi fra loro; ora la riga è una e la
   * schermata /account la trova già pronta.
   */
  useEffect(() => {
    if (!authUser) return;

    let active = true;
    const userId = authUser.userId;
    supabaseProfileService.leggiProfiloCorrente().then((esito) => {
      if (!active) return;
      setProfiloLetto({
        userId,
        profilo: esito.ok ? esito.data : null,
        letto: esito.ok,
      });
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
  const profiloCorrente =
    authUser && profiloLetto?.userId === authUser.userId ? profiloLetto : null;
  const statoEta: StatoEta =
    !profiloCorrente || !profiloCorrente.letto
      ? "sconosciuto"
      : profiloCorrente.profilo?.dob
        ? "completo"
        : "da_completare";
  const ruoliCorrenti =
    authUser && ruoliLetti?.userId === authUser.userId ? ruoliLetti.ruoli : [];
  const authRuolo = ruoloDaSessione(authUser, ruoliCorrenti);
  const authProfileLoading = Boolean(authUser && !profiloCorrente);
  const authProfileName = profiloCorrente?.profilo?.username || null;
  const authProfilo = profiloCorrente?.profilo ?? null;

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

  /**
   * Scrittura unica del profilo: chi la chiama passa i campi che cambia e li
   * riceve indietro già riletti dalla stessa istruzione, così lo stato locale
   * non è una copia ricostruita a mano di ciò che si spera sia stato scritto.
   *
   * Serve sia al completamento del profilo — nome utente e data di nascita
   * insieme, mai in due scritture separate — sia alla schermata /account.
   */
  const authAggiornaProfilo = useCallback(
    async (patch: ProfiloModifica): Promise<Result<ProfiloCorrente>> => {
      if (!authUser) return { ok: false, error: "Nessuna sessione attiva." };
      setAuthError(null);
      const result = await supabaseProfileService.aggiornaProfiloCorrente(patch);
      if (!result.ok) {
        setAuthError(result.error);
        return result;
      }
      setProfiloLetto({ userId: authUser.userId, profilo: result.data, letto: true });
      return result;
    },
    [authUser],
  );

  const authLogout = useCallback(async () => {
    await supabaseAuthService.logout();
    setAuthUser(null);
    setProfiloLetto(null);
    setRuoliLetti(null);
  }, []);

  return {
    authUser,
    authRuolo,
    authProfilo,
    authProfileName,
    authProfileLoading,
    authLoading,
    authError,
    authClearError,
    authRegistra,
    authLogin,
    authInviaMagicLink,
    authVerificaEmail,
    authAccediConOAuth,
    authStatoEta: statoEta,
    authAggiornaProfilo,
    authLogout,
  };
};
