// Fase 9a/9b - adapter Supabase dietro ModerationService.
//
// Le quattro letture del checkpoint 9a passano tutte da una proiezione, mai da
// una tabella: moderation_report_queue, moderation_report_events,
// moderation_dispute_queue, moderation_audit_log, my_reports, my_report_events.
// Le tabelle reports, report_events e audit_log non hanno alcun grant client,
// quindi una `.from("reports")` qui non fallirebbe per una svista di codice ma
// con un permission denied dal database.
//
// La scrittura del 9a e `segnala`, che chiama la RPC public.segnalazione_invia:
// identita da auth.uid(), priorita derivata sul server, motivo vincolato
// all'elenco chiuso, rate limit 10/ora.
//
// IL 9B E LE DUE FIRME CHE L'INTERFACCIA GIA AVEVA.
// ModerationService dichiara `aggiornaStato(id, stato, nota)` e
// `eseguiAzione(target, azione, motivo)` — due firme scritte per un mock in cui
// lo stato di una pratica era una leva indipendente. A database non lo e: uno
// stato e la conseguenza di un'azione, e le sette RPC sono per pratica, non per
// stato. Le due firme restano quelle e non vengono riscritte; sono implementate
// per la parte che sanno esprimere e sollevano, con un messaggio che dice
// perche, per la parte che non sanno. Il resto vive accanto all'interfaccia,
// esportato a parte — la stessa scelta gia fatta nel 9a per `codaContestazioni`
// e `motiviAmmessi`, che ModerationService non contempla.

import type { SupabaseClient } from "@supabase/supabase-js";
import { noPhase9Client, phase9Throw } from "@/services/phase9/shared";
import type { ModerationService } from "@/services/types";
// types.ts importa questi tipi da @/data/moderation senza riesportarli: la
// fonte e quella, e prenderli da li tiene una definizione sola.
import type {
  AuditEntry,
  ModAction,
  Priorita,
  Report,
  ReportHistoryEntry,
  ReportStatus,
  ReportTargetType,
} from "@/data/moderation";

// ---------------------------------------------------------------------------
// Righe come arrivano dalle proiezioni
// ---------------------------------------------------------------------------

type QueueRow = {
  id: string;
  codice: string;
  target_tipo: ReportTargetType;
  target_label: string;
  target_id: string | null;
  motivo: string;
  descrizione: string;
  foto: string[] | null;
  stato: ReportStatus;
  priorita: Priorita;
  reporter_id: string;
  reporter_username: string;
  club_slug: string | null;
  created_at: string;
  updated_at: string;
};

// my_reports non espone reporter_id ne reporter_username: il segnalante e
// sempre il chiamante, e la decisione 7.4 vuole che il dato non viaggi verso
// chi non e il moderatore.
type MyReportRow = Omit<QueueRow, "reporter_id" | "reporter_username">;

type ModEventRow = {
  id: string;
  report_id: string;
  visibile: boolean;
  testo: string;
  autore_etichetta: string;
  created_at: string;
};

// my_report_events non espone `visibile`: la colonna e il filtro della vista,
// non un dato del client. Se arrivasse, il segnalante saprebbe dell'esistenza
// di una nota interna pur non leggendola.
type MyEventRow = Omit<ModEventRow, "visibile">;

type AuditRow = {
  id: string;
  ts: string;
  attore_username: string;
  scope: AuditEntry["scope"];
  club_slug: string | null;
  azione: AuditEntry["azione"];
  target_tipo: ReportTargetType;
  target_id: string | null;
  target_label: string;
  motivazione: string;
  durata: string | null;
  report_id: string | null;
};

export type DisputeQueueRow = {
  id: string;
  orderId: string;
  apertaDa: string;
  apertaDaUsername: string;
  sellerId: string;
  sellerUsername: string;
  motivo: string;
  descrizione: string;
  foto: string[];
  stato: "aperta" | "in_valutazione" | "rimborsata" | "risolta" | "respinta";
  esitoNota: string | null;
  risoltaDa: string | null;
  aperturaAt: string;
  chiusuraAt: string | null;
  ordineStato: string;
  ordinePayoutStato: string;
  totaleCents: number;
  addebitoTotaleCents: number;
};

// ---------------------------------------------------------------------------
// Mappatori
// ---------------------------------------------------------------------------

