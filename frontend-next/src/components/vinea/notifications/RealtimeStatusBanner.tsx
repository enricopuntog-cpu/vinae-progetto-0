import type { RealtimeState } from "@/services/types";

const labels: Partial<Record<RealtimeState, string>> = {
  connecting: "Connessione agli aggiornamenti in tempo reale…",
  reconnecting: "Riconnessione in corso: i dati canonici saranno riallineati.",
  error: "Aggiornamenti in tempo reale temporaneamente non disponibili.",
};

export const RealtimeStatusBanner = ({ state }: { state: RealtimeState }) => {
  const label = labels[state];
  return label ? (
    <p
      role={state === "error" ? "alert" : "status"}
      className="rounded-xl border border-oro/30 bg-oro/10 px-3 py-2 text-xs"
    >
      {label}
    </p>
  ) : null;
};
