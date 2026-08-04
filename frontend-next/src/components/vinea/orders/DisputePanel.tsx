"use client";

import type { DisputeRecord, DisputeStato } from "@/services/types";

const ETICHETTE: Record<DisputeStato, string> = {
  aperta: "Aperta",
  in_valutazione: "In valutazione",
  rimborsata: "Rimborsata",
  risolta: "Risolta",
  respinta: "Respinta",
};

/**
 * Il fascicolo della contestazione, **in sola lettura per entrambe le parti**.
 *
 * È la divergenza dichiarata più visibile rispetto a `frontend/`, dove il
 * pannello mostrava a compratore e venditore tre bottoni — «Rimborsa»,
 * «Risolta con accordo», «Respingi» — sotto la scritta «Azioni demo». Quella
 * era impalcatura: portarla alla lettera lascerebbe a una parte in causa il
 * potere di chiudere la propria controversia, e a un venditore quello di
 * respingere la contestazione che blocca i suoi stessi fondi.
 *
 * `ordine_contestazione_risolvi` non ha alcun `GRANT` verso `authenticated`:
 * non è che il bottone sia nascosto, è che la chiamata non passerebbe.
 * L'interfaccia di gestione appartiene alla Fase 9.
 */
export function DisputePanel({ contestazione }: { contestazione: DisputeRecord }) {
  const chiusa = contestazione.chiusura_at !== null;

  return (
    <section className="rounded-2xl border border-red-500/30 bg-red-500/5 p-4">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold text-red-700">
          Contestazione · {ETICHETTE[contestazione.stato]}
        </p>
        <span className="rounded-full bg-red-500/10 px-2 py-0.5 text-[10px] font-medium text-red-700">
          {new Date(contestazione.apertura_at).toLocaleDateString("it-IT")}
        </span>
      </div>

      <p className="mt-2 text-sm">
        <b>Motivo:</b> {contestazione.motivo}
      </p>
      <p className="mt-1 text-sm text-antracite/80">{contestazione.descrizione}</p>

      {contestazione.esito_nota && (
        <p className="mt-3 text-xs text-muted-foreground">Esito: {contestazione.esito_nota}</p>
      )}

      <p className="mt-4 border-t border-red-500/20 pt-3 text-xs text-muted-foreground">
        {contestazione.stato === "rimborsata"
          ? "Rimborso disposto. L'ordine resta contestato finché il rimborso non è confermato dal fornitore di pagamento."
          : chiusa
            ? "Pratica chiusa."
            : "La pratica è in carico all'assistenza Vinea. Né il compratore né il venditore possono chiuderla."}
      </p>
    </section>
  );
}
