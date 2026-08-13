import { Bot } from "lucide-react";
import { ETICHETTA_IA, type SuperficieIA } from "@/lib/phase10/etichette-ia";

/**
 * L'etichetta di trasparenza IA, identica in forma sulle tre superfici.
 *
 * Il testo vive in `@/lib/phase10/etichette-ia` insieme alla ragione per cui
 * esiste; qui c'è solo il modo di mostrarlo. Due varianti perché una delle tre
 * intestazioni è su fondo bordeaux e le altre due su fondo chiaro: la forma
 * resta la stessa, così l'etichetta si riconosce come lo stesso elemento anche
 * passando da un pannello all'altro.
 *
 * L'icona è `Bot` e non `Sparkles`, che in questo progetto è il segno dell'IA
 * (`TrustBadge`) ma è già l'avatar accanto al titolo di tutti e tre i pannelli:
 * ripeterla renderebbe l'etichetta parte della decorazione invece che un
 * elemento a sé.
 */
export function AiTransparencyLabel({
  superficie,
  variante = "chiara",
}: {
  superficie: SuperficieIA;
  variante?: "chiara" | "scura";
}) {
  // La variante chiara riprende i colori che il progetto già usa per marcare la
  // provenienza IA (`TrustBadge`, sorgente `ia`). La scura tiene il crema del
  // testo dell'intestazione invece dell'oro degli accenti: un'etichetta va
  // letta, e l'oro su bordeaux a questa dimensione si legge male.
  const cls =
    variante === "scura"
      ? "border-crema/30 bg-crema/15 text-crema"
      : "border-oro/40 bg-oro/15 text-antracite";

  return (
    <p
      data-testid={`ai-transparency-${superficie}`}
      className={`mt-1 inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-medium ${cls}`}
    >
      <Bot aria-hidden className="h-3 w-3 shrink-0" />
      {ETICHETTA_IA[superficie]}
    </p>
  );
}
