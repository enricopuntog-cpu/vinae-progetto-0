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
  /** Ruoli della sola riga corrente, filtrati dalla RLS su `user_roles`. */
  ruoliProfilo(userId: string): Promise<Result<string[]>>;
  /**
   * Data di nascita dichiarata sul profilo, o null se non ancora fornita —
   * il caso di chi entra via Google/Facebook, che salta il form email e
   * quindi anche il banner di dichiarazione età.
   */
  dataNascitaProfilo(userId: string): Promise<Result<string | null>>;
  nomeProfilo(userId: string): Promise<Result<string | null>>;
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

/**
 * Stato del trasferimento verso il venditore (Fase 7b). È **ortogonale** a
 * `OrderStatus`, non una sua estensione: un ordine `completato` può avere il
 * Transfer ancora da creare, in corso o fallito. Rispecchia l'enum
 * `public.payout_stato`: i due elenchi vanno cambiati insieme.
 */
export type PayoutStatus =
  | "trattenuto"
  | "in_attesa"
  | "in_corso"
  | "trasferito"
  | "bloccato"
  | "fallito";

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
  /** Quanto incassa il venditore. La commissione sta sopra, non dentro. */
  prezzo_cents: number;
  /**
   * I tre parametri congelati alla creazione. Non si rileggono dalla
   * configurazione corrente, e ci sono tutti e tre perché il risultato da solo
   * non spiegherebbe più un ordine vecchio una volta cambiato il listino.
   */
  margine_obiettivo_bps: number;
  riferimento_stripe_percentuale_bps: number;
  riferimento_stripe_fisso_cents: number;
  /** Il rincaro risultante. La percentuale effettiva si deriva, non si legge. */
  commissione_cents: number;
  /**
   * Base di mercato: `prezzo + commissione`. Colonna generata. L'imballaggio
   * **non** entra qui, mai — è ciò che tiene intatta la formula del rincaro e
   * la riconciliazione della 7b.
   */
  totale_cents: number;
  payout_stato: PayoutStatus;
  consegnato_at: string | null;
  auto_rilascio_scadenza: string | null;
  ricezione_confermata_at: string | null;
  contestato_at: string | null;
  contestazione_motivo: string | null;
  currency: "eur";
  reservation_expires_at: string;
  paid_at: string | null;
  created_at: string;
  updated_at: string;

  // ---- Fase 7c ----
  preparazione_avviata_at: string | null;
  spedito_at: string | null;
  corriere: string | null;
  tracking_number: string | null;
  imballaggio_checklist: VoceChecklist[];
  imballaggio_foto: string[];
  /** Il metodo dichiarato dal venditore sull'annuncio, congelato alla creazione. */
  imballaggio_codice: string | null;
  imballaggio_provider: string | null;
  imballaggio_etichetta: string | null;
  imballaggio_cents: number;
  /** Punto fisico, scelto dopo il pagamento. Non ha prezzo. */
  imballaggio_punto_id: string | null;
  imballaggio_punto_nome: string | null;
  imballaggio_scelto_at: string | null;
  /**
   * Quanto viene davvero addebitato: `prezzo + commissione + imballaggio`.
   * Seconda colonna generata, ed è questo il numero della riga `payments`.
   */
  addebito_totale_cents: number;
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

/**
 * Come per `ListingService`, un metodo per transizione e non un
 * `aggiornaStato(id, stato)`: ogni passaggio ha precondizioni diverse e vive in
 * una funzione SQL dedicata, quindi chiedere una transizione che non esiste
 * dev'essere impossibile da scrivere.
 *
 * Nessun metodo di rilascio: il Transfer non è un'azione dell'interfaccia. Il
 * compratore conferma, e il rilascio lo esegue il job server-side — se una
 * schermata potesse chiederlo, il denaro dipenderebbe da chi apre una pagina.
 */
