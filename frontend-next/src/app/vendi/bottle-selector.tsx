import Link from "next/link";
import { Wine as WineIcon } from "lucide-react";
import type { CellarBottle } from "@/data/cellar";
import type { Wine } from "@/data/wines";
import { Button } from "@/components/ui/button";
import { SafeImage } from "@/components/vinea/States";

type BottleSelectorProps = {
  bottiglie: CellarBottle[];
  vini: Wine[];
};

export const BottleSelector = ({ bottiglie, vini }: BottleSelectorProps) => {
  const vinoPerSlug = new Map(vini.map((vino) => [vino.wineSlug ?? vino.id, vino]));
  const disponibili = bottiglie
    .filter(
      (bottiglia) =>
        bottiglia.quantita > 0 &&
        (bottiglia.saleStatus === "privata" ||
          bottiglia.saleStatus === "cantina_pubblica"),
    )
    .map((bottiglia) => ({ bottiglia, vino: vinoPerSlug.get(bottiglia.wineVintageId) }))
    .filter((voce): voce is { bottiglia: CellarBottle; vino: Wine } => Boolean(voce.vino));

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <h1 className="font-serif text-3xl md:text-4xl">Scegli dalla tua Cantina</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Una vendita parte sempre da una bottiglia esistente, chiusa e non già impegnata.
        </p>
      </div>

      {disponibili.length === 0 ? (
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
          {disponibili.map(({ bottiglia, vino }) => (
            <Link
              key={bottiglia.bottleId}
              href={`/vendi?mode=sell&bottiglia=${bottiglia.bottleId}`}
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
                <p className="mt-2 text-xs text-muted-foreground">
                  {bottiglia.saleStatus === "cantina_pubblica"
                    ? "Cantina pubblica"
                    : "Cantina privata"}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
};
