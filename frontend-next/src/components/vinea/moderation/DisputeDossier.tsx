"use client";

// Fascicolo di contestazione — le tre sezioni di sola lettura del dossier.
//
// Vivono in un file proprio per una ragione di sostanza, non di lunghezza:
// `RigaContestazione` e la riga che DECIDE, e ogni cosa che sta dentro il suo
// corpo somiglia a un comando. Queste tre sezioni non comandano niente. Non
// hanno stato, non chiamano RPC, non muovono denaro, non toccano il ciclo di
// vita della pratica: ricevono la riga e la mostrano. Tenerle separate rende
// vero a colpo d'occhio cio che altrimenti andrebbe verificato leggendo.
//
// LE TRE CLASSI DI FOTOGRAFIA NON SI MESCOLANO MAI.
//
//   A  Fotografie dell'annuncio e della confezione originale dichiarata.
//      Bucket pubblico, URL gia risolti dal servizio. Sono il RIFERIMENTO:
//      che cosa era stato promesso.
//   B  Prove pre-spedizione del venditore. Bucket privato, URL firmati a 15
//      minuti. Sono lo STATO DELLA MERCE alla chiusura del pacco.
//   C  Prove caricate dentro la pratica, dal compratore e dal venditore.
//      Stesso bucket privato di B, atto diverso: accusa e difesa.
//
// Una fotografia di catalogo scambiata per una prova di imballaggio cambia il
// verdetto. Per questo le sezioni sono tre, con tre titoli espliciti, e nessuna
// griglia unica le riunisce.

import { Badge } from "@/components/ui/badge";
import { ETICHETTA_CONFEZIONE_ORIGINALE } from "@/lib/vendi/logistica-annuncio";
import type { DisputeQueueRow } from "@/services/phase9/supabase-moderation-service";

// Stessa forma del formattatore del pannello. Non e importato da li perche
// `ModerationPanelClient` importa questo modulo: sarebbe un ciclo.
const dataOra = (iso: string) =>
  new Date(iso).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" });

/** Un campo che puo non esserci. Assente si dice, non si tace. */
const Campo = ({ etichetta, valore }: { etichetta: string; valore: string | null }) => (
  <div>
    <dt className="text-muted-foreground">{etichetta}</dt>
    <dd>{valore ?? "Non disponibile"}</dd>
  </div>
);

const Sezione = ({
  titolo,
  testId,
  children,
}: {
  titolo: string;
  testId: string;
  children: React.ReactNode;
}) => (
  <div className="space-y-2 rounded-lg border p-3" data-testid={testId}>
    <p className="text-xs font-semibold uppercase">{titolo}</p>
    {children}
  </div>
);

// ---------------------------------------------------------------------------
// A — L'annuncio collegato alla vendita
// ---------------------------------------------------------------------------

/**
 * Titolo deliberato: «Annuncio collegato alla vendita», NON «snapshot storico».
 *
 * Queste righe arrivano da un join su `public.listings` fatto adesso: sono
 * l'annuncio com'e oggi. Se il venditore lo ha modificato dopo la vendita, qui
 * si legge la versione modificata. Chiamarlo snapshot avrebbe promesso al
 * moderatore una fotografia del momento dell'acquisto che il database non
 * conserva, ed e il genere di promessa che si scopre falsa solo dopo una
 * decisione sbagliata.
 */