export interface OrderService {
  acquisti(): Promise<Result<OrderRecord[]>>;
  vendite(): Promise<Result<OrderRecord[]>>;
  get(id: string): Promise<Result<OrderRecord | null>>;
  /**
   * Solo il venditore, da `pagato`. Idempotente: riaprire la preparazione
   * aggiorna la checklist e non riscrive l'istante di avvio, che è ciò che
   * distingue il seller status «nuovo» da «da_preparare».
   */
  preparaSpedizione(
    id: string,
    checklist: VoceChecklist[],
    foto?: string[],
  ): Promise<Result<OrderRecord>>;
  /** Solo il venditore, da `pagato` o `in_preparazione`. */
  segnaSpedito(id: string, corriere: string, trackingNumber: string): Promise<Result<OrderRecord>>;
  /** Solo il venditore. Fa partire la finestra di verifica. */
  segnaConsegnato(id: string): Promise<Result<OrderRecord>>;
  /** Solo il compratore. Libera i fondi trattenuti. Idempotente. */
  confermaRicezione(id: string): Promise<Result<OrderRecord>>;
  /**
   * Nessun `contesta` qui, dalla Fase 7c: aprire una contestazione significa
   * anche creare il fascicolo con descrizione e foto, e la porta è
   * `DisputeService.apri`. La RPC `ordine_contesta` della 7b resta il motore
   * interno, ma il suo `execute` è stato revocato ad `authenticated` proprio
   * perché lato client resti una sola strada.
   */
}

// ---- Pagamenti -------------------------------------------------------------

/**
 * Ciò che serve al browser per montare **un solo** componente di pagamento.
 *
 * `clientSecret` non è un URL: i metodi disponibili (carta, wallet, PayPal,
 * Satispay) sono capability configurate sull'account presso il fornitore, non
 * flussi separati da costruire. `checkoutUrl` resta per un fornitore che offra
 * soltanto una pagina ospitata.
 *
 * La scomposizione arriva dal server ed è quella congelata sull'ordine: il
 * browser la mostra e non la ricalcola.
 */
export type CheckoutAperto = {
  clientSecret: string | null;
  checkoutUrl: string | null;
  orderId: string;
  amountCents: number;
  prezzoVenditoreCents: number | null;
  commissioneCents: number | null;
  margineObiettivoBps: number | null;
  riferimentoStripePercentualeBps: number | null;
  riferimentoStripeFissoCents: number | null;
  currency: string;
};

export interface PaymentService {
  creaCheckout(input: {
    listingId: string;
    proposalId?: string;
    deliveryMode: OrderDeliveryMode;
    idempotencyKey: string;
  }): Promise<Result<CheckoutAperto>>;
  perOrdine(orderId: string): Promise<Result<PaymentRecord | null>>;
}

// ---- Incassi del venditore -------------------------------------------------

export type SellerPayoutAccount = {
  id: string;
  seller_id: string;
  provider: string;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
  requisiti_pendenti: string[];
  disabled_reason: string | null;
  created_at: string;
  updated_at: string;
};

/**
 * Il dominio che chiude il debito `seller_enabled` della Fase 6a.
 *
 * Non c'è alcun metodo per *abilitare* un venditore, e l'assenza è il punto:
 * `charges_enabled` e `payouts_enabled` arrivano solo da un evento firmato dal
 * fornitore, e da lì un trigger deriva il ruolo. Un'interfaccia può avviare
 * l'onboarding e leggere lo stato, non decretarne l'esito.
 */
export interface SellerPayoutService {
  /** Apre o riprende l'onboarding ospitato e restituisce il link. */
  avviaOnboarding(): Promise<Result<{ onboardingUrl: string; expiresAt: string | null }>>;
  /** Stato del proprio account, o `null` se l'onboarding non è mai partito. */
  mioAccount(): Promise<Result<SellerPayoutAccount | null>>;
}

// ---- Configurazione di mercato ---------------------------------------------

/** Solo la configurazione corrente, dalla vista pubblica a colonne chiuse. */
export type MarketplaceConfigPubblica = {
  margine_obiettivo_bps: number;
  riferimento_stripe_percentuale_bps: number;
  riferimento_stripe_fisso_cents: number;
  auto_rilascio_giorni: number;
};

