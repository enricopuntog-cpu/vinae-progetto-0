/**
 * Le regioni vinicole canoniche, in sola lettura.
 *
 * PERCHÉ ESISTE. La fondazione D2 crea una tassonomia unica in
 * `public.wine_regions` e vincola `wines.regione` a essa. Senza questo modulo
 * i consumatori — il selettore di `/vendi` e il filtro di `/esplora` — si
 * troverebbero davanti alla stessa scelta che ha prodotto il problema:
 * interrogare la tabella direttamente da una pagina, o ricablare l'ennesima
 * lista di stringhe. Il contratto è qui perché quella scelta non debba essere
 * rifatta.
 *
 * NON HA `"use client"`, per la stessa ragione di `public-profile-service`: il
 * client Supabase arriva da fuori (`creaWineRegionsService`), così che la lista
 * possa essere letta dal server nel rendere `/esplora` oppure nel browser dal
 * wizard di `/vendi`. Entrambe le strade sono ora percorse, ed è la ragione per
 * cui il client resta un argomento invece che un import.
 *
 * PERCHÉ UNA TABELLA E NON UNA RPC. La differenza con il profilo pubblico è
 * reale: lì la tabella di base non è leggibile e l'unica porta è una funzione;
 * qui il registro è pubblico per costruzione — tre colonne, nessun dato
 * personale, `SELECT` concesso ad `anon` e `authenticated` e nessun `INSERT`,
 * `UPDATE` o `DELETE` per nessuno dei due. Interporre una RPC non aggiungerebbe
 * una barriera, aggiungerebbe solo un livello.
 *
 * NIENTE LOGICA DI PRODOTTO. Non c'è `Tutte`, non c'è un valore predefinito,
 * non c'è un raggruppamento per macro-area e non c'è una traduzione. `Tutte` in
 * particolare è un pseudo-valore della UI di `/esplora`, non una regione: se
 * comparisse qui finirebbe prima o poi in un `INSERT`, e la chiave esterna lo
 * rifiuterebbe. Chi rende un menù lo antepone da sé.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Result, WineRegionsService } from "./types";

/** Vedi `profile-service.ts`: chi compila un annuncio non installa il progetto. */
const NOT_CONFIGURED_ERROR = "Non è stato possibile leggere l'elenco delle regioni.";

const LETTURA_FALLITA = "Non è stato possibile leggere l'elenco delle regioni.";

/** Il registro canonico. Un nome solo, in un posto solo. */
const TABELLA = "wine_regions";

/**
 * `ordine` prima, `nome` come spareggio.
 *
 * `ordine` non è unico — la migrazione lascia un valore predefinito comune ai
 * nomi aggiunti in futuro — quindi da solo non definirebbe una sequenza: due
 * righe con lo stesso `ordine` potrebbero tornare in un verso oggi e nell'altro
 * domani, e un menù che cambia ordine da solo è un difetto che nessuno riesce a
 * riprodurre. Il secondo criterio rende la lettura deterministica.
 */
const ORDINE: ReadonlyArray<{ colonna: string; ascendente: boolean }> = [
  { colonna: "ordine", ascendente: true },
  { colonna: "nome", ascendente: true },
];

type RigaRegione = { nome: unknown };

export function creaWineRegionsService(client: SupabaseClient | null): WineRegionsService {
  return {
    async elenco(): Promise<Result<string[]>> {
      if (!client) return { ok: false, error: NOT_CONFIGURED_ERROR };

      let query = client.from(TABELLA).select("nome");
      for (const { colonna, ascendente } of ORDINE) {
        query = query.order(colonna, { ascending: ascendente });
      }

      const { data, error } = await query;

      if (error) {
        // Il dettaglio di PostgreSQL resta nei log: al chiamante arriva una
        // frase in italiano, mai il messaggio del database.
        console.error("[WineRegionsService] lettura regioni fallita:", error);
        return { ok: false, error: LETTURA_FALLITA };
      }

      // `typeof === "string"` non è difensivismo: `select("nome")` è tipizzato
      // in modo lasco e una riga malformata renderebbe `undefined` dentro un
      // `string[]`, che il consumatore scoprirebbe solo al rendering.
      const nomi = ((data ?? []) as RigaRegione[])
        .map((riga) => riga.nome)
        .filter((nome): nome is string => typeof nome === "string" && nome.length > 0);

      return { ok: true, data: nomi };
    },
  };
}
