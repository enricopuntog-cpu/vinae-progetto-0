"use client";

// WI-013 — primo cruscotto del Company Brain: stato di Sentinel, anomalie, task da approvare, catalogo, consumi AI e
// sorgenti non ancora collegate. Ogni numero viene dal database; le decisioni registrano un giudizio e non eseguono
// azioni su account, pagamenti, ordini o catalogo.

import Link from "next/link";
import { useMemo, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ErrorState } from "@/components/vinea/States";
import { Campo, Esito, Letto, data, testoValore, useLettura } from "@/components/vinea/catalogo-admin/comune";
import { OperazioniPanel, Rapporto, SpesaAi } from "@/components/vinea/azienda-admin/OperazioniPanel";
import { etichettaSentinel, serviziAziendaAdmin, type RiepilogoAzienda } from "@/lib/azienda-admin/azienda-admin";
import { getSupabaseClient } from "@/lib/supabase/client";

type Servizi = ReturnType<typeof serviziAziendaAdmin>;

export function AziendaAdminClient() {
  const client = useMemo(() => getSupabaseClient(), []);
  const servizi = useMemo(() => (client ? serviziAziendaAdmin(client) : null), [client]);
  const [giro, setGiro] = useState(0);
  if (!servizi) return <ErrorState message="Il cruscotto non è configurato in questo ambiente." />;
  return (
    <div className="mx-auto max-w-5xl space-y-4 p-4" data-testid="azienda-admin">
      <Link href="/admin" className="inline-flex items-center gap-1 text-sm text-antracite/70 hover:text-bordeaux">
        <ArrowLeft className="h-4 w-4" /> Operazioni Admin
      </Link>
      <h1 className="font-serif text-2xl">Cruscotto Vinea</h1>
      <Riepilogo key={`r${giro}`} servizi={servizi} dopoSentinel={() => setGiro((g) => g + 1)} />
      <Anomalie key={`a${giro}`} servizi={servizi} />
      <Rapporto key={`p${giro}`} servizi={servizi} />
      <Task key={`t${giro}`} servizi={servizi} />
    </div>
  );
}

