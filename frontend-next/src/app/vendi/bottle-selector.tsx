import Link from "next/link";
import { Wine as WineIcon } from "lucide-react";
import type { CellarBottle } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { Button } from "@/components/ui/button";
import { SafeImage } from "@/components/vinea/States";
import {
  chiaveCantina,
  etichettaBottiglie,
  unitaVendibiliDelGruppo,
} from "@/lib/cantina/gruppo";

type BottleSelectorProps = {
  bottiglie: CellarBottle[];
  vini: Wine[];
};

/**
 * Un gruppo per vino e formato (VP-C), non una scheda per bottiglia: chi ha 12
 * Barolo 2019 sceglie il Barolo 2019 e poi, nel wizard, quante metterne in
 * vendita. Il collegamento porta la prima bottiglia libera del gruppo; le altre
 * le propone il wizard, e il database le riverifica una per una.
 */
export const BottleSelector = ({ bottiglie, vini }: BottleSelectorProps) => {
  const gruppi = vini
    .map((vino) => {
      const chiave = chiaveCantina(vino);
      return { vino, libere: unitaVendibiliDelGruppo(bottiglie, chiave) };
    })
    .filter((g) => g.libere.length > 0);

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <h1 className="font-serif text-3xl md:text-4xl">Scegli dalla tua Cantina</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Una vendita parte sempre da bottiglie esistenti, chiuse e non già impegnate.
        </p>
      </div>

      {gruppi.length === 0 ? (
        <div className="rounded-3xl border border-dashed border-border bg-card p-8 text-center">
          <WineIcon className="mx-auto h-9 w-9 text-bordeaux" />
          <p className="mt-3 font-serif text-xl">Nessuna bottiglia vendibile</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Aggiungi prima una bottiglia privata o pubblica alla Cantina.
          </p>
          <Button asChild className="mt-4 bg-bordeaux hover:bg-bordeaux/90">
            <Link href="/vendi?mode=catalog">Aggiungi bottiglia</Link>
          </Button>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {gruppi.map(({ vino, libere }) => (
            <Link
              key={chiaveCantina(vino)}
              href={`/vendi?mode=sell&bottiglia=${libere[0].bottleId}`}
              className="flex gap-3 rounded-2xl border border-border bg-card p-3 transition hover:border-bordeaux/40 hover:shadow-md"
            >
              <SafeImage
                src={vino.immagini[0]}
                alt={vino.nome}
                className="h-24 w-20 shrink-0 rounded-xl object-cover"
                fallbackLabel="Foto non disponibile"
              />
              <div className="min-w-0">
                <p className="text-xs uppercase tracking-wide text-salvia">{vino.produttore}</p>
                <p className="truncate font-serif font-semibold">
                  {vino.nome} {vino.annata}
                </p>
                <p className="mt-1 text-xs text-muted-foreground">{vino.formato}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {etichettaBottiglie(libere.length)} {libere.length === 1 ? "libera" : "libere"}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
};
