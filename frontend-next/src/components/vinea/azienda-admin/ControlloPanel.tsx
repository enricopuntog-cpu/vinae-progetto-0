"use client";

// WI-016 — interruttore generale, sospensioni individuali e stato del controllo. Ogni valore arriva dal database;
// sospendere vale subito, togliere una sospensione richiede una conferma recente dell'identità e non accende nulla che
// il proprietario non abbia già acceso. Interruttori di dominio, tetti, tariffe e modelli si leggono soltanto.

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Campo, Esito, Letto, data, useLettura } from "@/components/vinea/catalogo-admin/comune";
import { bersagliSospendibili, type Bersaglio, type ServiziControllo, type StatoControllo } from "@/lib/azienda-admin/controllo";

const INTERRUTTORI: [string, string][] = [
  ["proposte_utenti", "Proposte degli utenti"],
  ["proposte_effettive", "Proposte effettive (accese e non sospese)"],
  ["acquisizione_annunci", "Acquisizione dagli annunci"],
  ["chiusura_automatica", "Chiusura automatica delle proposte note"],
  ["richieste_autenticita", "Richieste di verifica delle bottiglie"],
  ["valutazione_prezzi", "Valutazione prezzi nel pannello"],
  ["promozione", "Promozione del catalogo"],
  ["proiezione_pubblica", "Proiezione pubblica"],
];

