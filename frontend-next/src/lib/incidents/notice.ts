import type { SupabaseClient } from "@supabase/supabase-js";

export type IncidentNoticeKind = "manutenzione" | "degrado" | "incidente" | "sicurezza";

export type IncidentNotice = {
  kind: IncidentNoticeKind;
  message: string;
  statusUrl: string | null;
  updatedAt: string;
};

const KINDS = new Set<IncidentNoticeKind>([
  "manutenzione",
  "degrado",
  "incidente",
  "sicurezza",
]);

type NoticeRow = {
  kind?: unknown;
  message?: unknown;
  status_url?: unknown;
  updated_at?: unknown;
};

export function parseIncidentNotice(row: NoticeRow | null): IncidentNotice | null {
  if (!row || typeof row.kind !== "string" || !KINDS.has(row.kind as IncidentNoticeKind)) {
    return null;
  }
  if (typeof row.message !== "string") return null;
  const message = row.message.trim();
  if (message.length < 10 || message.length > 500) return null;
  if (typeof row.updated_at !== "string" || Number.isNaN(Date.parse(row.updated_at))) return null;

  let statusUrl: string | null = null;
  if (row.status_url !== null && row.status_url !== undefined) {
    if (typeof row.status_url !== "string") return null;
    try {
      const parsed = new URL(row.status_url);
      if (parsed.protocol !== "https:") return null;
      statusUrl = parsed.toString();
    } catch {
      return null;
    }
  }

  return {
    kind: row.kind as IncidentNoticeKind,
    message,
    statusUrl,
    updatedAt: row.updated_at,
  };
}

export async function readIncidentNotice(
  client: SupabaseClient | null,
): Promise<IncidentNotice | null> {
  if (!client) return null;
  const { data, error } = await client
    .from("public_incident_notice")
    .select("kind,message,status_url,updated_at")
    .maybeSingle();
  if (error) return null;
  return parseIncidentNotice(data as NoticeRow | null);
}