export interface MarketplaceConfigService {
  corrente(): Promise<Result<MarketplaceConfigPubblica | null>>;
}

// ---- Provider di incasso ---------------------------------------------------
// `PaymentService` è ciò che la UI chiama; `PaymentProvider` è ciò che il server
// usa per parlare con l'incasso. Sono due livelli distinti e non vanno fusi.
// Il modello è `AIProvider` in backend/ai_provider.py — un contratto che non
// nomina il fornitore — non `StripeGatewayProtocol` in backend/stripe_service.py,
// che è una cucitura per sostituire l'SDK e non il provider.

/** Riferimento opaco a una transazione presso il provider. */
export type ProviderPaymentRef = {
  provider: string;
  sessionId: string;
  intentId?: string | null;
};

/**
 * Tutto risolto server-side: nessun campo di questo tipo arriva dal client.
 * Gli identificativi sono di dominio Vinea, non del fornitore: sta all'adapter
 * decidere come trasportarli.
 *
 * Rispecchia `CheckoutRequest` in supabase/functions/_shared/payment-provider.ts,
 * che vive nel runtime Deno e non puo' importare da qui: i due vanno cambiati
 * insieme.
 */
export type CheckoutRequest = {
  orderId: string;
  buyerId: string;
  listingId: string;
  descrizione: string;
  amountCents: number;
  currency: string;
  successUrl: string;
  cancelUrl: string;
  idempotencyKey: string;
  expiresAt: string | null;
};

export type CheckoutHandle = {
  ref: ProviderPaymentRef;
  redirectUrl: string;
};

/**
 * Tassonomia interna degli esiti: non è il vocabolario di nessun provider.
 * Questi identificatori sono anche il contratto verso la RPC
 * `payment_apply_provider_event`, che ramifica su di essi e non sui nomi
 * evento del provider. Aggiungere un caso qui è un cambio di schema.
 */
export type PaymentOutcomeKind =
  | "pending"
  | "authorized"
  | "settled"
  | "failed"
  | "expired"
  | "refunded";

export type PaymentOutcome =
  | { kind: "pending" }
  | { kind: "authorized" }
  | { kind: "settled"; amountCents: number; currency: string; settledAt: string }
  | { kind: "failed"; reason: string }
  | { kind: "expired" }
  | { kind: "refunded"; refundedCents: number; fully: boolean };

/**
 * Evento tradotto dal provider. I campi `declared*` sono dichiarazioni del
 * provider da riverificare server-side contro l'ordine: non sono verità.
 */
export type ProviderEvent = {
  id: string;
  occurredAt: string;
  ref: ProviderPaymentRef;
  outcome: PaymentOutcome;
  declaredAmountCents: number;
  declaredCurrency: string;
  orderRef: string | null;
};

export interface PaymentProvider {
  readonly id: string;
  /** Apre la sessione di checkout presso il provider. */
  apriCheckout(input: CheckoutRequest): Promise<Result<CheckoutHandle>>;
  /** Interroga il provider sullo stato di una transazione. */
  statoPagamento(ref: ProviderPaymentRef): Promise<Result<PaymentOutcome>>;
  /**
   * Verifica la firma e traduce l'evento. Riceve il raw body, non un oggetto
   * già deserializzato: la verifica di firma è sui byte trasmessi.
   * Traduce e basta — non decide e non scrive stato: la transizione resta
   * nella RPC, che riconfronta importo, valuta e ordine.
   */
  interpretaEvento(input: {
    rawBody: string;
    headers: Headers;
    secret: string;
  }): Promise<Result<ProviderEvent>>;
}

// ---- Fase 7c: consegna, tracking, contestazione, recensione ----------------

/**
 * Stato dell'ordine visto dal **venditore**. Non è una colonna: si deriva da
 * `OrderRecord` con `sellerStatusDaOrdine`, che rispecchia la funzione SQL
 * `public.order_seller_stato`. Due colonne di stato sulla stessa riga sono due
 * scritture da tenere allineate, e prima o poi divergono.
 *
 * Rispecchia `SellerOrderStatus` in frontend/src/data/orders.ts: i due elenchi
 * vanno cambiati insieme.
 */