const mapEvento = (row: ModEventRow | MyEventRow): ReportHistoryEntry => ({
  ts: row.created_at,
  testo: row.testo,
  autore: row.autore_etichetta,
});

const raggruppaEventi = <T extends { report_id: string }>(righe: T[]): Map<string, T[]> => {
  const per = new Map<string, T[]>();
  for (const riga of righe) {
    const gruppo = per.get(riga.report_id);
    if (gruppo) gruppo.push(riga);
    else per.set(riga.report_id, [riga]);
  }
  return per;
};

export const mapQueueReport = (
  row: QueueRow,
  eventi: ModEventRow[] = [],
): Report => ({
  id: row.id,
  targetType: row.target_tipo,
  targetId: row.target_id ?? "",
  targetLabel: row.target_label,
  reason: row.motivo,
  descrizione: row.descrizione,
  foto: row.foto ?? [],
  stato: row.stato,
  priorita: row.priorita,
  reporter: row.reporter_username,
  // Nessun assignee: decisione 7.5, la coda e condivisa e il dato non esiste
  // nemmeno come colonna.
  clubSlug: row.club_slug ?? undefined,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  storia: eventi.filter((e) => e.visibile).map(mapEvento),
  noteInterne: eventi.filter((e) => !e.visibile).map(mapEvento),
});

export const mapMyReport = (row: MyReportRow, eventi: MyEventRow[] = []): Report => ({
  id: row.id,
  targetType: row.target_tipo,
  targetId: row.target_id ?? "",
  targetLabel: row.target_label,
  reason: row.motivo,
  descrizione: row.descrizione,
  foto: row.foto ?? [],
  stato: row.stato,
  priorita: row.priorita,
  // Il segnalante e il chiamante: la proiezione non lo ripete e qui non si
  // inventa un'etichetta. La schermata "Le mie segnalazioni" non la mostra.
  reporter: "",
  clubSlug: row.club_slug ?? undefined,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  storia: eventi.map(mapEvento),
  // Le note interne non hanno alcun percorso verso il segnalante: la vista non
  // le restituisce, quindi qui l'array e vuoto per costruzione e non per
  // filtro applicativo.
  noteInterne: [],
});

export const mapAuditEntry = (row: AuditRow): AuditEntry => ({
  id: row.id,
  ts: row.ts,
  attore: row.attore_username,
  scope: row.scope,
  clubSlug: row.club_slug ?? undefined,
  azione: row.azione,
  target: row.target_label,
  motivazione: row.motivazione,
  durata: row.durata ?? undefined,
  // Nessun `ricorso`: decisione 7.8b, la colonna non esiste a database.
});

export const mapDisputeRow = (row: {
  id: string;
  order_id: string;
  aperta_da: string;
  aperta_da_username: string;
  seller_id: string;
  seller_username: string;
  motivo: string;
  descrizione: string;
  foto: string[] | null;
  stato: DisputeQueueRow["stato"];
  esito_nota: string | null;
  risolta_da: string | null;
  apertura_at: string;
  chiusura_at: string | null;
  ordine_stato: string;
  ordine_payout_stato: string;
  totale_cents: number;
  addebito_totale_cents: number;
}): DisputeQueueRow => ({
  id: row.id,
  orderId: row.order_id,
  apertaDa: row.aperta_da,
  apertaDaUsername: row.aperta_da_username,
  sellerId: row.seller_id,
  sellerUsername: row.seller_username,
  motivo: row.motivo,
  descrizione: row.descrizione,
  foto: row.foto ?? [],
  stato: row.stato,
  esitoNota: row.esito_nota,
  risoltaDa: row.risolta_da,
  aperturaAt: row.apertura_at,
  chiusuraAt: row.chiusura_at,
  ordineStato: row.ordine_stato,
  ordinePayoutStato: row.ordine_payout_stato,
  totaleCents: row.totale_cents,
  addebitoTotaleCents: row.addebito_totale_cents,
});

// Le proiezioni non sono paginate: ModerationService dichiara Promise<Report[]>
// e non una pagina con cursore. Un tetto esplicito e comunque necessario,
// perche una coda senza limite diventa una lettura illimitata il giorno in cui
// le righe crescono. Quando servira la paginazione andra cambiata
// l'interfaccia, che e una decisione e non una correzione.
const TETTO_CODA = 200;
const TETTO_AUDIT = 200;

