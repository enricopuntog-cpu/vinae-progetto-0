"use client";

import { createContext, useContext, type ReactNode } from "react";
import { type Notifica } from "@/data/extra";
import { type CellarBottle, type StorageEnvironment, type StorageModule } from "@/data/cellar";
import {
  type Order,
  type Proposal,
  type BuyerOrderStatus,
  type SellerOrderStatus,
  type DeliveryMode,
  type TrackingEvent,
  type Dispute,
  type OrderReview,
} from "@/data/orders";
import {
  type Obiettivo,
  type EmailStatus,
  type AgeStatus,
  type IdentityStatus,
  type SellerStatus,
  type ProfiloUtente,
} from "@/data/onboarding";
import {
  type Report,
  type ReportStatus,
  type ReportTargetType,
  type ListingStatus,
  type ModAction,
  type AuditEntry,
} from "@/data/moderation";
import { useOrderDomain } from "@/lib/store/order-domain";
import { useCellarDomain, type DrinkOverride, type SfondoCantina } from "@/lib/store/cellar-domain";
import { useClubsDomain } from "@/lib/store/clubs-domain";
import { useMessagingDomain } from "@/lib/store/messaging-domain";
import { useListingsDomain } from "@/lib/store/listings-domain";
import { useProfileDomain } from "@/lib/store/profile-domain";
import { useAuthDomain, type DemoRuolo } from "@/lib/store/auth-domain";
import { useModerationDomain } from "@/lib/store/moderation-domain";
import { useRealAuthDomain, type AuthUser } from "@/lib/store/real-auth-domain";
import type { Result } from "@/services/types";

export type { DrinkOverride, SfondoCantina } from "@/lib/store/cellar-domain";
export type { DemoRuolo } from "@/lib/store/auth-domain";

