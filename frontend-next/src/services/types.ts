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
import type {
  CellarBottle,
  StorageEnvironment,
  StorageModule,
  WineVintageMeta,
} from "@/data/cellar";
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

/** Override personale della finestra di bevuta, come lo scrive DrinkWindow. */
export type OverrideFinestra = NonNullable<CellarBottle["override"]>;

/** Ciò che il configuratore raccoglie per creare un ambiente e il suo modulo. */
export interface DatiNuovoAmbiente {
  nome: string;
  forma: StorageEnvironment["shape"];
  tema: StorageEnvironment["theme"];
  righe: number;
  colonne: number;
}

/**
 * Tutto ciò che `/cantina` legge, in una struttura sola.
 *
 * `vini` ha una voce per vino distinto e non per bottiglia: le viste a griglia
 * e a elenco mostrano schede per vino, esattamente come in `frontend/`. Il
 * prezzo di ogni scheda viene dall'annuncio della bottiglia che la rappresenta
 * — nel catalogo `wines` un prezzo non esiste, perché appartiene all'annuncio.
 */
export interface DatiCantina {
  bottiglie: CellarBottle[];
  vini: Wine[];
  /** Metadati di bevuta indicizzati per slug del vino. */
  metaPerVino: Record<string, WineVintageMeta>;
  ambienti: StorageEnvironment[];
  moduli: StorageModule[];
}

/**
 * Le firme divergono dalla bozza di Fase 3
 * (`bottiglie(userId)`, `spostaBottiglia(bottleId, slotId)`, `apri(): void`)
 * per quattro ragioni emerse scrivendo la 6c-2:
 *
 * - **`userId` non è un parametro.** La RLS filtra già su `auth.uid()`:
 *   passarlo suggerisce di poter leggere la cantina di qualcun altro, cosa che
 *   il database rifiuta. Stessa correzione già fatta a `ListingService` in 6b.
 * - **`slotId` non esiste più.** Dalla 6c-1 una posizione libera non ha riga in
 *   `cellar_slots` e quindi non ha id: una posizione si nomina con
 *   (modulo, riga, colonna), che è la firma di `cellar_posiziona`. Serve anche
 *   il verso opposto, che nella bozza mancava.
 * - **Le letture stanno insieme.** `bottiglie`, `ambienti` e `moduli` vengono
 *   sempre usate nello stesso momento dalla stessa pagina; tre metodi separati
 *   diventerebbero tre andate e ritorni, e la pagina mostrerebbe gli scaffali
 *   prima delle bottiglie.
 * - **Le scritture ritornano `Result`.** `apri(): Promise<void>` non può
 *   fallire visibilmente; i messaggi delle funzioni SQL sono già in italiano ed
 *   è quello che l'interfaccia deve mostrare, come per `ListingService`.
 *
 * Le scritture che l'interfaccia esprime **per vino** (visibilità del prezzo,
 * override della finestra) prendono un elenco di bottiglie e non un vino: nella
 * 6c-1 quelle colonne stanno sull'unità, perché sono scelte personali. La
 * chiamante passa tutte le proprie unità di quel vino, così il comportamento
 * visibile resta quello di `frontend/`, dove l'indice è il vino.
 */
export interface CellarService {
  carica(): Promise<DatiCantina>;

