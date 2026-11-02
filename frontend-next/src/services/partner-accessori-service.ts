import type { SupabaseClient } from "@supabase/supabase-js";
import { parseElenco } from "@/lib/accessori/accessori";
import {
  messaggioErroreCantinaAccessori,
  parseAccessorioPersonale,
  type AccessorioPersonale,
  type ErroreRpcCantinaAccessori,
} from "@/lib/cantina-accessori/cantina-accessori";
import {
  parseMovimentoScorta,
  parseStatoPartnerAccessori,
  parseVenditoreAnnuncio,
  type MovimentoScorta,
  type StatoPartnerAccessori,
  type VenditoreAnnuncio,
} from "@/lib/partner-accessori/partner-accessori";
import { creaCantinaAccessoriService } from "./cantina-accessori-service";
import type { CantinaAccessoriService, Result } from "./types";

/**
 * Scorte commerciali di Accessori NUOVI del Vinea Partner (VPM-015C).
 *
 * Non è un secondo servizio di Cantina: è lo stesso `CantinaAccessoriService`
 * (foto, categorie, catalogo, rimozione) con tre metodi che passano dalle porte
 * Partner del database: elenco, salvataggio e archiviazione. Il Partner, la
 * natura commerciale, la condizione "nuovo" e ogni autorizzazione li decide il
 * database da `auth.uid()`; il client non invia mai un Partner, una classe, un
 * margine o un prezzo finale.
 *
 * NON HA `"use client"`: come gli altri adattatori, riceve il client.
 */

const NON_CONFIGURATO = "Le scorte Partner non sono disponibili in questo momento.";
const RICADUTA = "Operazione non riuscita. Riprova fra qualche istante.";

const senzaClient = <T>(): Result<T> => ({ ok: false, error: NON_CONFIGURATO });
const fallita = <T>(operazione: string, errore: ErroreRpcCantinaAccessori): Result<T> => {
  console.error(`[partner-accessori] ${operazione} fallita`, { code: errore?.code, hint: errore?.hint });
  return { ok: false, error: messaggioErroreCantinaAccessori(errore, RICADUTA) };
};

export type PartnerAccessoriService = CantinaAccessoriService & {
  statoPartner(): Promise<Result<StatoPartnerAccessori>>;
  movimenti(id: string): Promise<Result<MovimentoScorta[]>>;
};

export function creaPartnerAccessoriService(client: SupabaseClient | null): PartnerAccessoriService {
  const base = creaCantinaAccessoriService(client);

  const statoPartner = async (): Promise<Result<StatoPartnerAccessori>> => {
    if (!client) return senzaClient();
    const { data, error } = await client.rpc("accessori_partner_stato");
    if (error) return fallita("accessori_partner_stato", error);
    const stato = parseStatoPartnerAccessori(data);
    return stato ? { ok: true, data: stato } : fallita("accessori_partner_stato", null);
  };

  const scorta = async (rpc: string, args: Record<string, unknown>): Promise<Result<AccessorioPersonale>> => {
    if (!client) return senzaClient();
    const { data, error } = await client.rpc(rpc, args);
    if (error) return fallita(rpc, error);
    const letto = parseAccessorioPersonale(data);
    return letto ? { ok: true, data: letto } : fallita(rpc, null);
  };

  return {
    ...base,
    statoPartner,

    // La sezione è usabile da un Partner attivo o sospeso (il sospeso consulta, non
    // lo rifiuta la porta Partner) e solo con la funzione Cantina accesa.
    async stato() {
      const [partner, cantina] = await Promise.all([statoPartner(), base.stato()]);
      if (!partner.ok) return partner;
      if (!cantina.ok) return cantina;
      const ammesso = partner.data.partnerStato === "attivo" || partner.data.partnerStato === "sospeso";
      return { ok: true, data: { ...cantina.data, abilitata: cantina.data.abilitata && ammesso } };
    },

    async elenco(archiviati) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_partner_scorte_elenca", { p_archiviati: archiviati });
      if (error) return fallita("accessori_partner_scorte_elenca", error);
      const elenco = parseElenco(data, parseAccessorioPersonale);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_partner_scorte_elenca", null);
    },

    salva: (id, dati) =>
      scorta("accessori_partner_scorta_salva", {
        p_id: id,
        p_dati: {
          categoria_id: dati.categoriaId,
          nome: dati.nome,
          descrizione: dati.descrizione,
          marchio: dati.marchio,
          quantita: dati.quantita,
          note: dati.note,
          // `undefined` non viene serializzato: il legame resta com'è.
          catalogo_slug: dati.catalogoSlug,
        },
      }),

    archivia: (id, archivia) => scorta("accessori_partner_scorta_archivia", { p_id: id, p_archivia: archivia }),

    async movimenti(id) {
      if (!client) return senzaClient();
      const { data, error } = await client.rpc("accessori_partner_movimenti_elenca", { p_id: id });
      if (error) return fallita("accessori_partner_movimenti_elenca", error);
      const elenco = parseElenco(data, parseMovimentoScorta);
      return elenco ? { ok: true, data: elenco } : fallita("accessori_partner_movimenti_elenca", null);
    },
  };
}

/** Chi vende l'annuncio pubblicato: `null` se non è visibile (o il dato non è leggibile). */
export async function leggiVenditoreAnnuncio(
  client: SupabaseClient | null,
  annuncioId: string,
): Promise<Result<VenditoreAnnuncio | null>> {
  if (!client) return senzaClient();
  const { data, error } = await client.rpc("accessori_venditore_pubblico", { p_annuncio: annuncioId });
  if (error) return fallita("accessori_venditore_pubblico", error);
  if (data === null || data === undefined) return { ok: true, data: null };
  const letto = parseVenditoreAnnuncio(data);
  return letto ? { ok: true, data: letto } : fallita("accessori_venditore_pubblico", null);
}