export const DisputeListingEvidence = ({ riga }: { riga: DisputeQueueRow }) => {
  const { listing } = riga;
  const etichettaConfezione = listing.originalPackagingType
    ? ETICHETTA_CONFEZIONE_ORIGINALE[listing.originalPackagingType]
    : null;

  return (
    <Sezione titolo="Annuncio collegato alla vendita" testId={`contestazione-annuncio-${riga.orderId}`}>
      <p className="text-xs text-muted-foreground">
        Dati dell&apos;annuncio come sono adesso, non una copia congelata al momento della vendita.
      </p>
      <dl className="grid gap-2 text-xs sm:grid-cols-2">
        <Campo etichetta="Annuncio" valore={listing.slug} />
        <Campo etichetta="Identificativo annuncio" valore={listing.id} />
      </dl>

      <p className="text-xs font-medium">Foto dell&apos;annuncio</p>
      {listing.images.length === 0 ? (
        <p className="text-xs text-muted-foreground">Nessuna foto sull&apos;annuncio.</p>
      ) : (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {listing.images.map((url, index) => (
            // eslint-disable-next-line @next/next/no-img-element -- Bucket pubblico `annunci`, URL risolto dal servizio.
            <img
              key={url}
              src={url}
              alt={`Foto dell'annuncio ${index + 1}`}
              data-testid={`contestazione-annuncio-foto-${riga.orderId}`}
              className="aspect-square rounded-lg border object-cover"
            />
          ))}
        </div>
      )}

      <div className="space-y-2 border-t pt-2">
        <p className="text-xs font-medium">Confezione originale</p>
        {/*
          `null` e «non dichiarata», e resta tale. Tradurlo in «nessuna
          confezione originale» significherebbe attestare al posto del venditore
          un fatto che non ha mai dichiarato — e in una contestazione
          sull'imballaggio quel fatto e proprio l'oggetto del contendere.
        */}
        <p className="text-xs" data-testid={`contestazione-confezione-${riga.orderId}`}>
          {etichettaConfezione ?? "Non dichiarata"}
        </p>
        {etichettaConfezione ? null : (
          <p className="text-xs text-muted-foreground">
            Confezione originale non dichiarata.
          </p>
        )}
        {listing.originalPackagingImages.length > 0 ? (
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {listing.originalPackagingImages.map((url, index) => (
              // eslint-disable-next-line @next/next/no-img-element -- Bucket pubblico `annunci`, URL risolto dal servizio.
              <img
                key={url}
                src={url}
                alt={`Foto della confezione originale ${index + 1}`}
                data-testid={`contestazione-confezione-foto-${riga.orderId}`}
                className="aspect-square rounded-lg border object-cover"
              />
            ))}
          </div>
        ) : null}
      </div>
    </Sezione>
  );
};

// ---------------------------------------------------------------------------
// B — Le prove pre-spedizione del venditore
// ---------------------------------------------------------------------------

const ETICHETTA_PROVA: Record<"collo_finale" | "interno_pre_chiusura", string> = {
  collo_finale: "Pacco finale chiuso",
  interno_pre_chiusura: "Interno prima della chiusura",
};

// L'ordine e fisso e non dipende dai dati: prima il pacco chiuso, poi il suo
// interno. Due fascicoli aperti in due momenti diversi si leggono nello stesso
// ordine, che e cio che rende confrontabili due casi.
const ORDINE_PROVE = ["collo_finale", "interno_pre_chiusura"] as const;

/**
 * Correnti E sostituite, nello stesso elenco, marcate in modo diverso.
 *
 * Fuori da una contestazione una prova sostituita e rumore: conta l'ultima.
 * Dentro una contestazione e materiale probatorio, perche dice che cosa il
 * venditore aveva documentato prima e quando ha cambiato la documentazione.
 * Una prova sostituita non sparisce mai da questo elenco.
 */
export const DisputeShippingEvidence = ({ riga }: { riga: DisputeQueueRow }) => {
  const prove = riga.shipment.evidence;

  return (
    <Sezione
      titolo="Prove pre-spedizione del venditore"
      testId={`contestazione-prove-spedizione-${riga.orderId}`}
    >
      {prove.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          Nessuna prova pre-spedizione registrata per questo ordine.
        </p>
      ) : (
        ORDINE_PROVE.map((tipo) => {
          const gruppo = prove.filter((prova) => prova.kind === tipo);
          return (
            <div key={tipo} className="space-y-2">
              <p className="text-xs font-medium">{ETICHETTA_PROVA[tipo]}</p>
              {gruppo.length === 0 ? (
                <p className="text-xs text-muted-foreground">Nessuna prova di questo tipo.</p>
              ) : (
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  {gruppo.map((prova) => (
                    <figure
                      key={prova.id}
                      className="space-y-1"
                      data-testid={`contestazione-prova-spedizione-${prova.id}`}
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element -- URL firmato temporaneo. */}
                      <img
                        src={prova.signedUrl}
                        alt={`${ETICHETTA_PROVA[tipo]} · ${prova.current ? "corrente" : "sostituita"}`}
                        className="aspect-square w-full rounded-lg border object-cover"
                      />
                      <figcaption className="space-y-0.5 text-[11px]">
                        <Badge className={prova.current ? "" : "bg-muted text-muted-foreground"}>
                          {prova.current ? "Corrente" : "Sostituita"}
                        </Badge>
                        <time dateTime={prova.createdAt} className="block text-muted-foreground">
                          {dataOra(prova.createdAt)}
                        </time>
                        {prova.supersededAt ? (
                          <time dateTime={prova.supersededAt} className="block text-muted-foreground">
                            Sostituita il {dataOra(prova.supersededAt)}
                          </time>
                        ) : null}
                      </figcaption>
                    </figure>
                  ))}
                </div>
              )}
            </div>
          );
        })
      )}
    </Sezione>
  );
};

