"use client";

import { createContext, useContext, type ReactNode } from "react";
import {
  type CellarBottle,
  type StorageEnvironment,
  type StorageModule,
  type WineVintageMeta,
} from "@/data/cellar";
import { type Wine } from "@/data/wines";
import type { AnaliticaPortafoglio } from "@/lib/cantina/portfolio";
import { DEMO_UI_ABILITATA } from "@/config/features";
import { useAuthDomain, type DemoRuolo } from "@/lib/store/auth-domain";
import {
  useCellarDomain,
  type DrinkOverride,
} from "@/lib/store/cellar-domain";
import {
  useRealAuthDomain,
  type AuthUser,
  type StatoEta,
} from "@/lib/store/real-auth-domain";
import type {
  DatiNuovoAmbiente,
  OAuthProvider,
  ProfiloCorrente,
  ProfiloModifica,
  Result,
  ResultAuth,
} from "@/services/types";
import type { ContestoRitornoAuth } from "@/lib/auth/ritorno-auth";

export type { DrinkOverride } from "@/lib/store/cellar-domain";
export type { DemoRuolo } from "@/lib/store/auth-domain";

type StoreState = {
  ruolo: DemoRuolo;
  setRuolo: (ruolo: DemoRuolo) => void;
  authUser: AuthUser | null;
  authLoading: boolean;
  /** Riga completa di `public.profiles` per l'utente collegato. */
  authProfilo: ProfiloCorrente | null;
  authProfileName: string | null;
  authProfileLoading: boolean;
  /**
   * Errore del solo dominio profilo. I gesti di ingresso restituiscono il
   * proprio esito a chi li chiama (D5): un campo condiviso non sa distinguere
   * un fallimento della password da uno di Google, e le superfici di ingresso
   * ne hanno tre vivi insieme. Vedi `lib/store/real-auth-domain.ts`.
   */
  authError: string | null;
  authClearError: () => void;
  authRegistra: (
    input: {
      email: string;
      password: string;
      dataNascita: string;
      username: string;
    },
    contesto?: ContestoRitornoAuth,
  ) => Promise<
    ResultAuth<{ userId: string; sessioneAttiva: boolean; confermaEmailRichiesta: boolean }>
  >;
  authLogin: (email: string, password: string) => Promise<ResultAuth<{ userId: string }>>;
  authInviaMagicLink: (email: string, contesto?: ContestoRitornoAuth) => Promise<ResultAuth<void>>;
  authVerificaEmail: (tokenHash: string) => Promise<ResultAuth<void>>;
  authAccediConOAuth: (
    provider: OAuthProvider,
    contesto?: ContestoRitornoAuth,
  ) => Promise<ResultAuth<void>>;
  authStatoEta: StatoEta;
  /**
   * Scrittura unica del proprio profilo. Nessun `userId` in firma: la riga è
   * sempre quella di `auth.uid()`, risolta dal servizio a partire dalla
   * sessione e imposta comunque da `profiles_update_own`.
   */
  authAggiornaProfilo: (patch: ProfiloModifica) => Promise<Result<ProfiloCorrente>>;
  authLogout: () => Promise<void>;
  inVendita: Set<string>;
  prezzoNascosto: Set<string>;
  togglePrezzoNascosto: (id: string) => Promise<Result<void>>;
  bottiglieCantina: CellarBottle[];
  viniCantina: Wine[];
  metaPerVino: Record<string, WineVintageMeta>;
  cantinaLoading: boolean;
  /** Contabilità del portafoglio: `null` finché non arriva o se non arriva. */
  analitica: AnaliticaPortafoglio | null;
  analiticaErrore: string | null;
  analiticaLoading: boolean;
  ricaricaCantina: () => Promise<void>;
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
  drinkWindowOverrides: Record<string, DrinkOverride>;
  setDrinkWindowOverride: (wineId: string, override: DrinkOverride) => Promise<Result<void>>;
  openBottle: (bottleId: string, nota?: string) => Promise<Result<void>>;
  scheduleOpen: (bottleId: string, date: string) => Promise<Result<void>>;
  moveBottle: (bottleId: string, newSlotId: string) => Promise<Result<void>>;
  creaAmbiente: (dati: DatiNuovoAmbiente) => Promise<Result<void>>;
  reduceMotion: boolean;
  setReduceMotion: (riduci: boolean) => void;
};

const Ctx = createContext<StoreState | null>(null);

export const VineaProvider = ({ children }: { children: ReactNode }) => {
  const cellarDomain = useCellarDomain();
  const realAuthDomain = useRealAuthDomain();
  const authDomain = useAuthDomain({
    ruoloReale: realAuthDomain.authRuolo,
    demoAbilitata: DEMO_UI_ABILITATA,
  });

  return (
    <Ctx.Provider value={{ ...authDomain, ...cellarDomain, ...realAuthDomain }}>
      {children}
    </Ctx.Provider>
  );
};

export const useVinea = (): StoreState => {
  const context = useContext(Ctx);
  if (!context) throw new Error("useVinea deve stare dentro VineaProvider");
  return context;
};

export { formatEUR } from "@/lib/format";
