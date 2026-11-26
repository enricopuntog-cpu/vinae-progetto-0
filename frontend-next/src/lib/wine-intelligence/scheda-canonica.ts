// WI-008 — lettura della scheda autonoma di un vino del catalogo canonico.
//
// Passa dalla sola porta della ricerca (`vini_canonici_cerca`, per codice): valgono le sue regole — sessione,
// interruttore della proiezione, fonte autorizzata, vino promosso e attivo, Combined risolto, limite per utente.
// Nessuna seconda regola di visibilità e nessuna lettura di `catalog.*`.

import type { SupabaseClient } from "@supabase/supabase-js";
import { codiceErrore } from "@/lib/errore-per-log";
import { eCodiceScheda, LWIN7, UUID_SCHEDA } from "./codice-scheda";

export type SchedaCanonica = {
  /** Codice con cui la scheda si richiama: LWIN-7 se esiste, altrimenti l'UUID del vino canonico. */
  codice: string;
  vinoId: string | null;
  /** `null` per un'identità nativa Vinea (WI-011): il codice non viene inventato. */
  lwin7: string | null;
  produttore: string;
  nome: string;
  paese: string | null;
  territorio: string | null;
  territorioTipo: string | null;
  denominazione: string | null;
  tipo: string | null;
  colore: string | null;
  fonteNome: string | null;
  licenza: string | null;
  attribuzione: string | null;
};

export type EsitoScheda =
  | { stato: "trovata"; scheda: SchedaCanonica }
  /** Non esiste, non è pubblica o il catalogo è spento: la pagina non distingue. */
  | { stato: "assente" }
  | { stato: "accesso" }
  | { stato: "non_disponibile" };

const testo = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);

export async function leggiSchedaCanonica(client: SupabaseClient | null, codice: string): Promise<EsitoScheda> {
  if (!eCodiceScheda(codice)) return { stato: "assente" };
  if (!client) return { stato: "non_disponibile" };
  try {
    const { data: sessione } = await client.auth.getUser();
    if (!sessione.user) return { stato: "accesso" };
    const { data, error } = await client.rpc("vini_canonici_cerca", {
      p_produttore: "",
      p_nome: "",
      p_limite: 1,
      p_codice: codice,
    });
    if (error || !Array.isArray(data)) return { stato: "non_disponibile" };
    const r = data[0] as Record<string, unknown> | undefined;
    const lwin7 = testo(r?.lwin7);
    const produttore = testo(r?.produttore);
    const nome = testo(r?.nome);
    const vinoId = testo(r?.vino_id);
    const codiceScheda = lwin7 ?? (vinoId && UUID_SCHEDA.test(vinoId) ? vinoId : null);
    if (!r || r.livello !== "identificativo" || (lwin7 && !LWIN7.test(lwin7)) || !codiceScheda || !produttore || !nome) {
      return { stato: "assente" };
    }
    return {
      stato: "trovata",
      scheda: {
        codice: codiceScheda,
        vinoId,
        lwin7,
        produttore,
        nome,
        paese: testo(r.paese),
        territorio: testo(r.territorio),
        territorioTipo: testo(r.territorio_tipo),
        denominazione: testo(r.denominazione),
        tipo: testo(r.tipo),
        colore: testo(r.colore),
        fonteNome: testo(r.fonte_nome),
        licenza: testo(r.fonte_licenza),
        attribuzione: testo(r.attribuzione),
      },
    };
  } catch (errore) {
    console.error("[scheda-catalogo] lettura non riuscita:", codiceErrore(errore));
    return { stato: "non_disponibile" };
  }
}