export type SellerOrderStatus =
  | "nuovo"
  | "da_preparare"
  | "da_spedire"
  | "spedito"
  | "consegnato"
  | "completato"
  | "contestato"
  | "rimborsato"
  | "annullato";

/** Rispecchia `public.tracking_event_tipo`. */
export type TrackingEventTipo = "info" | "spedizione" | "consegna" | "problema" | "sistema";

export type TrackingEventRecord = {
  id: number;
  order_id: string;
  tipo: TrackingEventTipo;
  titolo: string;
  descrizione: string | null;
  luogo: string | null;
  created_at: string;
};

/** Rispecchia `public.dispute_stato`. */
export type DisputeStato = "aperta" | "in_valutazione" | "rimborsata" | "risolta" | "respinta";

/**
 * Il fascicolo della contestazione. `risolta_da` non c'è, e l'assenza è
 * deliberata: la colonna esiste ma resta fuori dal `GRANT`, perché chi ha
 * deciso la pratica è dato di moderazione e non informazione dovuta alle parti.
 */
export type DisputeRecord = {
  id: string;
  order_id: string;
  aperta_da: string;
  motivo: string;
  descrizione: string;
  foto: string[];
  stato: DisputeStato;
  esito_nota: string | null;
  apertura_at: string;
  chiusura_at: string | null;
};

export type OrderReviewRecord = {
  id: string;
  order_id: string;
  autore_id: string;
  destinatario_id: string;
  voto: number;
  conformita: number;
  imballaggio: number;
  comunicazione: number;
  testo: string | null;
  created_at: string;
};

/** Una voce della checklist di imballaggio, come la salva il venditore. */
export type VoceChecklist = { id: string; label: string; done: boolean };

export interface TrackingService {
  /** Timeline di un ordine, dal più vecchio al più recente. */
  perOrdine(orderId: string): Promise<Result<TrackingEventRecord[]>>;
}

/**
 * Nessun metodo di risoluzione, e l'assenza è il punto: in `frontend/` il
 * pannello mostrava a entrambe le parti tre bottoni che chiudevano la pratica,
 * sotto la scritta «Azioni demo». Era impalcatura, non un modello di permessi.
 * `ordine_contestazione_risolvi` esiste ma non ha alcun `GRANT` verso
 * `authenticated`: è back-office, e non può essere chiamata da qui.
 */
export interface DisputeService {
  apri(input: {
    orderId: string;
    motivo: string;
    descrizione: string;
    foto?: string[];
  }): Promise<Result<OrderRecord>>;
  perOrdine(orderId: string): Promise<Result<DisputeRecord | null>>;
}

export interface ReviewService {
  invia(input: {
    orderId: string;
    voto: number;
    conformita: number;
    imballaggio: number;
    comunicazione: number;
    testo?: string | null;
  }): Promise<Result<OrderReviewRecord>>;
  perOrdine(orderId: string): Promise<Result<OrderReviewRecord | null>>;
}

// ---- Fase 7c: imballaggio ---------------------------------------------------

/** Come la bottiglia entra nella rete logistica. Vocabolario Vinea, non di un fornitore. */
export type PackagingModalita = "kit_a_domicilio" | "centro_partner" | "punto_quartiere";

/**
 * Un punto fisico dove consegnare la bottiglia. In Fase 7c i dati sono
 * inventati e le coordinate non corrispondono a nulla: questo tipo è la forma
 * che un fornitore vero dovrà riempire, non un indirizzario Vinea.
 */
export type PackagingPoint = {
  id: string;
  nome: string;
  indirizzo: string;
  cap: string;
  citta: string;
  provincia: string;
  /** Finte in Fase 7c. Presenti perché una mappa vera le chiederà. */
  lat: number | null;
  lon: number | null;
  /** Metri in linea d'aria dal riferimento richiesto. Finta in Fase 7c. */
  distanzaMetri: number | null;
  orari: string | null;
};

