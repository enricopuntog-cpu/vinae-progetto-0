import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { PARAMETRO_NEXT } from "@/lib/auth/ritorno-auth";
import VenditePageClient from "./page-client";

export const metadata: Metadata = {
  title: "Le mie vendite — Vinea",
  description: "Annunci, ordini ricevuti e andamento della tua attività di venditore.",
  robots: { index: false, follow: false },
};

/**
 * Dove va chi arriva su `/vendite` senza sessione.
 *
 * Con `?next=/vendite`, da D5. Prima il parametro non c'era, e per una ragione
 * buona: `/accedi` non lo leggeva, e un redirect che sembra funzionare e non
 * funziona è peggio di uno onesto. Ora lo leggono `/accedi`, `/registrati` e
 * `/auth/callback` — è lo stesso valore, validato dalla stessa
 * `percorsoRelativoSicuro` in tutti e tre — quindi chi viene rimandato da qui
 * torna qui: con la password, con il magic link o con Google.
 *
 * È scritto per esteso e non ricavato dall'URL della richiesta: la
 * destinazione è nota staticamente, e dedurla da un dato in arrivo aprirebbe
 * una porta che non serve a nessuno.
 */
const PERCORSO_ACCESSO = `/accedi?${PARAMETRO_NEXT}=%2Fvendite`;

/**
 * Privata come la Cantina e come `/acquisti`: senza sessione non c'è nulla da
 * rendere sul server. Ordini e annunci arrivano dal browser, filtrati da RLS su
 * `seller_id`.
 *
 * Lo stato mostrato per gli ordini è quello **derivato** per il venditore: non
 * esiste una colonna `seller_stato`, e le nove etichette di frontend/ si
 * ricavano dallo stato dell'ordine più `preparazione_avviata_at`.
 *
 * ## La guardia
 *
 * Prima di questa correzione un anonimo raggiungeva la route e leggeva il testo
 * d'errore di `vendite()` — non i KPI a zero: una pagina privata che si presenta
 * come rotta invece che come chiusa. Ora la sessione si verifica **sul server**,
 * prima di rendere alcunché.
 *
 * La guardia sta qui e non in un `middleware.ts`: nel repository quel file non
 * esiste, e introdurlo per una sola route metterebbe un intercettore su ogni
 * richiesta del sito per risolvere un problema che riguarda un percorso solo.
 * Non è comunque un confine di fiducia — la RLS su `seller_id` resta l'unica
 * cosa che decide quali righe esistono. È il comportamento giusto per chi non ha
 * fatto il login, non la ragione per cui i dati di un altro venditore non si
 * vedono.
 */
export default async function Page() {
  // Il prerender si ferma qui. Serve al ramo in cui Supabase non è configurato
  // (`getSupabaseServerClient()` torna null **senza** leggere i cookie): in CI
  // `bun run build` gira senza variabili d'ambiente, e un `redirect()` valutato
  // durante la generazione statica verrebbe cotto nella pagina, rimandando ad
  // `/accedi` anche chi in produzione la sessione ce l'ha.
  //
  // `connection()` e non `export const dynamic = "force-dynamic"`: dalla 15 è la
  // forma preferita, perché lega il rendering dinamico alla richiesta in
  // arrivo invece che dichiararlo per l'intero segmento.
  await connection();

  const client = await getSupabaseServerClient();

  // `getUser()` e non `getSession()`: la sessione arriva dai cookie, che sono un
  // dato della richiesta; `getUser()` la fa verificare al server di Supabase.
  // Con Supabase non configurato non esiste alcuna sessione verificabile, quindi
  // il ramo `client === null` cade nello stesso redirect: chiuso, non aperto.
  const utente = client ? (await client.auth.getUser()).data.user : null;
  if (!utente) redirect(PERCORSO_ACCESSO);

  return <VenditePageClient />;
}
