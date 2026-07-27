import {
  CheckCircle2,
  Clock,
  XCircle,
  ShieldAlert,
  ShieldCheck,
  Mail,
  Cake,
  IdCard,
  Store,
} from "lucide-react";
import type { EmailStatus, AgeStatus, IdentityStatus, SellerStatus } from "@/data/onboarding";

type Tone = "ok" | "warn" | "err" | "muted";

const toneClass: Record<Tone, string> = {
  ok: "bg-salvia/15 text-salvia border-salvia/30",
  warn: "bg-oro/15 text-oro border-oro/30",
  err: "bg-bordeaux/10 text-bordeaux border-bordeaux/30",
  muted: "bg-secondary text-muted-foreground border-border",
};

export function VerificationBadge({
  tone,
  icon,
  label,
  size = "sm",
}: {
  tone: Tone;
  icon: React.ReactNode;
  label: string;
  size?: "sm" | "md";
}) {
  const pad = size === "md" ? "px-2.5 py-1 text-xs" : "px-2 py-0.5 text-[10px]";
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border ${pad} ${toneClass[tone]}`}
    >
      {icon} {label}
    </span>
  );
}

export function EmailBadge({ status }: { status: EmailStatus }) {
  return status === "verificata" ? (
    <VerificationBadge
      tone="ok"
      icon={<CheckCircle2 className="h-3 w-3" />}
      label="Email verificata"
    />
  ) : (
    <VerificationBadge
      tone="warn"
      icon={<Mail className="h-3 w-3" />}
      label="Email non verificata"
    />
  );
}

export function AgeBadge({ status }: { status: AgeStatus }) {
  if (status === "verificata")
    return (
      <VerificationBadge
        tone="ok"
        icon={<CheckCircle2 className="h-3 w-3" />}
        label="Età verificata"
      />
    );
  if (status === "dichiarata")
    return (
      <VerificationBadge tone="warn" icon={<Cake className="h-3 w-3" />} label="Età dichiarata" />
    );
  return (
    <VerificationBadge
      tone="err"
      icon={<ShieldAlert className="h-3 w-3" />}
      label="Età da verificare"
    />
  );
}

export function IdentityBadge({ status }: { status: IdentityStatus }) {
  const map: Record<IdentityStatus, { tone: Tone; label: string; icon: React.ReactNode }> = {
    non_avviata: {
      tone: "muted",
      label: "Identità non verificata",
      icon: <IdCard className="h-3 w-3" />,
    },
    in_verifica: {
      tone: "warn",
      label: "Identità in verifica",
      icon: <Clock className="h-3 w-3" />,
    },
    verificata: {
      tone: "ok",
      label: "Identità verificata",
      icon: <ShieldCheck className="h-3 w-3" />,
    },
    rifiutata: { tone: "err", label: "Identità rifiutata", icon: <XCircle className="h-3 w-3" /> },
  };
  const v = map[status];
  return <VerificationBadge tone={v.tone} icon={v.icon} label={v.label} />;
}

export function SellerBadge({ status }: { status: SellerStatus }) {
  return status === "abilitato" ? (
    <VerificationBadge tone="ok" icon={<Store className="h-3 w-3" />} label="Venditore abilitato" />
  ) : (
    <VerificationBadge
      tone="muted"
      icon={<Store className="h-3 w-3" />}
      label="Venditore non abilitato"
    />
  );
}