/**
 * Un'opzione di consegna alla rete logistica. `prezzoCents` è **indicativo per
 * il browser**: l'importo che finisce sull'ordine lo rilegge il server da
 * `packaging_options` al momento della prenotazione. Il client non manda mai
 * un prezzo.
 */
export type PackagingOption = {
  codice: string;
  provider: string;
  modalita: PackagingModalita;
  etichetta: string;
  descrizione: string | null;
  prezzoCents: number;
  /** Se true, la scelta non è completa senza un `PackagingPoint`. */
  richiedePunto: boolean;
};

/** Che cosa resta congelato sull'ordine dopo la scelta. */
export type PackagingSelection = {
  codice: string | null;
  provider: string | null;
  etichetta: string | null;
  prezzoCents: number;
  puntoId: string | null;
  puntoNome: string | null;
  sceltoAt: string | null;
};

/**
 * Ciò che l'interfaccia chiama. Non conosce alcun fornitore e non decide alcun
 * prezzo: chiede il listino per mostrarlo, registra una dichiarazione per
 * codice sull'annuncio, e dopo il pagamento registra il punto fisico — che non
 * ha prezzo e quindi non muove alcun importo.
 */
export interface PackagingService {
  /** Il listino corrente, dalla vista pubblica a colonne chiuse. */
  opzioni(): Promise<Result<PackagingOption[]>>;
  /** Punti disponibili per un'opzione, vicino a un riferimento geografico. */
  punti(input: {
    codice: string;
    cap: string | null;
  }): Promise<Result<PackagingPoint[]>>;
  /**
   * Il venditore dichiara il metodo sull'annuncio. Nessun prezzo fra i
   * parametri: lo risolve `order_checkout_reserve` dalla versione corrente.
   */
  dichiaraSuAnnuncio(listingId: string, codice: string | null): Promise<Result<void>>;
  /** Il venditore sceglie il punto fisico, dopo il pagamento. Non tocca importi. */
  scegliPunto(input: {
    orderId: string;
    puntoId: string;
    puntoNome: string;
  }): Promise<Result<OrderRecord>>;
}

/**
 * Ciò che il **server** userà per parlare con la rete logistica. Un fornitore
 * vero implementa questo, non `PackagingService`. Il modello è `AIProvider` in
 * backend/ai_provider.py — un contratto che non nomina il fornitore — e la
 * stessa distinzione a due livelli di `PaymentService` / `PaymentProvider`.
 *
 * In Fase 7c l'unica implementazione è `FakePackagingProvider` e vive nel
 * browser, perché non esiste alcuna chiamata esterna da nascondere dietro una
 * Edge Function. Quando il fornitore sarà vero, l'implementazione si sposta
 * dietro una Edge Function e questa interfaccia non cambia.
 */
export interface PackagingProvider {
  readonly id: string;
  opzioniDisponibili(input: {
    near: { cap: string; citta: string; provincia: string } | null;
    formato: string | null;
    quantita: number;
  }): Promise<Result<PackagingOption[]>>;
  puntiVicini(input: { codice: string; cap: string | null }): Promise<Result<PackagingPoint[]>>;
  /**
   * Conferma la scelta presso il fornitore. In Fase 7c non fa nulla di remoto e
   * restituisce un riferimento inventato. Esiste già ora perché un fornitore
   * vero emette qui un identificativo di ritiro, e aggiungerlo dopo
   * significherebbe cambiare la firma dell'unico punto di integrazione.
   */
  prenota(input: {
    codice: string;
    puntoId: string | null;
    riferimentoOrdine: string;
  }): Promise<Result<{ provider: string; prenotazioneId: string }>>;
}

// ---- Messaggi --------------------------------------------------------------
export type PageCursor = {
  createdAt: string;
  id: string;
};

export type RealtimeState =
  | "idle"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "offline"
  | "error";

export type ConversationParticipant = {
  userId: string;
  username: string;
  avatarUrl: string;
};

