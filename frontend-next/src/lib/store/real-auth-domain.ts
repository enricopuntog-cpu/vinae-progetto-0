"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { supabaseAuthService } from "@/services/auth-service";
import { supabaseProfileService } from "@/services/profile-service";
import type {
  OAuthProvider,
  ProfiloCorrente,
  ProfiloModifica,
  Result,
  ResultAuth,
} from "@/services/types";
import type { ContestoRitornoAuth } from "@/lib/auth/ritorno-auth";
import { ruoloDaSessione } from "@/lib/auth/role";

export type AuthUser = { userId: string; email: string | null };

/**
 * Stato della verifica del profilo necessaria al requisito di età. Vale per
 * qualunque metodo di accesso: email, magic link, Google o Facebook non fanno
 * differenza. Nessuno stato sovrappone assenza sessione, attesa ed errore.
 */
export type StatoEta =
  | "nessuna_sessione"
  | "in_verifica"
  | "da_completare"
  | "completo"
  | "errore_lettura";

/**
 * Una sola copia della riga completa, insieme all'esito della sua lettura e
 * all'utente a cui appartiene. Un errore di rete non diventa mai «DOB assente».
 */
export type ProfiloInMemoria = {
  userId: string;
  profilo: ProfiloCorrente | null;
  stato: "in_verifica" | "letto" | "errore_lettura";
};

/**
 * La regola dei cinque stati, pura e verificabile senza montare React.
 *
 * `letto` che appartiene a un altro utente vale quanto nessuna lettura: dopo un
 * cambio di sessione si torna in verifica, non si eredita l'esito precedente.
 * `errore_lettura` non collassa mai su `da_completare`: un guasto di rete non è
 * una data di nascita mancante, e trattarlo così manderebbe a completare il
 * profilo chi ce l'ha già completo.
 */
export function statoEtaProfilo(
  userId: string | null,
  letto: ProfiloInMemoria | null,
): StatoEta {
  if (!userId) return "nessuna_sessione";
  if (!letto || letto.userId !== userId || letto.stato === "in_verifica") return "in_verifica";
  if (letto.stato === "errore_lettura") return "errore_lettura";
  return letto.profilo?.dob ? "completo" : "da_completare";
}

/**
 * Sessione, profilo e ruolo effettivi Supabase. Il selettore dimostrativo può
 * sostituirli soltanto quando la sua flag pubblica è esplicitamente attiva.
 */
