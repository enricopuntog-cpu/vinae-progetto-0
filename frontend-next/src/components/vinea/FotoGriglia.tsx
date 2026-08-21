"use client";

import { useRef, useState } from "react";
import { ArrowLeft, ArrowRight, Camera, Loader2, RefreshCw, X } from "lucide-react";
import { MAX_FOTO } from "@/lib/annunci/foto-modifica";

export type FotoGrigliaItem = {
  chiave?: string;
  percorso: string;
  anteprima: string;
};

type FotoGrigliaProps = {
  foto: FotoGrigliaItem[];
  inCorso: boolean;
  onCarica: (file: File) => void | Promise<void>;
  onRimuovi: (indice: number) => void | Promise<void>;
  onSostituisci?: (indice: number, file: File) => void | Promise<void>;
  onSposta?: (indice: number, direzione: -1 | 1) => void;
  mostraPrincipale?: boolean;
};

const ACCEPT = "image/jpeg,image/png,image/webp,image/avif";

/**
 * Le sei caselle fotografiche condivise dal wizard e dall'editor proprietario.
 * Le funzioni di ordine e sostituzione sono opzionali: senza di esse il wizard
 * /vendi conserva la propria presentazione e il proprio comportamento.
 */
export function FotoGriglia({
  foto,
  inCorso,
  onCarica,
  onRimuovi,
  onSostituisci,
  onSposta,
  mostraPrincipale = false,
}: FotoGrigliaProps) {
  const inputAggiunta = useRef<HTMLInputElement>(null);
  const inputSostituzione = useRef<HTMLInputElement>(null);
  const [indiceSostituzione, setIndiceSostituzione] = useState<number | null>(null);
  const editor = Boolean(onSostituisci || onSposta || mostraPrincipale);

  const avviaSostituzione = (indice: number) => {
    setIndiceSostituzione(indice);
    inputSostituzione.current?.click();
  };

  return (
    <>
      <input
        ref={inputAggiunta}
        type="file"
        accept={ACCEPT}
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void onCarica(file);
          // Permette di riselezionare lo stesso file dopo averlo tolto.
          e.target.value = "";
        }}
      />
      {onSostituisci ? (
        <input
          ref={inputSostituzione}
          type="file"
          accept={ACCEPT}
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file && indiceSostituzione !== null) {
              void onSostituisci(indiceSostituzione, file);
            }
            setIndiceSostituzione(null);
            e.target.value = "";
          }}
        />
      ) : null}

      <div className="grid grid-cols-3 gap-3">
        {foto.map((f, i) => (
          <div
            key={f.chiave ?? f.percorso}
            className={`relative aspect-square overflow-hidden rounded-xl border border-border${editor ? " bg-secondary/50" : ""}`}
          >
            {/* Le anteprime possono essere blob: locali, quindi next/image non è adatto. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={f.anteprima}
              alt={editor ? (i === 0 ? "Fotografia principale dell'annuncio" : `Fotografia ${i + 1}`) : ""}
              className="h-full w-full object-cover"
            />

            {mostraPrincipale && i === 0 ? (
              <span className="absolute left-1.5 top-1.5 rounded-full bg-bordeaux px-2 py-1 text-[10px] font-semibold text-crema shadow-sm">
                Foto principale
              </span>
            ) : null}

            {onSposta || onSostituisci ? (
              <div className="absolute bottom-1.5 left-1.5 flex gap-1">
                {onSposta ? (
                  <>
                    <button
                      type="button"
                      onClick={() => onSposta(i, -1)}
                      disabled={inCorso || i === 0}
                      aria-label={`Sposta la fotografia ${i + 1} prima`}
                      className="grid h-7 w-7 place-items-center rounded-full bg-background/95 text-foreground shadow-sm hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50"
                    >
                      <ArrowLeft className="h-3.5 w-3.5" />
                    </button>
                    <button
                      type="button"
                      onClick={() => onSposta(i, 1)}
                      disabled={inCorso || i === foto.length - 1}
                      aria-label={`Sposta la fotografia ${i + 1} dopo`}
                      className="grid h-7 w-7 place-items-center rounded-full bg-background/95 text-foreground shadow-sm hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50"
                    >
                      <ArrowRight className="h-3.5 w-3.5" />
                    </button>
                  </>
                ) : null}

                {onSostituisci ? (
                  <button
                    type="button"
                    onClick={() => avviaSostituzione(i)}
                    disabled={inCorso}
                    aria-label={`Sostituisci la fotografia ${i + 1}`}
                    className="grid h-7 w-7 place-items-center rounded-full bg-background/95 text-foreground shadow-sm hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50"
                  >
                    <RefreshCw className="h-3.5 w-3.5" />
                  </button>
                ) : null}
              </div>
            ) : null}

            <button
              type="button"
              onClick={() => void onRimuovi(i)}
              disabled={editor && inCorso}
              aria-label={editor ? `Rimuovi la fotografia ${i + 1}` : "Rimuovi fotografia"}
              className={
                editor
                  ? "absolute right-1.5 top-1.5 grid h-7 w-7 place-items-center rounded-full bg-background/95 text-foreground shadow-sm hover:bg-destructive hover:text-destructive-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50"
                  : "absolute right-1 top-1 grid h-6 w-6 place-items-center rounded-full bg-antracite/70 text-crema hover:bg-antracite"
              }
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}

        {Array.from({ length: Math.max(0, MAX_FOTO - foto.length) }).map((_, i) => (
          <button
            type="button"
            key={`vuota-${i}`}
            onClick={() => inputAggiunta.current?.click()}
            disabled={inCorso}
            aria-label={editor ? "Aggiungi fotografia" : undefined}
            className="grid aspect-square place-items-center rounded-xl border-2 border-dashed border-border bg-secondary/50 text-muted-foreground hover:border-bordeaux hover:text-bordeaux disabled:opacity-50"
          >
            {inCorso && i === 0 ? (
              <Loader2 className="h-6 w-6 animate-spin" />
            ) : (
              <Camera className="h-6 w-6" />
            )}
          </button>
        ))}
      </div>
      <p className="text-[11px] text-muted-foreground">
        JPEG, PNG, WebP o AVIF, fino a 5 MB per fotografia.
      </p>
    </>
  );
}
