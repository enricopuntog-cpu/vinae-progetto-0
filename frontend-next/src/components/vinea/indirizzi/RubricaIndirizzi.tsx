"use client";

import { useState } from "react";
import { MapPin, Pencil, Plus, Archive } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  MAX_INDIRIZZI,
  daIndirizzo,
  indirizzoVuoto,
  rigaIndirizzo,
  titoloIndirizzo,
} from "@/lib/indirizzi/rubrica";
import type { Indirizzo } from "@/services/types";
import { FormIndirizzo } from "./FormIndirizzo";
import { SedePartnerRitiro } from "./SedePartnerRitiro";
import { useRubrica } from "./useRubrica";

/**
 * La rubrica privata degli indirizzi in /account: aggiungere, modificare,
 * archiviare, scegliere il predefinito di consegna e quello di ritiro.
 *
 * Tutto passa dalle porte `indirizzo_*`, che risolvono il proprietario da
 * `auth.uid()`: nessun altro utente legge questi indirizzi. Archiviare non
 * tocca gli ordini, che ne hanno già congelato una copia.
 */
export default function RubricaIndirizzi() {
  const { indirizzi, errore, caricamento, salva, archivia } = useRubrica();
  const [modifica, setModifica] = useState<string | "nuovo" | null>(null);
  const [erroreArchivio, setErroreArchivio] = useState<string | null>(null);
  const [inArchivio, setInArchivio] = useState<string | null>(null);

  const archiviaIndirizzo = async (i: Indirizzo) => {
    if (inArchivio) return;
    if (!window.confirm(`Archiviare «${titoloIndirizzo(i)}»? Gli ordini già fatti non cambiano.`)) return;
    setInArchivio(i.id);
    setErroreArchivio(null);
    const esito = await archivia(i.id);
    setInArchivio(null);
    if (!esito.ok) setErroreArchivio(esito.error);
    else if (modifica === i.id) setModifica(null);
  };

  const pieno = (indirizzi?.length ?? 0) >= MAX_INDIRIZZI;

  return (
    <section
      id="indirizzi"
      className="space-y-4 rounded-3xl border border-border bg-card p-5 md:p-6"
      data-testid="rubrica-indirizzi"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-serif text-2xl">I tuoi indirizzi</h2>
          <p className="text-sm text-muted-foreground">
            Visibili solo a te. Al venditore arrivano solo città e provincia della consegna; l&apos;indirizzo completo
            serve al corriere.
          </p>
        </div>
        {modifica === null && indirizzi && !pieno ? (
          <Button variant="outline" onClick={() => setModifica("nuovo")} data-testid="rubrica-aggiungi">
            <Plus className="h-4 w-4" /> Aggiungi indirizzo
          </Button>
        ) : null}
      </div>

      {caricamento && !indirizzi ? <p className="text-sm text-muted-foreground">Caricamento degli indirizzi…</p> : null}
      {errore && !indirizzi ? (
        <p role="alert" className="text-sm text-red-700">
          {errore}
        </p>
      ) : null}
      {erroreArchivio ? (
        <p role="alert" className="text-sm text-red-700">
          {erroreArchivio}
        </p>
      ) : null}

      {modifica === "nuovo" ? (
        <FormIndirizzo
          id={null}
          iniziale={indirizzoVuoto({
            predefinitoConsegna: indirizzi?.length === 0,
          })}
          onSalva={async (id, dati) => {
            const esito = await salva(id, dati);
            if (esito.ok) setModifica(null);
            return esito;
          }}
          onAnnulla={() => setModifica(null)}
        />
      ) : null}

      {indirizzi && indirizzi.length === 0 && modifica !== "nuovo" ? (
        <p className="text-sm text-muted-foreground" data-testid="rubrica-vuota">
          Nessun indirizzo salvato. Senza indirizzi puoi comunque ricevere al punto di ritiro.
        </p>
      ) : null}

      <ul className="space-y-3">
        {indirizzi?.map((i) =>
          modifica === i.id ? (
            <li key={i.id} className="rounded-2xl border border-border p-4">
              <FormIndirizzo
                id={i.id}
                iniziale={daIndirizzo(i)}
                onSalva={async (id, dati) => {
                  const esito = await salva(id, dati);
                  if (esito.ok) setModifica(null);
                  return esito;
                }}
                onAnnulla={() => setModifica(null)}
              />
            </li>
          ) : (
            <li
              key={i.id}
              className="flex flex-wrap items-start justify-between gap-3 rounded-2xl border border-border p-4"
              data-testid="rubrica-indirizzo"
            >
              <div className="flex gap-3">
                <MapPin className="mt-0.5 h-5 w-5 shrink-0 text-bordeaux" aria-hidden />
                <div className="min-w-0 text-sm">
                  <p className="font-semibold">{titoloIndirizzo(i)}</p>
                  {i.etichetta ? <p>{i.destinatario}</p> : null}
                  <p className="text-muted-foreground">{rigaIndirizzo(i)}</p>
                  <div className="mt-1 flex flex-wrap gap-1">
                    {i.predefinitoConsegna ? <Etichetta testo="Consegna predefinita" /> : null}
                    {i.predefinitoRitiro ? <Etichetta testo="Ritiro predefinito" /> : null}
                  </div>
                </div>
              </div>
              {modifica === null ? (
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" onClick={() => setModifica(i.id)}>
                    <Pencil className="h-4 w-4" /> Modifica
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={inArchivio === i.id}
                    onClick={() => void archiviaIndirizzo(i)}
                  >
                    <Archive className="h-4 w-4" /> Archivia
                  </Button>
                </div>
              ) : null}
            </li>
          ),
        )}
      </ul>
      {pieno ? (
        <p className="text-xs text-muted-foreground">
          Hai raggiunto il massimo di {MAX_INDIRIZZI} indirizzi: archiviane uno per aggiungerne un altro.
        </p>
      ) : null}
      <SedePartnerRitiro />
    </section>
  );
}

const Etichetta = ({ testo }: { testo: string }) => (
  <span className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium">{testo}</span>
);
