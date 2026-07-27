import { useCallback, useState } from "react";
import { toast } from "sonner";
import type { Notifica } from "@/data/extra";
import { wines } from "@/data/wines";
import {
  reportsSeed,
  listingStatusSeed,
  auditSeed,
  priorityFromReason,
  MY_REPORTER,
  type Report,
  type ReportStatus,
  type ReportTargetType,
  type ListingStatus,
  type ModAction,
  type AuditEntry,
} from "@/data/moderation";

type NotificationInput = Omit<Notifica, "id" | "letta">;

type ModerationDomainOptions = {
  pushNotifica: (notification: NotificationInput) => void;
};

export function useModerationDomain({ pushNotifica }: ModerationDomainOptions) {
  const [reports, setReports] = useState<Report[]>(reportsSeed);
  const [listingStatus, setListingStatusState] =
    useState<Record<string, ListingStatus>>(listingStatusSeed);
  const [auditLog, setAuditLog] = useState<AuditEntry[]>(auditSeed);
  const [modScope, setModScope] = useState<"piattaforma" | { club: string }>("piattaforma");

  const submitReport = useCallback(
    (input: {
      targetType: ReportTargetType;
      targetId: string;
      targetLabel: string;
      reason: string;
      descrizione: string;
      foto: string[];
      clubSlug?: string;
    }) => {
      const now = new Date().toISOString();
      const r: Report = {
        id: `SEG-2026-${String(300 + Math.floor(Math.random() * 699)).slice(-4)}`,
        targetType: input.targetType,
        targetId: input.targetId,
        targetLabel: input.targetLabel,
        reason: input.reason,
        descrizione: input.descrizione,
        foto: input.foto,
        stato: "inviata",
        priorita: priorityFromReason(input.reason),
        reporter: MY_REPORTER,
        clubSlug: input.clubSlug,
        createdAt: now,
        updatedAt: now,
        storia: [{ ts: now, testo: "Segnalazione ricevuta", autore: "Sistema" }],
        noteInterne: [],
      };
      setReports((prev) => [r, ...prev]);
      pushNotifica({
        categoria: "sistema",
        testo: `Segnalazione ${r.id} inviata. La stiamo esaminando.`,
        tempo: "ora",
      });
      toast.success("Segnalazione inviata (demo)");
    },
    [pushNotifica],
  );

  const updateReportStatus = useCallback(
    (id: string, stato: ReportStatus, nota?: string) => {
      const now = new Date().toISOString();
      setReports((prev) =>
        prev.map((r) =>
          r.id === id
            ? {
                ...r,
                stato,
                updatedAt: now,
                storia: [
                  ...r.storia,
                  { ts: now, testo: nota ?? `Stato aggiornato: ${stato}`, autore: "Moderazione" },
                ],
              }
            : r,
        ),
      );
      pushNotifica({
        categoria: "sistema",
        testo: `Segnalazione ${id}: ${stato.replace("_", " ")}`,
        tempo: "ora",
      });
    },
    [pushNotifica],
  );

  const assignReport = useCallback((id: string, assignee: string) => {
    const now = new Date().toISOString();
    setReports((prev) =>
      prev.map((r) =>
        r.id === id
          ? {
              ...r,
              assignee,
              updatedAt: now,
              storia: [
                ...r.storia,
                { ts: now, testo: `Assegnata a ${assignee}`, autore: "Sistema" },
              ],
            }
          : r,
      ),
    );
  }, []);

  const addReportNote = useCallback((id: string, testo: string) => {
    const now = new Date().toISOString();
    setReports((prev) =>
      prev.map((r) =>
        r.id === id
          ? {
              ...r,
              updatedAt: now,
              noteInterne: [...r.noteInterne, { ts: now, testo, autore: "Moderazione" }],
            }
          : r,
      ),
    );
  }, []);

  const setListingStatus = useCallback((wineId: string, s: ListingStatus) => {
    setListingStatusState((prev) => ({ ...prev, [wineId]: s }));
    toast.success(`Stato annuncio: ${s.replace("_", " ")}`);
  }, []);

  const applyModAction = useCallback(
    (input: {
      action: ModAction;
      target: string;
      motivazione: string;
      durata?: string;
      scope?: "piattaforma" | "club";
      clubSlug?: string;
      reportId?: string;
    }) => {
      const now = new Date().toISOString();
      const entry: AuditEntry = {
        id: `au-${Date.now()}`,
        ts: now,
        attore: input.scope === "club" ? "Mod. Club" : "Mod. Vinea",
        scope: input.scope ?? "piattaforma",
        clubSlug: input.clubSlug,
        azione: input.action,
        target: input.target,
        motivazione: input.motivazione,
        durata: input.durata,
        ricorso: "nessuno",
      };
      setAuditLog((prev) => [entry, ...prev]);
      if (input.reportId) {
        const nextStato: ReportStatus =
          input.action === "info_richieste"
            ? "info_richieste"
            : input.action === "chiusura"
              ? "risolta"
              : input.action === "ripristino"
                ? "respinta"
                : "risolta";
        setReports((prev) =>
          prev.map((r) =>
            r.id === input.reportId
              ? {
                  ...r,
                  stato: nextStato,
                  updatedAt: now,
                  storia: [
                    ...r.storia,
                    {
                      ts: now,
                      autore: entry.attore,
                      testo: `${input.action.replace("_", " ")}${input.durata ? ` (${input.durata})` : ""} — ${input.motivazione}`,
                    },
                  ],
                }
              : r,
          ),
        );
      }
      toast.success("Azione registrata (demo)");
    },
    [],
  );

  const richiediAltreFoto = useCallback(
    (wineId: string, sellerName: string) => {
      const wine = wines.find((w) => w.id === wineId);
      const label = wine ? `${wine.nome} ${wine.annata}` : wineId;
      pushNotifica({
        categoria: "marketplace",
        testo: `Hai chiesto altre foto a ${sellerName} per ${label}`,
        tempo: "ora",
      });
      toast.success(`Richiesta inviata a ${sellerName} in chat`);
    },
    [pushNotifica],
  );

  return {
    reports,
    listingStatus,
    auditLog,
    modScope,
    setModScope,
    submitReport,
    updateReportStatus,
    assignReport,
    addReportNote,
    setListingStatus,
    applyModAction,
    richiediAltreFoto,
  };
}