  aggiungiBottiglia(
    dati: DatiNuovaBottiglia,
  ): Promise<Result<{ bottleUnitId: string; wineId: string }>>;
  apri(bottleUnitId: string, nota?: string): Promise<Result<void>>;
  pianificaApertura(bottleUnitId: string, data: string): Promise<Result<void>>;
  colloca(
    bottleUnitId: string,
    moduleId: string,
    riga: number,
    colonna: number,
  ): Promise<Result<void>>;
  togliDallaPosizione(bottleUnitId: string): Promise<Result<void>>;
  impostaVisibilitaPrezzo(
    bottleUnitIds: string[],
    visibilita: CellarBottle["priceVisibility"],
  ): Promise<Result<void>>;
  impostaOverrideFinestra(
    bottleUnitIds: string[],
    override: OverrideFinestra,
  ): Promise<Result<void>>;
  creaAmbiente(dati: DatiNuovoAmbiente): Promise<Result<void>>;
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

/** Descrizione immessa da un utente per catalogare una propria bottiglia. */
export interface DatiVinoUtente {
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  tipo: Wine["tipo"];
}

/** Aggiunta alla Cantina: non contiene prezzo né campi di un annuncio. */
export interface DatiNuovaBottiglia extends DatiVinoUtente {
  visibilita: "privata" | "cantina_pubblica";
  /** Percorsi nel bucket privato `cantina`. */
  immagini: string[];
}

/** Campi di contenuto di una vendita, sempre riferita a una bottle_unit. */
export interface DatiModificaAnnuncio {
  condizione: Wine["condizione"];
  conservazione: string;
  storia: string;
  /** In centesimi interi: mai un prezzo in euro come float. */
  prezzoCents: number;
  /** Percorsi dentro il bucket `annunci`, nella forma `<uid>/<uuid>.<est>`. */
  immagini: string[];
}

/**
 * Mettere in vendita una bottiglia che è già in cantina (Fase 6c-2).
 *
 * Non ha produttore, nome, annata, regione né tipologia: descrivono il vino,
 * che per un'unità esistente è già deciso e vive in `wines`. Il database li
 * legge dall'unità, e chiederli qui darebbe l'impressione che passandoli
 * diversi si possa rinominare un vino di catalogo — la stessa ragione per cui
 * `DatiModificaAnnuncio` non li contiene.
 */
export type DatiVenditaDaCantina = DatiModificaAnnuncio & { bottleUnitId: string };

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
  /**
   * Crea un annuncio in bozza esclusivamente da una bottle_unit già presente
   * in Cantina. La catalogazione privata/pubblica appartiene a CellarService.
   */
  crea(dati: DatiVenditaDaCantina): Promise<Result<{ id: string; slug: string }>>;
  aggiorna(id: string, dati: Partial<DatiModificaAnnuncio>): Promise<Result<void>>;
  pubblica(id: string): Promise<Result<void>>;
  sospendi(id: string, motivo?: string): Promise<Result<void>>;
  scadi(id: string): Promise<Result<void>>;
}

// ---- Proposte & Ordini -----------------------------------------------------
export type ProposalStatus =
  | "inviata"
  | "controproposta"
  | "accettata"
  | "rifiutata"
  | "scaduta"
  | "convertita";

export type ProposalRecord = {
  id: string;
  listing_id: string;
  buyer_id: string;
  seller_id: string;
  prezzo_richiesto_cents: number;
  prezzo_proposto_cents: number;
  controproposta_cents: number | null;
  stato: ProposalStatus;
  scadenza: string;
  created_at: string;
  updated_at: string;
};

export type OrderStatus =
  | "in_attesa_pagamento"
  | "pagato"
  | "in_preparazione"
  | "spedito"
  | "consegnato"
  | "verifica"
  | "completato"
  | "contestato"
  | "rimborsato"
  | "annullato";
export type OrderDeliveryMode = "consegna_mano" | "spedizione";

export type OrderRecord = {
  id: string;
  listing_id: string;
  proposal_id: string | null;
  buyer_id: string;
  seller_id: string;
  seller_bottle_unit_id: string;
  buyer_bottle_unit_id: string | null;
  stato: OrderStatus;
  delivery_mode: OrderDeliveryMode;
  prezzo_cents: number;
  currency: "eur";
  reservation_expires_at: string;
  paid_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PaymentStatus =
  | "checkout_pending"
  | "processing"
  | "paid"
  | "failed"
  | "expired"
  | "partially_refunded"
  | "refunded";

export type PaymentRecord = {
  id: string;
  order_id: string;
  stato: PaymentStatus;
  amount_cents: number;
  amount_refunded_cents: number;
  currency: "eur";
  created_at: string;
  updated_at: string;
};

export interface ProposalService {
  invia(listingId: string, prezzoCents: number): Promise<Result<ProposalRecord>>;
  controproposta(id: string, prezzoCents: number): Promise<Result<ProposalRecord>>;
  accetta(id: string): Promise<Result<ProposalRecord>>;
  rifiuta(id: string): Promise<Result<void>>;
  mie(): Promise<Result<ProposalRecord[]>>;
}

export interface OrderService {
  acquisti(): Promise<Result<OrderRecord[]>>;
  vendite(): Promise<Result<OrderRecord[]>>;
  get(id: string): Promise<Result<OrderRecord | null>>;
}

// ---- Pagamenti -------------------------------------------------------------
export interface PaymentService {
  creaCheckout(input: {
    listingId: string;
    proposalId?: string;
    deliveryMode: OrderDeliveryMode;
    idempotencyKey: string;
  }): Promise<Result<{ checkoutUrl: string }>>;
  perOrdine(orderId: string): Promise<Result<PaymentRecord | null>>;
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