function Riepilogo({ servizi, dopoSentinel }: { servizi: Servizi; dopoSentinel: () => void }) {
  const { esito, ricarica } = useLettura(() => servizi.riepilogo(), "riepilogo");
  const [errore, setErrore] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);
  const esegui = async () => {
    setInCorso(true);
    setErrore(null);
    const r = await servizi.eseguiSentinel();
    setInCorso(false);
    if (r.ok) dopoSentinel();
    else setErrore(r.error);
  };
  return (
    <Letto esito={esito} ricarica={ricarica}>
      {(r: RiepilogoAzienda) => (
        <section className="space-y-3 text-sm">
          <div className="rounded-2xl border border-border bg-card p-3">
            <h2 className="font-semibold">Sentinel</h2>
            <p data-testid="sentinel-stato">{etichettaSentinel(r.sentinel)}</p>
            {r.sentinel.ultima_esecuzione ? (
              <p className="text-xs text-muted-foreground">
                Ultima: {data(r.sentinel.ultima_esecuzione.conclusa)} · {r.sentinel.ultima_esecuzione.controlli} controlli ·{" "}
                {r.sentinel.ultima_esecuzione.non_eseguiti} non eseguiti · {r.sentinel.ultima_esecuzione.problemi} problemi
              </p>
            ) : null}
            <Button type="button" size="sm" className="mt-2" disabled={inCorso} onClick={() => void esegui()}>
              {inCorso ? "Controllo in corso…" : "Esegui i controlli ora"}
            </Button>
            <Esito errore={errore} />
          </div>
          <dl className="grid gap-2 sm:grid-cols-4">
            {(
              [
                ["Anomalie aperte", r.anomalie.aperte],
                ["di cui P0/P1", r.anomalie.p0 + r.anomalie.p1],
                ["Task da approvare", r.task.da_approvare],
                ["Task in coda", r.task.in_attesa],
                ["Proposte al catalogo", r.catalogo.proposte.aperte],
                ["Vini canonici attivi", r.catalogo.vini.attivi],
                ["Identità native", r.catalogo.vini.nativi],
                ["Agenti operativi", r.agenti.operativi],
                ["Task approvati da eseguire", r.task.approvati],
                ["Task bloccati", r.task.bloccati],
                ["Evidenze", r.evidenze],
                ["Proposte senza task", r.coda_catalogo.proposte_senza_task],
              ] as [string, number][]
            ).map(([k, v]) => (
              <div key={k} className="rounded-xl border border-border bg-card p-3">
                <dt className="text-xs text-muted-foreground">{k}</dt>
                <dd className="text-lg font-semibold">{v.toLocaleString("it-IT")}</dd>
              </div>
            ))}
          </dl>
          <p className="text-xs">
            AI:{" "}
            {r.ai.configurato
              ? `${r.ai.oggi.consentite}/${r.ai.richieste_giorno} richieste oggi, ${r.ai.mese.consentite}/${r.ai.richieste_mese} nel mese`
              : "budget non configurato, quindi nessuna chiamata al fornitore"}
            {` · rifiuti di oggi: ${r.ai.oggi.rifiutate_budget} · guasti del fornitore: ${r.ai.oggi.guasti_fornitore}.`}
          </p>
          <SpesaAi spesa={r.ai.spesa} tariffe={r.ai.tariffe_registrate} />
          <OperazioniPanel scheduler={r.scheduler} agenti={r.agenti.elenco} fonti={r.fonti} />
          <p className="text-xs">
            <Link href="/admin/catalogo" className="underline">
              Apri la gestione del catalogo
            </Link>
          </p>
          <div className="rounded-xl border border-dashed border-border p-3 text-xs text-muted-foreground" data-testid="sorgenti-non-collegate">
            <p className="font-semibold">Non ancora collegate o mai verificate</p>
            <ul className="list-disc pl-5">
              {r.sorgenti_non_collegate.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
          </div>
        </section>
      )}
    </Letto>
  );
}