export type ConversationSummary = {
  id: string;
  listingId: string;
  listingSlug: string;
  listingPriceCents: number;
  orderId: string | null;
  orderStatus: string | null;
  counterpart: ConversationParticipant;
  wineName: string;
  wineImage: string;
  writable: boolean;
  lastMessageId: string | null;
  lastMessageAt: string | null;
  lastMessagePreview: string | null;
  unreadCount: number;
  activityAt: string;
  createdAt: string;
};

export type ConversationPage = {
  items: ConversationSummary[];
  nextCursor: PageCursor | null;
};

export type Message = {
  id: string;
  conversationId: string;
  senderId: string | null;
  kind: "user" | "system";
  body: string;
  createdAt: string;
};

export type MessagePage = {
  items: Message[];
  nextCursor: PageCursor | null;
};

export type OpenConversationInput =
  | { listingId: string; orderId?: never }
  | { listingId?: never; orderId: string };

export type SendMessageInput = {
  conversationId: string;
  text: string;
  idempotencyKey: string;
};

export interface MessagingService {
  conversazioni(cursor?: PageCursor, limit?: number): Promise<Result<ConversationPage>>;
  messaggi(
    conversationId: string,
    cursor?: PageCursor,
    limit?: number,
  ): Promise<Result<MessagePage>>;
  apri(input: OpenConversationInput): Promise<Result<{ conversationId: string }>>;
  invia(input: SendMessageInput): Promise<Result<Message>>;
  segnaLetti(conversationId: string, messageId?: string): Promise<Result<void>>;
}

// ---- Club — Fase 12a -------------------------------------------------------
//
// Questo blocco sostituisce uno stub che stava qui da prima della Fase 12: gli
// stessi quattro metodi, ma con `unknown[]`, `unknown | null` e `void`, cioe
// senza un tipo di ritorno e senza un ramo d'errore. Era il segnaposto di un
// dominio che viveva nello store demo, non un contratto.
//
// La forma e quella della convenzione Result delle Fasi 7 e 8, non le promesse
// nude di ModerationService: quella e piu vecchia della convenzione, non un
// modello da seguire.
//
// Nessun metodo prende un `userId`, in nessuna posizione. Non e una
// preferenza di stile: `club_memberships.user_id` arriva da `DEFAULT
// auth.uid()` e non e nel grant di INSERT, quindi un parametro del genere non
// avrebbe nemmeno un posto in cui finire.

export type Club = {
  slug: string;
  nome: string;
  // I quattro assi di filtro sono opzionali: un club per tipologia non ha un
  // territorio, uno per territorio non ha un produttore.
  territorio: string | null;
  denominazione: string | null;
  produttore: string | null;
  tipologia: string | null;
  descrizione: string;
  regole: string[];
  // Conteggio calcolato dalla vista: `club_memberships` non e leggibile oltre
  // le righe proprie, quindi il client non ha modo di derivarlo da se.
  membri: number;
  // Stato del solo chiamante. Per un visitatore anonimo e sempre `false`.
  seguito: boolean;
  createdAt: string;
};

// ---- Contenuti dei club (12b) -----------------------------------------------
//
// I sette valori sono quelli di PostTipo del mock
// (frontend/src/data/communities.ts:134-135), replicati qui perche il CHECK a
// database e questa unione devono dire la stessa cosa. A database e un CHECK e
// non un enum: sono etichette di filtro della UI, non gli stati di una
// macchina.
export type ClubPostTipo =
  | "discussione"
  | "domanda"
  | "degustazione"
  | "confronto"
  | "consiglio"
  | "sondaggio"
  | "annuncio";

// Il vino di cui un post parla, risolto dal server da `wine_id` oppure dalla
// bottiglia collegata. La vista NON pubblica l'identificativo della bottiglia:
// cio che l'autore rende pubblico e la bottiglia di cui parla, non la chiave
// con cui la sua cantina la nomina.
export type ClubPostVino = {
  slug: string;
  produttore: string;
  nome: string;
  annata: number;
};