export function ControlloPanel({ servizi }: { servizi: ServiziControllo }) {
  const { esito, ricarica } = useLettura(() => servizi.stato(), "controllo");
  const correlati = useLettura(() => servizi.correlati(), "correlati");
  const [motivo, setMotivo] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const [inCorso, setInCorso] = useState(false);

  const cambia = async (b: Bersaglio) => {
    setInCorso(true);
    setErrore(null);
    setMessaggio(null);
    const r = b.sospeso ? await servizi.ripristina(b.tipo, b.chiave, motivo) : await servizi.sospendi(b.tipo, b.chiave, motivo);
    setInCorso(false);
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    setMotivo("");
    setMessaggio(b.sospeso ? "Sospensione tolta." : "Sospeso.");
    ricarica();
  };

  return (
    <Letto esito={esito} ricarica={ricarica}>
      {(s: StatoControllo) => {
        const bersagli = bersagliSospendibili(s);
        const generale = bersagli[0]!;
        return (
          <div className="space-y-3 text-xs" data-testid="control-center">
            <section className="rounded-2xl border border-border bg-card p-3">
              <h2 className="text-sm font-semibold">Interruttore generale</h2>
              <p className="text-muted-foreground">
                Ferma AI, agenti, lavori che scrivono, proposte e acquisizione. La sorveglianza (Sentinel e fonti di
                monitoraggio) continua.
              </p>
              <Campo etichetta="Motivo (obbligatorio per sospendere o ripristinare)" valore={motivo} onCambio={setMotivo} massimo={500} />
              <Button
                type="button"
                size="sm"
                variant={generale.sospeso ? "outline" : "destructive"}
                className="mt-2"
                disabled={!motivo.trim() || inCorso}
                onClick={() => void cambia(generale)}
                data-testid="kill-switch"
              >
                {generale.sospeso ? "Togli la sospensione generale" : "Ferma tutto ciò che agisce"}
              </Button>
              <Esito errore={errore} messaggio={messaggio} />
              {s.sospensioni.length > 0 ? (
                <ul className="mt-2 list-disc pl-5" data-testid="sospensioni-attive">
                  {s.sospensioni.map((x) => (
                    <li key={`${x.tipo}:${x.chiave}`}>
                      {x.tipo} {x.chiave} dal {data(x.dal)}: {x.motivo}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="mt-2">Nessuna sospensione attiva.</p>
              )}
              <details className="mt-2">
                <summary className="cursor-pointer font-semibold">Sospendi singole funzioni ({bersagli.length - 1})</summary>
                <ul className="mt-1 space-y-1">
                  {bersagli.slice(1).map((b) => (
                    <li key={`${b.tipo}:${b.chiave}`} className="flex flex-wrap items-center justify-between gap-2">
                      <span>
                        {b.etichetta}
                        {b.sospeso ? " · SOSPESO" : ""}
                      </span>
                      <Button type="button" size="sm" variant="ghost" disabled={!motivo.trim() || inCorso} onClick={() => void cambia(b)}>
                        {b.sospeso ? "Ripristina" : "Sospendi"}
                      </Button>
                    </li>
                  ))}
                </ul>
              </details>
            </section>

            <section className="rounded-xl border border-border bg-card p-3" data-testid="ai-configurazione">
              <h2 className="text-sm font-semibold">Funzioni AI (configurazione del proprietario, sola lettura)</h2>
              <ul className="space-y-1">
                {s.funzioni_ai.map((f) => (
                  <li key={f.funzione}>
                    <b>{f.funzione}</b>
                    {f.sospesa ? " · SOSPESA" : ""} · tentativi {f.max_tentativi} · riserva {f.modello_riserva ?? "nessuna"} · input
                    fino a {f.max_input_caratteri} caratteri · in corso {f.in_corso}/{f.concorrenza_globale} · per utente{" "}
                    {f.concorrenza_utente} · account nuovi {f.quota_account_nuovo}/ora
                  </li>
                ))}
              </ul>
              <p className="mt-1">
                Segnali di sicurezza nelle 24 ore:{" "}
                {s.segnali_sicurezza_ai_24h.length
                  ? s.segnali_sicurezza_ai_24h.map((x) => `${x.tipo} ${x.conteggio}`).join(" · ")
                  : "nessuno registrato"}
              </p>
            </section>

            <section className="rounded-xl border border-border bg-card p-3">
              <h2 className="text-sm font-semibold">Interruttori (si accendono solo dal proprietario)</h2>
              <ul className="grid gap-1 sm:grid-cols-2">
                {INTERRUTTORI.map(([k, t]) => (
                  <li key={k}>
                    {t}: <b>{s.interruttori[k] === true ? "acceso" : s.interruttori[k] === false ? "spento" : "non letto"}</b>
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-border bg-card p-3" data-testid="qualita-catalogo">
              <h2 className="text-sm font-semibold">Qualità del catalogo e consenso</h2>
              <p>
                Proposte in attesa di registrazione {s.consenso.in_sospeso} · non registrate {s.consenso.esaurite} · in quarantena{" "}
                {s.consenso.quarantena}
              </p>
              {s.qualita.length === 0 ? (
                <p className="text-muted-foreground">Nessun rilievo di qualità nei dati letti.</p>
              ) : (
                <ul className="list-disc pl-5">
                  {s.qualita.map((q) => (
                    <li key={q.codice}>
                      {q.severita} · {q.codice}: {q.conteggio}
                    </li>
                  ))}
                </ul>
              )}
            </section>

            <section className="rounded-xl border border-border bg-card p-3">
              <h2 className="text-sm font-semibold">Esecutori</h2>
              {s.esecutori.length === 0 ? <p className="text-muted-foreground">Nessun agente registrato: nessun esecutore.</p> : null}
              <ul>
                {s.esecutori.map((a) => (
                  <li key={a.chiave}>
                    <b>{a.chiave}</b> · {a.acceso ? "acceso" : "spento"}
                    {a.sospeso ? " · sospeso" : ""} · ultima richiesta di lavoro {a.ultima_richiesta ? data(a.ultima_richiesta) : "mai"}
                  </li>
                ))}
              </ul>
            </section>

            <section className="rounded-xl border border-border bg-card p-3" data-testid="segnali-correlati">
              <h2 className="text-sm font-semibold">Escalation, peggioramenti e segnali nati insieme</h2>
              <Letto esito={correlati.esito} ricarica={correlati.ricarica}>
                {(c) =>
                  c.in_escalation.length + c.peggiorate.length + c.gruppi.length === 0 ? (
                    <p className="text-muted-foreground">Nulla nei dati letti. Non è una prova che tutto funzioni: vedi Sentinel.</p>
                  ) : (
                    <ul className="list-disc pl-5">
                      {c.in_escalation.map((a) => (
                        <li key={`e${a.codice}`}>
                          Non presa in carico: {a.severita} {a.codice} dal {data(a.dal)}
                        </li>
                      ))}
                      {c.peggiorate.map((a) => (
                        <li key={`p${a.codice}`}>
                          Peggiorata: {a.codice} da {a.all_apertura} a {a.ora}
                        </li>
                      ))}
                      {c.gruppi.map((g) => (
                        <li key={g.dal}>
                          Nate insieme dal {data(g.dal)}: {g.anomalie.join(", ")}
                        </li>
                      ))}
                    </ul>
                  )
                }
              </Letto>
            </section>
          </div>
        );
      }}
    </Letto>
  );
}
