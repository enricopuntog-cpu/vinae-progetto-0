import { Label } from "@/components/ui/label";

/**
 * Identificatori stabili dei controlli del wizard `/vendi` (VPM-018-UX-A11Y-01,
 * R-A11Y-01). Ogni `Field` dichiara a quale controllo appartiene la sua
 * etichetta con `htmlFor`, e il controllo porta lo stesso `id`: la lettura dello
 * schermo e il tocco sull'etichetta non dipendono dal segnaposto. Gli id sono
 * costanti, non generati, perché il wizard vive una sola volta per pagina e i
 * casi nel browser li possono nominare.
 */
export const CAMPO_ID = {
  produttore: "vendi-produttore",
  nome: "vendi-nome",
  annata: "vendi-annata",
  regione: "vendi-regione",
  tipologia: "vendi-tipologia",
  formato: "vendi-formato",
  quantita: "vendi-quantita",
  conservazione: "vendi-conservazione",
  storia: "vendi-storia",
  prezzoAcquisto: "vendi-prezzo-acquisto",
  dataAcquisto: "vendi-data-acquisto",
  prezzo: "vendi-prezzo",
  disponibili: "vendi-disponibili",
} as const;

/** `htmlFor` è obbligatorio: un campo nuovo senza etichetta associata non compila. */
export function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor} className="text-xs uppercase tracking-wide text-muted-foreground">
        {label}
      </Label>
      {children}
    </div>
  );
}
