"use client";

import { useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { routes } from "@/config/routes";

/**
 * Il ritorno indietro da una pagina che si raggiunge da posti diversi.
 *
 * Il Centro legale è linkato dal footer, dal gate dell'età e dalla
 * registrazione: non esiste «la» pagina precedente da mettere in un `<Link>`,
 * ed è per questo che qui la destinazione la decide la cronologia e non il
 * markup.
 *
 * ## Perché non `router.back()` e basta
 *
 * `back()` su una scheda aperta direttamente sul link — un messaggio, un
 * segnalibro, il primo ingresso di una sessione — non ha nessun posto dove
 * andare: il gesto non fa niente e il pulsante sembra rotto. `history.length`
 * distingue i due casi, e quando la cronologia non c'è si va su una rotta
 * interna nota invece di lasciare la persona ferma.
 *
 * La decisione è presa al click e non al render di proposito: `window` non
 * esiste durante il render sul server, e leggerlo per disegnare due pulsanti
 * diversi produrrebbe un'idratazione incoerente. Il pulsante è sempre lo
 * stesso; cambia solo dove porta.
 *
 * `fallback` resta un percorso interno costruito da `routes`: non arriva mai da
 * una query string, da `document.referrer` o da un altro dato non validato, e
 * quindi non può diventare un rimando fuori dominio.
 */
export const AzioneIndietro = ({
  fallback = routes.home,
  etichetta = "Indietro",
  className,
}: {
  fallback?: string;
  etichetta?: string;
  className?: string;
}) => {
  const router = useRouter();

  return (
    <button
      type="button"
      onClick={() => {
        // `length > 1` vuol dire che questa pagina non è la prima della scheda,
        // quindi esiste una voce precedente su cui tornare.
        if (typeof window !== "undefined" && window.history.length > 1) {
          router.back();
          return;
        }
        router.push(fallback);
      }}
      data-testid="azione-indietro"
      className={`inline-flex items-center gap-1 rounded-full px-2 py-1 text-sm text-muted-foreground transition hover:text-bordeaux focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${className ?? ""}`}
    >
      <ArrowLeft className="h-4 w-4" aria-hidden focusable="false" />
      {etichetta}
    </button>
  );
};