// ---------------------------------------------------------------------------
// Adapter
// ---------------------------------------------------------------------------

export const createSupabaseModerationService = (
  client: SupabaseClient | null,
): ModerationService => ({
  segnala: async (input) => {
    if (!client) return noPhase9Client("segnala");

    const rpcName =
      input.targetType === "club" ? "segnalazione_club_invia" : "segnalazione_invia";
    const rpcArgs =
      input.targetType === "club"
        ? {
            p_club_slug: input.clubSlug,
            p_motivo: input.reason,
            p_descrizione: input.descrizione ?? "",
          }
        : {
            p_target_tipo: input.targetType,
            p_target_id: input.targetId,
            p_target_label: input.targetLabel,
            p_motivo: input.reason,
            p_descrizione: input.descrizione ?? "",
            p_foto: input.foto ?? [],
            p_club_slug: input.clubSlug ?? null,
          };

    if (input.targetType === "club" && !input.clubSlug?.trim()) {
      return phase9Throw(rpcName, {
        code: "22023",
        message: "Club non valido.",
      });
    }

    const { data, error } = await client.rpc(rpcName, rpcArgs);
    if (error) return phase9Throw(rpcName, error);

    // La RPC restituisce l'id. La riga canonica si rilegge dalla proiezione:
    // stato, priorita e codice sono decisi dal server e non si ricostruiscono
    // qui, altrimenti la UI mostrerebbe una priorita indovinata dal client.
    const creata = await client
      .from("my_reports")
      .select("*")
      .eq("id", data as string)
      .maybeSingle();
    if (creata.error) return phase9Throw("my_reports", creata.error);
    if (!creata.data) {
      return phase9Throw("my_reports", {
        code: "P0001",
        message: "Segnalazione inviata ma non rileggibile.",
      });
    }
    return mapMyReport(creata.data as MyReportRow);
  },

  segnalazioniUtente: async () => {
    if (!client) return noPhase9Client("segnalazioniUtente");
    // L'argomento userId dell'interfaccia non viene usato: il filtro e dentro
    // my_reports, che confronta reporter_id con auth.uid(). Accettare un id dal
    // chiamante e lasciare che scelga di chi leggere le pratiche sarebbe
    // esattamente il frontend come confine di fiducia.
    const { data, error } = await client
      .from("my_reports")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(TETTO_CODA);
    if (error) return phase9Throw("my_reports", error);

    const righe = (data ?? []) as MyReportRow[];
    if (righe.length === 0) return [];

    const eventi = await client
      .from("my_report_events")
      .select("*")
      .in("report_id", righe.map((r) => r.id))
      .order("created_at", { ascending: true });
    if (eventi.error) return phase9Throw("my_report_events", eventi.error);

    const per = raggruppaEventi((eventi.data ?? []) as MyEventRow[]);
    return righe.map((riga) => mapMyReport(riga, per.get(riga.id) ?? []));
  },

  coda: async () => {
    if (!client) return noPhase9Client("coda");
    // Ordine della coda: priorita discendente e poi la piu vecchia per prima.
    // Nessuno SLA (decisione 7.8a): la priorita ordina, non promette un tempo.
    const { data, error } = await client
      .from("moderation_report_queue")
      .select("*")
      .order("priorita", { ascending: false })
      .order("created_at", { ascending: true })
      .limit(TETTO_CODA);
    if (error) return phase9Throw("moderation_report_queue", error);

    const righe = (data ?? []) as QueueRow[];
    if (righe.length === 0) return [];

    const eventi = await client
      .from("moderation_report_events")
      .select("*")
      .in("report_id", righe.map((r) => r.id))
      .order("created_at", { ascending: true });
    if (eventi.error) return phase9Throw("moderation_report_events", eventi.error);

    const per = raggruppaEventi((eventi.data ?? []) as ModEventRow[]);
    return righe.map((riga) => mapQueueReport(riga, per.get(riga.id) ?? []));
  },

  auditLog: async () => {
    if (!client) return noPhase9Client("auditLog");
    const { data, error } = await client
      .from("moderation_audit_log")
      .select("*")
      .order("ts", { ascending: false })
      .limit(TETTO_AUDIT);
    if (error) return phase9Throw("moderation_audit_log", error);
    return ((data ?? []) as AuditRow[]).map(mapAuditEntry);
  },

  // ---- checkpoint 9b -------------------------------------------------------

  // Solo i due stati che un'azione produce davvero. `in_revisione` e `risolta`
  // non hanno una porta propria: sono l'effetto di richiesta_modifiche e delle
  // quattro azioni che chiudono la pratica, e sceglierne una qui significherebbe
  // decidere al posto del moderatore quale provvedimento ha preso. `inviata` e
  // lo stato iniziale e non si torna indietro.
  aggiornaStato: async (id, stato, nota) => {
    const azione = AZIONE_PER_STATO[stato];
    if (!azione) {
      return phase9Throw("aggiornaStato", {
        code: "22023",
        message:
          "Lo stato di una pratica e la conseguenza di un'azione: usa l'azione di moderazione corrispondente.",
      });
    }
    await azionePratica(client, { reportId: id, azione, motivazione: nota ?? "" });
  },

  // L'interfaccia passa il bersaglio e non la pratica, quindi qui si arriva
  // alle porte per annuncio, che sono per bersaglio. Le azioni che vivono sulla
  // pratica (ammonizione, chiusura, info_richieste) non hanno un equivalente
  // per bersaglio e non se ne inventa uno.
  eseguiAzione: async (target, azione, motivo) => {
    if (target.tipo !== "annuncio") {
      return phase9Throw("eseguiAzione", {
        code: "22023",
        message: "Per questo bersaglio l'azione passa dalla pratica di segnalazione.",
      });
    }
    const transizione = TRANSIZIONE_PER_AZIONE[azione];
    if (!transizione) {
      return phase9Throw("eseguiAzione", {
        code: "22023",
        message: "Questa azione non ha un effetto sullo stato di un annuncio.",
      });
    }
    return azioneAnnuncio(client, target.id, transizione, motivo);
  },
});

