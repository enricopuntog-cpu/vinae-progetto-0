/**
 * Scorte commerciali del Partner (VP-C).
 *
 * L'inventario commerciale vive nelle stesse righe di `bottle_units` della
 * Cantina — un motore solo — ma con `inventario = 'commerciale'` e il Partner
 * accanto. Questo servizio legge SOLO quelle righe: le bottiglie personali del
 * titolare non compaiono, non si convertono e non si contano qui. Nessun
 * costo, valore o degustazione: è un catalogo, non una collezione.
 *
 * La scrittura passa da `scorte_partner_aggiungi`, che solo un Partner attivo
 * con account attivo può chiamare; il gruppo è vino + formato, come nella
 * Cantina, e ogni quantità è un conteggio di righe.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { FORMATO_STANDARD, chiaveGruppo } from "@/lib/cantina/gruppo";
import type { EsitoLotto, Result } from "@/services/types";

export type GruppoScorte = {
  chiave: string;
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  tipo: string;
  formato: string;
  quantita: number;
};

export type DatiNuoveScorte = {
  produttore: string;
  nome: string;
  annata: number;
  regione: string;
  tipo: string;
  formato: string;
  quantita: number;
  idempotencyKey: string;
};

type RigaScorta = {
  id: string;
  formato: string | null;
  wines:
    | { slug: string; produttore: string; nome: string; annata: number; regione: string; tipo: string }
    | { slug: string; produttore: string; nome: string; annata: number; regione: string; tipo: string }[]
    | null;
};

const ERRORE_LETTURA = "Le scorte non sono consultabili in questo momento.";
const ERRORE_SCRITTURA = "Non è stato possibile aggiungere le scorte. Riprova.";
/** Messaggi delle porte che si possono mostrare così come sono. */
const CODICI_LEGGIBILI = new Set(["P0001"]);

/** Raggruppa per vino e formato; puro, per poterlo provare senza rete. */
export function raggruppaScorte(righe: readonly RigaScorta[]): GruppoScorte[] {
  const gruppi = new Map<string, GruppoScorte>();
  for (const riga of righe) {
    const vino = Array.isArray(riga.wines) ? riga.wines[0] : riga.wines;
    if (!vino) continue;
    const formato = riga.formato ?? FORMATO_STANDARD;
    const chiave = chiaveGruppo(vino.slug, formato);
    const gruppo = gruppi.get(chiave);
    if (gruppo) {
      gruppo.quantita += 1;
    } else {
      gruppi.set(chiave, {
        chiave,
        produttore: vino.produttore,
        nome: vino.nome,
        annata: vino.annata,
        regione: vino.regione,
        tipo: vino.tipo,
        formato,
        quantita: 1,
      });
    }
  }
  return [...gruppi.values()].sort(
    (a, b) =>
      a.produttore.localeCompare(b.produttore) ||
      a.nome.localeCompare(b.nome) ||
      b.annata - a.annata ||
      a.formato.localeCompare(b.formato),
  );
}

export function creaScortePartnerService(client: SupabaseClient | null) {
  return {
    async elenco(): Promise<Result<GruppoScorte[]>> {
      if (!client) return { ok: false, error: ERRORE_LETTURA };
      const { data, error } = await client
        .from("bottle_units")
        .select("id, formato, wines!inner ( slug, produttore, nome, annata, regione, tipo )")
        .eq("inventario", "commerciale")
        .is("deleted_at", null)
        .is("ceduta_at", null)
        .order("created_at");
      if (error) {
        console.error("[ScortePartner] elenco fallito:", error);
        return { ok: false, error: ERRORE_LETTURA };
      }
      return { ok: true, data: raggruppaScorte((data as unknown as RigaScorta[] | null) ?? []) };
    },

    async aggiungi(dati: DatiNuoveScorte): Promise<Result<EsitoLotto>> {
      if (!client) return { ok: false, error: ERRORE_SCRITTURA };
      const { data, error } = await client.rpc("scorte_partner_aggiungi", {
        p_produttore: dati.produttore,
        p_nome: dati.nome,
        p_annata: dati.annata,
        p_regione: dati.regione,
        p_tipo: dati.tipo,
        p_formato: dati.formato,
        p_quantita: dati.quantita,
        p_idempotency_key: dati.idempotencyKey,
      });
      if (error) {
        console.error("[ScortePartner] aggiunta fallita:", error);
        return {
          ok: false,
          error: error.code && CODICI_LEGGIBILI.has(error.code) && error.message ? error.message : ERRORE_SCRITTURA,
        };
      }
      const esito = data as Partial<EsitoLotto> | null;
      if (
        !esito ||
        typeof esito.lottoId !== "string" ||
        typeof esito.quantita !== "number" ||
        !Array.isArray(esito.bottleUnitIds)
      ) {
        console.error("[ScortePartner] risposta malformata");
        return { ok: false, error: ERRORE_SCRITTURA };
      }
      return {
        ok: true,
        data: {
          lottoId: esito.lottoId,
          wineId: String(esito.wineId ?? ""),
          formato: String(esito.formato ?? dati.formato),
          quantita: esito.quantita,
          bottleUnitIds: esito.bottleUnitIds.map(String),
          replay: esito.replay === true,
        },
      };
    },
  };
}
