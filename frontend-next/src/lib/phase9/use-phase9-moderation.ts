"use client";

// Fase 9a/9b - controller della moderazione.
//
// Stessa forma del controller di Fase 8: se il client Supabase e configurato si
// legge dalle proiezioni reali. Senza configurazione la beta pubblica fallisce
// chiusa e dichiara il servizio non disponibile, senza fallback mock.
//
// Dal 9b il controller espone anche le azioni. Senza servizio le azioni sono
// assenti: un comando che scrive soltanto in memoria e sparisce al
// ricaricamento sarebbe piu fuorviante della sua indisponibilita.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseClient } from "@/lib/supabase/client";
import { useVinea } from "@/lib/vinea-store";
import {
  azioneAnnuncio,
  azionePratica,
  codaContestazioni,
  createSupabaseModerationService,
  type AzionePraticaInput,
  type DisputeQueueRow,
  type TransizioneAnnuncio,
} from "@/services/phase9/supabase-moderation-service";
import type { AuditEntry, Report } from "@/data/moderation";

export type Phase9ModerationState = {
  mode: "supabase" | "unavailable";
  coda: Report[];
  audit: AuditEntry[];
  contestazioni: DisputeQueueRow[];
  mieSegnalazioni: Report[];
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
  // Null quando il servizio non e disponibile: le azioni non esistono.
  agisci: ((input: AzionePraticaInput) => Promise<void>) | null;
  transizioneAnnuncio:
    | ((listingId: string, transizione: TransizioneAnnuncio, motivazione: string) => Promise<void>)
    | null;
  inCorso: string | null;
};

const messaggio = (e: unknown) =>
  e instanceof Error ? e.message : "Non e stato possibile caricare la moderazione.";

export const usePhase9Moderation = (opzioni?: { moderatore?: boolean }): Phase9ModerationState => {
  const moderatore = opzioni?.moderatore ?? false;
  const { authUser } = useVinea();
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
  // L'azione in corso, per bloccare il doppio invio. Non e un booleano: la coda
  // ha piu righe e un flag globale spegnerebbe tutti i comandi insieme.
  const [inCorso, setInCorso] = useState<string | null>(null);
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

  // Dopo un'azione si rilegge tutto invece di aggiornare lo stato in memoria:
  // una sola azione tocca la pratica, la sua storia, il registro di audit e
  // spesso lo stato del bersaglio. Ricostruire quel risultato dal client
  // significherebbe riscrivere la logica delle RPC, e sbagliarla.
  const agisci = useCallback(
    async (input: AzionePraticaInput) => {
      if (!service) return;
      setInCorso(`${input.reportId}:${input.azione}`);
      try {
        await azionePratica(client, input);
        setError(null);
        await reload();
      } catch (e) {
        setError(messaggio(e));
        throw e;
      } finally {
        setInCorso(null);
      }
    },
    [client, reload, service],
  );

  const transizioneAnnuncio = useCallback(
    async (listingId: string, transizione: TransizioneAnnuncio, motivazione: string) => {
      if (!service) return;
      setInCorso(`${listingId}:${transizione}`);
      try {
        await azioneAnnuncio(client, listingId, transizione, motivazione);
        setError(null);
        await reload();
      } catch (e) {
        setError(messaggio(e));
        throw e;
      } finally {
        setInCorso(null);
      }
    },
    [client, reload, service],
  );

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
      return {
        mode: "unavailable" as const,
        coda: [],
        audit: [],
        contestazioni: [],
        mieSegnalazioni: [],
        loading: false,
        error: "Il servizio non e disponibile in questa configurazione.",
        reload: async () => {},
        agisci: null,
        transizioneAnnuncio: null,
        inCorso: null,
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
      agisci,
      transizioneAnnuncio,
      inCorso,
    };
  }, [
    agisci,
    audit,
    coda,
    contestazioni,
    error,
    inCorso,
    loading,
    mieSegnalazioni,
    reload,
    service,
    transizioneAnnuncio,
  ]);
};