type StoreState = {
  favorites: Set<string>;
  follows: Set<string>;
  proposte: Record<string, number>;
  toggleFavorite: (id: string) => void;
  toggleFollow: (nome: string) => void;
  proponi: (wineId: string, prezzo: number) => void;

  ruolo: DemoRuolo;
  setRuolo: (r: DemoRuolo) => void;

  // Autenticazione reale (Supabase, Fase 5a) — separata dal demo-switcher `ruolo` sopra.
  authUser: AuthUser | null;
  authLoading: boolean;
  authError: string | null;
  authClearError: () => void;
  authRegistra: (input: {
    email: string;
    password: string;
    dataNascita: string;
    username: string;
  }) => Promise<Result<{ userId: string; sessioneAttiva: boolean }>>;
  authLogin: (email: string, password: string) => Promise<Result<{ userId: string }>>;
  authInviaMagicLink: (email: string) => Promise<Result<void>>;
  authVerificaEmail: (tokenHash: string) => Promise<Result<void>>;
  authLogout: () => Promise<void>;

  notifiche: Notifica[];
  nonLette: number;
  segnaLetta: (id: string) => void;
  segnaTutteLette: () => void;

  communityFollows: Set<string>;
  toggleCommunityFollow: (slug: string) => void;

  regionePref: string;
  tipologiaPref: string;
  setPreferenze: (r: string, t: string) => void;
  sfondoCantina: SfondoCantina;
  setSfondoCantina: (s: SfondoCantina) => void;
  inVendita: Set<string>;
  toggleInVendita: (id: string) => void;
  prezzoNascosto: Set<string>;
  togglePrezzoNascosto: (id: string) => void;

  // Cellar 3D
  bottiglieCantina: CellarBottle[];
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
  drinkWindowOverrides: Record<string, DrinkOverride>;
  setDrinkWindowOverride: (wineId: string, o: DrinkOverride) => void;
  openBottle: (bottleId: string, nota?: string) => void;
  scheduleOpen: (bottleId: string, date: string) => void;
  moveBottle: (bottleId: string, newSlotId: string) => void;
  addEnvironment: (env: StorageEnvironment, mods: StorageModule[]) => void;
  reduceMotion: boolean;
  setReduceMotion: (b: boolean) => void;

  // Orders & proposals
  orders: Order[];
  sales: Order[];
  proposals: Proposal[];
  getOrder: (id: string) => Order | undefined;
  createOrder: (input: {
    wineId: string;
    quantita: number;
    deliveryMode: DeliveryMode;
    metodoPagamento: "carta_demo" | "paypal_demo" | "bonifico_demo";
    proposalId?: string;
    prezzoUnitario?: number;
  }) => Promise<Order>;
  advanceOrder: (orderId: string, target: BuyerOrderStatus, side?: "buyer" | "sales") => void;
  updateSellerOrder: (orderId: string, patch: Partial<Order>) => void;
  addTracking: (
    orderId: string,
    ev: Omit<TrackingEvent, "id" | "ts"> & { ts?: string },
    side?: "buyer" | "sales",
  ) => void;
  markShipped: (orderId: string, trackingNumber: string, courier: string) => void;
  markDelivered: (orderId: string, side?: "buyer" | "sales") => void;
  confirmOk: (orderId: string) => void;
  openDispute: (
    orderId: string,
    d: { motivo: string; descrizione: string; foto: string[] },
  ) => void;
  resolveDispute: (
    orderId: string,
    esito: "rimborsata" | "risolta" | "respinta",
    nota?: string,
  ) => void;
  submitReview: (orderId: string, r: OrderReview) => void;

  // Proposte v2 (state machine)
  createProposal: (wineId: string, prezzoProposto: number) => Proposal | null;
  sellerCounter: (proposalId: string, controProposta: number) => void;
  acceptProposal: (proposalId: string) => void;
  rejectProposal: (proposalId: string) => void;

  pushNotifica: (n: Omit<Notifica, "id" | "letta">) => void;

  // Onboarding & verifica
  registrato: boolean;
  emailStatus: EmailStatus;
  ageStatus: AgeStatus;
  identityStatus: IdentityStatus;
  sellerStatus: SellerStatus;
  obiettivi: Set<Obiettivo>;
  regioniPreferite: Set<string>;
  tipologiePreferite: Set<string>;
  fasciaPrezzo: string | null;
  clubSuggeritiSalvati: boolean;
  preferenzeSalvate: boolean;
  profiloBase: boolean;
  profilo: ProfiloUtente;
  registerAccount: (p: {
    username: string;
    email: string;
    dob: string;
    maggiorenne: boolean;
  }) => void;
  verifyEmail: () => void;
  toggleObiettivo: (o: Obiettivo) => void;
  saveObiettivi: () => void;
  toggleRegionePref: (r: string) => void;
  toggleTipologiaPref: (t: string) => void;
  setFasciaPrezzo: (id: string) => void;
  savePreferenze: () => void;
  saveProfilo: (p: Partial<ProfiloUtente>) => void;
  startIdentityVerification: () => void;
  completeIdentityVerification: (esito: "verificata" | "rifiutata") => void;
  resetOnboarding: () => void;
  profileCompletion: { perc: number; items: { label: string; done: boolean; to?: string }[] };

  // Moderation
  reports: Report[];
  listingStatus: Record<string, ListingStatus>;
  auditLog: AuditEntry[];
  modScope: "piattaforma" | { club: string };
  setModScope: (s: "piattaforma" | { club: string }) => void;
  submitReport: (input: {
    targetType: ReportTargetType;
    targetId: string;
    targetLabel: string;
    reason: string;
    descrizione: string;
    foto: string[];
    clubSlug?: string;
  }) => void;
  updateReportStatus: (id: string, stato: ReportStatus, nota?: string) => void;
  assignReport: (id: string, assignee: string) => void;
  addReportNote: (id: string, testo: string) => void;
  setListingStatus: (wineId: string, s: ListingStatus) => void;
  applyModAction: (input: {
    action: ModAction;
    target: string;
    motivazione: string;
    durata?: string;
    scope?: "piattaforma" | "club";
    clubSlug?: string;
    reportId?: string;
  }) => void;
  richiediAltreFoto: (wineId: string, sellerName: string) => void;
};

const Ctx = createContext<StoreState | null>(null);

export function VineaProvider({ children }: { children: ReactNode }) {
  const cellarDomain = useCellarDomain();
  const clubsDomain = useClubsDomain();
  const messagingDomain = useMessagingDomain();
  const { pushNotifica } = messagingDomain;
  const { recordProposalPrice, ...listingsDomain } = useListingsDomain();

  const orderDomain = useOrderDomain({ pushNotifica, recordProposalPrice });
  const { resetForGuest, ...profileDomain } = useProfileDomain({ pushNotifica });
  const authDomain = useAuthDomain({ onGuestSwitch: resetForGuest });
  const moderationDomain = useModerationDomain({ pushNotifica });
  const realAuthDomain = useRealAuthDomain();

  return (
    <Ctx.Provider
      value={{
        ...listingsDomain,
        ...authDomain,
        ...messagingDomain,
        ...clubsDomain,
        ...cellarDomain,
        ...orderDomain,
        ...profileDomain,
        ...moderationDomain,
        ...realAuthDomain,
      }}
    >
      {children}
    </Ctx.Provider>
  );
}

export function useVinea() {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useVinea deve stare dentro VineaProvider");
  return ctx;
}

export { formatEUR } from "@/lib/format";