import { Bot, CreditCard, Truck, type LucideIcon } from "lucide-react";
import type { AzioneEsternaBeta } from "@/lib/beta/external-actions";
import { MESSAGGI_AZIONI_BETA } from "@/lib/beta/external-actions";

const ICONE: Record<AzioneEsternaBeta, LucideIcon> = {
  ia: Bot,
  pagamento: CreditCard,
  spedizione: Truck,
};

export const BetaActionNotice = ({
  tipo,
  className = "",
}: {
  tipo: AzioneEsternaBeta;
  className?: string;
}) => {
  const Icon = ICONE[tipo];

  return (
    <div
      role="status"
      data-testid={`beta-action-notice-${tipo}`}
      className={`flex items-start gap-2 rounded-xl border border-oro/40 bg-oro/10 p-3 text-sm text-antracite ${className}`}
    >
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-bordeaux" />
      <p>{MESSAGGI_AZIONI_BETA[tipo]}</p>
    </div>
  );
};
