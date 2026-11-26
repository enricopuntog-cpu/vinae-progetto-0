"use client";

// WI-015 — sezioni operative del cruscotto: scheduler, agenti, fonti di monitoraggio, spesa AI e rapporto periodico.
// Ogni stato arriva dal database e viene mostrato com'è: un agente registrato non è «operativo», un giro lanciato a
// mano non è «pianificato», una fonte mai ricevuta è «non verificata». Nessuna azione parte da qui.

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Letto, data, useLettura } from "@/components/vinea/catalogo-admin/comune";
import {
  etichettaAgente,
  etichettaFonte,
  etichettaScheduler,
  serviziAziendaAdmin,
  type RiepilogoAzienda,
} from "@/lib/azienda-admin/azienda-admin";

const usd = (v: number | null) => (v === null ? "non impostato" : `${v.toLocaleString("it-IT", { maximumFractionDigits: 4 })} USD`);

export function SpesaAi({ spesa, tariffe }: { spesa: RiepilogoAzienda["ai"]["spesa"]; tariffe: number }) {
  return (
    <p className="text-xs" data-testid="spesa-ai">
      Spesa AI (stima, non fattura): oggi {usd(spesa.stimata_oggi_usd)} più {usd(spesa.riservata_aperta_oggi_usd)} prenotati,
      mese {usd(spesa.stimata_mese_usd)} · fatturato noto: {spesa.effettiva_mese_usd === null ? "nessuno" : usd(spesa.effettiva_mese_usd)} ·
      tetti: giorno {usd(spesa.limite_giorno_usd)}, mese {usd(spesa.limite_mese_usd)} · tariffe registrate: {tariffe}
      {spesa.chiamate_senza_tariffa_mese > 0 ? ` · chiamate senza tariffa: ${spesa.chiamate_senza_tariffa_mese}` : ""}
    </p>
  );
}

export function OperazioniPanel({
  scheduler,
  agenti,
  fonti,
}: {
  scheduler: RiepilogoAzienda["scheduler"];
  agenti: RiepilogoAzienda["agenti"]["elenco"];
  fonti: RiepilogoAzienda["fonti"];
}) {
  return (
    <div className="space-y-3 text-xs">
      <section className="rounded-xl border border-border bg-card p-3" data-testid="scheduler">
        <h2 className="text-sm font-semibold">Scheduler</h2>
        <p>
          {etichettaScheduler(scheduler)}
          {scheduler.ultimo_giro ? ` · ultimo giro ${data(scheduler.ultimo_giro)} (${scheduler.ultimo_giro_da})` : " · mai eseguito"}
        </p>
        <ul className="mt-1 space-y-1">
          {scheduler.lavori.map((j) => (
            <li key={j.chiave}>
              <b>{j.descrizione}</b> · {j.acceso ? "acceso" : "spento"} · ogni {j.intervallo_minuti} min
              {j.ultimo ? ` · ultimo ${data(j.ultimo)} (${j.esito ?? "non verificato"}${j.errore ? ` ${j.errore}` : ""})` : " · mai eseguito"}
              {j.prossimo ? ` · prossimo non prima di ${data(j.prossimo)}` : ""}
              {j.esito === "sospeso" ? " · SOSPESO dopo guasti ripetuti" : ""}
            </li>
          ))}
        </ul>
      </section>
      <section className="rounded-xl border border-border bg-card p-3" data-testid="agenti">
        <h2 className="text-sm font-semibold">Agenti</h2>
        {agenti.length === 0 ? <p className="text-muted-foreground">Nessun agente registrato.</p> : null}
        <ul className="space-y-1">
          {agenti.map((a) => (
            <li key={a.chiave}>
              <b>{a.chiave}</b> · {etichettaAgente(a.stato)} · task in corso {a.task_in_corso}
              {a.ultima_presa ? ` · ultima presa ${data(a.ultima_presa)}` : ""}
            </li>
          ))}
        </ul>
      </section>
      <section className="rounded-xl border border-border bg-card p-3" data-testid="fonti-monitor">
        <h2 className="text-sm font-semibold">Monitoraggio e backup</h2>
        <ul className="space-y-1">
          {fonti.map((f) => (
            <li key={f.chiave}>
              <b>{f.descrizione}</b> · {etichettaFonte(f.stato)}
              {f.ultimo ? ` · ultimo segnale ${data(f.ultimo)}` : ""}
              {f.riferimento?.startsWith("https://github.com/") ? (
                <>
                  {" · "}
                  <a className="underline" href={f.riferimento} target="_blank" rel="noreferrer noopener">
                    prova
                  </a>
                </>
              ) : null}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

export function Rapporto({ servizi }: { servizi: ReturnType<typeof serviziAziendaAdmin> }) {
  const [giorni, setGiorni] = useState(7);
  const { esito, ricarica } = useLettura(() => servizi.rapporto(giorni), String(giorni));
  return (
    <section className="space-y-2 text-sm" data-testid="rapporto">
      <h2 className="font-semibold">Rapporto periodico</h2>
      <div className="flex gap-2">
        {[1, 7, 30].map((g) => (
          <Button key={g} type="button" size="sm" variant={g === giorni ? "default" : "outline"} onClick={() => setGiorni(g)}>
            {g === 1 ? "24 ore" : `${g} giorni`}
          </Button>
        ))}
      </div>
      <Letto esito={esito} ricarica={ricarica}>
        {(r) => (
          <div className="space-y-1 text-xs">
            <p>
              Nel periodo: {r.nel_periodo.aperte} anomalie nuove, {r.nel_periodo.risolte} risolte, {r.nel_periodo.decisioni} decisioni,{" "}
              {r.nel_periodo.chiusure_per_regola} chiusure per regola, {r.nel_periodo.esecuzioni_sentinel} esecuzioni di Sentinel,{" "}
              {r.segnali.totali} segnali ({r.segnali.guasti} guasti, {r.segnali.degradati} degradati), {r.ai_richieste} richieste AI.
            </p>
            <ul className="list-disc pl-5">
              {r.anomalie_aperte.length === 0 ? <li>Nessuna anomalia aperta.</li> : null}
              {r.anomalie_aperte.map((a) => (
                <li key={`${a.severita}-${a.categoria}`}>
                  {a.severita} · {a.categoria}: {a.conteggio} ({a.codici.join(", ")})
                </li>
              ))}
            </ul>
            {r.lavori_con_problemi.length > 0 ? (
              <p>Lavori con problemi: {r.lavori_con_problemi.map((l) => `${l.chiave} (${l.esito})`).join(", ")}</p>
            ) : null}
          </div>
        )}
      </Letto>
    </section>
  );
}
