"use client";

// WI-016 — Marketplace Monitor (sole revisioni: nessuna sospensione, rimozione, rimborso o pagamento parte da qui),
// richieste di verifica delle bottiglie (nessun esito di autenticità) e anteprima della valutazione economica.

import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Campo, Esito, Letto, data, testoValore, useLettura } from "@/components/vinea/catalogo-admin/comune";
import {
  SOGLIE_MERCATO,
  etichettaRevisione,
  soglieDaCampi,
  valutaVinoDaPorta,
  type EsitoValutazione,
  type ServiziControllo,
} from "@/lib/azienda-admin/controllo";
import { ETICHETTE_SEGNALE, type SegnaleAutenticita } from "@/lib/autenticita/analisi";

export function MercatoPanel({ servizi }: { servizi: ServiziControllo }) {
  const [aperte, setAperte] = useState(true);
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => servizi.mercato(aperte, 1), String(aperte));
  const stato = useLettura(() => servizi.stato(), "soglie");

  const scansiona = async () => {
    setErrore(null);
    const r = await servizi.scansionaMercato();
    if (!r.ok) setErrore(r.error);
    else {
      setMessaggio(
        r.data.esito === "completato"
          ? `Controlli eseguiti: ${r.data.rilievi ?? 0} rilievi, ${r.data.nuove_revisioni ?? 0} nuove revisioni.`
          : `Scansione ${r.data.esito}: ${r.data.non_eseguiti ?? 0} controlli non eseguiti.`,
      );
      ricarica();
    }
  };
  const decidi = async (id: number, azione: "prendi_in_carico" | "chiudi_senza_azione" | "chiudi_segnalata") => {
    setErrore(null);
    const r = await servizi.decidiRevisione(id, azione, nota);
    if (!r.ok) setErrore(r.error);
    else {
      setNota("");
      ricarica();
    }
  };

  return (
    <section className="space-y-3 text-xs" data-testid="mercato-monitor">
      <p className="text-muted-foreground">
        Ogni riga è una richiesta di revisione, non un&apos;accusa: da qui non si sospende nessuno, non si tolgono annunci e
        non si muove denaro. La soglia di vendita non è una classificazione fiscale.
      </p>
      <div className="flex flex-wrap gap-2">
        <Button type="button" size="sm" onClick={() => void scansiona()}>
          Esegui i controlli ora
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={() => setAperte(!aperte)}>
          {aperte ? "Mostra chiuse" : "Mostra aperte"}
        </Button>
      </div>
      <Campo etichetta="Motivo della decisione" valore={nota} onCambio={setNota} massimo={500} />
      <Esito errore={errore} messaggio={messaggio} />
      <Letto esito={esito} ricarica={ricarica}>
        {(righe) => (
          <ul className="space-y-2">
            {righe.length === 0 ? <li className="text-muted-foreground">Nessuna revisione in questo elenco.</li> : null}
            {righe.map((m) => (
              <li key={m.id} className="rounded-xl border border-border bg-card p-3">
                <p className="font-semibold">{etichettaRevisione(m.tipo)}</p>
                <p className="text-muted-foreground">
                  {m.stato}
                  {m.utente ? ` · utente ${m.utente}` : ""} · dal {data(m.prima)} · ultima volta {data(m.ultima)}
                </p>
                <p>Evidenza: {testoValore(m.evidenza)}</p>
                {m.annunci.length ? (
                  <p>
                    Annunci:{" "}
                    {m.annunci.map((slug) => (
                      <Link key={slug} href={`/annuncio/${slug}`} className="mr-2 underline">
                        {slug}
                      </Link>
                    ))}
                  </p>
                ) : null}
                {m.nota ? <p className="text-muted-foreground">Nota: {m.nota}</p> : null}
                {aperte ? (
                  <div className="mt-1 flex flex-wrap gap-2">
                    {m.stato === "aperta" ? (
                      <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi(m.id, "prendi_in_carico")}>
                        Prendi in carico
                      </Button>
                    ) : null}
                    <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi(m.id, "chiudi_senza_azione")}>
                      Chiudi: nessuna azione
                    </Button>
                    <Button type="button" size="sm" variant="ghost" disabled={!nota.trim()} onClick={() => void decidi(m.id, "chiudi_segnalata")}>
                      Chiudi: segnalata
                    </Button>
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </Letto>
      <Letto esito={stato.esito} ricarica={stato.ricarica}>
        {(s) => <Soglie servizi={servizi} attuali={s.mercato.soglie} dopo={stato.ricarica} />}
      </Letto>
    </section>
  );
}

function Soglie({
  servizi,
  attuali,
  dopo,
}: {
  servizi: ServiziControllo;
  attuali: Record<string, number | string | null>;
  dopo: () => void;
}) {
  const [campi, setCampi] = useState<Record<string, string>>(() =>
    Object.fromEntries(SOGLIE_MERCATO.map(([k]) => [k, attuali[k] === null || attuali[k] === undefined ? "" : String(attuali[k])])),
  );
  const [errore, setErrore] = useState<string | null>(null);
  const [messaggio, setMessaggio] = useState<string | null>(null);
  const salva = async () => {
    setErrore(null);
    setMessaggio(null);
    const preparate = soglieDaCampi(campi);
    if (!preparate.ok) {
      setErrore(preparate.error);
      return;
    }
    const r = await servizi.salvaSoglie(preparate.data);
    if (!r.ok) setErrore(r.error);
    else {
      setMessaggio("Soglie salvate.");
      dopo();
    }
  };
  return (
    <details className="rounded-xl border border-border bg-card p-3">
      <summary className="cursor-pointer font-semibold">Soglie di revisione</summary>
      <div className="mt-2 grid gap-2 sm:grid-cols-2">
        {SOGLIE_MERCATO.map(([k, t]) => (
          <Campo key={k} etichetta={t} valore={campi[k] ?? ""} numerico massimo={14} onCambio={(v) => setCampi((p) => ({ ...p, [k]: v }))} />
        ))}
      </div>
      <Button type="button" size="sm" className="mt-2" onClick={() => void salva()}>
        Salva le soglie
      </Button>
      <Esito errore={errore} messaggio={messaggio} />
    </details>
  );
}

export function VerifichePanel({ servizi }: { servizi: ServiziControllo }) {
  const [nota, setNota] = useState("");
  const [errore, setErrore] = useState<string | null>(null);
  const { esito, ricarica } = useLettura(() => servizi.autenticita(1), "autenticita");
  const decidi = async (id: string, azione: "avvia_verifica" | "richiedi_documenti" | "chiudi") => {
    setErrore(null);
    const r = await servizi.decidiAutenticita(id, azione, nota);
    if (!r.ok) setErrore(r.error);
    else {
      setNota("");
      ricarica();
    }
  };
  return (
    <section className="space-y-2 text-xs" data-testid="verifiche-bottiglie">
      <h2 className="text-sm font-semibold">Richieste di verifica delle bottiglie</h2>
      <p className="text-muted-foreground">
        Si registrano solo passi di verifica. Non esiste, e non si dichiara, un esito di autenticità.
      </p>
      <Campo etichetta="Motivo o passo richiesto" valore={nota} onCambio={setNota} massimo={500} />
      <Esito errore={errore} />
      <Letto esito={esito} ricarica={ricarica}>
        {(righe) => (
          <ul className="space-y-2">
            {righe.length === 0 ? <li className="text-muted-foreground">Nessuna richiesta.</li> : null}
            {righe.map((r) => (
              <li key={r.id} className="rounded-xl border border-border bg-card p-3">
                <p className="font-semibold">
                  {r.produttore} — {r.nome} {r.annata ?? ""}
                </p>
                <p>{r.anomalie.map((a) => ETICHETTE_SEGNALE[a as SegnaleAutenticita] ?? a).join(" · ")}</p>
                <p className="text-muted-foreground">
                  {r.stato} · dal {data(r.creata)}
                  {r.nota ? ` · ${r.nota}` : ""}
                </p>
                {r.stato !== "chiusa" ? (
                  <div className="mt-1 flex flex-wrap gap-2">
                    {r.stato !== "in_verifica" ? (
                      <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi(r.id, "avvia_verifica")}>
                        Avvia verifica
                      </Button>
                    ) : null}
                    {r.stato !== "documenti_richiesti" ? (
                      <Button type="button" size="sm" variant="outline" disabled={!nota.trim()} onClick={() => void decidi(r.id, "richiedi_documenti")}>
                        Richiedi documenti
                      </Button>
                    ) : null}
                    <Button type="button" size="sm" variant="ghost" disabled={!nota.trim()} onClick={() => void decidi(r.id, "chiudi")}>
                      Chiudi
                    </Button>
                  </div>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </Letto>
    </section>
  );
}

const euro = (cents: number) => (cents / 100).toLocaleString("it-IT", { style: "currency", currency: "EUR" });

export function ValutazionePanel({ servizi }: { servizi: ServiziControllo }) {
  const [slug, setSlug] = useState("");
  const [esito, setEsito] = useState<EsitoValutazione | null>(null);
  const [errore, setErrore] = useState<string | null>(null);
  const valuta = async () => {
    setErrore(null);
    setEsito(null);
    const r = await servizi.prezzi(slug.trim());
    if (!r.ok) {
      setErrore(r.error);
      return;
    }
    setEsito(await valutaVinoDaPorta(r.data, new Date()));
  };
  return (
    <section className="space-y-2 text-xs" data-testid="valutazione-prezzi">
      <h2 className="text-sm font-semibold">Valutazione economica (anteprima interna)</h2>
      <p className="text-muted-foreground">
        Solo transazioni concluse comparabili producono una stima; i prezzi richiesti non entrano mai nella stima.
      </p>
      <Campo etichetta="Identificativo del vino (slug)" valore={slug} onCambio={setSlug} massimo={200} />
      <Button type="button" size="sm" disabled={!slug.trim()} onClick={() => void valuta()}>
        Valuta
      </Button>
      <Esito errore={errore} />
      {esito?.stato === "spenta" ? <p role="status">La valutazione nel pannello è spenta (decisione del proprietario).</p> : null}
      {esito?.stato === "valutata" ? (
        <div role="status" className="rounded-xl border border-border bg-card p-3">
          <p>
            Prezzi osservati: {esito.realizzati} concluse, {esito.richiesti} richiesti
            {esito.scartate ? `, ${esito.scartate} righe scartate` : ""}.
          </p>
          {esito.valutazione.esito === "stima" ? (
            <p>
              Mediana {euro(esito.valutazione.medianaCents)} (metà dei prezzi fra {euro(esito.valutazione.quartileBassoCents)} e{" "}
              {euro(esito.valutazione.quartileAltoCents)}) · {esito.valutazione.comparabili} comparabili · incertezza{" "}
              {esito.valutazione.incertezza} · fonti {esito.valutazione.fonti.join(", ")} · dal {data(esito.valutazione.periodo.dal)} al{" "}
              {data(esito.valutazione.periodo.al)}
            </p>
          ) : (
            <p>Dati insufficienti. {esito.valutazione.spiegazione}</p>
          )}
        </div>
      ) : null}
    </section>
  );
}
