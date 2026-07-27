import { ShieldCheck, User, Sparkles } from "lucide-react";
import { trustLabel, trustHint, type TrustSource } from "@/data/moderation";

const styles: Record<TrustSource, { cls: string; Icon: typeof ShieldCheck }> = {
  piattaforma: { cls: "bg-salvia/15 text-salvia border-salvia/30", Icon: ShieldCheck },
  venditore: { cls: "bg-secondary text-antracite border-border", Icon: User },
  ia: { cls: "bg-oro/15 text-antracite border-oro/40", Icon: Sparkles },
};

export function TrustBadge({ source, size = "md" }: { source: TrustSource; size?: "sm" | "md" }) {
  const { cls, Icon } = styles[source];
  const sz = size === "sm" ? "text-[10px] px-1.5 py-0.5" : "text-[11px] px-2 py-0.5";
  return (
    <span
      title={trustHint[source]}
      className={`inline-flex items-center gap-1 rounded-full border font-medium ${cls} ${sz}`}
    >
      <Icon className="h-3 w-3" />
      {trustLabel[source]}
    </span>
  );
}

export function TrustLegend() {
  return (
    <div className="rounded-2xl border border-border bg-card p-3 text-xs">
      <p className="mb-2 font-semibold">Come leggere i badge di fiducia</p>
      <ul className="space-y-1.5">
        {(["piattaforma", "venditore", "ia"] as TrustSource[]).map((s) => (
          <li key={s} className="flex flex-wrap items-center gap-2">
            <TrustBadge source={s} size="sm" />
            <span className="text-muted-foreground">{trustHint[s]}</span>
          </li>
        ))}
      </ul>
      <p className="mt-2 text-[11px] text-muted-foreground">
        Vinea non dichiara mai l'autenticità garantita di una bottiglia.
      </p>
    </div>
  );
}
