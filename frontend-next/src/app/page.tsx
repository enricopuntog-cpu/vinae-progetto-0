import { Wine } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { TrustBadge } from "@/components/vinea/TrustBadge";

export default function Home() {
  return (
    <main className="mx-auto flex max-w-2xl flex-1 flex-col justify-center gap-6 px-6 py-16">
      <div className="flex items-center gap-3">
        <span className="grid h-12 w-12 place-items-center rounded-full bg-bordeaux text-crema">
          <Wine className="h-6 w-6" />
        </span>
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-oro">Vinea Wine Club</p>
          <h1 className="font-serif text-3xl">
            Scaffold <span className="gold-shimmer">Next.js</span>
          </h1>
        </div>
      </div>
      <p className="text-muted-foreground">
        Fase 2 della traccia Migrazione: questa pagina esiste solo per verificare che il design
        system (Tailwind v4 con i token del brand, shadcn/ui, componenti Vinea copiati) funzioni
        correttamente su Next.js. Nessuna route reale è ancora collegata.
      </p>
      <div className="flex flex-wrap items-center gap-3">
        <Button className="bg-bordeaux hover:bg-bordeaux/90">Bottone primario</Button>
        <Button variant="outline">Bottone outline</Button>
        <Badge>Badge shadcn</Badge>
        <TrustBadge source="piattaforma" />
      </div>
    </main>
  );
}