export const useRealAuthDomain = () => {
  const [authUser, setAuthUser] = useState<AuthUser | null>(null);
  const authUserIdRef = useRef<string | null>(null);
  const profiloInLetturaRef = useRef<{ userId: string } | null>(null);
  // Se Supabase non è configurato non c'è nulla da caricare: parte già a
  // false. Evita una setState sincrona nel corpo dell'effect sotto.
  const [authLoading, setAuthLoading] = useState(() => getSupabaseClient() !== null);
  // Errore del solo dominio profilo: vedi il commento su `authClearError`.
  const [authError, setAuthError] = useState<string | null>(null);
  const [profiloLetto, setProfiloLetto] = useState<ProfiloInMemoria | null>(null);
  const [ruoliLetti, setRuoliLetti] = useState<{ userId: string; ruoli: string[] } | null>(null);

  const applicaUtente = useCallback((utente: AuthUser | null) => {
    authUserIdRef.current = utente?.userId ?? null;
    setAuthUser(utente);
  }, []);

  useEffect(() => {
    const supabase = getSupabaseClient();
    if (!supabase) return;

    let active = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      applicaUtente(
        data.session
          ? { userId: data.session.user.id, email: data.session.user.email ?? null }
          : null,
      );
      setAuthLoading(false);
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, session) => {
      applicaUtente(
        session ? { userId: session.user.id, email: session.user.email ?? null } : null,
      );
      setAuthLoading(false);
    });

    return () => {
      active = false;
      subscription.subscription.unsubscribe();
    };
  }, [applicaUtente]);

  /**
   * Una lettura sola per l'intero profilo, non una per campo. Il token
   * impedisce a due tentativi sovrapposti di applicarsi fuori ordine; il ref
   * dell'utente impedisce di applicarli a una sessione diversa da quella che
   * li ha chiesti.
   *
   * L'attesa del **primo** tentativo non viene scritta qui: `statoEtaProfilo`
   * la deduce già dall'assenza di una lettura per l'utente corrente, e una
   * setState sincrona nel corpo dell'effect che chiama questa funzione è ciò
   * che la regola `set-state-in-effect` rifiuta. La riprova, che parte da un
   * gesto dell'utente, la scrive invece esplicitamente.
   */
  const leggiProfilo = useCallback(async (userId: string) => {
    const token = { userId };
    profiloInLetturaRef.current = token;

    const esito = await supabaseProfileService.leggiProfiloCorrente();
    if (authUserIdRef.current !== userId || profiloInLetturaRef.current !== token) return;

    profiloInLetturaRef.current = null;
    setProfiloLetto({
      userId,
      profilo: esito.ok ? esito.data : null,
      stato: esito.ok ? "letto" : "errore_lettura",
    });
  }, []);

  useEffect(() => {
    if (!authUser) return;
    void leggiProfilo(authUser.userId);
    return () => {
      if (profiloInLetturaRef.current?.userId === authUser.userId) {
        profiloInLetturaRef.current = null;
      }
    };
  }, [authUser, leggiProfilo]);

  /**
   * Un tentativo solo per pressione, e nessun secondo tentativo mentre il
   * primo è ancora in volo. L'esito precedente — in pratica l'errore appena
   * mostrato — sparisce subito: chi preme «Riprova» vede l'attesa, non il
   * guasto di prima accanto a un pulsante che sembra non aver fatto niente.
   */
  const authRicaricaProfilo = useCallback(async () => {
    const userId = authUserIdRef.current;
    if (!userId || profiloInLetturaRef.current?.userId === userId) return;
    setProfiloLetto({ userId, profilo: null, stato: "in_verifica" });
    await leggiProfilo(userId);
  }, [leggiProfilo]);

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

  const profiloCorrente =
    authUser && profiloLetto?.userId === authUser.userId ? profiloLetto : null;
  const statoEta = statoEtaProfilo(authUser?.userId ?? null, profiloLetto);
  const ruoliCorrenti =
    authUser && ruoliLetti?.userId === authUser.userId ? ruoliLetti.ruoli : [];
  const authRuolo = ruoloDaSessione(authUser, ruoliCorrenti);
  const authProfileLoading = statoEta === "in_verifica";
  const authProfileName = profiloCorrente?.profilo?.username || null;
  const authProfilo = profiloCorrente?.profilo ?? null;

  const authClearError = useCallback(() => setAuthError(null), []);

  /**
   * I quattro gesti di ingresso **non** scrivono più in `authError` (D5).
   *
   * `authError` era uno solo per tutto il dominio, e le superfici di ingresso ne
   * hanno tre contemporaneamente vivi: password, magic link e social. Con un
   * campo solo, un fallimento di Google compariva nello stesso riquadro sotto il
   * campo password — e ci restava anche dopo che l'utente aveva ricominciato da
   * un'altra strada. Ora l'esito torna a chi lo ha chiesto, tipizzato, e la
   * pagina lo mostra accanto al pulsante che lo ha prodotto.
   *
   * `authError` sopravvive per il solo dominio profilo (`authAggiornaProfilo`),
   * che ha una superficie sola e un errore alla volta: /account e
   * /completa-profilo continuano a leggerlo come prima.
   */
  const authRegistra = useCallback(
    (
      input: { email: string; password: string; dataNascita: string; username: string },
      contesto?: ContestoRitornoAuth,
    ) => supabaseAuthService.registra(input, contesto),
    [],
  );

  const authLogin = useCallback(
    (email: string, password: string) => supabaseAuthService.login(email, password),
    [],
  );

  const authInviaMagicLink = useCallback(
    (email: string, contesto?: ContestoRitornoAuth) =>
      supabaseAuthService.inviaMagicLink(email, contesto),
    [],
  );

  const authVerificaEmail = useCallback(
    (tokenHash: string): Promise<ResultAuth<void>> => supabaseAuthService.verificaEmail(tokenHash),
    [],
  );

  const authAccediConOAuth = useCallback(
    (provider: OAuthProvider, contesto?: ContestoRitornoAuth) =>
      supabaseAuthService.accediConOAuth(provider, contesto),
    [],
  );

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
      // Stessa regola della lettura: se nel frattempo la sessione è cambiata,
      // la risposta appartiene a un utente che non è più quello davanti allo
      // schermo e non entra nello stato canonico.
      if (authUserIdRef.current !== authUser.userId) return result;
      setProfiloLetto({ userId: authUser.userId, profilo: result.data, stato: "letto" });
      return result;
    },
    [authUser],
  );

  const authLogout = useCallback(async () => {
    await supabaseAuthService.logout();
    profiloInLetturaRef.current = null;
    applicaUtente(null);
    setProfiloLetto(null);
    setRuoliLetti(null);
  }, [applicaUtente]);

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
    authRicaricaProfilo,
    authAggiornaProfilo,
    authLogout,
  };
};
