/**
 * Contratti servizio (solo interfacce). Nessuna implementazione reale.
 * I tipi di dominio vivono in src/data/*.ts — qui riesportiamo solo le firme.
 */

import type {
  Order,
  Proposal,
  BuyerOrderStatus,
  SellerOrderStatus,
  DeliveryMode,
  TrackingEvent,
  Dispute,
  OrderReview,
} from "@/data/orders";
import type {
  Report,
  ReportStatus,
  ReportTargetType,
  ListingStatus,
  ModAction,
  AuditEntry,
} from "@/data/moderation";
import type {
  ProfiloUtente,
  Obiettivo,
  EmailStatus,
  AgeStatus,
  IdentityStatus,
  SellerStatus,
} from "@/data/onboarding";
import type { CellarBottle, StorageEnvironment, StorageModule } from "@/data/cellar";
import type { Notifica } from "@/data/extra";

export type Result<T, E = string> = { ok: true; data: T } | { ok: false; error: E };

// ---- Auth ------------------------------------------------------------------
export interface AuthService {
  registra(input: {
    email: string;
    password: string;
    dataNascita: string;
  }): Promise<Result<{ userId: string }>>;
  verificaEmail(token: string): Promise<Result<void>>;
  login(email: string, password: string): Promise<Result<{ userId: string }>>;
  logout(): Promise<void>;
  utenteCorrente(): Promise<{ userId: string } | null>;
}

// ---- Profili ---------------------------------------------------------------
export interface ProfileService {
  get(userId: string): Promise<ProfiloUtente | null>;
  update(userId: string, patch: Partial<ProfiloUtente>): Promise<ProfiloUtente>;
  aggiornaObiettivi(userId: string, obiettivi: Obiettivo[]): Promise<void>;
  stati(userId: string): Promise<{
    email: EmailStatus;
    eta: AgeStatus;
    identita: IdentityStatus;
    venditore: SellerStatus;
  }>;
}

// ---- Catalogo vini ---------------------------------------------------------
export interface WineCatalogService {
  cerca(query: string, filtri?: Record<string, unknown>): Promise<unknown[]>;
  dettaglio(id: string): Promise<unknown | null>;
  suggeriti(userId?: string): Promise<unknown[]>;
}

// ---- Cantina ---------------------------------------------------------------
export interface CellarService {
  bottiglie(userId: string): Promise<CellarBottle[]>;
  ambienti(userId: string): Promise<StorageEnvironment[]>;
  moduli(userId: string): Promise<StorageModule[]>;
  apri(bottleId: string, nota?: string): Promise<void>;
  spostaBottiglia(bottleId: string, slotId: string): Promise<void>;
}

// ---- Annunci ---------------------------------------------------------------
export interface ListingService {
  crea(input: unknown): Promise<{ id: string; stato: ListingStatus }>;
  aggiornaStato(id: string, stato: ListingStatus, motivo?: string): Promise<void>;
  richiediFoto(listingId: string, message: string): Promise<void>;
  elenco(filtri?: Record<string, unknown>): Promise<unknown[]>;
}

// ---- Proposte & Ordini -----------------------------------------------------
export interface ProposalService {
  invia(listingId: string, prezzo: number): Promise<Proposal>;
  controproposta(id: string, prezzo: number): Promise<Proposal>;
  accetta(id: string): Promise<Order>;
  rifiuta(id: string): Promise<void>;
}

export interface OrderService {
  acquisti(userId: string): Promise<Order[]>;
  vendite(userId: string): Promise<Order[]>;
  get(id: string): Promise<Order | null>;
  aggiornaAcquirente(id: string, stato: BuyerOrderStatus): Promise<void>;
  aggiornaVenditore(id: string, stato: SellerOrderStatus): Promise<void>;
  aggiungiTracking(id: string, evento: TrackingEvent): Promise<void>;
  scegliConsegna(id: string, modo: DeliveryMode): Promise<void>;
  apriContestazione(id: string, dispute: Omit<Dispute, "id" | "stato">): Promise<Dispute>;
  recensisci(id: string, review: Omit<OrderReview, "id" | "createdAt">): Promise<OrderReview>;
}

// ---- Pagamenti (demo-only) -------------------------------------------------
export interface PaymentService {
  /** Puramente dimostrativo: non raccoglie dati reali. */
  simulaCheckout(orderId: string): Promise<Result<{ paymentId: string }>>;
}

// ---- Messaggi --------------------------------------------------------------
export interface MessagingService {
  conversazioni(userId: string): Promise<unknown[]>;
  messaggi(conversationId: string): Promise<unknown[]>;
  invia(conversationId: string, testo: string): Promise<void>;
}

// ---- Club ------------------------------------------------------------------
export interface ClubService {
  elenco(): Promise<unknown[]>;
  dettaglio(slug: string): Promise<unknown | null>;
  segui(slug: string): Promise<void>;
  smettiSegui(slug: string): Promise<void>;
}

// ---- Notifiche -------------------------------------------------------------
export interface NotificationService {
  elenco(userId: string): Promise<Notifica[]>;
  segnaLetta(id: string): Promise<void>;
  segnaTutteLette(userId: string): Promise<void>;
}

// ---- Moderazione -----------------------------------------------------------
export interface ModerationService {
  segnala(input: Omit<Report, "id" | "createdAt" | "stato">): Promise<Report>;
  segnalazioniUtente(userId: string): Promise<Report[]>;
  coda(): Promise<Report[]>;
  aggiornaStato(id: string, stato: ReportStatus, nota?: string): Promise<void>;
  eseguiAzione(
    target: { tipo: ReportTargetType; id: string },
    azione: ModAction,
    motivo: string,
  ): Promise<AuditEntry>;
  auditLog(): Promise<AuditEntry[]>;
}

// ---- AI (demo-only) --------------------------------------------------------
export type AiJobStatus =
  "in_attesa" | "in_elaborazione" | "completata" | "richiede_conferma" | "fallita";

export interface AiService {
  identificaBottiglia(
    imageIds: string[],
  ): Promise<{ status: AiJobStatus; suggerimenti?: unknown[] }>;
  miglioraSfondo(
    imageId: string,
    stile: string,
  ): Promise<{ status: AiJobStatus; anteprima?: string }>;
  suggerisciAbbinamento(query: string): Promise<{ status: AiJobStatus; risultati?: unknown[] }>;
}
