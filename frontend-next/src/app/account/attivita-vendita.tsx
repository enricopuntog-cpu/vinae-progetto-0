"use client";

/**
 * Il riepilogo dell'attività di vendita dentro `/account`.
 *
 * Sostituisce la vecchia scheda «Certificazioni», che mostrava tre stati
 * amministrativi e nessun fatto sull'attività della persona. Qui l'Account dice
 * invece che cosa sta succedendo — annunci vivi, ordini che aspettano un gesto,
 * vendite chiuse — e apre la porta verso `/vendite`, dove quella stessa attività
 * si gestisce davvero.
 *
 * ## Perché è un componente e non un blocco della pagina
 *
 * `page-client.tsx` è il modulo di modifica del profilo: ha il suo stato, le sue
 * validazioni e il suo salvataggio. Questa sezione ha un ciclo di vita
 * completamente diverso — due letture di rete che possono fallire da sole — e
 * tenerla separata è ciò che garantisce l'invariante richiesta: se la lettura
 * delle vendite fallisce, il modulo profilo continua a funzionare. Un errore
 * qui non ha modo di raggiungere quello stato.
 *
 * ## Non è una seconda dashboard
 *
 * Le quattro misure non sono ricalcolate: escono da `riepilogoVenditore()`, la
 * stessa funzione che alimenta i KPI di `/vendite`. Se un giorno «valore
 * indicativo» cambierà definizione, cambierà in un posto solo e le due
 * superfici non potranno raccontare due numeri diversi. Qui non c'è nessuna
 * soglia, nessun filtro e nessun conteggio locale.
 *
 * ## Due letture, non una per KPI
 *
 * Esattamente le stesse due di `/vendite`: `vendite()` per gli ordini e la
 * lettura degli annunci del proprietario. Nessuna interrogazione a `profiles`,
 * nessuna nuova tabella, nessuna query per singola misura.
 *
 * Degli annunci si chiede però `mieiAnnunciConEsito()` e non `mieiAnnunci()`.
 * Il secondo collassa deliberatamente errore ed elenco vuoto sullo stesso `[]`
 * — una scelta giusta per la gestione annunci, dove quel vuoto si vede — ma qui
 * quel `[]` diventerebbe il numero «annunci attivi: 0», e una lettura fallita
 * si presenterebbe come il fatto di non avere niente in vendita. È la stessa
 * query, senza il collasso.
 *
 * ## Chi la vede
 *
 * Chiunque sia autenticato. Non esiste un test «è un venditore»: non il ruolo,
 * non `seller_verificato`, non la presenza di annunci. Un account senza alcuna
 * attività legge quattro zeri, che sono la risposta vera alla domanda «quanto ho
 * venduto», non un vuoto da nascondere.
 */

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { Loader2, Store } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Kpi } from "@/components/vinea/Layout";
import { routes } from "@/config/routes";
import { formatEUR, formatInteger } from "@/lib/format";
import { riepilogoVenditore } from "@/lib/vendite/dashboard";
import { getSupabaseClient } from "@/lib/supabase/client";
import { createListingService, type AnnuncioProprietario } from "@/services/listing-service";
import { createOrderService } from "@/services/phase7/order-service";
import type { OrderRecord } from "@/services/types";