function Anomalie({ servizi }: { servizi: Servizi }) {
  const [aperte, setAperte] = useState(true);
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => servizi.anomalie(aperte, 1), String(aperte));
  const aggiorna = async (id: number, azione: "prendi_in_carico" | "ignora" | "riapri" | "risolvi") => {
    setErrore(null);
    const r = await servizi.aggiornaAnomalia(id, azione, nota);
    if (r.ok) {
      setNota("");
      ricarica();
    } else setErrore(r.error);
  };
  return (
    <section className="space-y-2 text-sm">
      <h2 className="font-semibold">Anomalie</h2>
      <Button type="button" size="sm" variant="outline" onClick={() => setAperte(!aperte)}>
        {aperte ? "Mostra chiuse e ignorate" : "Mostra aperte"}
      </Button>
      <Campo etichetta="Motivo (richiesto per risolvere o ignorare)" valore={nota} onCambio={setNota} massimo={500} />
      <p className="text-xs text-muted-foreground">
        «Ignora» è sempre temporaneo (di base il massimo: P0 24 ore, P1 7 giorni, P2/P3 90 giorni) e l&apos;anomalia torna
        visibile alla scadenza o se si aggrava.
      </p>
      <Esito errore={errore} />
      <Letto esito={esito} ricarica={ricarica}>
        {(righe) => (
          <ul className="space-y-2">
            {righe.length === 0 ? <li className="text-xs text-muted-foreground">Nessuna anomalia in questo elenco.</li> : null}
            {righe.map((a) => (
              <li key={a.id} className="rounded-xl border border-border bg-card p-3">
                <p className="font-semibold">
                  {a.severita} · {a.titolo}
                </p>
                <p className="text-xs text-muted-foreground">
                  {a.categoria} · {a.fonte} · {a.stato} · vista {a.ricorrenze} volte dal {data(a.prima)} al {data(a.ultima)}
                </p>
                <p className="text-xs">Evidenza: {testoValore(a.evidenza)}</p>
                <p className="text-xs">Azione proposta: {a.azione_proposta}</p>
                <p className="text-xs text-muted-foreground">
                  Responsabile: {a.responsabile ?? "non assegnato"}
                  {a.richiede_approvazione ? " · richiede approvazione" : ""}
                  {a.nota ? ` · ${a.nota}` : ""}
                  {a.ignorata_fino_al ? ` · ignorata fino al ${data(a.ignorata_fino_al)}` : ""}
                </p>
                <div className="mt-1 flex flex-wrap gap-2">
                  {aperte ? (
                    <>
                      {a.stato === "aperta" ? (
                        <Button type="button" size="sm" variant="outline" onClick={() => void aggiorna(a.id, "prendi_in_carico")}>
                          Prendi in carico
                        </Button>
                      ) : null}
                      <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void aggiorna(a.id, "risolvi")}>
                        Risolvi
                      </Button>
                      <Button type="button" size="sm" variant="ghost" disabled={!nota.trim()} onClick={() => void aggiorna(a.id, "ignora")}>
                        Ignora
                      </Button>
                    </>
                  ) : (
                    <Button type="button" size="sm" variant="outline" onClick={() => void aggiorna(a.id, "riapri")}>
                      Riapri
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Letto>
    </section>
  );
}

function Task({ servizi }: { servizi: Servizi }) {
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => servizi.task(1), "task");
  const decidi = async (id: string, decisione: "approva" | "respingi" | "annulla" | "conferma_eseguito") => {
    setErrore(null);
    const r = await servizi.decidiTask(id, decisione, nota);
    if (r.ok) {
      setNota("");
      ricarica();
    } else setErrore(r.error);
  };
  return (
    <section className="space-y-2 text-sm">
      <h2 className="font-semibold">Task e approvazioni</h2>
      <p className="text-xs text-muted-foreground">
        La decisione registra il tuo giudizio: non esegue modifiche su account, pagamenti, ordini o catalogo. Approvare
        non significa eseguito: l&apos;esecuzione si fa dagli strumenti del suo dominio e poi si conferma qui.
      </p>
      <Campo etichetta="Motivo della decisione" valore={nota} onCambio={setNota} massimo={500} />
      <Esito errore={errore} />
      <Letto esito={esito} ricarica={ricarica}>
        {(righe) => (
          <ul className="space-y-2">
            {righe.length === 0 ? <li className="text-xs text-muted-foreground">Nessun task aperto.</li> : null}
            {righe.map((t) => (
              <li key={t.id} className="rounded-xl border border-border bg-card p-3">
                <p className="font-semibold">{t.titolo}</p>
                <p className="text-xs text-muted-foreground">
                  {t.tipo} · P{t.priorita} · {t.stato} · tentativi {t.tentativi} · evidenze {t.evidenze}
                  {t.agente ? ` · agente ${t.agente}` : ""} · {data(t.creato)}
                </p>
                {t.proposta ? <p className="text-xs">Proposta: {testoValore(t.proposta)}</p> : null}
                <div className="mt-1 flex gap-2">
                  {t.stato === "in_approvazione" ? (
                    <>
                      <Button type="button" size="sm" disabled={!nota.trim()} onClick={() => void decidi(t.id, "approva")}>
                        Approva
                      </Button>
                      <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi(t.id, "respingi")}>
                        Respingi
                      </Button>
                    </>
                  ) : null}
                  {t.stato === "approvato" ? (
                    <Button type="button" size="sm" disabled={!nota.trim()} onClick={() => void decidi(t.id, "conferma_eseguito")}>
                      Conferma eseguito
                    </Button>
                  ) : null}
                  {t.stato !== "assegnato" ? (
                    <Button type="button" size="sm" variant="ghost" disabled={!nota.trim()} onClick={() => void decidi(t.id, "annulla")}>
                      Annulla
                    </Button>
                  ) : null}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Letto>
    </section>
  );
}
