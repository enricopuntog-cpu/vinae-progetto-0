"use client";

import { useState } from "react";

/**
 * La galleria di una bottiglia: immagine grande e miniature che la cambiano.
 *
 * Estratta dalla pagina dell'annuncio quando la pagina di degustazione ha avuto
 * bisogno della stessa cosa. Due copie della stessa galleria si sarebbero
 * separate alla prima correzione — e la richiesta era esplicitamente di
 * *riusare* il layout della scheda annuncio, non di somigliargli.
 *
 * Non sa niente di annunci né di degustazioni: riceve immagini e un nome per
 * l'alternativa testuale. È ciò che la rende usabile da entrambe senza che
 * nessuna delle due debba spiegarle in che pagina si trova.
 */
export function GalleriaVino({ immagini, nome }: { immagini: string[]; nome: string }) {
  const [attiva, setAttiva] = useState(0);
  // Un indice che sopravvive a un elenco accorciato punterebbe nel vuoto.
  const indice = attiva < immagini.length ? attiva : 0;

  if (immagini.length === 0) return null;

  return (
    <div>
      <div className="aspect-[4/5] overflow-hidden rounded-2xl bg-secondary">
        <img src={immagini[indice]} alt={nome} className="h-full w-full object-cover" />
      </div>
      {immagini.length > 1 ? (
        <div className="mt-3 flex gap-2">
          {immagini.map((src, i) => (
            <button
              key={i}
              onClick={() => setAttiva(i)}
              aria-label={`Fotografia ${i + 1} di ${immagini.length}`}
              className={`h-16 w-16 overflow-hidden rounded-lg border-2 ${
                indice === i ? "border-bordeaux" : "border-transparent"
              }`}
            >
              <img src={src} alt="" className="h-full w-full object-cover" />
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