// L'annuncio collegato, quando esiste ancora ed e ancora pubblico. E' `null`
// anche per un post che ne aveva uno: se nel frattempo e stato sospeso o
// venduto la vista non lo risolve piu, e il post resta leggibile senza.
export type ClubPostAnnuncio = {
  id: string;
  slug: string;
  prezzoCents: number;
};

export type ClubPost = {
  id: string;
  clubSlug: string;
  tipo: ClubPostTipo;
  titolo: string;
  corpo: string;
  autoreId: string;
  autoreUsername: string;
  autoreAvatarUrl: string | null;
  vino: ClubPostVino | null;
  annuncio: ClubPostAnnuncio | null;
  risposte: number;
  miPiace: number;
  // Stato del solo chiamante, come `seguito` su Club. Per un anonimo e sempre
  // `false`.
  piaciuto: boolean;
  // Se il post e del chiamante. La UI ci decide se offrire "Segnala": non si
  // segnala se stessi.
  mio: boolean;
  createdAt: string;
};

export type ClubPostRisposta = {
  id: string;
  postId: string;
  corpo: string;
  autoreId: string;
  autoreUsername: string;
  autoreAvatarUrl: string | null;
  mio: boolean;
  createdAt: string;
};

// I tre allegati sono facoltativi e nessuno di essi e verificato dal client:
// la bottiglia dev'essere dell'autore e l'annuncio dev'essere pubblico, e
// entrambe le cose le stabilisce un trigger a database. Qui sono opzionali
// perche la maggior parte dei post non ne ha.
export type NuovoClubPost = {
  clubSlug: string;
  tipo: ClubPostTipo;
  titolo: string;
  corpo: string;
  bottleUnitId?: string | null;
  wineId?: string | null;
  listingId?: string | null;
};

export interface ClubService {
  elenco(): Promise<Result<Club[]>>;
  // `null` e una risposta legittima e non un errore: lo slug non esiste.
  dettaglio(slug: string): Promise<Result<Club | null>>;
  // Restituiscono il club riletto e non `void`: seguire cambia `membri`, che
  // e un conteggio del server. Farlo indovinare al client significa mostrare
  // un numero che diverge dal database al primo caso concorrente.
  segui(slug: string): Promise<Result<Club>>;
  smettiSegui(slug: string): Promise<Result<Club>>;

  // ---- 12b: contenuti ------------------------------------------------------
  // Nessuna di queste firme accetta un identificativo di utente, per la stessa
  // ragione delle quattro sopra: `autore_id` arriva da un DEFAULT del database
  // e non e nel grant di INSERT, quindi un parametro del genere non avrebbe
  // nemmeno un posto in cui finire.
  discussioni(clubSlug: string): Promise<Result<ClubPost[]>>;
  creaDiscussione(input: NuovoClubPost): Promise<Result<ClubPost>>;
  risposte(postId: string): Promise<Result<ClubPostRisposta[]>>;
  creaRisposta(postId: string, corpo: string): Promise<Result<ClubPostRisposta>>;
  // Restituiscono il post riletto, non `void`: `miPiace` e un conteggio del
  // server, e farlo indovinare al client lo fa divergere al primo caso
  // concorrente. Stessa scelta gia fatta per `segui`.
  mettiLike(postId: string): Promise<Result<ClubPost>>;
  togliLike(postId: string): Promise<Result<ClubPost>>;
}

// ---- Notifiche -------------------------------------------------------------
export type NotificationDestination =
  | { kind: "none" }
  | { kind: "conversation"; conversationId: string }
  | { kind: "listing"; listingId: string }
  | { kind: "order"; orderId: string }
  | { kind: "club"; clubSlug: string };

export type Notification = {
  id: string;
  category: "marketplace" | "community" | "sistema";
  eventType: string;
  body: string;
  destination: NotificationDestination;
  readAt: string | null;
  createdAt: string;
};

export type NotificationPage = {
  items: Notification[];
  nextCursor: PageCursor | null;
};

