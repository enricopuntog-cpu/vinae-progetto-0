/**
 * Contratti servizio (solo interfacce per i domini ancora mock).
 * I tipi di dominio vivono in src/data/*.ts — qui riesportiamo solo le firme.
 *
 * AuthService è l'eccezione: dalla Fase 5a ha un'implementazione reale
 * (src/services/auth-service.ts, Supabase Auth) invece di restare uno stub.
 * L'interfaccia qui sotto è stata estesa rispetto alla versione originale di
 * frontend/src/services/types.ts con `username` in `registra()` (già
 * raccolto dal form di registrazione, necessario per popolare profiles.username)
 * e con `inviaMagicLink`, non previsto nella bozza originale.
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
import type { Wine } from "@/data/wines";

export type Result<T, E = string> = { ok: true; data: T } | { ok: false; error: E };

// ---- Auth --------------------------------------------------------------
// Google e Facebook aggiunti in Fase 5b. Client ID/Secret vivono solo nella
// dashboard Supabase: qui si nomina soltanto il provider.
export type OAuthProvider = "google" | "facebook";

export interface AuthService {
  /**
   * Una registrazione riuscita ha tre esiti distinti, non due:
   *
   * - `sessioneAttiva: true` — sessione già aperta, l'utente è dentro.
   * - `sessioneAttiva: false` + `confermaEmailRichiesta: true` — utente creato
   *   ma inattivo finché non clicca il link di conferma ricevuto per email.
   * - `sessioneAttiva: false` + `confermaEmailRichiesta: false` — email già
   *   confermata d'ufficio (auto-conferma attiva sul progetto) ma signUp non
   *   ha restituito una sessione. Caso realmente osservato sul progetto in
   *   uso: l'account è immediatamente utilizzabile, quindi mostrare
   *   "controlla la posta" sarebbe fuorviante e bloccherebbe l'utente su uno
   *   schermo che aspetta un'email che non arriverà mai.
   */
  registra(input: {
    email: string;
    password: string;
    dataNascita: string;
    username: string;
  }): Promise<Result<{ userId: string; sessioneAttiva: boolean; confermaEmailRichiesta: boolean }>>;
  verificaEmail(tokenHash: string): Promise<Result<void>>;
  login(email: string, password: string): Promise<Result<{ userId: string }>>;
  inviaMagicLink(email: string): Promise<Result<void>>;
  /**
   * Avvia il flusso OAuth. Non ritorna una sessione: il browser viene
   * reindirizzato al provider e rientra su /auth/callback, che completa lo
   * scambio del code. Un esito `ok` significa solo "redirect avviato".
   */
  accediConOAuth(provider: OAuthProvider): Promise<Result<void>>;
  signInWithGoogle(): Promise<Result<void>>;
  signInWithFacebook(): Promise<Result<void>>;
  logout(): Promise<void>;
  utenteCorrente(): Promise<{ userId: string; email: string | null } | null>;
  /**
   * Data di nascita dichiarata sul profilo, o null se non ancora fornita —
   * il caso di chi entra via Google/Facebook, che salta il form email e
   * quindi anche il banner di dichiarazione età.
   */
  dataNascitaProfilo(userId: string): Promise<Result<string | null>>;
  salvaDataNascita(userId: string, dataNascita: string): Promise<Result<void>>;
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
/**
 * La parte in sola lettura del dominio annunci, separata dal resto perché è
 * l'unica che la Fase 6a implementa davvero (src/services/listing-service.ts,
 * su Supabase). Tenerla distinta evita l'alternativa peggiore: una classe che
 * dichiara `implements ListingService` e riempie di `throw new Error("non
 * implementato")` i metodi di scrittura, facendo sembrare disponibile ciò che
 * non lo è.
 *
 * `elenco()` restituisce `Wine[]` e non `unknown[]` come la bozza originale:
 * i componenti esistenti sono tipizzati su `Wine`, e l'adattatore ricompone
 * quella forma partendo dallo schema normalizzato. `dettaglio()` non era
 * previsto nella bozza — la pagina /annuncio/[id] ha bisogno di caricare un
 * singolo annuncio per slug senza scaricare l'intero elenco.
 */
export interface ListingReadService {
  elenco(): Promise<Wine[]>;
  dettaglio(slug: string): Promise<Wine | null>;
}

/** Dati che il wizard /vendi raccoglie per creare un annuncio. */
export interface DatiNuovoAnnuncio {
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  tipo: Wine["tipo"];
  condizione: Wine["condizione"];
  conservazione: string;
  storia: string;
  /** In centesimi interi: mai un prezzo in euro come float. */
  prezzoCents: number;
  /** Percorsi dentro il bucket `annunci`, nella forma `<uid>/<uuid>.<est>`. */
  immagini: string[];
}

/**
 * I campi modificabili dopo la creazione.
 *
 * Produttore, nome, annata, regione e tipologia non ci sono: descrivono il
 * vino, che vive in `wines` ed è un catalogo condiviso scrivibile solo dallo
 * staff. Correggere "Antinori" in "Antinory" su un annuncio cambierebbe il
 * vino per tutti gli annunci che lo citano. Un annuncio sbagliato sul vino si
 * ricrea; il catalogo lo corregge chi ha il ruolo per farlo.
 */
export type DatiModificaAnnuncio = Pick<
  DatiNuovoAnnuncio,
  "prezzoCents" | "condizione" | "conservazione" | "storia" | "immagini"
>;

/**
 * Lettura più scrittura.
 *
 * Le firme divergono dalla bozza di Fase 3 (`crea(input: unknown)`,
 * `aggiornaStato(id, stato)`, `richiediFoto`) per tre ragioni emerse
 * scrivendo la 6b:
 *
 * - `input: unknown` non è un contratto: il wizard raccoglie campi precisi e
 *   il database li valida uno per uno. `DatiNuovoAnnuncio` li nomina.
 * - `aggiornaStato(id, stato)` suggerisce che il chiamante scelga lo stato di
 *   arrivo. Non è così: ogni transizione ha precondizioni diverse e vive in
 *   una funzione SQL dedicata. Un metodo per transizione rende impossibile
 *   chiedere un passaggio che non esiste.
 * - `richiediFoto` è un'azione di moderazione (Fase 9), non del venditore, e
 *   resta fuori da qui finché quel dominio non arriva.
 *
 * Ogni scrittura ritorna `Result` e non lancia: il messaggio d'errore del
 * database è già in italiano e leggibile, ed è quello che il wizard mostra.
 */
export interface ListingService extends ListingReadService {
  crea(dati: DatiNuovoAnnuncio): Promise<Result<{ id: string; slug: string }>>;
  aggiorna(id: string, dati: Partial<DatiModificaAnnuncio>): Promise<Result<void>>;
  pubblica(id: string): Promise<Result<void>>;
  sospendi(id: string, motivo?: string): Promise<Result<void>>;
  scadi(id: string): Promise<Result<void>>;
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