export default function AttivitaVendita() {
  const [ordini, setOrdini] = useState<OrderRecord[] | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const [annunci, setAnnunci] = useState<AnnuncioProprietario[] | null>(null);

  useEffect(() => {
    const client = getSupabaseClient();
    let vivo = true;

    // Le due letture partono insieme e si aspettano: i KPI hanno bisogno di
    // entrambe, e mostrarne una metà per volta significherebbe far salire
    // «annunci attivi» prima che «da gestire» esista.
    void Promise.all([
      createOrderService(client).vendite(),
      createListingService(client).mieiAnnunciConEsito(),
    ]).then(([esitoOrdini, esitoAnnunci]) => {
      if (!vivo) return;
      // Basta che una delle due fallisca perché i quattro numeri smettano di
      // essere veri: «annunci attivi» esce dalla seconda, tutto il resto dalla
      // prima. Un esito parziale qui è un riepilogo sbagliato, non un
      // riepilogo incompleto.
      if (!esitoOrdini.ok) setErrore(esitoOrdini.error);
      else if (!esitoAnnunci.ok) setErrore(esitoAnnunci.error);
      else {
        setOrdini(esitoOrdini.data);
        setAnnunci(esitoAnnunci.data);
      }
    });

    return () => {
      vivo = false;
    };
  }, []);

  const caricamento = ordini === null && errore === null;

  const righe = useMemo(() => ordini ?? [], [ordini]);
  const schede = useMemo(() => annunci ?? [], [annunci]);
  const riepilogo = useMemo(() => riepilogoVenditore(righe, schede), [righe, schede]);

  const vaiAlleVendite = (
    <Button asChild variant="outline" className="mt-5">
      <Link href={routes.vendite} data-testid="vai-alle-vendite">
        <Store className="h-4 w-4" /> Vai alle mie vendite
      </Link>
    </Button>
  );

  return (
    <section
      className="rounded-3xl border border-border bg-card p-5 md:p-8"
      data-testid="attivita-vendita"
    >
      <h2 className="font-serif text-xl md:text-2xl">Attività di vendita</h2>
      <p className="mt-2 text-sm text-muted-foreground">
        Un riepilogo di quello che hai in vendita e di quello che hai venduto. La gestione di
        annunci e ordini vive nelle tue vendite.
      </p>

      {caricamento ? (
        // Nessun numero prima che i dati esistano. Quattro zeri mostrati durante
        // l'attesa non sono un caricamento: sono un'affermazione, e per chi ha
        // davvero venduto sarebbe falsa per il tempo di una risposta di rete.
        <p className="mt-6 flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin text-bordeaux" />
          Carico la tua attività…
        </p>
      ) : errore !== null ? (
        // Compatto e generico, e soprattutto confinato qui: il modulo di
        // modifica del profilo sopra non sa nemmeno che questa lettura esiste.
        // Nessuno zero al posto di un dato mancante — uno zero falso è peggio di
        // un riepilogo assente.
        <p
          className="mt-6 rounded-xl border border-border bg-muted/40 p-3 text-sm text-muted-foreground"
          data-testid="attivita-vendita-errore"
        >
          Non siamo riusciti a leggere la tua attività di vendita. Riprova fra poco.
        </p>
      ) : (
        // Quattro misure, tutte da `riepilogoVenditore()`. Due parlano di
        // denaro e nessuna delle due è denaro incassato: «Valore indicativo» è
        // la somma dei prezzi *richiesti* sugli annunci ancora attivi — una
        // vetrina, non una vendita — e «Valore completate» è il prezzo
        // venditore congelato sugli ordini chiusi. Né saldo, né incassato, né
        // payout: il rilascio dei fondi è un'altra cosa e non si legge da qui,
        // ed è per questo che entrambe le etichette lo dicono a voce.
        //
        // «Da gestire» ha lasciato il posto al valore indicativo: era l'unica
        // delle quattro che chiedeva un'azione, e l'azione si fa in `/vendite`,
        // dove quel numero continua a esistere accanto al pulsante che lo
        // risolve. Qui l'Account resta un riepilogo.
        <div className="mt-6 grid grid-cols-2 gap-3">
          <Kpi
            label="Annunci attivi"
            value={formatInteger(riepilogo.annunciAttivi)}
            hint={`su ${formatInteger(schede.length)} in totale`}
          />
          <Kpi
            label="Valore indicativo"
            value={formatEUR(riepilogo.valoreIndicativoAttiviCents / 100)}
            hint="Prezzi richiesti degli attivi: non è un saldo, un incassato o un payout"
          />
          <Kpi
            label="Vendite completate"
            value={formatInteger(riepilogo.venditeCompletate)}
            hint="Ordini chiusi come completati"
          />
          <Kpi
            label="Valore completate"
            value={formatEUR(riepilogo.valoreVenditeCompletateCents / 100)}
            hint="Prezzo venditore, non un incassato"
          />
        </div>
      )}

      {vaiAlleVendite}
    </section>
  );
}