// ---------------------------------------------------------------------------
// Spedizione, consegna e tracking
// ---------------------------------------------------------------------------

const ETICHETTA_EVENTO_TRACKING: Record<string, string> = {
  info: "Informazione",
  spedizione: "Spedizione",
  consegna: "Consegna",
  problema: "Problema",
  sistema: "Sistema",
};

/**
 * NESSUNA PROVA DI CONSEGNA DEL VETTORE.
 *
 * Nessun provider logistico e integrato: il POD non esiste come dato e non
 * viene simulato. `consegnato_at` e uno stato del NOSTRO dominio — qualcuno ha
 * registrato la consegna qui dentro — e leggerlo come prova del corriere
 * significherebbe attribuire a un terzo un'attestazione che quel terzo non ha
 * mai dato. Il riquadro lo dice esplicitamente invece di lasciare un vuoto che
 * il lettore riempirebbe da solo.
 *
 * Nessun collegamento profondo al sito del corriere: senza una mappatura
 * affidabile corriere → URL, un link costruito a intuito porta a una pagina
 * sbagliata o a un dominio che non controlliamo.
 */
export const DisputeTrackingPanel = ({ riga }: { riga: DisputeQueueRow }) => {
  const { shipment } = riga;

  return (
    <Sezione titolo="Spedizione e consegna" testId={`contestazione-spedizione-${riga.orderId}`}>
      <dl className="grid gap-2 text-xs sm:grid-cols-2">
        <Campo etichetta="Corriere" valore={shipment.carrier} />
        <Campo etichetta="Codice di tracking" valore={shipment.trackingNumber} />
        <Campo etichetta="Spedito il" valore={shipment.shippedAt ? dataOra(shipment.shippedAt) : null} />
        <Campo
          etichetta="Consegna registrata il"
          valore={shipment.deliveredAt ? dataOra(shipment.deliveredAt) : null}
        />
        <Campo
          etichetta="Ricezione confermata dall'acquirente"
          valore={shipment.receiptConfirmedAt ? dataOra(shipment.receiptConfirmedAt) : null}
        />
        <div data-testid={`contestazione-pod-${riga.orderId}`}>
          <dt className="text-muted-foreground">POD vettore</dt>
          <dd>non disponibile</dd>
        </div>
      </dl>
      <p className="text-xs text-muted-foreground">
        La prova di consegna del vettore sarà disponibile quando verrà integrato il provider
        logistico.
      </p>

      <div className="space-y-2 border-t pt-2">
        <p className="text-xs font-medium">Eventi di tracking</p>
        {shipment.trackingEvents.length === 0 ? (
          <p className="text-xs text-muted-foreground">Nessun evento di tracking registrato.</p>
        ) : (
          <ol className="space-y-2">
            {shipment.trackingEvents.map((evento) => (
              <li
                key={evento.id}
                data-testid={`contestazione-tracking-evento-${evento.id}`}
                className="flex flex-col gap-0.5 text-xs sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <span>
                    {ETICHETTA_EVENTO_TRACKING[evento.tipo] ?? evento.tipo} · {evento.titolo}
                    {evento.luogo ? ` · ${evento.luogo}` : ""}
                  </span>
                  {evento.descrizione ? (
                    <p className="text-muted-foreground">{evento.descrizione}</p>
                  ) : null}
                </div>
                <time dateTime={evento.createdAt} className="text-muted-foreground">
                  {dataOra(evento.createdAt)}
                </time>
              </li>
            ))}
          </ol>
        )}
      </div>
    </Sezione>
  );
};