// ---------------------------------------------------------------------------
// Le sette azioni sulla pratica
// ---------------------------------------------------------------------------
// Sette RPC distinte a database, sette voci qui: la mappa non e una funzione
// parametrica travestita, e il nome della RPC che il client invoca cambia con
// l'azione. Se domani una delle sette venisse revocata ad `authenticated`, il
// fallimento sarebbe di quella sola azione.

const RPC_PRATICA: Record<ModAction, string> = {
  info_richieste: "moderazione_info_richieste",
  richiesta_modifiche: "moderazione_richiesta_modifiche",
  ammonizione: "moderazione_ammonizione",
  sospensione: "moderazione_sospensione",
  rimozione: "moderazione_rimozione",
  ripristino: "moderazione_ripristino",
  chiusura: "moderazione_chiusura",
};

const AZIONE_PER_STATO: Partial<Record<ReportStatus, ModAction>> = {
  info_richieste: "info_richieste",
  respinta: "chiusura",
};

export type AzionePraticaInput = {
  reportId: string;
  azione: ModAction;
  motivazione: string;
  // Solo `sospensione` la accetta: audit_log ha un CHECK che rifiuta una durata
  // su qualunque altra azione, quindi passarla altrove sarebbe un errore di
  // database e non un campo ignorato.
  durata?: string;
  notaInterna?: string;
};

export const azionePratica = async (
  client: SupabaseClient | null,
  input: AzionePraticaInput,
): Promise<void> => {
  if (!client) return noPhase9Client("azionePratica");
  // La motivazione e obbligatoria a database (NOT NULL con CHECK su
  // audit_log.motivazione, piu il controllo in testa a ogni RPC). Fermarla qui
  // risparmia un giro di rete; il vincolo autoritativo resta quello.
  if (input.motivazione.trim().length === 0) {
    return phase9Throw("azionePratica", {
      code: "22023",
      message: "Una motivazione e obbligatoria.",
    });
  }

  const nome = RPC_PRATICA[input.azione];
  const parametri: Record<string, string | null> = {
    p_report_id: input.reportId,
    p_motivazione: input.motivazione.trim(),
    p_nota_interna: input.notaInterna?.trim() || null,
  };
  if (input.azione === "sospensione") {
    parametri.p_durata = input.durata?.trim() || null;
  }

  const { error } = await client.rpc(nome, parametri);
  if (error) phase9Throw(nome, error);
};

// ---------------------------------------------------------------------------
// Le transizioni di moderazione su un annuncio
// ---------------------------------------------------------------------------

