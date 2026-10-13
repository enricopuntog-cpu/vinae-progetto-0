import type { SupabaseClient } from "@supabase/supabase-js";
import {
  messaggioErrorePartner,
  normalizzaPartitaIva,
  parseInvito,
  parsePartner,
  parsePartnerAdmin,
  type ErroreRpc,
} from "@/lib/partner/partner";
import type {
  Partner,
  PartnerAdminService,
  PartnerService,
  PartnerStato,
  Result,
} from "./types";

/**
 * Adattatore Supabase del programma Partner (Blocco A).
 *
 * Ogni operazione è una RPC `partner_*`: le tabelle stanno in `private` e il
 * browser non ha alcun grant su di esse. Nessun metodo passa un proprietario o
 * un ruolo — identità e permessi li risolve il database da `auth.uid()` e da
 * `public.user_roles`. I metodi admin esistono qui per l'interfaccia di
 * amministrazione, ma chiamati da chi non è admin ricevono 42501 dal server.
 */

const NON_CONFIGURATO = "Il programma Partner non è disponibile in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });

const fallita = <T>(operazione: string, errore: ErroreRpc): Result<T> => {
  console.error(`[partner] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErrorePartner(errore, RICADUTA) };
};

const STATI: readonly string[] = ["invitato", "in_verifica", "attivo", "sospeso", "revocato"];

const statoDa = (data: unknown): PartnerStato | null =>
  typeof data === "string" && STATI.includes(data) ? (data as PartnerStato) : null;

export function creaPartnerService(client: SupabaseClient | null): PartnerService {
  return {
    async mio() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_me");
      if (error) return fallita("partner_me", error);
      if (data === null || data === undefined) return { ok: true, data: null };
      const partner = parsePartner(data);
      return partner ? { ok: true, data: partner } : fallita("partner_me", null);
    },

    async accettaInvito(token) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_invito_accetta", { p_token: token });
      if (error) return fallita("partner_invito_accetta", error);
      return typeof data === "string" ? { ok: true, data } : fallita("partner_invito_accetta", null);
    },

    async aggiornaDati(dati) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_dati_aggiorna", {
        p_ragione_sociale: dati.ragioneSociale.trim() || null,
        p_nome_commerciale: dati.nomeCommerciale.trim() || null,
        p_partita_iva: normalizzaPartitaIva(dati.partitaIva) || null,
        p_email_commerciale: dati.emailCommerciale.trim() || null,
        p_tipologia: dati.tipologia,
        p_sede_indirizzo: dati.sedeIndirizzo.trim() || null,
        p_sede_cap: dati.sedeCap.trim() || null,
        p_sede_citta: dati.sedeCitta.trim() || null,
        p_sede_provincia: dati.sedeProvincia.trim().toUpperCase() || null,
      });
      if (error) return fallita("partner_dati_aggiorna", error);
      const partner: Partner | null = parsePartner(data);
      return partner ? { ok: true, data: partner } : fallita("partner_dati_aggiorna", null);
    },

    async inviaVerifica() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_invia_verifica");
      if (error) return fallita("partner_invia_verifica", error);
      const stato = statoDa(data);
      return stato ? { ok: true, data: stato } : fallita("partner_invia_verifica", null);
    },
  };
}

export function creaPartnerAdminService(client: SupabaseClient | null): PartnerAdminService {
  return {
    async creaInvito({ email, validitaGiorni, nota }) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_invito_crea", {
        p_email: email,
        p_validita_giorni: validitaGiorni,
        p_nota: nota,
      });
      if (error) return fallita("partner_admin_invito_crea", error);
      const r = (data ?? {}) as Record<string, unknown>;
      if (
        typeof r.invito_id !== "string" ||
        typeof r.token !== "string" ||
        typeof r.scade_at !== "string" ||
        typeof r.email !== "string"
      ) {
        return fallita("partner_admin_invito_crea", null);
      }
      return {
        ok: true,
        data: { invitoId: r.invito_id, token: r.token, scadeAt: r.scade_at, email: r.email },
      };
    },

    async revocaInvito(invitoId, motivo) {
      if (!client) return senzaClient();
      const { error } = await client.rpc("partner_admin_invito_revoca", {
        p_invito_id: invitoId,
        p_motivo: motivo,
      });
      if (error) return fallita("partner_admin_invito_revoca", error);
      return { ok: true, data: undefined };
    },

    async inviti() {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_inviti", { p_limite: 200 });
      if (error) return fallita("partner_admin_inviti", error);
      const righe = Array.isArray(data) ? data : [];
      return { ok: true, data: righe.flatMap((r) => parseInvito(r) ?? []) };
    },

    async partner(stato) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_elenco", {
        p_stato: stato,
        p_limite: 200,
      });
      if (error) return fallita("partner_admin_elenco", error);
      const righe = Array.isArray(data) ? data : [];
      return { ok: true, data: righe.flatMap((r) => parsePartnerAdmin(r) ?? []) };
    },

    async decidi(partnerId, azione, motivo) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_decidi", {
        p_partner_id: partnerId,
        p_azione: azione,
        p_motivo: motivo,
      });
      if (error) return fallita("partner_admin_decidi", error);
      const nuovo = statoDa(data);
      return nuovo ? { ok: true, data: nuovo } : fallita("partner_admin_decidi", null);
    },

    async riabilitaVendite(partnerId, motivo) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_vendite_riabilita", {
        p_partner_id: partnerId,
        p_motivo: motivo,
      });
      if (error) return fallita("partner_admin_vendite_riabilita", error);
      const r = (data ?? {}) as Record<string, unknown>;
      return r.venditeBloccate === false
        ? { ok: true, data: undefined }
        : fallita("partner_admin_vendite_riabilita", null);
    },

    async sospendiAnnunci(partnerId, motivo) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_annunci_sospendi", {
        p_partner_id: partnerId,
        p_motivo: motivo,
      });
      if (error) return fallita("partner_admin_annunci_sospendi", error);
      return typeof data === "number" && Number.isSafeInteger(data) && data >= 0
        ? { ok: true, data }
        : fallita("partner_admin_annunci_sospendi", null);
    },

    async spegniVenditaPartner(motivo) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("partner_admin_vendita_partner_spegni", {
        p_motivo: motivo,
      });
      if (error) return fallita("partner_admin_vendita_partner_spegni", error);
      return data === false
        ? { ok: true, data: undefined }
        : fallita("partner_admin_vendita_partner_spegni", null);
    },
  };
}
