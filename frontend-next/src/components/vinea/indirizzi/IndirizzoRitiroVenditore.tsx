"use client";

import Link from "next/link";
import { useState } from "react";
import { Home } from "lucide-react";
import { Button } from "@/components/ui/button";
import { daIndirizzo, indirizzoVuoto, rigaIndirizzo, ritiroPredefinito } from "@/lib/indirizzi/rubrica";
import { FormIndirizzo } from "./FormIndirizzo";
import { useRubrica } from "./useRubrica";

/**
 * Ritiro a domicilio scelto dal venditore privato: il corriere passa
 * all'indirizzo di ritiro predefinito della rubrica. Senza di esso il
 * database non apre il preventivo né il checkout (`indirizzo_ritiro_mancante`),
 * quindi qui si dice e si permette di indicarlo subito. Il corriere non lo
 * sceglie il venditore: lo decide il routing di Vinea.
 */
export function IndirizzoRitiroVenditore() {
  const { indirizzi, errore, caricamento, salva } = useRubrica();
  const [modifica, setModifica] = useState(false);

  if (caricamento && !indirizzi) return <p className="text-xs text-muted-foreground">Verifica dell&apos;indirizzo di ritiro…</p>;
  if (!indirizzi) {
    return (
      <p role="alert" className="text-xs text-red-700">
        {errore ?? "La rubrica non è leggibile in questo momento."}
      </p>
    );
  }
  const ritiro = ritiroPredefinito(indirizzi);

  return (
    <div className="space-y-3 rounded-xl border border-border p-3" data-testid="indirizzo-ritiro-venditore">
      <div className="flex gap-3 text-sm">
        <Home className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" aria-hidden />
        {ritiro ? (
          <div>
            <p className="font-medium">Il corriere ritirerà qui</p>
            <p className="text-muted-foreground">
              {ritiro.destinatario} · {rigaIndirizzo(ritiro)}
            </p>
            <p className="text-xs text-muted-foreground">
              L&apos;acquirente ne vede solo città e provincia.
            </p>
          </div>
        ) : (
          <div role="status">
            <p className="font-medium">Manca l&apos;indirizzo di ritiro</p>
            <p className="text-xs text-muted-foreground">
              Finché non lo indichi, l&apos;annuncio non si può acquistare con la spedizione.
            </p>
          </div>
        )}
      </div>
      {modifica ? (
        <FormIndirizzo
          id={ritiro?.id ?? null}
          iniziale={ritiro ? daIndirizzo(ritiro) : indirizzoVuoto({ predefinitoRitiro: true })}
          mostraPredefiniti={false}
          etichettaSalva="Salva indirizzo di ritiro"
          onSalva={async (id, dati) => {
            const esito = await salva(id, { ...dati, predefinitoRitiro: true });
            if (esito.ok) setModifica(false);
            return esito;
          }}
          onAnnulla={() => setModifica(false)}
        />
      ) : (
        <div className="flex flex-wrap items-center gap-3">
          <Button type="button" size="sm" variant="outline" onClick={() => setModifica(true)}>
            {ritiro ? "Modifica indirizzo di ritiro" : "Indica l'indirizzo di ritiro"}
          </Button>
          <Link href="/account#indirizzi" className="text-xs text-bordeaux underline underline-offset-2">
            Scegline un altro dalla rubrica
          </Link>
        </div>
      )}
    </div>
  );
}