export type TransizioneAnnuncio =
  | "in_revisione"
  | "modifiche_richieste"
  | "rifiutato"
  | "sospeso"
  | "attivo";

const RPC_ANNUNCIO: Record<TransizioneAnnuncio, string> = {
  in_revisione: "moderazione_annuncio_in_revisione",
  modifiche_richieste: "moderazione_annuncio_modifiche_richieste",
  rifiutato: "moderazione_annuncio_rifiuta",
  sospeso: "moderazione_annuncio_sospendi",
  attivo: "moderazione_annuncio_ripristina",
};

// Le tre azioni che restano fuori — ammonizione, chiusura, info_richieste — non
// spostano lo stato di un annuncio: appartengono alla pratica.
const TRANSIZIONE_PER_AZIONE: Partial<Record<ModAction, TransizioneAnnuncio>> = {
  richiesta_modifiche: "modifiche_richieste",
  sospensione: "sospeso",
  rimozione: "rifiutato",
  ripristino: "attivo",
};

export const azioneAnnuncio = async (
  client: SupabaseClient | null,
  listingId: string,
  transizione: TransizioneAnnuncio,
  motivazione: string,
): Promise<AuditEntry> => {
  if (!client) return noPhase9Client("azioneAnnuncio");
  if (motivazione.trim().length === 0) {
    return phase9Throw("azioneAnnuncio", {
      code: "22023",
      message: "Una motivazione e obbligatoria.",
    });
  }

  const nome = RPC_ANNUNCIO[transizione];
  const { error } = await client.rpc(nome, {
    p_listing_id: listingId,
    p_motivazione: motivazione.trim(),
  });
  if (error) return phase9Throw(nome, error);

  // La RPC non restituisce nulla: la riga di audit e la sola prova dell'azione
  // e si rilegge dalla proiezione, dove attore_username e l'istantanea che il
  // registro conserva. Ricostruirla qui significherebbe inventare l'attore.
  const { data, error: erroreAudit } = await client
    .from("moderation_audit_log")
    .select("*")
    .eq("target_id", listingId)
    .order("ts", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (erroreAudit) return phase9Throw("moderation_audit_log", erroreAudit);
  if (!data) {
    return phase9Throw("moderation_audit_log", {
      code: "P0001",
      message: "Azione eseguita ma non rileggibile dal registro.",
    });
  }
  return mapAuditEntry(data as AuditRow);
};

// ---------------------------------------------------------------------------
// Il motivo dell'ultima transizione, per i propri annunci
// ---------------------------------------------------------------------------
// `listings.stato_motivo` non e nel GRANT di colonna di nessun ruolo client,
// proprietario compreso: senza questa proiezione un venditore vede il proprio
// annuncio passare a `rifiutato` e non puo sapere perche. La schermata che la
// mostra non e in questo checkpoint — frontend/src/components/vinea/States.tsx:474
// ha «Leggi motivazione» fra le azioni di un annuncio rifiutato, quindi il posto
// dove metterla esiste gia nella versione servita — ma la porta di lettura si.

export type MotivoModerazioneAnnuncio = {
  listingId: string;
  slug: string;
  stato: string;
  motivo: string;
  aggiornatoAt: string | null;
};

export const motiviModerazioneAnnunci = async (
  client: SupabaseClient | null,
): Promise<MotivoModerazioneAnnuncio[]> => {
  if (!client) return noPhase9Client("motiviModerazioneAnnunci");
  const { data, error } = await client
    .from("my_listing_moderation")
    .select("*")
    .order("stato_aggiornato_at", { ascending: false });
  if (error) return phase9Throw("my_listing_moderation", error);
  return ((data ?? []) as {
    listing_id: string;
    slug: string;
    stato: string;
    stato_motivo: string;
    stato_aggiornato_at: string | null;
  }[]).map((riga) => ({
    listingId: riga.listing_id,
    slug: riga.slug,
    stato: riga.stato,
    motivo: riga.stato_motivo,
    aggiornatoAt: riga.stato_aggiornato_at,
  }));
};

// La coda contestazioni non appartiene a ModerationService: quell'interfaccia
// descrive le segnalazioni. Contestazioni e segnalazioni restano due code
// distinte con due tabelle distinte, unite solo dall'audit e dalla schermata —
// fonderle sarebbe un ridisegno, non una migrazione.
export const codaContestazioni = async (
  client: SupabaseClient | null,
): Promise<DisputeQueueRow[]> => {
  if (!client) return noPhase9Client("codaContestazioni");
  const { data, error } = await client
    .from("moderation_dispute_queue")
    .select("*")
    .order("apertura_at", { ascending: true })
    .limit(TETTO_CODA);
  if (error) return phase9Throw("moderation_dispute_queue", error);
  return (data ?? []).map((row) => mapDisputeRow(row as Parameters<typeof mapDisputeRow>[0]));
};

// ---------------------------------------------------------------------------
// D10 - la risoluzione di una contestazione dal pannello
// ---------------------------------------------------------------------------
// La coda contestazioni era in sola lettura: la vista la mostrava e non
// esisteva alcuna porta di scrittura raggiungibile dal browser. Il motore -
// public.ordine_contestazione_risolvi - e concesso al solo service_role, e
// resta li: `moderazione_contestazione_risolvi` e una porta nuova e piu
// stretta che lo riusa senza duplicarne la semantica.
//
// Due esiti soli. `rimborsata` non e nella firma della porta - non e escluso
// qui e ammesso la: il database non sa nemmeno riceverlo da questa strada,
// finche refund e provider restano spenti. Il tipo qui sotto e la stessa lista
// del `check` in SQL, non una copia che possa divergere in silenzio: se un
// giorno divergesse, il database rifiuterebbe con 22023 invece di eseguire.

export type EsitoContestazioneAdmin = "risolta" | "respinta";

export type EsitoRisoluzione = {
  orderId: string;
  disputeStato: DisputeQueueRow["stato"];
  chiusuraAt: string | null;
  /** Vero quando la pratica era gia terminale: nessuna seconda scrittura. */
  giaChiusa: boolean;
};

export const risolviContestazione = async (
  client: SupabaseClient | null,
  input: { orderId: string; esito: EsitoContestazioneAdmin; nota: string },
): Promise<EsitoRisoluzione> => {
  if (!client) return noPhase9Client("risolviContestazione");
  // La motivazione e obbligatoria a database. Fermarla qui risparmia un giro di
  // rete; il vincolo autoritativo resta quello, come per azionePratica.
  if (input.nota.trim().length === 0) {
    return phase9Throw("risolviContestazione", {
      code: "22023",
      message: "Una motivazione e obbligatoria.",
    });
  }

  const { data, error } = await client.rpc("moderazione_contestazione_risolvi", {
    p_order_id: input.orderId,
    p_esito: input.esito,
    p_nota: input.nota.trim(),
  });
  if (error) return phase9Throw("moderazione_contestazione_risolvi", error);

  // La RPC torna un jsonb stretto e non la riga di orders: quattro campi, per
  // costruzione, cosi nessuna colonna dell'ordine attraversa questa porta.
  const riga = (data ?? {}) as {
    order_id?: string;
    dispute_stato?: DisputeQueueRow["stato"];
    chiusura_at?: string | null;
    gia_chiusa?: boolean;
  };
  return {
    orderId: riga.order_id ?? input.orderId,
    disputeStato: riga.dispute_stato ?? input.esito,
    chiusuraAt: riga.chiusura_at ?? null,
    giaChiusa: riga.gia_chiusa === true,
  };
};

// I motivi ammessi per tipo di bersaglio vengono dal database, non dalla copia
// TypeScript: reportReasons in data/moderation.ts e la stessa lista, ma se le
// due divergessero il vincolo referenziale di reports.motivo rifiuterebbe la
// segnalazione dopo che l'utente ha gia scritto tutto.
export const motiviAmmessi = async (
  client: SupabaseClient | null,
): Promise<Record<string, string[]>> => {
  if (!client) return noPhase9Client("motiviAmmessi");
  const { data, error } = await client
    .from("report_reasons")
    .select("target_tipo, motivo, ordine")
    .order("target_tipo", { ascending: true })
    .order("ordine", { ascending: true });
  if (error) return phase9Throw("report_reasons", error);

  const per: Record<string, string[]> = {};
  for (const riga of (data ?? []) as { target_tipo: string; motivo: string }[]) {
    (per[riga.target_tipo] ??= []).push(riga.motivo);
  }
  return per;
};