export interface NotificationService {
  elenco(cursor?: PageCursor, limit?: number): Promise<Result<NotificationPage>>;
  nonLette(): Promise<Result<number>>;
  segnaLetta(id: string): Promise<Result<void>>;
  segnaTutteLette(): Promise<Result<number>>;
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

// ---- AI — Fase 10 ----------------------------------------------------------
//
// Questo blocco sostituisce un'interfaccia `AiService` dimostrativa che stava
// qui da prima della Fase 10, con tre metodi — `identificaBottiglia`,
// `miglioraSfondo`, `suggerisciAbbinamento` — e nessuna implementazione, né
// mock né reale. Non descriveva il perimetro migrato: due dei tre metodi erano
// funzionalità che nel legacy non esistono (identificazione da foto, sfondo
// reale) e mancavano invece le due che esistono, la chat Sommelier e il
// suggerimento di catalogazione. Era una dichiarazione di intenti, non un
// contratto, e va corretta la nota che diceva il contrario: `AiService`
// esisteva, semplicemente descriveva un'altra cosa.
//
// Ciò che segue è il perimetro del checkpoint 10a + 10b: le tre funzionalità
// che il legacy ha davvero. `identificaBottiglia` e `miglioraSfondo` tornano
// con la 7.3a e la 7.13, che hanno una sessione di spec propria.
export type AiJobStatus =
  "in_attesa" | "in_elaborazione" | "completata" | "richiede_conferma" | "fallita";

/** Un vino proposto dall'abbinamento. */
export type AbbinamentoScelta = {
  /**
   * Identificativo di un annuncio di `public_listings`, non di un vino di
   * catalogo: con la decisione 7.8 i candidati li risolve il server, quindi un
   * identificativo proposto è dimostrabilmente un annuncio reale e pubblicato.
   * Nel JSON che il modello produce il campo si chiama ancora `wine_id`, perché
   * il prompt di sistema è quello del legacy e non è stato riscritto.
   */
  annuncioId: string;
  motivazione: string;
};

export type Abbinamento = {
  intro: string;
  scelte: AbbinamentoScelta[];
};

/** I nove campi di `ListingResponse` (`backend/ai_routes.py:232-241`). */
export type CatalogazioneSuggerimento = {
  nome: string;
  produttore: string;
  annata: number | null;
  denominazione: string;
  regione: string;
  tipologia: string;
  noteDegustazione: string;
  condizioniSuggerite: string;
  /** Sempre in [0,1]: fuori intervallo o assente vale 0. */
  confidence: number;
};

export type SommelierRuolo = "utente" | "sommelier";

export type SommelierMessaggio = {
  ruolo: SommelierRuolo;
  contenuto: string;
  createdAt: string;
};

export type SommelierEsito = {
  testo: string;
  /**
   * Vero quando lo stream è finito senza l'evento di chiusura. La decisione 7.7
   * lo tratta come **caso atteso** e non come errore raro: una Edge Function che
   * inoltra uno stream può essere troncata quando il worker viene ritirato, e
   * una risposta parziale è una risposta da tenere, non un guasto da mostrare.
   */
  troncato: boolean;
};

export interface AiService {
  /** Abbinamento cibo-vino. Il catalogo lo risolve il server (7.8). */
  abbinamento(query: string): Promise<Result<Abbinamento>>;
  /** Suggerimento di catalogazione da testo. Almeno uno dei due campi. */
  catalogazione(
    input: { ocrText?: string; hint?: string },
  ): Promise<Result<CatalogazioneSuggerimento>>;
  /** Storico di una conversazione, già filtrato su (proprietario, sessione). */
  sommelierStorico(sessionId: string): Promise<Result<SommelierMessaggio[]>>;
  sommelierCancella(sessionId: string): Promise<Result<void>>;
  /**
   * Una battuta di conversazione. `onDelta` riceve i frammenti mano a mano;
   * l'esito finale dice se lo stream è arrivato in fondo.
   */
  sommelierChat(
    input: { sessionId: string; messaggio: string },
    onDelta: (delta: string) => void,
  ): Promise<Result<SommelierEsito>>;
}
