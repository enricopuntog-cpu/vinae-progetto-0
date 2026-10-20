import type { SupabaseClient } from "@supabase/supabase-js";
import type { AccessorioPubblico } from "@/lib/cantina-accessori/cantina-accessori";
import { creaCantinaAccessoriPubblicaService } from "@/services/cantina-accessori-service";

export type AccessoriPubbliciLetti = {
  accessori: AccessorioPubblico[];
  /** URL FIRMATE (a tempo) delle prime foto; mancante = segnaposto. */
  url: Record<string, string>;
};

const NESSUNO: AccessoriPubbliciLetti = { accessori: [], url: {} };

/**
 * Gli accessori ESPOSTI di un profilo, per le pagine rese dal server.
 *
 * Fail closed e indipendente: qualunque guasto (porta assente, migrazione non
 * ancora applicata, firma non riuscita) restituisce «nessun accessorio» e
 * non toglie la Cantina o il profilo. Con gli interruttori spenti il database
 * risponde gia con un elenco vuoto: la pagina non distingue i due casi, cosi
 * non rivela né la funzione né una scelta privata.
 */
export async function leggiAccessoriPubblici(
  client: SupabaseClient | null,
  userId: string,
  opzioni: { limite: number; offset?: number },
): Promise<AccessoriPubbliciLetti> {
  if (!client) return NESSUNO;
  try {
    const servizio = creaCantinaAccessoriPubblicaService(client);
    const esito = await servizio.perProfilo(userId, { limite: opzioni.limite, offset: opzioni.offset });
    if (!esito.ok || esito.data.length === 0) return NESSUNO;
    const prime = esito.data.flatMap((a) => (a.immagini[0] ? [a.immagini[0]] : []));
    const firmate = await servizio.urlFoto(prime);
    return { accessori: esito.data, url: firmate.ok ? firmate.data : {} };
  } catch {
    return NESSUNO;
  }
}
