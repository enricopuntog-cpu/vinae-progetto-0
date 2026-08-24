import type { Metadata } from "next";
import VenditePageClient from "./page-client";

export const metadata: Metadata = {
  title: "Le mie vendite — Vinea",
  description: "Annunci, ordini ricevuti e andamento della tua attività di venditore.",
  robots: { index: false, follow: false },
};

/**
 * Privata come la Cantina e come `/acquisti`: senza sessione non c'è nulla da
 * rendere sul server. Ordini e annunci arrivano dal browser, filtrati da RLS su
 * `seller_id`.
 *
 * Lo stato mostrato per gli ordini è quello **derivato** per il venditore: non
 * esiste una colonna `seller_stato`, e le nove etichette di frontend/ si
 * ricavano dallo stato dell'ordine più `preparazione_avviata_at`.
 */
export default function Page() {
  return <VenditePageClient />;
}
