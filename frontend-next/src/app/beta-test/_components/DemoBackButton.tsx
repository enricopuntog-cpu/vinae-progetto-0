import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * L'unico controllo di ritorno delle schermate della guida: sempre in alto a
 * sinistra, sempre «Indietro». Riporta alla schermata precedente della guida,
 * mai a una pagina del sito.
 */
export function DemoBackButton({ onBack }: { onBack: () => void }) {
  return (
    <Button
      type="button"
      variant="outline"
      className="min-h-11 gap-1.5 self-start px-4 text-base"
      onClick={onBack}
      data-testid="mv-back"
    >
      <ArrowLeft className="h-4 w-4" aria-hidden />
      Indietro
    </Button>
  );
}
