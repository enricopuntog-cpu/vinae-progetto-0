"use client";

// Fase 9a - controller di sola lettura della moderazione.
//
// Stessa forma del controller di Fase 8: se il client Supabase e configurato si
// legge dalle proiezioni reali, altrimenti si resta sui dati del mock, che nel
// frontend-next continuano a guidare i domini non ancora migrati. Non e un
// ripiego silenzioso: `mode` dice quale delle due sorgenti e in uso.
//
// Qui non esiste alcuna azione. Le sette azioni di moderazione sono il
// checkpoint 9b; questo controller non le espone nemmeno come funzioni
// disabilitate, perche un comando che non esiste e piu onesto di un comando
// che non fa nulla.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import {
  codaContestazioni,
  createSupabaseModerationService,
  type DisputeQueueRow,
} from "@/services/phase9/supabase-moderation-service";
import type { AuditEntry, Report } from "@/data/moderation";

export type Phase9ModerationState = {
  mode: "supabase" | "mock";
  coda: Report[];
  audit: AuditEntry[];
  contestazioni: DisputeQueueRow[];
  mieSegnalazioni: Report[];
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
};

const messaggio = (e: unknown) =>
  e instanceof Error ? e.message : "Non e stato possibile caricare la moderazione.";

export const usePhase9Moderation = (opzioni?: { moderatore?: boolean }): Phase9ModerationState => {
  const moderatore = opzioni?.moderatore ?? false;
  const { authUser, reports: reportsMock, auditLog: auditMock } = useVinea();
  const authUserId = authUser?.userId;
  const client = getSupabaseClient();
  const service = useMemo(
    () => (client ? createSupabaseModerationService(client) : null),
    [client],
  );

  const [coda, setCoda] = useState<Report[]>([]);
  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [contestazioni, setContestazioni] = useState<DisputeQueueRow[]>([]);
  const [mieSegnalazioni, setMie] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Stesso accorgimento del controller di Fase 8: una risposta che arriva dopo
  // un cambio di utente non deve scrivere nello stato del nuovo utente.
  const epoch = useRef(0);

  const reload = useCallback(async () => {
    const richiesta = epoch.current;
    if (!service) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      // Le letture di moderazione partono solo se il chiamante e un moderatore:
      // per chiunque altro le proiezioni restituirebbero zero righe, e chiederle
      // sarebbe traffico inutile e un messaggio d'errore fuorviante.
      const [mie, codaRighe, auditRighe, dispute] = await Promise.all([
        service.segnalazioniUtente(authUserId ?? ""),
        moderatore ? service.coda() : Promise.resolve<Report[]>([]),
        moderatore ? service.auditLog() : Promise.resolve<AuditEntry[]>([]),
        moderatore ? codaContestazioni(client) : Promise.resolve<DisputeQueueRow[]>([]),
      ]);
      if (richiesta !== epoch.current) return;
      setMie(mie);
      setCoda(codaRighe);
      setAudit(auditRighe);
      setContestazioni(dispute);
      setError(null);
    } catch (e) {
      if (richiesta !== epoch.current) return;
      setError(messaggio(e));
    } finally {
      if (richiesta === epoch.current) setLoading(false);
    }
  }, [authUserId, client, moderatore, service]);

  useEffect(() => {
    const richiesta = ++epoch.current;
    queueMicrotask(() => {
      if (richiesta !== epoch.current) return;
      setCoda([]);
      setAudit([]);
      setContestazioni([]);
      setMie([]);
      if (client && !authUserId) {
        setLoading(false);
        return;
      }
      void reload();
    });
    return () => {
      if (richiesta === epoch.current) epoch.current += 1;
    };
  }, [authUserId, client, reload]);

  return useMemo(() => {
    if (!service) {
      // Sorgente mock: nessuna chiamata di rete, nessun caricamento.
      return {
        mode: "mock" as const,
        coda: reportsMock,
        audit: auditMock,
        contestazioni: [],
        mieSegnalazioni: reportsMock,
        loading: false,
        error: null,
        reload: async () => {},
      };
    }
    return {
      mode: "supabase" as const,
      coda,
      audit,
      contestazioni,
      mieSegnalazioni,
      loading,
      error,
      reload,
    };
  }, [
    audit,
    auditMock,
    coda,
    contestazioni,
    error,
    loading,
    mieSegnalazioni,
    reload,
    reportsMock,
    service,
  ]);
};
