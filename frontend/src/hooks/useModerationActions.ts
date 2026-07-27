import { useCallback, useMemo, useState } from "react";
import type { AuditEntry, ModAction, Priorita, Report, ReportStatus } from "@/data/moderation";

type ModScope = "piattaforma" | { club: string };

type ReportQueueOptions = {
  reports: Report[];
  modScope: ModScope;
};

export function useReportQueue({ reports, modScope }: ReportQueueOptions) {
  const [priorita, setPriorita] = useState<"tutte" | Priorita>("tutte");
  const [stato, setStato] = useState<"tutti" | ReportStatus>("tutti");
  const clubSlug = typeof modScope === "object" ? modScope.club : undefined;
  const isClub = clubSlug !== undefined;

  const filtrate = useMemo(() => {
    let list = reports;
    if (isClub) list = list.filter((r) => r.clubSlug === clubSlug);
    if (priorita !== "tutte") list = list.filter((r) => r.priorita === priorita);
    if (stato !== "tutti") list = list.filter((r) => r.stato === stato);
    return list;
  }, [reports, isClub, clubSlug, priorita, stato]);

  return { priorita, setPriorita, stato, setStato, filtrate };
}

type ApplyModActionInput = {
  action: ModAction;
  target: string;
  motivazione: string;
  durata?: string;
  scope?: "piattaforma" | "club";
  clubSlug?: string;
  reportId?: string;
};

type ModActionOptions = {
  modScope: ModScope;
  applyModAction: (input: ApplyModActionInput) => void;
};

export function useModAction({ modScope, applyModAction }: ModActionOptions) {
  const [motivazione, setMotivazione] = useState("");
  const [durata, setDurata] = useState("7 giorni");

  const actionsFor = useCallback((report: Report): ModAction[] => {
    const closed = report.stato === "risolta" || report.stato === "respinta";
    return closed
      ? ["ripristino"]
      : [
          "richiesta_modifiche",
          "info_richieste",
          "ammonizione",
          "sospensione",
          "rimozione",
          "chiusura",
        ];
  }, []);

  const eseguiAzione = useCallback(
    (report: Report, action: ModAction, onDone: () => void) => {
      if (!motivazione.trim()) return;
      const isClub = typeof modScope === "object";
      applyModAction({
        action,
        target: report.targetLabel,
        motivazione,
        durata: action === "sospensione" ? durata : undefined,
        scope: isClub ? "club" : "piattaforma",
        clubSlug: isClub ? modScope.club : report.clubSlug,
        reportId: report.id,
      });
      setMotivazione("");
      onDone();
    },
    [motivazione, durata, modScope, applyModAction],
  );

  return { motivazione, setMotivazione, durata, setDurata, actionsFor, eseguiAzione };
}

type ScopedAuditLogOptions = {
  auditLog: AuditEntry[];
  modScope: ModScope;
};

export function useScopedAuditLog({ auditLog, modScope }: ScopedAuditLogOptions) {
  const isClub = typeof modScope === "object";
  const clubSlug = isClub ? modScope.club : undefined;

  return useMemo(
    () =>
      isClub ? auditLog.filter((e) => e.scope === "club" && e.clubSlug === clubSlug) : auditLog,
    [auditLog, isClub, clubSlug],
  );
}
