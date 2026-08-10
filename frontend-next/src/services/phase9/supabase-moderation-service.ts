// Fase 9a - adapter Supabase in sola lettura dietro ModerationService.
//
// Le quattro letture del checkpoint 9a passano tutte da una proiezione, mai da
// una tabella: moderation_report_queue, moderation_report_events,
// moderation_dispute_queue, moderation_audit_log, my_reports, my_report_events.
// Le tabelle reports, report_events e audit_log non hanno alcun grant client,
// quindi una `.from("reports")` qui non fallirebbe per una svista di codice ma
// con un permission denied dal database.
//
// L'unica scrittura di questo checkpoint e `segnala`, che chiama la RPC
// public.segnalazione_invia: identita da auth.uid(), priorita derivata sul
// server, motivo vincolato all'elenco chiuso, rate limit 10/ora.
// `aggiornaStato` ed `eseguiAzione` sono azioni di moderazione e appartengono
// al 9b: esistono perche l'interfaccia le dichiara, e sollevano.

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  noPhase9Client,
  nonAncoraDisponibile,
  phase9Throw,
} from "@/services/phase9/shared";
import type { ModerationService } from "@/services/types";
// types.ts importa questi tipi da @/data/moderation senza riesportarli: la
// fonte e quella, e prenderli da li tiene una definizione sola.
import type {
  AuditEntry,
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
    const { data, error } = await client.rpc("segnalazione_invia", {
      p_target_tipo: input.targetType,
      p_target_id: input.targetId,
      p_target_label: input.targetLabel,
      p_motivo: input.reason,
      p_descrizione: input.descrizione ?? "",
      p_foto: input.foto ?? [],
      p_club_slug: input.clubSlug ?? null,
    });
    if (error) return phase9Throw("segnalazione_invia", error);

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
  aggiornaStato: async () => nonAncoraDisponibile("aggiornaStato"),
  eseguiAzione: async () => nonAncoraDisponibile("eseguiAzione"),
});

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
