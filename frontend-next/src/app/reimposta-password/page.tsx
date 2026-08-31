import type { Metadata } from "next";
import { eCodiceErroreAuth } from "@/lib/auth/errori-auth";
import ReimpostaPasswordPageClient from "./page-client";

export const metadata: Metadata = {
  title: "Reimposta la password — Vinea Wine Club",
  description: "Imposta una nuova password per il tuo account Vinea.",
  // Pagina raggiungibile solo con una sessione di recupero aperta da un link
  // personale: non ha nulla da offrire a un motore di ricerca, e comparire fra
  // i risultati significherebbe mandarci utenti che vedranno solo un errore.
  robots: { index: false, follow: false },
};

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ errore?: string }>;
}) {
  const { errore } = await searchParams;
  /**
   * Quando lo scambio del code non riesce, `/auth/callback` manda qui il motivo
   * invece di lasciare il recupero su una pagina di accesso. Il valore è letto
   * dal server e validato contro il vocabolario chiuso prima di arrivare al
   * client: ciò che non è un codice nostro non diventa `generico` per cortesia,
   * diventa `null` — l'assenza di sessione ha già il suo messaggio, ed è più
   * preciso di un «riprova» senza oggetto.
   */
  const erroreRientro = eCodiceErroreAuth(errore) ? errore : null;

  // Nessun Suspense: il parametro lo legge il server e scende come prop, quindi
  // il client non chiama `useSearchParams` e non serve alcun boundary.
  return <ReimpostaPasswordPageClient erroreRientro={erroreRientro} />;
}
